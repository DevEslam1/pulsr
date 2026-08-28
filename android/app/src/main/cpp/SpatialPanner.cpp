// android/app/src/main/cpp/SpatialPanner.cpp
#include "SpatialPanner.h"
#include <algorithm>

SpatialPanner::SpatialPanner() {
    setBalance(0.0);
    setMono(false);
    reset();
}

void SpatialPanner::setBalance(double balance) {
    targetBalance_ = std::clamp(balance, -1.0, 1.0);
}

void SpatialPanner::setMono(bool mono) {
    mono_ = mono;
}

void SpatialPanner::applyParams(const PannerParamSet& params) {
    targetBalance_ = std::clamp(params.balance, -1.0, 1.0);
    mono_ = params.monoMix;
}

void SpatialPanner::reset() {
    smoothedBalance_ = targetBalance_;
    const double theta = (smoothedBalance_ + 1.0) * (M_PI / 4.0); // 0 (left) to pi/2 (right)
    gainL_ = static_cast<float>(std::cos(theta) * std::sqrt(2.0));
    gainR_ = static_cast<float>(std::sin(theta) * std::sqrt(2.0));
}

void SpatialPanner::process(float* L, float* R, int frames) {
    if (!L || !R || frames <= 0) return;

    const double smoothFactor = 0.05; // Quick ~10ms smoothing per block
    smoothedBalance_ += smoothFactor * (targetBalance_ - smoothedBalance_);

    const double theta = (smoothedBalance_ + 1.0) * (M_PI / 4.0);
    gainL_ = static_cast<float>(std::cos(theta) * std::sqrt(2.0));
    gainR_ = static_cast<float>(std::sin(theta) * std::sqrt(2.0));

    for (int i = 0; i < frames; ++i) {
        float l = L[i];
        float r = R[i];

        if (mono_) {
            float monoSample = 0.5f * (l + r);
            l = monoSample;
            r = monoSample;
        }

        L[i] = l * gainL_;
        R[i] = r * gainR_;
    }
}

void SpatialPanner::processInterleaved(float* buffer, int frames, int channels) {
    if (!buffer || frames <= 0) return;

    if (channels == 1) {
        // Mono channel
        for (int i = 0; i < frames; ++i) {
            buffer[i] *= 1.0f;
        }
        return;
    }

    const double smoothFactor = 0.05;
    smoothedBalance_ += smoothFactor * (targetBalance_ - smoothedBalance_);

    const double theta = (smoothedBalance_ + 1.0) * (M_PI / 4.0);
    gainL_ = static_cast<float>(std::cos(theta) * std::sqrt(2.0));
    gainR_ = static_cast<float>(std::sin(theta) * std::sqrt(2.0));

    // Process pairwise channels (0/1, 2/3, etc.)
    for (int i = 0; i < frames; ++i) {
        for (int ch = 0; ch < channels - 1; ch += 2) {
            float l = buffer[i * channels + ch];
            float r = buffer[i * channels + ch + 1];

            if (mono_) {
                float monoSample = 0.5f * (l + r);
                l = monoSample;
                r = monoSample;
            }

            buffer[i * channels + ch] = l * gainL_;
            buffer[i * channels + ch + 1] = r * gainR_;
        }
    }
}
