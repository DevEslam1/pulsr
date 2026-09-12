// android/app/src/main/cpp/HarmonicSaturation.cpp
#include "HarmonicSaturation.h"
#include <cstring>

namespace {
constexpr double kMaxDrive = 5.0;
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
    configure(0.0, 0.5, 0.0, 0);
    reset();
}

void HarmonicSaturation::setSampleRate(double sampleRate) {
    if (sampleRate < 8000.0) sampleRate = 8000.0;
    if (sampleRate > 768000.0) sampleRate = 768000.0;
    sampleRate_ = sampleRate;
    configure(drive_, mix_, tilt_, mode_);
}

void HarmonicSaturation::configure(double drive, double mix, double tilt, int mode, bool multiband) {
    drive_ = std::clamp(drive, 0.0, 1.0);
    mix_ = std::clamp(mix, 0.0, 1.0);
    tilt_ = std::clamp(tilt, 0.0, 1.0);
    mode_ = std::clamp(mode, 0, 2);
    multiband_ = multiband;
    k_ = drive_ * kMaxDrive;

    const double fc = kTiltHpHz / (sampleRate_ * OVERSAMPLE_FACTOR);
    tiltHpCoeff_ = static_cast<float>(1.0 - std::exp(-2.0 * M_PI * fc));
}

void HarmonicSaturation::applyParams(const SaturationParamSet& params) {
    enabled_ = params.enabled;
    configure(params.drive, params.mix, params.tilt, params.mode, params.multiband);
}

void HarmonicSaturation::reset() {
    std::memset(hpState_, 0, sizeof(hpState_));
    std::memset(history_, 0, sizeof(history_));
    std::memset(dcX_, 0, sizeof(dcX_));
    std::memset(dcY_, 0, sizeof(dcY_));
}

static inline float shapeSample(float x, double k, float invNorm, int mode) {
    const float xin = static_cast<float>(k) * x;
    if (mode == 1) {
        // Tube (Triode / 6J1): asymmetric quadratic curve generating rich 2nd harmonics
        const float num = xin + 0.35f * (xin * std::abs(xin));
        const float den = 1.0f + 0.35f * std::abs(xin);
        return (num / den) * invNorm;
    } else if (mode == 2) {
        // Analog Class-A single-ended transistor curve
        const float num = xin - 0.15f * (xin * xin * xin) + 0.20f * (xin * std::abs(xin));
        const float den = 1.0f + 0.25f * std::abs(xin);
        return (num / den) * invNorm;
    }
    // Mode 0: Tape (symmetric tanh)
    return std::tanh(xin) * invNorm;
}

void HarmonicSaturation::process(float* L, float* R, int frames) {
    if (!enabled_ || !L || !R || frames <= 0) return;

    const double k = k_;
    const float mix = static_cast<float>(mix_);
    const float tilt = static_cast<float>(tilt_);
    const float hpCoeff = tiltHpCoeff_;
    const float invNorm = (k > 1e-9) ? static_cast<float>(1.0 / k) : 1.0f;
    const int mode = mode_;
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

                sumL += shapeSample(emphL, k, invNorm, mode);
                sumR += shapeSample(emphR, k, invNorm, mode);
            }

            wetL = sumL * (1.0f / static_cast<float>(OVERSAMPLE_FACTOR));
            wetR = sumR * (1.0f / static_cast<float>(OVERSAMPLE_FACTOR));

            // DC blocker for asymmetric modes
            if (mode != 0) {
                float yL = wetL - dcX_[0] + 0.9995f * dcY_[0];
                float yR = wetR - dcX_[1] + 0.9995f * dcY_[1];
                dcX_[0] = wetL;
                dcX_[1] = wetR;
                dcY_[0] = yL;
                dcY_[1] = yR;
                wetL = yL;
                wetR = yR;
            }
        }

        if (!std::isfinite(wetL)) wetL = 0.0f;
        if (!std::isfinite(wetR)) wetR = 0.0f;

        L[i] = (1.0f - mix) * inL + mix * wetL;
        R[i] = (1.0f - mix) * inR + mix * wetR;
    }
}

void HarmonicSaturation::processInterleaved(float* buffer, int frames, int channels) {
    channels = std::clamp(channels, 1, MAX_CHANNELS);
    if (!enabled_ || !buffer || frames <= 0 || channels <= 0) return;

    const double k = k_;
    const float mix = static_cast<float>(mix_);
    const float tilt = static_cast<float>(tilt_);
    const float hpCoeff = tiltHpCoeff_;
    const float invNorm = (k > 1e-9) ? static_cast<float>(1.0 / k) : 1.0f;
    const int mode = mode_;

    for (int i = 0; i < frames; ++i) {
        for (int ch = 0; ch < channels; ++ch) {
            const int idx = i * channels + ch;
            float inSample = buffer[idx];
            if (!std::isfinite(inSample)) inSample = 0.0f;

            for (int t = TAPS_PER_PHASE - 1; t > 0; --t) {
                history_[ch][t] = history_[ch][t - 1];
            }
            history_[ch][0] = inSample;

            float wet = inSample;

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

                    sum += shapeSample(emph, k, invNorm, mode);
                }

                wet = sum * (1.0f / static_cast<float>(OVERSAMPLE_FACTOR));

                if (mode != 0) {
                    float y = wet - dcX_[ch] + 0.9995f * dcY_[ch];
                    dcX_[ch] = wet;
                    dcY_[ch] = y;
                    wet = y;
                }
            }

            if (!std::isfinite(wet)) wet = 0.0f;

            buffer[idx] = (1.0f - mix) * inSample + mix * wet;
        }
    }
}
