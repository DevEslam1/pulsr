#include "../../main/cpp/SincResampler.h"
#include <cassert>
#include <iostream>
#include <vector>
#include <cmath>

void testRateConversion(double inRate, double outRate, const std::string& testName) {
    SincResampler resampler;
    resampler.setRates(inRate, outRate);
    resampler.setEnabled(true);
    resampler.reset();

    const int blockSize = 512;
    const int numBlocks = 20;

    std::vector<float> inInterleaved(blockSize * 2);
    std::vector<float> outInterleaved(blockSize * 2);

    for (int b = 0; b < numBlocks; ++b) {
        for (int i = 0; i < blockSize; ++i) {
            float t = static_cast<float>(b * blockSize + i) / static_cast<float>(inRate);
            inInterleaved[i * 2] = std::sin(2.0f * static_cast<float>(M_PI) * 440.0f * t);
            inInterleaved[i * 2 + 1] = std::cos(2.0f * static_cast<float>(M_PI) * 440.0f * t);
        }

        // processInterleaved is in-place and holds the N-in/N-out contract.
        outInterleaved = inInterleaved;
        int produced = resampler.processInterleaved(outInterleaved.data(), blockSize, 2);

        if (produced != blockSize) {
            std::cerr << "FAIL: " << testName << " block " << b 
                      << " expected " << blockSize << " frames, but got " << produced << std::endl;
            std::exit(1);
        }

        // Verify output is finite and non-empty
        for (int i = 0; i < blockSize * 2; ++i) {
            if (std::isnan(outInterleaved[i]) || std::isinf(outInterleaved[i])) {
                std::cerr << "FAIL: " << testName << " NaN/Inf detected in output" << std::endl;
                std::exit(1);
            }
        }
    }

    std::cout << "PASS: " << testName << " (" << inRate << " -> " << outRate << ") in==out frames invariant preserved." << std::endl;
}

void testPlanarQualityFidelity(double inRate, double outRate, int quality, const std::string& label) {
    SincResampler resampler;
    resampler.setRates(inRate, outRate);
    resampler.setQuality(quality);
    resampler.setEnabled(true);
    resampler.reset();

    const int inBlock = 512;
    const int maxOut = static_cast<int>(resampler.maximumOutputFrames(inBlock)) + 64;
    std::vector<float> inL(inBlock), inR(inBlock);
    std::vector<float> outL(maxOut), outR(maxOut);
    double steadySqSum = 0.0;
    int steadyCount = 0;

    for (int b = 0; b < 12; ++b) {
        for (int i = 0; i < inBlock; ++i) {
            const double t = static_cast<double>(b * inBlock + i) / inRate;
            inL[i] = static_cast<float>(std::sin(2.0 * M_PI * 1000.0 * t));
            inR[i] = static_cast<float>(std::cos(2.0 * M_PI * 1000.0 * t));
        }
        const float* inPtrs[2] = { inL.data(), inR.data() };
        float* outPtrs[2] = { outL.data(), outR.data() };
        const int produced = resampler.processPlanar(inPtrs, outPtrs, inBlock, 2, maxOut);
        for (int i = 0; i < produced; ++i) {
            if (!std::isfinite(outL[i]) || !std::isfinite(outR[i])) {
                std::cerr << "FAIL: " << label << " produced NaN/Inf" << std::endl;
                std::exit(1);
            }
            if (b >= 4) {
                steadySqSum += static_cast<double>(outL[i]) * outL[i];
                steadyCount++;
            }
        }
    }

    const double rms = std::sqrt(steadySqSum / std::max(1, steadyCount));
    const double expectedRms = 1.0 / std::sqrt(2.0);
    const double dbErr = std::abs(20.0 * std::log10(rms / expectedRms));
    if (steadyCount < 1000 || dbErr > 0.15) {
        std::cerr << "FAIL: " << label << " passband level err = " << dbErr << " dB" << std::endl;
        std::exit(1);
    }
    std::cout << "PASS: " << label << " planar fidelity verified (level err = " << dbErr << " dB)." << std::endl;
}

int main() {
    std::cout << "Running SincResampler C++ unit tests..." << std::endl;
    testRateConversion(44100.0, 48000.0, "44.1k -> 48k Upsample");
    testRateConversion(48000.0, 44100.0, "48k -> 44.1k Downsample");
    testRateConversion(96000.0, 48000.0, "96k -> 48k 2:1 Decimation");
    testRateConversion(48000.0, 48000.0, "48k -> 48k Identity Rate");
    testRateConversion(44100.0, 44100.0, "44.1k -> 44.1k Identity Rate");
    testPlanarQualityFidelity(44100.0, 48000.0, 3, "44.1k -> 48k Ultra Planar");
    testPlanarQualityFidelity(96000.0, 48000.0, 2, "96k -> 48k High Planar");
    testPlanarQualityFidelity(44100.0, 96000.0, 1, "44.1k -> 96k Standard Planar");
    std::cout << "All SincResampler C++ tests passed successfully!" << std::endl;
    return 0;
}
