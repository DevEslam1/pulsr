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
    updateCrossovers();
}

void StereoWidth::configure(double width) {
    targetWidth_ = std::clamp(width, 0.0, 2.0);
}

void StereoWidth::configureMultiband(bool multiband, double lowWidth, double midWidth, double highWidth,
                                    double lowCrossoverHz, double highCrossoverHz) {
    multiband_ = multiband;
    targetLowWidth_ = std::clamp(lowWidth, 0.0, 2.0);
    targetMidWidth_ = std::clamp(midWidth, 0.0, 2.0);
    targetHighWidth_ = std::clamp(highWidth, 0.0, 2.0);
    lowCrossoverHz_ = std::clamp(lowCrossoverHz, 40.0, 1000.0);
    highCrossoverHz_ = std::clamp(highCrossoverHz, lowCrossoverHz_ + 100.0, sampleRate_ * 0.45);
    updateCrossovers();
}

void StereoWidth::updateCrossovers() {
    crossoverLow_.configure(sampleRate_, lowCrossoverHz_);
    crossoverHigh_.configure(sampleRate_, highCrossoverHz_);
}

void StereoWidth::applyParams(const StereoWidthParamSet& params) {
    enabled_ = params.enabled;
    configure(params.width);
    configureMultiband(params.multiband, params.lowWidth, params.midWidth, params.highWidth,
                       params.lowCrossoverHz, params.highCrossoverHz);
}

void StereoWidth::reset() {
    smoothedWidth_ = targetWidth_;
    smoothedLowWidth_ = targetLowWidth_;
    smoothedMidWidth_ = targetMidWidth_;
    smoothedHighWidth_ = targetHighWidth_;
    crossoverLow_.reset();
    crossoverHigh_.reset();
}

void StereoWidth::process(float* L, float* R, int frames) {
    if (!enabled_ || !L || !R || frames <= 0) return;

    constexpr double kTau = 0.015;
    const double smoothFactor = 1.0 - std::exp(-static_cast<double>(frames) / (sampleRate_ * kTau));

    if (!multiband_) {
        // Broadband mode
        smoothedWidth_ += smoothFactor * (targetWidth_ - smoothedWidth_);
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
        return;
    }

    // 3-Band Multiband Stereo Imager with Bass Mono
    smoothedLowWidth_ += smoothFactor * (targetLowWidth_ - smoothedLowWidth_);
    smoothedMidWidth_ += smoothFactor * (targetMidWidth_ - smoothedMidWidth_);
    smoothedHighWidth_ += smoothFactor * (targetHighWidth_ - smoothedHighWidth_);

    const float wLow = static_cast<float>(smoothedLowWidth_);
    const float wMid = static_cast<float>(smoothedMidWidth_);
    const float wHigh = static_cast<float>(smoothedHighWidth_);

    for (int i = 0; i < frames; ++i) {
        const double inL = L[i];
        const double inR = R[i];

        // 1. Split low vs (mid+high)
        double lowL, lowR, midHighL, midHighR;
        crossoverLow_.process(inL, inR, lowL, lowR, midHighL, midHighR);

        // 2. Split mid vs high
        double midL, midR, highL, highR;
        crossoverHigh_.process(midHighL, midHighR, midL, midR, highL, highR);

        // 3. Process each band with its dedicated stereo width
        // Low band (defaults to mono when wLow == 0.0)
        const double mLow = 0.5 * (lowL + lowR);
        const double sLow = 0.5 * (lowL - lowR);
        const double outLowL = mLow + wLow * sLow;
        const double outLowR = mLow - wLow * sLow;

        // Mid band
        const double mMid = 0.5 * (midL + midR);
        const double sMid = 0.5 * (midL - midR);
        const double outMidL = mMid + wMid * sMid;
        const double outMidR = mMid - wMid * sMid;

        // High band
        const double mHigh = 0.5 * (highL + highR);
        const double sHigh = 0.5 * (highL - highR);
        const double outHighL = mHigh + wHigh * sHigh;
        const double outHighR = mHigh - wHigh * sHigh;

        // 4. Sum bands back together
        L[i] = static_cast<float>(outLowL + outMidL + outHighL);
        R[i] = static_cast<float>(outLowR + outMidR + outHighR);
    }
}

void StereoWidth::processInterleaved(float* buffer, int frames, int channels) {
    if (!enabled_ || !buffer || frames <= 0 || channels < 2) return;

    constexpr double kTau = 0.015;
    const double smoothFactor = 1.0 - std::exp(-static_cast<double>(frames) / (sampleRate_ * kTau));

    if (!multiband_) {
        // Broadband mode
        smoothedWidth_ += smoothFactor * (targetWidth_ - smoothedWidth_);
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
        return;
    }

    // 3-Band Multiband Stereo Imager with Bass Mono
    smoothedLowWidth_ += smoothFactor * (targetLowWidth_ - smoothedLowWidth_);
    smoothedMidWidth_ += smoothFactor * (targetMidWidth_ - smoothedMidWidth_);
    smoothedHighWidth_ += smoothFactor * (targetHighWidth_ - smoothedHighWidth_);

    const float wLow = static_cast<float>(smoothedLowWidth_);
    const float wMid = static_cast<float>(smoothedMidWidth_);
    const float wHigh = static_cast<float>(smoothedHighWidth_);

    for (int i = 0; i < frames; ++i) {
        for (int ch = 0; ch + 1 < channels; ch += 2) {
            const double inL = buffer[i * channels + ch];
            const double inR = buffer[i * channels + ch + 1];

            double lowL, lowR, midHighL, midHighR;
            crossoverLow_.process(inL, inR, lowL, lowR, midHighL, midHighR);

            double midL, midR, highL, highR;
            crossoverHigh_.process(midHighL, midHighR, midL, midR, highL, highR);

            const double mLow = 0.5 * (lowL + lowR);
            const double sLow = 0.5 * (lowL - lowR);
            const double outLowL = mLow + wLow * sLow;
            const double outLowR = mLow - wLow * sLow;

            const double mMid = 0.5 * (midL + midR);
            const double sMid = 0.5 * (midL - midR);
            const double outMidL = mMid + wMid * sMid;
            const double outMidR = mMid - wMid * sMid;

            const double mHigh = 0.5 * (highL + highR);
            const double sHigh = 0.5 * (highL - highR);
            const double outHighL = mHigh + wHigh * sHigh;
            const double outHighR = mHigh - wHigh * sHigh;

            buffer[i * channels + ch] = static_cast<float>(outLowL + outMidL + outHighL);
            buffer[i * channels + ch + 1] = static_cast<float>(outLowR + outMidR + outHighR);
        }
    }
}
