// android/app/src/main/cpp/UsbAudioSink.cpp
#include "UsbAudioSink.h"
#include "AudioDspEngine.h"
#include "DsdNativePacker.h"
#include "SinkQuantizer.h"
#include "Uac2Descriptors.h"
#include "UsbPcmProducer.h"

#if defined(__ANDROID__)
#include <android/log.h>
#define PULSR_USB_LOG(prio, ...) \
    __android_log_print(prio, "PulsrUsbSink", __VA_ARGS__)
#else
#define PULSR_USB_LOG(prio, ...) ((void)0)
#endif

#if defined(__linux__) || defined(__ANDROID__)
#include <linux/usbdevice_fs.h>
#include <poll.h>
#include <sys/ioctl.h>
#include <sys/resource.h>
#include <unistd.h>
#else
// Non-Linux mock definitions for host compilation and tests
struct usbdevfs_urb {
    unsigned char type;
    unsigned char endpoint;
    int status;
    unsigned int flags;
    void* buffer;
    int buffer_length;
    int actual_length;
    int start_frame;
    int number_of_packets;
    int error_count;
    unsigned int signr;
    void* usercontext;
    struct usbdevfs_iso_packet_desc {
        unsigned int length;
        unsigned int actual_length;
        unsigned int status;
    } iso_frame_desc[1];
};
struct usbdevfs_setinterface {
    unsigned int interface;
    unsigned int altsetting;
};
struct usbdevfs_ctrltransfer {
    uint8_t bRequestType;
    uint8_t bRequest;
    uint16_t wValue;
    uint16_t wIndex;
    uint16_t wLength;
    uint32_t timeout;
    void* data;
};
#define USBDEVFS_URB_TYPE_ISO 0
#define USBDEVFS_URB_ISO_ASAP 2
#define USBDEVFS_CLAIMINTERFACE 0
#define USBDEVFS_RELEASEINTERFACE 0
#define USBDEVFS_SETINTERFACE 0
#define USBDEVFS_SUBMITURB 0
#define USBDEVFS_DISCARDURB 0
#define USBDEVFS_REAPURBNDELAY 0
#define USBDEVFS_CONTROL 0
inline int ioctl(int, unsigned long, ...) { return -1; }
#endif

#include <algorithm>
#include <cerrno>
#include <chrono>
#include <cmath>
#include <cstring>
#include <limits>
#include <new>

// Abandon() and the destructor deliberately leak the URB header storage and
// packet payloads the kernel may still be writing to. Those allocations are
// permanent by design, so tell LeakSanitizer about them instead of disabling
// leak detection for the whole suite. Only sanitizer runtimes that publish
// __lsan_ignore_object are annotated; every other build expands to a no-op.
#if defined(__has_feature)
#if __has_feature(address_sanitizer)
#define PULSR_HAS_ADDRESS_SANITIZER 1
#endif
#endif
#if defined(__SANITIZE_ADDRESS__)
#define PULSR_HAS_ADDRESS_SANITIZER 1
#endif
#if (defined(__linux__) || defined(__ANDROID__)) && defined(PULSR_HAS_ADDRESS_SANITIZER)
extern "C" void __lsan_ignore_object(const void* p);
#define PULSR_LSAN_IGNORE_OBJECT(ptr) __lsan_ignore_object(static_cast<const void*>(ptr))
#else
#define PULSR_LSAN_IGNORE_OBJECT(ptr) ((void)(ptr))
#endif

namespace pulsr {

namespace {
constexpr int kNumUrbs = 8;
constexpr int kTargetUrbDurationUs = 8000;
// Upper bound for a tuned pull-renderer reservoir (SetStreamTuning).
constexpr int kMaxTunedBufferMs = 10000;

// True for the two modes that stream through UsbPullRenderer's reservoir.
// Everything else - BestEffort and the native-DSD ring path - is served from
// ring_ and must keep the ring read pointer / prefill / steering logic live.
constexpr bool IsReservoirMode(int mode) {
    return mode == static_cast<int>(UsbRenderMode::BitPerfectPull) ||
           mode == static_cast<int>(UsbRenderMode::ClockSyncAsrc);
}
constexpr bool IsDsdMode(int mode) {
    return mode == static_cast<int>(UsbRenderMode::DsdNative);
}
} // namespace

UsbAudioSink& UsbAudioSink::instance() {
    // Construct registry first so control teardown can clear its broadcast
    // safely during sink static destruction, even after worker self-exit.
    static auto& registry = DspEngineRegistry::instance();
    (void)registry;
    static UsbAudioSink sink;
    return sink;
}

UsbAudioSink::~UsbAudioSink() {
    // A joinable worker must always be reaped; otherwise ~thread terminates.
    if (worker_.joinable()) {
        running_.store(false, std::memory_order_release);
        active_.store(false, std::memory_order_release);
        worker_.join();
    }
    // Close() publishes to AudioDspEngine/DspEngineRegistry. At static
    // destruction those singletons may already be gone, so only run the full
    // teardown when this sink still owns a stream, a claim or a publication.
    if (active_.load(std::memory_order_acquire) ||
        exclusive_.load(std::memory_order_acquire) || sinkDepthPublished_ ||
        hasOutstandingUrbs()) {
        Close();
    }
    if (hasOutstandingUrbs()) {
        // A fatal reap error is not proof of returned kernel ownership. Keep
        // header allocations and payloads alive even at static destruction.
        // Payload pointers deliberately leak; moving storage preserves addresses.
        // The allocation is bound to a local first: the annotation macro is a
        // no-op outside sanitizer builds and must never swallow the new.
        auto* leakedOut = new std::vector<uint8_t>(std::move(urbStorage_));
        PULSR_LSAN_IGNORE_OBJECT(leakedOut);
        auto* leakedIn = new std::vector<uint8_t>(std::move(feedbackUrbStorage_));
        PULSR_LSAN_IGNORE_OBJECT(leakedIn);
        for (uint8_t* payload : urbBuffers_) {
            if (payload) PULSR_LSAN_IGNORE_OBJECT(payload);
        }
        for (uint8_t* payload : feedbackBuffers_) {
            if (payload) PULSR_LSAN_IGNORE_OBJECT(payload);
        }
    }
}

bool UsbAudioSink::IsActive() const {
    return active_.load(std::memory_order_acquire);
}

bool UsbAudioSink::IsDsdActive() const {
    // Both halves matter: the latch alone survives a worker fault until control
    // teardown, and an active PCM stream is obviously not DSD.
    return dsdMode_.load(std::memory_order_acquire) &&
           active_.load(std::memory_order_acquire);
}

uint8_t UsbAudioSink::FillDsdSilence(uint8_t* dst, int bytes, uint8_t firstPhase) {
    if (dst == nullptr || bytes <= 0) return firstPhase;
    uint8_t phase = (firstPhase == kDsdSilenceByteB) ? kDsdSilenceByteB : kDsdSilenceByteA;
    for (int i = 0; i < bytes; ++i) {
        dst[i] = phase;
        phase = (phase == kDsdSilenceByteA) ? kDsdSilenceByteB : kDsdSilenceByteA;
    }
    return phase;
}

bool UsbAudioSink::submitAll(UrbSubmit submit) {
    // HAL must stay muted even if only part of startup reaches the kernel and
    // rollback cannot reap it. releaseResources clears this only after drain.
    exclusive_.store(true, std::memory_order_release);
    for (size_t i = 0; i < urbs_.size(); ++i) {
        if (!submitUrb(urbs_[i], false, i, submit)) {
            return false;
        }
    }
    return true;
}

UsbStreamResult UsbAudioSink::Open(int fd, int endpointAddress, int interfaceNumber,
                                   int altSetting, int sampleRate, int channels,
                                   int bytesPerSample, int validBitDepth,
                                   bool alreadyConfigured, int renderMode) {
    std::lock_guard<std::mutex> control(controlMutex_);
    if (fd < 0 || interfaceNumber < 0 || altSetting < 0) {
        ReportWriteError(EINVAL);
        return UsbStreamResult::InvalidArgs;
    }
    // Stream shape is one policy for every mode: PCM takes the S16/S24/S32 wire
    // geometries on the standard rate list, DsdNative only a 4-byte subslot at
    // 32 valid bits, two channels, and a framesPerSecond that maps onto the
    // DSD64/128/256/512 U32 ladder. An unknown renderMode value is a caller bug
    // and is rejected the same way. Doing it before any device state is touched
    // keeps PCM geometry in DSD mode (and DSD geometry in a PCM mode) a clean
    // refusal instead of a half-open stream.
    const UsbStreamResult shape = CheckStreamShape(
        static_cast<UsbRenderMode>(renderMode), channels, bytesPerSample,
        validBitDepth, sampleRate);
    if (shape != UsbStreamResult::Ok) {
        ReportWriteError(EINVAL);
        return shape;
    }
    const int effectiveBits = validBitDepth == 0 && bytesPerSample >= 2 && bytesPerSample <= 4
        ? bytesPerSample * 8 : validBitDepth;
    // Isochronous OUT endpoint: addresses 1-15 with the IN bit clear.
    if (endpointAddress <= 0 || endpointAddress > 0x0f || (endpointAddress & 0x80) != 0) {
        ReportWriteError(EINVAL);
        return UsbStreamResult::InvalidArgs;
    }

    // Never tear down a live sink implicitly; caller must Stop first.
    if (active_.load()) {
        ReportWriteError(EBUSY);
        return UsbStreamResult::ClaimFailed;
    }

    // Defensive: if a previous worker self-exited (device unplug / URB error)
    // its std::thread is still joinable. Reassigning it below would abort the
    // process, so reap it first.
    if (worker_.joinable()) {
        worker_.join();
    }
    // A prior drain that failed leaves kernel-owned storage and HAL exclusivity
    // live. Never start a new stream on top of that half-torn-down sink.
    if (!releaseResources() || hasOutstandingUrbs()) {
        if (lastError_.load(std::memory_order_acquire) == 0) {
            lastError_.store(EBUSY, std::memory_order_release);
        }
        return UsbStreamResult::ClaimFailed; // never overwrite kernel-owned storage
    }

    lastError_.store(0, std::memory_order_relaxed);
    underrunCount_.store(0, std::memory_order_relaxed);
    overrunCount_.store(0, std::memory_order_relaxed);
    channelMismatchFrames_.store(0, std::memory_order_relaxed);

    fd_ = fd;
    endpoint_ = endpointAddress;
    interfaceNumber_ = interfaceNumber;
    altSetting_ = altSetting;
    sampleRate_ = sampleRate;
    channels_ = channels;
    bytesPerSample_ = bytesPerSample;
    validBitDepth_ = effectiveBits;
    renderMode_ = renderMode;
    // Published before any blocking setup so the producer-side refusals and
    // IsDsdActive() can never observe a PCM mode with DSD ring contents (or the
    // reverse). Every failure path below runs releaseResources(), which clears
    // it again.
    dsdMode_.store(IsDsdMode(renderMode), std::memory_order_release);
    dsdSilencePhase_ = kDsdSilenceByteA;
    bitPerfectEligible_.store(false, std::memory_order_relaxed);
    bitPerfectDisqualified_.store(false, std::memory_order_relaxed);
    producerDither_ = {};
    workerDither_ = {};
    // UsbGapFader fades PCM words around a ring gap; a DSD packet is a 1-bit
    // payload where that arithmetic is meaningless, so it is never configured
    // (and never applied) for a DSD stream.
    if (!IsDsdMode(renderMode_)) {
        gapFader_.configure(sampleRate, channels, bytesPerSample_);
    }
    asrcOutAvail_ = 0;

#if defined(__linux__) || defined(__ANDROID__)
    const int speed = ioctl(fd_, USBDEVFS_GET_SPEED);
    const auto config = fetchConfigDescriptor(fd_);
    const auto timing = ParseEndpointTiming(config.data(), config.size(),
                                           interfaceNumber_, altSetting_, endpoint_, speed);
    if (timing.intervalUs <= 0 || timing.maxPacketBytes <= 0) {
        lastError_.store(EINVAL, std::memory_order_relaxed);
        releaseResources();
        return UsbStreamResult::InvalidArgs;
    }
    if (!configureFeedbackFromDescriptor(config.data(), config.size())) {
        lastError_.store(EINVAL, std::memory_order_relaxed);
        releaseResources();
        return UsbStreamResult::InvalidArgs;
    }
    serviceIntervalUs_ = timing.intervalUs;
    const int frameBytes = channels_ * bytesPerSample_;
    const int capacityFrames = timing.maxPacketBytes / frameBytes;
    const uint64_t samplesPerInterval = static_cast<uint64_t>(sampleRate_) * serviceIntervalUs_;
    const int nominalFrames = static_cast<int>((samplesPerInterval + 999999) / 1000000);
    if (capacityFrames < nominalFrames) {
        lastError_.store(EINVAL, std::memory_order_relaxed);
        releaseResources();
        return UsbStreamResult::RateUnsupported;
    }
    maxFramesPerPacket_ = std::min(capacityFrames, nominalFrames + 1);
    if (IsReservoirMode(renderMode_)) {
        // Real-time ExoPlayer playback is paced by DefaultAudioSink's ~250 ms
        // AudioTrack buffer, so an untuned reservoir defaults to 200 ms (160 ms
        // prefill gate, 100 ms ASRC midpoint) instead of a 3000 ms file-reader
        // reservoir that ExoPlayer cannot prefill in one burst. StartPcmFile()
        // reconfigures to 3000 ms when standalone file streaming is used.
        const int reservoirMs = tunedBufferMs_ > 0 ? tunedBufferMs_ : 200;
        // Pull mode stores the wire bytes verbatim, so its frame size is the
        // wire frame size. ASRC mode stores decoded float frames (4 bytes each)
        // and packs after resampling.
        const int storageBytes = renderMode_ == static_cast<int>(UsbRenderMode::ClockSyncAsrc)
            ? 4 : bytesPerSample_;
        pullPackFrames_ = static_cast<size_t>(std::max(maxFramesPerPacket_, 8192));
        pullPack_.assign(pullPackFrames_ * static_cast<size_t>(channels_) *
                             static_cast<size_t>(bytesPerSample_), 0);
        if (!pullRenderer_.Configure(sampleRate_, channels_, storageBytes, reservoirMs)) {
            lastError_.store(EINVAL, std::memory_order_relaxed);
            releaseResources();
            return UsbStreamResult::InvalidArgs;
        }
        if (renderMode_ == static_cast<int>(UsbRenderMode::ClockSyncAsrc)) {
            if (!asrc_.configure(channels_, UsbAsrcClockSync::kDefaultTaps,
                                 UsbAsrcClockSync::kDefaultPhases,
                                 /*allowDynamicBypass=*/false)) {
                lastError_.store(EINVAL, std::memory_order_relaxed);
                releaseResources();
                return UsbStreamResult::InvalidArgs;
            }
            // maxFramesPerPacket_ is now known, so high-rate 10 ms packets
            // cannot overflow asrcPack_ or asrcOut_.
            allocateAsrcBuffers();
        }
    }
    // When Kotlin already claimed the interface, selected the alternate setting
    // and programmed+verified the DAC sample clock, do NOT send a second
    // USBDEVFS_SETINTERFACE here: on many UAC1/UAC2 DACs a redundant
    // SET_INTERFACE resets the sample clock back to 48 kHz while the host
    // streams at the track rate (producing slow/glitchy playback).
    if (!alreadyConfigured) {
        int iface = interfaceNumber_;
        if (ioctl(fd_, USBDEVFS_CLAIMINTERFACE, &iface) < 0) {
            lastError_.store(errno, std::memory_order_relaxed);
            releaseResources();
            return UsbStreamResult::ClaimFailed;
        }
        claimed_ = true;

        struct usbdevfs_setinterface si {};
        si.interface = static_cast<unsigned int>(interfaceNumber_);
        si.altsetting = static_cast<unsigned int>(altSetting_);
        // Best-effort: some HALs already selected the alt setting.
        if (ioctl(fd_, USBDEVFS_SETINTERFACE, &si) < 0) {
            if (errno != 0 && errno != EBUSY && altSetting_ > 0) {
                lastError_.store(errno, std::memory_order_relaxed);
                releaseResources();
                return UsbStreamResult::AltSettingFailed;
            }
        }
    } else {
        claimed_ = false;
    }

    const int maxBytesPerPacket = maxFramesPerPacket_ * frameBytes;
    bytesPerPacket_ = maxBytesPerPacket;
    // Automatic sizing targets an 8 ms URB. Stream tuning may replace it with an
    // explicit transfer size, clamped to 64 packets so one URB can never grow an
    // unbounded buffer; a request too small to carry a single packet falls back
    // to the automatic target (and says so once) instead of starving the pipe.
    int packetsPerUrb = std::max(1, kTargetUrbDurationUs / serviceIntervalUs_);
    if (tunedTransferSizeBytes_ > 0) {
        const int requestedPackets = maxBytesPerPacket > 0
            ? tunedTransferSizeBytes_ / maxBytesPerPacket : 0;
        if (requestedPackets >= 1) {
            packetsPerUrb = std::clamp(requestedPackets, 1, 64);
            PULSR_USB_LOG(ANDROID_LOG_INFO,
                          "tuning: transferSizeBytes=%d -> packetsPerUrb=%d",
                          tunedTransferSizeBytes_, packetsPerUrb);
        } else {
            static bool loggedSmallTransfer = false;
            if (!loggedSmallTransfer) {
                loggedSmallTransfer = true;
                PULSR_USB_LOG(ANDROID_LOG_WARN,
                              "tuning: transferSizeBytes=%d cannot hold one %d-byte "
                              "packet; using automatic URB sizing",
                              tunedTransferSizeBytes_, maxBytesPerPacket);
            }
        }
    }
    packetsPerUrb_ = packetsPerUrb;
    bytesPerUrb_ = maxBytesPerPacket * packetsPerUrb_;

    // Packet-sizing / feedback state consumed by the worker thread.
    frameAccumulator_ = 0;
    feedbackRatePerSec_.store(sampleRate_, std::memory_order_relaxed);  // nominal until a feedback sample arrives

    // Power-of-two frame capacity for mask-based frame & raw-depth indexing
    // (~1000 ms slack on standard devices; capped on <= 3 GiB RAM devices).
    const size_t minRingFrames = std::max(
        static_cast<size_t>(packetsPerUrb_ * maxFramesPerPacket_) * 8,
        static_cast<size_t>(256));
    size_t targetRingFrames = std::max(
        static_cast<size_t>(packetsPerUrb_ * maxFramesPerPacket_) * 32,
        static_cast<size_t>(sampleRate_));
#if defined(__linux__) || defined(__ANDROID__)
    const long physPages = sysconf(_SC_PHYS_PAGES);
    const long pageSize = sysconf(_SC_PAGESIZE);
    if (physPages > 0 && pageSize > 0) {
        const uint64_t totalRamBytes =
            static_cast<uint64_t>(physPages) * static_cast<uint64_t>(pageSize);
        if (totalRamBytes <= 3ULL * 1024ULL * 1024ULL * 1024ULL && frameBytes > 0) {
            constexpr size_t kLowRamMaxRingBytes = 4ULL * 1024ULL * 1024ULL;
            const size_t maxFramesByRam =
                std::max(minRingFrames, kLowRamMaxRingBytes / static_cast<size_t>(frameBytes));
            targetRingFrames = std::min(targetRingFrames, maxFramesByRam);
        }
    }
#endif
    size_t capFrames = 256;
    while (capFrames < targetRingFrames) capFrames <<= 1;
    ring_.assign(capFrames * static_cast<size_t>(frameBytes), 0);
    ringRawDepth_.assign(capFrames, 0);
    ringFrameMask_ = capFrames - 1;
    // 120 ms of cushion (capped to half the ring): sits comfortably inside
    // ExoPlayer's 250 ms AudioTrack buffer so the producer reaches prefill
    // immediately without stalling, while absorbing app/USB scheduler jitter.
    prefillFrames_ = std::min(
        static_cast<size_t>(sampleRate_) * 120 / 1000,
        capFrames / 2);
    ringRead_.store(0, std::memory_order_relaxed);
    ringWrite_.store(0, std::memory_order_relaxed);

    urbStride_ = sizeof(struct usbdevfs_urb) +
                 static_cast<size_t>(packetsPerUrb_) *
                     sizeof(struct usbdevfs_iso_packet_desc);
    // Keep each URB header 8-byte aligned within the storage block.
    urbStride_ = (urbStride_ + 7u) & ~static_cast<size_t>(7u);

    numUrbs_ = kNumUrbs;
    urbStorage_.assign(urbStride_ * numUrbs_, 0);
    urbBuffers_.assign(numUrbs_, nullptr);
    urbs_.assign(numUrbs_, nullptr);
    urbOwned_.assign(numUrbs_, 0);
    urbRawDepth_.assign(numUrbs_, 0);
    urbDeliveryEpoch_.assign(numUrbs_, deliveryEpoch_.load(std::memory_order_acquire));
    PULSR_USB_LOG(ANDROID_LOG_INFO,
                  "open: rate=%d ch=%d bytes=%d intervalUs=%d packetsPerUrb=%d "
                  "urbs=%d feedbackEp=0x%02x ringMs=%zu capacityFrames=%d",
                  sampleRate_, channels_, bytesPerSample_, serviceIntervalUs_,
                  packetsPerUrb_, numUrbs_, feedbackEndpoint_,
                  ringRawDepth_.size() * 1000 / static_cast<size_t>(std::max(1, sampleRate_)),
                  capacityFrames);

    // Nominal (feedback-free) initial packet lengths. frameAccumulator_ is a
    // member so the worker thread continues the same fractional cadence when it
    // refills URBs (and later feedback-adjusts it).
    for (int i = 0; i < numUrbs_; ++i) {
        auto* urb = reinterpret_cast<struct usbdevfs_urb*>(
            urbStorage_.data() + static_cast<size_t>(i) * urbStride_);
        urbBuffers_[i] = new (std::nothrow) uint8_t[bytesPerUrb_]();
        if (!urbBuffers_[i]) {
            lastError_.store(ENOMEM, std::memory_order_relaxed);
            releaseResources();
            return UsbStreamResult::SubmitFailed;
        }
        std::memset(urb, 0, sizeof(struct usbdevfs_urb));
        urb->type = USBDEVFS_URB_TYPE_ISO;
        urb->endpoint = static_cast<unsigned char>(endpoint_);
        urb->flags = USBDEVFS_URB_ISO_ASAP;
        urb->buffer = urbBuffers_[i];
        urb->number_of_packets = packetsPerUrb_;
        urb->usercontext = urb;
        int urbTotalBytes = 0;
        for (int p = 0; p < packetsPerUrb_; ++p) {
            const int framesInPacket = NextPacketFrames(
                frameAccumulator_, static_cast<uint32_t>(sampleRate_),
                serviceIntervalUs_, maxFramesPerPacket_);
            const int pktBytes = framesInPacket * frameBytes;
            urb->iso_frame_desc[p].length = static_cast<unsigned int>(pktBytes);
            urb->iso_frame_desc[p].actual_length = 0;
            urb->iso_frame_desc[p].status = 0;
            urbTotalBytes += pktBytes;
        }
        urb->buffer_length = urbTotalBytes;
        urbs_[i] = urb;
    }

    if (!submitAll()) {
        lastError_.store(errno, std::memory_order_relaxed);
        releaseResources();
        return UsbStreamResult::SubmitFailed;
    }

    // Explicit feedback is required when present: partial setup cannot safely
    // masquerade as a nominal-rate asynchronous stream.
    if (feedbackEndpoint_ != 0) {
        if (!setupFeedbackUrbs()) {
            releaseResources(); // drains OUT and IN by submitted identity
            return UsbStreamResult::SubmitFailed;
        }
    }

    // The container this sink packs into is the grid every rendering engine
    // must shape for; the broadcast reaches the registered players and engines
    // registered later inherit it.
    DspEngineRegistry::instance().setSinkBitDepth(validBitDepth_);
    sinkDepthPublished_ = true;
    // Direct USB PCM is now the live endpoint, so the engine may apply the
    // software attenuation (bitPerfect.directUsbGain). Published before the
    // worker starts so the first block already sees the gate open.
    AudioDspEngine::instance().updateParams([](DspParamSnapshot& snap) {
        snap.bitPerfect.directUsbActive = true;
    });
    producerOwner_.store(0, std::memory_order_release);
    paused_.store(false, std::memory_order_release);
    pullRenderer_.setPaused(false);
    running_.store(true, std::memory_order_release);
    active_.store(true, std::memory_order_release);
    writerGate_.store(0, std::memory_order_release);
    worker_ = std::thread([this] { workerLoop(); });
    return UsbStreamResult::Ok;
#else
    lastError_.store(ENOSYS, std::memory_order_relaxed);
    releaseResources();
    return UsbStreamResult::InvalidArgs;
#endif
}

bool UsbAudioSink::Close() {
    std::lock_guard<std::mutex> control(controlMutex_);
    if (active_.load(std::memory_order_acquire) || underrunCount_.load() > 0 ||
        overrunCount_.load() > 0) {
        PULSR_USB_LOG(ANDROID_LOG_INFO,
                      "close: rate=%d underruns=%llu overruns=%llu lastError=%d",
                      sampleRate_,
                      static_cast<unsigned long long>(underrunCount_.load()),
                      static_cast<unsigned long long>(overrunCount_.load()),
                      lastError_.load());
    }
    writerGate_.fetch_or(kWriterClosed, std::memory_order_acq_rel);
    // Always stop and join the worker, even if it already self-exited: a
    // joinable std::thread must never be reassigned (Open) or destroyed
    // (destructor), both of which call std::terminate().
    running_.store(false, std::memory_order_release);
    active_.store(false, std::memory_order_release);

    if (worker_.joinable()) {
        worker_.join();
    }

    return releaseResources();
}

void UsbAudioSink::Abandon() {
    std::lock_guard<std::mutex> control(controlMutex_);
    // Stop the worker first: nothing it writes may look live afterwards.
    writerGate_.fetch_or(kWriterClosed, std::memory_order_acq_rel);
    running_.store(false, std::memory_order_release);
    active_.store(false, std::memory_order_release);
    dsdMode_.store(false, std::memory_order_release);
    if (worker_.joinable()) {
        worker_.join();
    }
    // An admitted producer keeps its ring slot until it leaves. The gate is
    // already closed, so this terminates after the current writer.
    while (writerGate_.load(std::memory_order_acquire) & kWriterBusy) {
        std::this_thread::yield();
    }
    producerOwner_.store(0, std::memory_order_release);
    producerRawDepth_.store(0, std::memory_order_release);
    paused_.store(false, std::memory_order_release);
    pullRenderer_.setPaused(false);
    // A new stream starts as plain PCM; the JNI tap re-declares DoP on its next
    // direct-USB block. Reset the marker phase so it starts on 0x05 like every
    // other DoP framer in this codebase.
    producerIsDop_.store(false, std::memory_order_relaxed);
    dopMarkerPhase_ = kDopMarkerA;
    deliveryEpoch_.fetch_add(1, std::memory_order_acq_rel);
    rawPcmStatus_.store(0, std::memory_order_release);
    if (sinkDepthPublished_) {
        DspEngineRegistry::instance().setSinkBitDepth(0);
        sinkDepthPublished_ = false;
    }
    // No live Direct USB endpoint any more: gate directUsbGain back to unity so
    // an attenuation left over from this DAC cannot scale a speaker/Bluetooth
    // stream that is still claiming bit-perfect.
    AudioDspEngine::instance().updateParams([](DspParamSnapshot& snap) {
        snap.bitPerfect.directUsbActive = false;
    });

    // The caller has force-released the interface and closed the connection, so
    // this fd is dead: no RELEASEINTERFACE/CONNECT ioctl may run and no URB can
    // ever be reaped. Anything the kernel may still write through must stay
    // allocated for the lifetime of the process. Moving the header storage into
    // a leaked vector keeps every URB address valid (urbs_ points into it); the
    // packet payloads are leaked by dropping their pointers without delete[].
    // LSan is told about each allocation so leak checking stays meaningful for
    // the rest of the suite while the intentional leak remains documented here.
    if (!urbStorage_.empty()) {
        auto* leakedOut = new std::vector<uint8_t>(std::move(urbStorage_));
        PULSR_LSAN_IGNORE_OBJECT(leakedOut);
    }
    if (!feedbackUrbStorage_.empty()) {
        auto* leakedIn = new std::vector<uint8_t>(std::move(feedbackUrbStorage_));
        PULSR_LSAN_IGNORE_OBJECT(leakedIn);
    }
    for (uint8_t* payload : urbBuffers_) {
        if (payload) PULSR_LSAN_IGNORE_OBJECT(payload);
    }
    for (uint8_t* payload : feedbackBuffers_) {
        if (payload) PULSR_LSAN_IGNORE_OBJECT(payload);
    }
    urbBuffers_.clear();     // payload arrays deliberately leaked
    feedbackBuffers_.clear(); // payload arrays deliberately leaked
    urbs_.clear();
    feedbackUrbs_.clear();
    urbOwned_.clear();
    feedbackOwned_.clear();
    urbRawDepth_.clear();
    urbDeliveryEpoch_.clear();
    urbStride_ = 0;
    numUrbs_ = 0;
    feedbackUrbStride_ = 0;
    numFeedbackUrbs_ = 0;
    feedbackPacketsPerUrb_ = 0;
    feedbackEndpoint_ = 0;
    feedbackPacketSize_ = 0;
    // The producer is stopped and the gate is closed, so the ring can go.
    ring_.clear();
    ring_.shrink_to_fit();
    ringRawDepth_.clear();
    ringRawDepth_.shrink_to_fit();
    ringFrameMask_ = 0;
    prefillFrames_ = 0;
    ringWrite_.store(0, std::memory_order_relaxed);
    ringRead_.store(0, std::memory_order_relaxed);
    // No fd, no claim, no exclusivity: the next Open starts from scratch instead
    // of draining a dead descriptor forever.
    claimed_ = false;
    fd_ = -1;
    renderMode_ = 0;
    exclusive_.store(false, std::memory_order_release);
    // A completed forced teardown is not a live fault: drop the ETIMEDOUT (or
    // any other error) the failed drain left here so the sink matches its
    // pristine pre-Open contract and status reads stop reporting a dead stream.
    lastError_.store(0, std::memory_order_release);
}

bool UsbAudioSink::hasOutstandingUrbs() const {
    return std::find(urbOwned_.begin(), urbOwned_.end(), 1) != urbOwned_.end() ||
        std::find(feedbackOwned_.begin(), feedbackOwned_.end(), 1) != feedbackOwned_.end();
}

int UsbAudioSink::submitUsbfsUrb(int fd, void* urb) {
    return ioctl(fd, USBDEVFS_SUBMITURB, urb);
}

bool UsbAudioSink::submitUrb(void* urb, bool feedback, size_t index, UrbSubmit submit) {
    if (submit(fd_, urb) < 0) return false;
    (feedback ? feedbackOwned_ : urbOwned_)[index] = 1;
    return true;
}

bool UsbAudioSink::markReaped(void* urb, bool* feedback, size_t* index) {
    for (size_t i = 0; i < urbs_.size(); ++i) {
        if (urbs_[i] == urb && urbOwned_[i]) {
            urbOwned_[i] = 0;
            *feedback = false;
            *index = i;
            return true;
        }
    }
    for (size_t i = 0; i < feedbackUrbs_.size(); ++i) {
        if (feedbackUrbs_[i] == urb && feedbackOwned_[i]) {
            feedbackOwned_[i] = 0;
            *feedback = true;
            *index = i;
            return true;
        }
    }
    return false; // unrelated/duplicate completion does not discharge ownership
}

int UsbAudioSink::reapUsbfsUrb(int fd, void** urb) {
#if defined(__linux__) || defined(__ANDROID__)
    return ioctl(fd, USBDEVFS_REAPURBNDELAY, urb);
#else
    (void)fd;
    (void)urb;
    // No usbfs endpoint exists on this host, so answer exactly like an idle one:
    // the caller's deadline logic is then exercised unchanged by the host tests.
    errno = EAGAIN;
    return -1;
#endif
}

bool UsbAudioSink::drainUrbCompletions(int timeoutMs, UrbReap reap) {
    if (!hasOutstandingUrbs()) return true;
    if (!reap) {
        lastError_.store(EINVAL, std::memory_order_release);
        return false;
    }
    if (fd_ < 0) {
        ReportWriteError(EBADF);
        return false;
    }
#if defined(__linux__) || defined(__ANDROID__)
    // Ask the kernel to cancel every transfer we still own. Cancellation has no
    // shortcut: a submitted header/payload stays allocated until that exact URB
    // is reaped, so the poll below is the only proof ownership came back.
    for (size_t i = 0; i < urbs_.size(); ++i) {
        if (urbOwned_[i]) ioctl(fd_, USBDEVFS_DISCARDURB, urbs_[i]);
    }
    for (size_t i = 0; i < feedbackUrbs_.size(); ++i) {
        if (feedbackOwned_[i]) ioctl(fd_, USBDEVFS_DISCARDURB, feedbackUrbs_[i]);
    }
#endif
    // Bounded teardown (control thread only). USBDEVFS_REAPURB blocks forever
    // when the HAL stops servicing the endpoint, which would wedge Close() and
    // pin HAL exclusivity for the rest of the process. Poll non-blocking with a
    // 1 ms backoff instead and give the kernel a fixed budget to hand back
    // every cancelled URB. The loop itself is not #if'd out: `reap` is
    // injectable, so the host build tests the deadline, not just the helpers.
    const auto deadline = std::chrono::steady_clock::now() +
        std::chrono::milliseconds(std::max(0, timeoutMs));
    bool sawUnknownCompletion = false;
    while (hasOutstandingUrbs()) {
        // The budget is checked before every reap, not only after an idle one:
        // a device or queue that keeps returning duplicate/foreign completion
        // pointers would otherwise spin here forever, pinning HAL exclusivity.
        if (std::chrono::steady_clock::now() >= deadline) break;
        void* urb = nullptr;
        if (reap(fd_, &urb) < 0) {
            const int err = errno;
            if (err != EINTR && err != EAGAIN && err != EINPROGRESS) {
                lastError_.store(err, std::memory_order_release);
                return false; // retain ALL storage; error is not an ownership proof
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(1));
            continue;
        }
        bool feedback = false;
        size_t index = 0;
        if (!markReaped(urb, &feedback, &index)) {
            // The claimed interface is exclusive. Unknown completions cannot
            // be safely requeued or counted as our cancellation acknowledgments,
            // but they must not poison diagnostics after a clean drain either
            // (see the EPROTO clear below).
            lastError_.store(EPROTO, std::memory_order_release);
            sawUnknownCompletion = true;
        }
    }
    if (hasOutstandingUrbs()) {
        // Ownership is unproven: keep every buffer and the interface claim so a
        // later teardown can still reap the exact URBs the kernel holds.
        lastError_.store(ETIMEDOUT, std::memory_order_release);
        return false;
    }
    if (sawUnknownCompletion) {
        // Every URB we own came back, so a stray completion was noise rather
        // than proof the stream is corrupt. Leaving EPROTO latched would make
        // the next status/diagnostic read report a protocol error forever after
        // an otherwise successful teardown.
        lastError_.store(0, std::memory_order_release);
        static auto lastUnknownLog = std::chrono::steady_clock::time_point{};
        const auto now = std::chrono::steady_clock::now();
        if (now - lastUnknownLog >= std::chrono::seconds(1)) {
            lastUnknownLog = now;
            PULSR_USB_LOG(ANDROID_LOG_WARN,
                          "drain: ignored an unrecognized URB completion; "
                          "cleared stale EPROTO");
        }
    }
    return true;
}

// ---- Async feedback (anti-drift) support, FIX 2 ----

std::vector<uint8_t> UsbAudioSink::fetchConfigDescriptor(int fd) {
#if defined(__linux__) || defined(__ANDROID__)
    if (fd < 0) return {};
    // GET_DESCRIPTOR(CONFIG): first read 4 bytes to learn wTotalLength, then the
    // whole configuration.
    uint8_t header[4] = {0};
    struct usbdevfs_ctrltransfer ctrl {};
    ctrl.bRequestType = 0x80; // IN | STANDARD | DEVICE
    ctrl.bRequest = 0x06;     // GET_DESCRIPTOR
    ctrl.wValue = 0x0200;     // (CONFIG << 8) | index 0
    ctrl.wIndex = 0;
    ctrl.wLength = sizeof(header);
    ctrl.timeout = 1000;
    ctrl.data = header;
    if (ioctl(fd, USBDEVFS_CONTROL, &ctrl) < 0) return {};

    uint16_t totalLength = static_cast<uint16_t>(header[2] | (header[3] << 8));
    if (totalLength < 9 || totalLength > 16384) totalLength = 4096;

    std::vector<uint8_t> cfg(totalLength);
    ctrl.wLength = totalLength;
    ctrl.data = cfg.data();
    int res = ioctl(fd, USBDEVFS_CONTROL, &ctrl);
    if (res < 0) return {};
    cfg.resize(std::min(static_cast<size_t>(res), cfg.size()));
    return cfg;
#else
    (void)fd;
    return {};
#endif
}

int UsbAudioSink::findFeedbackEndpoint(const uint8_t* cfg, size_t len,
                                       int interfaceNumber, int altSetting,
                                       int* outPacketSize) {
    if (outPacketSize) *outPacketSize = 0;
    // A valid OUT descriptor can precede a truncated feedback descriptor. Its
    // timing alone is not proof that this configuration has no feedback.
    if (!cfg || len < 9 || cfg[0] < 9 || cfg[0] > len || cfg[1] != 0x02 ||
        static_cast<size_t>(cfg[2] | (cfg[3] << 8)) != len) return -1;

    bool selected = false, foundInterface = false;
    int expectedEndpoints = 0, seenEndpoints = 0;
    int endpoint = 0, packetSize = 0;
    for (size_t i = 0; i < len;) {
        if (len - i < 2) return -1;
        const size_t bLength = cfg[i];
        if (bLength < 2 || bLength > len - i) return -1;
        const uint8_t bType = cfg[i + 1];
        if (bType == 0x04) { // INTERFACE
            if (bLength < 9 || (selected && seenEndpoints != expectedEndpoints)) return -1;
            const uint8_t ifClass = cfg[i + 5];
            const uint8_t ifProtocol = cfg[i + 7];
            const bool isAudioClass = ifClass == 0x01 ||
                (ifClass == 0xFF && (ifProtocol == 0x00 || ifProtocol == 0x20));
            selected = cfg[i + 2] == interfaceNumber && cfg[i + 3] == altSetting &&
                isAudioClass && cfg[i + 6] == 0x02;
            if (selected) {
                if (foundInterface) return -1; // ambiguous duplicate interface/alt
                foundInterface = true;
                expectedEndpoints = cfg[i + 4];
                seenEndpoints = 0;
            }
        } else if (bType == 0x05) { // ENDPOINT
            if (bLength < 7) return -1;
            if (selected) {
                if (++seenEndpoints > expectedEndpoints) return -1;
                const uint8_t addr = cfg[i + 2];
                const uint8_t attrs = cfg[i + 3];
                const int maxPacket = cfg[i + 4] | (cfg[i + 5] << 8);
                const bool isIso = (attrs & 0x03) == 0x01;
                const bool isIn = (addr & 0x80) != 0;
                const int usage = attrs & 0x30; // 0x10 => feedback usage
                const int synch = attrs & 0x0C; // 0x04 => asynchronous
                if (endpoint == 0 && isIso && isIn &&
                    (usage == 0x10 || synch == 0x04 ||
                     (maxPacket >= 3 && maxPacket <= 8))) {
                    endpoint = addr;
                    packetSize = maxPacket;
                }
            }
        }
        i += bLength;
    }
    // Validate the entire descriptor chain, even after finding feedback, and
    // use bNumEndpoints to reject omission at an otherwise valid boundary.
    if (!foundInterface || (selected && seenEndpoints != expectedEndpoints)) return -1;
    if (outPacketSize) *outPacketSize = packetSize;
    return endpoint;
}

bool UsbAudioSink::configureFeedbackFromDescriptor(const uint8_t* config, size_t len) {
    feedbackEndpoint_ = findFeedbackEndpoint(config, len,
                                             interfaceNumber_, altSetting_,
                                             &feedbackPacketSize_);
    if (feedbackEndpoint_ < 0) {
        feedbackEndpoint_ = 0;
        feedbackPacketSize_ = 0;
        return false;
    }
    // Stream tuning: a DAC whose feedback IN endpoint steers badly can be
    // pinned to ring-fill steering. Treat the endpoint as absent so no feedback
    // URB is ever submitted; the worker's steering fallback then owns cadence
    // (the same path a DAC without feedback already takes).
    if (disableExplicitFeedback_ && feedbackEndpoint_ != 0) {
        PULSR_USB_LOG(ANDROID_LOG_INFO,
                      "tuning: ignoring advertised feedback endpoint 0x%02x",
                      feedbackEndpoint_);
        feedbackEndpoint_ = 0;
        feedbackPacketSize_ = 0;
    }
    return true;
}

void UsbAudioSink::allocateAsrcBuffers() {
    const size_t ch = static_cast<size_t>(std::max(1, channels_));
    // One packet of output plus lookahead, and a bounded input chunk.
    // Sized after maxFramesPerPacket_ is computed so high-rate 10 ms packets
    // (e.g. 768 kHz -> 7681 frames) never overflow asrcPack_ or asrcOut_.
    const size_t packetFloor = static_cast<size_t>(
        std::max(maxFramesPerPacket_, 2048));
    const size_t outCap = (packetFloor + 64) * ch;
    asrcOut_.assign(outCap, 0.0f);
    asrcPack_.assign(packetFloor * ch, 0.0f);
    asrcInputCapacityFrames_ = 1024;
    asrcIn_.assign(asrcInputCapacityFrames_ * ch, 0.0f);
    // Typical decoder blocks are 256-4096 frames; 8192 covers them
    // without allocating in the producer path.
    asrcRawScratchFrames_ = 8192;
    asrcRawScratch_.assign(asrcRawScratchFrames_ * ch, 0.0f);
    asrcOutAvail_ = 0;
}

double UsbAudioSink::computeAsrcRatio() const {
    double ratio = 1.0;
    if (feedbackEndpoint_ != 0) {
        const int fbRate = feedbackRatePerSec_.load(std::memory_order_relaxed);
        if (sampleRate_ > 0 && fbRate > 0) {
            ratio = static_cast<double>(fbRate) / static_cast<double>(sampleRate_);
        }
    } else {
        const int targetMs = pullRenderer_.bufferMs();
        if (targetMs > 0) {
            const double targetMidMs = static_cast<double>(targetMs) * 0.5;
            const double currentFillMs = static_cast<double>(pullRenderer_.fillMs());
            // Low reservoir fill (DAC running faster than producer) needs
            // ratio > 1 so fewer input frames are consumed per output frame;
            // high reservoir fill needs ratio < 1 to drain the surplus.
            const double error = (targetMidMs - currentFillMs) / targetMidMs;
            ratio = 1.0 + error * UsbAsrcClockSync::kMaxRatioDeviation;
        }
    }
    return std::clamp(ratio, UsbAsrcClockSync::kMinRatio, UsbAsrcClockSync::kMaxRatio);
}

void UsbAudioSink::freeFeedbackResources() {
    for (uint8_t* b : feedbackBuffers_) {
        delete[] b;
    }
    feedbackBuffers_.clear();
    feedbackBuffers_.shrink_to_fit();
    feedbackUrbs_.clear();
    feedbackUrbs_.shrink_to_fit();
    feedbackOwned_.clear();
    feedbackUrbStorage_.clear();
    feedbackUrbStorage_.shrink_to_fit();
    feedbackUrbStride_ = 0;
    numFeedbackUrbs_ = 0;
    feedbackPacketsPerUrb_ = 0;
    feedbackEndpoint_ = 0;
    feedbackPacketSize_ = 0;
}

bool UsbAudioSink::releaseResources() {
    // Stop the reader thread before any buffer it writes can be released.
    if (pcmProducer_) {
        pcmProducer_->stop();
        pcmProducer_.reset();
    }
    writerGate_.fetch_or(kWriterClosed, std::memory_order_acq_rel);
    active_.store(false, std::memory_order_release);
    // Teardown retires the DSD latch immediately: no producer call and no status
    // read may keep describing a native-DSD stream while the ring is being
    // drained or freed.
    dsdMode_.store(false, std::memory_order_release);
    while (writerGate_.load(std::memory_order_acquire) & kWriterBusy) {
        std::this_thread::yield(); // control only; never free a live writer's ring
    }
    producerOwner_.store(0, std::memory_order_release);
    producerRawDepth_.store(0, std::memory_order_release);
    paused_.store(false, std::memory_order_release);
    pullRenderer_.setPaused(false);
    // Item 3: a new stream starts as plain PCM; the JNI tap re-declares DoP on the
    // next direct-USB block. Reset the marker phase so a fresh stream starts on
    // 0x05 like every DoP framer in this codebase.
    producerIsDop_.store(false, std::memory_order_relaxed);
    dopMarkerPhase_ = kDopMarkerA;
    deliveryEpoch_.fetch_add(1, std::memory_order_acq_rel);
    rawPcmStatus_.store(0, std::memory_order_release);
    if (sinkDepthPublished_) {
        DspEngineRegistry::instance().setSinkBitDepth(0);
        sinkDepthPublished_ = false; // clear even after the worker self-exited
    }
    // No live Direct USB endpoint any more: gate directUsbGain back to unity so
    // an attenuation left over from this DAC cannot scale a speaker/Bluetooth
    // stream that is still claiming bit-perfect.
    AudioDspEngine::instance().updateParams([](DspParamSnapshot& snap) {
        snap.bitPerfect.directUsbActive = false;
    });

    if (!drainUrbCompletions()) return false; // keep kernel-owned buffers + claim on failure

    for (uint8_t* b : urbBuffers_) {
        delete[] b;
    }
    urbBuffers_.clear();
    urbs_.clear();
    urbOwned_.clear();
    urbRawDepth_.clear();
    urbDeliveryEpoch_.clear();
    urbStorage_.clear();
    urbBuffers_.shrink_to_fit();
    urbs_.shrink_to_fit();
    urbStorage_.shrink_to_fit();
    // Feedback URBs were cancelled+reaped by drainUrbCompletions() above.
    freeFeedbackResources();
    ring_.clear();
    ring_.shrink_to_fit();
    ringRawDepth_.clear();
    ringRawDepth_.shrink_to_fit();
    ringFrameMask_ = 0;
    if (claimed_ && fd_ >= 0) {
        int iface = interfaceNumber_;
        ioctl(fd_, USBDEVFS_RELEASEINTERFACE, &iface);
        RebindKernelDriver(fd_, interfaceNumber_);
    }
    claimed_ = false;
    fd_ = -1;
    // No live stream: the next Open must not inherit a shape it did not request.
    renderMode_ = 0;
    running_.store(false, std::memory_order_release);
    exclusive_.store(false, std::memory_order_release); // only after USB ownership is drained
    return true;
}

bool UsbAudioSink::RebindKernelDriver(int fd, int interfaceNumber) {
#if defined(__linux__) || defined(__ANDROID__)
    if (fd < 0 || interfaceNumber < 0) return false;
    struct usbdevfs_ioctl cmd {};
    cmd.ifno = interfaceNumber;
    cmd.ioctl_code = USBDEVFS_CONNECT;
    cmd.data = nullptr;
    return ioctl(fd, USBDEVFS_IOCTL, &cmd) >= 0;
#else
    (void)fd;
    (void)interfaceNumber;
    return false;
#endif
}

int UsbAudioSink::completionError(const void* raw, bool feedback, int packets, int maxBytes) {
    const auto* urb = static_cast<const usbdevfs_urb*>(raw);
    if (!urb || urb->number_of_packets != packets || packets <= 0 ||
        urb->buffer_length < 0 || urb->buffer_length > maxBytes ||
        urb->actual_length < 0 || urb->actual_length > urb->buffer_length) return EPROTO;
    if (urb->status != 0) return urb->status < 0 ? -urb->status : EIO;
    if (urb->error_count != 0) return EIO;
    uint64_t requested = 0, actual = 0;
    for (int p = 0; p < packets; ++p) {
        const auto& packet = urb->iso_frame_desc[p];
        if (packet.status != 0) return EIO;
        if (packet.actual_length > packet.length ||
            (!feedback && packet.actual_length != packet.length)) return EIO;
        requested += packet.length;
        actual += packet.actual_length;
    }
    if (requested != static_cast<uint64_t>(urb->buffer_length) ||
        actual != static_cast<uint64_t>(urb->actual_length)) return EPROTO;
    return 0;
}

size_t UsbAudioSink::fillPacketFromRing(uint8_t* dst, int framesInPacket,
                                          size_t& readFrame, int& rawDepth,
                                          uint64_t& deliveryEpoch) {
    const size_t frameBytes =
        static_cast<size_t>(channels_) * static_cast<size_t>(bytesPerSample_);
    const size_t pktLen = static_cast<size_t>(framesInPacket) * frameBytes;
    if (pktLen == 0) return 0;
    // Native DSD: the wire payload is a 1-bit stream packed into 32-bit words. It
    // is never dithered, faded, requantised or gap-faded, and a gap is filled
    // with the alternating 0x69/0x96 pattern instead of PCM zeroes: an all-zero
    // word is 32 zero DSD bits, i.e. hard negative DC that a DSD DAC renders as
    // a thump rather than silence.
    const bool dsd = dsdMode_.load(std::memory_order_relaxed);

    const size_t w = ringWrite_.load(std::memory_order_acquire);
    const size_t availFrames = w - readFrame; // unsigned arithmetic survives counter wrap
    const size_t copyFrames = std::min(availFrames, static_cast<size_t>(framesInPacket));
    bool packetRaw = false;

    if (copyFrames > 0) {
        const size_t mask = ringFrameMask_;
        for (size_t f = 0; f < copyFrames; ++f) {
            const size_t slot = (readFrame + f) & mask;
            const uint8_t* src = ring_.data() + slot * frameBytes;
            std::memcpy(dst + f * frameBytes, src, frameBytes);
            const int depth = ringRawDepth_[slot];
            packetRaw = packetRaw || depth != 0;
            if (rawDepth == -1) rawDepth = depth;
            else if (rawDepth != depth) rawDepth = 0;
        }
        readFrame += copyFrames;
    }

    const size_t realBytes = copyFrames * frameBytes;
    // Item 3: DoP words carry a 0x05/0xFA marker in their MSB. A raw underrun on a
    // DoP stream must therefore be filled with valid DoP silence that continues
    // the producer's phase, not with plain zeros. A DSD stream is not DoP: its
    // words are plain DSD payload, so the DoP marker machinery stays out of it.
    const bool dopGap = !dsd &&
                        producerIsDop_.load(std::memory_order_relaxed) &&
                        IsDopSilenceContainer(bytesPerSample_);
    if (copyFrames == static_cast<size_t>(framesInPacket)) {
        if (packetRaw) {
            // Raw/DoP packets must stay bit-identical across underrun recovery:
            // never run gapFader_ or RequantizePcmValidBits on raw samples.
            gapFader_.reset();
            if (dopGap) {
                // Carry the marker phase forward so a later gap stays in lockstep.
                dopMarkerPhase_ = DopMarkerAfterLastFrame(
                    dst, copyFrames, channels_, bytesPerSample_, dopMarkerPhase_);
            }
            if (dsd) {
                // A whole packet of producer DSD bytes reached the wire exactly as
                // written, so the session has earned the BitPerfect-shaped domain
                // (DeriveClockDomain still requires zero underruns/mismatches).
                bitPerfectEligible_.store(
                    !bitPerfectDisqualified_.load(std::memory_order_acquire),
                    std::memory_order_release);
            }
        } else {
            if (gapFader_.recovering()) {
                rawDepth = 0;
            }
            gapFader_.applyReal(dst, framesInPacket, workerDither_);
            if (validBitDepth_ < bytesPerSample_ * 8) {
                for (size_t sample = 0; sample < pktLen; sample += bytesPerSample_) {
                    RequantizePcmValidBits(dst + sample, bytesPerSample_,
                                           validBitDepth_, workerDither_);
                }
            }
        }
    } else {
        // Partial or complete underrun: salvage any available real frames at the
        // packet head rather than discarding up to a full packet of buffered audio.
        const int missingFrames = framesInPacket - static_cast<int>(copyFrames);
        if (copyFrames > 0) {
            if (dsd) {
                // Head of the packet is real DSD; the tail is the DSD silence
                // pattern. No fader, no requantisation: both would rewrite payload
                // words the DAC reads as bitstream.
                dsdSilencePhase_ = FillDsdSilence(
                    dst + realBytes, static_cast<int>(pktLen - realBytes),
                    dsdSilencePhase_);
                bitPerfectDisqualified_.store(true, std::memory_order_release);
                bitPerfectEligible_.store(false, std::memory_order_release);
                gapFader_.reset();
            } else if (packetRaw || producerRawDepth_.load(std::memory_order_acquire) != 0) {
                if (dopGap) {
                    // Continue the marker alternation from the last real frame and
                    // emit zero payload; no fader and no requantisation (both would
                    // corrupt the DoP words).
                    dopMarkerPhase_ = DopMarkerAfterLastFrame(
                        dst, copyFrames, channels_, bytesPerSample_, dopMarkerPhase_);
                    dopMarkerPhase_ = FillDopSilence(dst + realBytes, missingFrames,
                                                     channels_, bytesPerSample_,
                                                     dopMarkerPhase_);
                } else {
                    std::memset(dst + realBytes, 0, pktLen - realBytes);
                }
                gapFader_.reset();
            } else {
                gapFader_.applyReal(dst, static_cast<int>(copyFrames), workerDither_);
                gapFader_.fillGap(dst + realBytes, missingFrames, workerDither_);
                if (validBitDepth_ < bytesPerSample_ * 8) {
                    for (size_t sample = 0; sample < pktLen; sample += bytesPerSample_) {
                        RequantizePcmValidBits(dst + sample, bytesPerSample_,
                                               validBitDepth_, workerDither_);
                    }
                }
            }
        } else {
            // Raw/DoP gaps must be silence, not synthesized marker/audio bytes.
            if (dsd) {
                dsdSilencePhase_ = FillDsdSilence(dst, static_cast<int>(pktLen),
                                                 dsdSilencePhase_);
                bitPerfectDisqualified_.store(true, std::memory_order_release);
                bitPerfectEligible_.store(false, std::memory_order_release);
                gapFader_.reset();
            } else if (producerRawDepth_.load(std::memory_order_acquire) != 0) {
                if (dopGap) {
                    dopMarkerPhase_ = FillDopSilence(dst, framesInPacket, channels_,
                                                     bytesPerSample_, dopMarkerPhase_);
                } else {
                    std::memset(dst, 0, pktLen);
                }
                gapFader_.reset();
            } else {
                gapFader_.fillGap(dst, framesInPacket, workerDither_);
                if (validBitDepth_ < bytesPerSample_ * 8) {
                    for (size_t sample = 0; sample < pktLen; sample += bytesPerSample_) {
                        RequantizePcmValidBits(dst + sample, bytesPerSample_,
                                               validBitDepth_, workerDither_);
                    }
                }
            }
        }
        // A PCM gap is no longer a raw delivery. A DSD gap still is: the words
        // written there are genuine DSD_U32 payload (silence), not float, so the
        // depth marker must say 32 - reporting 0 would make the status surfaces
        // describe a DSD stream as float.
        rawDepth = dsd ? 32 : 0;
        deliveryEpoch = deliveryEpoch_.fetch_add(1, std::memory_order_acq_rel) + 1;
        const uint64_t total = underrunCount_.fetch_add(1, std::memory_order_relaxed) + 1;
        // Rate-limited: an underrun burst can span every packet of a URB.
        static auto lastLog = std::chrono::steady_clock::time_point{};
        const auto now = std::chrono::steady_clock::now();
        if (now - lastLog >= std::chrono::seconds(1)) {
            lastLog = now;
            const size_t w = ringWrite_.load(std::memory_order_acquire);
            const size_t fillFrames = w - readFrame;
            PULSR_USB_LOG(ANDROID_LOG_WARN,
                          "underrun #%llu: missing=%d ringFillMs=%.1f rate=%u "
                          "feedback=%d",
                          static_cast<unsigned long long>(total), missingFrames,
                          sampleRate_ > 0
                              ? static_cast<double>(fillFrames) * 1000.0 / sampleRate_
                              : 0.0,
                          static_cast<uint32_t>(feedbackRatePerSec_.load(
                              std::memory_order_relaxed)),
                          feedbackEndpoint_ != 0 ? 1 : 0);
        }
    }

    return pktLen;
}

void UsbAudioSink::workerLoop() {
#if defined(__linux__) || defined(__ANDROID__)
    // Java's Process.THREAD_PRIORITY_URGENT_AUDIO is nice -19. usbfs URB
    // completion latency is directly in the playback path; best effort because
    // some kernels refuse the negative nice for app threads.
    setpriority(PRIO_PROCESS, 0, -19);
#endif
    // Keep the URB pipeline continuously reaped and resubmitted while waiting
    // for the ring cushion (`prefillFrames_`). Sleeping BEFORE entering the
    // reap loop starved all 8 submitted URBs within ~64 ms, stalling the USB
    // xHCI isochronous schedule and causing startup glitches/underruns. While
    // waiting for prefill, OUT URBs carry clean silence (or DoP silence)
    // without incrementing underrunCount_.
    const bool pullMode = IsReservoirMode(renderMode_);
    bool prefillDone = pullMode ? pullRenderer_.prefillSatisfied()
                                : (prefillFrames_ == 0);
    bool producerSeen = false;
    auto prefillDeadline = std::chrono::steady_clock::time_point{};
    int repeatedReadyPolls = 0;
    int consecutiveOutFaults = 0;
    constexpr int kMaxConsecutiveOutFaults = 3;
    while (running_.load(std::memory_order_acquire)) {
        struct usbdevfs_urb* urb = nullptr;
        int r = ioctl(fd_, USBDEVFS_REAPURBNDELAY, &urb);
        if (r < 0) {
            if (errno == EAGAIN || errno == EINPROGRESS) {
#if defined(__linux__) || defined(__ANDROID__)
                // Block until a URB completes (or 5 ms, keeping running_
                // responsive) instead of spinning on a 1 ms sleep.
                struct pollfd pfd{};
                pfd.fd = fd_;
                pfd.events = POLLOUT;
                const int polled = poll(&pfd, 1, 5);
                if (polled > 0 && (pfd.revents & POLLOUT) != 0) {
                    // Some kernels report usbfs fds as always writable. Bail
                    // out to a short sleep if that produces no completions.
                    if (++repeatedReadyPolls < 8) continue;
                }
                repeatedReadyPolls = 0;
                if (polled < 0 && errno == EINTR) continue;
                std::this_thread::sleep_for(std::chrono::milliseconds(1));
#else
                std::this_thread::sleep_for(std::chrono::milliseconds(1));
#endif
                continue;
            }
            // ESHUTDOWN / ENOENT / device gone: stop cleanly.
            lastError_.store(errno, std::memory_order_release);
            break;
        }
        repeatedReadyPolls = 0;
        if (urb == nullptr) continue;

        bool feedback = false;
        size_t urbIndex = 0;
        if (!markReaped(urb, &feedback, &urbIndex)) {
            ReportWriteError(EPROTO);
            break; // never dereference an unrecognized returned pointer
        }
        const int fault = completionError(urb, feedback,
            feedback ? feedbackPacketsPerUrb_ : packetsPerUrb_,
            feedback ? feedbackPacketSize_ * feedbackPacketsPerUrb_ : bytesPerUrb_);
        if (feedback) {
            // Invalid IN completion/packet status cannot steer the DAC clock.
            uint8_t* fbuf = reinterpret_cast<uint8_t*>(urb->buffer);
            if (urb->number_of_packets != feedbackPacketsPerUrb_) {
                ReportWriteError(EPROTO);
                break;
            }
            for (int p = 0; p < feedbackPacketsPerUrb_; ++p) {
                const unsigned int got = urb->iso_frame_desc[p].actual_length;
                if (fault == 0 && got == static_cast<unsigned int>(feedbackPacketSize_)) {
                    applyFeedback(fbuf, static_cast<int>(got));
                }
                fbuf += feedbackPacketSize_;
                urb->iso_frame_desc[p].length =
                    static_cast<unsigned int>(feedbackPacketSize_);
                urb->iso_frame_desc[p].actual_length = 0;
                urb->iso_frame_desc[p].status = 0;
            }
            if (fault != 0) {
                ReportWriteError(fault);
                feedbackRatePerSec_.store(sampleRate_, std::memory_order_relaxed);
            }
            urb->buffer_length = feedbackPacketSize_ * feedbackPacketsPerUrb_;
            urb->status = 0;
            urb->actual_length = 0;
            urb->error_count = 0;
            if (!submitUrb(urb, true, urbIndex)) {
                ReportWriteError(errno);
                break; // loss of required feedback is a stream fault
            }
            continue;
        }
        if (fault != 0) {
            ReportWriteError(fault);
            const auto faultNowNs = std::chrono::steady_clock::now().time_since_epoch().count();
            const int64_t prevFaultNs = lastFaultLogNs_.load(std::memory_order_relaxed);
            if (prevFaultNs == 0 || (faultNowNs - prevFaultNs) >= 1'000'000'000LL) {
                lastFaultLogNs_.store(faultNowNs, std::memory_order_relaxed);
                PULSR_USB_LOG(ANDROID_LOG_WARN,
                              "urb fault=%d consecutive=%d underruns=%llu errno=%d",
                              fault, consecutiveOutFaults + 1,
                              static_cast<unsigned long long>(underrunCount_.load()),
                              lastError_.load());
            }
            // One short/failed isochronous OUT is usually a transient
            // controller/DAC hiccup. Killing the worker turns it into a hard
            // silent stream; requeue the URB instead, using the ring's current
            // audio (or silence when it is empty). A genuinely gone device
            // keeps faulting and crosses the consecutive budget below.
            if (++consecutiveOutFaults >= kMaxConsecutiveOutFaults) {
                break;
            }
        } else {
            consecutiveOutFaults = 0;
            rawPcmStatus_.store((urbDeliveryEpoch_[urbIndex] << 8) |
                static_cast<uint64_t>(urbRawDepth_[urbIndex]), std::memory_order_release);
        }

        // OUT URB: recompute every packet length from the fractional sample
        // accumulator stepped by the current (feedback-adjusted) rate, clamped
        // to maxFramesPerPacket_ so the preallocated buffer can never overflow.
        uint8_t* buf = reinterpret_cast<uint8_t*>(urb->buffer);
        const size_t ringFrames = ringRawDepth_.size();
        size_t readFrame = ringRead_.load(std::memory_order_relaxed);
        uint8_t* dst = buf;
        int urbTotalBytes = 0;
        const bool isPaused = paused_.load(std::memory_order_acquire);
        const size_t wNow = ringWrite_.load(std::memory_order_acquire);
        const size_t availNow = wNow - readFrame;
        if (!isPaused) {
            if (pullMode) {
                if (!prefillDone && pullRenderer_.prefillSatisfied()) {
                    prefillDone = true;
                    PULSR_USB_LOG(ANDROID_LOG_INFO,
                                  "pull prefill ready: fillMs=%d targetMs=%zu",
                                  pullRenderer_.fillMs(),
                                  pullRenderer_.configuredFrames() * 1000 /
                                      static_cast<size_t>(std::max(1, sampleRate_)));
                }
            } else if (!prefillDone) {
                if (availNow > 0 && !producerSeen) {
                    producerSeen = true;
                    prefillDeadline = std::chrono::steady_clock::now() +
                                      std::chrono::milliseconds(250);
                }
                if (availNow >= prefillFrames_ ||
                    (producerSeen && availNow > 0 &&
                     std::chrono::steady_clock::now() >= prefillDeadline)) {
                    prefillDone = true;
                    PULSR_USB_LOG(ANDROID_LOG_INFO,
                                  "prefill ready: fillMs=%.1f targetMs=%zu",
                                  sampleRate_ > 0
                                      ? static_cast<double>(availNow) * 1000.0 / sampleRate_
                                      : 0.0,
                                  prefillFrames_ * 1000 /
                                      static_cast<size_t>(std::max(1, sampleRate_)));
                }
            }
        }
        if (!isPaused && !pullMode && feedbackEndpoint_ == 0 && prefillDone) {
            // Steer against the operating window (~2x prefillFrames_), not the
            // full 1+ second physical ring capacity: ExoPlayer's AudioTrack
            // buffer caps producer lead at ~200-250 ms, which would otherwise
            // stay permanently below 20% of a 1.3 s ring and drag the rate down.
            const size_t steerWindow = std::min(
                ringFrames,
                std::max<size_t>(
                    prefillFrames_ * 2,
                    static_cast<size_t>(packetsPerUrb_ * maxFramesPerPacket_) * 4));
            feedbackRatePerSec_.store(
                SteerPacketRateForRingFill(
                    feedbackRatePerSec_.load(std::memory_order_relaxed),
                    sampleRate_, availNow, steerWindow),
                std::memory_order_relaxed);
        } else if (!isPaused &&
                   renderMode_ == static_cast<int>(UsbRenderMode::BitPerfectPull) &&
                   feedbackEndpoint_ == 0 && prefillDone) {
            // Whole-frame packet cadence steering for feedback-less UAC DACs in
            // BitPerfectPull mode: samples remain bit-identical while packet
            // lengths (e.g. 48 vs 47/49 frames) track the reservoir fill.
            const size_t pullAvail = pullRenderer_.availableFrames();
            const size_t pullWindow = pullRenderer_.configuredFrames();
            if (pullWindow > 0) {
                feedbackRatePerSec_.store(
                    SteerPacketRateForRingFill(
                        feedbackRatePerSec_.load(std::memory_order_relaxed),
                        sampleRate_, pullAvail, pullWindow),
                    std::memory_order_relaxed);
            }
        }
        const uint32_t ratePerSec =
            static_cast<uint32_t>(feedbackRatePerSec_.load(std::memory_order_relaxed));
        int rawDepth = -1;
        uint64_t deliveryEpoch = deliveryEpoch_.load(std::memory_order_acquire);
        const size_t frameBytes =
            static_cast<size_t>(channels_) * static_cast<size_t>(bytesPerSample_);
        const bool dsdStream = IsDsdMode(renderMode_);
        const bool dopSilence = !dsdStream &&
                                producerIsDop_.load(std::memory_order_relaxed) &&
                                IsDopSilenceContainer(bytesPerSample_);
        for (int p = 0; p < urb->number_of_packets; ++p) {
            const int framesInPacket = NextPacketFrames(
                frameAccumulator_, ratePerSec, serviceIntervalUs_, maxFramesPerPacket_);
            size_t pktLen = 0;
            if (!prefillDone || isPaused) {
                pktLen = static_cast<size_t>(framesInPacket) * frameBytes;
                if (pktLen > 0) {
                    if (dsdStream) {
                        // The cushion packets before the first producer block must
                        // already be valid DSD: zero words would be -FS, not silence.
                        dsdSilencePhase_ = FillDsdSilence(
                            dst, static_cast<int>(pktLen), dsdSilencePhase_);
                    } else if (dopSilence) {
                        dopMarkerPhase_ = FillDopSilence(
                            dst, framesInPacket, channels_, bytesPerSample_,
                            dopMarkerPhase_);
                    } else {
                        std::memset(dst, 0, pktLen);
                    }
                }
                // DSD silence is genuine DSD_U32 payload, so the depth marker
                // must not say "float" or the status surfaces would misreport a
                // DSD stream as a float one.
                rawDepth = dsdStream ? 32 : 0;
            } else if (renderMode_ == static_cast<int>(UsbRenderMode::BitPerfectPull)) {
                pktLen = fillPullPacket(dst, framesInPacket, rawDepth);
            } else if (renderMode_ == static_cast<int>(UsbRenderMode::ClockSyncAsrc)) {
                pktLen = fillAsrcPacket(dst, framesInPacket, rawDepth);
            } else {
                pktLen = fillPacketFromRing(
                    dst, framesInPacket, readFrame, rawDepth, deliveryEpoch);
            }
            urb->iso_frame_desc[p].length = static_cast<unsigned int>(pktLen);
            urb->iso_frame_desc[p].actual_length = 0;
            urb->iso_frame_desc[p].status = 0;
            dst += pktLen;
            urbTotalBytes += static_cast<int>(pktLen);
        }
        urb->buffer_length = urbTotalBytes;
        urb->status = 0;
        urb->actual_length = 0;
        urb->error_count = 0;
        urbRawDepth_[urbIndex] = std::max(rawDepth, 0);
        urbDeliveryEpoch_[urbIndex] = deliveryEpoch;
        if (!pullMode && !isPaused) ringRead_.store(readFrame, std::memory_order_release);

        if (!submitUrb(urb, false, urbIndex)) {
            ReportWriteError(errno);
            break;
        }
    }
    // Critical: set running_ and active_ to false on exit so sink never stays
    // in a zombie "playing but silent" state when the worker thread terminates.
    writerGate_.fetch_or(kWriterClosed, std::memory_order_acq_rel);
    deliveryEpoch_.fetch_add(1, std::memory_order_acq_rel);
    running_.store(false, std::memory_order_release);
    active_.store(false, std::memory_order_release);
}

void UsbAudioSink::ReportWriteError(int error) {
    lastError_.store(error == 0 ? EIO : error, std::memory_order_release);
    deliveryEpoch_.fetch_add(1, std::memory_order_acq_rel);
}

bool UsbAudioSink::beginWrite(int64_t producerId) {
    uint32_t expectedGate = 0;
    if (!writerGate_.compare_exchange_strong(expectedGate, kWriterBusy,
            std::memory_order_acquire, std::memory_order_relaxed)) {
        ReportWriteError((expectedGate & kWriterClosed) ? ENODEV : EBUSY);
        return false;
    }
    if (!active_.load(std::memory_order_acquire) || producerId == 0) {
        ReportWriteError(producerId == 0 ? EINVAL : ENODEV);
        endWrite();
        return false;
    }
    int64_t owner = 0;
    if (!producerOwner_.compare_exchange_strong(owner, producerId,
            std::memory_order_acq_rel, std::memory_order_acquire) && owner != producerId) {
        ReportWriteError(EBUSY);
        endWrite();
        return false;
    }
    return true;
}

void UsbAudioSink::endWrite() {
    writerGate_.fetch_and(~kWriterBusy, std::memory_order_release);
}

void UsbAudioSink::ReleaseProducer(int64_t id) {
    if (id == 0) return;
    int64_t expected = id;
    if (producerOwner_.compare_exchange_strong(expected, 0,
            std::memory_order_acq_rel, std::memory_order_relaxed)) {
        deliveryEpoch_.fetch_add(1, std::memory_order_acq_rel);
    }
}

void UsbAudioSink::SetPaused(bool paused) {
    paused_.store(paused, std::memory_order_release);
    pullRenderer_.setPaused(paused);
}

void UsbAudioSink::FlushStream() {
    if (!active_.load(std::memory_order_acquire)) return;
    // Wait briefly for any active producer write to finish before advancing read
    // pointer to write pointer (or flushing the pull reservoir).
    for (int spin = 0; spin < 200; ++spin) {
        if ((writerGate_.load(std::memory_order_acquire) & kWriterBusy) == 0) break;
        std::this_thread::yield();
    }
    const size_t w = ringWrite_.load(std::memory_order_acquire);
    ringRead_.store(w, std::memory_order_release);
    if (IsReservoirMode(renderMode_)) {
        pullRenderer_.flush();
    }
    deliveryEpoch_.fetch_add(1, std::memory_order_acq_rel);
}

bool UsbAudioSink::WriteInterleaved(const float* buffer, int frames, int channels,
                                    int sampleRate, int64_t producerId) {
    return writeBlock(buffer, nullptr, frames, channels, 0, sampleRate, producerId);
}

bool UsbAudioSink::WritePcm(const uint8_t* buffer, int frames, int channels,
                           int sourceBitDepth, int sampleRate, int64_t producerId) {
    if (sourceBitDepth != 16 && sourceBitDepth != 24 && sourceBitDepth != 32) {
        ReportWriteError(EINVAL);
        return false;
    }
    return writeBlock(nullptr, buffer, frames, channels, sourceBitDepth, sampleRate, producerId);
}

bool UsbAudioSink::WriteDsd(const uint8_t* left, const uint8_t* right,
                            int bytesPerChannel, int64_t producerId) {
    if (left == nullptr || right == nullptr || bytesPerChannel <= 0 ||
        bytesPerChannel > kMaxDsdBytesPerCall) {
        ReportWriteError(EINVAL);
        return false;
    }
    // Every PCM mode refuses 1-bit payloads: there is no PCM reading of a DSD
    // byte string, and a silent reinterpretation would be worse than a refusal.
    if (!dsdMode_.load(std::memory_order_acquire)) {
        ReportWriteError(ENOTSUP);
        return false;
    }
    if (!beginWrite(producerId)) return false;
    struct WriterExit {
        UsbAudioSink* sink;
        ~WriterExit() { sink->endWrite(); }
    } exit{this};
    // One wire frame is one 32-bit word per channel, so a 4-byte subslot turns
    // 4 DSD bytes into one frame; a trailing partial word is zero-padded on its
    // high side by the packer (never sign-extended, never dithered).
    const int frames = (bytesPerChannel + bytesPerSample_ - 1) / bytesPerSample_;
    const size_t capFrames = ringRawDepth_.size();
    const size_t frameBytes =
        static_cast<size_t>(channels_) * static_cast<size_t>(bytesPerSample_);
    size_t w = ringWrite_.load(std::memory_order_relaxed);
    const size_t r = ringRead_.load(std::memory_order_acquire);
    const size_t occupiedFrames = w - r;
    const size_t freeFrames = capFrames > occupiedFrames ? capFrames - occupiedFrames - 1 : 0;
    if (capFrames == 0 || static_cast<size_t>(frames) > freeFrames) {
        // All-or-nothing exactly like WritePcm: a half-delivered DSD block would
        // splice a truncated word into the bitstream and shift every later word.
        overrunCount_.fetch_add(static_cast<uint64_t>(frames), std::memory_order_relaxed);
        ReportWriteError(ENOSPC);
        return false;
    }
    for (int f = 0; f < frames; ++f) {
        const int offset = f * bytesPerSample_;
        const int chunk = std::min(bytesPerSample_, bytesPerChannel - offset);
        const size_t slot = w & ringFrameMask_;
        // 32 = "these words are raw 32-bit payload, not float". The worker uses
        // it to skip dither/fade/requantisation on the packet.
        ringRawDepth_[slot] = 32;
        uint8_t* frameDst = ring_.data() + slot * frameBytes;
        uint8_t wordL[4] = {0, 0, 0, 0};
        uint8_t wordR[4] = {0, 0, 0, 0};
        PackDsdBitsToWords(left + offset, chunk, wordL, bytesPerSample_, bytesPerSample_);
        PackDsdBitsToWords(right + offset, chunk, wordR, bytesPerSample_, bytesPerSample_);
        std::memcpy(frameDst, wordL, static_cast<size_t>(bytesPerSample_));
        std::memcpy(frameDst + bytesPerSample_, wordR, static_cast<size_t>(bytesPerSample_));
        ++w;
    }
    producerRawDepth_.store(32, std::memory_order_release);
    ringWrite_.store(w, std::memory_order_release);
    return true;
}

bool UsbAudioSink::writeBlock(const float* floats, const uint8_t* pcm, int frames,
        int channels, int sourceBitDepth, int sampleRate, int64_t producerId) {
    // PCM producer calls are refused outright while a native-DSD stream is live.
    // Packing a float or integer PCM block into the DSD ring would dither/gain
    // words the DAC reads as bitstream - full-scale noise, not audio - so the
    // only honest answer is a clean refusal.
    if (dsdMode_.load(std::memory_order_acquire)) {
        ReportWriteError(ENOTSUP);
        return false;
    }
    if ((!floats && !pcm) || frames <= 0 || channels <= 0 || channels > 8) {
        ReportWriteError(EINVAL);
        return false;
    }
    if (!beginWrite(producerId)) return false;
    struct WriterExit {
        UsbAudioSink* sink;
        ~WriterExit() { sink->endWrite(); }
    } exit{this};
    // Rate-limited rejection diagnostics: a silent ring while the status says
    // "streaming" is invisible otherwise, and the reason is one of these three.
    const auto rejectLog = [&](const char* reason) {
        const auto nowNs = std::chrono::steady_clock::now().time_since_epoch().count();
        const int64_t prevNs = lastRejectLogNs_.load(std::memory_order_relaxed);
        if (prevNs != 0 && (nowNs - prevNs) < 1'000'000'000LL) return;
        lastRejectLogNs_.store(nowNs, std::memory_order_relaxed);
        PULSR_USB_LOG(ANDROID_LOG_WARN,
                      "write rejected (%s): frames=%d ch=%d/%d rate=%d/%d "
                      "depth=%d/%d lastError=%d",
                      reason, frames, channels, channels_, sampleRate, sampleRate_,
                      sourceBitDepth, validBitDepth_, lastError_.load());
    };
    if (channels != channels_) {
        channelMismatchFrames_.fetch_add(static_cast<uint64_t>(frames), std::memory_order_relaxed);
        ReportWriteError(EINVAL);
        rejectLog("channels");
        return false; // no duplication, silence-fill, drop, or remap
    }
    if (sampleRate != sampleRate_ || sourceBitDepth > validBitDepth_) {
        ReportWriteError(ERANGE);
        rejectLog(sampleRate != sampleRate_ ? "rate" : "depth");
        return false; // no implicit SRC or lossy valid-depth reduction
    }
    if (renderMode_ == static_cast<int>(UsbRenderMode::BitPerfectPull)) {
        // Bit-perfect pull stores the wire bytes exactly as the producer wrote
        // them. A float block (e.g. when software directUsbGain < 1.0 scaled
        // the stream on a DAC without hardware volume) or a different valid
        // depth cannot be claimed as sample-identical, so it disqualifies the
        // bit-perfect badge while still rendering audio instead of dropping out.
        if (!pcm && floats != nullptr) {
            bitPerfectDisqualified_.store(true, std::memory_order_release);
            bitPerfectEligible_.store(false, std::memory_order_release);
            if (static_cast<size_t>(frames) > pullPackFrames_) {
                ReportWriteError(ENOTSUP);
                rejectLog("pull_block_too_large");
                return false;
            }
            const size_t fb = static_cast<size_t>(channels_) *
                              static_cast<size_t>(bytesPerSample_);
            for (int f = 0; f < frames; ++f) {
                for (int c = 0; c < channels_; ++c) {
                    const size_t sample = static_cast<size_t>(f) * channels_ + c;
                    uint8_t packed[4] = {0, 0, 0, 0};
                    PackPcmSample(floats[sample], packed, bytesPerSample_,
                                  producerDither_, validBitDepth_);
                    std::memcpy(pullPack_.data() + static_cast<size_t>(f) * fb +
                                    static_cast<size_t>(c) * bytesPerSample_,
                                packed, static_cast<size_t>(bytesPerSample_));
                }
            }
            if (!pullRenderer_.write(pullPack_.data(), frames)) {
                overrunCount_.fetch_add(static_cast<uint64_t>(frames),
                                        std::memory_order_relaxed);
                ReportWriteError(ENOSPC);
                return false;
            }
            producerRawDepth_.store(0, std::memory_order_release);
            deliveryEpoch_.fetch_add(1, std::memory_order_acq_rel);
            return true;
        }
        if (!pcm || sourceBitDepth <= 0 || sourceBitDepth > validBitDepth_) {
            bitPerfectDisqualified_.store(true, std::memory_order_release);
            bitPerfectEligible_.store(false, std::memory_order_release);
            ReportWriteError(ENOTSUP);
            rejectLog(!pcm ? "float_in_pull" : "depth");
            return false;
        }
        const int srcBytes = sourceBitDepth / 8;
        const void* payload = pcm;
        if (srcBytes != bytesPerSample_) {
            // A wider container is allowed only as zero padding: repack the
            // source's valid bits into the wire subslot, exactly as the
            // BestEffort path does. The sample values are unchanged.
            if (static_cast<size_t>(frames) > pullPackFrames_) {
                bitPerfectDisqualified_.store(true, std::memory_order_release);
                bitPerfectEligible_.store(false, std::memory_order_release);
                ReportWriteError(ENOTSUP);
                rejectLog("pull_block_too_large");
                return false;
            }
            const size_t fb = static_cast<size_t>(channels_) *
                              static_cast<size_t>(bytesPerSample_);
            for (int f = 0; f < frames; ++f) {
                for (int c = 0; c < channels_; ++c) {
                    const size_t sample = static_cast<size_t>(f) * channels_ + c;
                    uint8_t packed[4] = {0, 0, 0, 0};
                    PackRawPcmSample(pcm + sample * static_cast<size_t>(srcBytes),
                                     sourceBitDepth, packed, bytesPerSample_,
                                     validBitDepth_);
                    std::memcpy(pullPack_.data() + static_cast<size_t>(f) * fb +
                                    static_cast<size_t>(c) * bytesPerSample_,
                                packed, static_cast<size_t>(bytesPerSample_));
                }
            }
            payload = pullPack_.data();
        }
        if (!pullRenderer_.write(payload, frames)) {
            overrunCount_.fetch_add(static_cast<uint64_t>(frames), std::memory_order_relaxed);
            ReportWriteError(ENOSPC);
            return false;
        }
        producerRawDepth_.store(sourceBitDepth, std::memory_order_release);
        deliveryEpoch_.fetch_add(1, std::memory_order_acq_rel);
        // Eligibility is earned by a full, bit-identical packet pull, not by a
        // write: claiming before any payload reached the wire would be a lie.
        return true;
    }
    if (renderMode_ == static_cast<int>(UsbRenderMode::ClockSyncAsrc)) {
        // The ASRC path is float-only by design: a decoded float block can be
        // resampled without inventing integer bits, while a raw integer block
        // would have to be reinterpreted first. Refuse it visibly.
        // ASRC is a resampling path, so an integer source is legal: convert it
        // to float first (the same scale the engine uses), then resample. The
        // conversion is exact for 16/24-bit integer grids and is never claimed
        // as bit-perfect.
        if (!floats) {
            if (!pcm || frames > static_cast<int>(asrcRawScratchFrames_) ||
                (sourceBitDepth != 16 && sourceBitDepth != 24 && sourceBitDepth != 32)) {
                asrcRawPcmRejected_.fetch_add(static_cast<uint64_t>(frames),
                                              std::memory_order_relaxed);
                ReportWriteError(ENOTSUP);
                rejectLog("pcm_in_asrc");
                return false;
            }
            const int srcBytes = sourceBitDepth / 8;
            const float scale = 1.0f / static_cast<float>(1u << (sourceBitDepth - 1));
            for (int f = 0; f < frames; ++f) {
                for (int c = 0; c < channels_; ++c) {
                    const uint8_t* src = pcm +
                        (static_cast<size_t>(f) * channels_ + c) * static_cast<size_t>(srcBytes);
                    int64_t value = 0;
                    for (int b = 0; b < srcBytes; ++b) {
                        value |= static_cast<int64_t>(src[b]) << (8 * b);
                    }
                    const int shift = 32 - sourceBitDepth;
                    value = (value << shift) >> shift;  // sign-extend in 64-bit
                    asrcRawScratch_[static_cast<size_t>(f) * channels_ + c] =
                        static_cast<float>(value) * scale;
                }
            }
            if (!pullRenderer_.write(asrcRawScratch_.data(), frames)) {
                overrunCount_.fetch_add(static_cast<uint64_t>(frames), std::memory_order_relaxed);
                ReportWriteError(ENOSPC);
                return false;
            }
        } else if (!pullRenderer_.write(floats, frames)) {
            overrunCount_.fetch_add(static_cast<uint64_t>(frames), std::memory_order_relaxed);
            ReportWriteError(ENOSPC);
            return false;
        }
        producerRawDepth_.store(0, std::memory_order_release);
        deliveryEpoch_.fetch_add(1, std::memory_order_acq_rel);
        return true;
    }
    const size_t capFrames = ringRawDepth_.size();
    const size_t frameBytes = static_cast<size_t>(channels_) * bytesPerSample_;
    size_t w = ringWrite_.load(std::memory_order_relaxed);
    const size_t r = ringRead_.load(std::memory_order_acquire);
    const size_t occupiedFrames = w - r;
    const size_t freeFrames = capFrames > occupiedFrames ? capFrames - occupiedFrames - 1 : 0;
    if (capFrames == 0 || static_cast<size_t>(frames) > freeFrames) {
        overrunCount_.fetch_add(static_cast<uint64_t>(frames), std::memory_order_relaxed);
        ReportWriteError(ENOSPC);
        return false; // all-or-nothing: never report a partially delivered block
    }
    const int sourceBytes = sourceBitDepth / 8;
    for (int f = 0; f < frames; ++f) {
        const size_t slot = w & ringFrameMask_;
        ringRawDepth_[slot] = static_cast<uint8_t>(sourceBitDepth);
        uint8_t* frameDst = ring_.data() + slot * frameBytes;
        for (int c = 0; c < channels_; ++c) {
            const size_t sample = static_cast<size_t>(f) * channels_ + c;
            uint8_t packed[4];
            if (pcm) {
                PackRawPcmSample(pcm + sample * sourceBytes, sourceBitDepth, packed,
                                 bytesPerSample_, validBitDepth_);
            } else {
                PackPcmSample(floats[sample], packed, bytesPerSample_, producerDither_, validBitDepth_);
            }
            for (int b = 0; b < bytesPerSample_; ++b) {
                frameDst[static_cast<size_t>(c) * bytesPerSample_ + b] = packed[b];
            }
        }
        ++w;
    }
    producerRawDepth_.store(sourceBitDepth, std::memory_order_release);
    if (sourceBitDepth == 0) deliveryEpoch_.fetch_add(1, std::memory_order_acq_rel);
    ringWrite_.store(w, std::memory_order_release);
    return true;
}

size_t UsbAudioSink::fillPullPacket(uint8_t* dst, int framesInPacket, int& rawDepth) {
    const size_t frameBytes =
        static_cast<size_t>(channels_) * static_cast<size_t>(bytesPerSample_);
    const int got = pullRenderer_.pullExact(dst, framesInPacket);
    if (got < framesInPacket) {
        // pullExact zero-fills the remainder. A gap means the wire stream is no
        // longer a byte-for-byte copy of the source, so the session loses its
        // bit-perfect eligibility even if it recovers.
        underrunCount_.fetch_add(1, std::memory_order_relaxed);
        bitPerfectDisqualified_.store(true, std::memory_order_release);
        bitPerfectEligible_.store(false, std::memory_order_release);
    } else if (producerRawDepth_.load(std::memory_order_acquire) > 0) {
        bitPerfectEligible_.store(
            !bitPerfectDisqualified_.load(std::memory_order_acquire),
            std::memory_order_release);
    }
    // Report the producer's valid depth, not the container width: a 16-bit
    // source in a 24-bit subslot is still a 16-bit sample stream.
    rawDepth = producerRawDepth_.load(std::memory_order_acquire);
    return static_cast<size_t>(framesInPacket) * frameBytes;
}

size_t UsbAudioSink::fillAsrcPacket(uint8_t* dst, int framesInPacket, int& rawDepth) {
    if (framesInPacket <= 0 || channels_ <= 0) {
        rawDepth = 0;
        return 0;
    }
    asrc_.setRatio(computeAsrcRatio());
    const size_t ch = static_cast<size_t>(channels_);
    const size_t frameBytes = ch * static_cast<size_t>(bytesPerSample_);
    const int packCapFrames = static_cast<int>(asrcPack_.size() / ch);
    const int targetFrames = std::min(framesInPacket, packCapFrames);
    int produced = 0;
    const size_t outCapacityFrames = asrcOut_.size() / ch;
    while (produced < targetFrames) {
        if (asrcOutAvail_ > 0) {
            const int take = std::min(targetFrames - produced, asrcOutAvail_);
            std::memcpy(asrcPack_.data() + static_cast<size_t>(produced) * ch,
                        asrcOut_.data(), static_cast<size_t>(take) * ch * sizeof(float));
            produced += take;
            asrcOutAvail_ -= take;
            if (asrcOutAvail_ > 0) {
                std::memmove(asrcOut_.data(),
                             asrcOut_.data() + static_cast<size_t>(take) * ch,
                             static_cast<size_t>(asrcOutAvail_) * ch * sizeof(float));
            }
            if (produced >= targetFrames) break;
        }
        const int got = pullRenderer_.pull(asrcIn_.data(),
                                          static_cast<int>(asrcInputCapacityFrames_));
        if (got <= 0) break;
        const size_t outRoom = outCapacityFrames - static_cast<size_t>(asrcOutAvail_);
        const int made = asrc_.process(
            asrcIn_.data(), got,
            asrcOut_.data() + static_cast<size_t>(asrcOutAvail_) * ch,
            static_cast<int>(outRoom));
        asrcOutAvail_ += made;
        if (made == 0) break;  // needs more input than one chunk can supply
    }
    if (produced < targetFrames) {
        std::memset(asrcPack_.data() + static_cast<size_t>(produced) * ch, 0,
                    static_cast<size_t>(targetFrames - produced) * ch * sizeof(float));
        underrunCount_.fetch_add(1, std::memory_order_relaxed);
    }
    for (int f = 0; f < targetFrames; ++f) {
        for (size_t c = 0; c < ch; ++c) {
            uint8_t packed[4] = {0, 0, 0, 0};
            PackPcmSample(asrcPack_[static_cast<size_t>(f) * ch + c], packed,
                          bytesPerSample_, workerDither_, validBitDepth_);
            std::memcpy(dst + static_cast<size_t>(f) * frameBytes +
                            c * static_cast<size_t>(bytesPerSample_),
                        packed, static_cast<size_t>(bytesPerSample_));
        }
    }
    if (targetFrames < framesInPacket) {
        std::memset(dst + static_cast<size_t>(targetFrames) * frameBytes, 0,
                    static_cast<size_t>(framesInPacket - targetFrames) * frameBytes);
        underrunCount_.fetch_add(1, std::memory_order_relaxed);
    }
    // Resampled output is never a raw-integer copy, regardless of the source.
    rawDepth = 0;
    return static_cast<size_t>(framesInPacket) * frameBytes;
}

double UsbAudioSink::GetBufferedMs() {
    std::lock_guard<std::mutex> control(controlMutex_); // status/control, not render
    if (!active_.load(std::memory_order_acquire)) return 0.0;
    if (IsReservoirMode(renderMode_)) {
        return static_cast<double>(pullRenderer_.fillMs());
    }
    const size_t w = ringWrite_.load(std::memory_order_acquire);
    const size_t r = ringRead_.load(std::memory_order_acquire);
    const size_t countFrames = w - r;
    const double ringMs = sampleRate_ > 0
        ? static_cast<double>(countFrames) * 1000.0 / static_cast<double>(sampleRate_)
        : 0.0;
    const double urbMs = static_cast<double>(numUrbs_ * packetsPerUrb_) * serviceIntervalUs_ / 1000.0;
    return ringMs + urbMs;
}

void UsbAudioSink::SetStreamTuning(int transferSizeBytes, int bufferMs,
                                   bool disableExplicitFeedback) {
    std::lock_guard<std::mutex> control(controlMutex_);
    // Control-thread state for the next Open(): recording it now must never
    // disturb a stream that is already running (Open reads it once).
    tunedTransferSizeBytes_ = transferSizeBytes > 0 ? transferSizeBytes : 0;
    // A reservoir longer than 10 s cannot improve clock lock and turns a seek
    // into a multi-second flush; 0 keeps the automatic 3000 ms target.
    tunedBufferMs_ = bufferMs > 0 ? std::min(bufferMs, kMaxTunedBufferMs) : 0;
    disableExplicitFeedback_ = disableExplicitFeedback;
}

bool UsbAudioSink::StartPcmFile(const std::string& path) {
    std::lock_guard<std::mutex> control(controlMutex_);
    if (!active_.load(std::memory_order_acquire) ||
        renderMode_ != static_cast<int>(UsbRenderMode::BitPerfectPull)) {
        return false;
    }
    if (pcmProducer_) {
        pcmProducer_->stop();
        pcmProducer_.reset();
    }
    auto producer = std::make_unique<UsbPcmProducer>();
    const UsbPcmFormat target{sampleRate_, channels_, bytesPerSample_, validBitDepth_};
    const int reservoirMs = tunedBufferMs_ > 0 ? tunedBufferMs_ : 3000;
    if (!producer->open(path, target, pullRenderer_, reservoirMs,
                       /*configureRenderer=*/true)) {
        ReportWriteError(EINVAL);
        return false;
    }
    producer->start();
    pcmProducer_ = std::move(producer);
    return true;
}

void UsbAudioSink::StopPcmFile() {
    std::lock_guard<std::mutex> control(controlMutex_);
    if (pcmProducer_) {
        pcmProducer_->stop();
        pcmProducer_.reset();
    }
}

bool UsbAudioSink::HasPcmFileSource() const {
    std::lock_guard<std::mutex> control(controlMutex_);
    return pcmProducer_ != nullptr && pcmProducer_->isOpen();
}

UsbStreamResult UsbAudioSink::CheckStreamShape(UsbRenderMode mode, int channels,
                                               int bytesPerSample, int validBitDepth,
                                               int framesPerSecond) {
    const int effectiveBits = validBitDepth == 0 && bytesPerSample >= 2 && bytesPerSample <= 4
        ? bytesPerSample * 8 : validBitDepth;
    if (mode == UsbRenderMode::DsdNative) {
        // DSD_U32 is the only native-DSD wire shape this sink speaks: one 32-bit
        // word per channel per frame, so a 4-byte subslot at 32 valid bits and a
        // stereo pair. Anything else is a PCM request wearing a DSD mode.
        if (bytesPerSample != 4 || effectiveBits != 32 || channels != 2) {
            return UsbStreamResult::InvalidArgs;
        }
        // The frame rate *is* the DSD clock: 88200/176400/352800/705600 for
        // DSD64/128/256/512. A rate off that ladder (48 kHz family, DSD1024,
        // plain PCM rates) has no native-DSD packing this sink can honour.
        if (DsdRateForAltSetting(framesPerSecond, bytesPerSample) == 0) {
            return UsbStreamResult::RateUnsupported;
        }
        return UsbStreamResult::Ok;
    }
    if (mode != UsbRenderMode::BestEffort && mode != UsbRenderMode::BitPerfectPull &&
        mode != UsbRenderMode::ClockSyncAsrc) {
        return UsbStreamResult::InvalidArgs;  // unknown wire value: caller bug
    }
    if (channels <= 0 || channels > 8 ||
        !IsPcmWireFormat(bytesPerSample, effectiveBits)) {
        return UsbStreamResult::InvalidArgs;
    }
    if (framesPerSecond <= 0) return UsbStreamResult::RateUnsupported;
    static const int kValidRates[] = {44100, 48000, 88200, 96000, 176400, 192000, 352800, 384000, 705600, 768000};
    for (int r : kValidRates) {
        if (framesPerSecond == r) return UsbStreamResult::Ok;
    }
    return UsbStreamResult::RateUnsupported;
}

UsbClockDomain UsbAudioSink::DeriveClockDomain(UsbRenderMode mode, bool active,
                                               bool bitPerfectEligible,
                                               uint64_t underruns,
                                               uint64_t channelMismatch) {
    if (!active) return UsbClockDomain::Unknown;
    switch (mode) {
        case UsbRenderMode::ClockSyncAsrc:
            // The resampler *is* the clock domain by construction: samples are
            // no longer the bits the producer wrote, whatever the source is.
            return UsbClockDomain::Asrc;
        case UsbRenderMode::BitPerfectPull:
        case UsbRenderMode::DsdNative:
            // Both are BitPerfect-shaped: payloads stay sample-identical only
            // while the session was never disqualified, nothing had to be
            // zero-filled, and no channel mismatch was ever summed into the wire
            // stream. DsdNative reuses the same rule instead of a private one so
            // a DSD stream can never claim more than the pull path does.
            return (bitPerfectEligible && underruns == 0 && channelMismatch == 0)
                ? UsbClockDomain::BitPerfectLocked
                : UsbClockDomain::BestEffort;
        case UsbRenderMode::BestEffort:
            break;
    }
    return UsbClockDomain::BestEffort;
}

UsbClockStatus UsbAudioSink::GetClockStatus() const {
    std::lock_guard<std::mutex> control(controlMutex_);
    UsbClockStatus status;
    const bool active = active_.load(std::memory_order_acquire);
    status.underrunCount = underrunCount_.load(std::memory_order_relaxed);
    // Raw PCM refused by the float-only ASRC path is a producer/output format
    // mismatch, so it is reported where the UI already looks for stream faults
    // rather than being folded into silence. Zero outside that path.
    status.overrunCount = overrunCount_.load(std::memory_order_relaxed) +
        asrcRawPcmRejected_.load(std::memory_order_relaxed);
    // No pull session can be live while its engine is unlinked, so a session is
    // never bit-perfect eligible here; the pull path will supply the real flag.
    status.domain = DeriveClockDomain(
        static_cast<UsbRenderMode>(renderMode_), active,
        bitPerfectEligible_.load(std::memory_order_acquire), status.underrunCount,
        channelMismatchFrames_.load(std::memory_order_relaxed));
    if (!active || sampleRate_ <= 0) return status;

    status.feedbackPresent = feedbackEndpoint_ != 0;
    if (IsReservoirMode(renderMode_)) {
        status.ringFillMs = pullRenderer_.fillMs();
    } else {
        const size_t written = ringWrite_.load(std::memory_order_acquire);
        const size_t read = ringRead_.load(std::memory_order_acquire);
        const uint64_t fillMs = static_cast<uint64_t>(written - read) * 1000ull /
                                static_cast<uint64_t>(sampleRate_);
        status.ringFillMs = static_cast<int>(std::min<uint64_t>(
            fillMs, static_cast<uint64_t>(std::numeric_limits<int>::max())));
    }
    // Positive means the producer clock is running fast relative to the DAC:
    // the rate the feedback loop (or the ring-steering fallback) is currently
    // asking the packet cadence to reach, against nominal.
    const double drift =
        (static_cast<double>(feedbackRatePerSec_.load(std::memory_order_relaxed)) -
         static_cast<double>(sampleRate_)) * 1e6 / static_cast<double>(sampleRate_);
    status.clockDriftPpm = static_cast<int>(
        std::lround(std::clamp(drift, -1000000.0, 1000000.0)));
    return status;
}

int UsbAudioSink::WaitForWriteSpace(int frames, int maxWaitMs) {
    if (frames <= 0) return -1;
    const auto checkOnce = [this, frames]() -> int {
        uint32_t gate = 0;
        if (!writerGate_.compare_exchange_strong(
                gate, kWriterBusy,
                std::memory_order_acq_rel, std::memory_order_acquire)) {
            return -1;
        }
        int status = -1;
        if (exclusive_.load(std::memory_order_acquire) &&
            active_.load(std::memory_order_acquire)) {
            const size_t neededFrames = static_cast<size_t>(frames);
            if (IsReservoirMode(renderMode_)) {
                // Pull modes answer from their own reservoir, not ring_: the
                // ring stays empty there and would always report "space free".
                const size_t capacity = pullRenderer_.capacityFrames();
                const size_t available = pullRenderer_.availableFrames();
                if (capacity > available) {
                    const size_t freeFrames = capacity - available;
                    status = (neededFrames <= freeFrames) ? 0 : 1;
                }
            } else {
                const size_t capFrames = ringRawDepth_.size();
                if (capFrames > 1 && neededFrames <= capFrames - 1) {
                    const size_t w = ringWrite_.load(std::memory_order_relaxed);
                    const size_t r = ringRead_.load(std::memory_order_acquire);
                    const size_t occupiedFrames = w - r;
                    const size_t freeFrames =
                        capFrames > occupiedFrames ? capFrames - occupiedFrames - 1 : 0;
                    status = (neededFrames <= freeFrames) ? 0 : 1;
                }
            }
        }
        writerGate_.fetch_and(~kWriterBusy, std::memory_order_release);
        return status;
    };

    int res = checkOnce();
    if (res <= 0 || maxWaitMs <= 0) return res;
    const auto deadline = std::chrono::steady_clock::now() +
                          std::chrono::milliseconds(maxWaitMs);
    while (res == 1 && std::chrono::steady_clock::now() < deadline) {
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
        res = checkOnce();
    }
    return res;
}

bool UsbAudioSink::NeedsPrefillCushion() const {
    if (!exclusive_.load(std::memory_order_acquire) ||
        !active_.load(std::memory_order_acquire)) {
        return false;
    }
    if (IsReservoirMode(renderMode_)) {
        if (!pullRenderer_.prefillSatisfied()) return true;
        const size_t configured = pullRenderer_.configuredFrames();
        return configured > 0 && pullRenderer_.availableFrames() < (configured / 2);
    }
    const size_t w = ringWrite_.load(std::memory_order_acquire);
    const size_t r = ringRead_.load(std::memory_order_acquire);
    const size_t avail = w >= r ? (w - r) : 0;
    return prefillFrames_ > 0 && avail < prefillFrames_;
}

bool UsbAudioSink::setupFeedbackUrbs() {
#if defined(__linux__) || defined(__ANDROID__)
    if (feedbackEndpoint_ == 0 || fd_ < 0) return false;
    if (feedbackPacketSize_ != 3 && feedbackPacketSize_ != 4) {
        lastError_.store(EINVAL, std::memory_order_release);
        return false;
    }
    numFeedbackUrbs_ = 2;
    feedbackPacketsPerUrb_ = 4;
    feedbackUrbStride_ = sizeof(struct usbdevfs_urb) +
                         static_cast<size_t>(feedbackPacketsPerUrb_) *
                             sizeof(struct usbdevfs_iso_packet_desc);
    feedbackUrbStride_ = (feedbackUrbStride_ + 7u) & ~static_cast<size_t>(7u);

    feedbackUrbStorage_.assign(feedbackUrbStride_ * numFeedbackUrbs_, 0);
    feedbackBuffers_.assign(numFeedbackUrbs_, nullptr);
    feedbackUrbs_.assign(numFeedbackUrbs_, nullptr);
    feedbackOwned_.assign(numFeedbackUrbs_, 0);
    const int fbBufBytes = feedbackPacketSize_ * feedbackPacketsPerUrb_;

    // Phase 1: allocate + initialize every URB (kernel owns none of them yet).
    for (int i = 0; i < numFeedbackUrbs_; ++i) {
        auto* urb = reinterpret_cast<struct usbdevfs_urb*>(
            feedbackUrbStorage_.data() + static_cast<size_t>(i) * feedbackUrbStride_);
        feedbackBuffers_[i] = new (std::nothrow) uint8_t[fbBufBytes]();
        if (!feedbackBuffers_[i]) {
            lastError_.store(ENOMEM, std::memory_order_release);
            return false; // caller rolls back OUT as well as unsubmitted IN
        }
        std::memset(urb, 0, sizeof(struct usbdevfs_urb));
        urb->type = USBDEVFS_URB_TYPE_ISO;
        urb->endpoint = static_cast<unsigned char>(feedbackEndpoint_);
        urb->flags = USBDEVFS_URB_ISO_ASAP;
        urb->buffer = feedbackBuffers_[i];
        urb->number_of_packets = feedbackPacketsPerUrb_;
        urb->usercontext = urb;
        for (int p = 0; p < feedbackPacketsPerUrb_; ++p) {
            urb->iso_frame_desc[p].length = static_cast<unsigned int>(feedbackPacketSize_);
            urb->iso_frame_desc[p].actual_length = 0;
            urb->iso_frame_desc[p].status = 0;
        }
        urb->buffer_length = fbBufBytes;
        feedbackUrbs_[i] = urb;
    }
    // On failure Open aborts the entire startup. Unified teardown tracks each
    // OUT/IN identity, so an OUT completion can never count as a reaped IN.
    for (int i = 0; i < numFeedbackUrbs_; ++i) {
        if (!submitUrb(feedbackUrbs_[i], true, static_cast<size_t>(i))) {
            lastError_.store(errno, std::memory_order_release);
            return false;
        }
    }
    return true;
#else
    return false;
#endif
}

void UsbAudioSink::applyFeedback(const uint8_t* data, int len) {
    const int decoded = DecodeFeedbackRatePerSec(data, len, sampleRate_);
    if (decoded > 0) {
        feedbackRatePerSec_.store(decoded, std::memory_order_relaxed);
    }
}

int UsbAudioSink::DecodeFeedbackRatePerSec(const uint8_t* data, int len, int nominalRate) {
    if (data == nullptr || nominalRate <= 0 || (len != 3 && len != 4)) return 0;

    // Express the DAC's request as a ratio to nominal, independent of the
    // frame/microframe time base:
    //   * 3-byte feedback (full-speed) is Q10.14 samples per 1 ms frame.
    //   * 4-byte feedback (high-speed) is Q16.16 samples per 125 us microframe.
    // ratio = reported-samples-per-interval / nominal-samples-per-interval.
    double ratio;
    if (len >= 4) {
        const uint32_t v = static_cast<uint32_t>(data[0]) |
                           (static_cast<uint32_t>(data[1]) << 8) |
                           (static_cast<uint32_t>(data[2]) << 16) |
                           (static_cast<uint32_t>(data[3]) << 24);
        if (v == 0) return 0;
        const double samplesPerMicroframe = static_cast<double>(v) / 65536.0;
        const double nominalPerMicroframe = static_cast<double>(nominalRate) / 8000.0;
        if (nominalPerMicroframe <= 0.0) return 0;
        ratio = samplesPerMicroframe / nominalPerMicroframe;
    } else {
        const uint32_t v = static_cast<uint32_t>(data[0]) |
                           (static_cast<uint32_t>(data[1]) << 8) |
                           (static_cast<uint32_t>(data[2]) << 16);
        if (v == 0) return 0;
        const double samplesPerFrame = static_cast<double>(v) / 16384.0;
        const double nominalPerFrame = static_cast<double>(nominalRate) / 1000.0;
        if (nominalPerFrame <= 0.0) return 0;
        ratio = samplesPerFrame / nominalPerFrame;
    }

    // Reject an implausible decode (buggy device / wrong fixed-point format): a
    // real async DAC deviates from nominal by only tens of ppm.
    if (ratio < 0.90 || ratio > 1.10) return 0;

    double target = static_cast<double>(nominalRate) * ratio;
    // Hard safety clamp to +/-0.1% of nominal: far above any real crystal error
    // yet far below anything that could run the ring away within one session.
    const double lo = static_cast<double>(nominalRate) * 0.999;
    const double hi = static_cast<double>(nominalRate) * 1.001;
    if (target < lo) target = lo;
    if (target > hi) target = hi;
    return static_cast<int>(target + 0.5);
}

UsbAudioSink::EndpointTiming UsbAudioSink::ParseEndpointTiming(
        const uint8_t* desc, size_t len, int interfaceNumber, int altSetting,
        int endpointAddress, int usbSpeed) {
    const bool fullSpeed = usbSpeed == 2;
    const bool highSpeed = usbSpeed == 3;
    const bool superSpeed = usbSpeed == 5 || usbSpeed == 6;
    if (desc == nullptr || (!fullSpeed && !highSpeed && !superSpeed)) return {};
    bool selectedInterface = false;
    for (size_t i = 0; i + 2 <= len;) {
        const size_t length = desc[i];
        if (length < 2 || length > len - i) return {};
        const uint8_t type = desc[i + 1];
        if (type == 0x04) {
            if (length < 9) return {};
            const uint8_t ifClass = desc[i + 5];
            const uint8_t ifProtocol = desc[i + 7];
            const bool isAudioClass = ifClass == 0x01 ||
                (ifClass == 0xFF && (ifProtocol == 0x00 || ifProtocol == 0x20));
            selectedInterface = desc[i + 2] == interfaceNumber &&
                desc[i + 3] == altSetting && isAudioClass && desc[i + 6] == 0x02;
        } else if (type == 0x05 && selectedInterface) {
            if (length < 7) return {};
            if (desc[i + 2] == endpointAddress) {
                const int attributes = desc[i + 3];
                const int interval = desc[i + 6];
                if ((endpointAddress & 0x80) != 0 || (attributes & 0x03) != 0x01 ||
                    (attributes & 0x30) == 0x10 || interval < 1 || interval > 16) return {};
                const int packet = desc[i + 4] | (desc[i + 5] << 8);
                const int payload = packet & 0x07ff;
                const int transactions = (packet >> 11) & 0x03;
                if ((packet & 0xe000) != 0 || payload <= 0 ||
                    payload > (fullSpeed ? 1023 : 1024) ||
                    (highSpeed ? transactions == 3 : transactions != 0)) return {};
                int capacity = payload * (transactions + 1);
                if (superSpeed) {
                    const size_t companion = i + length;
                    if (companion + 6 > len || desc[companion] < 6 ||
                        desc[companion] > len - companion || desc[companion + 1] != 0x30) return {};
                    const int burst = desc[companion + 2];
                    const int mult = desc[companion + 3] & 0x03;
                    const int bytesPerInterval = desc[companion + 4] | (desc[companion + 5] << 8);
                    if (burst > 15 || mult > 2 || bytesPerInterval <= 0 ||
                        bytesPerInterval > payload * (burst + 1) * (mult + 1)) return {};
                    capacity = bytesPerInterval;
                }
                // bInterval is an exponent. Audio isochronous endpoints use
                // 1 ms (FS) or 125 us (HS/SS); a malformed descriptor can ask
                // for a multi-second service interval, which no URB schedule
                // can carry. Reject anything above 10 ms instead of opening a
                // stream that would starve.
                const int intervalUs =
                    (fullSpeed ? 1000 : 125) * (1 << (interval - 1));
                if (intervalUs <= 0 || intervalUs > 10000) return {};
                return {intervalUs, capacity};
            }
        }
        i += length;
    }
    return {};
}

int UsbAudioSink::NextPacketFrames(uint64_t& accumulator, uint32_t ratePerSec,
                                   int intervalUs, int maxFramesPerPacket) {
    if (intervalUs <= 0 || maxFramesPerPacket <= 0) return 0;
    accumulator += static_cast<uint64_t>(ratePerSec) * static_cast<uint64_t>(intervalUs);
    const uint64_t frames = accumulator / 1000000;
    accumulator %= 1000000;
    return static_cast<int>(std::min(frames, static_cast<uint64_t>(maxFramesPerPacket)));
}

int UsbAudioSink::SteerPacketRateForRingFill(int currentRatePerSec, int nominalRate,
                                             size_t occupiedBytes, size_t capacityBytes) {
    if (nominalRate <= 0) return currentRatePerSec;
    // +/-1% of nominal. Cheap feedback-less DACs commonly run their crystal
    // 0.2-0.6% off the host clock; a +/-0.1% window saturates almost immediately
    // and leaves the ring to gap-fill every ~80 s. 1% is still far below an
    // audible pitch shift, yet wide enough to hold lock for a whole session.
    const int deltaMax = std::max(1, nominalRate / 100); // +/-1% clamp
    const int minRate = std::max(1, nominalRate - deltaMax);
    const int maxRate = nominalRate + deltaMax;
    int rate = (currentRatePerSec > 0)
        ? std::clamp(currentRatePerSec, minRate, maxRate)
        : nominalRate;
    if (capacityBytes == 0) return rate;
    const size_t clampedOccupied = std::min(occupiedBytes, capacityBytes);
    const int fillPermille = static_cast<int>(
        (static_cast<uint64_t>(clampedOccupied) * 1000ULL) / capacityBytes);
    const int step = std::max(1, deltaMax / 48);
    if (fillPermille < 200) {
        rate = std::max(minRate, rate - step);
    } else if (fillPermille > 800) {
        rate = std::min(maxRate, rate + step);
    } else if (fillPermille >= 300 && fillPermille <= 700) {
        if (rate < nominalRate) {
            rate = std::min(nominalRate, rate + step);
        } else if (rate > nominalRate) {
            rate = std::max(nominalRate, rate - step);
        }
    }
    return std::clamp(rate, minRate, maxRate);
}

std::vector<int> UsbAudioSink::ParseSupportedRatesFromDescriptors(
    const uint8_t* desc, size_t len, int targetInterface) {
    if (!desc || len < 8) return {};

    std::vector<int> rates;
    // Range guard for discrete FORMAT_TYPE_I rates. The band is wider than the
    // standard-rate table so a DAC advertising e.g. 32 kHz or 22.05 kHz keeps
    // its real capability, but an arbitrary 24-bit field cannot become one.
    constexpr int kMinPlausibleRate = 8000;
    constexpr int kMaxPlausibleRate = 1536000;
    constexpr int kStandardRates[] = {
        44100, 48000, 88200, 96000, 176400, 192000, 352800, 384000, 705600, 768000
    };

    size_t i = 0;
    int currentInterface = -1;
    int currentClass = 0;
    int currentSubclass = 0;

    while (i + 2 <= len) {
        uint8_t bLength = desc[i];
        if (bLength < 2 || i + bLength > len) {
            i++;
            continue;
        }
        uint8_t bType = desc[i + 1];

        if (bType == 0x04) { // DESC_INTERFACE
            if (bLength >= 9) {
                currentInterface = desc[i + 2];
                currentClass = desc[i + 5];
                currentSubclass = desc[i + 6];
            }
        } else if (bType == 0x24 && bLength >= 3) { // DESC_CS_INTERFACE
            if (currentClass == 0x01 && currentSubclass == 0x02 &&
                (targetInterface < 0 || currentInterface == targetInterface)) {
                // AudioStreaming CS_INTERFACE
                uint8_t bSubtype = desc[i + 2];
                if (bSubtype == 0x02 && bLength >= 8) { // FORMAT_TYPE
                    uint8_t bFormatType = desc[i + 3];
                    if (bFormatType == 0x01) { // FORMAT_TYPE_I (UAC1)
                        uint8_t bSamFreqType = desc[i + 7];
                        if (bSamFreqType == 0 && bLength >= 14) {
                            // Continuous sample rate range
                            int lower = desc[i + 8] | (desc[i + 9] << 8) | (desc[i + 10] << 16);
                            int upper = desc[i + 11] | (desc[i + 12] << 8) | (desc[i + 13] << 16);
                            for (int r : kStandardRates) {
                                if (r >= lower && r <= upper) {
                                    rates.push_back(r);
                                }
                            }
                        } else if (bSamFreqType > 0) {
                            // Discrete sample rates
                            for (uint8_t k = 0; k < bSamFreqType; ++k) {
                                size_t offset = i + 8 + 3 * k;
                                if (offset + 3 <= i + bLength) {
                                    int r = desc[offset] | (desc[offset + 1] << 8) | (desc[offset + 2] << 16);
                                    // A discrete wSamFreq field is three bytes; a
                                    // malformed or hostile descriptor can put any
                                    // 24-bit value there. Only a plausible audio
                                    // rate is a capability: 8 kHz..1.536 MHz. The
                                    // fuzz suite found the old `r > 0` check echoing
                                    // 15 MHz values into status.
                                    if (r >= kMinPlausibleRate && r <= kMaxPlausibleRate) {
                                        rates.push_back(r);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        i += bLength;
    }

    std::sort(rates.begin(), rates.end());
    rates.erase(std::unique(rates.begin(), rates.end()), rates.end());
    return rates;
}

} // namespace pulsr
