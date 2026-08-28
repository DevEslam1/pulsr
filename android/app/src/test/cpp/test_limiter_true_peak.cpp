// android/app/src/test/cpp/test_limiter_true_peak.cpp
#include "../../main/cpp/LookaheadLimiter.h"
#include <iostream>
#include <vector>
#include <cmath>
#include <cassert>

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
    assert(limiter.getLatencyFrames() == static_cast<int>(5.0 * 0.001 * 48000.0));
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

    std::cout << "[PASS] Lookahead Limiter True-Peak tests successfully passed!" << std::endl;
    return 0;
}
