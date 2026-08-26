#include "DsdDecoder.h"
#include <cmath>
#include <cstring>
#include <algorithm>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

DsdDecoder::DsdDecoder() {
    configure(DsdRate::DSD64, 176400, DsdBitOrder::MSB_FIRST);
    reset();
}

void DsdDecoder::configure(DsdRate rate, int targetPcmSampleRate, DsdBitOrder bitOrder) {
    dsdRate_ = rate;
    targetRate_ = (targetPcmSampleRate > 0) ? targetPcmSampleRate : 176400;
    bitOrder_ = bitOrder;

    double dsdFreq = 44100.0 * static_cast<int>(dsdRate_);
    decimationRatio_ = std::max(1, static_cast<int>(std::round(dsdFreq / targetRate_)));

    // Design Lowpass FIR filter with cutoff ~40 kHz to remove 1-bit high frequency noise
    double fc = 40000.0 / dsdFreq;
    double sum = 0.0;
    for (int i = 0; i < FIR_TAPS; ++i) {
        double n = i - (FIR_TAPS - 1) / 2.0;
        double sincVal = (std::abs(n) < 1e-6) ? 1.0 : std::sin(2.0 * M_PI * fc * n) / (M_PI * n);
        // Hamming window
        double window = 0.54 - 0.46 * std::cos(2.0 * M_PI * i / (FIR_TAPS - 1));
        firCoeffs_[i] = static_cast<float>(sincVal * window);
        sum += firCoeffs_[i];
    }
    if (sum > 0.0001) {
        for (int i = 0; i < FIR_TAPS; ++i) firCoeffs_[i] /= static_cast<float>(sum);
    }
    reset();
}

void DsdDecoder::reset() {
    std::memset(historyL_, 0, sizeof(historyL_));
    std::memset(historyR_, 0, sizeof(historyR_));
    historyIdx_ = 0;
}

int DsdDecoder::decodeDsdBytes(const uint8_t* dsdL, const uint8_t* dsdR, int byteCount,
                              float* pcmOutInterleaved, int maxPcmFrames) {
    if (!dsdL || !dsdR || byteCount <= 0 || !pcmOutInterleaved || maxPcmFrames <= 0) {
        return 0;
    }

    int totalBits = byteCount * 8;
    int pcmFrames = 0;

    // Convert bits (+1.0 for 1, -1.0 for 0) and filter/decimate
    for (int b = 0; b < totalBits && pcmFrames < maxPcmFrames; ++b) {
        int byteIdx = b / 8;
        // MSB-first for DSF, LSB-first for DFF
        int bitIdx = (bitOrder_ == DsdBitOrder::MSB_FIRST) ? (7 - (b % 8)) : (b % 8);

        float sampleL = ((dsdL[byteIdx] >> bitIdx) & 1) ? 1.0f : -1.0f;
        float sampleR = ((dsdR[byteIdx] >> bitIdx) & 1) ? 1.0f : -1.0f;

        historyL_[historyIdx_] = sampleL;
        historyR_[historyIdx_] = sampleR;
        historyIdx_ = (historyIdx_ + 1) % FIR_TAPS;

        // Decimate
        if (b % decimationRatio_ == 0) {
            float outL = 0.0f;
            float outR = 0.0f;
            int hIdx = historyIdx_;
            for (int tap = 0; tap < FIR_TAPS; ++tap) {
                hIdx--;
                if (hIdx < 0) hIdx += FIR_TAPS;
                outL += historyL_[hIdx] * firCoeffs_[tap];
                outR += historyR_[hIdx] * firCoeffs_[tap];
            }

            // DSD modulation level is typically -6dB relative to 0dBFS PCM
            constexpr float dsdPcmGain = 1.4142f; // ~ +3dB boost for standard loudness match
            pcmOutInterleaved[pcmFrames * 2] = std::max(-1.0f, std::min(outL * dsdPcmGain, 1.0f));
            pcmOutInterleaved[pcmFrames * 2 + 1] = std::max(-1.0f, std::min(outR * dsdPcmGain, 1.0f));
            pcmFrames++;
        }
    }

    return pcmFrames;
}
