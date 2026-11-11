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

using pulsr::UsbAudioSink;

namespace pulsr {
struct UsbAudioSinkTestAccess {
    static void prepare(UsbAudioSink& sink, int bytes = 4, int bits = 32,
                        size_t capacity = 128, size_t position = 0) {
        sink.Close();
        sink.sampleRate_ = 48000;
        sink.channels_ = 2;
        sink.bytesPerSample_ = bytes;
        sink.validBitDepth_ = bits;
        sink.ring_.assign(capacity, 0xAA);
        sink.ringRawDepth_.assign(capacity, 0);
        sink.ringMask_ = capacity - 1;
        sink.ringRead_.store(position);
        sink.ringWrite_.store(position);
        sink.producerOwner_.store(0);
        sink.producerRawDepth_.store(0);
        sink.lastError_.store(0);
        sink.channelMismatchFrames_.store(0);
        sink.exclusive_.store(true);
        sink.active_.store(true);
        sink.writerGate_.store(0);
    }
    static size_t written(UsbAudioSink& sink) { return sink.ringWrite_.load(); }
    static std::vector<uint8_t> bytes(UsbAudioSink& sink, size_t start, size_t count) {
        std::vector<uint8_t> out(count);
        for (size_t i = 0; i < count; ++i) out[i] = sink.ring_[(start + i) & sink.ringMask_];
        return out;
    }
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
    static int completion(const void* urb, bool feedback) {
        return UsbAudioSink::completionError(urb, feedback, 2, 16);
    }
    static int feedbackEndpoint(const uint8_t* config, size_t len, int iface,
                                int alt, int* packetSize) {
        return UsbAudioSink::findFeedbackEndpoint(config, len, iface, alt, packetSize);
    }
    static void setWrappedFill(UsbAudioSink& sink, size_t occupiedBytes) {
        prepare(sink, 4, 32, 65536, 0);
        const size_t readPos = std::numeric_limits<size_t>::max() - 1023;
        sink.ringRead_.store(readPos);
        sink.ringWrite_.store(readPos + occupiedBytes);
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
        sink.releaseResources(); // same rollback as Open after partial submit
        const bool startupRetained = sink.IsExclusive() && !sink.IsActive() && closed(sink) &&
            sink.hasOutstandingUrbs() && sink.urbStorage_.data() == startupStorage &&
            sink.urbStorage_.size() == 32;
        const bool restartBlocked = sink.Open(10, 1, 1, 1, 48000, 2, 4, 32) == UsbStreamResult::ClaimFailed &&
            sink.IsExclusive() && sink.urbStorage_.data() == startupStorage;
        bool feedback = false;
        size_t index = 99;
        const bool notSubmitted = !sink.markReaped(&unsubmitted, &feedback, &index) && sink.hasOutstandingUrbs();
        const bool startupReturned = sink.markReaped(&out, &feedback, &index) && !feedback && index == 0 &&
            !sink.hasOutstandingUrbs() && sink.IsExclusive();
        sink.Close();
        const bool startupReleased = !sink.IsExclusive() && sink.urbStorage_.empty();

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
        sink.Close();
        const bool retained = sink.IsExclusive() && sink.hasOutstandingUrbs() && sink.urbStorage_.data() == outStorage &&
            sink.feedbackUrbStorage_.data() == inStorage && sink.urbStorage_.size() == 32 &&
            sink.feedbackUrbStorage_.size() == 32;
        const bool unrecognized = !sink.markReaped(&unknown, &feedback, &index) && sink.hasOutstandingUrbs();
        const bool outOnly = sink.markReaped(&out, &feedback, &index) && !feedback && index == 0 &&
            sink.feedbackOwned_[0] == 1 && sink.hasOutstandingUrbs();
        const bool duplicate = !sink.markReaped(&out, &feedback, &index) && sink.feedbackOwned_[0] == 1;
        const bool inOnly = sink.markReaped(&in, &feedback, &index) && feedback && !sink.hasOutstandingUrbs();
        sink.Close(); // only exact submitted identities authorize freeing storage
        const bool released = !sink.IsExclusive() && sink.urbStorage_.empty() && sink.feedbackUrbStorage_.empty();
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
        check(!sink.WritePcm(source.data(), 2, 2, 32, 48000, 101) && sink.GetLastError() == ENOSPC &&
              Access::written(sink) == 0, "overrun must reject entire block, not partially publish");
        check(sink.WritePcm(source.data(), 1, 2, 32, 48000, 101), "fitting block may follow rejected overrun");
        check(Access::enter(sink, 101), "writer lease for close-drain test must admit");
        std::atomic<bool> closeReturned{false};
        std::thread closer([&] { sink.Close(); closeReturned.store(true); });
        while (!Access::closed(sink)) std::this_thread::yield();
        check(!closeReturned.load(), "Close must wait for admitted writer before freeing ring");
        Access::leave(sink);
        closer.join();
        check(closeReturned.load() && sink.GetRawPcmBitDepth() == 0 && !sink.IsActive(),
              "Close must drain writer and clear raw delivery status");
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

        // Ring occupancy across size_t wraparound + adaptive cadence steering.
        Access::setWrappedFill(sink, 38400); // 100.0 ms at 48 kHz / 2ch / 4B
        const double wrappedMs = sink.GetBufferedMs();
        sink.Close();
        check(std::abs(wrappedMs - 100.0) < 0.1,
              "GetBufferedMs must survive unsigned size_t wraparound");

        int steeredLow = UsbAudioSink::SteerPacketRateForRingFill(48000, 48000, 100, 1000);
        check(steeredLow < 48000 && steeredLow >= 47952,
              "low ring fill must steer cadence gently downward within -0.1%");
        for (int s = 0; s < 200; ++s) {
            steeredLow = UsbAudioSink::SteerPacketRateForRingFill(steeredLow, 48000, 0, 1000);
        }
        check(steeredLow == 47952, "low-fill cadence steering must clamp at -0.1%");
        int steeredHigh = UsbAudioSink::SteerPacketRateForRingFill(48000, 48000, 900, 1000);
        check(steeredHigh > 48000 && steeredHigh <= 48048,
              "high ring fill must steer cadence gently upward within +0.1%");
        check(UsbAudioSink::SteerPacketRateForRingFill(47980, 48000, 250, 1000) == 47980,
              "hysteresis zone must hold tuned cadence without chatter");
        int recovered = 47980;
        for (int s = 0; s < 100; ++s) {
            recovered = UsbAudioSink::SteerPacketRateForRingFill(recovered, 48000, 500, 1000);
        }
        check(recovered == 48000, "centered deadband must relax back to nominal rate");
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

    if (gFailures != 0) {
        std::cout << "[FAIL] " << gFailures << " USB sink check(s) failed." << std::endl;
        return 1;
    }
    std::cout << "[PASS] USB descriptor parsing, feedback decode, and packet sizing verified."
              << std::endl;
    return 0;
}
