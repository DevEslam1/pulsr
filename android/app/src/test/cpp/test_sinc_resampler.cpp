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

        int produced = resampler.processInterleaved(
            inInterleaved.data(), blockSize, outInterleaved.data(), blockSize);

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

int main() {
    std::cout << "Running SincResampler C++ unit tests..." << std::endl;
    testRateConversion(44100.0, 48000.0, "44.1k -> 48k Upsample");
    testRateConversion(48000.0, 44100.0, "48k -> 44.1k Downsample");
    testRateConversion(96000.0, 48000.0, "96k -> 48k 2:1 Decimation");
    testRateConversion(48000.0, 48000.0, "48k -> 48k Identity Rate");
    testRateConversion(44100.0, 44100.0, "44.1k -> 44.1k Identity Rate");
    std::cout << "All SincResampler C++ tests passed successfully!" << std::endl;
    return 0;
}
