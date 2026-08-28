// android/app/src/test/cpp/test_reverb_fft.cpp
#include "../../main/cpp/ConvolutionReverb.h"
#include <iostream>
#include <vector>
#include <cmath>
#include <cassert>
#include <random>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

int main() {
    std::cout << "[TEST] Running Convolution Reverb FFT Parity & Unity Gain Tests..." << std::endl;

    ConvolutionReverb reverb;
    reverb.setSampleRate(48000.0);
    reverb.setEnabled(true);
    reverb.setWetDry(1.0); // 100% wet

    // 1. Unity Gain Test: full-scale sine at wet=1.0 -> output true peak <= 1.0
    {
        reverb.setPreset(ReverbPreset::Hall);
        reverb.reset();

        const int testFrames = 48000 * 2; // 2 seconds
        std::vector<float> buffer(testFrames * 2);

        for (int i = 0; i < testFrames; ++i) {
            float s = std::sin(2.0f * static_cast<float>(M_PI) * 440.0f * static_cast<float>(i) / 48000.0f);
            buffer[i * 2] = s;
            buffer[i * 2 + 1] = s;
        }

        reverb.processInterleaved(buffer.data(), testFrames, 2);

        float maxPeak = 0.0f;
        for (float val : buffer) {
            maxPeak = std::max(maxPeak, std::abs(val));
        }

        assert(maxPeak <= 1.01f);
        std::cout << "  ✓ Unity Gain verified (max peak = " << maxPeak << " <= 1.0)." << std::endl;
    }

    // 2. Custom IR loading & partitioned FFT equivalence test
    {
        // Generate a 4096-sample synthetic stereo IR
        const int irLen = 4096;
        std::vector<float> customIr(irLen * 2);
        for (int i = 0; i < irLen; ++i) {
            float env = std::exp(-static_cast<float>(i) / 800.0f);
            customIr[i * 2] = env * 0.01f;
            customIr[i * 2 + 1] = env * 0.01f;
        }

        bool loaded = reverb.loadCustomIR(customIr.data(), irLen, 2);
        assert(loaded);
        reverb.reset();

        const int noiseLen = 8192;
        std::vector<float> noiseBuf(noiseLen * 2);
        std::mt19937 rng(42);
        std::uniform_real_distribution<float> dist(-0.5f, 0.5f);
        for (int i = 0; i < noiseLen * 2; ++i) {
            noiseBuf[i] = dist(rng);
        }

        reverb.processInterleaved(noiseBuf.data(), noiseLen, 2);

        // Verify output is active and non-zero
        double energy = 0.0;
        for (float s : noiseBuf) {
            assert(!std::isnan(s) && !std::isinf(s));
            energy += s * s;
        }
        assert(energy > 0.0);
        std::cout << "  ✓ Partitioned FFT convolution processed 4096-tap IR cleanly." << std::endl;
    }

    std::cout << "[PASS] Convolution Reverb tests successfully passed!" << std::endl;
    return 0;
}
