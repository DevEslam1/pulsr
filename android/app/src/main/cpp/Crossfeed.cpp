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
    const CrossfeedMode previousMode = mode_;
    const bool liveWet = enabled_ && smoothedEnabledMix_ > 1e-4f;
    bool crossfadeStarted = false;
    if (liveWet && mode != previousMode) {
        crossfadeStarted = true;
        prevCustomDelaySamples_ = smoothedDelaySamples_;
        prevCustomFeedLevel_ = smoothedFeedLevel_;
        prevCustomLpCoeff_ = smoothedLpCoeff_;
        // Snapshot the old BS2B coefficients/states so the old and new modes
        // can run concurrently for the 15 ms output crossfade below.
        prevMode_ = previousMode;
        prevBs2bA0Lo_ = bs2b_a0_lo_;
        prevBs2bB1Lo_ = bs2b_b1_lo_;
        prevBs2bA0Hi_ = bs2b_a0_hi_;
        prevBs2bA1Hi_ = bs2b_a1_hi_;
        prevBs2bB1Hi_ = bs2b_b1_hi_;
        prevBs2bGain_ = bs2b_gain_;
        prevBs2bLo_[0] = bs2b_lo_[0];
        prevBs2bLo_[1] = bs2b_lo_[1];
        prevBs2bHi_[0] = bs2b_hi_[0];
        prevBs2bHi_[1] = bs2b_hi_[1];
        prevBs2bAsis_[0] = bs2b_asis_[0];
        prevBs2bAsis_[1] = bs2b_asis_[1];
        modeCrossfadeTotal_ = std::max(1, static_cast<int>(sampleRate_ * 0.015));
        modeCrossfadeSamples_ = 0;
    } else if (mode == previousMode || !liveWet) {
        modeCrossfadeTotal_ = 0;
        modeCrossfadeSamples_ = 0;
    }
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
        default:
            // Out-of-range mode: fall back to the default preset rather than
            // silently reusing whatever stale fcut_/feedDb_/delayUs_ were set.
            mode_ = CrossfeedMode::Bs2bDefault;
            fcut_ = 700.0;
            feedDb_ = -4.5;
            delayUs_ = 300.0;
            break;
    }
    initBs2b(fcut_, feedDb_);
    configure(delayUs_, feedDb_, fcut_);
    if (mode_ != CrossfeedMode::Custom && previousMode == CrossfeedMode::Custom) {
        // Entering BS2B from Custom: the BS2B registers are stale from an
        // earlier session (they were not ticked during Custom). Start clean.
        bs2b_lo_[0] = bs2b_lo_[1] = 0.0;
        bs2b_hi_[0] = bs2b_hi_[1] = 0.0;
        bs2b_asis_[0] = bs2b_asis_[1] = 0.0;
    }

    // The Custom delay line is only written while in Custom mode, so switching
    // into Custom would otherwise read stale samples from a previous Custom run
    // (or zeros/garbage) until the line refills. Clear it on any mode change.
    // When leaving Custom mid-crossfade the old custom path is still running,
    // so keep its state until the fade completes.
    if (mode_ != previousMode && (mode_ == CrossfeedMode::Custom || !crossfadeStarted)) {
        clearCustomState();
    }
}

void Crossfeed::clearCustomState() {
    std::memset(delayBufferL_, 0, sizeof(delayBufferL_));
    std::memset(delayBufferR_, 0, sizeof(delayBufferR_));
    writeIdx_ = 0;
    lpL_ = 0.0f;
    lpR_ = 0.0f;
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
    const CrossfeedMode requested = static_cast<CrossfeedMode>(params.mode);
    if (requested == CrossfeedMode::Custom) {
        const CrossfeedMode previousMode = mode_;
        mode_ = CrossfeedMode::Custom;
        configure(params.delayUs, params.feedDb, params.fcut);
        // Entering Custom from a preset leaves the delay line holding stale
        // audio; clear it just like setMode() does for a preset transition.
        if (mode_ != previousMode) clearCustomState();
    } else {
        // Let setMode() observe the old mode so a preset change still resets
        // the BS2B/custom state. Assigning mode_ before the call prevented it.
        setMode(requested);
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
    modeCrossfadeSamples_ = 0;
    modeCrossfadeTotal_ = 0;

    bs2b_lo_[0] = 0.0; bs2b_lo_[1] = 0.0;
    bs2b_hi_[0] = 0.0; bs2b_hi_[1] = 0.0;
    bs2b_asis_[0] = 0.0; bs2b_asis_[1] = 0.0;
}

inline void Crossfeed::processBs2bFrameWith(
        float inL, float inR, float& outL, float& outR,
        double a0Lo, double b1Lo, double a0Hi, double a1Hi, double b1Hi,
        double gain, double lo[2], double hi[2], double asis[2]) {
    double dInL = inL;
    double dInR = inR;
    if (!std::isfinite(dInL)) dInL = 0.0;
    if (!std::isfinite(dInR)) dInR = 0.0;

    lo[0] = a0Lo * dInL + b1Lo * lo[0];
    lo[1] = a0Lo * dInR + b1Lo * lo[1];

    hi[0] = a0Hi * dInL + a1Hi * asis[0] + b1Hi * hi[0];
    hi[1] = a0Hi * dInR + a1Hi * asis[1] + b1Hi * hi[1];
    asis[0] = dInL;
    asis[1] = dInR;

    if (std::abs(lo[0]) < 1e-30) lo[0] = 0.0;
    if (std::abs(lo[1]) < 1e-30) lo[1] = 0.0;
    if (std::abs(hi[0]) < 1e-30) hi[0] = 0.0;
    if (std::abs(hi[1]) < 1e-30) hi[1] = 0.0;

    outL = static_cast<float>((hi[0] + lo[1]) * gain);
    outR = static_cast<float>((hi[1] + lo[0]) * gain);
}

inline void Crossfeed::processBs2bFrame(float inL, float inR, float& outL, float& outR) {
    processBs2bFrameWith(inL, inR, outL, outR,
                         bs2b_a0_lo_, bs2b_b1_lo_,
                         bs2b_a0_hi_, bs2b_a1_hi_, bs2b_b1_hi_,
                         bs2b_gain_, bs2b_lo_, bs2b_hi_, bs2b_asis_);
}

inline void Crossfeed::processCustomFrame(float l, float r, float& outL, float& outR,
                                         float currentDelay, float feedLevel, float lpCoeff, float makeup) {
    if (!std::isfinite(l)) l = 0.0f;
    if (!std::isfinite(r)) r = 0.0f;

    lpL_ += lpCoeff * (l - lpL_);
    lpR_ += lpCoeff * (r - lpR_);

    if (!std::isfinite(lpL_)) lpL_ = 0.0f;
    if (!std::isfinite(lpR_)) lpR_ = 0.0f;
    if (std::abs(lpL_) < 1e-25f) lpL_ = 0.0f;
    if (std::abs(lpR_) < 1e-25f) lpR_ = 0.0f;

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

    outL = (l + delayedR * feedLevel) * makeup;
    outR = (r + delayedL * feedLevel) * makeup;
}

inline void Crossfeed::processMixedFrame(float inL, float inR, float& outL,
                                         float& outR, float currentMix,
                                         float currentDelay) {
    float wetL = 0.0f;
    float wetR = 0.0f;
    if (modeCrossfadeTotal_ > 0 && modeCrossfadeSamples_ < modeCrossfadeTotal_) {
        float newL = 0.0f, newR = 0.0f;
        float oldL = 0.0f, oldR = 0.0f;
        if (mode_ == CrossfeedMode::Custom) {
            const float feed = smoothedFeedLevel_;
            processCustomFrame(inL, inR, newL, newR, currentDelay, feed,
                               smoothedLpCoeff_, 1.0f / (1.0f + feed));
        } else {
            processBs2bFrame(inL, inR, newL, newR);
        }
        if (prevMode_ == CrossfeedMode::Custom) {
            const float feed = prevCustomFeedLevel_;
            processCustomFrame(inL, inR, oldL, oldR, prevCustomDelaySamples_,
                               feed, prevCustomLpCoeff_, 1.0f / (1.0f + feed));
        } else {
            processBs2bFrameWith(inL, inR, oldL, oldR,
                                 prevBs2bA0Lo_, prevBs2bB1Lo_,
                                 prevBs2bA0Hi_, prevBs2bA1Hi_, prevBs2bB1Hi_,
                                 prevBs2bGain_, prevBs2bLo_, prevBs2bHi_,
                                 prevBs2bAsis_);
        }
        const float progress = static_cast<float>(modeCrossfadeSamples_) /
                               static_cast<float>(modeCrossfadeTotal_);
        const float oldW =
            0.5f * (1.0f + std::cos(static_cast<float>(M_PI) * progress));
        wetL = oldW * oldL + (1.0f - oldW) * newL;
        wetR = oldW * oldR + (1.0f - oldW) * newR;
        ++modeCrossfadeSamples_;
        if (modeCrossfadeSamples_ >= modeCrossfadeTotal_) {
            modeCrossfadeTotal_ = 0;
            if (mode_ != CrossfeedMode::Custom) {
                clearCustomState();
            }
        }
    } else if (mode_ == CrossfeedMode::Custom) {
        const float feed = smoothedFeedLevel_;
        processCustomFrame(inL, inR, wetL, wetR, currentDelay, feed,
                           smoothedLpCoeff_, 1.0f / (1.0f + feed));
    } else {
        processBs2bFrame(inL, inR, wetL, wetR);
    }
    outL = (1.0f - currentMix) * inL + currentMix * wetL;
    outR = (1.0f - currentMix) * inR + currentMix * wetR;
}

void Crossfeed::process(float* L, float* R, int frames) {
    const float targetMix = enabled_ ? 1.0f : 0.0f;
    if (!enabled_ && smoothedEnabledMix_ < 1e-4f) {
        modeCrossfadeTotal_ = 0;
        modeCrossfadeSamples_ = 0;
        return;
    }
    if (!L || !R || frames <= 0) return;

    constexpr double kTau = 0.015;
    const double smoothFactor = 1.0 - std::exp(-static_cast<double>(frames) / (sampleRate_ * kTau));
    const float startMix = smoothedEnabledMix_;
    smoothedEnabledMix_ += static_cast<float>(smoothFactor) * (targetMix - smoothedEnabledMix_);
    if (std::abs(smoothedEnabledMix_ - targetMix) < 1e-4f) {
        smoothedEnabledMix_ = targetMix;
    }
    const float mixStep = (smoothedEnabledMix_ - startMix) / static_cast<float>(frames);
    float currentMix = startMix;

    // Custom parameters are smoothed unconditionally so a mode switch into
    // Custom never begins with a parameter step.
    smoothedFeedLevel_ += static_cast<float>(smoothFactor) * (targetFeedLevel_ - smoothedFeedLevel_);
    if (std::abs(smoothedFeedLevel_ - targetFeedLevel_) < 1e-5f) {
        smoothedFeedLevel_ = targetFeedLevel_;
    }
    smoothedLpCoeff_ += static_cast<float>(smoothFactor) * (targetLpCoeff_ - smoothedLpCoeff_);
    if (std::abs(smoothedLpCoeff_ - targetLpCoeff_) < 1e-5f) {
        smoothedLpCoeff_ = targetLpCoeff_;
    }

    const float startDelay = smoothedDelaySamples_;
    smoothedDelaySamples_ += static_cast<float>(smoothFactor) * (targetDelaySamples_ - smoothedDelaySamples_);
    if (std::abs(smoothedDelaySamples_ - targetDelaySamples_) < 1e-5f) {
        smoothedDelaySamples_ = targetDelaySamples_;
    }
    const float delayStep = (smoothedDelaySamples_ - startDelay) / static_cast<float>(frames);
    float currentDelay = startDelay;

    for (int i = 0; i < frames; ++i) {
        float outL = 0.0f, outR = 0.0f;
        currentDelay += delayStep;
        processMixedFrame(L[i], R[i], outL, outR, currentMix, currentDelay);
        L[i] = outL;
        R[i] = outR;
        currentMix += mixStep;
    }
}

void Crossfeed::processInterleaved(float* buffer, int frames, int channels) {
    const float targetMix = enabled_ ? 1.0f : 0.0f;
    if (!enabled_ && smoothedEnabledMix_ < 1e-4f) {
        modeCrossfadeTotal_ = 0;
        modeCrossfadeSamples_ = 0;
        return;
    }
    if (!buffer || frames <= 0 || channels < 2) return;

    constexpr double kTau = 0.015;
    const double smoothFactor = 1.0 - std::exp(-static_cast<double>(frames) / (sampleRate_ * kTau));
    const float startMix = smoothedEnabledMix_;
    smoothedEnabledMix_ += static_cast<float>(smoothFactor) * (targetMix - smoothedEnabledMix_);
    if (std::abs(smoothedEnabledMix_ - targetMix) < 1e-4f) {
        smoothedEnabledMix_ = targetMix;
    }
    const float mixStep = (smoothedEnabledMix_ - startMix) / static_cast<float>(frames);
    float currentMix = startMix;

    smoothedFeedLevel_ += static_cast<float>(smoothFactor) * (targetFeedLevel_ - smoothedFeedLevel_);
    if (std::abs(smoothedFeedLevel_ - targetFeedLevel_) < 1e-5f) {
        smoothedFeedLevel_ = targetFeedLevel_;
    }
    smoothedLpCoeff_ += static_cast<float>(smoothFactor) * (targetLpCoeff_ - smoothedLpCoeff_);
    if (std::abs(smoothedLpCoeff_ - targetLpCoeff_) < 1e-5f) {
        smoothedLpCoeff_ = targetLpCoeff_;
    }

    const float startDelay = smoothedDelaySamples_;
    smoothedDelaySamples_ += static_cast<float>(smoothFactor) * (targetDelaySamples_ - smoothedDelaySamples_);
    if (std::abs(smoothedDelaySamples_ - targetDelaySamples_) < 1e-5f) {
        smoothedDelaySamples_ = targetDelaySamples_;
    }
    const float delayStep = (smoothedDelaySamples_ - startDelay) / static_cast<float>(frames);
    float currentDelay = startDelay;

    for (int i = 0; i < frames; ++i) {
        const int idx = i * channels;
        float outL = 0.0f, outR = 0.0f;
        currentDelay += delayStep;
        processMixedFrame(buffer[idx], buffer[idx + 1], outL, outR,
                          currentMix, currentDelay);
        buffer[idx] = outL;
        buffer[idx + 1] = outR;
        currentMix += mixStep;
    }
}
