// android/app/src/main/cpp/MultibandCompressor.cpp
#include "MultibandCompressor.h"

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

MultibandCompressor::MultibandCompressor() {
    setSampleRate(48000.0);
    reset();
}

void MultibandCompressor::setSampleRate(double sampleRate) {
    if (sampleRate < 8000.0) sampleRate = 8000.0;
    if (sampleRate > 768000.0) sampleRate = 768000.0;
    sampleRate_ = sampleRate;
    updateCoefficients();
    // FIX M-7: the crossovers were just reconfigured for the new rate; their
    // retained LR4 filter registers belong to the old coefficients and would
    // thump on the first block. LinkwitzRiley4::configure() already resets on a
    // rate change, but flush explicitly here so a stale register set can never
    // survive a rate swap (mirrors SubCrossover/LookaheadLimiter).
    crossoverMid_.reset();
    crossoverLow_.reset();
    crossoverHigh_.reset();
    // FIX M-11: the phase-compensation allpasses hold recursive state too; flush
    // them on a rate swap alongside the crossovers so no stale register survives.
    allpassLowPath_.reset();
    allpassHighPath_.reset();
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
    // FIX M-11: phase-compensation allpasses mirror the sibling sub-crossover
    // cutoffs (and Butterworth Q) so their allpass phase matches exactly: the low
    // half is given crossoverHigh_'s allpass (f2), the high half crossoverLow_'s
    // allpass (f0). configure() resets the LR4 state when the cutoff/rate moves.
    allpassLowPath_.configure(sampleRate_, f2);
    allpassHighPath_.configure(sampleRate_, f0);

    for (int b = 0; b < NUM_BANDS; ++b) {
        const double attSec = std::clamp(params_.bands[b].attackMs, 0.1, 500.0) * 0.001;
        const double relSec = std::clamp(params_.bands[b].releaseMs, 5.0, 2000.0) * 0.001;
        attackCoeff_[b] = std::exp(-1.0 / (attSec * sampleRate_));
        releaseCoeff_[b] = std::exp(-1.0 / (relSec * sampleRate_));
    }
    // Makeup gain follows user changes and fades out when a band/stage is
    // disabled; a fixed 20 ms ramp avoids both parameter zipper noise and the
    // level jump caused by dropping makeup instantly on bypass.
    makeupSmoothCoeff_ = std::exp(-1.0 / (0.020 * sampleRate_));
}

void MultibandCompressor::reset() {
    crossoverMid_.reset();
    crossoverLow_.reset();
    crossoverHigh_.reset();
    allpassLowPath_.reset();
    allpassHighPath_.reset();
    smoothedEnabledMix_ = enabled_ ? 1.0f : 0.0f;
    for (int b = 0; b < NUM_BANDS; ++b) {
        envelope_[b] = 0.0;          // linear amplitude envelope, starts at silence
        smoothedGainDb_[b] = 0.0;
        smoothedMakeupDb_[b] = 0.0;
        currentGainReductionDb_[b] = 0.0;
    }
}

double MultibandCompressor::computeBandGain(int band, double envDb) {
    const auto& bp = params_.bands[band];
    const bool active = enabled_ && bp.enabled && bp.ratio > 1.001;

    const double makeupTarget = active ? bp.makeupGainDb : 0.0;
    smoothedMakeupDb_[band] = makeupSmoothCoeff_ * smoothedMakeupDb_[band] +
                              (1.0 - makeupSmoothCoeff_) * makeupTarget;
    if (std::abs(smoothedMakeupDb_[band] - makeupTarget) < 0.001) {
        smoothedMakeupDb_[band] = makeupTarget;
    }

    if (!active) {
        // Release the applied gain to unity instead of snapping to 0 dB, so
        // toggling a band off (or its ratio to 1, or disabling the whole stage)
        // ramps out rather than clicks.
        smoothedGainDb_[band] += (1.0 - releaseCoeff_[band]) * (0.0 - smoothedGainDb_[band]);
        if (std::abs(smoothedGainDb_[band]) < 0.01) smoothedGainDb_[band] = 0.0;
        currentGainReductionDb_[band] = smoothedGainDb_[band];
        return smoothedGainDb_[band] + smoothedMakeupDb_[band];
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
    return targetGainDb;
}

void MultibandCompressor::processInterleaved(float* buffer, int frames, int channels) {
    if (paramsChanged_.load(std::memory_order_acquire)) {
        params_ = pendingParams_;
        enabled_ = params_.enabled;
        updateCoefficients();
        paramsChanged_.store(false, std::memory_order_release);
    }

    const float targetEnabledMix = enabled_ ? 1.0f : 0.0f;
    if (!enabled_ && smoothedEnabledMix_ < 1e-4f) return;
    if (!buffer || frames <= 0 || channels < 2) return;

    // Smooth stage bypass/enable over 20 ms to prevent clicks and phase jumps against dry signal
    constexpr double kTau = 0.020;
    const double smoothFactor = 1.0 - std::exp(-static_cast<double>(frames) / (sampleRate_ * kTau));
    const float startEnabledMix = smoothedEnabledMix_;
    smoothedEnabledMix_ += static_cast<float>(smoothFactor) * (targetEnabledMix - smoothedEnabledMix_);
    if (std::abs(smoothedEnabledMix_ - targetEnabledMix) < 1e-4f) {
        smoothedEnabledMix_ = targetEnabledMix;
    }
    const float mixStep = (smoothedEnabledMix_ - startEnabledMix) / static_cast<float>(frames);
    float currentEnabledMix = startEnabledMix;

    int framesRemaining = frames;
    int offset = 0;

    while (framesRemaining > 0) {
        const int chunkFrames = std::min(framesRemaining, MAX_CHUNK_FRAMES);

        // 1. Split chunk into 4 frequency bands via Linkwitz-Riley 4th order
        //    crossovers, with allpass phase compensation for flat reconstruction.
        for (int i = 0; i < chunkFrames; ++i) {
            const int inIdx = (offset + i) * channels;
            const double inL = buffer[inIdx];
            const double inR = buffer[inIdx + 1];

            double lowHalfL, lowHalfR, highHalfL, highHalfR;
            crossoverMid_.process(inL, inR, lowHalfL, lowHalfR, highHalfL, highHalfR);

            // Allpass-compensate each half (LR4 allpass = LP + HP).
            double apLpL, apLpR, apHpL, apHpR;
            allpassLowPath_.process(lowHalfL, lowHalfR, apLpL, apLpR, apHpL, apHpR);
            const double lowCompL = apLpL + apHpL;  // AP_f2(lowHalf)
            const double lowCompR = apLpR + apHpR;

            allpassHighPath_.process(highHalfL, highHalfR, apLpL, apLpR, apHpL, apHpR);
            const double highCompL = apLpL + apHpL; // AP_f0(highHalf)
            const double highCompR = apLpR + apHpR;

            double b0L, b0R, b1L, b1R;
            crossoverLow_.process(lowCompL, lowCompR, b0L, b0R, b1L, b1R);

            double b2L, b2R, b3L, b3R;
            crossoverHigh_.process(highCompL, highCompR, b2L, b2R, b3L, b3R);

            bandBufferL_[0][i] = static_cast<float>(b0L);
            bandBufferR_[0][i] = static_cast<float>(b0R);
            bandBufferL_[1][i] = static_cast<float>(b1L);
            bandBufferR_[1][i] = static_cast<float>(b1R);
            bandBufferL_[2][i] = static_cast<float>(b2L);
            bandBufferR_[2][i] = static_cast<float>(b2R);
            bandBufferL_[3][i] = static_cast<float>(b3L);
            bandBufferR_[3][i] = static_cast<float>(b3R);
        }

        // 2. Process dynamic compression per band and sum back with dB-domain ballistics
        for (int b = 0; b < NUM_BANDS; ++b) {
            for (int i = 0; i < chunkFrames; ++i) {
                const float sL = bandBufferL_[b][i];
                const float sR = bandBufferR_[b][i];

                const double peak = std::max(std::abs(static_cast<double>(sL)), std::abs(static_cast<double>(sR)));
                const double envDb = (peak > 1e-6) ? (20.0 * std::log10(peak)) : -120.0;
                const double targetGainDb = computeBandGain(b, envDb);

                // Smooth gain reduction with attack/release ballistics in dB domain
                const double coeff = (targetGainDb < smoothedGainDb_[b]) ? attackCoeff_[b] : releaseCoeff_[b];
                smoothedGainDb_[b] = coeff * smoothedGainDb_[b] + (1.0 - coeff) * targetGainDb;
                currentGainReductionDb_[b] = smoothedGainDb_[b];

                const double totalGainDb = smoothedGainDb_[b] + smoothedMakeupDb_[b];
                const float linearGain = static_cast<float>(std::pow(10.0, totalGainDb / 20.0));

                bandBufferL_[b][i] *= linearGain;
                bandBufferR_[b][i] *= linearGain;
            }
        }

        // 3. Recombine all 4 bands into output buffer with equal-power wet/dry crossfade
        for (int i = 0; i < chunkFrames; ++i) {
            const int outIdx = (offset + i) * channels;
            const float inL = buffer[outIdx];
            const float inR = buffer[outIdx + 1];

            const float wetL = bandBufferL_[0][i] + bandBufferL_[1][i] + bandBufferL_[2][i] + bandBufferL_[3][i];
            const float wetR = bandBufferR_[0][i] + bandBufferR_[1][i] + bandBufferR_[2][i] + bandBufferR_[3][i];

            float dryW, wetW;
            if (currentEnabledMix >= 0.9999f) {
                dryW = 0.0f;
                wetW = 1.0f;
            } else if (currentEnabledMix <= 0.0001f) {
                dryW = 1.0f;
                wetW = 0.0f;
            } else {
                const float angle = currentEnabledMix * (static_cast<float>(M_PI) * 0.5f);
                dryW = std::cos(angle);
                wetW = std::sin(angle);
            }

            buffer[outIdx] = dryW * inL + wetW * wetL;
            buffer[outIdx + 1] = dryW * inR + wetW * wetR;
            currentEnabledMix += mixStep;
        }

        offset += chunkFrames;
        framesRemaining -= chunkFrames;
    }
}
