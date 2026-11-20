// android/app/src/main/cpp/LfeCrossover.cpp
#include "LfeCrossover.h"

LfeCrossover::LfeCrossover() {
    sampleRate_ = 48000.0;
    crossoverHz_ = pulsr::dsp::ranges::kLfeCrossoverHz.fallback;
    lfeLowPassHz_ = pulsr::dsp::ranges::kLfeLowPassHz.fallback;
    slopeDbPerOct_ = 24.0;
    cascade_ = true;
    lfeGainDb_ = pulsr::dsp::ranges::kLfeGainDb.fallback;
    targetLfeGainLinear_ = 1.0;
    smoothedLfeGainLinear_ = 1.0;
    lfeChannelIndex_ = 3;
    redirectBass_ = true;
    enabled_ = false;
    smoothedEnabledMix_ = 0.0;
    computeCoeffs();
    reset();
}

void LfeCrossover::setSampleRate(double sampleRate) {
    double sr = (std::isfinite(sampleRate) && sampleRate > 0.0) ? sampleRate : 48000.0;
    sr = std::clamp(sr, 8000.0, 768000.0);
    if (std::abs(sampleRate_ - sr) < 0.5) return;
    sampleRate_ = sr;
    computeCoeffs();
    reset();
}

void LfeCrossover::configure(double crossoverHz,
                             double lfeLowPassHz,
                             double slopeDbPerOct,
                             double lfeGainDb,
                             int lfeChannelIndex,
                             bool redirectBass) {
    const double newCrossover = pulsr::dsp::ranges::kLfeCrossoverHz.clamp(crossoverHz);
    const double newLfeLp = pulsr::dsp::ranges::kLfeLowPassHz.clamp(lfeLowPassHz);
    const bool newCascade = !std::isfinite(slopeDbPerOct) || slopeDbPerOct >= 18.0;
    const double newGainDb = pulsr::dsp::ranges::kLfeGainDb.clamp(lfeGainDb);
    const int newLfeCh = std::clamp(lfeChannelIndex, 0, MAX_CHANNELS - 1);

    const bool coeffChanged =
        std::abs(newCrossover - crossoverHz_) > 0.01 ||
        std::abs(newLfeLp - lfeLowPassHz_) > 0.01 ||
        newCascade != cascade_;
    const bool redirectChanged = (redirectBass != redirectBass_);
    const bool lfeChChanged = (newLfeCh != lfeChannelIndex_);

    crossoverHz_ = newCrossover;
    lfeLowPassHz_ = newLfeLp;
    cascade_ = newCascade;
    slopeDbPerOct_ = newCascade ? 24.0 : 12.0;
    lfeGainDb_ = newGainDb;
    targetLfeGainLinear_ = std::pow(10.0, newGainDb / 20.0);
    lfeChannelIndex_ = newLfeCh;
    redirectBass_ = redirectBass;

    if (coeffChanged) {
        computeCoeffs();
        if (!newCascade) {
            for (int ch = 0; ch < MAX_CHANNELS; ++ch) {
                satHp2_[ch].clearState();
            }
            redirectLp2_.clearState();
            lfeLp2_.clearState();
        }
    }
    if (redirectChanged || lfeChChanged) {
        for (int ch = 0; ch < MAX_CHANNELS; ++ch) {
            satHp1_[ch].clearState();
            satHp2_[ch].clearState();
        }
        redirectLp1_.clearState();
        redirectLp2_.clearState();
        lfeLp1_.clearState();
        lfeLp2_.clearState();
    }
}

void LfeCrossover::applyParams(const LfeCrossoverParamSet& params) {
    enabled_ = params.enabled;
    configure(params.crossoverHz,
              params.lfeLowPassHz,
              params.slopeDbPerOct,
              params.lfeGainDb,
              params.lfeChannelIndex,
              params.redirectBass);
}

void LfeCrossover::makeLowPass(double fc, double sampleRate, double q, BiquadStage& out) {
    const double clampedFc = std::clamp(fc, 20.0, sampleRate * 0.45);
    const double w0 = 2.0 * M_PI * clampedFc / sampleRate;
    const double cosw0 = std::cos(w0);
    const double sinw0 = std::sin(w0);
    const double alpha = sinw0 / (2.0 * q);
    const double a0 = 1.0 + alpha;

    out.b0 = ((1.0 - cosw0) * 0.5) / a0;
    out.b1 = (1.0 - cosw0) / a0;
    out.b2 = ((1.0 - cosw0) * 0.5) / a0;
    out.a1 = (-2.0 * cosw0) / a0;
    out.a2 = (1.0 - alpha) / a0;
}

void LfeCrossover::makeHighPass(double fc, double sampleRate, double q, BiquadStage& out) {
    const double clampedFc = std::clamp(fc, 20.0, sampleRate * 0.45);
    const double w0 = 2.0 * M_PI * clampedFc / sampleRate;
    const double cosw0 = std::cos(w0);
    const double sinw0 = std::sin(w0);
    const double alpha = sinw0 / (2.0 * q);
    const double a0 = 1.0 + alpha;

    out.b0 = ((1.0 + cosw0) * 0.5) / a0;
    out.b1 = -(1.0 + cosw0) / a0;
    out.b2 = ((1.0 + cosw0) * 0.5) / a0;
    out.a1 = (-2.0 * cosw0) / a0;
    out.a2 = (1.0 - alpha) / a0;
}

void LfeCrossover::computeCoeffs() {
    // LR4 (24 dB/oct) cascades two Butterworth (Q = 1/sqrt(2)) sections.
    // LR2 (12 dB/oct) uses a single critically damped (Q = 0.5) section.
    const double q = cascade_ ? 0.7071067811865475 : 0.5;

    BiquadStage hpTemplate;
    makeHighPass(crossoverHz_, sampleRate_, q, hpTemplate);
    for (int ch = 0; ch < MAX_CHANNELS; ++ch) {
        satHp1_[ch].b0 = hpTemplate.b0;
        satHp1_[ch].b1 = hpTemplate.b1;
        satHp1_[ch].b2 = hpTemplate.b2;
        satHp1_[ch].a1 = hpTemplate.a1;
        satHp1_[ch].a2 = hpTemplate.a2;

        satHp2_[ch].b0 = hpTemplate.b0;
        satHp2_[ch].b1 = hpTemplate.b1;
        satHp2_[ch].b2 = hpTemplate.b2;
        satHp2_[ch].a1 = hpTemplate.a1;
        satHp2_[ch].a2 = hpTemplate.a2;
    }

    BiquadStage redirTemplate;
    makeLowPass(crossoverHz_, sampleRate_, q, redirTemplate);
    redirectLp1_.b0 = redirTemplate.b0;
    redirectLp1_.b1 = redirTemplate.b1;
    redirectLp1_.b2 = redirTemplate.b2;
    redirectLp1_.a1 = redirTemplate.a1;
    redirectLp1_.a2 = redirTemplate.a2;
    redirectLp2_.b0 = redirTemplate.b0;
    redirectLp2_.b1 = redirTemplate.b1;
    redirectLp2_.b2 = redirTemplate.b2;
    redirectLp2_.a1 = redirTemplate.a1;
    redirectLp2_.a2 = redirTemplate.a2;

    BiquadStage lfeTemplate;
    makeLowPass(lfeLowPassHz_, sampleRate_, q, lfeTemplate);
    lfeLp1_.b0 = lfeTemplate.b0;
    lfeLp1_.b1 = lfeTemplate.b1;
    lfeLp1_.b2 = lfeTemplate.b2;
    lfeLp1_.a1 = lfeTemplate.a1;
    lfeLp1_.a2 = lfeTemplate.a2;
    lfeLp2_.b0 = lfeTemplate.b0;
    lfeLp2_.b1 = lfeTemplate.b1;
    lfeLp2_.b2 = lfeTemplate.b2;
    lfeLp2_.a1 = lfeTemplate.a1;
    lfeLp2_.a2 = lfeTemplate.a2;
}

void LfeCrossover::reset() {
    smoothedLfeGainLinear_ = targetLfeGainLinear_;
    smoothedEnabledMix_ = enabled_ ? 1.0 : 0.0;
    for (int ch = 0; ch < MAX_CHANNELS; ++ch) {
        satHp1_[ch].clearState();
        satHp2_[ch].clearState();
    }
    redirectLp1_.clearState();
    redirectLp2_.clearState();
    lfeLp1_.clearState();
    lfeLp2_.clearState();
}

void LfeCrossover::processInterleaved(float* buffer, int frames, int channels) {
    if (!buffer || frames <= 0 || channels < MIN_MULTICHANNEL || channels > MAX_CHANNELS) {
        return;
    }
    if (lfeChannelIndex_ < 0 || lfeChannelIndex_ >= channels) {
        return;
    }

    const double targetMix = enabled_ ? 1.0 : 0.0;
    if (!enabled_ && smoothedEnabledMix_ < 1e-4) {
        return;
    }

    constexpr double kTau = 0.020;
    const double smoothFactor =
        1.0 - std::exp(-static_cast<double>(frames) / (sampleRate_ * kTau));

    const double startGain = smoothedLfeGainLinear_;
    smoothedLfeGainLinear_ += smoothFactor * (targetLfeGainLinear_ - startGain);
    if (std::abs(smoothedLfeGainLinear_ - targetLfeGainLinear_) < 1e-5) {
        smoothedLfeGainLinear_ = targetLfeGainLinear_;
    }
    const double gainStep = (smoothedLfeGainLinear_ - startGain) / static_cast<double>(frames);

    const double startMix = smoothedEnabledMix_;
    smoothedEnabledMix_ += smoothFactor * (targetMix - startMix);
    if (std::abs(smoothedEnabledMix_ - targetMix) < 5e-4) {
        smoothedEnabledMix_ = targetMix;
    }
    const double mixStep = (smoothedEnabledMix_ - startMix) / static_cast<double>(frames);

    const int lfeCh = lfeChannelIndex_;
    const int satCount = channels - 1;
    // Constant-sum, not equal-power: a coherent bass note present on every
    // satellite must arrive at one channel's level, not +10*log10(N-1) dB
    // (+7 dB at 5.1, +9 dB at 7.1). Uncorrelated bass is correspondingly
    // quieter; the LFE trim is the user's level control.
    const float satSumScale =
        (satCount > 0) ? (1.0f / static_cast<float>(satCount)) : 0.0f;
    // LR2 (12 dB/oct) has a 180-degree phase shift between LP and HP at fc;
    // invert the redirected bass sum so LP + HP sums flat rather than nulling.
    const float redirectPolarity = cascade_ ? 1.0f : -1.0f;
    const bool doRedirect = redirectBass_;
    const bool doCascade = cascade_;

    double curMix = startMix;
    double curGain = startGain;
    for (int f = 0; f < frames; ++f) {
        curMix += mixStep;
        curGain += gainStep;
        const float mixF = static_cast<float>(std::clamp(curMix, 0.0, 1.0));
        const float lfeGainF = static_cast<float>(curGain);
        const int base = f * channels;

        float satSum = 0.0f;
        if (doRedirect) {
            for (int ch = 0; ch < channels; ++ch) {
                if (ch == lfeCh) continue;
                float x = buffer[base + ch];
                if (!std::isfinite(x)) x = 0.0f;
                satSum += x;
                float hp = satHp1_[ch].process(x);
                if (doCascade) hp = satHp2_[ch].process(hp);
                buffer[base + ch] = x * (1.0f - mixF) + hp * mixF;
            }
        }

        float lfeIn = buffer[base + lfeCh];
        if (!std::isfinite(lfeIn)) lfeIn = 0.0f;
        float lfeFiltered = lfeLp1_.process(lfeIn);
        if (doCascade) lfeFiltered = lfeLp2_.process(lfeFiltered);

        float redirectedBass = 0.0f;
        if (doRedirect) {
            redirectedBass = redirectLp1_.process(satSum * satSumScale);
            if (doCascade) redirectedBass = redirectLp2_.process(redirectedBass);
            redirectedBass *= redirectPolarity;
        }

        const float lfeOut = (lfeFiltered + redirectedBass) * lfeGainF;
        buffer[base + lfeCh] = lfeIn * (1.0f - mixF) + lfeOut * mixF;
    }

    if (!enabled_ && smoothedEnabledMix_ < 1e-4) {
        reset();
    }
}
