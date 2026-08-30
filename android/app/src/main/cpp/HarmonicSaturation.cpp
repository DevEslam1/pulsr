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

    const double fc = kTiltHpHz / sampleRate_;
    tiltHpCoeff_ = static_cast<float>(1.0 - std::exp(-2.0 * M_PI * fc));
}

void HarmonicSaturation::applyParams(const SaturationParamSet& params) {
    enabled_ = params.enabled;
    configure(params.drive, params.mix, params.tilt);
}

void HarmonicSaturation::reset() {
    std::memset(hpState_, 0, sizeof(hpState_));
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
        float l = L[i];
        float r = R[i];
        if (!std::isfinite(l)) l = 0.0f;
        if (!std::isfinite(r)) r = 0.0f;

        float wetL = l;
        float wetR = r;
        if (k > 1e-9) {
            // Tilt pre-emphasis: add a touch of HP content so HF drives the shaper harder
            float emphL = l;
            float emphR = r;
            if (tilt > 0.0f) {
                hpL += hpCoeff * (l - hpL);
                hpR += hpCoeff * (r - hpR);
                if (!std::isfinite(hpL)) hpL = 0.0f;
                if (!std::isfinite(hpR)) hpR = 0.0f;
                emphL = l + tilt * (l - hpL);
                emphR = r + tilt * (r - hpR);
            }
            wetL = std::tanh(k * emphL) * invTanhK;
            wetR = std::tanh(k * emphR) * invTanhK;
        }

        if (!std::isfinite(wetL)) wetL = 0.0f;
        if (!std::isfinite(wetR)) wetR = 0.0f;

        L[i] = l + mix * (wetL - l);
        R[i] = r + mix * (wetR - r);
    }
}

void HarmonicSaturation::processInterleaved(float* buffer, int frames, int channels) {
    if (!enabled_ || !buffer || frames <= 0 || channels <= 0) return;
    if (channels == 2) {
        process(buffer, buffer + 1, frames);
        return;
    }

    const double k = k_;
    const float mix = static_cast<float>(mix_);
    const float tilt = static_cast<float>(tilt_);
    const float hpCoeff = tiltHpCoeff_;
    const float invTanhK = (k > 1e-9) ? static_cast<float>(1.0 / std::tanh(k)) : 1.0f;

    for (int i = 0; i < frames; ++i) {
        for (int ch = 0; ch < channels && ch < MAX_CHANNELS; ++ch) {
            float x = buffer[i * channels + ch];
            if (!std::isfinite(x)) x = 0.0f;

            float wet = x;
            if (k > 1e-9) {
                float emph = x;
                if (tilt > 0.0f) {
                    float& hp = hpState_[ch];
                    hp += hpCoeff * (x - hp);
                    if (!std::isfinite(hp)) hp = 0.0f;
                    emph = x + tilt * (x - hp);
                }
                wet = std::tanh(k * emph) * invTanhK;
            }
            if (!std::isfinite(wet)) wet = 0.0f;
            buffer[i * channels + ch] = x + mix * (wet - x);
        }
    }
}
