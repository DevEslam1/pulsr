// android/app/src/main/cpp/StereoWidth.cpp
#include "StereoWidth.h"
#include <algorithm>
#include <cmath>

#if defined(__ARM_NEON) || defined(__ARM_NEON__)
#include <arm_neon.h>
#define PULSR_HAS_NEON 1
#elif defined(__x86_64__) || defined(_M_X64) || defined(__i386__) || defined(_M_IX86)
#include <emmintrin.h>
#include <xmmintrin.h>
#define PULSR_HAS_SSE 1
#endif

StereoWidth::StereoWidth() {
    setSampleRate(48000.0);
    configure(1.0);
    reset();
}

void StereoWidth::setSampleRate(double sampleRate) {
    if (sampleRate < 8000.0) sampleRate = 8000.0;
    if (sampleRate > 768000.0) sampleRate = 768000.0;
    sampleRate_ = sampleRate;
    updateCrossovers();
}

void StereoWidth::configure(double width) {
    targetWidth_ = std::clamp(width, 0.0, 2.0);
}

void StereoWidth::configureMultiband(bool multiband, double lowWidth, double midWidth, double highWidth,
                                    double lowCrossoverHz, double highCrossoverHz) {
    multiband_ = multiband;
    targetLowWidth_ = std::clamp(lowWidth, 0.0, 2.0);
    targetMidWidth_ = std::clamp(midWidth, 0.0, 2.0);
    targetHighWidth_ = std::clamp(highWidth, 0.0, 2.0);
    lowCrossoverHz_ = std::clamp(lowCrossoverHz, 40.0, 1000.0);
    highCrossoverHz_ = std::clamp(highCrossoverHz, lowCrossoverHz_ + 100.0, sampleRate_ * 0.45);
    updateCrossovers();
}

void StereoWidth::updateCrossovers() {
    crossoverLow_.configure(sampleRate_, lowCrossoverHz_);
    crossoverHigh_.configure(sampleRate_, highCrossoverHz_);
}

void StereoWidth::applyParams(const StereoWidthParamSet& params) {
    enabled_ = params.enabled;
    configure(params.width);
    configureMultiband(params.multiband, params.lowWidth, params.midWidth, params.highWidth,
                       params.lowCrossoverHz, params.highCrossoverHz);
}

void StereoWidth::reset() {
    smoothedWidth_ = targetWidth_;
    smoothedLowWidth_ = targetLowWidth_;
    smoothedMidWidth_ = targetMidWidth_;
    smoothedHighWidth_ = targetHighWidth_;
    crossoverLow_.reset();
    crossoverHigh_.reset();
}

void StereoWidth::process(float* L, float* R, int frames) {
    if (!L || !R || frames <= 0) return;

    constexpr double kTau = 0.015;
    const double smoothFactor = 1.0 - std::exp(-static_cast<double>(frames) / (sampleRate_ * kTau));

    if (!multiband_) {
        // Broadband mode
        const double effTarget = enabled_ ? targetWidth_ : 1.0;
        smoothedWidth_ += smoothFactor * (effTarget - smoothedWidth_);
        if (smoothedWidth_ < 1e-15) smoothedWidth_ = 0.0;
        if (!enabled_ && std::abs(smoothedWidth_ - 1.0) < 1e-4) return;
        if (std::abs(smoothedWidth_ - 1.0) < 1e-5 && std::abs(effTarget - 1.0) < 1e-5) return;

        const float w = static_cast<float>(smoothedWidth_);
        int i = 0;
#if defined(PULSR_HAS_NEON)
        for (; i + 4 <= frames; i += 4) {
            float32x4_t vL = vld1q_f32(&L[i]);
            float32x4_t vR = vld1q_f32(&R[i]);
            float32x4_t vMid = vmulq_n_f32(vaddq_f32(vL, vR), 0.5f);
            float32x4_t vSide = vmulq_n_f32(vsubq_f32(vL, vR), 0.5f);
            float32x4_t vOutL = vfmaq_n_f32(vMid, vSide, w);
            float32x4_t vOutR = vfmsq_n_f32(vMid, vSide, w);
            vst1q_f32(&L[i], vOutL);
            vst1q_f32(&R[i], vOutR);
        }
#elif defined(PULSR_HAS_SSE)
        const __m128 vHalf = _mm_set1_ps(0.5f);
        const __m128 vW = _mm_set1_ps(w);
        for (; i + 4 <= frames; i += 4) {
            __m128 vL = _mm_loadu_ps(&L[i]);
            __m128 vR = _mm_loadu_ps(&R[i]);
            __m128 vMid = _mm_mul_ps(_mm_add_ps(vL, vR), vHalf);
            __m128 vSide = _mm_mul_ps(_mm_sub_ps(vL, vR), vHalf);
            __m128 vOutL = _mm_add_ps(vMid, _mm_mul_ps(vW, vSide));
            __m128 vOutR = _mm_sub_ps(vMid, _mm_mul_ps(vW, vSide));
            _mm_storeu_ps(&L[i], vOutL);
            _mm_storeu_ps(&R[i], vOutR);
        }
#endif
        for (; i < frames; ++i) {
            const float l = L[i];
            const float r = R[i];
            const float mid = 0.5f * (l + r);
            const float side = 0.5f * (l - r);
            L[i] = mid + w * side;
            R[i] = mid - w * side;
        }
        return;
    }

    // 3-Band Multiband Stereo Imager with Bass Mono
    const double effLow = enabled_ ? targetLowWidth_ : 1.0;
    const double effMid = enabled_ ? targetMidWidth_ : 1.0;
    const double effHigh = enabled_ ? targetHighWidth_ : 1.0;
    smoothedLowWidth_ += smoothFactor * (effLow - smoothedLowWidth_);
    smoothedMidWidth_ += smoothFactor * (effMid - smoothedMidWidth_);
    smoothedHighWidth_ += smoothFactor * (effHigh - smoothedHighWidth_);

    if (!enabled_ && std::abs(smoothedLowWidth_ - 1.0) < 1e-4 &&
        std::abs(smoothedMidWidth_ - 1.0) < 1e-4 && std::abs(smoothedHighWidth_ - 1.0) < 1e-4) {
        return;
    }

    const float wLow = static_cast<float>(smoothedLowWidth_);
    const float wMid = static_cast<float>(smoothedMidWidth_);
    const float wHigh = static_cast<float>(smoothedHighWidth_);

    for (int i = 0; i < frames; ++i) {
        const double inL = L[i];
        const double inR = R[i];

        // 1. Split low vs (mid+high)
        double lowL, lowR, midHighL, midHighR;
        crossoverLow_.process(inL, inR, lowL, lowR, midHighL, midHighR);

        // 2. Split mid vs high
        double midL, midR, highL, highR;
        crossoverHigh_.process(midHighL, midHighR, midL, midR, highL, highR);

        // 3. Process each band with its dedicated stereo width
        // Low band (defaults to mono when wLow == 0.0)
        const double mLow = 0.5 * (lowL + lowR);
        const double sLow = 0.5 * (lowL - lowR);
        const double outLowL = mLow + wLow * sLow;
        const double outLowR = mLow - wLow * sLow;

        // Mid band
        const double mMid = 0.5 * (midL + midR);
        const double sMid = 0.5 * (midL - midR);
        const double outMidL = mMid + wMid * sMid;
        const double outMidR = mMid - wMid * sMid;

        // High band
        const double mHigh = 0.5 * (highL + highR);
        const double sHigh = 0.5 * (highL - highR);
        const double outHighL = mHigh + wHigh * sHigh;
        const double outHighR = mHigh - wHigh * sHigh;

        // 4. Sum bands back together
        L[i] = static_cast<float>(outLowL + outMidL + outHighL);
        R[i] = static_cast<float>(outLowR + outMidR + outHighR);
    }
}

void StereoWidth::processInterleaved(float* buffer, int frames, int channels) {
    if (!buffer || frames <= 0 || channels < 2) return;

    constexpr double kTau = 0.015;
    const double smoothFactor = 1.0 - std::exp(-static_cast<double>(frames) / (sampleRate_ * kTau));

    if (!multiband_) {
        // Broadband mode
        const double effTarget = enabled_ ? targetWidth_ : 1.0;
        smoothedWidth_ += smoothFactor * (effTarget - smoothedWidth_);
        if (smoothedWidth_ < 1e-15) smoothedWidth_ = 0.0;
        if (!enabled_ && std::abs(smoothedWidth_ - 1.0) < 1e-4) return;
        if (std::abs(smoothedWidth_ - 1.0) < 1e-5 && std::abs(effTarget - 1.0) < 1e-5) return;

        const float w = static_cast<float>(smoothedWidth_);
        if (channels == 2) {
            int i = 0;
#if defined(PULSR_HAS_NEON)
            for (; i + 4 <= frames; i += 4) {
                float32x4x2_t vIn = vld2q_f32(buffer + i * 2);
                float32x4_t vMid = vmulq_n_f32(vaddq_f32(vIn.val[0], vIn.val[1]), 0.5f);
                float32x4_t vSide = vmulq_n_f32(vsubq_f32(vIn.val[0], vIn.val[1]), 0.5f);
                float32x4x2_t vOut;
                vOut.val[0] = vfmaq_n_f32(vMid, vSide, w);
                vOut.val[1] = vfmsq_n_f32(vMid, vSide, w);
                vst2q_f32(buffer + i * 2, vOut);
            }
#elif defined(PULSR_HAS_SSE)
            const __m128 vHalf = _mm_set1_ps(0.5f);
            const __m128 vW = _mm_set1_ps(w);
            for (; i + 4 <= frames; i += 4) {
                __m128 v0 = _mm_loadu_ps(buffer + i * 2);     // [L0, R0, L1, R1]
                __m128 v1 = _mm_loadu_ps(buffer + i * 2 + 4); // [L2, R2, L3, R3]
                __m128 vL = _mm_shuffle_ps(v0, v1, _MM_SHUFFLE(2, 0, 2, 0)); // [L0, L1, L2, L3]
                __m128 vR = _mm_shuffle_ps(v0, v1, _MM_SHUFFLE(3, 1, 3, 1)); // [R0, R1, R2, R3]
                __m128 vMid = _mm_mul_ps(_mm_add_ps(vL, vR), vHalf);
                __m128 vSide = _mm_mul_ps(_mm_sub_ps(vL, vR), vHalf);
                __m128 vOutL = _mm_add_ps(vMid, _mm_mul_ps(vW, vSide));
                __m128 vOutR = _mm_sub_ps(vMid, _mm_mul_ps(vW, vSide));
                __m128 out0 = _mm_unpacklo_ps(vOutL, vOutR); // [L0, R0, L1, R1]
                __m128 out1 = _mm_unpackhi_ps(vOutL, vOutR); // [L2, R2, L3, R3]
                _mm_storeu_ps(buffer + i * 2, out0);
                _mm_storeu_ps(buffer + i * 2 + 4, out1);
            }
#endif
            for (; i < frames; ++i) {
                const float l = buffer[i * 2];
                const float r = buffer[i * 2 + 1];
                const float mid = 0.5f * (l + r);
                const float side = 0.5f * (l - r);
                buffer[i * 2] = mid + w * side;
                buffer[i * 2 + 1] = mid - w * side;
            }
        } else {
            for (int i = 0; i < frames; ++i) {
                for (int ch = 0; ch + 1 < channels; ch += 2) {
                    const float l = buffer[i * channels + ch];
                    const float r = buffer[i * channels + ch + 1];
                    const float mid = 0.5f * (l + r);
                    const float side = 0.5f * (l - r);
                    buffer[i * channels + ch] = mid + w * side;
                    buffer[i * channels + ch + 1] = mid - w * side;
                }
            }
        }
        return;
    }

    // 3-Band Multiband Stereo Imager with Bass Mono
    const double effLow = enabled_ ? targetLowWidth_ : 1.0;
    const double effMid = enabled_ ? targetMidWidth_ : 1.0;
    const double effHigh = enabled_ ? targetHighWidth_ : 1.0;
    smoothedLowWidth_ += smoothFactor * (effLow - smoothedLowWidth_);
    smoothedMidWidth_ += smoothFactor * (effMid - smoothedMidWidth_);
    smoothedHighWidth_ += smoothFactor * (effHigh - smoothedHighWidth_);

    if (!enabled_ && std::abs(smoothedLowWidth_ - 1.0) < 1e-4 &&
        std::abs(smoothedMidWidth_ - 1.0) < 1e-4 && std::abs(smoothedHighWidth_ - 1.0) < 1e-4) {
        return;
    }

    const float wLow = static_cast<float>(smoothedLowWidth_);
    const float wMid = static_cast<float>(smoothedMidWidth_);
    const float wHigh = static_cast<float>(smoothedHighWidth_);

    for (int i = 0; i < frames; ++i) {
        for (int ch = 0; ch + 1 < channels; ch += 2) {
            const double inL = buffer[i * channels + ch];
            const double inR = buffer[i * channels + ch + 1];

            double lowL, lowR, midHighL, midHighR;
            crossoverLow_.process(inL, inR, lowL, lowR, midHighL, midHighR);

            double midL, midR, highL, highR;
            crossoverHigh_.process(midHighL, midHighR, midL, midR, highL, highR);

            const double mLow = 0.5 * (lowL + lowR);
            const double sLow = 0.5 * (lowL - lowR);
            const double outLowL = mLow + wLow * sLow;
            const double outLowR = mLow - wLow * sLow;

            const double mMid = 0.5 * (midL + midR);
            const double sMid = 0.5 * (midL - midR);
            const double outMidL = mMid + wMid * sMid;
            const double outMidR = mMid - wMid * sMid;

            const double mHigh = 0.5 * (highL + highR);
            const double sHigh = 0.5 * (highL - highR);
            const double outHighL = mHigh + wHigh * sHigh;
            const double outHighR = mHigh - wHigh * sHigh;

            buffer[i * channels + ch] = static_cast<float>(outLowL + outMidL + outHighL);
            buffer[i * channels + ch + 1] = static_cast<float>(outLowR + outMidR + outHighR);
        }
    }
}
