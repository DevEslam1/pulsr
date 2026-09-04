// android/app/src/main/cpp/HarmonicSaturation.cpp
#include "HarmonicSaturation.h"
#include <cstring>

namespace {
// drive 0..1 maps to tanh sharpness k = 0..kMax. k=0 keeps the identity
// (tanh(k*x)/tanh(k) -> x as k -> 0), so the drive slider is continuous
// from transparent to heavily saturated.
constexpr double kMaxDrive = 10.0;
// Tilt pre-emphasis one-pole highpass corner (~1.8 kHz): above this the
// shaper is driven progressively harder, emulating tape HF bias.
constexpr double kTiltHpHz = 1800.0;
} // namespace

// 24-tap polyphase sinc coefficients windowed with Blackman-Harris across 4 phases (6 taps per phase)
const float HarmonicSaturation::polyphase4x_[OVERSAMPLE_FACTOR][TAPS_PER_PHASE] = {
    { 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 0.0f },                       // Phase 0 (identity)
    { 0.0063f, -0.0984f, 0.8841f, 0.2642f, -0.0682f, 0.0120f },   // Phase 1 (1/4)
    { 0.0152f, -0.1386f, 0.6234f, 0.6234f, -0.1386f, 0.0152f },   // Phase 2 (2/4)
    { 0.0120f, -0.0682f, 0.2642f, 0.8841f, -0.0984f, 0.0063f }    // Phase 3 (3/4)
};

HarmonicSaturation::HarmonicSaturation() {
    setSampleRate(48000.0);
    configure(0.0, 0.5, 0.0);
    reset();
}

void HarmonicSaturation::setSampleRate(double sampleRate) {
    if (sampleRate < 8000.0) sampleRate = 8000.0;
    if (sampleRate > 768000.0) sampleRate = 768000.0;
    sampleRate_ = sampleRate;
    configure(drive_, mix_, tilt_);
}

void HarmonicSaturation::configure(double drive, double mix, double tilt) {
    drive_ = std::clamp(drive, 0.0, 1.0);
    mix_ = std::clamp(mix, 0.0, 1.0);
    tilt_ = std::clamp(tilt, 0.0, 1.0);
    k_ = drive_ * kMaxDrive;

    const double fc = kTiltHpHz / (sampleRate_ * OVERSAMPLE_FACTOR);
    tiltHpCoeff_ = static_cast<float>(1.0 - std::exp(-2.0 * M_PI * fc));
}

void HarmonicSaturation::applyParams(const SaturationParamSet& params) {
    enabled_ = params.enabled;
    configure(params.drive, params.mix, params.tilt);
}

void HarmonicSaturation::reset() {
    std::memset(hpState_, 0, sizeof(hpState_));
    std::memset(history_, 0, sizeof(history_));
}

void HarmonicSaturation::process(float* L, float* R, int frames) {
    if (!enabled_ || !L || !R || frames <= 0) return;

    const double k = k_;
    const float mix = static_cast<float>(mix_);
    const float tilt = static_cast<float>(tilt_);
    const float hpCoeff = tiltHpCoeff_;
    const float invTanhK = (k > 1e-9) ? static_cast<float>(1.0 / std::tanh(k)) : 1.0f;
    float& hpL = hpState_[0];
    float& hpR = hpState_[1];

    for (int i = 0; i < frames; ++i) {
        float inL = L[i];
        float inR = R[i];
        if (!std::isfinite(inL)) inL = 0.0f;
        if (!std::isfinite(inR)) inR = 0.0f;

        // Shift history buffers
        for (int t = TAPS_PER_PHASE - 1; t > 0; --t) {
            history_[0][t] = history_[0][t - 1];
            history_[1][t] = history_[1][t - 1];
        }
        history_[0][0] = inL;
        history_[1][0] = inR;

        float wetL = inL;
        float wetR = inR;

        if (k > 1e-9) {
            float sumL = 0.0f;
            float sumR = 0.0f;

            // 4x oversampled nonlinear waveshaping with anti-aliasing decimation
            for (int p = 0; p < OVERSAMPLE_FACTOR; ++p) {
                float subL = 0.0f;
                float subR = 0.0f;
                for (int t = 0; t < TAPS_PER_PHASE; ++t) {
                    const float coeff = polyphase4x_[p][t];
                    subL += history_[0][t] * coeff;
                    subR += history_[1][t] * coeff;
                }

                // Tilt pre-emphasis at 4x rate
                float emphL = subL;
                float emphR = subR;
                if (tilt > 0.0f) {
                    hpL += hpCoeff * (subL - hpL);
                    hpR += hpCoeff * (subR - hpR);
                    if (!std::isfinite(hpL)) hpL = 0.0f;
                    if (!std::isfinite(hpR)) hpR = 0.0f;
                    emphL = subL + tilt * (subL - hpL);
                    emphR = subR + tilt * (subR - hpR);
                }

                sumL += std::tanh(k * emphL) * invTanhK;
                sumR += std::tanh(k * emphR) * invTanhK;
            }

            wetL = sumL * (1.0f / static_cast<float>(OVERSAMPLE_FACTOR));
            wetR = sumR * (1.0f / static_cast<float>(OVERSAMPLE_FACTOR));
        }

        if (!std::isfinite(wetL)) wetL = 0.0f;
        if (!std::isfinite(wetR)) wetR = 0.0f;

        L[i] = inL + mix * (wetL - inL);
        R[i] = inR + mix * (wetR - inR);
    }
}

void HarmonicSaturation::processInterleaved(float* buffer, int frames, int channels) {
    if (!enabled_ || !buffer || frames <= 0 || channels <= 0) return;

    const double k = k_;
    const float mix = static_cast<float>(mix_);
    const float tilt = static_cast<float>(tilt_);
    const float hpCoeff = tiltHpCoeff_;
    const float invTanhK = (k > 1e-9) ? static_cast<float>(1.0 / std::tanh(k)) : 1.0f;

    // Fast unrolled path for stereo (channels == 2)
    if (channels == 2) {
        float& hpL = hpState_[0];
        float& hpR = hpState_[1];

        for (int i = 0; i < frames; ++i) {
            float inL = buffer[i * 2];
            float inR = buffer[i * 2 + 1];
            if (!std::isfinite(inL)) inL = 0.0f;
            if (!std::isfinite(inR)) inR = 0.0f;

            for (int t = TAPS_PER_PHASE - 1; t > 0; --t) {
                history_[0][t] = history_[0][t - 1];
                history_[1][t] = history_[1][t - 1];
            }
            history_[0][0] = inL;
            history_[1][0] = inR;

            float wetL = inL;
            float wetR = inR;

            if (k > 1e-9) {
                float sumL = 0.0f;
                float sumR = 0.0f;

                for (int p = 0; p < OVERSAMPLE_FACTOR; ++p) {
                    float subL = 0.0f;
                    float subR = 0.0f;
                    for (int t = 0; t < TAPS_PER_PHASE; ++t) {
                        const float coeff = polyphase4x_[p][t];
                        subL += history_[0][t] * coeff;
                        subR += history_[1][t] * coeff;
                    }

                    float emphL = subL;
                    float emphR = subR;
                    if (tilt > 0.0f) {
                        hpL += hpCoeff * (subL - hpL);
                        hpR += hpCoeff * (subR - hpR);
                        if (!std::isfinite(hpL)) hpL = 0.0f;
                        if (!std::isfinite(hpR)) hpR = 0.0f;
                        emphL = subL + tilt * (subL - hpL);
                        emphR = subR + tilt * (subR - hpR);
                    }

                    sumL += std::tanh(k * emphL) * invTanhK;
                    sumR += std::tanh(k * emphR) * invTanhK;
                }

                wetL = sumL * (1.0f / static_cast<float>(OVERSAMPLE_FACTOR));
                wetR = sumR * (1.0f / static_cast<float>(OVERSAMPLE_FACTOR));
            }

            if (!std::isfinite(wetL)) wetL = 0.0f;
            if (!std::isfinite(wetR)) wetR = 0.0f;

            buffer[i * 2] = inL + mix * (wetL - inL);
            buffer[i * 2 + 1] = inR + mix * (wetR - inR);
        }
        return;
    }

    // Multichannel path (channels != 2)
    for (int i = 0; i < frames; ++i) {
        for (int ch = 0; ch < channels && ch < MAX_CHANNELS; ++ch) {
            float inX = buffer[i * channels + ch];
            if (!std::isfinite(inX)) inX = 0.0f;

            for (int t = TAPS_PER_PHASE - 1; t > 0; --t) {
                history_[ch][t] = history_[ch][t - 1];
            }
            history_[ch][0] = inX;

            float wet = inX;
            if (k > 1e-9) {
                float sum = 0.0f;
                for (int p = 0; p < OVERSAMPLE_FACTOR; ++p) {
                    float sub = 0.0f;
                    for (int t = 0; t < TAPS_PER_PHASE; ++t) {
                        sub += history_[ch][t] * polyphase4x_[p][t];
                    }

                    float emph = sub;
                    if (tilt > 0.0f) {
                        float& hp = hpState_[ch];
                        hp += hpCoeff * (sub - hp);
                        if (!std::isfinite(hp)) hp = 0.0f;
                        emph = sub + tilt * (sub - hp);
                    }

                    sum += std::tanh(k * emph) * invTanhK;
                }
                wet = sum * (1.0f / static_cast<float>(OVERSAMPLE_FACTOR));
            }

            if (!std::isfinite(wet)) wet = 0.0f;
            buffer[i * channels + ch] = inX + mix * (wet - inX);
        }
    }
}
