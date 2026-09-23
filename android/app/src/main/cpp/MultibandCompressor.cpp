// android/app/src/main/cpp/MultibandCompressor.cpp
#include "MultibandCompressor.h"

#if defined(__ARM_NEON) || defined(__ARM_NEON__)
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

MultibandCompressor::MultibandCompressor() {
    setSampleRate(48000.0);
    reset();
}

void MultibandCompressor::setSampleRate(double sampleRate) {
    if (sampleRate < 8000.0) sampleRate = 8000.0;
    if (sampleRate > 768000.0) sampleRate = 768000.0;
    sampleRate_ = sampleRate;
    updateCoefficients();
}

void MultibandCompressor::applyParams(const MultibandCompressorParamSet& params) {
    pendingParams_ = params;
    paramsChanged_.store(true, std::memory_order_release);
}

void MultibandCompressor::updateCoefficients() {
    // Validate and sort crossover frequencies. Guard std::clamp's lo <= hi
    // precondition: f2's upper bound is never allowed below its lower bound.
    double f0 = std::clamp(params_.crossoverFreqs[0], 20.0, std::min(1000.0, sampleRate_ * 0.40));
    double f1 = std::clamp(params_.crossoverFreqs[1], f0 + 50.0,
                           std::max(f0 + 50.0, std::min(8000.0, sampleRate_ * 0.44)));
    double f2lo = f1 + 100.0;
    double f2hi = std::max(f2lo, sampleRate_ * 0.45);
    double f2 = std::clamp(params_.crossoverFreqs[2], f2lo, f2hi);

    crossoverMid_.configure(sampleRate_, f1);
    crossoverLow_.configure(sampleRate_, f0);
    crossoverHigh_.configure(sampleRate_, f2);

    for (int b = 0; b < NUM_BANDS; ++b) {
        const double attSec = std::clamp(params_.bands[b].attackMs, 0.1, 500.0) * 0.001;
        const double relSec = std::clamp(params_.bands[b].releaseMs, 5.0, 2000.0) * 0.001;
        attackCoeff_[b] = std::exp(-1.0 / (attSec * sampleRate_));
        releaseCoeff_[b] = std::exp(-1.0 / (relSec * sampleRate_));
    }
}

void MultibandCompressor::reset() {
    crossoverMid_.reset();
    crossoverLow_.reset();
    crossoverHigh_.reset();
    for (int b = 0; b < NUM_BANDS; ++b) {
        envelopeDb_[b] = 0.0;        // linear amplitude envelope, starts at silence
        smoothedGainDb_[b] = 0.0;
        currentGainReductionDb_[b] = 0.0;
    }
}

double MultibandCompressor::computeBandGain(int band, double envDb) {
    const auto& bp = params_.bands[band];
    if (!enabled_ || !bp.enabled || bp.ratio <= 1.001) {
        // Release the applied gain to unity instead of snapping to 0 dB, so
        // toggling a band off (or its ratio to 1, or disabling the whole stage)
        // ramps out rather than clicks.
        smoothedGainDb_[band] += (1.0 - releaseCoeff_[band]) * (0.0 - smoothedGainDb_[band]);
        if (std::abs(smoothedGainDb_[band]) < 0.01) smoothedGainDb_[band] = 0.0;
        currentGainReductionDb_[band] = smoothedGainDb_[band];
        return smoothedGainDb_[band];
    }

    const double T = bp.thresholdDb;
    const double R = bp.ratio;
    const double W = std::max(bp.kneeDb, 0.0);

    double targetGainDb = 0.0;
    if (W > 0.001 && envDb > (T - W * 0.5) && envDb < (T + W * 0.5)) {
        // Soft knee region
        const double delta = envDb - T + W * 0.5;
        targetGainDb = (1.0 / R - 1.0) * (delta * delta) / (2.0 * W);
    } else if (envDb >= (T + W * 0.5)) {
        // Fully above threshold
        targetGainDb = (T + (envDb - T) / R) - envDb;
    } else {
        targetGainDb = 0.0;
    }

    if (targetGainDb > 0.0) targetGainDb = 0.0; // compressor only cuts

    // Ballistics: faster coefficient when entering compression (target < smoothed)
    const double coeff = (targetGainDb < smoothedGainDb_[band]) ? attackCoeff_[band] : releaseCoeff_[band];
    smoothedGainDb_[band] = coeff * smoothedGainDb_[band] + (1.0 - coeff) * targetGainDb;
    currentGainReductionDb_[band] = smoothedGainDb_[band];

    return smoothedGainDb_[band] + bp.makeupGainDb;
}

void MultibandCompressor::processInterleaved(float* buffer, int frames, int channels) {
    if (paramsChanged_.load(std::memory_order_acquire)) {
        params_ = pendingParams_;
        enabled_ = params_.enabled;
        updateCoefficients();
        paramsChanged_.store(false, std::memory_order_release);
    }

    bool allBandsZero = true;
    for (int b = 0; b < NUM_BANDS; ++b) {
        if (std::abs(smoothedGainDb_[b]) > 0.01) {
            allBandsZero = false;
            break;
        }
    }
    if (!enabled_ && allBandsZero) return;
    if (!buffer || frames <= 0 || channels < 2) return;

    int framesRemaining = frames;
    int offset = 0;

    while (framesRemaining > 0) {
        const int chunkFrames = std::min(framesRemaining, MAX_CHUNK_FRAMES);

        // 1. Split chunk into 4 frequency bands via Linkwitz-Riley 4th order crossovers
        for (int i = 0; i < chunkFrames; ++i) {
            const int inIdx = (offset + i) * channels;
            const double inL = buffer[inIdx];
            const double inR = buffer[inIdx + 1];

            double lowHalfL, lowHalfR, highHalfL, highHalfR;
            crossoverMid_.process(inL, inR, lowHalfL, lowHalfR, highHalfL, highHalfR);

            double b0L, b0R, b1L, b1R;
            crossoverLow_.process(lowHalfL, lowHalfR, b0L, b0R, b1L, b1R);

            double b2L, b2R, b3L, b3R;
            crossoverHigh_.process(highHalfL, highHalfR, b2L, b2R, b3L, b3R);

            bandBufferL_[0][i] = static_cast<float>(b0L);
            bandBufferR_[0][i] = static_cast<float>(b0R);
            bandBufferL_[1][i] = static_cast<float>(b1L);
            bandBufferR_[1][i] = static_cast<float>(b1R);
            bandBufferL_[2][i] = static_cast<float>(b2L);
            bandBufferR_[2][i] = static_cast<float>(b2R);
            bandBufferL_[3][i] = static_cast<float>(b3L);
            bandBufferR_[3][i] = static_cast<float>(b3R);
        }

        // 2. Process dynamic compression per band and sum back
        for (int b = 0; b < NUM_BANDS; ++b) {
            for (int i = 0; i < chunkFrames; ++i) {
                const float sL = bandBufferL_[b][i];
                const float sR = bandBufferR_[b][i];

                // Level detector: instantaneous peak. Ballistics (attack/release)
                // are applied once, to the gain in computeBandGain().
                const double peak = std::max(std::abs(sL), std::abs(sR));
                envelopeDb_[b] = peak;

                // Convert linear envelope to dB once per sample
                const double envDb = (envelopeDb_[b] > 1e-6) ? (20.0 * std::log10(envelopeDb_[b])) : -120.0;
                const double gainDb = computeBandGain(b, envDb);
                const float linearGain = static_cast<float>(std::pow(10.0, gainDb / 20.0));

                bandBufferL_[b][i] *= linearGain;
                bandBufferR_[b][i] *= linearGain;
            }
        }

        // 3. Recombine all 4 bands into output buffer
        int i = 0;
        if (channels == 2) {
#if defined(PULSR_HAS_NEON)
            for (; i + 4 <= chunkFrames; i += 4) {
                float32x4_t v0L = vld1q_f32(&bandBufferL_[0][i]);
                float32x4_t v1L = vld1q_f32(&bandBufferL_[1][i]);
                float32x4_t v2L = vld1q_f32(&bandBufferL_[2][i]);
                float32x4_t v3L = vld1q_f32(&bandBufferL_[3][i]);
                float32x4_t sumL = vaddq_f32(vaddq_f32(v0L, v1L), vaddq_f32(v2L, v3L));

                float32x4_t v0R = vld1q_f32(&bandBufferR_[0][i]);
                float32x4_t v1R = vld1q_f32(&bandBufferR_[1][i]);
                float32x4_t v2R = vld1q_f32(&bandBufferR_[2][i]);
                float32x4_t v3R = vld1q_f32(&bandBufferR_[3][i]);
                float32x4_t sumR = vaddq_f32(vaddq_f32(v0R, v1R), vaddq_f32(v2R, v3R));

                float32x4x2_t vOut = { sumL, sumR };
                vst2q_f32(buffer + (offset + i) * 2, vOut);
            }
#elif defined(PULSR_HAS_SSE)
            for (; i + 4 <= chunkFrames; i += 4) {
                __m128 v0L = _mm_loadu_ps(&bandBufferL_[0][i]);
                __m128 v1L = _mm_loadu_ps(&bandBufferL_[1][i]);
                __m128 v2L = _mm_loadu_ps(&bandBufferL_[2][i]);
                __m128 v3L = _mm_loadu_ps(&bandBufferL_[3][i]);
                __m128 sumL = _mm_add_ps(_mm_add_ps(v0L, v1L), _mm_add_ps(v2L, v3L));

                __m128 v0R = _mm_loadu_ps(&bandBufferR_[0][i]);
                __m128 v1R = _mm_loadu_ps(&bandBufferR_[1][i]);
                __m128 v2R = _mm_loadu_ps(&bandBufferR_[2][i]);
                __m128 v3R = _mm_loadu_ps(&bandBufferR_[3][i]);
                __m128 sumR = _mm_add_ps(_mm_add_ps(v0R, v1R), _mm_add_ps(v2R, v3R));

                __m128 lo = _mm_unpacklo_ps(sumL, sumR);
                __m128 hi = _mm_unpackhi_ps(sumL, sumR);
                _mm_storeu_ps(buffer + (offset + i) * 2, lo);
                _mm_storeu_ps(buffer + (offset + i) * 2 + 4, hi);
            }
#endif
        }
        for (; i < chunkFrames; ++i) {
            const int outIdx = (offset + i) * channels;
            buffer[outIdx] = bandBufferL_[0][i] + bandBufferL_[1][i] + bandBufferL_[2][i] + bandBufferL_[3][i];
            buffer[outIdx + 1] = bandBufferR_[0][i] + bandBufferR_[1][i] + bandBufferR_[2][i] + bandBufferR_[3][i];
        }

        offset += chunkFrames;
        framesRemaining -= chunkFrames;
    }
}
