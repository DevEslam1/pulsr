#include "LookaheadLimiter.h"
#include <cstring>

LookaheadLimiter::LookaheadLimiter() {
    setSampleRate(48000.0);
    configure(3.0, -0.2, 50.0);
    reset();
}

void LookaheadLimiter::setSampleRate(double sampleRate) {
    if (sampleRate < 8000.0) sampleRate = 8000.0;
    if (sampleRate > 768000.0) sampleRate = 768000.0;
    sampleRate_ = sampleRate;
    configure(lookaheadMs_, thresholdDb_, releaseMs_);
}

void LookaheadLimiter::configure(double lookaheadMs, double thresholdDb, double releaseMs) {
    lookaheadMs_ = std::max(0.1, std::min(lookaheadMs, 25.0));
    thresholdDb_ = std::max(-24.0, std::min(thresholdDb, 0.0));
    releaseMs_ = std::max(5.0, std::min(releaseMs, 1000.0));

    lookaheadSamples_ = std::clamp(static_cast<int>(sampleRate_ * lookaheadMs_ / 1000.0), 1, MAX_LOOKAHEAD_SAMPLES - 1);
    threshold_ = static_cast<float>(std::pow(10.0, thresholdDb_ / 20.0));

    // Exponential release factor: env -> 1.0
    double releaseSec = releaseMs_ / 1000.0;
    releaseCoeff_ = static_cast<float>(std::exp(-1.0 / (sampleRate_ * releaseSec)));
}

void LookaheadLimiter::setEnabled(bool enabled) {
    enabled_ = enabled;
}

void LookaheadLimiter::reset() {
    std::memset(delayBuf_, 0, sizeof(delayBuf_));
    writeIdx_ = 0;
    envelope_ = 1.0f;
}

void LookaheadLimiter::process(float* L, float* R, int frames) {
    if (!enabled_ || !L || !R || frames <= 0) return;

    for (int i = 0; i < frames; ++i) {
        float inL = L[i];
        float inR = R[i];

        // Instant peak detection on incoming transient
        float peak = std::max(std::abs(inL), std::abs(inR));
        float targetGain = (peak > threshold_) ? (threshold_ / peak) : 1.0f;

        // Instant attack, smooth exponential release
        if (targetGain < envelope_) {
            envelope_ = targetGain;
        } else {
            envelope_ = releaseCoeff_ * envelope_ + (1.0f - releaseCoeff_) * targetGain;
        }

        // Apply calculated gain to the delayed lookahead signal
        int rdIdx = (writeIdx_ - lookaheadSamples_ + MAX_LOOKAHEAD_SAMPLES) % MAX_LOOKAHEAD_SAMPLES;
        float outL = delayBuf_[0][rdIdx] * envelope_;
        float outR = delayBuf_[1][rdIdx] * envelope_;

        // Write current input into circular delay buffer
        delayBuf_[0][writeIdx_] = inL;
        delayBuf_[1][writeIdx_] = inR;
        writeIdx_ = (writeIdx_ + 1) % MAX_LOOKAHEAD_SAMPLES;

        L[i] = std::max(-1.0f, std::min(outL, 1.0f));
        R[i] = std::max(-1.0f, std::min(outR, 1.0f));
    }
}

void LookaheadLimiter::processMono(float* inOut, int frames) {
    if (!enabled_ || !inOut || frames <= 0) return;

    for (int i = 0; i < frames; ++i) {
        float in = inOut[i];
        float peak = std::abs(in);
        float targetGain = (peak > threshold_) ? (threshold_ / peak) : 1.0f;

        if (targetGain < envelope_) {
            envelope_ = targetGain;
        } else {
            envelope_ = releaseCoeff_ * envelope_ + (1.0f - releaseCoeff_) * targetGain;
        }

        int rdIdx = (writeIdx_ - lookaheadSamples_ + MAX_LOOKAHEAD_SAMPLES) % MAX_LOOKAHEAD_SAMPLES;
        float out = delayBuf_[0][rdIdx] * envelope_;

        delayBuf_[0][writeIdx_] = in;
        writeIdx_ = (writeIdx_ + 1) % MAX_LOOKAHEAD_SAMPLES;

        inOut[i] = std::max(-1.0f, std::min(out, 1.0f));
    }
}

void LookaheadLimiter::processInterleaved(float* buffer, int frames) {
    if (!enabled_ || !buffer || frames <= 0) return;

    for (int i = 0; i < frames; ++i) {
        float inL = buffer[i * 2];
        float inR = buffer[i * 2 + 1];

        float peak = std::max(std::abs(inL), std::abs(inR));
        float targetGain = (peak > threshold_) ? (threshold_ / peak) : 1.0f;

        if (targetGain < envelope_) {
            envelope_ = targetGain;
        } else {
            envelope_ = releaseCoeff_ * envelope_ + (1.0f - releaseCoeff_) * targetGain;
        }

        int rdIdx = (writeIdx_ - lookaheadSamples_ + MAX_LOOKAHEAD_SAMPLES) % MAX_LOOKAHEAD_SAMPLES;
        float outL = delayBuf_[0][rdIdx] * envelope_;
        float outR = delayBuf_[1][rdIdx] * envelope_;

        delayBuf_[0][writeIdx_] = inL;
        delayBuf_[1][writeIdx_] = inR;
        writeIdx_ = (writeIdx_ + 1) % MAX_LOOKAHEAD_SAMPLES;

        buffer[i * 2] = std::max(-1.0f, std::min(outL, 1.0f));
        buffer[i * 2 + 1] = std::max(-1.0f, std::min(outR, 1.0f));
    }
}
