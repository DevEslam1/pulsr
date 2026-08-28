// android/app/src/test/cpp/test_reverb_regression.cpp
#include "../../main/cpp/ConvolutionReverb.h"
#include <iostream>
#include <vector>
#include <cmath>
#include <cassert>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

int main() {
    std::cout << "[TEST] Running Reverb N-1 Single-Tap Delay Regression Test..." << std::endl;

    ConvolutionReverb reverb;
    reverb.setSampleRate(48000.0);
    reverb.setEnabled(true);
    reverb.setWetDry(1.0); // 100% wet
    reverb.setPredelay(0.0);

    // Create a 2048-tap single-tap IR at j=300 (partition 0)
    // IR length 2048 forces partitioned FFT mode (>1024 taps)
    const int irLen = 2048;
    std::vector<float> irInterleaved(irLen * 2, 0.0f);
    irInterleaved[300 * 2] = 1.0f;     // Left tap at sample 300
    irInterleaved[300 * 2 + 1] = 1.0f; // Right tap at sample 300

    bool loaded = reverb.loadCustomIR(irInterleaved.data(), irLen, 2);
    assert(loaded);
    reverb.reset();

    // 10 blocks of 512 samples = 5120 samples
    const int numBlocks = 10;
    const int blockSize = 512;
    const int totalFrames = numBlocks * blockSize;

    std::vector<float> inL(totalFrames);
    std::vector<float> inR(totalFrames);
    std::vector<float> outL(totalFrames, 0.0f);
    std::vector<float> outR(totalFrames, 0.0f);

    // Feed 1 kHz sine wave
    for (int i = 0; i < totalFrames; ++i) {
        float s = std::sin(2.0f * static_cast<float>(M_PI) * 1000.0f * static_cast<float>(i) / 48000.0f);
        inL[i] = s;
        inR[i] = s;
    }

    // Process block by block
    for (int b = 0; b < numBlocks; ++b) {
        reverb.process(&inL[b * blockSize], &inR[b * blockSize],
                       &outL[b * blockSize], &outR[b * blockSize], blockSize);
    }

    // Check outputs against expected delayed sine
    // In partitioned overlap-save, wet path latency is PARTITION_SIZE (512) + tap (300) = 812 samples
    const int totalDelay = 512 + 300;
    int mismatchCount = 0;
    float maxErr = 0.0f;

    for (int i = totalDelay; i < totalFrames; ++i) {
        float expected = inL[i - totalDelay];
        float actual = outL[i];
        float err = std::abs(expected - actual);
        if (err > maxErr) maxErr = err;
        if (err > 1e-4f) {
            mismatchCount++;
            if (mismatchCount <= 5) {
                std::cout << "  Mismatch at sample " << i << " (block " << (i / blockSize) 
                          << " pos " << (i % blockSize) << "): expected " << expected 
                          << ", got " << actual << " (err " << err << ")" << std::endl;
            }
        }
    }

    std::cout << "  Total mismatches (> 1e-4): " << mismatchCount << " / " << (totalFrames - totalDelay) << std::endl;
    std::cout << "  Max absolute error: " << maxErr << std::endl;

    if (mismatchCount > 0 || maxErr > 1e-3f) {
        std::cout << "  [FAIL] Output does not match delayed input!" << std::endl;
        return 1;
    }

    std::cout << "  [PASS] Single-tap delay exact match across all 10 blocks (max error: " << maxErr << ")." << std::endl;
    return 0;
}
