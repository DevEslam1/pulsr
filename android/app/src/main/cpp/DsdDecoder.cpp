// android/app/src/main/cpp/DsdDecoder.cpp
#include "DsdDecoder.h"
#include <cstring>
#include <cmath>

#if defined(__aarch64__) || defined(_M_ARM64)
#include <arm_neon.h>
#define PULSR_HAS_NEON 1
#elif defined(__x86_64__) || defined(_M_X64) || defined(__i386__) || defined(_M_IX86)
#include <emmintrin.h>
#include <xmmintrin.h>
#define PULSR_HAS_SSE 1
#endif

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

DsdDecoder::DsdDecoder() {
    configure(DsdRate::DSD64, 176400, DsdBitOrder::LSB_FIRST);
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

    for (int i = 0; i < DECIMATION_TAPS; ++i) {
        reversedDecimationCoeffs_[i] = decimationCoeffs_[DECIMATION_TAPS - 1 - i];
    }

    // 5Hz DC blocker pole: R = 1 - 2*pi*5 / targetRate
    dcPole_ = static_cast<float>(1.0 - (2.0 * M_PI * 5.0 / targetRate_));
}

void DsdDecoder::configure(DsdRate rate, int targetPcmSampleRate, DsdBitOrder bitOrder) {
    dsdRate_ = rate;
    const double stage1Rate = (44100.0 * static_cast<double>(dsdRate_)) / 8.0;
    const int maxTargetRate = std::min(768000, static_cast<int>(stage1Rate));
    targetRate_ = std::clamp(targetPcmSampleRate, 44100, maxTargetRate);
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

            // Convert 0/1 to bipolar -1/+1 signed int64_t
            const int64_t xL = bitValL ? 1 : -1;
            const int64_t xR = bitValR ? 1 : -1;

            // --- STAGE 1: CIC Integrators (order 3, signed 64-bit) ---
            cicL_.int1 += xL;
            cicL_.int2 += cicL_.int1;
            cicL_.int3 += cicL_.int2;

            cicR_.int1 += xR;
            cicR_.int2 += cicR_.int1;
            cicR_.int3 += cicR_.int2;

            // Slow leak on the integrators to prevent int64 overflow on prolonged pathological DC (> 240 dB down)
            cicL_.int1 -= (cicL_.int1 >> 40);
            cicL_.int2 -= (cicL_.int2 >> 40);
            cicL_.int3 -= (cicL_.int3 >> 40);
            cicR_.int1 -= (cicR_.int1 >> 40);
            cicR_.int2 -= (cicR_.int2 >> 40);
            cicR_.int3 -= (cicR_.int3 >> 40);

            cicCount_++;

            // Decimate 8x in CIC stage
            if (cicCount_ >= 8) {
                cicCount_ = 0;

                // CIC Comb filters (signed 64-bit)
                int64_t c1L = cicL_.int3 - cicL_.comb1_d;
                cicL_.comb1_d = cicL_.int3;
                int64_t c2L = c1L - cicL_.comb2_d;
                cicL_.comb2_d = c1L;
                int64_t c3L = c2L - cicL_.comb3_d;
                cicL_.comb3_d = c2L;

                int64_t c1R = cicR_.int3 - cicR_.comb1_d;
                cicR_.comb1_d = cicR_.int3;
                int64_t c2R = c1R - cicR_.comb2_d;
                cicR_.comb2_d = c1R;
                int64_t c3R = c2R - cicR_.comb3_d;
                cicR_.comb3_d = c2R;

                // Scale CIC output (8^3 = 512 gain) and clamp to [-2.0f, 2.0f] to prevent runaway on corrupted streams
                const float cicOutL = std::clamp(static_cast<float>(c3L) * (1.0f / 512.0f), -2.0f, 2.0f);
                const float cicOutR = std::clamp(static_cast<float>(c3R) * (1.0f / 512.0f), -2.0f, 2.0f);

                // --- STAGE 2: Anti-Aliasing Decimation Filter ---
                stage2RingL_[stage2WriteIdx_] = cicOutL;
                stage2RingL_[stage2WriteIdx_ + DECIMATION_TAPS] = cicOutL;
                stage2RingR_[stage2WriteIdx_] = cicOutR;
                stage2RingR_[stage2WriteIdx_ + DECIMATION_TAPS] = cicOutR;

                const float* bufL = &stage2RingL_[stage2WriteIdx_ + 1];
                const float* bufR = &stage2RingR_[stage2WriteIdx_ + 1];
                stage2WriteIdx_ = (stage2WriteIdx_ + 1) % DECIMATION_TAPS;

                float decimationOutL = 0.0f;
                float decimationOutR = 0.0f;

#if defined(PULSR_HAS_NEON)
                float32x4_t accL0 = vdupq_n_f32(0.0f);
                float32x4_t accL1 = vdupq_n_f32(0.0f);
                float32x4_t accR0 = vdupq_n_f32(0.0f);
                float32x4_t accR1 = vdupq_n_f32(0.0f);
                int tap = 0;
                for (; tap <= DECIMATION_TAPS - 8; tap += 8) {
                    float32x4_t c0 = vld1q_f32(&reversedDecimationCoeffs_[tap]);
                    float32x4_t c1 = vld1q_f32(&reversedDecimationCoeffs_[tap + 4]);
                    float32x4_t l0 = vld1q_f32(&bufL[tap]);
                    float32x4_t l1 = vld1q_f32(&bufL[tap + 4]);
                    float32x4_t r0 = vld1q_f32(&bufR[tap]);
                    float32x4_t r1 = vld1q_f32(&bufR[tap + 4]);
                    accL0 = vfmaq_f32(accL0, l0, c0);
                    accL1 = vfmaq_f32(accL1, l1, c1);
                    accR0 = vfmaq_f32(accR0, r0, c0);
                    accR1 = vfmaq_f32(accR1, r1, c1);
                }
                accL0 = vaddq_f32(accL0, accL1);
                accR0 = vaddq_f32(accR0, accR1);
                for (; tap <= DECIMATION_TAPS - 4; tap += 4) {
                    float32x4_t c = vld1q_f32(&reversedDecimationCoeffs_[tap]);
                    float32x4_t l = vld1q_f32(&bufL[tap]);
                    float32x4_t r = vld1q_f32(&bufR[tap]);
                    accL0 = vfmaq_f32(accL0, l, c);
                    accR0 = vfmaq_f32(accR0, r, c);
                }
                decimationOutL = vaddvq_f32(accL0);
                decimationOutR = vaddvq_f32(accR0);
                for (; tap < DECIMATION_TAPS; ++tap) {
                    decimationOutL += bufL[tap] * reversedDecimationCoeffs_[tap];
                    decimationOutR += bufR[tap] * reversedDecimationCoeffs_[tap];
                }
#elif defined(PULSR_HAS_SSE)
                __m128 accL0 = _mm_setzero_ps();
                __m128 accL1 = _mm_setzero_ps();
                __m128 accR0 = _mm_setzero_ps();
                __m128 accR1 = _mm_setzero_ps();
                int tap = 0;
                for (; tap <= DECIMATION_TAPS - 8; tap += 8) {
                    __m128 c0 = _mm_loadu_ps(&reversedDecimationCoeffs_[tap]);
                    __m128 c1 = _mm_loadu_ps(&reversedDecimationCoeffs_[tap + 4]);
                    __m128 l0 = _mm_loadu_ps(&bufL[tap]);
                    __m128 l1 = _mm_loadu_ps(&bufL[tap + 4]);
                    __m128 r0 = _mm_loadu_ps(&bufR[tap]);
                    __m128 r1 = _mm_loadu_ps(&bufR[tap + 4]);
                    accL0 = _mm_add_ps(accL0, _mm_mul_ps(l0, c0));
                    accL1 = _mm_add_ps(accL1, _mm_mul_ps(l1, c1));
                    accR0 = _mm_add_ps(accR0, _mm_mul_ps(r0, c0));
                    accR1 = _mm_add_ps(accR1, _mm_mul_ps(r1, c1));
                }
                accL0 = _mm_add_ps(accL0, accL1);
                accR0 = _mm_add_ps(accR0, accR1);
                for (; tap <= DECIMATION_TAPS - 4; tap += 4) {
                    __m128 c = _mm_loadu_ps(&reversedDecimationCoeffs_[tap]);
                    __m128 l = _mm_loadu_ps(&bufL[tap]);
                    __m128 r = _mm_loadu_ps(&bufR[tap]);
                    accL0 = _mm_add_ps(accL0, _mm_mul_ps(l, c));
                    accR0 = _mm_add_ps(accR0, _mm_mul_ps(r, c));
                }
                alignas(16) float tmpL[4];
                alignas(16) float tmpR[4];
                _mm_store_ps(tmpL, accL0);
                _mm_store_ps(tmpR, accR0);
                decimationOutL = tmpL[0] + tmpL[1] + tmpL[2] + tmpL[3];
                decimationOutR = tmpR[0] + tmpR[1] + tmpR[2] + tmpR[3];
                for (; tap < DECIMATION_TAPS; ++tap) {
                    decimationOutL += bufL[tap] * reversedDecimationCoeffs_[tap];
                    decimationOutR += bufR[tap] * reversedDecimationCoeffs_[tap];
                }
#else
                for (int tap = 0; tap < DECIMATION_TAPS; ++tap) {
                    decimationOutL += bufL[tap] * reversedDecimationCoeffs_[tap];
                    decimationOutR += bufR[tap] * reversedDecimationCoeffs_[tap];
                }
#endif

                // --- STAGE 3: Fractional Phase Accumulator to target rate ---
                phaseAcc_ += 8.0; // 8 raw DSD bits processed per CIC output
                while (phaseAcc_ >= decimationRatio_ && outFrames < maxPcmFrames) {
                    phaseAcc_ -= decimationRatio_;

                    // --- STAGE 4: 5Hz DC Blocker Highpass Filter ---
                    // y[n] = x[n] - x[n-1] + R * y[n-1]
                    const float sL = decimationOutL * headroomScale;
                    const float sR = decimationOutR * headroomScale;

                    float dcOutL = sL - dcPrevInL_ + dcPole_ * dcPrevOutL_;
                    float dcOutR = sR - dcPrevInR_ + dcPole_ * dcPrevOutR_;
                    if (!std::isfinite(dcOutL)) dcOutL = 0.0f;
                    if (!std::isfinite(dcOutR)) dcOutR = 0.0f;

                    dcPrevInL_ = sL;
                    dcPrevOutL_ = dcOutL;
                    dcPrevInR_ = sR;
                    dcPrevOutR_ = dcOutR;

                    pcmOutInterleaved[outFrames * 2] = std::clamp(dcOutL, -1.0f, 1.0f);
                    pcmOutInterleaved[outFrames * 2 + 1] = std::clamp(dcOutR, -1.0f, 1.0f);
                    outFrames++;
                }
            }
        }
    }

    return outFrames;
}
