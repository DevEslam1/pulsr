#include "ConvolutionReverb.h"
#include <cstring>
#include <random>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

ConvolutionReverb::ConvolutionReverb() {
    setSampleRate(48000.0);
    setPreset(ReverbPreset::StudioRoom);
    reset();
}

void ConvolutionReverb::setSampleRate(double sampleRate) {
    if (sampleRate < 8000.0) sampleRate = 8000.0;
    if (sampleRate > 768000.0) sampleRate = 768000.0;
    sampleRate_ = sampleRate;
    generatePresetIR(currentPreset_);
}

void ConvolutionReverb::setPreset(ReverbPreset preset) {
    currentPreset_ = preset;
    generatePresetIR(preset);
}

void ConvolutionReverb::loadCustomIR(const float* irSamples, int sampleCount) {
    if (!irSamples || sampleCount <= 0) return;
    int maxLen = static_cast<int>(sampleRate_ * 3.0); // max 3 seconds
    irLength_ = std::min(sampleCount, maxLen);
    irL_.resize(irLength_);
    irR_.resize(irLength_);

    float maxVal = 0.0001f;
    for (int i = 0; i < irLength_; ++i) {
        irL_[i] = irSamples[i];
        irR_[i] = irSamples[i];
        maxVal = std::max(maxVal, std::abs(irSamples[i]));
    }
    // Normalize IR energy
    for (int i = 0; i < irLength_; ++i) {
        irL_[i] /= maxVal;
        irR_[i] /= maxVal;
    }

    historyL_.assign(irLength_, 0.0f);
    historyR_.assign(irLength_, 0.0f);
    historyIdx_ = 0;
    currentPreset_ = ReverbPreset::Custom;
}

void ConvolutionReverb::setWetDry(float wetRatio) {
    wetRatio_ = std::max(0.0f, std::min(wetRatio, 1.0f));
}

void ConvolutionReverb::setEnabled(bool enabled) {
    enabled_ = enabled;
}

void ConvolutionReverb::reset() {
    std::fill(historyL_.begin(), historyL_.end(), 0.0f);
    std::fill(historyR_.begin(), historyR_.end(), 0.0f);
    historyIdx_ = 0;
}

void ConvolutionReverb::generatePresetIR(ReverbPreset preset) {
    double decaySec = 0.5;
    double damping = 0.3;
    switch (preset) {
        case ReverbPreset::StudioRoom:
            decaySec = 0.35;
            damping = 0.4;
            break;
        case ReverbPreset::ConcertHall:
            decaySec = 2.0;
            damping = 0.15;
            break;
        case ReverbPreset::WarmTube:
            decaySec = 0.9;
            damping = 0.5;
            break;
        case ReverbPreset::PlateReverb:
            decaySec = 1.4;
            damping = 0.2;
            break;
        case ReverbPreset::Custom:
            return;
    }

    // Downsample convolution taps to keep real-time performance lightning fast
    int tapCount = static_cast<int>(sampleRate_ * decaySec * 0.25);
    tapCount = std::max(256, std::min(tapCount, 4096));
    irLength_ = tapCount;
    irL_.resize(irLength_);
    irR_.resize(irLength_);

    std::mt19937 rng(1337);
    std::uniform_real_distribution<float> dist(-1.0f, 1.0f);

    double decayFactor = -6.91 / (decaySec * sampleRate_ * 0.25); // -60dB at decaySec
    for (int i = 0; i < irLength_; ++i) {
        float env = static_cast<float>(std::exp(decayFactor * i));
        // High frequency damping
        float lowpass = static_cast<float>(1.0 - damping * (static_cast<double>(i) / irLength_));
        irL_[i] = dist(rng) * env * lowpass;
        irR_[i] = dist(rng) * env * lowpass;
    }

    // Early reflections boost
    int earlyEnd = std::min(64, irLength_ / 4);
    for (int i = 0; i < earlyEnd; ++i) {
        if (i % 8 == 0) {
            irL_[i] += 0.8f * (1.0f - static_cast<float>(i) / earlyEnd);
            irR_[i] += 0.8f * (1.0f - static_cast<float>(i) / earlyEnd);
        }
    }

    // Normalize
    float sumSqL = 0.0f, sumSqR = 0.0f;
    for (int i = 0; i < irLength_; ++i) {
        sumSqL += irL_[i] * irL_[i];
        sumSqR += irR_[i] * irR_[i];
    }
    float normL = std::sqrt(sumSqL);
    float normR = std::sqrt(sumSqR);
    if (normL > 0.0001f) {
        for (int i = 0; i < irLength_; ++i) irL_[i] = (irL_[i] / normL) * 0.4f;
    }
    if (normR > 0.0001f) {
        for (int i = 0; i < irLength_; ++i) irR_[i] = (irR_[i] / normR) * 0.4f;
    }

    historyL_.assign(irLength_, 0.0f);
    historyR_.assign(irLength_, 0.0f);
    historyIdx_ = 0;
}

void ConvolutionReverb::process(float* L, float* R, int frames) {
    if (!enabled_ || !L || !R || frames <= 0 || irLength_ <= 0 || wetRatio_ <= 0.001f) return;

    const int step = qualityStep_;
    float dryGain = 1.0f - wetRatio_ * 0.5f;
    float wetGain = wetRatio_ * std::sqrt(static_cast<float>(step));

    for (int f = 0; f < frames; ++f) {
        float inL = L[f];
        float inR = R[f];

        historyL_[historyIdx_] = inL;
        historyR_[historyIdx_] = inR;

        float convL = 0.0f;
        float convR = 0.0f;

        int hIdx = historyIdx_;
        for (int i = 0; i < irLength_; i += step) {
            convL += historyL_[hIdx] * irL_[i];
            convR += historyR_[hIdx] * irR_[i];
            hIdx -= step;
            if (hIdx < 0) hIdx += irLength_;
        }

        historyIdx_ = (historyIdx_ + 1) % irLength_;

        L[f] = inL * dryGain + convL * wetGain;
        R[f] = inR * dryGain + convR * wetGain;
    }
}

void ConvolutionReverb::processInterleaved(float* buffer, int frames) {
    if (!enabled_ || !buffer || frames <= 0 || irLength_ <= 0 || wetRatio_ <= 0.001f) return;

    const int step = qualityStep_;
    float dryGain = 1.0f - wetRatio_ * 0.5f;
    float wetGain = wetRatio_ * std::sqrt(static_cast<float>(step));

    for (int f = 0; f < frames; ++f) {
        float inL = buffer[f * 2];
        float inR = buffer[f * 2 + 1];

        historyL_[historyIdx_] = inL;
        historyR_[historyIdx_] = inR;

        float convL = 0.0f;
        float convR = 0.0f;

        int hIdx = historyIdx_;
        for (int i = 0; i < irLength_; i += step) {
            convL += historyL_[hIdx] * irL_[i];
            convR += historyR_[hIdx] * irR_[i];
            hIdx -= step;
            if (hIdx < 0) hIdx += irLength_;
        }

        historyIdx_ = (historyIdx_ + 1) % irLength_;

        buffer[f * 2] = inL * dryGain + convL * wetGain;
        buffer[f * 2 + 1] = inR * dryGain + convR * wetGain;
    }
}
