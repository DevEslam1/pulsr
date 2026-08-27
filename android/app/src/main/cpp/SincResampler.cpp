#include "SincResampler.h"
#include <cstring>

SincResampler::SincResampler() {
    historyL_.assign(TAPS, 0.0f);
    historyR_.assign(TAPS, 0.0f);
    setRates(44100.0, 48000.0);
    reset();
}

void SincResampler::setRates(double inRate, double outRate) {
    if (inRate < 8000.0) inRate = 8000.0;
    if (outRate < 8000.0) outRate = 8000.0;
    inRate_ = inRate;
    outRate_ = outRate;
    ratio_ = inRate_ / outRate_;
    reset();
}

void SincResampler::setEnabled(bool enabled) {
    enabled_ = enabled;
}

void SincResampler::reset() {
    std::fill(historyL_.begin(), historyL_.end(), 0.0f);
    std::fill(historyR_.begin(), historyR_.end(), 0.0f);
    phase_ = 0.0;
}

int SincResampler::getExpectedOutFrames(int inFrames) const {
    if (ratio_ <= 0.0) return inFrames;
    const int effectiveIn = inFrames - TAPS;
    if (effectiveIn <= 0) return 0;
    return static_cast<int>(std::ceil(effectiveIn / ratio_));
}

float SincResampler::sinc(float x) const {
    if (std::abs(x) < 1e-6f) return 1.0f;
    float px = static_cast<float>(M_PI) * x;
    return std::sin(px) / px;
}

float SincResampler::blackmanHarris(float x) const {
    // x in [-HALF_TAPS, HALF_TAPS] -> normalized t in [0, 1]
    float t = (x + HALF_TAPS) / static_cast<float>(TAPS);
    if (t < 0.0f || t > 1.0f) return 0.0f;
    constexpr float a0 = 0.35875f;
    constexpr float a1 = 0.48829f;
    constexpr float a2 = 0.14128f;
    constexpr float a3 = 0.01168f;
    float twoPiT = static_cast<float>(2.0 * M_PI * t);
    return a0 - a1 * std::cos(twoPiT) + a2 * std::cos(2.0f * twoPiT) - a3 * std::cos(3.0f * twoPiT);
}

int SincResampler::process(const float* inL, const float* inR, int inFrames,
                           float* outL, float* outR, int maxOutFrames) {
    if (!enabled_ || std::abs(inRate_ - outRate_) < 1.0) {
        int count = std::min(inFrames, maxOutFrames);
        if (inL && outL) std::memcpy(outL, inL, count * sizeof(float));
        if (inR && outR) std::memcpy(outR, inR, count * sizeof(float));
        return count;
    }

    // Append new input to history using pre-allocated buffers
    int histSize = static_cast<int>(historyL_.size());
    int needed = histSize + inFrames;
    if (needed > bufCapacity_) {
        bufCapacity_ = std::max(needed * 2, 4096);
        bufL_.resize(bufCapacity_, 0.0f);
        bufR_.resize(bufCapacity_, 0.0f);
    }

    std::memcpy(bufL_.data(), historyL_.data(), histSize * sizeof(float));
    std::memcpy(bufR_.data(), historyR_.data(), histSize * sizeof(float));
    if (inL) std::memcpy(bufL_.data() + histSize, inL, inFrames * sizeof(float));
    if (inR) std::memcpy(bufR_.data() + histSize, inR, inFrames * sizeof(float));

    int outCount = 0;
    double currentInPos = phase_;
    double cutoff = (ratio_ > 1.0) ? (1.0 / ratio_) : 1.0; // Anti-aliasing cutoff for downsampling

    while (outCount < maxOutFrames) {
        int centerIdx = histSize + static_cast<int>(std::floor(currentInPos));
        if (centerIdx + HALF_TAPS >= needed) {
            break; // Need more input
        }

        double frac = currentInPos - std::floor(currentInPos);
        float sumL = 0.0f;
        float sumR = 0.0f;
        float weightSum = 0.0f;

        for (int tap = -HALF_TAPS; tap < HALF_TAPS; ++tap) {
            float dist = static_cast<float>(tap - frac);
            float w = blackmanHarris(dist) * sinc(static_cast<float>(dist * cutoff));
            int sampleIdx = centerIdx + tap;
            if (sampleIdx >= 0 && sampleIdx < needed) {
                sumL += bufL_[sampleIdx] * w;
                sumR += bufR_[sampleIdx] * w;
                weightSum += w;
            }
        }

        float norm = (std::abs(weightSum) > 1e-5f) ? (1.0f / weightSum) : 1.0f;
        outL[outCount] = sumL * norm;
        outR[outCount] = sumR * norm;
        outCount++;

        currentInPos += ratio_;
    }

    // Save remainder for next block
    int consumedInSamples = static_cast<int>(std::floor(currentInPos));
    phase_ = currentInPos - consumedInSamples;

    int remaining = inFrames - consumedInSamples;
    if (remaining < 0) remaining = 0;

    // Shift last TAPS samples into history
    int startIdx = needed - TAPS;
    if (startIdx >= 0) {
        std::memcpy(historyL_.data(), bufL_.data() + startIdx, TAPS * sizeof(float));
        std::memcpy(historyR_.data(), bufR_.data() + startIdx, TAPS * sizeof(float));
    }

    // Shrink capacity if needed drops significantly below allocated capacity
    if (bufCapacity_ > 8192 && needed < bufCapacity_ / 4) {
        bufCapacity_ = std::max(needed * 2, 4096);
        bufL_.resize(bufCapacity_, 0.0f);
        bufR_.resize(bufCapacity_, 0.0f);
        bufL_.shrink_to_fit();
        bufR_.shrink_to_fit();
    }

    return outCount;
}

int SincResampler::processInterleaved(const float* in, int inFrames,
                                     float* out, int maxOutFrames) {
    if (!in || !out || inFrames <= 0 || maxOutFrames <= 0) return 0;

    if (!enabled_ || std::abs(inRate_ - outRate_) < 1.0) {
        int count = std::min(inFrames, maxOutFrames);
        if (in != out) {
            std::memcpy(out, in, count * 2 * sizeof(float));
        }
        return count;
    }

    if (static_cast<int>(inL_.size()) < inFrames) {
        inL_.resize(inFrames * 2);
        inR_.resize(inFrames * 2);
    }
    if (static_cast<int>(outL_.size()) < maxOutFrames) {
        outL_.resize(maxOutFrames * 2);
        outR_.resize(maxOutFrames * 2);
    }

    for (int i = 0; i < inFrames; ++i) {
        inL_[i] = in[i * 2];
        inR_[i] = in[i * 2 + 1];
    }

    int outFrames = process(inL_.data(), inR_.data(), inFrames, outL_.data(), outR_.data(), maxOutFrames);
    for (int i = 0; i < outFrames; ++i) {
        out[i * 2] = outL_[i];
        out[i * 2 + 1] = outR_[i];
    }
    return outFrames;
}
