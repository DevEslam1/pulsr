// android/app/src/test/cpp/test_usb_sink.cpp
//
// No physical DAC is required: pure descriptor/feedback/sizing helpers and
// producer transport are exercised on the host. Startup submission uses an
// injected syscall in the production ownership path; Open's real usbfs claim,
// descriptor I/O, and asynchronous kernel cancellation still need hardware.
#include "../../main/cpp/UsbAudioSink.h"
#include "../../main/cpp/AudioDspEngine.h"

#include <atomic>
#include <cerrno>
#include <cmath>
#include <cstdint>
#include <limits>
#include <thread>
#if defined(__linux__) || defined(__ANDROID__)
#include <linux/usbdevice_fs.h>
#else
// Layout mirrors the non-Linux usbfs mock in UsbAudioSink.cpp.
struct usbdevfs_urb {
    unsigned char type, endpoint;
    int status;
    unsigned int flags;
    void* buffer;
    int buffer_length, actual_length, start_frame, number_of_packets, error_count;
    unsigned int signr;
    void* usercontext;
    struct Packet { unsigned int length, actual_length, status; } iso_frame_desc[2];
};
#endif
#include <cstring>
#include <cstdlib>
#include <new>
#include <iostream>
#include <vector>

static std::atomic<uint64_t> gAllocations{0};
void* operator new(std::size_t size) {
    gAllocations.fetch_add(1, std::memory_order_relaxed);
    if (void* p = std::malloc(size ? size : 1)) return p;
    throw std::bad_alloc();
}
void* operator new[](std::size_t size) { return ::operator new(size); }
void operator delete(void* p) noexcept { std::free(p); }
void operator delete[](void* p) noexcept { std::free(p); }
void operator delete(void* p, std::size_t) noexcept { std::free(p); }
void operator delete[](void* p, std::size_t) noexcept { std::free(p); }

// Identity addresses shared by the injected-reap regressions below. They are never
// dereferenced: the sink only compares completion pointers for identity.
static int gUsbUrbIdentityOut = 0;
static int gUsbUrbIdentityIn = 0;
static int gUsbStrangerUrb = 0;
static int gReapScript = 0;

// P2-4: a live usbfs endpoint whose DAC never returns a URB. Captureless, so it
// converts to UsbAudioSink::UrbReap regardless of which thread runs the drain.
int reapNever(int, void**) {
    errno = EAGAIN;
    return -1;
}

// P3-8: one unrecognized completion, then every URB this sink submitted. The
// stray completion must not leave lastError_ = EPROTO latched afterwards.
int reapScripted(int, void** urb) {
    switch (gReapScript++) {
        case 0: *urb = &gUsbStrangerUrb; return 0;
        case 1: *urb = &gUsbUrbIdentityOut; return 0;
        case 2: *urb = &gUsbUrbIdentityIn; return 0;
        default: errno = EAGAIN; return -1;
    }
}

// A queue that keeps reporting a completion this sink does not own (duplicate or
// foreign pointer). It always "succeeds", so only the deadline can end the loop.
int reapAlwaysForeign(int, void** urb) {
    *urb = &gUsbStrangerUrb;
    return 0;
}

using pulsr::UsbAudioSink;

namespace pulsr {
struct UsbAudioSinkTestAccess {
    static void prepare(UsbAudioSink& sink, int bytes = 4, int bits = 32,
                        size_t capacityBytes = 128, size_t positionBytes = 0) {
        sink.Close();
        sink.sampleRate_ = 48000;
        sink.channels_ = 2;
        sink.bytesPerSample_ = bytes;
        sink.validBitDepth_ = bits;
        const size_t frameBytes =
            static_cast<size_t>(sink.channels_) * static_cast<size_t>(sink.bytesPerSample_);
        const size_t capFrames = std::max<size_t>(2, capacityBytes / frameBytes);
        const size_t posFrames = positionBytes / frameBytes;
        sink.ring_.assign(capFrames * frameBytes, 0xAA);
        sink.ringRawDepth_.assign(capFrames, 0);
        sink.ringFrameMask_ = capFrames - 1;
        sink.ringRead_.store(posFrames);
        sink.ringWrite_.store(posFrames);
        sink.gapFader_.reset();
        sink.underrunCount_.store(0);
        sink.producerOwner_.store(0);
        sink.producerRawDepth_.store(0);
        sink.lastError_.store(0);
        sink.channelMismatchFrames_.store(0);
        sink.exclusive_.store(true);
        sink.active_.store(true);
        sink.writerGate_.store(0);
    }
    static size_t written(UsbAudioSink& sink) {
        const size_t frameBytes =
            static_cast<size_t>(sink.channels_) * static_cast<size_t>(sink.bytesPerSample_);
        return sink.ringWrite_.load() * frameBytes;
    }
    static std::vector<uint8_t> bytes(UsbAudioSink& sink, size_t startByte, size_t count) {
        const size_t capBytes = sink.ring_.size();
        std::vector<uint8_t> out(count);
        for (size_t i = 0; i < count; ++i) out[i] = sink.ring_[(startByte + i) % capBytes];
        return out;
    }
    static void preparePull(UsbAudioSink& sink, int mode, int bufferMs) {
        sink.renderMode_ = mode;
        sink.sampleRate_ = 48000;
        sink.channels_ = 2;
        sink.bytesPerSample_ = 2;
        sink.validBitDepth_ = 16;
        sink.maxFramesPerPacket_ = 480;
        sink.frameAccumulator_ = 0;
        sink.underrunCount_.store(0);
        sink.overrunCount_.store(0);
        sink.channelMismatchFrames_.store(0);
        sink.bitPerfectEligible_.store(false);
        sink.asrcRawPcmRejected_.store(0);
        sink.active_.store(true);
        sink.exclusive_.store(true);
        sink.writerGate_.store(0);
        sink.producerOwner_.store(0);
        sink.producerRawDepth_.store(mode == 1 ? 16 : 0);
        const int storageBytes = mode == 2 ? 4 : 2;
        sink.pullRenderer_.Configure(48000, 2, storageBytes, bufferMs);
        sink.asrcOutAvail_ = 0;
        if (mode == 2) {
            sink.asrc_.configure(2, 32, 256);
            const size_t packetFloor = 2048;
            sink.asrcOut_.assign((packetFloor + 64) * 2, 0.0f);
            sink.asrcPack_.assign(packetFloor * 2, 0.0f);
            sink.asrcInputCapacityFrames_ = 1024;
            sink.asrcIn_.assign(1024 * 2, 0.0f);
            sink.asrcRawScratchFrames_ = 8192;
            sink.asrcRawScratch_.assign(8192 * 2, 0.0f);
        }
    }
    static bool writePull(UsbAudioSink& sink, const void* src, int frames) {
        return sink.pullRenderer_.write(src, frames);
    }
    static size_t fillPull(UsbAudioSink& sink, uint8_t* dst, int frames, int& depth) {
        return sink.fillPullPacket(dst, frames, depth);
    }
    static size_t fillAsrc(UsbAudioSink& sink, uint8_t* dst, int frames, int& depth) {
        return sink.fillAsrcPacket(dst, frames, depth);
    }
    static bool writeRawAsrc(UsbAudioSink& sink, const uint8_t* pcm, int frames,
                             int depth) {
        return sink.writeBlock(nullptr, pcm, frames, sink.channels_, depth,
                               sink.sampleRate_, 7);
    }
    static size_t underruns(UsbAudioSink& sink) {
        return sink.underrunCount_.load();
    }
    static bool eligible(UsbAudioSink& sink) {
        return sink.bitPerfectEligible_.load();
    }
    static void markEligible(UsbAudioSink& sink) {
        sink.bitPerfectEligible_.store(true);
    }
    static void stopPull(UsbAudioSink& sink) {
        sink.active_.store(false);
        sink.exclusive_.store(false);
        sink.sinkDepthPublished_ = false;
        sink.renderMode_ = 0;
    }

    static size_t fillPacket(UsbAudioSink& sink, uint8_t* dst, int framesInPacket,
                             int& rawDepth, uint64_t& deliveryEpoch) {
        size_t r = sink.ringRead_.load(std::memory_order_relaxed);
        const size_t writtenBytes =
            sink.fillPacketFromRing(dst, framesInPacket, r, rawDepth, deliveryEpoch);
        sink.ringRead_.store(r, std::memory_order_release);
        return writtenBytes;
    }
    static size_t ringRawDepthBytes(const UsbAudioSink& sink) { return sink.ringRawDepth_.size(); }
    static int tunedTransferBytes(const UsbAudioSink& sink) { return sink.tunedTransferSizeBytes_; }
    static int tunedBufferMs(const UsbAudioSink& sink) { return sink.tunedBufferMs_; }
    static bool feedbackDisabled(const UsbAudioSink& sink) { return sink.disableExplicitFeedback_; }
    static uint64_t underrunCount(const UsbAudioSink& sink) { return sink.underrunCount_.load(); }
    static bool enter(UsbAudioSink& sink, int64_t id) { return sink.beginWrite(id); }
    static void leave(UsbAudioSink& sink) { sink.endWrite(); }
    static bool closed(UsbAudioSink& sink) { return (sink.writerGate_.load() & sink.kWriterClosed) != 0; }
    static void delivered(UsbAudioSink& sink, int depth, uint64_t epoch) {
        sink.rawPcmStatus_.store((epoch << 8) | static_cast<uint64_t>(depth));
    }
    static uint64_t epoch(UsbAudioSink& sink) { return sink.deliveryEpoch_.load(); }
    static bool clearRegistryAfterWorkerExit(UsbAudioSink& sink) {
        DspEngineRegistry::instance().setSinkBitDepth(24);
        sink.sinkDepthPublished_ = true;
        sink.exclusive_.store(true);
        sink.active_.store(false); // worker self-exited, but control must clear
        const bool mutedUntilTeardown = sink.IsExclusive();
        sink.Close();
        auto probe = std::make_unique<AudioDspEngine>();
        if (!DspEngineRegistry::instance().registerEngine(probe.get())) return false;
        const bool cleared = probe->getSinkBitDepth() == 0 && mutedUntilTeardown && !sink.IsExclusive();
        DspEngineRegistry::instance().unregisterEngine(probe.get());
        return cleared;
    }
    // P2-2/P2-4: stage a stream whose drain failed - submitted OUT/IN identities,
    // kernel-visible storage and a live fd that is about to be closed by Kotlin.
    static bool stageOutstandingUrbs(UsbAudioSink& sink) {
        sink.Close();
        sink.urbs_ = {&gUsbUrbIdentityOut};
        sink.urbOwned_ = {0};
        sink.feedbackUrbs_ = {&gUsbUrbIdentityIn};
        sink.feedbackOwned_ = {0};
        sink.urbStorage_.assign(32, 0xAA);
        sink.feedbackUrbStorage_.assign(32, 0xBB);
        sink.urbRawDepth_.assign(1, 32);
        sink.urbDeliveryEpoch_.assign(1, 7);
        sink.ring_.assign(64, 0x11);
        sink.ringRawDepth_.assign(8, 24);
        sink.ringFrameMask_ = 7;
        sink.ringRead_.store(0);
        sink.ringWrite_.store(0);
        sink.fd_ = 12;
        sink.claimed_ = true;
        sink.active_.store(true);
        sink.exclusive_.store(true);
        sink.running_.store(false);
        sink.lastError_.store(0);
        const auto accept = +[](int, void*) { return 0; };
        return sink.submitAll(accept) && sink.submitUrb(&gUsbUrbIdentityIn, true, 0, accept);
    }
    static bool drainDeadlineRetainsOwnership(UsbAudioSink& sink) {
        const bool staged = stageOutstandingUrbs(sink);
        // reapNever never hands back a completion, so the bounded deadline must
        // expire instead of freeing memory the kernel still owns.
        const bool timedOut = !sink.drainUrbCompletions(0, reapNever);
        const bool retained = timedOut && sink.GetLastError() == ETIMEDOUT &&
            sink.IsExclusive() && sink.hasOutstandingUrbs() &&
            !sink.urbStorage_.empty() && !sink.feedbackUrbStorage_.empty();
        sink.Abandon(); // never leave kernel-visible pointers behind for later tests
        return staged && retained;
    }
    static bool abandonRecoversCleanStart(UsbAudioSink& sink) {
        // Pristine pre-Open contract: no claim, no fd, no kernel-visible storage,
        // no exclusivity and no latched error from the teardown that just ran.
        auto pristine = [&sink] {
            return !sink.IsExclusive() && !sink.IsActive() &&
                !sink.hasOutstandingUrbs() && sink.urbStorage_.empty() &&
                sink.feedbackUrbStorage_.empty() && sink.ring_.empty() &&
                sink.ringRawDepth_.empty() && sink.fd_ == -1 && !sink.claimed_ &&
                sink.producerOwner_.load() == 0 && !sink.sinkDepthPublished_ &&
                sink.GetLastError() == 0;
        };
        const bool staged = stageOutstandingUrbs(sink);
        DspEngineRegistry::instance().setSinkBitDepth(24);
        sink.sinkDepthPublished_ = true;
        // Leave the sink in the state a failed Close() produces: outstanding
        // URBs and a latched ETIMEDOUT that only Abandon() may clear.
        const bool drainFailed = !sink.drainUrbCompletions(0, reapNever) &&
            sink.GetLastError() == ETIMEDOUT && sink.IsExclusive();
        sink.Abandon();
        const bool clean = pristine();
        // Idempotence: a second forced teardown must neither resurrect a claim,
        // an fd, storage or a live error, nor wedge the next Open.
        sink.Abandon();
        const bool stillClean = pristine();
        // The failed-drain gate must be gone: Open now reaches its normal path
        // (this host has no usbfs, so it reports InvalidArgs) instead of
        // ClaimFailed forever on a dead descriptor.
        const bool reopened = sink.Open(12, 1, 1, 1, 48000, 2, 4, 32) ==
            pulsr::UsbStreamResult::InvalidArgs;
        sink.Close();
        return staged && drainFailed && clean && stillClean && reopened;
    }
    static bool duplicateCompletionDrainIsBounded(UsbAudioSink& sink) {
        const bool staged = stageOutstandingUrbs(sink);
        // reapAlwaysForeign never hands back an URB markReaped owns, so only the
        // deadline checked before each reap can terminate this drain.
        const bool timedOut = !sink.drainUrbCompletions(20, reapAlwaysForeign);
        const bool retained = timedOut && sink.GetLastError() == ETIMEDOUT &&
            sink.IsExclusive() && sink.hasOutstandingUrbs() &&
            !sink.urbStorage_.empty() && !sink.feedbackUrbStorage_.empty();
        sink.Abandon();
        return staged && retained;
    }
    static bool unknownCompletionClearsProtocolError(UsbAudioSink& sink) {
        const bool staged = stageOutstandingUrbs(sink);
        sink.lastError_.store(EPROTO); // stale error from an earlier stray completion
        gReapScript = 0;
        // A non-zero budget: the deadline is now consulted before every reap, so
        // a 0 ms drain would (correctly) perform no reaps at all.
        const bool drained = sink.drainUrbCompletions(1000, reapScripted);
        const bool cleared = drained && !sink.hasOutstandingUrbs() &&
            sink.GetLastError() == 0 && sink.IsExclusive() &&
            !sink.urbStorage_.empty();
        sink.Close();
        return staged && cleared;
    }
    static int completion(const void* urb, bool feedback) {
        return UsbAudioSink::completionError(urb, feedback, 2, 16);
    }
    static int feedbackEndpoint(const uint8_t* config, size_t len, int iface,
                                int alt, int* packetSize) {
        return UsbAudioSink::findFeedbackEndpoint(config, len, iface, alt, packetSize);
    }
    static void setWrappedFill(UsbAudioSink& sink, size_t occupiedBytes) {
        prepare(sink, 4, 32, 65536, 0);
        const size_t frameBytes =
            static_cast<size_t>(sink.channels_) * static_cast<size_t>(sink.bytesPerSample_);
        const size_t readFrame = std::numeric_limits<size_t>::max() - 1023;
        sink.ringRead_.store(readFrame);
        sink.ringWrite_.store(readFrame + occupiedBytes / frameBytes);
        sink.numUrbs_ = 0;
        sink.packetsPerUrb_ = 0;
        sink.serviceIntervalUs_ = 1000;
    }
    static bool ownership(UsbAudioSink& sink) {
        sink.Close();
        const bool initiallyReleased = !sink.IsExclusive() && !sink.hasOutstandingUrbs();
        int out, in, unsubmitted, unknown;
        sink.urbs_ = {&out, &unsubmitted};
        sink.urbOwned_ = {0, 0};
        sink.urbStorage_.assign(32, 0xAA);
        const auto* startupStorage = sink.urbStorage_.data();
        sink.fd_ = -1; // failed drain is NOT proof that ownership ended
        // The real startup loop must mute HAL BEFORE the first syscall. Accept
        // one OUT, then fail the second; submitUrb itself records ownership.
        const bool partialSubmit = !sink.submitAll([](int, void*) {
            auto& s = UsbAudioSink::instance();
            if (!s.IsExclusive() || s.IsActive() || !closed(s)) {
                errno = EPROTO;
                return -1;
            }
            if (s.urbOwned_[0]) {
                errno = EIO;
                return -1;
            }
            return 0;
        }) && sink.urbOwned_[0] == 1 && sink.urbOwned_[1] == 0 && errno == EIO;
        sink.lastError_.store(errno);
        // fd_ is unusable here, so the drain cannot prove ownership returned:
        // the rollback must refuse and keep every buffer alive.
        const bool drainRefused = !sink.releaseResources(); // same rollback as Open after partial submit
        const bool startupRetained = drainRefused && sink.IsExclusive() && !sink.IsActive() && closed(sink) &&
            sink.hasOutstandingUrbs() && sink.urbStorage_.data() == startupStorage &&
            sink.urbStorage_.size() == 32;
        const bool restartBlocked = sink.Open(10, 1, 1, 1, 48000, 2, 4, 32) == UsbStreamResult::ClaimFailed &&
            sink.IsExclusive() && sink.urbStorage_.data() == startupStorage;
        bool feedback = false;
        size_t index = 99;
        const bool notSubmitted = !sink.markReaped(&unsubmitted, &feedback, &index) && sink.hasOutstandingUrbs();
        const bool startupReturned = sink.markReaped(&out, &feedback, &index) && !feedback && index == 0 &&
            !sink.hasOutstandingUrbs() && sink.IsExclusive();
        const bool closeDrained = sink.Close();
        const bool startupReleased = closeDrained && !sink.IsExclusive() && sink.urbStorage_.empty();

        // Also preserve the independent OUT/IN identity regression, acquiring
        // both identities through production submission rather than owned_=1.
        sink.urbs_ = {&out};
        sink.urbOwned_ = {0};
        sink.feedbackUrbs_ = {&in};
        sink.feedbackOwned_ = {0};
        sink.urbStorage_.assign(32, 0xAA);
        sink.feedbackUrbStorage_.assign(32, 0xBB);
        const auto* outStorage = sink.urbStorage_.data();
        const auto* inStorage = sink.feedbackUrbStorage_.data();
        const auto accept = +[](int, void*) { return 0; };
        const bool submitted = sink.submitAll(accept) && sink.submitUrb(&in, true, 0, accept);
        const bool closeRefused = !sink.Close(); // undrained ownership must be reported
        const bool retained = closeRefused && sink.IsExclusive() && sink.hasOutstandingUrbs() && sink.urbStorage_.data() == outStorage &&
            sink.feedbackUrbStorage_.data() == inStorage && sink.urbStorage_.size() == 32 &&
            sink.feedbackUrbStorage_.size() == 32;
        const bool unrecognized = !sink.markReaped(&unknown, &feedback, &index) && sink.hasOutstandingUrbs();
        const bool outOnly = sink.markReaped(&out, &feedback, &index) && !feedback && index == 0 &&
            sink.feedbackOwned_[0] == 1 && sink.hasOutstandingUrbs();
        const bool duplicate = !sink.markReaped(&out, &feedback, &index) && sink.feedbackOwned_[0] == 1;
        const bool inOnly = sink.markReaped(&in, &feedback, &index) && feedback && !sink.hasOutstandingUrbs();
        // Only exact submitted identities authorize freeing storage.
        const bool closeAfterReap = sink.Close();
        const bool released = closeAfterReap && !sink.IsExclusive() && sink.urbStorage_.empty() && sink.feedbackUrbStorage_.empty();
        return initiallyReleased && partialSubmit && startupRetained && restartBlocked && notSubmitted &&
            startupReturned && startupReleased && submitted && retained && unrecognized && outOnly && duplicate && inOnly && released;
    }
};
} // namespace pulsr

namespace {

int gFailures = 0;

void check(bool ok, const char* what) {
    if (!ok) {
        std::cout << "[FAIL] " << what << std::endl;
        ++gFailures;
    }
}

// Appends a 9-byte standard INTERFACE descriptor.
void pushInterface(std::vector<uint8_t>& d, uint8_t ifaceNum, uint8_t alt,
                   uint8_t klass, uint8_t subclass, uint8_t endpoints = 0) {
    d.push_back(9);          // bLength
    d.push_back(0x04);       // bDescriptorType = INTERFACE
    d.push_back(ifaceNum);   // bInterfaceNumber
    d.push_back(alt);        // bAlternateSetting
    d.push_back(endpoints);  // bNumEndpoints
    d.push_back(klass);      // bInterfaceClass (0x01 = Audio)
    d.push_back(subclass);   // bInterfaceSubClass (0x02 = AudioStreaming)
    d.push_back(0);          // bInterfaceProtocol
    d.push_back(0);          // iInterface
}

void setConfigLength(std::vector<uint8_t>& d) {
    d[2] = static_cast<uint8_t>(d.size() & 0xFF);
    d[3] = static_cast<uint8_t>((d.size() >> 8) & 0xFF);
}

void push3(std::vector<uint8_t>& d, int v) {
    d.push_back(static_cast<uint8_t>(v & 0xFF));
    d.push_back(static_cast<uint8_t>((v >> 8) & 0xFF));
    d.push_back(static_cast<uint8_t>((v >> 16) & 0xFF));
}

// Appends a UAC1 FORMAT_TYPE_I CS_INTERFACE descriptor.
// If discrete is empty, emits a continuous [lo,hi] range.
void pushFormatType(std::vector<uint8_t>& d, const std::vector<int>& discrete,
                    int lo = 0, int hi = 0) {
    const uint8_t freqType = discrete.empty() ? 0 : static_cast<uint8_t>(discrete.size());
    const int body = 8 + 3 * (discrete.empty() ? 2 : static_cast<int>(discrete.size()));
    d.push_back(static_cast<uint8_t>(body)); // bLength
    d.push_back(0x24);       // bDescriptorType = CS_INTERFACE
    d.push_back(0x02);       // bDescriptorSubtype = FORMAT_TYPE
    d.push_back(0x01);       // bFormatType = FORMAT_TYPE_I
    d.push_back(2);          // bNrChannels
    d.push_back(3);          // bSubframeSize
    d.push_back(24);         // bBitResolution
    d.push_back(freqType);   // bSamFreqType
    if (discrete.empty()) {
        push3(d, lo);
        push3(d, hi);
    } else {
        for (int r : discrete) push3(d, r);
    }
}

bool contains(const std::vector<int>& v, int x) {
    for (int e : v) if (e == x) return true;
    return false;
}

} // namespace

int main() {
    std::cout << "[TEST] USB UAC2 sink host-verifiable math..." << std::endl;

    // ---- Descriptor rate parsing -----------------------------------------
    {
        // Discrete 44100 + 48000 on an AudioStreaming interface.
        std::vector<uint8_t> d;
        pushInterface(d, 1, 1, 0x01, 0x02);
        pushFormatType(d, {44100, 48000});
        auto rates = UsbAudioSink::ParseSupportedRatesFromDescriptors(d.data(), d.size());
        check(rates.size() == 2 && rates[0] == 44100 && rates[1] == 48000,
              "discrete FORMAT_TYPE_I must yield sorted {44100,48000}");
    }
    {
        // Continuous [44100,96000] expands to the standard rates in range.
        std::vector<uint8_t> d;
        pushInterface(d, 1, 1, 0x01, 0x02);
        pushFormatType(d, {}, 44100, 96000);
        auto rates = UsbAudioSink::ParseSupportedRatesFromDescriptors(d.data(), d.size());
        check(rates.size() == 4 && contains(rates, 44100) && contains(rates, 48000) &&
                  contains(rates, 88200) && contains(rates, 96000),
              "continuous range must expand to {44100,48000,88200,96000}");
        check(!contains(rates, 176400), "continuous range must not exceed upper bound");
    }
    {
        // targetInterface filters: rates on interface 2 must be ignored when
        // querying interface 1.
        std::vector<uint8_t> d;
        pushInterface(d, 1, 1, 0x01, 0x02);
        pushFormatType(d, {44100});
        pushInterface(d, 2, 1, 0x01, 0x02);
        pushFormatType(d, {192000});
        auto only1 = UsbAudioSink::ParseSupportedRatesFromDescriptors(d.data(), d.size(), 1);
        check(only1.size() == 1 && only1[0] == 44100,
              "targetInterface=1 must return only interface 1's rates");
        auto only2 = UsbAudioSink::ParseSupportedRatesFromDescriptors(d.data(), d.size(), 2);
        check(only2.size() == 1 && only2[0] == 192000,
              "targetInterface=2 must return only interface 2's rates");
        auto all = UsbAudioSink::ParseSupportedRatesFromDescriptors(d.data(), d.size());
        check(all.size() == 2 && contains(all, 44100) && contains(all, 192000),
              "no targetInterface must merge every AudioStreaming interface");
    }
    {
        // A non-AudioStreaming interface (class != 0x01) must be skipped.
        std::vector<uint8_t> d;
        pushInterface(d, 1, 1, 0x08, 0x06); // mass storage, not audio
        pushFormatType(d, {48000});
        auto rates = UsbAudioSink::ParseSupportedRatesFromDescriptors(d.data(), d.size());
        check(rates.empty(), "non-audio interface must yield no rates");
    }
    {
        // Malformed input must not crash or invent rates.
        check(UsbAudioSink::ParseSupportedRatesFromDescriptors(nullptr, 0).empty(),
              "null descriptor must be empty");
        const uint8_t tiny[4] = {0x09, 0x04, 0x01, 0x01};
        check(UsbAudioSink::ParseSupportedRatesFromDescriptors(tiny, sizeof(tiny)).empty(),
              "descriptor shorter than 8 bytes must be empty");
        // bLength=0 would loop forever if not guarded; ensure forward progress.
        std::vector<uint8_t> zero(64, 0);
        check(UsbAudioSink::ParseSupportedRatesFromDescriptors(zero.data(), zero.size()).empty(),
              "all-zero descriptor must terminate and yield no rates");
    }

    // ---- Feedback discovery from Open's already-fetched configuration -----
    {
        using Access = pulsr::UsbAudioSinkTestAccess;
        std::vector<uint8_t> d = {9, 0x02, 0, 0, 3, 1, 0, 0x80, 50};
        pushInterface(d, 0, 0, 0x01, 0x01, 1); // AudioControl, not streaming
        d.insert(d.end(), {7, 0x05, 0x81, 0x11, 3, 0, 1});
        pushInterface(d, 1, 0, 0x01, 0x02, 1); // wrong alternate setting
        d.insert(d.end(), {7, 0x05, 0x82, 0x11, 3, 0, 1});
        const size_t selectedInterface = d.size();
        pushInterface(d, 1, 1, 0x01, 0x02, 2);
        d.insert(d.end(), {7, 0x05, 0x01, 0x05, 192, 0, 1});
        const size_t feedbackOffset = d.size();
        d.insert(d.end(), {7, 0x05, 0x83, 0x11, 4, 0, 1});
        pushInterface(d, 2, 1, 0x01, 0x02, 1); // wrong interface
        d.insert(d.end(), {7, 0x05, 0x84, 0x11, 3, 0, 1});
        setConfigLength(d);
        int packetSize = 99;
        check(Access::feedbackEndpoint(d.data(), d.size(), 1, 1, &packetSize) == 0x83 && packetSize == 4,
              "cached configuration must select feedback only on the operational audio interface/alt");
        check(Access::feedbackEndpoint(d.data(), d.size(), 1, 1, nullptr) == 0x83,
              "feedback discovery must allow an omitted packet-size output");
        for (int attrs : {0x11, 0x05, 0x01}) {
            auto compatible = d;
            compatible[feedbackOffset + 3] = static_cast<uint8_t>(attrs);
            compatible[feedbackOffset + 4] = 3;
            check(Access::feedbackEndpoint(compatible.data(), compatible.size(), 1, 1, &packetSize) == 0x83 && packetSize == 3,
                  "explicit usage, async sync type, and small iso-IN fallback must retain feedback discovery");
        }
        std::vector<uint8_t> noFeedback = {9, 0x02, 0, 0, 1, 1, 0, 0x80, 50};
        pushInterface(noFeedback, 1, 1, 0x01, 0x02, 2);
        noFeedback.insert(noFeedback.end(), {7, 0x05, 0x01, 0x05, 192, 0, 1,
                                            7, 0x05, 0x83, 0x09, 192, 0, 1});
        setConfigLength(noFeedback);
        check(Access::feedbackEndpoint(noFeedback.data(), noFeedback.size(), 1, 1, &packetSize) == 0 && packetSize == 0,
              "complete OUT/large adaptive-IN configuration must prove feedback absence");
        noFeedback[28] = 0x13; // small interrupt IN is not isochronous feedback
        noFeedback[29] = 3;
        check(Access::feedbackEndpoint(noFeedback.data(), noFeedback.size(), 1, 1, &packetSize) == 0,
              "small interrupt IN must not be mistaken for feedback");
        noFeedback.resize(25); // complete OUT-only interface
        noFeedback[13] = 1;
        setConfigLength(noFeedback);
        check(Access::feedbackEndpoint(noFeedback.data(), noFeedback.size(), 1, 1, &packetSize) == 0 && packetSize == 0,
              "complete OUT-only configuration must allow nominal-rate startup");
        for (const auto* config : {&d, &noFeedback}) {
            for (size_t len = 0; len < config->size(); ++len) {
                packetSize = 99;
                check(Access::feedbackEndpoint(config->data(), len, 1, 1, &packetSize) < 0 && packetSize == 0,
                      "every truncated configuration prefix must fail, never report no feedback");
            }
        }
        check(Access::feedbackEndpoint(nullptr, d.size(), 1, 1, &packetSize) < 0 && packetSize == 0,
              "null feedback configuration must fail closed");
        check(Access::feedbackEndpoint(d.data(), d.size(), 7, 1, &packetSize) < 0 &&
              Access::feedbackEndpoint(d.data(), d.size(), 1, 7, &packetSize) < 0,
              "missing operational interface or alternate setting cannot prove feedback absence");
        auto missingEndpoint = d;
        missingEndpoint.resize(feedbackOffset);
        setConfigLength(missingEndpoint);
        check(Access::feedbackEndpoint(missingEndpoint.data(), missingEndpoint.size(), 1, 1, &packetSize) < 0 && packetSize == 0,
              "bNumEndpoints must detect a missing feedback descriptor even at a clean boundary");
        for (int length : {0, 1, 6, 255}) {
            auto malformed = d;
            malformed[feedbackOffset] = static_cast<uint8_t>(length);
            packetSize = 99;
            check(Access::feedbackEndpoint(malformed.data(), malformed.size(), 1, 1, &packetSize) < 0 && packetSize == 0,
                  "malformed endpoint lengths must fail instead of hiding required feedback");
        }
        auto shortInterface = d;
        shortInterface[selectedInterface] = 8;
        shortInterface.erase(shortInterface.begin() + selectedInterface + 8);
        setConfigLength(shortInterface);
        check(Access::feedbackEndpoint(shortInterface.data(), shortInterface.size(), 1, 1, &packetSize) < 0,
              "short interface descriptor must not reuse a previous interface's identity");
        for (int count : {1, 3}) {
            auto mismatched = d;
            mismatched[selectedInterface + 4] = static_cast<uint8_t>(count);
            check(Access::feedbackEndpoint(mismatched.data(), mismatched.size(), 1, 1, &packetSize) < 0 && packetSize == 0,
                  "selected interface endpoint count must match before feedback discovery succeeds");
        }
        auto trailing = d;
        trailing.push_back(0); // malformed after an otherwise valid feedback endpoint
        setConfigLength(trailing);
        check(Access::feedbackEndpoint(trailing.data(), trailing.size(), 1, 1, &packetSize) < 0 && packetSize == 0,
              "finding feedback must not bypass validation of a malformed descriptor tail");
        auto badHeader = d;
        badHeader[1] = 0x04;
        check(Access::feedbackEndpoint(badHeader.data(), badHeader.size(), 1, 1, &packetSize) < 0,
              "feedback parser requires a configuration header, not a bare descriptor list");
        badHeader = d;
        ++badHeader[2];
        check(Access::feedbackEndpoint(badHeader.data(), badHeader.size(), 1, 1, &packetSize) < 0,
              "configuration total length must match the cached bytes");
    }

    // ---- Async-feedback decode -------------------------------------------
    {
        // 4-byte Q16.16 high-speed: nominal 48000 => 6.0 samples/microframe.
        // v = 6.0 * 65536 = 0x00060000 (LE).
        const uint8_t nom[4] = {0x00, 0x00, 0x06, 0x00};
        check(UsbAudioSink::DecodeFeedbackRatePerSec(nom, 4, 48000) == 48000,
              "HS nominal feedback must decode to the nominal rate");

        // +50 ppm: ratio 1.00005 -> 48002 (inside the +/-0.1% clamp).
        const uint32_t vUp = static_cast<uint32_t>(6.0 * 1.00005 * 65536.0 + 0.5);
        uint8_t up[4] = {static_cast<uint8_t>(vUp & 0xFF), static_cast<uint8_t>((vUp >> 8) & 0xFF),
                         static_cast<uint8_t>((vUp >> 16) & 0xFF), static_cast<uint8_t>((vUp >> 24) & 0xFF)};
        const int gotUp = UsbAudioSink::DecodeFeedbackRatePerSec(up, 4, 48000);
        check(gotUp > 48000 && gotUp <= 48048,
              "small positive feedback must nudge the rate up within the clamp");

        // ratio 1.05 is accepted by the +/-10% window but must clamp to +0.1%.
        const uint32_t vBig = static_cast<uint32_t>(6.0 * 1.05 * 65536.0 + 0.5);
        uint8_t big[4] = {static_cast<uint8_t>(vBig & 0xFF), static_cast<uint8_t>((vBig >> 8) & 0xFF),
                          static_cast<uint8_t>((vBig >> 16) & 0xFF), static_cast<uint8_t>((vBig >> 24) & 0xFF)};
        check(UsbAudioSink::DecodeFeedbackRatePerSec(big, 4, 48000) == 48048,
              "in-window but out-of-clamp feedback must clamp to +0.1%");

        // ratio 1.5 is outside +/-10% -> reject (return 0).
        const uint32_t vRej = static_cast<uint32_t>(6.0 * 1.5 * 65536.0 + 0.5);
        uint8_t rej[4] = {static_cast<uint8_t>(vRej & 0xFF), static_cast<uint8_t>((vRej >> 8) & 0xFF),
                          static_cast<uint8_t>((vRej >> 16) & 0xFF), static_cast<uint8_t>((vRej >> 24) & 0xFF)};
        check(UsbAudioSink::DecodeFeedbackRatePerSec(rej, 4, 48000) == 0,
              "implausible feedback (>+10%) must be rejected");

        const uint8_t zero[4] = {0, 0, 0, 0};
        check(UsbAudioSink::DecodeFeedbackRatePerSec(zero, 4, 48000) == 0,
              "zero feedback sample must be rejected");
        check(UsbAudioSink::DecodeFeedbackRatePerSec(nullptr, 4, 48000) == 0,
              "null feedback must be rejected");
        check(UsbAudioSink::DecodeFeedbackRatePerSec(nom, 4, 0) == 0,
              "non-positive nominal rate must be rejected");
        const uint8_t shortFeedback[2] = {0, 1};
        check(UsbAudioSink::DecodeFeedbackRatePerSec(shortFeedback, 2, 48000) == 0,
              "truncated feedback must be rejected before reading three bytes");
    }
    {
        // 3-byte Q10.14 full-speed: nominal 48000 => 48.0 samples/frame.
        // v = 48.0 * 16384 = 0x0C0000 (LE, 3 bytes).
        const uint8_t nom[3] = {0x00, 0x00, 0x0C};
        check(UsbAudioSink::DecodeFeedbackRatePerSec(nom, 3, 48000) == 48000,
              "FS nominal feedback must decode to the nominal rate");

        // 44100 => 44.1 samples/frame => v = 44.1*16384 = 722534.4 -> 722534.
        const uint32_t v44 = 722534;
        const uint8_t f44[3] = {static_cast<uint8_t>(v44 & 0xFF), static_cast<uint8_t>((v44 >> 8) & 0xFF),
                                static_cast<uint8_t>((v44 >> 16) & 0xFF)};
        const int got44 = UsbAudioSink::DecodeFeedbackRatePerSec(f44, 3, 44100);
        check(got44 >= 44055 && got44 <= 44145, "FS 44100 feedback must decode near nominal");
    }

    // ---- Fractional packet sizing ----------------------------------------
    {
        // 48000 is an integer number of frames per 1 ms packet: always 48.
        uint64_t acc = 0;
        const int maxF = (48000 + 999) / 1000 + 1; // 49
        bool all48 = true;
        for (int i = 0; i < 100; ++i) {
            if (UsbAudioSink::NextPacketFrames(acc, 48000, 1000, maxF) != 48) all48 = false;
        }
        check(all48, "48000 must emit exactly 48 frames per 1 ms packet");
        check(acc == 0, "48000 must leave zero fractional remainder");
    }
    {
        // 44100 emits 44/45 frames so every 10 packets sum to exactly 441.
        uint64_t acc = 0;
        const int maxF = (44100 + 999) / 1000 + 1; // 45
        int sum = 0;
        bool in4445 = true;
        for (int i = 0; i < 10; ++i) {
            const int f = UsbAudioSink::NextPacketFrames(acc, 44100, 1000, maxF);
            if (f != 44 && f != 45) in4445 = false;
            sum += f;
        }
        check(in4445, "44100 packets must be 44 or 45 frames");
        check(sum == 441, "44100 must emit exactly 441 frames per 10 packets");
        // Over 1000 packets the accumulator must produce exactly 44100 frames.
        acc = 0;
        long total = 0;
        for (int i = 0; i < 1000; ++i) total += UsbAudioSink::NextPacketFrames(acc, 44100, 1000, maxF);
        check(total == 44100, "44100 must emit exactly 44100 frames per 1000 packets");
    }
    {
        // The clamp caps a packet so feedback can never overflow the URB buffer.
        uint64_t acc = 0;
        const int f = UsbAudioSink::NextPacketFrames(acc, 48000, 1000, 10);
        check(f == 10, "NextPacketFrames must clamp to maxFramesPerPacket");
        check(acc == 0, "clamp must still consume the whole 1 ms remainder");
    }

    {
        uint64_t acc = 0;
        int total = 0;
        for (int i = 0; i < 8000; ++i) {
            total += UsbAudioSink::NextPacketFrames(acc, 48000, 125, 7);
        }
        check(total == 48000,
              "48 kHz at 125 us service intervals must send 48000 frames per second");
    }

    {
        for (int rate : {44100, 48000, 96000, 192000, 768000}) {
            for (int interval : {125, 250, 500, 1000, 2000}) {
                uint64_t acc = 0;
                int total = 0;
                const int maxFrames = (rate * interval + 999999) / 1000000 + 1;
                for (int i = 0; i < 1000000 / interval; ++i) {
                    total += UsbAudioSink::NextPacketFrames(acc, rate, interval, maxFrames);
                }
                check(total == rate && acc == 0, "service-interval cadence must preserve one second of PCM");
            }
        }
        uint64_t acc = 0;
        check(UsbAudioSink::NextPacketFrames(acc, 768000, 4096000, 4000000) == 3145728,
              "long service intervals must not overflow 32-bit rate products");
        check(UsbAudioSink::NextPacketFrames(acc, 48000, 0, 48) == 0,
              "invalid service interval must not emit frames");
    }
    {
        std::vector<uint8_t> d;
        pushInterface(d, 1, 1, 0x01, 0x02);
        d.insert(d.end(), {7, 0x05, 0x01, 0x05, 0xc0, 0x00, 1});
        auto timing = UsbAudioSink::ParseEndpointTiming(d.data(), d.size(), 1, 1, 1, 3);
        check(timing.intervalUs == 125 && timing.maxPacketBytes == 192,
              "HS bInterval=1 must use 125 us and the advertised packet capacity");
        timing = UsbAudioSink::ParseEndpointTiming(d.data(), d.size(), 1, 1, 1, 2);
        check(timing.intervalUs == 1000, "FS bInterval=1 must use 1 ms");
        d[15] = 4;
        timing = UsbAudioSink::ParseEndpointTiming(d.data(), d.size(), 1, 1, 1, 3);
        check(timing.intervalUs == 1000, "HS bInterval=4 must use 1 ms");
        d[13] = 0;
        d[14] = 0x14;
        timing = UsbAudioSink::ParseEndpointTiming(d.data(), d.size(), 1, 1, 1, 3);
        check(timing.maxPacketBytes == 3072, "HS high-bandwidth packet capacity must include transactions");
        check(UsbAudioSink::ParseEndpointTiming(d.data(), d.size(), 1, 2, 1, 3).intervalUs == 0,
              "wrong alternate setting must not supply packet timing");
        check(UsbAudioSink::ParseEndpointTiming(d.data(), d.size(), 1, 1, 1, 0).intervalUs == 0,
              "unknown USB speed must not guess a service interval");
        d[14] = 0x1c;
        check(UsbAudioSink::ParseEndpointTiming(d.data(), d.size(), 1, 1, 1, 3).intervalUs == 0,
              "reserved HS transaction count must be rejected");
        d[14] = 4;
        d[15] = 1;
        d.insert(d.end(), {6, 0x30, 1, 1, 0, 0x10});
        timing = UsbAudioSink::ParseEndpointTiming(d.data(), d.size(), 1, 1, 1, 5);
        check(timing.intervalUs == 125 && timing.maxPacketBytes == 4096,
              "SuperSpeed capacity must use the endpoint companion's bytes per interval");
        for (size_t length = 0; length < d.size(); ++length) {
            check(UsbAudioSink::ParseEndpointTiming(d.data(), length, 1, 1, 1, 5).intervalUs == 0,
                  "truncated descriptors must not invent endpoint timing");
        }
        d[15] = 0;
        check(UsbAudioSink::ParseEndpointTiming(d.data(), d.size(), 1, 1, 1, 5).intervalUs == 0,
              "zero endpoint interval must be rejected");
    }

    // ---- Raw ring transport, fail-closed formats, producer admission -------
    {
        using Access = pulsr::UsbAudioSinkTestAccess;
        auto& sink = UsbAudioSink::instance();
        const std::vector<uint8_t> source = {
            0xFF,0xFF,0xFF,0x7F, 0xFE,0xFF,0xFF,0x7F,
            0x01,0x00,0x00,0x80, 0xFF,0xFF,0xFF,0xFF,
            0x79,0x56,0x34,0x12, 0x00,0x00,0x00,0x80};
        const auto original = source;
        Access::prepare(sink, 4, 32, 128, 120); // crosses byte ring wrap
        const uint64_t allocations = gAllocations.load();
        const bool rawAccepted = sink.WritePcm(source.data(), 3, 2, 32, 48000, 101);
        const uint64_t allocationsAfter = gAllocations.load();
        check(rawAccepted, "raw S32 write must accept whole block");
        check(allocations == allocationsAfter, "raw RT write must allocate nothing");
        check(Access::written(sink) == 144 && Access::bytes(sink, 120, source.size()) == source,
              "raw S32 rails/negative/near-FS LSBs must survive ring wrap exactly");
        check(source == original, "USB write must never mutate caller PCM");
        check(sink.GetRawPcmBitDepth() == 0, "queued bytes alone must not claim delivered raw PCM");
        const uint64_t epoch = Access::epoch(sink);
        Access::delivered(sink, 32, epoch);
        check(sink.GetRawPcmBitDepth() == 32, "successful completion must report original integer depth");
        const auto before = Access::written(sink);
        check(!sink.WritePcm(source.data(), 1, 2, 32, 48000, 202) && sink.GetLastError() == EBUSY,
              "secondary producer must fail with actionable EBUSY");
        check(Access::written(sink) == before && sink.GetRawPcmBitDepth() == 0,
              "secondary producer must not change ring or retain raw-success claim");
        Access::delivered(sink, 32, epoch);
        check(sink.GetRawPcmBitDepth() == 0, "old outstanding completion cannot erase a later failure");
        sink.ReleaseProducer(202);
        check(!sink.WritePcm(source.data(), 1, 2, 32, 48000, 202), "wrong owner release must not steal producer");
        sink.ReleaseProducer(101);
        check(sink.WritePcm(source.data(), 1, 2, 32, 48000, 202), "released producer can hand off atomically");
        check(Access::enter(sink, 202), "same producer can acquire free admission gate");
        const auto admitted = Access::written(sink);
        check(!sink.WritePcm(source.data(), 1, 2, 32, 48000, 202) && sink.GetLastError() == EBUSY &&
              Access::written(sink) == admitted, "same producer reentrancy must fail without SPSC corruption");
        Access::leave(sink);

        Access::prepare(sink, 4, 24);
        check(!sink.WritePcm(source.data(), 1, 2, 32, 48000, 101) && sink.GetLastError() == ERANGE &&
              Access::written(sink) == 0, "32-bit source must reject a 24-valid-bit four-byte subslot");
        const uint8_t s24[] = {0xFF,0xFF,0x7F, 0x01,0x00,0x80};
        const std::vector<uint8_t> wire24 = {0,0xFF,0xFF,0x7F, 0,0x01,0x00,0x80};
        check(sink.WritePcm(s24, 1, 2, 24, 48000, 101) && Access::bytes(sink, 0, 8) == wire24,
              "S24 must left-align into 24-valid-in-32 without losing source LSBs");
        check(!sink.WritePcm(s24, 1, 2, 24, 44100, 101) && sink.GetLastError() == ERANGE,
              "source rate mismatch must reject rather than silently play at wrong rate");
        check(!sink.WritePcm(s24, 1, 1, 24, 48000, 101) && sink.GetChannelMismatchFrames() == 1,
              "raw channel mismatch must reject and count affected frames");
        check(!sink.WritePcm(s24, 1, 2, 20, 48000, 101), "unsupported raw depth must reject");
        const float processed[] = {0.25f, -0.25f};
        check(!sink.WriteInterleaved(processed, 1, 1, 48000, 101), "float channel mismatch must not remap");
        check(!sink.WriteInterleaved(processed, 1, 2, 96000, 101), "float rate mismatch must not silently retime");
        const uint64_t floatAllocations = gAllocations.load();
        const bool floatAccepted = sink.WriteInterleaved(processed, 1, 2, 48000, 101);
        const uint64_t floatAllocationsAfter = gAllocations.load();
        check(floatAccepted, "processed float may use valid wire depth");
        check(floatAllocations == floatAllocationsAfter, "float RT write must allocate nothing");
        check(Access::bytes(sink, 8, 8) == std::vector<uint8_t>({0,0,0,0x20, 0,0,0,0xE0}),
              "processed 24-in-32 ring bytes must have zero padding and correct levels");
        Access::delivered(sink, 0, Access::epoch(sink));
        check(sink.GetRawPcmBitDepth() == 0, "processed delivery must never report raw depth");

        Access::prepare(sink, 4, 32, 16);
        check(sink.WaitForWriteSpace(1, 0) == 0,
              "WaitForWriteSpace must report 0 immediately when ring has space");
        check(!sink.WritePcm(source.data(), 2, 2, 32, 48000, 101) && sink.GetLastError() == ENOSPC &&
              Access::written(sink) == 0, "overrun must reject entire block, not partially publish");
        check(sink.WritePcm(source.data(), 1, 2, 32, 48000, 101), "fitting block may follow rejected overrun");
        check(sink.WaitForWriteSpace(1, 2) == 1,
              "WaitForWriteSpace must report 1 (backpressure) when active exclusive ring is full");
        check(sink.WaitForWriteSpace(8, 2) == -1,
              "WaitForWriteSpace must report -1 when requested frames exceed total ring capacity");
        check(Access::enter(sink, 101), "writer lease for close-drain test must admit");
        std::atomic<bool> closeReturned{false};
        std::atomic<bool> closeDrained{false};
        std::thread closer([&] { closeDrained.store(sink.Close()); closeReturned.store(true); });
        while (!Access::closed(sink)) std::this_thread::yield();
        check(!closeReturned.load(), "Close must wait for admitted writer before freeing ring");
        Access::leave(sink);
        closer.join();
        check(closeReturned.load() && closeDrained.load() && sink.GetRawPcmBitDepth() == 0 && !sink.IsActive(),
              "Close must drain writer, report a successful bounded drain and clear raw delivery status");
        for (int trial = 0; trial < 32; ++trial) {
            Access::prepare(sink);
            std::atomic<int> ready{0};
            std::atomic<bool> go{false};
            bool accepted[2] = {};
            const auto compete = [&](int index) {
                ready.fetch_add(1);
                while (!go.load()) std::this_thread::yield();
                accepted[index] = sink.WritePcm(source.data(), 1, 2, 32, 48000, 100 + index);
            };
            std::thread first(compete, 0), second(compete, 1);
            while (ready.load() != 2) std::this_thread::yield();
            go.store(true);
            first.join();
            second.join();
            check(accepted[0] != accepted[1] && Access::written(sink) == 8 &&
                  Access::bytes(sink, 0, 8) == std::vector<uint8_t>(source.begin(), source.begin() + 8),
                  "simultaneous producers must publish exactly one intact frame");
        }
        sink.Close();
        check(Access::ownership(sink), "startup rollback must retain HAL exclusivity and OUT/IN ownership until exact completion");
        check(Access::clearRegistryAfterWorkerExit(sink), "control teardown must clear registry depth after worker self-exit");
        check(sink.Open(10, 1, 1, 1, 48000, 2, 3, 32) == pulsr::UsbStreamResult::InvalidArgs,
              "Open must reject valid bits exceeding wire width before usbfs calls");
        check(sink.Open(10, 1, 1, 1, 48000, 2, 4, 20) == pulsr::UsbStreamResult::InvalidArgs,
              "Open must reject unsupported valid depth before usbfs calls");
        check(Access::drainDeadlineRetainsOwnership(sink),
              "bounded drain must time out (ETIMEDOUT) and retain exclusive ownership when no completion arrives");
        check(Access::duplicateCompletionDrainIsBounded(sink),
              "bounded drain must end when every reap reports a foreign completion");
        check(Access::abandonRecoversCleanStart(sink),
              "Abandon must leak kernel-owned URBs, clear the error, withdraw publication and let the next Open start clean");
        check(Access::unknownCompletionClearsProtocolError(sink),
              "a stray completion must not leave EPROTO latched after a successful drain");

        // Ring occupancy across size_t wraparound + adaptive cadence steering.
        Access::setWrappedFill(sink, 38400); // 100.0 ms at 48 kHz / 2ch / 4B
        const double wrappedMs = sink.GetBufferedMs();
        sink.Close();
        check(std::abs(wrappedMs - 100.0) < 0.1,
              "GetBufferedMs must survive unsigned size_t wraparound");

        int steeredLow = UsbAudioSink::SteerPacketRateForRingFill(48000, 48000, 100, 1000);
        check(steeredLow < 48000 && steeredLow >= 47520,
              "low ring fill must steer cadence gently downward within -1%");
        for (int s = 0; s < 200; ++s) {
            steeredLow = UsbAudioSink::SteerPacketRateForRingFill(steeredLow, 48000, 0, 1000);
        }
        check(steeredLow == 47520, "low-fill cadence steering must clamp at -1%");
        int steeredHigh = UsbAudioSink::SteerPacketRateForRingFill(48000, 48000, 900, 1000);
        check(steeredHigh > 48000 && steeredHigh <= 48480,
              "high ring fill must steer cadence gently upward within +1%");
        check(UsbAudioSink::SteerPacketRateForRingFill(47980, 48000, 250, 1000) == 47980,
              "hysteresis zone must hold tuned cadence without chatter");
        int recovered = 47980;
        for (int s = 0; s < 100; ++s) {
            recovered = UsbAudioSink::SteerPacketRateForRingFill(recovered, 48000, 500, 1000);
        }
        check(recovered == 48000, "centered deadband must relax back to nominal rate");

        // Feedback-less DACs typically run 0.2-0.6% off the host clock. That
        // drift must be steerable: under the old +/-0.1% (+/-48 Hz) window these
        // corrections were clamped away and the ring could only gap-fill. Probe
        // in the hysteresis band so the value is held, not re-centred.
        const int twoPerMilleFast = 48000 + 48000 * 2 / 1000; // +96 Hz
        const int twoPerMilleSlow = 48000 - 48000 * 2 / 1000; // -96 Hz
        check(UsbAudioSink::SteerPacketRateForRingFill(twoPerMilleFast, 48000, 750, 1000) == twoPerMilleFast &&
              UsbAudioSink::SteerPacketRateForRingFill(twoPerMilleSlow, 48000, 250, 1000) == twoPerMilleSlow,
              "a 0.2% clock error must survive steering instead of saturating at +/-0.1%");
        int saturatedFast = 48000;
        int saturatedSlow = 48000;
        for (int s = 0; s < 200; ++s) {
            saturatedFast = UsbAudioSink::SteerPacketRateForRingFill(saturatedFast, 48000, 990, 1000);
            saturatedSlow = UsbAudioSink::SteerPacketRateForRingFill(saturatedSlow, 48000, 10, 1000);
        }
        check(saturatedFast == 48480 && saturatedSlow == 47520,
              "sustained ring error must be able to reach the full +/-1% steering range");
    }

    // ---- Completion validation: not every reaped OUT actually played -------
    {
        using Access = pulsr::UsbAudioSinkTestAccess;
        std::vector<uint64_t> storage((sizeof(usbdevfs_urb) + 32 + 7) / 8, 0);
        auto* urb = reinterpret_cast<usbdevfs_urb*>(storage.data());
        urb->number_of_packets = 2;
        urb->buffer_length = urb->actual_length = 16;
        for (int p = 0; p < 2; ++p) urb->iso_frame_desc[p].length = urb->iso_frame_desc[p].actual_length = 8;
        check(Access::completion(urb, false) == 0, "complete successful OUT must be accepted");
        urb->status = -EPIPE;
        check(Access::completion(urb, false) == EPIPE, "OUT URB status must surface actual failure");
        urb->status = 0;
        urb->error_count = 1;
        check(Access::completion(urb, false) != 0, "OUT error_count must not be ignored");
        urb->error_count = 0;
        urb->iso_frame_desc[1].status = static_cast<unsigned int>(-EIO);
        check(Access::completion(urb, false) != 0 && Access::completion(urb, true) != 0,
              "packet error must fail OUT and invalidate feedback samples");
        urb->iso_frame_desc[1].status = 0;
        urb->iso_frame_desc[1].actual_length = 4;
        urb->actual_length = 12;
        check(Access::completion(urb, false) != 0, "short OUT packet must not claim successful delivery");
        check(Access::completion(urb, true) == 0, "short IN completion is structurally valid but decoded only at exact feedback length");
        urb->iso_frame_desc[1].actual_length = 9;
        check(Access::completion(urb, true) != 0, "feedback packet length above submitted capacity must reject");
        urb->number_of_packets = 200;
        check(Access::completion(urb, false) != 0, "invalid completion packet count must reject before descriptor access");
    }

    // ---- Underrun -> Raw 24-in-32 custody & partial packet salvage ---------
    {
        using Access = pulsr::UsbAudioSinkTestAccess;
        auto& sink = UsbAudioSink::instance();
        // 24-valid-in-32 subslot: verify ringRawDepth_ is 1 byte/frame and
        // raw 24-bit packets after an underrun are never touched by gapFader_ or
        // RequantizePcmValidBits.
        Access::prepare(sink, 4, 24, 512, 0);
        check(Access::ringRawDepthBytes(sink) == 512 / 8,
              "ringRawDepth_ must store one depth byte per frame, not per byte");

        int rawDepth = -1;
        uint64_t epoch = Access::epoch(sink);
        std::vector<uint8_t> pkt(4 * 8, 0xAA);
        // 1) Force an underrun first (empty ring -> gapFader_ or silence + underrun count)
        Access::fillPacket(sink, pkt.data(), 4, rawDepth, epoch);
        check(Access::underrunCount(sink) == 1 && rawDepth == 0,
              "empty ring must record underrun and clear rawDepth");

        // 2) Push a 4-frame raw 24-bit packet with distinct LSBs (0x01, 0x7F, ...)
        const std::vector<uint8_t> s24Block = {
            0x01,0x23,0x45,  0x81,0x80,0x7F,
            0x55,0xAA,0x10,  0xFE,0xFF,0x80,
            0x13,0x37,0x42,  0x00,0x00,0x7F,
            0x09,0x08,0x07,  0x01,0x00,0x80,
        };
        const std::vector<uint8_t> expectedWire = {
            0,0x01,0x23,0x45, 0,0x81,0x80,0x7F,
            0,0x55,0xAA,0x10, 0,0xFE,0xFF,0x80,
            0,0x13,0x37,0x42, 0,0x00,0x00,0x7F,
            0,0x09,0x08,0x07, 0,0x01,0x00,0x80,
        };
        check(sink.WritePcm(s24Block.data(), 4, 2, 24, 48000, 101),
              "raw S24 resume write after underrun must succeed");
        rawDepth = -1;
        Access::fillPacket(sink, pkt.data(), 4, rawDepth, epoch);
        check(rawDepth == 24 && pkt == expectedWire,
              "raw 24-in-32 resume after underrun must remain bit-exact without gapFader or dither");

        // 3) Partial packet salvage: 2 frames available for a 4-frame packet
        const std::vector<uint8_t> partialS24(s24Block.begin(), s24Block.begin() + 12);
        check(sink.WritePcm(partialS24.data(), 2, 2, 24, 48000, 101),
              "partial packet write must accept 2 frames");
        pkt.assign(32, 0xAA);
        rawDepth = -1;
        Access::fillPacket(sink, pkt.data(), 4, rawDepth, epoch);
        const std::vector<uint8_t> expectedPartialWire = {
            0,0x01,0x23,0x45, 0,0x81,0x80,0x7F,
            0,0x55,0xAA,0x10, 0,0xFE,0xFF,0x80,
            0,0,0,0, 0,0,0,0,
            0,0,0,0, 0,0,0,0,
        };
        check(pkt == expectedPartialWire && rawDepth == 0 &&
              Access::underrunCount(sink) == 2,
              "partial packet must copy available frames verbatim and zero-fill missing tail");
        sink.Close();
    }

    // ---- Item 3: DoP underrun gaps carry valid marker silence -------------
    {
        using Access = pulsr::UsbAudioSinkTestAccess;
        auto& sink = UsbAudioSink::instance();
        Access::prepare(sink, 4, 32, 4096, 0);
        sink.SetProducerDop(true);
        check(sink.IsProducerDop(), "the DoP producer flag must be observable by the worker");
        // Two real 24-in-32 DoP frames: markers 0x05 then 0xFA.
        const std::vector<uint8_t> dop = {
            0x11,0x22,0x33,0x05, 0x44,0x55,0x66,0x05,
            0x77,0x88,0x99,0xFA, 0xAA,0xBB,0xCC,0xFA,
        };
        check(sink.WritePcm(dop.data(), 2, 2, 32, 48000, 101),
              "raw DoP frames must be accepted");
        int rawDepth = -1;
        uint64_t epoch = Access::epoch(sink);
        std::vector<uint8_t> pkt(4 * 8, 0xAA);
        Access::fillPacket(sink, pkt.data(), 4, rawDepth, epoch);
        const std::vector<uint8_t> expectedDop = {
            0x11,0x22,0x33,0x05, 0x44,0x55,0x66,0x05,
            0x77,0x88,0x99,0xFA, 0xAA,0xBB,0xCC,0xFA,
            0x00,0x00,0x00,0x05, 0x00,0x00,0x00,0x05,  // frame 2 -> 0x05
            0x00,0x00,0x00,0xFA, 0x00,0x00,0x00,0xFA,  // frame 3 -> 0xFA
        };
        check(pkt == expectedDop && rawDepth == 0,
              "a DoP underrun must synthesize marker silence in phase with the producer");
        // A fully-empty packet must continue the alternation: frame 4 is 0x05.
        Access::fillPacket(sink, pkt.data(), 4, rawDepth, epoch);
        const std::vector<uint8_t> expectedDop2 = {
            0x00,0x00,0x00,0x05, 0x00,0x00,0x00,0x05,
            0x00,0x00,0x00,0xFA, 0x00,0x00,0x00,0xFA,
            0x00,0x00,0x00,0x05, 0x00,0x00,0x00,0x05,
            0x00,0x00,0x00,0xFA, 0x00,0x00,0x00,0xFA,
        };
        check(pkt == expectedDop2,
              "DoP marker alternation must continue across empty packets");
        // Plain PCM gaps keep the historical zero fill.
        sink.SetProducerDop(false);
        const std::vector<uint8_t> pcm = {0x01,0x00,0x00,0x00, 0x02,0x00,0x00,0x00};
        check(sink.WritePcm(pcm.data(), 1, 2, 32, 48000, 101),
              "raw PCM frames must still be accepted after DoP");
        pkt.assign(4 * 8, 0xAA);
        Access::fillPacket(sink, pkt.data(), 4, rawDepth, epoch);
        const std::vector<uint8_t> expectedPcm = {
            0x01,0x00,0x00,0x00, 0x02,0x00,0x00,0x00,
            0x00,0x00,0x00,0x00, 0x00,0x00,0x00,0x00,
            0x00,0x00,0x00,0x00, 0x00,0x00,0x00,0x00,
            0x00,0x00,0x00,0x00, 0x00,0x00,0x00,0x00,
        };
        check(pkt == expectedPcm,
              "raw PCM gaps must keep the plain zero fill (no synthetic markers)");
        sink.Close();
    }

    // ---- Stream tuning clamps (control-thread state for the next Open) ----
    // The values are consumed by Open(); what is pinned here is that a tuning
    // request cannot smuggle an unbounded reservoir or a negative transfer size
    // into the transport.
    {
        using Access = pulsr::UsbAudioSinkTestAccess;
        auto& sink = UsbAudioSink::instance();
        Access::prepare(sink);
        sink.SetStreamTuning(4096, 20000, true);
        check(Access::tunedTransferBytes(sink) == 4096 &&
                  Access::tunedBufferMs(sink) == 10000 &&
                  Access::feedbackDisabled(sink),
              "stream tuning keeps a valid transfer size and caps the pull buffer at 10000 ms");
        sink.SetStreamTuning(-64, -5, false);
        check(Access::tunedTransferBytes(sink) == 0 && Access::tunedBufferMs(sink) == 0 &&
                  !Access::feedbackDisabled(sink),
              "non-positive tuning values fall back to automatic");
        sink.SetStreamTuning(0, 3000, false);
        check(Access::tunedBufferMs(sink) == 3000,
              "a within-range pull buffer is kept as requested");
        sink.Close();
    }

    // ---- Clock-domain policy: pure, no device or stream required ----------
    // These are the values Kotlin/Dart quote as "what the USB path is doing",
    // so the contract is pinned here: BitPerfectLocked must survive every
    // precondition, and nothing else may produce it.
    int clockDomainChecks = 0;
    int pullChecks = 0;
    {
        using pulsr::UsbClockDomain;
        using pulsr::UsbRenderMode;
        int n = 0;
        const auto expect = [&](bool ok, const char* what) {
            check(ok, what);
            ++n;
        };
        const auto domain = [](UsbRenderMode mode, bool active, bool eligible,
                               uint64_t underruns, uint64_t mismatch) {
            return UsbAudioSink::DeriveClockDomain(mode, active, eligible, underruns,
                                                   mismatch);
        };

        expect(domain(UsbRenderMode::BestEffort, false, true, 0, 0) ==
                   UsbClockDomain::Unknown,
               "an inactive stream is Unknown whatever mode was requested");
        expect(domain(UsbRenderMode::BitPerfectPull, false, true, 0, 0) ==
                   UsbClockDomain::Unknown,
               "an eligible pull request that is not running is still Unknown");
        expect(domain(UsbRenderMode::ClockSyncAsrc, true, false, 0, 0) ==
                   UsbClockDomain::Asrc,
               "an active ASRC stream reports Asrc");
        expect(domain(UsbRenderMode::ClockSyncAsrc, true, false, 7, 11) ==
                   UsbClockDomain::Asrc,
               "ASRC stays Asrc after underruns and channel mismatches");
        expect(domain(UsbRenderMode::BitPerfectPull, true, true, 0, 0) ==
                   UsbClockDomain::BitPerfectLocked,
               "an eligible pull stream with no faults is BitPerfectLocked");
        expect(domain(UsbRenderMode::BitPerfectPull, true, false, 0, 0) ==
                   UsbClockDomain::BestEffort,
               "an ineligible pull stream must not claim bit-perfect");
        expect(domain(UsbRenderMode::BitPerfectPull, true, true, 1, 0) ==
                   UsbClockDomain::BestEffort,
               "one pull underrun drops the domain to BestEffort");
        expect(domain(UsbRenderMode::BitPerfectPull, true, true, 0, 1) ==
                   UsbClockDomain::BestEffort,
               "one channel-mismatch frame drops the domain to BestEffort");
        expect(domain(UsbRenderMode::BestEffort, true, true, 0, 0) ==
                   UsbClockDomain::BestEffort,
               "the default producer path is BestEffort even with a clean session");

        // Wire vocabulary: the JNI getters cast the enum to jint and the status
        // names are consumed verbatim by Kotlin/Dart telemetry.
        expect(static_cast<int>(UsbRenderMode::BestEffort) == 0 &&
                   static_cast<int>(UsbRenderMode::BitPerfectPull) == 1 &&
                   static_cast<int>(UsbRenderMode::ClockSyncAsrc) == 2,
               "UsbRenderMode wire values must stay 0/1/2");
        expect(std::strcmp(pulsr::UsbClockDomainName(UsbClockDomain::BitPerfectLocked),
                           "bitPerfectLocked") == 0,
               "BitPerfectLocked must keep its wire name");
        expect(std::strcmp(pulsr::UsbClockDomainName(UsbClockDomain::Asrc), "asrc") == 0,
               "Asrc must keep its wire name");
        expect(std::strcmp(pulsr::UsbClockDomainName(UsbClockDomain::BestEffort),
                           "bestEffort") == 0,
               "BestEffort must keep its wire name");
        expect(std::strcmp(pulsr::UsbClockDomainName(UsbClockDomain::Unknown), "unknown") == 0,
               "Unknown must keep its wire name");

        // A value built for a torn-down or never-started stream must be inert,
        // not merely plausible: the UI shows these fields directly.
        const pulsr::UsbClockStatus fresh{};
        expect(fresh.domain == UsbClockDomain::Unknown,
               "a default-constructed clock status is Unknown");
        expect(fresh.clockDriftPpm == 0 && fresh.ringFillMs == 0 &&
                   !fresh.feedbackPresent,
               "a default clock status carries no drift, fill or feedback");
        expect(fresh.underrunCount == 0 && fresh.overrunCount == 0,
               "a default clock status starts with zero counters");

        clockDomainChecks = n;
    }

    // ---- Pull / ASRC packet-fill integration (no USB device required) ----
    {
        using Access = pulsr::UsbAudioSinkTestAccess;
        auto& sink = pulsr::UsbAudioSink::instance();
        // 100 ms reservoir at 48 kHz stereo/16-bit: 4800 frames, 80% prefill.
        Access::preparePull(sink, /*mode=*/1, /*bufferMs=*/100);
        std::vector<uint8_t> source(4800 * 4);
        for (size_t i = 0; i < source.size(); ++i) {
            source[i] = static_cast<uint8_t>((i * 37 + 11) & 0xFF);
        }
        check(Access::writePull(sink, source.data(), 4800),
               "pull renderer accepts a whole prefill block");
        std::vector<uint8_t> out(480 * 4, 0);
        int depth = 0;
        const size_t packetBytes = Access::fillPull(sink, out.data(), 480, depth);
        check(packetBytes == out.size(), "pull packet fills every requested frame");
        check(std::memcmp(out.data(), source.data(), out.size()) == 0,
               "pull packet payload is bit-identical to what the producer wrote");
        check(depth == 16, "raw pull packets report the source valid depth");
        // A full, bit-identical packet pull is what earns eligibility.
        check(Access::eligible(sink),
               "a clean raw pull session is bit-perfect eligible");

        // Drain the rest, then force one underrun.
        for (int p = 0; p < 9; ++p) {
            Access::fillPull(sink, out.data(), 480, depth);
        }
        const size_t underrunsBefore = Access::underruns(sink);
        Access::fillPull(sink, out.data(), 480, depth);
        check(Access::underruns(sink) == underrunsBefore + 1,
               "a short pull counts exactly one underrun");
        check(!Access::eligible(sink),
               "one pull underrun permanently disqualifies the session");

        // ASRC: float reservoir, 24-bit wire, resampled output must be packed
        // and must never advertise raw-integer depth.
        Access::preparePull(sink, /*mode=*/2, /*bufferMs=*/100);
        std::vector<float> floats(4800 * 2);
        for (size_t f = 0; f < 4800; ++f) {
            const float v = 0.25f * std::sin(2.0f * 3.14159265f * 1000.0f *
                                             static_cast<float>(f) / 48000.0f);
            floats[f * 2] = v;
            floats[f * 2 + 1] = v;
        }
        check(Access::writePull(sink, floats.data(), 4800),
               "ASRC renderer accepts decoded float frames");
        std::vector<uint8_t> asrcOut(480 * 2 * 2, 0x7f);
        depth = 99;
        const size_t asrcBytes = Access::fillAsrc(sink, asrcOut.data(), 480, depth);
        check(asrcBytes == asrcOut.size(), "ASRC packet produces the exact byte count");
        check(depth == 0, "ASRC output is never reported as raw integer PCM");
        bool anyNonZero = false;
        for (uint8_t b : asrcOut) anyNonZero = anyNonZero || b != 0;
        check(anyNonZero, "ASRC packet carries resampled samples, not silence");

        // Raw integer sources must be converted, not refused: the ASRC mode is
        // offered for decoded sources of either storage type.
        Access::preparePull(sink, /*mode=*/2, /*bufferMs=*/100);
        std::vector<uint8_t> raw16(4800 * 2 * 2);
        for (size_t i = 0; i < raw16.size(); i += 2) {
            const int16_t sample = static_cast<int16_t>(
                12000 * std::sin(2.0 * 3.14159265 * 1000.0 *
                                 static_cast<double>(i / 4) / 48000.0));
            raw16[i] = static_cast<uint8_t>(sample & 0xFF);
            raw16[i + 1] = static_cast<uint8_t>((sample >> 8) & 0xFF);
        }
        check(Access::writeRawAsrc(sink, raw16.data(), 4800, 16),
              "ASRC accepts a raw 16-bit producer block");
        std::fill(asrcOut.begin(), asrcOut.end(), 0);
        depth = 99;
        const size_t rawBytes = Access::fillAsrc(sink, asrcOut.data(), 480, depth);
        check(rawBytes == asrcOut.size(),
              "ASRC packs a converted raw block at the wire byte count");
        bool rawNonZero = false;
        for (uint8_t b : asrcOut) rawNonZero = rawNonZero || b != 0;
        check(rawNonZero, "converted raw block reaches the ASRC output");
        Access::stopPull(sink);

        pullChecks = 13;
    }

    if (gFailures != 0) {
        std::cout << "[FAIL] " << gFailures << " USB sink check(s) failed." << std::endl;
        return 1;
    }
    std::cout << "[PASS] USB descriptor parsing, feedback decode, and packet sizing verified."
              << std::endl;
    std::cout << "[PASS] " << clockDomainChecks
              << " clock-domain checks verified (policy, wire names, status default)."
              << std::endl;
    std::cout << "[PASS] " << pullChecks
              << " pull/ASRC packet-fill checks verified (bit-exact payload, underrun, packing)."
              << std::endl;
    return 0;
}
