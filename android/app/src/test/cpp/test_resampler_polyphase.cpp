// android/app/src/test/cpp/test_resampler_polyphase.cpp
#include "../../main/cpp/SincResampler.h"
#include <iostream>
#include <vector>
#include <cmath>
#include <cassert>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

int main() {
    std::cout << "[TEST] Running Polyphase SincResampler Invariant & Fidelity Tests..." << std::endl;

    SincResampler resampler;

    // 1. Latency Exactness Test
    assert(resampler.getLatencyFrames() == SincResampler::HALF_TAPS);
    std::cout << "  ✓ Latency reporting exactness verified (" << resampler.getLatencyFrames() << " frames group delay)." << std::endl;

    // 2. Exact Frame Invariant across multiple sample rate pairs over 10,000,000 frames total
    struct RatePair { double inRate; double outRate; const char* name; };
    RatePair pairs[] = {
        { 44100.0, 48000.0, "44.1k -> 48k" },
        { 48000.0, 44100.0, "48k -> 44.1k" },
        { 48000.0, 96000.0, "48k -> 96k" },
        { 88200.0, 48000.0, "88.2k -> 48k" },
        { 48000.0, 48000.0, "Identity 48k -> 48k" }
    };

    const int blockSize = 512;
    const int blocksPerPair = 4000; // 4000 * 512 * 5 = ~10.24M samples processed

    for (const auto& pair : pairs) {
        resampler.setRates(pair.inRate, pair.outRate);
        resampler.reset();

        std::vector<float> buffer(blockSize * 2, 0.0f);
        int totalOutFrames = 0;

        for (int b = 0; b < blocksPerPair; ++b) {
            for (int i = 0; i < blockSize * 2; ++i) {
                buffer[i] = std::sin(static_cast<float>(i + b * blockSize) * 0.05f);
            }

            int outFrames = resampler.processInterleaved(buffer.data(), blockSize, 2);
            assert(outFrames == blockSize);
            totalOutFrames += outFrames;
        }

        assert(totalOutFrames == blockSize * blocksPerPair);
        std::cout << "  ✓ Frame invariant passed for " << pair.name << " (" << totalOutFrames << " frames, 0 drift)." << std::endl;
    }

    // 3. Roundtrip SNR (44.1k -> 48k -> 44.1k)
    {
        SincResampler upsampler;
        upsampler.setRates(44100.0, 48000.0);

        SincResampler downsampler;
        downsampler.setRates(48000.0, 44100.0);

        const int testLen = 8192;
        std::vector<float> input(testLen * 2);
        std::vector<float> processed(testLen * 2);

        // 1 kHz test sine at 44.1kHz
        for (int i = 0; i < testLen; ++i) {
            float val = std::sin(2.0f * static_cast<float>(M_PI) * 1000.0f * static_cast<float>(i) / 44100.0f);
            input[i * 2] = val;
            input[i * 2 + 1] = val;
            processed[i * 2] = val;
            processed[i * 2 + 1] = val;
        }

        upsampler.processInterleaved(processed.data(), testLen, 2);
        downsampler.processInterleaved(processed.data(), testLen, 2);

        // Calculate SNR excluding filter warm-up
        double signalPower = 0.0;
        double noisePower = 0.0;
        const int startIdx = 100;
        const int endIdx = testLen - 100;

        for (int i = startIdx; i < endIdx; ++i) {
            float inVal = input[i * 2];
            float outVal = processed[i * 2];
            signalPower += inVal * inVal;
            noisePower += (inVal - outVal) * (inVal - outVal);
        }

        double snrDb = 10.0 * std::log10(signalPower / std::max(noisePower, 1e-12));
        assert(snrDb > 85.0);
        std::cout << "  ✓ Roundtrip SNR 44.1k -> 48k -> 44.1k = " << snrDb << " dB (> 85dB target)." << std::endl;
    }

    std::cout << "[PASS] Polyphase SincResampler tests successfully passed!" << std::endl;
    return 0;
}
