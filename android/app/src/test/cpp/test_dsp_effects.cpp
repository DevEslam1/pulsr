#include "../../main/cpp/ConvolutionReverb.h"
#include "../../main/cpp/LookaheadLimiter.h"
#include "../../main/cpp/Crossfeed.h"
#include "../../main/cpp/ParametricEQ.h"
#include "../../main/cpp/DsdDecoder.h"
#include <cassert>
#include <iostream>
#include <vector>
#include <cmath>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

void testConvolutionReverbUnityGain() {
    ConvolutionReverb reverb;
    reverb.setSampleRate(48000.0);
    reverb.setEnabled(true);
    reverb.setWetDry(1.0f); // 100% wet
    reverb.setPreset(ReverbPreset::ConcertHall);
    reverb.reset();

    const int blockSize = 1024;
    const int blocks = 50;
    std::vector<float> buffer(blockSize * 2);

    float maxOutput = 0.0f;

    for (int b = 0; b < blocks; ++b) {
        for (int i = 0; i < blockSize; ++i) {
            float t = static_cast<float>(b * blockSize + i) / 48000.0f;
            // Full-scale sine wave input (1.0 amplitude)
            float sample = std::sin(2.0f * static_cast<float>(M_PI) * 1000.0f * t);
            buffer[i * 2] = sample;
            buffer[i * 2 + 1] = sample;
        }

        reverb.processInterleaved(buffer.data(), blockSize);

        for (int i = 0; i < blockSize * 2; ++i) {
            float val = std::abs(buffer[i]);
            if (val > maxOutput) maxOutput = val;
            if (val > 1.0001f) {
                std::cerr << "FAIL: ConvolutionReverb exceeded unity gain: " << val << std::endl;
                std::exit(1);
            }
        }
    }

    std::cout << "PASS: ConvolutionReverb constant-power crossfading unity test (maxOutput = " 
              << maxOutput << " <= 1.0)." << std::endl;
}

void testLookaheadLimiterCeiling() {
    LookaheadLimiter limiter;
    limiter.setSampleRate(48000.0);
    limiter.configure(3.0, -0.2, 50.0);
    limiter.setEnabled(true);
    limiter.reset();

    const int blockSize = 512;
    std::vector<float> buffer(blockSize * 2);

    // Feed massive +12dB clipped transient (amplitude 4.0)
    for (int i = 0; i < blockSize * 2; ++i) {
        buffer[i] = (i % 2 == 0) ? 4.0f : -4.0f;
    }

    limiter.processInterleaved(buffer.data(), blockSize);

    for (int i = 0; i < blockSize * 2; ++i) {
        if (std::abs(buffer[i]) > 1.0001f) {
            std::cerr << "FAIL: LookaheadLimiter ceiling exceeded: " << buffer[i] << std::endl;
            std::exit(1);
        }
    }

    std::cout << "PASS: LookaheadLimiter ceiling invariant preserved (|out| <= 1.0)." << std::endl;
}

int main() {
    std::cout << "Running DSP effects C++ unit tests..." << std::endl;
    testConvolutionReverbUnityGain();
    testLookaheadLimiterCeiling();
    std::cout << "All DSP effects C++ tests passed successfully!" << std::endl;
    return 0;
}
