// android/app/src/main/cpp/MultibandCompressor.cpp
#include "MultibandCompressor.h"

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
    if (!bp.enabled || bp.ratio <= 1.001) {
        // Release the applied gain to unity instead of snapping to 0 dB, so
        // toggling a band off (or its ratio to 1) ramps out rather than clicks.
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

    if (!enabled_ || !buffer || frames <= 0 || channels != 2) return;

    int framesRemaining = frames;
    int offset = 0;

    while (framesRemaining > 0) {
        const int chunkFrames = std::min(framesRemaining, MAX_CHUNK_FRAMES);

        // 1. Split chunk into 4 frequency bands via Linkwitz-Riley 4th order crossovers
        for (int i = 0; i < chunkFrames; ++i) {
            const int inIdx = (offset + i) * 2;
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
                // are applied once, to the gain in computeBandGain(). Previously
                // the envelope follower AND the gain smoother each applied the
                // same time constants, roughly doubling the effective times.
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
        for (int i = 0; i < chunkFrames; ++i) {
            const int outIdx = (offset + i) * 2;
            buffer[outIdx] = bandBufferL_[0][i] + bandBufferL_[1][i] + bandBufferL_[2][i] + bandBufferL_[3][i];
            buffer[outIdx + 1] = bandBufferR_[0][i] + bandBufferR_[1][i] + bandBufferR_[2][i] + bandBufferR_[3][i];
        }

        offset += chunkFrames;
        framesRemaining -= chunkFrames;
    }
}
