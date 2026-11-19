// android/app/src/test/cpp/test_limiter_reset_live.cpp
//
// Item 1 regression: reset() on a LIVE lookahead limiter must re-prime, not go
// silent.
//
// reset() is what every seek / track start hits (AudioDspEngine::resetInternal),
// plus the sample-rate change and the NaN-recovery paths. Before the fix it
// zeroed the delay line but left bypassMix_ at 1.0 (fully wet) and cleared
// processingActive_, so the next lookaheadSamples_ + FILTER_DELAY output frames
// read the memset zeros and the stage then stepped hard back to level: one
// lookahead window of digital silence plus a broadband click at the seam.
//
// The test drives a limiter into steady-state limiting at 48 kHz, calls reset()
// directly mid-stream and asserts (a) no run of silence longer than the
// re-prime hold, (b) the ceiling is still enforced after the hold, (c) the stage
// is still actively limiting afterwards, and (d) a dormant limiter that is
// reset() still reports zero latency and no drain.
#include "../../main/cpp/LookaheadLimiter.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <memory>
#include <vector>

namespace {

int gFailures = 0;

void check(bool ok, const char* what) {
    if (!ok) {
        std::printf("[FAIL] %s\n", what);
        ++gFailures;
    }
}

constexpr double kPi = 3.14159265358979323846;
constexpr double kAmplitude = 0.9;   // ~ -0.9 dBFS, well above a -6 dB ceiling
constexpr double kCeilingDb = -6.0;
constexpr double kSampleRate = 48000.0;

}  // namespace

int main() {
    std::printf("[TEST] LookaheadLimiter reset() on an active stage...\n");

    // Heap: the limiter holds ~850 KB of delay/deque state, so two of them on
    // the stack would overflow the 1 MB Windows test-thread stack.
    auto limiter = std::make_unique<LookaheadLimiter>();
    limiter->setSampleRate(kSampleRate);
    limiter->configure(5.0, kCeilingDb, 50.0, true);
    limiter->setEnabled(true);
    limiter->setProcessingActive(true);

    const int block = 256;
    const int primedLatency =
        static_cast<int>(0.005 * kSampleRate) + LookaheadLimiter::FILTER_DELAY;
    const int maxZeroRunAllowed = primedLatency;
    std::vector<float> left(block);
    std::vector<float> right(block);
    double phase = 0.0;

    const auto renderBlock = [&]() {
        const double increment = 2.0 * kPi * 2000.0 / kSampleRate;
        for (int i = 0; i < block; ++i) {
            const float s = static_cast<float>(kAmplitude * std::sin(phase));
            left[i] = s;
            right[i] = s;
            phase += increment;
        }
        limiter->process(left.data(), right.data(), block);
    };

    // Settle: the insertion fade plus the attack ramp need far less than 60
    // blocks, and the gain reduction must be well below unity.
    for (int b = 0; b < 60; ++b) renderBlock();
    check(limiter->getCurrentGainReductionDb() < -1.0f,
          "limiter must be actively limiting before the reset");
    check(limiter->getLatencyFrames() == primedLatency,
          "48 kHz latency must be 5 ms + the true-peak FIR delay");

    // Simulate a seek / track start: the engine calls reset() bare.
    limiter->reset();
    check(limiter->getLatencyFrames() == primedLatency,
          "a live limiter must keep reporting its lookahead latency after reset()");
    check(!limiter->isDraining(),
          "a re-primed live limiter must not report a bypass drain");

    std::vector<float> out;
    out.reserve(static_cast<size_t>(block) * 40);
    for (int b = 0; b < 40; ++b) {
        renderBlock();
        out.insert(out.end(), left.begin(), left.end());
    }

    int zeroRun = 0;
    int maxZeroRun = 0;
    for (float v : out) {
        if (std::abs(v) < 1e-6f) {
            ++zeroRun;
            maxZeroRun = std::max(maxZeroRun, zeroRun);
        } else {
            zeroRun = 0;
        }
    }
    std::printf("      max silent run after reset(): %d frames (hold=%d)\n",
                maxZeroRun, maxZeroRunAllowed);
    check(maxZeroRun < maxZeroRunAllowed,
          "reset() must not emit a lookahead-length run of silence");

    const float ceiling = static_cast<float>(std::pow(10.0, kCeilingDb / 20.0));
    float peakAfterHold = 0.0f;
    for (size_t i = static_cast<size_t>(maxZeroRunAllowed) + block; i < out.size(); ++i) {
        peakAfterHold = std::max(peakAfterHold, std::abs(out[i]));
    }
    std::printf("      peak after the re-prime hold: %.4f (ceiling %.4f)\n",
                peakAfterHold, ceiling);
    check(peakAfterHold > 1e-4f, "the output must never collapse to silence");
    check(peakAfterHold <= ceiling * 1.02f,
          "the ceiling must still be enforced after the re-prime");
    check(limiter->getCurrentGainReductionDb() < -1.0f,
          "the limiter must still be limiting after the reset");

    // A dormant limiter (never activated) keeps the plain reset: no latency,
    // no residual drain.
    {
        auto dormant = std::make_unique<LookaheadLimiter>();
        dormant->setSampleRate(kSampleRate);
        dormant->configure(5.0, kCeilingDb, 50.0, true);
        dormant->reset();
        check(!dormant->isEnabled(), "the dormant limiter must stay disabled");
        check(dormant->getLatencyFrames() == 0,
              "a dormant limiter must report zero latency after reset()");
        check(!dormant->isDraining(),
              "a dormant limiter must not report a bypass drain");
    }

    if (gFailures != 0) {
        std::printf("[FAIL] %d limiter reset check(s) failed.\n", gFailures);
        return 1;
    }
    std::printf("[PASS] reset() re-primes a live limiter without silence.\n");
    return 0;
}
