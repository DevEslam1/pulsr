// android/app/src/main/cpp/UsbAudioSink.cpp
#include "UsbAudioSink.h"
#include "AudioDspEngine.h"
#include "SinkQuantizer.h"

#if defined(__ANDROID__)
#include <android/log.h>
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
#include <new>

namespace pulsr {

namespace {
constexpr int kNumUrbs = 4;
constexpr int kTargetUrbDurationUs = 8000;
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
    Close();
    if (hasOutstandingUrbs()) {
        // A fatal reap error is not proof of returned kernel ownership. Keep
        // header allocations and payloads alive even at static destruction.
        // Payload pointers deliberately leak; moving storage preserves addresses.
        (void)new std::vector<uint8_t>(std::move(urbStorage_));
        (void)new std::vector<uint8_t>(std::move(feedbackUrbStorage_));
    }
}

bool UsbAudioSink::IsActive() const {
    return active_.load(std::memory_order_acquire);
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
                                   int bytesPerSample, int validBitDepth) {
    std::lock_guard<std::mutex> control(controlMutex_);
    const int effectiveBits = validBitDepth == 0 && bytesPerSample >= 2 && bytesPerSample <= 4
        ? bytesPerSample * 8 : validBitDepth;
    if (fd < 0 || interfaceNumber < 0 || altSetting < 0 || channels <= 0 ||
        channels > 8 || !IsPcmWireFormat(bytesPerSample, effectiveBits)) {
        ReportWriteError(EINVAL);
        return UsbStreamResult::InvalidArgs;
    }
    if (sampleRate <= 0) {
        ReportWriteError(EINVAL);
        return UsbStreamResult::RateUnsupported;
    }
    static const int kValidRates[] = {44100, 48000, 88200, 96000, 176400, 192000, 352800, 384000, 705600, 768000};
    bool validRate = false;
    for (int r : kValidRates) {
        if (sampleRate == r) {
            validRate = true;
            break;
        }
    }
    if (!validRate) {
        ReportWriteError(EINVAL);
        return UsbStreamResult::RateUnsupported;
    }
    // Isochronous OUT endpoint: addresses 1-15 with the IN bit clear. Checked
    // after the rate so an unsupported rate keeps reporting itself.
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
    releaseResources(); // also tears down a worker that self-exited
    if (hasOutstandingUrbs()) {
        lastError_.store(EBUSY, std::memory_order_release);
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
    producerDither_ = {};
    workerDither_ = {};
    gapFader_.configure(sampleRate, channels, bytesPerSample_);

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
    feedbackEndpoint_ = findFeedbackEndpoint(config.data(), config.size(),
                                             interfaceNumber_, altSetting_,
                                             &feedbackPacketSize_);
    if (feedbackEndpoint_ < 0) {
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
    // Claim the AudioStreaming interface (force: detaches the kernel audio
    // driver so the HAL can no longer own the endpoint) and select the alt
    // setting that exposes the isochronous OUT endpoint.
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

    const int maxBytesPerPacket = maxFramesPerPacket_ * frameBytes;
    bytesPerPacket_ = maxBytesPerPacket;
    packetsPerUrb_ = std::max(1, kTargetUrbDurationUs / serviceIntervalUs_);
    bytesPerUrb_ = maxBytesPerPacket * packetsPerUrb_;

    // Packet-sizing / feedback state consumed by the worker thread.
    frameAccumulator_ = 0;
    feedbackRatePerSec_ = sampleRate_;  // nominal until a feedback sample arrives

    // Power-of-two ring buffer capacity for mask-based indexing (at least 250ms slack).
    const size_t targetRingBytes = std::max(
        static_cast<size_t>(bytesPerUrb_) * 32,
        static_cast<size_t>(sampleRate_ * channels_ * bytesPerSample_ / 4));
    size_t cap = 2048;
    while (cap < targetRingBytes) cap <<= 1;
    ring_.assign(cap, 0);
    ringRawDepth_.assign(cap, 0);
    ringMask_ = cap - 1;
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
    producerOwner_.store(0, std::memory_order_release);
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

void UsbAudioSink::Close() {
    std::lock_guard<std::mutex> control(controlMutex_);
    writerGate_.fetch_or(kWriterClosed, std::memory_order_acq_rel);
    // Always stop and join the worker, even if it already self-exited: a
    // joinable std::thread must never be reassigned (Open) or destroyed
    // (destructor), both of which call std::terminate().
    running_.store(false, std::memory_order_release);
    active_.store(false, std::memory_order_release);

    if (worker_.joinable()) {
        worker_.join();
    }

    releaseResources();
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

bool UsbAudioSink::drainUrbCompletions() {
#if defined(__linux__) || defined(__ANDROID__)
    if (!hasOutstandingUrbs()) return true;
    if (fd_ < 0) {
        ReportWriteError(EBADF);
        return false;
    }
    for (size_t i = 0; i < urbs_.size(); ++i) {
        if (urbOwned_[i]) ioctl(fd_, USBDEVFS_DISCARDURB, urbs_[i]);
    }
    for (size_t i = 0; i < feedbackUrbs_.size(); ++i) {
        if (feedbackOwned_[i]) ioctl(fd_, USBDEVFS_DISCARDURB, feedbackUrbs_[i]);
    }
    // Teardown is control-thread only. Cancellation has no safe timeout: a
    // submitted header/payload stays allocated until that exact URB is reaped.
    while (hasOutstandingUrbs()) {
        struct usbdevfs_urb* urb = nullptr;
        if (ioctl(fd_, USBDEVFS_REAPURB, &urb) < 0) {
            if (errno == EINTR) continue;
            if (errno == EAGAIN || errno == EINPROGRESS) {
                std::this_thread::sleep_for(std::chrono::milliseconds(1));
                continue;
            }
            lastError_.store(errno, std::memory_order_release);
            return false; // retain ALL storage; error is not an ownership proof
        }
        bool feedback = false;
        size_t index = 0;
        if (!markReaped(urb, &feedback, &index)) {
            // The claimed interface is exclusive. Unknown completions cannot
            // be safely requeued or counted as our cancellation acknowledgments.
            lastError_.store(EPROTO, std::memory_order_release);
        }
    }
#endif
    return !hasOutstandingUrbs();
}

// ---- Async feedback (anti-drift) support, FIX 2 ----

std::vector<uint8_t> UsbAudioSink::fetchConfigDescriptor(int fd) {
#if defined(__linux__) || defined(__ANDROID__)
    if (fd < 0) return {};
    // GET_DESCRIPTOR(CONFIG): first read 4 bytes to learn wTotalLength, then the
    // whole configuration (same control request QuerySupportedRates uses).
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
    cfg.resize(static_cast<size_t>(res));
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
            selected = cfg[i + 2] == interfaceNumber && cfg[i + 3] == altSetting &&
                cfg[i + 5] == 0x01 && cfg[i + 6] == 0x02;
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

void UsbAudioSink::releaseResources() {
    writerGate_.fetch_or(kWriterClosed, std::memory_order_acq_rel);
    active_.store(false, std::memory_order_release);
    while (writerGate_.load(std::memory_order_acquire) & kWriterBusy) {
        std::this_thread::yield(); // control only; never free a live writer's ring
    }
    producerOwner_.store(0, std::memory_order_release);
    producerRawDepth_.store(0, std::memory_order_release);
    deliveryEpoch_.fetch_add(1, std::memory_order_acq_rel);
    rawPcmStatus_.store(0, std::memory_order_release);
    if (sinkDepthPublished_) {
        DspEngineRegistry::instance().setSinkBitDepth(0);
        sinkDepthPublished_ = false; // clear even after the worker self-exited
    }

    if (!drainUrbCompletions()) return; // preserve kernel-owned buffers on failure

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
    ringMask_ = 0;
    if (claimed_ && fd_ >= 0) {
        int iface = interfaceNumber_;
        ioctl(fd_, USBDEVFS_RELEASEINTERFACE, &iface);
#if defined(__linux__) || defined(__ANDROID__)
        // Re-attach the kernel snd-usb-audio driver so system audio routing and ALSA recover immediately
        struct usbdevfs_ioctl cmd {};
        cmd.ifno = interfaceNumber_;
        cmd.ioctl_code = USBDEVFS_CONNECT;
        cmd.data = nullptr;
        ioctl(fd_, USBDEVFS_IOCTL, &cmd);
#endif
    }
    claimed_ = false;
    fd_ = -1;
    running_.store(false, std::memory_order_release);
    exclusive_.store(false, std::memory_order_release); // only after USB ownership is drained
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

void UsbAudioSink::workerLoop() {
#if defined(__linux__) || defined(__ANDROID__)
    // Java's Process.THREAD_PRIORITY_URGENT_AUDIO is nice -19. usbfs URB
    // completion latency is directly in the playback path; best effort because
    // some kernels refuse the negative nice for app threads.
    setpriority(PRIO_PROCESS, 0, -19);
#endif
    const int frameBytes = channels_ * bytesPerSample_;
    int repeatedReadyPolls = 0;
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
                feedbackRatePerSec_ = sampleRate_;
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
            break; // short/error OUT is not successfully delivered audio
        }
        rawPcmStatus_.store((urbDeliveryEpoch_[urbIndex] << 8) |
            static_cast<uint64_t>(urbRawDepth_[urbIndex]), std::memory_order_release);

        // OUT URB: recompute every packet length from the fractional sample
        // accumulator stepped by the current (feedback-adjusted) rate, clamped
        // to maxFramesPerPacket_ so the preallocated buffer can never overflow.
        uint8_t* buf = reinterpret_cast<uint8_t*>(urb->buffer);
        const size_t mask = ringMask_;
        size_t readPos = ringRead_.load(std::memory_order_relaxed);
        uint8_t* dst = buf;
        int urbTotalBytes = 0;
        const uint32_t ratePerSec = static_cast<uint32_t>(feedbackRatePerSec_);
        int rawDepth = -1;
        uint64_t deliveryEpoch = deliveryEpoch_.load(std::memory_order_acquire);
        for (int p = 0; p < urb->number_of_packets; ++p) {
            const int framesInPacket = NextPacketFrames(
                frameAccumulator_, ratePerSec, serviceIntervalUs_, maxFramesPerPacket_);
            const size_t pktLen = static_cast<size_t>(framesInPacket) * frameBytes;

            const size_t w = ringWrite_.load(std::memory_order_acquire);
            const size_t avail = w - readPos; // unsigned sequence arithmetic also survives counter wrap
            if (pktLen > 0 && avail >= pktLen) {
                for (size_t i = 0; i < pktLen; ++i) {
                    dst[i] = ring_[(readPos + i) & mask];
                }
                bool packetRaw = false;
                for (int f = 0; f < framesInPacket; ++f) {
                    const int depth = ringRawDepth_[(readPos + static_cast<size_t>(f) * frameBytes) & mask];
                    packetRaw = packetRaw || depth != 0;
                    if (rawDepth == -1) rawDepth = depth;
                    else if (rawDepth != depth) rawDepth = 0;
                }
                readPos += pktLen;
                if (packetRaw) {
                    // A recovery ramp must never requantize raw S32 (or DoP).
                    gapFader_.reset();
                } else if (gapFader_.recovering()) {
                    rawDepth = 0;
                }
                gapFader_.applyReal(dst, framesInPacket, workerDither_);
            } else if (pktLen > 0) {
                // Raw/DoP gaps must be silence, not synthesized marker/audio
                // bytes. Processed PCM retains the existing click-reducing fade.
                if (producerRawDepth_.load(std::memory_order_acquire) != 0) {
                    std::memset(dst, 0, pktLen);
                    gapFader_.reset();
                } else {
                    gapFader_.fillGap(dst, framesInPacket, workerDither_);
                }
                rawDepth = 0;
                deliveryEpoch = deliveryEpoch_.fetch_add(1, std::memory_order_acq_rel) + 1;
                underrunCount_.fetch_add(1, std::memory_order_relaxed);
            }
            // Fades work in the subslot grid. Requantize to valid bits instead
            // of biased low-byte truncation; already-on-grid/raw PCM stays exact.
            if (validBitDepth_ < bytesPerSample_ * 8) {
                for (size_t sample = 0; sample < pktLen; sample += bytesPerSample_) {
                    RequantizePcmValidBits(dst + sample, bytesPerSample_, validBitDepth_, workerDither_);
                }
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
        ringRead_.store(readPos, std::memory_order_release);

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

bool UsbAudioSink::writeBlock(const float* floats, const uint8_t* pcm, int frames,
        int channels, int sourceBitDepth, int sampleRate, int64_t producerId) {
    if ((!floats && !pcm) || frames <= 0 || channels <= 0 || channels > 8) {
        ReportWriteError(EINVAL);
        return false;
    }
    if (!beginWrite(producerId)) return false;
    struct WriterExit {
        UsbAudioSink* sink;
        ~WriterExit() { sink->endWrite(); }
    } exit{this};
    if (channels != channels_) {
        channelMismatchFrames_.fetch_add(static_cast<uint64_t>(frames), std::memory_order_relaxed);
        ReportWriteError(EINVAL);
        return false; // no duplication, silence-fill, drop, or remap
    }
    if (sampleRate != sampleRate_ || sourceBitDepth > validBitDepth_) {
        ReportWriteError(ERANGE);
        return false; // no implicit SRC or lossy valid-depth reduction
    }
    const size_t cap = ring_.size();
    const size_t frameBytes = static_cast<size_t>(channels_) * bytesPerSample_;
    size_t w = ringWrite_.load(std::memory_order_relaxed);
    const size_t r = ringRead_.load(std::memory_order_acquire);
    const size_t occupied = w - r;
    const size_t space = cap > occupied ? cap - occupied - 1 : 0;
    if (cap == 0 || static_cast<size_t>(frames) > space / frameBytes) {
        overrunCount_.fetch_add(static_cast<uint64_t>(frames), std::memory_order_relaxed);
        ReportWriteError(ENOSPC);
        return false; // all-or-nothing: never report a partially delivered block
    }
    const int sourceBytes = sourceBitDepth / 8;
    for (int f = 0; f < frames; ++f) {
        ringRawDepth_[w & ringMask_] = static_cast<uint8_t>(sourceBitDepth);
        for (int c = 0; c < channels_; ++c) {
            const size_t sample = static_cast<size_t>(f) * channels_ + c;
            uint8_t packed[4];
            if (pcm) {
                PackRawPcmSample(pcm + sample * sourceBytes, sourceBitDepth, packed,
                                 bytesPerSample_, validBitDepth_);
            } else {
                PackPcmSample(floats[sample], packed, bytesPerSample_, producerDither_, validBitDepth_);
            }
            for (int b = 0; b < bytesPerSample_; ++b) ring_[(w + b) & ringMask_] = packed[b];
            w += bytesPerSample_;
        }
    }
    producerRawDepth_.store(sourceBitDepth, std::memory_order_release);
    if (sourceBitDepth == 0) deliveryEpoch_.fetch_add(1, std::memory_order_acq_rel);
    ringWrite_.store(w, std::memory_order_release);
    return true;
}

double UsbAudioSink::GetBufferedMs() {
    std::lock_guard<std::mutex> control(controlMutex_); // status/control, not render
    if (!active_.load(std::memory_order_acquire)) return 0.0;
    const size_t w = ringWrite_.load(std::memory_order_acquire);
    const size_t r = ringRead_.load(std::memory_order_acquire);
    const size_t count = (w >= r) ? (w - r) : 0;
    const int frameBytes = channels_ * bytesPerSample_;
    const double ringMs = frameBytes > 0 && sampleRate_ > 0
        ? static_cast<double>(count) * 1000.0 / (frameBytes * sampleRate_) : 0.0;
    const double urbMs = static_cast<double>(numUrbs_ * packetsPerUrb_) * serviceIntervalUs_ / 1000.0;
    return ringMs + urbMs;
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
    if (decoded > 0) feedbackRatePerSec_ = decoded;
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
            selectedInterface = desc[i + 2] == interfaceNumber &&
                desc[i + 3] == altSetting && desc[i + 5] == 0x01 && desc[i + 6] == 0x02;
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
                return {(fullSpeed ? 1000 : 125) * (1 << (interval - 1)), capacity};
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

std::vector<int> UsbAudioSink::ParseSupportedRatesFromDescriptors(
    const uint8_t* desc, size_t len, int targetInterface) {
    if (!desc || len < 8) return {};

    std::vector<int> rates;
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
                                    if (r > 0) {
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

std::vector<int> UsbAudioSink::QuerySupportedRates(int fd, int interfaceNumber) {
#if defined(__linux__) || defined(__ANDROID__)
    if (fd < 0) return {};

    uint8_t header[4] = {0};
    struct usbdevfs_ctrltransfer ctrl {};
    ctrl.bRequestType = 0x80; // USB_DIR_IN | USB_TYPE_STANDARD | USB_RECIP_DEVICE
    ctrl.bRequest = 0x06;     // USB_REQ_GET_DESCRIPTOR
    ctrl.wValue = 0x0200;     // (USB_DT_CONFIG << 8) | 0
    ctrl.wIndex = 0;
    ctrl.wLength = sizeof(header);
    ctrl.timeout = 1000;
    ctrl.data = header;

    if (ioctl(fd, USBDEVFS_CONTROL, &ctrl) < 0) {
        return {};
    }

    uint16_t totalLength = static_cast<uint16_t>(header[2] | (header[3] << 8));
    if (totalLength < 9 || totalLength > 16384) {
        totalLength = 4096;
    }

    std::vector<uint8_t> configDesc(totalLength);
    ctrl.wLength = totalLength;
    ctrl.data = configDesc.data();

    int res = ioctl(fd, USBDEVFS_CONTROL, &ctrl);
    if (res < 0) {
        return {};
    }
    configDesc.resize(static_cast<size_t>(res));

    std::vector<int> rates = ParseSupportedRatesFromDescriptors(
        configDesc.data(), configDesc.size(), interfaceNumber);

    // Scan for UAC2 Clock Source entities and query sample rates
    int acInterface = 0;
    std::vector<uint8_t> clockIds;
    size_t dIdx = 0;
    while (dIdx + 2 <= configDesc.size()) {
        uint8_t bLength = configDesc[dIdx];
        if (bLength < 2 || dIdx + bLength > configDesc.size()) break;
        uint8_t bType = configDesc[dIdx + 1];
        if (bType == 0x04 && bLength >= 9) { // DESC_INTERFACE
            if (configDesc[dIdx + 5] == 0x01 && configDesc[dIdx + 6] == 0x01) {
                acInterface = configDesc[dIdx + 2]; // AudioControl interface
            }
        } else if (bType == 0x24 && bLength >= 8) { // CS_INTERFACE
            if (configDesc[dIdx + 2] == 0x0B) { // CLOCK_SOURCE
                clockIds.push_back(configDesc[dIdx + 3]); // bClockID
            }
        }
        dIdx += bLength;
    }

    for (uint8_t clockId : clockIds) {
        uint8_t rangeBuf[256] = {0};
        struct usbdevfs_ctrltransfer rangeCtrl {};
        rangeCtrl.bRequestType = 0xA1; // IN | CLASS | INTERFACE
        rangeCtrl.bRequest = 0x02;     // UAC2 RANGE
        rangeCtrl.wValue = 0x0100;     // CS_SAM_FREQ_CONTROL (0x01) << 8
        rangeCtrl.wIndex = static_cast<uint16_t>((clockId << 8) | acInterface);
        rangeCtrl.wLength = sizeof(rangeBuf);
        rangeCtrl.timeout = 1000;
        rangeCtrl.data = rangeBuf;

        if (ioctl(fd, USBDEVFS_CONTROL, &rangeCtrl) >= 2) {
            uint16_t numRanges = rangeBuf[0] | (rangeBuf[1] << 8);
            size_t offset = 2;
            for (uint16_t r = 0; r < numRanges && offset + 12 <= sizeof(rangeBuf); ++r) {
                uint32_t dMin = rangeBuf[offset] | (rangeBuf[offset + 1] << 8) |
                                (rangeBuf[offset + 2] << 16) | (rangeBuf[offset + 3] << 24);
                uint32_t dMax = rangeBuf[offset + 4] | (rangeBuf[offset + 5] << 8) |
                                (rangeBuf[offset + 6] << 16) | (rangeBuf[offset + 7] << 24);
                if (dMin == dMax && dMin > 0) {
                    rates.push_back(static_cast<int>(dMin));
                } else if (dMin < dMax) {
                    constexpr int kStandardRates[] = {
                        44100, 48000, 88200, 96000, 176400, 192000, 352800, 384000, 705600, 768000
                    };
                    for (int sr : kStandardRates) {
                        if (static_cast<uint32_t>(sr) >= dMin && static_cast<uint32_t>(sr) <= dMax) {
                            rates.push_back(sr);
                        }
                    }
                }
                offset += 12;
            }
        }
    }

    if (!rates.empty()) {
        std::sort(rates.begin(), rates.end());
        rates.erase(std::unique(rates.begin(), rates.end()), rates.end());
        return rates;
    }

    // Fallback: If no UAC1 rates detected (e.g. UAC2 DAC), probe standard high-res rates
    return {44100, 48000, 88200, 96000, 176400, 192000, 352800, 384000, 705600, 768000};
#else
    (void)fd;
    (void)interfaceNumber;
    return {44100, 48000, 88200, 96000, 176400, 192000, 352800, 384000, 705600, 768000};
#endif
}

} // namespace pulsr
