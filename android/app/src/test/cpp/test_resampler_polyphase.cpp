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

    // 3. Roundtrip SNR (44.1k -> 48k -> 44.1k) via planar processing (Part 2)
    {
        SincResampler upsampler;
        upsampler.setRates(44100.0, 48000.0);
        upsampler.setEnabled(true);
        upsampler.reset();

        SincResampler downsampler;
        downsampler.setRates(48000.0, 44100.0);
        downsampler.setEnabled(true);
        downsampler.reset();

        const int inBlock = 512;
        const int numBlocks = 32; // 16384 frames total
        const int testLen = inBlock * numBlocks;

        std::vector<float> inL(testLen);
        std::vector<float> inR(testLen);

        // 1 kHz test sine at 44.1kHz
        for (int i = 0; i < testLen; ++i) {
            float val = std::sin(2.0f * static_cast<float>(M_PI) * 1000.0f * static_cast<float>(i) / 44100.0f);
            inL[i] = val;
            inR[i] = val;
        }

        std::vector<float> downOutL;
        std::vector<float> downOutR;
        downOutL.reserve(testLen + 1024);
        downOutR.reserve(testLen + 1024);

        const int maxUpPerBlock = static_cast<int>(upsampler.maximumOutputFrames(inBlock)) + 64;
        std::vector<float> upBlockL(maxUpPerBlock);
        std::vector<float> upBlockR(maxUpPerBlock);
        float* const upPtrs[2] = { upBlockL.data(), upBlockR.data() };

        const int maxDownPerBlock = static_cast<int>(downsampler.maximumOutputFrames(maxUpPerBlock)) + 64;
        std::vector<float> downBlockL(maxDownPerBlock);
        std::vector<float> downBlockR(maxDownPerBlock);
        float* const downPtrs[2] = { downBlockL.data(), downBlockR.data() };

        for (int b = 0; b < numBlocks; ++b) {
            const float* const inPtrs[2] = { inL.data() + b * inBlock, inR.data() + b * inBlock };
            int upProduced = upsampler.processPlanar(inPtrs, upPtrs, inBlock, 2, maxUpPerBlock);
            if (upProduced > 0) {
                const float* const downInPtrs[2] = { upBlockL.data(), upBlockR.data() };
                int downProduced = downsampler.processPlanar(downInPtrs, downPtrs, upProduced, 2, maxDownPerBlock);
                for (int i = 0; i < downProduced; ++i) {
                    downOutL.push_back(downBlockL[i]);
                    downOutR.push_back(downBlockR[i]);
                }
            }
        }

        assert(!downOutL.empty());

        // Calculate phase-aligned fidelity / THD+N over steady-state region
        const int startIdx = 512;
        const int endIdx = static_cast<int>(std::min(static_cast<size_t>(testLen), downOutL.size())) - 512;
        const double omega = 2.0 * M_PI * 1000.0 / 44100.0;

        double sumSin2 = 0.0, sumCos2 = 0.0, sumSinCos = 0.0;
        double sumYSin = 0.0, sumYCos = 0.0;
        double totalPower = 0.0;

        for (int i = startIdx; i < endIdx; ++i) {
            double s = std::sin(omega * i);
            double c = std::cos(omega * i);
            double y = downOutL[i];
            sumSin2 += s * s;
            sumCos2 += c * c;
            sumSinCos += s * c;
            sumYSin += y * s;
            sumYCos += y * c;
            totalPower += y * y;
        }

        // Solve for fundamental components: y_hat = a*sin + b*cos
        double det = sumSin2 * sumCos2 - sumSinCos * sumSinCos;
        double a = (sumCos2 * sumYSin - sumSinCos * sumYCos) / det;
        double b = (sumSin2 * sumYCos - sumSinCos * sumYSin) / det;

        double noisePower = 0.0;
        double signalPower = 0.0;
        for (int i = startIdx; i < endIdx; ++i) {
            double yHat = a * std::sin(omega * i) + b * std::cos(omega * i);
            double diff = downOutL[i] - yHat;
            noisePower += diff * diff;
            signalPower += yHat * yHat;
        }

        double snrDb = 10.0 * std::log10(signalPower / std::max(noisePower, 1e-12));
        double levelErrDb = std::abs(20.0 * std::log10(std::sqrt(a * a + b * b)));
        std::cout << "  ✓ Roundtrip SNR (THD+N) = " << snrDb << " dB, level error = " << levelErrDb << " dB (> 55 dB target)." << std::endl;
        assert(snrDb > 55.0);
        assert(levelErrDb < 0.1);
    }

    std::cout << "[PASS] Polyphase SincResampler tests successfully passed!" << std::endl;
    return 0;
}
