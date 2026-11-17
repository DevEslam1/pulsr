// android/app/src/test/cpp/test_limiter_rate_change.cpp
//
// Item 1 regression: a sample-rate change on an ACTIVE lookahead limiter must
// re-prime the stage, not go silent.
//
// Before the fix LookaheadLimiter::setSampleRate() called configure() and then an
// unconditional reset(). reset() zeroes the delay line but restores bypassMix_ to
// 1.0 (fully wet) and clears processingActive_, so the very next
// lookaheadSamples_ + FILTER_DELAY output frames were the *zeroed* delay line:
// one lookahead window of digital silence in the middle of a playing track, and
// the stage then had to re-fade in from nothing.
//
// The test drives the limiter into steady-state limiting at 48 kHz, changes the
// rate to 96 kHz mid-stream and asserts (a) no run of silence longer than the
// crossfade hold, (b) the ceiling is still enforced after the hold, and (c) the
// stage is still actively limiting afterwards.
#include "../../main/cpp/LookaheadLimiter.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
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

}  // namespace

int main() {
    std::printf("[TEST] LookaheadLimiter sample-rate change on an active stage...\n");

    LookaheadLimiter limiter;
    limiter.setSampleRate(48000.0);
    limiter.configure(5.0, kCeilingDb, 50.0, true);
    limiter.setEnabled(true);
    limiter.setProcessingActive(true);

    const int block = 256;
    const int maxZeroRunAllowed =
        static_cast<int>(0.005 * 96000.0) + LookaheadLimiter::FILTER_DELAY;
    std::vector<float> left(block);
    std::vector<float> right(block);
    double phase = 0.0;

    const auto renderBlock = [&](double rate) {
        const double increment = 2.0 * kPi * 2000.0 / rate;
        for (int i = 0; i < block; ++i) {
            const float s = static_cast<float>(kAmplitude * std::sin(phase));
            left[i] = s;
            right[i] = s;
            phase += increment;
        }
        limiter.process(left.data(), right.data(), block);
    };

    // Settle at 48 kHz: the insertion fade plus the attack ramp need far less
    // than 60 blocks, and the gain reduction must be well below unity.
    for (int b = 0; b < 60; ++b) renderBlock(48000.0);
    check(limiter.getCurrentGainReductionDb() < -1.0f,
          "limiter must be actively limiting before the rate change");
    check(limiter.getLatencyFrames() == 240 + LookaheadLimiter::FILTER_DELAY,
          "48 kHz latency must be 5 ms + the true-peak FIR delay");

    limiter.setSampleRate(96000.0);
    check(limiter.getLatencyFrames() == maxZeroRunAllowed,
          "96 kHz latency must follow the new lookahead length");

    std::vector<float> out;
    out.reserve(static_cast<size_t>(block) * 40);
    for (int b = 0; b < 40; ++b) {
        renderBlock(96000.0);
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
    std::printf("      max silent run after the rate change: %d frames (hold=%d)\n",
                maxZeroRun, maxZeroRunAllowed);
    check(maxZeroRun < maxZeroRunAllowed,
          "rate change must not emit a lookahead-length run of silence");

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
    check(limiter.getCurrentGainReductionDb() < -1.0f,
          "the limiter must still be limiting after the rate change");
    check(!limiter.isDraining(), "a live limiter must not report a bypass drain");

    // A dormant limiter keeps the plain reset: no latency, no residual state.
    {
        LookaheadLimiter dormant;
        dormant.setSampleRate(48000.0);
        dormant.configure(5.0, kCeilingDb, 50.0, true);
        dormant.setSampleRate(96000.0);
        check(dormant.getLatencyFrames() == 0,
              "a dormant limiter must stay bypassed after a rate change");
    }

    if (gFailures != 0) {
        std::printf("[FAIL] %d limiter rate-change check(s) failed.\n", gFailures);
        return 1;
    }
    std::printf("[PASS] Live sample-rate change re-primes the limiter without silence.\n");
    return 0;
}
