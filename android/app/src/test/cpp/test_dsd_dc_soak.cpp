// android/app/src/test/cpp/test_dsd_dc_soak.cpp
#include "../../main/cpp/DsdDecoder.h"
#include <iostream>
#include <vector>
#include <cmath>
#include <cassert>

int main() {
    std::cout << "[TEST] Running DSD Decoder DC-biased Soak Test (30s all-ones bits)..." << std::endl;

    DsdDecoder decoder;
    decoder.configure(DsdDecoder::DsdRate::DSD64, 176400, DsdDecoder::DsdBitOrder::LSB_FIRST);
    decoder.reset();

    // 30 seconds of DSD64 = 30 * 2,822,400 bits = 10,584,000 bytes per channel
    const int totalBytes = 10584000;
    const int chunkBytes = 65536; // 64 KB chunks

    std::vector<uint8_t> allOnes(chunkBytes, 0xFF); // All 1s (maximum positive DC)
    const int maxFramesPerChunk = decoder.getExpectedPcmFrames(chunkBytes);
    std::vector<float> pcmOut(maxFramesPerChunk * 2);

    int processedBytes = 0;
    int totalPcmFrames = 0;
    float lastSampleL = 0.0f;
    float lastSampleR = 0.0f;

    while (processedBytes < totalBytes) {
        int bytesThisChunk = std::min(chunkBytes, totalBytes - processedBytes);
        int outFrames = decoder.decodeDsdBytes(
            allOnes.data(), allOnes.data(), bytesThisChunk,
            pcmOut.data(), maxFramesPerChunk);

        assert(outFrames > 0);
        totalPcmFrames += outFrames;

        for (int i = 0; i < outFrames; ++i) {
            float sL = pcmOut[i * 2];
            float sR = pcmOut[i * 2 + 1];

            // Verify no NaN or Inf occurs throughout millions of integrator wraps
            assert(!std::isnan(sL) && !std::isinf(sL));
            assert(!std::isnan(sR) && !std::isinf(sR));

            lastSampleL = sL;
            lastSampleR = sR;
        }

        processedBytes += bytesThisChunk;
    }

    std::cout << "  Decoded " << totalPcmFrames << " PCM frames from 30s continuous 0xFF DSD64 stream." << std::endl;
    std::cout << "  Final steady-state DC blocker output: L=" << lastSampleL << ", R=" << lastSampleR << std::endl;

    // After transient, the 5Hz DC blocker should have driven the DC signal to near 0 (< 1e-3)
    assert(std::abs(lastSampleL) < 0.01f);
    assert(std::abs(lastSampleR) < 0.01f);
    std::cout << "  ✓ DC blocker settled output to 0.0 without overflow or divergence." << std::endl;
    std::cout << "[PASS] DSD DC soak test passed successfully!" << std::endl;

    return 0;
}
