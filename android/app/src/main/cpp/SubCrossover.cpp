// android/app/src/main/cpp/SubCrossover.cpp
#include "SubCrossover.h"
#include <cstring>

SubCrossover::SubCrossover() {
    setSampleRate(48000.0);
    configure(80.0, 24.0, 0.8);
    reset();
}

void SubCrossover::setSampleRate(double sampleRate) {
    if (sampleRate < 8000.0) sampleRate = 8000.0;
    if (sampleRate > 768000.0) sampleRate = 768000.0;
    sampleRate_ = sampleRate;
    computeCoeffs();
}

void SubCrossover::configure(double cornerHz, double slopeDbPerOct, double subGain) {
    cornerHz_ = std::clamp(cornerHz, 60.0, 150.0);
    // Accept 12 or 24 dB/oct; anything between snaps to the nearest supported slope.
    slopeDbPerOct_ = (slopeDbPerOct < 18.0) ? 12.0 : 24.0;
    subGain_ = std::clamp(subGain, 0.0, 1.0);
    cascade_ = slopeDbPerOct_ >= 24.0;
    computeCoeffs();
}

void SubCrossover::applyParams(const SubCrossoverParamSet& params) {
    enabled_ = params.enabled;
    configure(params.cornerHz, params.slopeDbPerOct, params.subGain);
}

void SubCrossover::computeCoeffs() {
    // Cascaded 2nd-order Butterworth low-pass sections (Q = 0.7071) give a
    // Linkwitz-Riley-style response: one section = 12 dB/oct (LR2-ish),
    // two sections = 24 dB/oct (LR4).
    const double w0 = 2.0 * M_PI * cornerHz_ / sampleRate_;
    const double cw = std::cos(w0), sw = std::sin(w0);
    const double alpha = sw / (2.0 * 0.70710678118654752440);
    const double a0 = (1.0 + alpha);
    const double b0 = (1.0 - cw) / 2.0 / a0;
    const double b1 = (1.0 - cw) / a0;
    const double b2 = (1.0 - cw) / 2.0 / a0;
    const double a1 = (-2.0 * cw) / a0;
    const double a2 = (1.0 - alpha) / a0;

    for (int p = 0; p < MAX_PAIRS; ++p) {
        stage1_[p].b0 = b0; stage1_[p].b1 = b1; stage1_[p].b2 = b2;
        stage1_[p].a1 = a1; stage1_[p].a2 = a2;
        stage2_[p] = stage1_[p];
    }
}

void SubCrossover::reset() {
    for (int p = 0; p < MAX_PAIRS; ++p) {
        stage1_[p].z1 = stage1_[p].z2 = 0.0;
        stage2_[p].z1 = stage2_[p].z2 = 0.0;
    }
}

void SubCrossover::process(float* L, float* R, int frames) {
    if (!enabled_ || !L || !R || frames <= 0) return;
    if (subGain_ <= 1e-6) return;

    const float gain = static_cast<float>(subGain_);
    const float makeup = 1.0f / (1.0f + gain * 0.5f);
    LpStage& s1 = stage1_[0];
    LpStage& s2 = stage2_[0];

    for (int i = 0; i < frames; ++i) {
        const float l = L[i];
        const float r = R[i];
        const float mono = 0.5f * (l + r);
        float sub = s1.process(mono);
        if (cascade_) sub = s2.process(sub);
        const float subTap = sub * gain;
        L[i] = (l + subTap) * makeup;
        R[i] = (r + subTap) * makeup;
    }
}

void SubCrossover::processInterleaved(float* buffer, int frames, int channels) {
    if (!enabled_ || !buffer || frames <= 0 || channels < 2) return;
    if (subGain_ <= 1e-6) return;

    const float gain = static_cast<float>(subGain_);
    const float makeup = 1.0f / (1.0f + gain * 0.5f);
    // Redirect one mono sub tap per channel pair (stereo pairs stay coherent).
    for (int i = 0; i < frames; ++i) {
        for (int ch = 0; ch + 1 < channels; ch += 2) {
            const int iL = i * channels + ch;
            const int iR = i * channels + ch + 1;
            const float mono = 0.5f * (buffer[iL] + buffer[iR]);
            const int pair = ch >> 1;
            LpStage& s1 = stage1_[pair];
            LpStage& s2 = stage2_[pair];
            float sub = s1.process(mono);
            if (cascade_) sub = s2.process(sub);
            const float subTap = sub * gain;
            buffer[iL] = (buffer[iL] + subTap) * makeup;
            buffer[iR] = (buffer[iR] + subTap) * makeup;
        }
    }
}
