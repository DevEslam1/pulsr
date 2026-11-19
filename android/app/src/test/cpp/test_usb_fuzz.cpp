// android/app/src/test/cpp/test_usb_fuzz.cpp
//
// 1,000,000 deterministic pseudo-random descriptor / control buffers through
// every host-verifiable USB parsing entry point:
//
//   UsbAudioSink::ParseSupportedRatesFromDescriptors
//   UsbAudioSink::ParseEndpointTiming
//   UsbAudioSink::DecodeFeedbackRatePerSec
//
// The bytes are attacker-controlled (a USB device is untrusted input); the
// nominal sample rate is not, so it is fuzzed over the supported ladder plus
// the degenerate 0/negative cases instead of over the whole int range. Every
// result is range-checked, not just "did not crash": a descriptor walk that
// invents a 40 GHz rate would otherwise pass this test.
//
// A watchdog thread aborts with [FAIL] if a single case stops making progress,
// so an infinite descriptor loop is a test failure rather than a hung build.
#include "../../main/cpp/UsbAudioSink.h"

#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <thread>
#include <vector>

using pulsr::UsbAudioSink;

namespace {

int gFailures = 0;
long long gChecks = 0;

void check(bool ok, const char* what) {
    ++gChecks;
    if (!ok) {
        std::cout << "[FAIL] " << what << std::endl;
        ++gFailures;
    }
}

std::atomic<uint64_t> gCase{0};
std::atomic<bool> gFinished{false};

void pushInterface(std::vector<uint8_t>& d, uint8_t ifaceNum, uint8_t alt, uint8_t klass,
                   uint8_t subclass, uint8_t endpoints = 0) {
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

void push3(std::vector<uint8_t>& d, int v) {
    d.push_back(static_cast<uint8_t>(v & 0xFF));
    d.push_back(static_cast<uint8_t>((v >> 8) & 0xFF));
    d.push_back(static_cast<uint8_t>((v >> 16) & 0xFF));
}

// UAC1 FORMAT_TYPE_I, discrete rates (or a continuous range when `discrete` is
// empty).
void pushFormatType(std::vector<uint8_t>& d, const std::vector<int>& discrete, int lo = 0,
                    int hi = 0) {
    const uint8_t freqType = discrete.empty() ? 0 : static_cast<uint8_t>(discrete.size());
    const int body = 8 + 3 * (discrete.empty() ? 2 : static_cast<int>(discrete.size()));
    d.push_back(static_cast<uint8_t>(body));
    d.push_back(0x24);  // CS_INTERFACE
    d.push_back(0x02);  // FORMAT_TYPE
    d.push_back(0x01);  // FORMAT_TYPE_I
    d.push_back(2);     // bNrChannels
    d.push_back(3);     // bSubframeSize
    d.push_back(24);    // bBitResolution
    d.push_back(freqType);
    if (discrete.empty()) {
        push3(d, lo);
        push3(d, hi);
    } else {
        for (int r : discrete) push3(d, r);
    }
}

void setConfigLength(std::vector<uint8_t>& d) {
    d[2] = static_cast<uint8_t>(d.size() & 0xFF);
    d[3] = static_cast<uint8_t>((d.size() >> 8) & 0xFF);
}

// A realistic configuration: audio control interface, an operational
// AudioStreaming alt 1 with a discrete-rate FORMAT_TYPE_I, an isochronous OUT
// endpoint and an async feedback IN endpoint.
std::vector<uint8_t> makeValidConfig() {
    std::vector<uint8_t> d = {9, 0x02, 0, 0, 0, 1, 0, 0x80, 50};
    pushInterface(d, 0, 0, 0x01, 0x01, 0);
    pushInterface(d, 1, 0, 0x01, 0x02, 0);
    pushInterface(d, 1, 1, 0x01, 0x02, 2);
    pushFormatType(d, {44100, 48000, 96000});
    d.insert(d.end(), {7, 0x05, 0x01, 0x05, 0xc0, 0x00, 1});  // iso OUT, 192 B
    d.insert(d.end(), {7, 0x05, 0x83, 0x11, 4, 0, 1});        // iso IN, feedback
    setConfigLength(d);
    return d;
}

uint64_t gRng = 0x243F6A8885A308D3ull;
uint64_t nextRandom() {
    gRng ^= gRng << 13;
    gRng ^= gRng >> 7;
    gRng ^= gRng << 17;
    return gRng;
}

const int kRates[] = {-1, 0, 8000, 11025, 16000, 22050, 32000, 44100,
                      48000, 88200, 96000, 176400, 192000, 352800, 384000,
                      705600, 768000, 1536000};

}  // namespace

int main() {
    std::cout << "[TEST] USB descriptor/control parser fuzz (1,000,000 cases)..."
              << std::endl;

    constexpr int kCases = 1000000;
    constexpr int kMaxLen = 512;
    const std::vector<uint8_t> valid = makeValidConfig();
    std::vector<uint8_t> buf(kMaxLen + 64);

    // Watchdog: a case that stops advancing for 10 s is a hang, not a slow test.
    std::thread watchdog([] {
        uint64_t last = 0;
        int stalls = 0;
        while (!gFinished.load(std::memory_order_acquire)) {
            std::this_thread::sleep_for(std::chrono::milliseconds(200));
            const uint64_t now = gCase.load(std::memory_order_relaxed);
            if (now == last) {
                if (++stalls >= 50) {
                    std::printf("[FAIL] watchdog: no progress at case %llu (hang)\n",
                                static_cast<unsigned long long>(now));
                    std::fflush(stdout);
                    std::_Exit(2);
                }
            } else {
                last = now;
                stalls = 0;
            }
        }
    });

    long long nonEmptyRates = 0;
    long long timedEndpoints = 0;
    long long feedbackDecodes = 0;
    long long rejectedFeedback = 0;
    long long rateViolationCases = 0;
    long long rateViolationValues = 0;
    long long timingViolations = 0;
    long long feedbackViolations = 0;
    int reportedRateExamples = 0;
    int reportedTimingExamples = 0;
    int reportedFeedbackExamples = 0;

    const auto start = std::chrono::steady_clock::now();
    for (int i = 0; i < kCases; ++i) {
        gCase.store(static_cast<uint64_t>(i), std::memory_order_relaxed);

        const uint64_t mode = nextRandom() % 8;
        size_t len = 0;
        if (mode <= 2) {
            // Fully random bytes: descriptor walks, zero bLength, oversized
            // lengths, truncated tails.
            len = static_cast<size_t>(nextRandom() % (kMaxLen + 1));
            size_t k = 0;
            while (k < len) {
                const uint64_t r = nextRandom();
                for (int b = 0; b < 8 && k < len; ++b, ++k) {
                    buf[k] = static_cast<uint8_t>((r >> (8 * b)) & 0xFF);
                }
            }
        } else if (mode == 3 || mode == 4) {
            // Every truncation prefix of a valid configuration.
            len = static_cast<size_t>(nextRandom() % (valid.size() + 1));
            std::memcpy(buf.data(), valid.data(), len);
        } else if (mode == 5 || mode == 6) {
            // Valid configuration with a handful of byte mutations: the shape
            // stays plausible, the fields lie.
            std::memcpy(buf.data(), valid.data(), valid.size());
            len = valid.size();
            const int mutations = 1 + static_cast<int>(nextRandom() % 8);
            for (int m = 0; m < mutations; ++m) {
                const size_t at = static_cast<size_t>(nextRandom() % len);
                buf[at] = static_cast<uint8_t>(nextRandom() & 0xFF);
            }
        } else {
            // Valid configuration with random bytes spliced in or cut out, which
            // exercises length bookkeeping that pure mutation cannot reach.
            std::memcpy(buf.data(), valid.data(), valid.size());
            len = valid.size();
            const int edits = 1 + static_cast<int>(nextRandom() % 4);
            for (int e = 0; e < edits && len > 4; ++e) {
                const size_t at = static_cast<size_t>(nextRandom() % len);
                const bool insert = (nextRandom() & 1) != 0;
                if (insert && len < kMaxLen) {
                    std::memmove(buf.data() + at + 1, buf.data() + at, len - at);
                    buf[at] = static_cast<uint8_t>(nextRandom() & 0xFF);
                    ++len;
                } else {
                    std::memmove(buf.data() + at, buf.data() + at + 1, len - at - 1);
                    --len;
                }
            }
        }

        // Half the cases ask the questions a real host would ask (the
        // operational interface/alt/endpoint at high speed), otherwise the
        // success path of ParseEndpointTiming is never reached by random
        // parameters; the other half stays fully random.
        const bool knownGoodQuery = (nextRandom() & 1) != 0;
        const int targetInterface = knownGoodQuery
                                        ? ((nextRandom() & 1) ? 1 : -1)
                                        : static_cast<int>(nextRandom() % 6) - 1;
        const auto rates = UsbAudioSink::ParseSupportedRatesFromDescriptors(
            buf.data(), len, targetInterface);
        if (!rates.empty()) ++nonEmptyRates;
        bool rateBad = false;
        for (int r : rates) {
            if (r < 8000 || r > 1536000) {
                ++rateViolationValues;
                rateBad = true;
                if (reportedRateExamples < 3) {
                    std::printf("[FAIL] rate %d outside 8k..1536k (case %d, len %zu, iface %d)\n",
                                r, i, len, targetInterface);
                    ++reportedRateExamples;
                }
            }
        }
        if (rateBad) ++rateViolationCases;

        const int iface = knownGoodQuery ? 1 : static_cast<int>(nextRandom() % 4);
        const int alt = knownGoodQuery ? 1 : static_cast<int>(nextRandom() % 4);
        const int endpoint = knownGoodQuery ? 0x01 : static_cast<int>(nextRandom() % 256);
        const int speed = knownGoodQuery ? 3 : static_cast<int>(nextRandom() % 6);
        const auto timing = UsbAudioSink::ParseEndpointTiming(
            buf.data(), len, iface, alt, endpoint, speed);
        if (timing.intervalUs > 0) ++timedEndpoints;
        if (timing.intervalUs < 0 || timing.intervalUs > 1000000 ||
            timing.maxPacketBytes < 0 || timing.maxPacketBytes > (1 << 22)) {
            ++timingViolations;
            if (reportedTimingExamples < 3) {
                std::printf("[FAIL] endpoint timing out of range: intervalUs %d, maxPacketBytes %d "
                            "(case %d, len %zu)\n",
                            timing.intervalUs, timing.maxPacketBytes, i, len);
                ++reportedTimingExamples;
            }
        }

        const int nominal = kRates[nextRandom() % (sizeof(kRates) / sizeof(kRates[0]))];
        const int feedbackLen = static_cast<int>(nextRandom() % 9);
        const int decoded =
            UsbAudioSink::DecodeFeedbackRatePerSec(buf.data(), feedbackLen, nominal);
        if (decoded != 0) ++feedbackDecodes; else ++rejectedFeedback;
        if (nominal <= 0) {
            if (decoded != 0) {
                ++feedbackViolations;
                if (reportedFeedbackExamples < 3) {
                    std::printf("[FAIL] feedback decode %d with nominal %d (case %d)\n", decoded,
                                nominal, i);
                    ++reportedFeedbackExamples;
                }
            }
        } else if (decoded != 0) {
            const double lo = static_cast<double>(nominal) * 0.999;
            const double hi = static_cast<double>(nominal) * 1.001;
            if (decoded < lo - 1.0 || decoded > hi + 1.0) {
                ++feedbackViolations;
                if (reportedFeedbackExamples < 3) {
                    std::printf("[FAIL] feedback %d outside +/-0.1%% of %d (case %d)\n", decoded,
                                nominal, i);
                    ++reportedFeedbackExamples;
                }
            }
        }
    }
    const auto elapsed = std::chrono::steady_clock::now() - start;
    const double seconds = std::chrono::duration<double>(elapsed).count();

    gFinished.store(true, std::memory_order_release);
    watchdog.join();

    std::cout << "[INFO] fuzz: " << kCases << " cases in " << seconds << " s ("
              << (static_cast<double>(kCases) / seconds / 1000.0) << " k cases/s), "
              << nonEmptyRates << " with rates, " << timedEndpoints << " with timing, "
              << feedbackDecodes << " feedback decodes accepted, " << rejectedFeedback
              << " rejected" << std::endl;
    std::cout << "[INFO] violations: " << rateViolationCases << " cases ("
              << rateViolationValues << " values) out of the 8k..1536k rate band, "
              << timingViolations << " endpoint-timing, " << feedbackViolations
              << " feedback" << std::endl;

    if (rateViolationCases != 0) {
        std::printf("[FAIL] ParseSupportedRatesFromDescriptors returned %lld out-of-band rate "
                    "value(s) from %lld of %d cases: the discrete FORMAT_TYPE_I path echoes any "
                    "non-zero 24-bit field without a range check (UsbAudioSink.cpp, 'if (r > 0)').\n",
                    rateViolationValues, rateViolationCases, kCases);
    }
    if (timingViolations != 0) {
        std::printf("[FAIL] ParseEndpointTiming returned %lld out-of-range result(s).\n",
                    timingViolations);
    }
    if (feedbackViolations != 0) {
        std::printf("[FAIL] DecodeFeedbackRatePerSec returned %lld out-of-contract result(s).\n",
                    feedbackViolations);
    }
    gFailures += static_cast<int>(rateViolationCases != 0) +
                 static_cast<int>(timingViolations != 0) +
                 static_cast<int>(feedbackViolations != 0);

    check(nonEmptyRates > 0 && timedEndpoints > 0,
          "fuzz corpus must actually reach the success paths, not just the reject paths");
    check(rejectedFeedback > 0, "fuzz corpus must exercise rejected feedback samples");
    check(seconds < 120.0, "1,000,000 fuzz cases must finish under 120 s");

    if (gFailures != 0) {
        std::cout << "[FAIL] " << gFailures << " fuzz invariant violation(s) in " << kCases
                  << " cases." << std::endl;
        return 1;
    }
    std::cout << "[PASS] USB parser fuzz: " << kCases << " cases, " << seconds
              << " s, no crash, no hang, no out-of-range result." << std::endl;
    return 0;
}
