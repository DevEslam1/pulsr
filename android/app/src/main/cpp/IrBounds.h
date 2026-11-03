// Impulse-response shape/budget helpers, kept header-only so the native test
// suite can verify them without the JNI bridge.
#pragma once

#include <algorithm>
#include <cstdint>
#include <vector>

namespace pulsr {

constexpr int kMaxIrSeconds = 10;

inline bool ValidateIrShape(int64_t sampleCount, int channels) {
    return sampleCount > 0 && channels >= 1 && channels <= 8 &&
           (sampleCount % channels) == 0;
}

/**
 * Truncates an interleaved IR to `maxFrames` per channel and applies a short
 * fade-out to the cut so a hard truncation cannot click.
 * Returns the resulting frame count.
 */
inline int TruncateIrWithFade(std::vector<float>& ir, int channels,
                              int maxFrames, int fadeFrames) {
    if (channels <= 0 || maxFrames <= 0) return 0;
    const int64_t currentSamples = static_cast<int64_t>(ir.size());
    const int currentFrames = static_cast<int>(currentSamples / channels);
    if (currentFrames <= maxFrames) return currentFrames;

    ir.resize(static_cast<size_t>(maxFrames) * channels);
    const int fade = std::clamp(fadeFrames, 1, maxFrames);
    const int fadeStart = maxFrames - fade;
    for (int f = fadeStart; f < maxFrames; ++f) {
        const float gain = static_cast<float>(maxFrames - f) /
                           static_cast<float>(fade + 1);
        for (int ch = 0; ch < channels; ++ch) {
            ir[static_cast<size_t>(f) * channels + ch] *= gain;
        }
    }
    return maxFrames;
}

}  // namespace pulsr
