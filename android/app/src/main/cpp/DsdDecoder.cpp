// android/app/src/main/cpp/DsdDecoder.cpp
#include "DsdDecoder.h"
#include <cstring>
#include <cmath>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

DsdDecoder::DsdDecoder() {
    configure(DsdRate::DSD64, 176400, DsdBitOrder::LSB_FIRST);
    reset();
}

void DsdDecoder::generateFilters() {
    // Stage 1 output sample rate is (44100 * dsdRate) / 8 = 352.8 kHz for DSD64
    const double stage1Rate = (44100.0 * static_cast<double>(dsdRate_)) / 8.0;
    // Anti-aliasing cutoff at 0.42 * targetRate_ (e.g. 20.16 kHz for 48kHz target rate)
    const double cutoff = std::min(0.48, (0.42 * static_cast<double>(targetRate_)) / stage1Rate);

    double sum = 0.0;
    for (int i = 0; i < DECIMATION_TAPS; ++i) {
        int n = i - DECIMATION_HALF;
        double val = 0.0;
        if (n == 0) {
            val = 2.0 * cutoff;
        } else {
            val = std::sin(2.0 * M_PI * cutoff * n) / (M_PI * n);
        }

        // 4-term Blackman-Harris window for > 92 dB stopband attenuation
        double w = 2.0 * M_PI * i / (DECIMATION_TAPS - 1);
        double win = 0.35875 - 0.48829 * std::cos(w) + 0.14128 * std::cos(2.0 * w) - 0.01168 * std::cos(3.0 * w);
        decimationCoeffs_[i] = static_cast<float>(val * win);
        sum += decimationCoeffs_[i];
    }

    if (std::abs(sum) > 1e-6) {
        float invSum = static_cast<float>(1.0 / sum);
        for (int i = 0; i < DECIMATION_TAPS; ++i) {
            decimationCoeffs_[i] *= invSum;
        }
    }

    // 5Hz DC blocker pole: R = 1 - 2*pi*5 / targetRate
    dcPole_ = static_cast<float>(1.0 - (2.0 * M_PI * 5.0 / targetRate_));
}

void DsdDecoder::configure(DsdRate rate, int targetPcmSampleRate, DsdBitOrder bitOrder) {
    dsdRate_ = rate;
    targetRate_ = std::clamp(targetPcmSampleRate, 44100, 768000);
    bitOrder_ = bitOrder;

    const double dsdFrequencyHz = 44100.0 * static_cast<double>(dsdRate_);
    decimationRatio_ = dsdFrequencyHz / static_cast<double>(targetRate_);

    generateFilters();
    reset();
}

void DsdDecoder::reset() {
    cicL_ = {};
    cicR_ = {};
    cicCount_ = 0;
    std::memset(stage2RingL_, 0, sizeof(stage2RingL_));
    std::memset(stage2RingR_, 0, sizeof(stage2RingR_));
    stage2WriteIdx_ = 0;
    phaseAcc_ = 0.0;

    dcPrevInL_ = 0.0f;
    dcPrevOutL_ = 0.0f;
    dcPrevInR_ = 0.0f;
    dcPrevOutR_ = 0.0f;
}

int DsdDecoder::decodeDsdBytes(const uint8_t* dsdL, const uint8_t* dsdR, int byteCount,
                               float* pcmOutInterleaved, int maxPcmFrames) {
    if (!dsdL || !dsdR || byteCount <= 0 || !pcmOutInterleaved || maxPcmFrames <= 0) {
        return 0;
    }

    int outFrames = 0;

    // Normalization factor: 3dB headroom = 0.7071f
    const float headroomScale = 0.70710678f;

    for (int byteIdx = 0; byteIdx < byteCount; ++byteIdx) {
        const uint8_t bL = dsdL[byteIdx];
        const uint8_t bR = dsdR[byteIdx];

        // Extract 8 bits according to bitOrder
        for (int bit = 0; bit < 8; ++bit) {
            int bitValL = 0;
            int bitValR = 0;

            if (bitOrder_ == DsdBitOrder::LSB_FIRST) {
                // Sony DSF: bit 0 first
                bitValL = (bL >> bit) & 1;
                bitValR = (bR >> bit) & 1;
            } else {
                // Philips DFF: bit 7 first
                bitValL = (bL >> (7 - bit)) & 1;
                bitValR = (bR >> (7 - bit)) & 1;
            }

            // Convert 0/1 to bipolar -1/+1 unsigned delta (mod 2^32)
            const uint32_t xL = bitValL ? 1u : static_cast<uint32_t>(-1);
            const uint32_t xR = bitValR ? 1u : static_cast<uint32_t>(-1);

            // --- STAGE 1: CIC Integrators (order 3, mod 2^32 wrapping) ---
            cicL_.int1 += xL;
            cicL_.int2 += cicL_.int1;
            cicL_.int3 += cicL_.int2;

            cicR_.int1 += xR;
            cicR_.int2 += cicR_.int1;
            cicR_.int3 += cicR_.int2;

            cicCount_++;

            // Decimate 8x in CIC stage
            if (cicCount_ >= 8) {
                cicCount_ = 0;

                // CIC Comb filters (mod 2^32 wrapping)
                uint32_t c1L = cicL_.int3 - cicL_.comb1_d;
                cicL_.comb1_d = cicL_.int3;
                uint32_t c2L = c1L - cicL_.comb2_d;
                cicL_.comb2_d = c1L;
                uint32_t c3L = c2L - cicL_.comb3_d;
                cicL_.comb3_d = c2L;

                uint32_t c1R = cicR_.int3 - cicR_.comb1_d;
                cicR_.comb1_d = cicR_.int3;
                uint32_t c2R = c1R - cicR_.comb2_d;
                cicR_.comb2_d = c1R;
                uint32_t c3R = c2R - cicR_.comb3_d;
                cicR_.comb3_d = c2R;

                // Scale CIC output (cast diff to signed int32_t, 8^3 = 512)
                const int32_t diffL = static_cast<int32_t>(c3L);
                const int32_t diffR = static_cast<int32_t>(c3R);
                const float cicOutL = static_cast<float>(diffL) * (1.0f / 512.0f);
                const float cicOutR = static_cast<float>(diffR) * (1.0f / 512.0f);

                // --- STAGE 2: Anti-Aliasing Decimation Filter ---
                stage2RingL_[stage2WriteIdx_] = cicOutL;
                stage2RingR_[stage2WriteIdx_] = cicOutR;
                stage2WriteIdx_ = (stage2WriteIdx_ + 1) % DECIMATION_TAPS;

                float decimationOutL = 0.0f;
                float decimationOutR = 0.0f;

                for (int tap = 0; tap < DECIMATION_TAPS; ++tap) {
                    int rIdx = (stage2WriteIdx_ - 1 - tap + DECIMATION_TAPS) % DECIMATION_TAPS;
                    decimationOutL += stage2RingL_[rIdx] * decimationCoeffs_[tap];
                    decimationOutR += stage2RingR_[rIdx] * decimationCoeffs_[tap];
                }

                // --- STAGE 3: Fractional Phase Accumulator to target rate ---
                phaseAcc_ += 8.0; // 8 raw DSD bits processed per CIC output
                while (phaseAcc_ >= decimationRatio_ && outFrames < maxPcmFrames) {
                    phaseAcc_ -= decimationRatio_;

                    // --- STAGE 4: 5Hz DC Blocker Highpass Filter ---
                    // y[n] = x[n] - x[n-1] + R * y[n-1]
                    const float sL = decimationOutL * headroomScale;
                    const float sR = decimationOutR * headroomScale;

                    const float dcOutL = sL - dcPrevInL_ + dcPole_ * dcPrevOutL_;
                    const float dcOutR = sR - dcPrevInR_ + dcPole_ * dcPrevOutR_;

                    dcPrevInL_ = sL;
                    dcPrevOutL_ = dcOutL;
                    dcPrevInR_ = sR;
                    dcPrevOutR_ = dcOutR;

                    pcmOutInterleaved[outFrames * 2] = dcOutL;
                    pcmOutInterleaved[outFrames * 2 + 1] = dcOutR;
                    outFrames++;
                }
            }
        }
    }

    return outFrames;
}
