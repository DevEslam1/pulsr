// android/app/src/main/cpp/Crossfeed.cpp
#include "Crossfeed.h"
#include <cstring>
#include <cmath>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

Crossfeed::Crossfeed() {
    setSampleRate(48000.0);
    configure(350.0, -9.0, 650.0);
    reset();
}

void Crossfeed::setSampleRate(double sampleRate) {
    if (sampleRate < 8000.0) sampleRate = 8000.0;
    if (sampleRate > 768000.0) sampleRate = 768000.0;
    sampleRate_ = sampleRate;
    configure(delayUs_, feedDb_, fcut_);
}

void Crossfeed::configure(double delayUs, double feedDb, double fcut) {
    delayUs_ = std::clamp(delayUs, 50.0, 2000.0);
    feedDb_ = std::clamp(feedDb, -30.0, 0.0);
    fcut_ = std::clamp(fcut, 100.0, 5000.0);

    delaySamples_ = std::clamp(static_cast<int>(sampleRate_ * delayUs_ / 1e6), 1, MAX_DELAY_SAMPLES - 1);
    feedLevel_ = static_cast<float>(std::pow(10.0, feedDb_ / 20.0));

    // One-pole lowpass filter for head-shadow simulation at fcut
    const double fc = fcut_ / sampleRate_;
    lpCoeff_ = static_cast<float>(1.0 - std::exp(-2.0 * M_PI * fc));
}

void Crossfeed::setEnabled(bool enabled) {
    enabled_ = enabled;
}

void Crossfeed::applyParams(const CrossfeedParamSet& params) {
    enabled_ = params.enabled;
    configure(params.delayUs, params.feedDb, params.fcut);
}

void Crossfeed::reset() {
    std::memset(delayBufferL_, 0, sizeof(delayBufferL_));
    std::memset(delayBufferR_, 0, sizeof(delayBufferR_));
    writeIdx_ = 0;
    lpL_ = 0.0f;
    lpR_ = 0.0f;
}

void Crossfeed::process(float* L, float* R, int frames) {
    if (!enabled_ || !L || !R || frames <= 0) return;
    const float makeup = 1.0f / (1.0f + feedLevel_);

    for (int i = 0; i < frames; ++i) {
        float l = L[i];
        float r = R[i];
        if (!std::isfinite(l)) l = 0.0f;
        if (!std::isfinite(r)) r = 0.0f;

        lpL_ += lpCoeff_ * (l - lpL_);
        lpR_ += lpCoeff_ * (r - lpR_);

        if (!std::isfinite(lpL_)) lpL_ = 0.0f;
        if (!std::isfinite(lpR_)) lpR_ = 0.0f;

        const int rdIdx = (writeIdx_ - delaySamples_ + MAX_DELAY_SAMPLES) % MAX_DELAY_SAMPLES;
        const float delayedL = delayBufferL_[rdIdx];
        const float delayedR = delayBufferR_[rdIdx];

        delayBufferL_[writeIdx_] = lpL_;
        delayBufferR_[writeIdx_] = lpR_;
        writeIdx_ = (writeIdx_ + 1) % MAX_DELAY_SAMPLES;

        L[i] = (l + delayedR * feedLevel_) * makeup;
        R[i] = (r + delayedL * feedLevel_) * makeup;
    }
}

void Crossfeed::processInterleaved(float* buffer, int frames) {
    if (!enabled_ || !buffer || frames <= 0) return;
    const float makeup = 1.0f / (1.0f + feedLevel_);

    for (int i = 0; i < frames; ++i) {
        float l = buffer[i * 2];
        float r = buffer[i * 2 + 1];
        if (!std::isfinite(l)) l = 0.0f;
        if (!std::isfinite(r)) r = 0.0f;

        lpL_ += lpCoeff_ * (l - lpL_);
        lpR_ += lpCoeff_ * (r - lpR_);

        if (!std::isfinite(lpL_)) lpL_ = 0.0f;
        if (!std::isfinite(lpR_)) lpR_ = 0.0f;

        const int rdIdx = (writeIdx_ - delaySamples_ + MAX_DELAY_SAMPLES) % MAX_DELAY_SAMPLES;
        const float delayedL = delayBufferL_[rdIdx];
        const float delayedR = delayBufferR_[rdIdx];

        delayBufferL_[writeIdx_] = lpL_;
        delayBufferR_[writeIdx_] = lpR_;
        writeIdx_ = (writeIdx_ + 1) % MAX_DELAY_SAMPLES;

        buffer[i * 2] = (l + delayedR * feedLevel_) * makeup;
        buffer[i * 2 + 1] = (r + delayedL * feedLevel_) * makeup;
    }
}

