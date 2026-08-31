// android/app/src/main/cpp/StereoWidth.cpp
#include "StereoWidth.h"

StereoWidth::StereoWidth() {
    configure(1.0);
}

void StereoWidth::configure(double width) {
    width_ = std::clamp(width, 0.0, 2.0);
}

void StereoWidth::applyParams(const StereoWidthParamSet& params) {
    enabled_ = params.enabled;
    configure(params.width);
}

void StereoWidth::reset() {
    // Stateless M/S matrix — nothing to clear.
}

void StereoWidth::process(float* L, float* R, int frames) {
    if (!enabled_ || !L || !R || frames <= 0) return;
    // Exact passthrough fast path at unity width.
    if (std::abs(width_ - 1.0) < 1e-9) return;

    const float w = static_cast<float>(width_);
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
    if (std::abs(width_ - 1.0) < 1e-9) return;

    const float w = static_cast<float>(width_);
    if (channels % 2 != 0) {
        // Odd channel count: process first 2 channels as stereo, pass remaining channels unchanged
        for (int i = 0; i < frames; ++i) {
            const float l = buffer[i * channels];
            const float r = buffer[i * channels + 1];
            const float mid = 0.5f * (l + r);
            const float side = 0.5f * (l - r);
            buffer[i * channels] = mid + w * side;
            buffer[i * channels + 1] = mid - w * side;
        }
        return;
    }

    // Process channel pairs (0/1, 2/3, …) so multichannel layouts keep
    // their stereo pairs coherent.
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
