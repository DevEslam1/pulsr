// android/app/src/test/cpp/test_limiter_true_peak.cpp
#include "../../main/cpp/LookaheadLimiter.h"
#include <iostream>
#include <vector>
#include <cmath>
#include <cassert>
#include <memory>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

int main() {
    std::cout << "[TEST] Running Lookahead Limiter True-Peak & Latency Tests..." << std::endl;

    LookaheadLimiter limiter;
    limiter.setSampleRate(48000.0);
    limiter.configure(5.0, -0.2, 50.0, true);
    limiter.setEnabled(true);
    limiter.reset();

    // 1. Latency Invariant
    // The reported latency includes the 12-tap true-peak FIR group delay,
    // not just the lookahead window.
    assert(limiter.getLatencyFrames() ==
           static_cast<int>(5.0 * 0.001 * 48000.0) +
               LookaheadLimiter::FILTER_DELAY);
    std::cout << "  ✓ Lookahead latency exactness verified (" << limiter.getLatencyFrames() << " frames)." << std::endl;

    // 2. +6dBFS Sine Input True-Peak Ceiling Test
    const int testFrames = 48000;
    std::vector<float> hotAudio(testFrames * 2);

    // +6dBFS = amplitude ~2.0
    const float inputAmp = 2.0f;
    for (int i = 0; i < testFrames; ++i) {
        float s = inputAmp * std::sin(2.0f * static_cast<float>(M_PI) * 1000.0f * static_cast<float>(i) / 48000.0f);
        hotAudio[i * 2] = s;
        hotAudio[i * 2 + 1] = s;
    }

    limiter.processInterleaved(hotAudio.data(), testFrames, 2);

    // Target threshold for -0.2dB is ~0.9772
    const float targetThreshold = std::pow(10.0f, -0.2f / 20.0f);
    float maxOutputPeak = 0.0f;

    // Evaluate steady state (skip initial lookahead lead-in)
    for (int i = limiter.getLatencyFrames() * 2; i < testFrames * 2; ++i) {
        maxOutputPeak = std::max(maxOutputPeak, std::abs(hotAudio[i]));
    }

    assert(maxOutputPeak <= targetThreshold + 0.02f);
    std::cout << "  ✓ +6dBFS input contained to " << maxOutputPeak << " (ceiling: " << targetThreshold << ")." << std::endl;

    // 3. Small gain reduction ramps smoothly across the lookahead window
    //    instead of collapsing to the 1/lookahead floor.
    {
        // Heap: the limiter holds ~850 KB of delay/deque state and two on the
        // stack overflow the 1 MB Windows test-thread stack.
        auto slow = std::make_unique<LookaheadLimiter>();
        slow->setSampleRate(48000.0);
        slow->configure(5.0, -0.5, 50.0, true);
        slow->setEnabled(true);
        slow->reset();
        std::vector<float> early(10 * 2, 1.0f);
        slow->processInterleaved(early.data(), 10, 2);
        const float earlyDb = -slow->getCurrentGainReductionDb();
        assert(earlyDb < 0.1f);

        // Let the initial step-response overshoot leave the lookahead window
        // and the release settle back to the steady 0.5 dB reduction.
        std::vector<float> settle(40000 * 2, 1.0f);
        slow->processInterleaved(settle.data(), 40000, 2);
        std::vector<float> tail(256 * 2, 1.0f);
        slow->processInterleaved(tail.data(), 256, 2);
        const float settledDb = -slow->getCurrentGainReductionDb();
        assert(settledDb > 0.45f && settledDb <= 0.51f);
        std::cout << "  ✓ 0.5 dB attack is smooth (early " << earlyDb
                  << " dB, settled " << settledDb << " dB)." << std::endl;
    }

    // 4. Latency is reported only while the delayed/processed path is active.
    {
        auto l = std::make_unique<LookaheadLimiter>();
        l->setSampleRate(48000.0);
        l->configure(5.0, -0.2, 50.0, true);
        l->setEnabled(false);
        assert(l->getLatencyFrames() == 0);
        l->setEnabled(true);
        l->reset();
        assert(l->getLatencyFrames() ==
               static_cast<int>(5.0 * 0.001 * 48000.0) + LookaheadLimiter::FILTER_DELAY);
        std::cout << "  ✓ latency reports 0 when bypassed and L+F when active." << std::endl;
    }

    std::cout << "[PASS] Lookahead Limiter True-Peak tests successfully passed!" << std::endl;
    return 0;
}
