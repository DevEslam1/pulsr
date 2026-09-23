// android/app/src/main/cpp/Crossfeed.cpp
#include "Crossfeed.h"
#include <cstring>
#include <cmath>
#include <algorithm>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

Crossfeed::Crossfeed() {
    setSampleRate(48000.0);
    setMode(CrossfeedMode::Bs2bDefault);
    reset();
}

void Crossfeed::setSampleRate(double sampleRate) {
    if (sampleRate < 8000.0) sampleRate = 8000.0;
    if (sampleRate > 768000.0) sampleRate = 768000.0;
    sampleRate_ = sampleRate;
    setMode(mode_);
    reset();
}

void Crossfeed::initBs2b(double fcut, double feedDb) {
    double level = std::abs(feedDb);
    if (level < 1.0) level = 1.0;
    if (level > 15.0) level = 15.0;

    double Fc_lo = std::clamp(fcut, 300.0, 2000.0);
    double GB_lo = level * -5.0 / 6.0 - 3.0;
    double GB_hi = level / 6.0 - 3.0;
    double G_lo  = std::pow(10.0, GB_lo / 20.0);
    double G_hi  = 1.0 - std::pow(10.0, GB_hi / 20.0);
    double Fc_hi = Fc_lo * std::pow(2.0, (GB_lo - 20.0 * std::log10(G_hi)) / 12.0);

    double x_lo = std::exp(-2.0 * M_PI * Fc_lo / sampleRate_);
    bs2b_b1_lo_ = x_lo;
    bs2b_a0_lo_ = G_lo * (1.0 - x_lo);

    double x_hi = std::exp(-2.0 * M_PI * Fc_hi / sampleRate_);
    bs2b_b1_hi_ = x_hi;
    bs2b_a0_hi_ = 1.0 - G_hi * (1.0 - x_hi);
    bs2b_a1_hi_ = -x_hi;

    bs2b_gain_ = 1.0 / (1.0 - G_hi + G_lo);
}

void Crossfeed::setMode(CrossfeedMode mode) {
    mode_ = mode;
    switch (mode_) {
        case CrossfeedMode::Bs2bDefault:
            fcut_ = 700.0;
            feedDb_ = -4.5;
            delayUs_ = 300.0;
            break;
        case CrossfeedMode::Bs2bChuMoy:
            fcut_ = 700.0;
            feedDb_ = -6.0;
            delayUs_ = 350.0;
            break;
        case CrossfeedMode::Bs2bJanMeier:
            fcut_ = 650.0;
            feedDb_ = -9.5;
            delayUs_ = 400.0;
            break;
        case CrossfeedMode::Custom:
            break;
    }
    initBs2b(fcut_, feedDb_);
    configure(delayUs_, feedDb_, fcut_);
}

void Crossfeed::configure(double delayUs, double feedDb, double fcut) {
    delayUs_ = std::clamp(delayUs, 50.0, 2000.0);
    feedDb_ = std::clamp(feedDb, -30.0, 0.0);
    fcut_ = std::clamp(fcut, 100.0, 5000.0);

    targetDelaySamples_ = std::clamp(static_cast<float>(sampleRate_ * delayUs_ / 1e6), 1.0f, static_cast<float>(MAX_DELAY_SAMPLES - 2));
    delaySamplesFloat_ = targetDelaySamples_;
    targetFeedLevel_ = static_cast<float>(std::pow(10.0, feedDb_ / 20.0));

    const double fc = fcut_ / sampleRate_;
    targetLpCoeff_ = static_cast<float>(1.0 - std::exp(-2.0 * M_PI * fc));
    lpCoeff_ = targetLpCoeff_;

    initBs2b(fcut_, feedDb_);
}

void Crossfeed::setEnabled(bool enabled) {
    enabled_ = enabled;
}

void Crossfeed::applyParams(const CrossfeedParamSet& params) {
    enabled_ = params.enabled;
    mode_ = params.mode;
    if (mode_ == CrossfeedMode::Custom) {
        configure(params.delayUs, params.feedDb, params.fcut);
    } else {
        setMode(mode_);
    }
}

void Crossfeed::reset() {
    std::memset(delayBufferL_, 0, sizeof(delayBufferL_));
    std::memset(delayBufferR_, 0, sizeof(delayBufferR_));
    writeIdx_ = 0;
    lpL_ = 0.0f;
    lpR_ = 0.0f;
    smoothedFeedLevel_ = targetFeedLevel_;
    smoothedDelaySamples_ = targetDelaySamples_;
    smoothedLpCoeff_ = targetLpCoeff_;
    smoothedEnabledMix_ = enabled_ ? 1.0f : 0.0f;

    bs2b_lo_[0] = 0.0; bs2b_lo_[1] = 0.0;
    bs2b_hi_[0] = 0.0; bs2b_hi_[1] = 0.0;
    bs2b_asis_[0] = 0.0; bs2b_asis_[1] = 0.0;
}

void Crossfeed::process(float* L, float* R, int frames) {
    const float targetMix = enabled_ ? 1.0f : 0.0f;
    if (!enabled_ && smoothedEnabledMix_ < 1e-4f) return;
    if (!L || !R || frames <= 0) return;

    constexpr double kTau = 0.015;
    const double smoothFactor = 1.0 - std::exp(-static_cast<double>(frames) / (sampleRate_ * kTau));
    const float startMix = smoothedEnabledMix_;
    smoothedEnabledMix_ += static_cast<float>(smoothFactor) * (targetMix - smoothedEnabledMix_);
    const float mixStep = (smoothedEnabledMix_ - startMix) / static_cast<float>(frames);
    float currentMix = startMix;

    if (mode_ != CrossfeedMode::Custom) {
        for (int i = 0; i < frames; ++i) {
            double inL = L[i];
            double inR = R[i];
            if (!std::isfinite(inL)) inL = 0.0;
            if (!std::isfinite(inR)) inR = 0.0;

            bs2b_lo_[0] = bs2b_a0_lo_ * inL + bs2b_b1_lo_ * bs2b_lo_[0];
            bs2b_lo_[1] = bs2b_a0_lo_ * inR + bs2b_b1_lo_ * bs2b_lo_[1];

            bs2b_hi_[0] = bs2b_a0_hi_ * inL + bs2b_a1_hi_ * bs2b_asis_[0] + bs2b_b1_hi_ * bs2b_hi_[0];
            bs2b_hi_[1] = bs2b_a0_hi_ * inR + bs2b_a1_hi_ * bs2b_asis_[1] + bs2b_b1_hi_ * bs2b_hi_[1];
            bs2b_asis_[0] = inL;
            bs2b_asis_[1] = inR;
            // Flush subnormal state during silence (ARM denormal CPU spikes).
            if (std::abs(bs2b_lo_[0]) < 1e-30) bs2b_lo_[0] = 0.0;
            if (std::abs(bs2b_lo_[1]) < 1e-30) bs2b_lo_[1] = 0.0;
            if (std::abs(bs2b_hi_[0]) < 1e-30) bs2b_hi_[0] = 0.0;
            if (std::abs(bs2b_hi_[1]) < 1e-30) bs2b_hi_[1] = 0.0;

            float outL = static_cast<float>((bs2b_hi_[0] + bs2b_lo_[1]) * bs2b_gain_);
            float outR = static_cast<float>((bs2b_hi_[1] + bs2b_lo_[0]) * bs2b_gain_);

            L[i] = (1.0f - currentMix) * static_cast<float>(inL) + currentMix * outL;
            R[i] = (1.0f - currentMix) * static_cast<float>(inR) + currentMix * outR;
            currentMix += mixStep;
        }
        return;
    }

    // Custom Delay-Line Crossfeed mode
    smoothedFeedLevel_ += static_cast<float>(smoothFactor) * (targetFeedLevel_ - smoothedFeedLevel_);
    smoothedLpCoeff_ += static_cast<float>(smoothFactor) * (targetLpCoeff_ - smoothedLpCoeff_);

    const float startDelay = smoothedDelaySamples_;
    smoothedDelaySamples_ += static_cast<float>(smoothFactor) * (targetDelaySamples_ - smoothedDelaySamples_);
    const float delayStep = (smoothedDelaySamples_ - startDelay) / static_cast<float>(frames);
    float currentDelay = startDelay;

    const float feedLevel = smoothedFeedLevel_;
    const float lpCoeff = smoothedLpCoeff_;
    const float makeup = 1.0f / (1.0f + feedLevel);

    for (int i = 0; i < frames; ++i) {
        float l = L[i];
        float r = R[i];
        if (!std::isfinite(l)) l = 0.0f;
        if (!std::isfinite(r)) r = 0.0f;

        lpL_ += lpCoeff * (l - lpL_);
        lpR_ += lpCoeff * (r - lpR_);

        if (!std::isfinite(lpL_)) lpL_ = 0.0f;
        if (!std::isfinite(lpR_)) lpR_ = 0.0f;
        if (std::abs(lpL_) < 1e-25f) lpL_ = 0.0f;
        if (std::abs(lpR_) < 1e-25f) lpR_ = 0.0f;

        currentDelay += delayStep;
        float exactReadPos = static_cast<float>(writeIdx_) - currentDelay;
        while (exactReadPos < 0.0f) exactReadPos += static_cast<float>(MAX_DELAY_SAMPLES);
        const int rdIdx0 = static_cast<int>(exactReadPos) % MAX_DELAY_SAMPLES;
        const int rdIdx1 = (rdIdx0 + 1) % MAX_DELAY_SAMPLES;
        const float frac = exactReadPos - static_cast<float>(static_cast<int>(exactReadPos));

        const float delayedL = (1.0f - frac) * delayBufferL_[rdIdx0] + frac * delayBufferL_[rdIdx1];
        const float delayedR = (1.0f - frac) * delayBufferR_[rdIdx0] + frac * delayBufferR_[rdIdx1];

        delayBufferL_[writeIdx_] = lpL_;
        delayBufferR_[writeIdx_] = lpR_;
        writeIdx_ = (writeIdx_ + 1) % MAX_DELAY_SAMPLES;

        float outL = (l + delayedR * feedLevel) * makeup;
        float outR = (r + delayedL * feedLevel) * makeup;

        L[i] = (1.0f - currentMix) * l + currentMix * outL;
        R[i] = (1.0f - currentMix) * r + currentMix * outR;
        currentMix += mixStep;
    }
}

void Crossfeed::processInterleaved(float* buffer, int frames, int channels) {
    const float targetMix = enabled_ ? 1.0f : 0.0f;
    if (!enabled_ && smoothedEnabledMix_ < 1e-4f) return;
    if (!buffer || frames <= 0 || channels < 2) return;

    constexpr double kTau = 0.015;
    const double smoothFactor = 1.0 - std::exp(-static_cast<double>(frames) / (sampleRate_ * kTau));
    const float startMix = smoothedEnabledMix_;
    smoothedEnabledMix_ += static_cast<float>(smoothFactor) * (targetMix - smoothedEnabledMix_);
    const float mixStep = (smoothedEnabledMix_ - startMix) / static_cast<float>(frames);
    float currentMix = startMix;

    if (mode_ != CrossfeedMode::Custom) {
        for (int i = 0; i < frames; ++i) {
            const int idx = i * channels;
            double inL = buffer[idx];
            double inR = buffer[idx + 1];
            if (!std::isfinite(inL)) inL = 0.0;
            if (!std::isfinite(inR)) inR = 0.0;

            bs2b_lo_[0] = bs2b_a0_lo_ * inL + bs2b_b1_lo_ * bs2b_lo_[0];
            bs2b_lo_[1] = bs2b_a0_lo_ * inR + bs2b_b1_lo_ * bs2b_lo_[1];

            bs2b_hi_[0] = bs2b_a0_hi_ * inL + bs2b_a1_hi_ * bs2b_asis_[0] + bs2b_b1_hi_ * bs2b_hi_[0];
            bs2b_hi_[1] = bs2b_a0_hi_ * inR + bs2b_a1_hi_ * bs2b_asis_[1] + bs2b_b1_hi_ * bs2b_hi_[1];
            bs2b_asis_[0] = inL;
            bs2b_asis_[1] = inR;
            // Flush subnormal state during silence (ARM denormal CPU spikes).
            if (std::abs(bs2b_lo_[0]) < 1e-30) bs2b_lo_[0] = 0.0;
            if (std::abs(bs2b_lo_[1]) < 1e-30) bs2b_lo_[1] = 0.0;
            if (std::abs(bs2b_hi_[0]) < 1e-30) bs2b_hi_[0] = 0.0;
            if (std::abs(bs2b_hi_[1]) < 1e-30) bs2b_hi_[1] = 0.0;

            float outL = static_cast<float>((bs2b_hi_[0] + bs2b_lo_[1]) * bs2b_gain_);
            float outR = static_cast<float>((bs2b_hi_[1] + bs2b_lo_[0]) * bs2b_gain_);

            buffer[idx] = (1.0f - currentMix) * static_cast<float>(inL) + currentMix * outL;
            buffer[idx + 1] = (1.0f - currentMix) * static_cast<float>(inR) + currentMix * outR;
            currentMix += mixStep;
        }
        return;
    }

    // Custom Delay-Line Crossfeed mode
    smoothedFeedLevel_ += static_cast<float>(smoothFactor) * (targetFeedLevel_ - smoothedFeedLevel_);
    smoothedLpCoeff_ += static_cast<float>(smoothFactor) * (targetLpCoeff_ - smoothedLpCoeff_);

    const float startDelay = smoothedDelaySamples_;
    smoothedDelaySamples_ += static_cast<float>(smoothFactor) * (targetDelaySamples_ - smoothedDelaySamples_);
    const float delayStep = (smoothedDelaySamples_ - startDelay) / static_cast<float>(frames);
    float currentDelay = startDelay;

    const float feedLevel = smoothedFeedLevel_;
    const float lpCoeff = smoothedLpCoeff_;
    const float makeup = 1.0f / (1.0f + feedLevel);

    for (int i = 0; i < frames; ++i) {
        const int idx = i * channels;
        float l = buffer[idx];
        float r = buffer[idx + 1];
        if (!std::isfinite(l)) l = 0.0f;
        if (!std::isfinite(r)) r = 0.0f;

        lpL_ += lpCoeff * (l - lpL_);
        lpR_ += lpCoeff * (r - lpR_);

        if (!std::isfinite(lpL_)) lpL_ = 0.0f;
        if (!std::isfinite(lpR_)) lpR_ = 0.0f;
        if (std::abs(lpL_) < 1e-25f) lpL_ = 0.0f;
        if (std::abs(lpR_) < 1e-25f) lpR_ = 0.0f;

        currentDelay += delayStep;
        float exactReadPos = static_cast<float>(writeIdx_) - currentDelay;
        while (exactReadPos < 0.0f) exactReadPos += static_cast<float>(MAX_DELAY_SAMPLES);
        const int rdIdx0 = static_cast<int>(exactReadPos) % MAX_DELAY_SAMPLES;
        const int rdIdx1 = (rdIdx0 + 1) % MAX_DELAY_SAMPLES;
        const float frac = exactReadPos - static_cast<float>(static_cast<int>(exactReadPos));

        const float delayedL = (1.0f - frac) * delayBufferL_[rdIdx0] + frac * delayBufferL_[rdIdx1];
        const float delayedR = (1.0f - frac) * delayBufferR_[rdIdx0] + frac * delayBufferR_[rdIdx1];

        delayBufferL_[writeIdx_] = lpL_;
        delayBufferR_[writeIdx_] = lpR_;
        writeIdx_ = (writeIdx_ + 1) % MAX_DELAY_SAMPLES;

        float outL = (l + delayedR * feedLevel) * makeup;
        float outR = (r + delayedL * feedLevel) * makeup;

        buffer[idx] = (1.0f - currentMix) * l + currentMix * outL;
        buffer[idx + 1] = (1.0f - currentMix) * r + currentMix * outR;
        currentMix += mixStep;
    }
}

