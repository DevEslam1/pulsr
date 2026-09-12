// android/app/src/main/cpp/SubCrossover.cpp
#include "SubCrossover.h"

SubCrossover::SubCrossover() {
    setSampleRate(48000.0);
    configure(80.0, 24.0, 0.8, true, true);
    reset();
}

void SubCrossover::setSampleRate(double sampleRate) {
    if (sampleRate < 8000.0) sampleRate = 8000.0;
    if (sampleRate > 768000.0) sampleRate = 768000.0;
    sampleRate_ = sampleRate;
    computeCoeffs();
}

void SubCrossover::configure(double cornerHz, double slopeDbPerOct, double subGain, bool bassMono, bool antiPop) {
    cornerHz_ = std::clamp(cornerHz, 30.0, 300.0);
    slopeDbPerOct_ = (slopeDbPerOct < 18.0) ? 12.0 : 24.0;
    cascade_ = (slopeDbPerOct_ >= 24.0);
    targetSubGain_ = std::clamp(subGain, 0.0, 1.5);
    bassMono_ = bassMono;
    antiPop_ = antiPop;
    computeCoeffs();
}

void SubCrossover::applyParams(const SubCrossoverParamSet& params) {
    enabled_ = params.enabled;
    configure(params.cornerHz, params.slopeDbPerOct, params.subGain, params.bassMono, params.antiPop);
}

void SubCrossover::computeCoeffs() {
    const double fc = std::clamp(cornerHz_, 20.0, sampleRate_ * 0.45);
    const double w0 = 2.0 * M_PI * fc / sampleRate_;
    const double cosw0 = std::cos(w0);
    const double sinw0 = std::sin(w0);
    const double q = 0.7071067811865475; // Butterworth Q
    const double alpha = sinw0 / (2.0 * q);

    const double a0 = 1.0 + alpha;
    const double b0 = ((1.0 - cosw0) / 2.0) / a0;
    const double b1 = (1.0 - cosw0) / a0;
    const double b2 = ((1.0 - cosw0) / 2.0) / a0;
    const double a1 = (-2.0 * cosw0) / a0;
    const double a2 = (1.0 - alpha) / a0;

    for (int p = 0; p < MAX_PAIRS; ++p) {
        stage1_[p].b0 = b0; stage1_[p].b1 = b1; stage1_[p].b2 = b2;
        stage1_[p].a1 = a1; stage1_[p].a2 = a2;
        stage2_[p] = stage1_[p];
        stageSide1_[p] = stage1_[p];
        stageSide2_[p] = stage1_[p];
    }
}

void SubCrossover::reset() {
    smoothedSubGain_ = targetSubGain_;
    for (int p = 0; p < MAX_PAIRS; ++p) {
        stage1_[p].z1 = stage1_[p].z2 = 0.0;
        stage2_[p].z1 = stage2_[p].z2 = 0.0;
        stageSide1_[p].z1 = stageSide1_[p].z2 = 0.0;
        stageSide2_[p].z1 = stageSide2_[p].z2 = 0.0;
    }
}

void SubCrossover::process(float* L, float* R, int frames) {
    if (!enabled_ || !L || !R || frames <= 0) return;

    constexpr double kTau = 0.020;
    const double smoothFactor = 1.0 - std::exp(-static_cast<double>(frames) / (sampleRate_ * kTau));
    smoothedSubGain_ += smoothFactor * (targetSubGain_ - smoothedSubGain_);

    const float gain = static_cast<float>(smoothedSubGain_);
    const float makeup = 1.0f / (1.0f + gain * 0.5f);
    LpStage& s1 = stage1_[0];
    LpStage& s2 = stage2_[0];
    LpStage& ss1 = stageSide1_[0];
    LpStage& ss2 = stageSide2_[0];

    const bool doBassMono = bassMono_;
    const bool doAntiPop = antiPop_;

    for (int i = 0; i < frames; ++i) {
        float l = L[i];
        float r = R[i];

        // 1. Bass Mono isolation: subtract side energy below cornerHz
        if (doBassMono) {
            const float side = 0.5f * (l - r);
            float sideSub = ss1.process(side);
            if (cascade_) sideSub = ss2.process(sideSub);
            l -= sideSub;
            r += sideSub;
        }

        // 2. Low-pass mono sub redirection
        const float mono = 0.5f * (l + r);
        float sub = s1.process(mono);
        if (cascade_) sub = s2.process(sub);

        // 3. Anti-pop soft limiting
        if (doAntiPop) {
            sub = std::tanh(sub);
        }

        const float subTap = sub * gain;
        L[i] = (l + subTap) * makeup;
        R[i] = (r + subTap) * makeup;
    }
}

void SubCrossover::processInterleaved(float* buffer, int frames, int channels) {
    channels = std::clamp(channels, 2, MAX_CHANNELS);
    if (!enabled_ || !buffer || frames <= 0 || channels < 2) return;

    constexpr double kTau = 0.020;
    const double smoothFactor = 1.0 - std::exp(-static_cast<double>(frames) / (sampleRate_ * kTau));
    smoothedSubGain_ += smoothFactor * (targetSubGain_ - smoothedSubGain_);

    const float gain = static_cast<float>(smoothedSubGain_);
    const float makeup = 1.0f / (1.0f + gain * 0.5f);
    const bool doBassMono = bassMono_;
    const bool doAntiPop = antiPop_;

    for (int i = 0; i < frames; ++i) {
        for (int ch = 0; ch + 1 < channels; ch += 2) {
            const int iL = i * channels + ch;
            const int iR = i * channels + ch + 1;
            float l = buffer[iL];
            float r = buffer[iR];

            const int pair = ch >> 1;
            LpStage& s1 = stage1_[pair];
            LpStage& s2 = stage2_[pair];
            LpStage& ss1 = stageSide1_[pair];
            LpStage& ss2 = stageSide2_[pair];

            if (doBassMono) {
                const float side = 0.5f * (l - r);
                float sideSub = ss1.process(side);
                if (cascade_) sideSub = ss2.process(sideSub);
                l -= sideSub;
                r += sideSub;
            }

            const float mono = 0.5f * (l + r);
            float sub = s1.process(mono);
            if (cascade_) sub = s2.process(sub);

            if (doAntiPop) {
                sub = std::tanh(sub);
            }

            const float subTap = sub * gain;
            buffer[iL] = (l + subTap) * makeup;
            buffer[iR] = (r + subTap) * makeup;
        }
    }
}
