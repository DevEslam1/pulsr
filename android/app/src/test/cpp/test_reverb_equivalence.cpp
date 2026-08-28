// android/app/src/test/cpp/test_reverb_equivalence.cpp
#include "../../main/cpp/ConvolutionReverb.h"
#include <iostream>
#include <vector>
#include <cmath>
#include <cassert>
#include <random>

int main() {
    std::cout << "[TEST] Running 10s Pink Noise 40k-tap FFT vs Direct Convolution Equivalence Test..." << std::endl;

    const double sampleRate = 48000.0;
    const int irTaps = 40000; // 40k taps -> 79 partitions
    const int testSeconds = 10;
    const int totalFrames = static_cast<int>(sampleRate * testSeconds); // 480,000 samples

    // 1. Generate 40k-tap exponentially decaying random impulse response
    std::vector<float> irInterleaved(irTaps * 2);
    std::vector<float> irDirectL(irTaps);
    std::mt19937 irRng(1337);
    std::normal_distribution<float> irDist(0.0f, 1.0f);

    for (int i = 0; i < irTaps; ++i) {
        float env = std::exp(-5.0f * static_cast<float>(i) / static_cast<float>(irTaps));
        float tapL = env * irDist(irRng) * 0.005f;
        float tapR = env * irDist(irRng) * 0.005f;

        irInterleaved[i * 2] = tapL;
        irInterleaved[i * 2 + 1] = tapR;
        irDirectL[i] = tapL;
    }

    ConvolutionReverb reverb;
    reverb.setSampleRate(sampleRate);
    reverb.setEnabled(true);
    reverb.setWetDry(1.0); // 100% wet
    reverb.setPredelay(0.0);

    bool loaded = reverb.loadCustomIR(irInterleaved.data(), irTaps, 2);
    assert(loaded);
    reverb.reset();

    // 2. Generate 10s pink noise input (Paul Kellet's filtered white noise method)
    std::vector<float> inL(totalFrames);
    std::vector<float> inR(totalFrames);
    std::mt19937 noiseRng(4242);
    std::uniform_real_distribution<float> whiteDist(-1.0f, 1.0f);

    float b0 = 0.0f, b1 = 0.0f, b2 = 0.0f, b3 = 0.0f, b4 = 0.0f, b5 = 0.0f, b6 = 0.0f;
    for (int i = 0; i < totalFrames; ++i) {
        float white = whiteDist(noiseRng);
        b0 = 0.99886f * b0 + white * 0.0555179f;
        b1 = 0.99332f * b1 + white * 0.0750759f;
        b2 = 0.96900f * b2 + white * 0.1538520f;
        b3 = 0.86650f * b3 + white * 0.3104856f;
        b4 = 0.55000f * b4 + white * 0.5329522f;
        b5 = -0.7616f * b5 - white * 0.0168980f;
        float pink = (b0 + b1 + b2 + b3 + b4 + b5 + b6 + white * 0.5362f) * 0.11f;
        b6 = white * 0.115926f;

        inL[i] = pink;
        inR[i] = pink;
    }

    // 3. Process through FFT Partitioned Reverb in blocks of 512
    std::vector<float> fftOutL(totalFrames, 0.0f);
    std::vector<float> fftOutR(totalFrames, 0.0f);
    const int blockSize = 512;
    const int numBlocks = totalFrames / blockSize;

    for (int b = 0; b < numBlocks; ++b) {
        reverb.process(&inL[b * blockSize], &inR[b * blockSize],
                       &fftOutL[b * blockSize], &fftOutR[b * blockSize], blockSize);
    }

    // 4. Verification against direct convolution on a subset of test window
    // (after 40k IR decay transient + 512 block latency, sample 50,000 to 70,000 for direct evaluation)
    const int evalStart = 50000;
    const int evalEnd = 70000; // 20,000 samples direct convolution verification
    const int latency = 512;

    double sumSqError = 0.0;
    double sumSqRef = 0.0;
    float maxAbsDiff = 0.0f;

    for (int n = evalStart; n < evalEnd; ++n) {
        // Direct convolution: sum(in[n - latency - k] * ir[k])
        double directVal = 0.0;
        for (int k = 0; k < irTaps; ++k) {
            int inIdx = n - latency - k;
            if (inIdx >= 0) {
                directVal += inL[inIdx] * irDirectL[k];
            }
        }

        float fftVal = fftOutL[n];
        double diff = static_cast<double>(fftVal) - directVal;
        sumSqError += diff * diff;
        sumSqRef += directVal * directVal;

        if (std::abs(diff) > maxAbsDiff) {
            maxAbsDiff = static_cast<float>(std::abs(diff));
        }
    }

    double snrDb = 10.0 * std::log10(sumSqRef / (sumSqError + 1e-18));
    double errDb = -snrDb;

    std::cout << "  Evaluated 20,000 samples over 40k-tap IR." << std::endl;
    std::cout << "  Direct vs FFT Error: " << errDb << " dB (SNR: " << snrDb << " dB, max abs diff: " << maxAbsDiff << ")" << std::endl;

    assert(errDb < -60.0);
    std::cout << "  ✓ Error is < -60dB (Achieved " << errDb << " dB)." << std::endl;
    std::cout << "[PASS] Reference-equivalence test passed successfully!" << std::endl;
    return 0;
}
