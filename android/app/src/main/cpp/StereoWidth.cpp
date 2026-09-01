// android/app/src/main/cpp/StereoWidth.cpp
#include "StereoWidth.h"
#include <algorithm>
#include <cmath>

StereoWidth::StereoWidth() {
    setSampleRate(48000.0);
    configure(1.0);
    reset();
}

void StereoWidth::setSampleRate(double sampleRate) {
    if (sampleRate < 8000.0) sampleRate = 8000.0;
    if (sampleRate > 768000.0) sampleRate = 768000.0;
    sampleRate_ = sampleRate;
}

void StereoWidth::configure(double width) {
    targetWidth_ = std::clamp(width, 0.0, 2.0);
}

void StereoWidth::applyParams(const StereoWidthParamSet& params) {
    enabled_ = params.enabled;
    configure(params.width);
}

void StereoWidth::reset() {
    smoothedWidth_ = targetWidth_;
}

void StereoWidth::process(float* L, float* R, int frames) {
    if (!enabled_ || !L || !R || frames <= 0) return;

    // Smooth width transitions across 15ms window
    constexpr double kTau = 0.015;
    const double smoothFactor = 1.0 - std::exp(-static_cast<double>(frames) / (sampleRate_ * kTau));
    smoothedWidth_ += smoothFactor * (targetWidth_ - smoothedWidth_);

    // Exact passthrough fast path when settled at unity width
    if (std::abs(smoothedWidth_ - 1.0) < 1e-5 && std::abs(targetWidth_ - 1.0) < 1e-5) return;

    const float w = static_cast<float>(smoothedWidth_);
    for (int i = 0; i < frames; ++i) {
        const float l = L[i];
        const float r = R[i];
        const float mid = 0.5f * (l + r);
        const float side = 0.5f * (l - r);
        L[i] = mid + w * side;
        R[i] = mid - w * side;
    }
}

void StereoWidth::processInterleaved(float* buffer, int frames, int channels) {
    if (!enabled_ || !buffer || frames <= 0 || channels < 2) return;

    // Smooth width transitions across 15ms window
    constexpr double kTau = 0.015;
    const double smoothFactor = 1.0 - std::exp(-static_cast<double>(frames) / (sampleRate_ * kTau));
    smoothedWidth_ += smoothFactor * (targetWidth_ - smoothedWidth_);

    // Exact passthrough fast path when settled at unity width
    if (std::abs(smoothedWidth_ - 1.0) < 1e-5 && std::abs(targetWidth_ - 1.0) < 1e-5) return;

    const float w = static_cast<float>(smoothedWidth_);
    for (int i = 0; i < frames; ++i) {
        for (int ch = 0; ch + 1 < channels; ch += 2) {
            const float l = buffer[i * channels + ch];
            const float r = buffer[i * channels + ch + 1];
            const float mid = 0.5f * (l + r);
            const float side = 0.5f * (l - r);
            buffer[i * channels + ch] = mid + w * side;
            buffer[i * channels + ch + 1] = mid - w * side;
        }
    }
}
