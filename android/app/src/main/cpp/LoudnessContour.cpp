// android/app/src/main/cpp/LoudnessContour.cpp
#include "LoudnessContour.h"
#include <cstring>

LoudnessContour::LoudnessContour() {
    setSampleRate(48000.0);
    configure(0.0, 1.0);
}

void LoudnessContour::setSampleRate(double sampleRate) {
    if (sampleRate < 8000.0) sampleRate = 8000.0;
    if (sampleRate > 768000.0) sampleRate = 768000.0;
    sampleRate_ = sampleRate;
    updateTargetGains();
    // Re-derive biquads from current (smoothed) gains at the new rate
    for (int ch = 0; ch < MAX_CHANNELS; ++ch) {
        computeLowShelf(bass_[ch], kBassShelfHz, currentBassDb_, sampleRate_);
        computeHighShelf(treble_[ch], kTrebleShelfHz, currentTrebleDb_, sampleRate_);
    }
}

void LoudnessContour::configure(double intensity, double volumeLinear) {
    intensity_ = std::clamp(intensity, 0.0, 1.0);
    volumeLinear_ = std::clamp(volumeLinear, 0.0, 1.0);
    updateTargetGains();
}

void LoudnessContour::applyParams(const LoudnessContourParamSet& params) {
    enabled_ = params.enabled;
    configure(params.intensity, params.volumeLinear);
}

void LoudnessContour::updateTargetGains() {
    // Equal-loudness approximation: lift grows as (1 - volume)^1.5 so the
    // contour is most active at low listening levels and vanishes at unity.
    const double loudnessWeight = std::pow(std::clamp(1.0 - volumeLinear_, 0.0, 1.0), 1.5);
    targetBassDb_ = intensity_ * kBassMaxDb * loudnessWeight;
    targetTrebleDb_ = intensity_ * kTrebleMaxDb * loudnessWeight;
}

void LoudnessContour::rampTowardTarget() {
    // ~50 ms gain smoothing (block-rate step, blocks are ~10 ms at 48000)
    constexpr double kSmooth = 0.18;
    const double bassStep = kSmooth * (targetBassDb_ - currentBassDb_);
    const double trebleStep = kSmooth * (targetTrebleDb_ - currentTrebleDb_);
    if (std::abs(bassStep) < 1e-4 && std::abs(trebleStep) < 1e-4) {
        currentBassDb_ = targetBassDb_;
        currentTrebleDb_ = targetTrebleDb_;
        return;
    }
    currentBassDb_ += bassStep;
    currentTrebleDb_ += trebleStep;
}

void LoudnessContour::reset() {
    std::memset(bass_, 0, sizeof(bass_));
    std::memset(treble_, 0, sizeof(treble_));
    currentBassDb_ = targetBassDb_;
    currentTrebleDb_ = targetTrebleDb_;
    for (int ch = 0; ch < MAX_CHANNELS; ++ch) {
        computeLowShelf(bass_[ch], kBassShelfHz, currentBassDb_, sampleRate_);
        computeHighShelf(treble_[ch], kTrebleShelfHz, currentTrebleDb_, sampleRate_);
    }
}

void LoudnessContour::computeLowShelf(Biquad& bq, double f0, double gainDb, double fs) {
    const double A = std::pow(10.0, gainDb / 40.0);
    const double w0 = 2.0 * M_PI * f0 / fs;
    const double cw = std::cos(w0), sw = std::sin(w0);
    const double alpha = sw / 2.0 * std::sqrt((A + 1.0 / A) * (1.0 / 0.85 - 1.0) + 2.0);
    const double twoSqrtA = 2.0 * std::sqrt(A) * alpha;
    const double a0 = (A + 1.0) + (A - 1.0) * cw + twoSqrtA;
    bq.b0 = A * ((A + 1.0) - (A - 1.0) * cw + twoSqrtA) / a0;
    bq.b1 = 2.0 * A * ((A - 1.0) - (A + 1.0) * cw) / a0;
    bq.b2 = A * ((A + 1.0) - (A - 1.0) * cw - twoSqrtA) / a0;
    bq.a1 = -2.0 * ((A - 1.0) + (A + 1.0) * cw) / a0;
    bq.a2 = ((A + 1.0) + (A - 1.0) * cw - twoSqrtA) / a0;
}

void LoudnessContour::computeHighShelf(Biquad& bq, double f0, double gainDb, double fs) {
    const double A = std::pow(10.0, gainDb / 40.0);
    const double w0 = 2.0 * M_PI * f0 / fs;
    const double cw = std::cos(w0), sw = std::sin(w0);
    const double alpha = sw / 2.0 * std::sqrt((A + 1.0 / A) * (1.0 / 0.85 - 1.0) + 2.0);
    const double twoSqrtA = 2.0 * std::sqrt(A) * alpha;
    const double a0 = (A + 1.0) - (A - 1.0) * cw + twoSqrtA;
    bq.b0 = A * ((A + 1.0) + (A - 1.0) * cw + twoSqrtA) / a0;
    bq.b1 = -2.0 * A * ((A - 1.0) + (A + 1.0) * cw) / a0;
    bq.b2 = A * ((A + 1.0) + (A - 1.0) * cw - twoSqrtA) / a0;
    bq.a1 = 2.0 * ((A - 1.0) - (A + 1.0) * cw) / a0;
    bq.a2 = ((A + 1.0) - (A - 1.0) * cw - twoSqrtA) / a0;
}

void LoudnessContour::process(float* L, float* R, int frames) {
    if (!enabled_ || !L || !R || frames <= 0) return;
    rampTowardTarget();
    if (std::abs(currentBassDb_) < 1e-6 && std::abs(currentTrebleDb_) < 1e-6) return;
    computeLowShelf(bass_[0], kBassShelfHz, currentBassDb_, sampleRate_);
    computeHighShelf(treble_[0], kTrebleShelfHz, currentTrebleDb_, sampleRate_);
    computeLowShelf(bass_[1], kBassShelfHz, currentBassDb_, sampleRate_);
    computeHighShelf(treble_[1], kTrebleShelfHz, currentTrebleDb_, sampleRate_);

    for (int i = 0; i < frames; ++i) {
        L[i] = bass_[0].process(treble_[0].process(L[i]));
        R[i] = bass_[1].process(treble_[1].process(R[i]));
    }
}

void LoudnessContour::processInterleaved(float* buffer, int frames, int channels) {
    if (!enabled_ || !buffer || frames <= 0 || channels <= 0) return;
    rampTowardTarget();
    if (std::abs(currentBassDb_) < 1e-6 && std::abs(currentTrebleDb_) < 1e-6) return;

    for (int ch = 0; ch < channels && ch < MAX_CHANNELS; ++ch) {
        computeLowShelf(bass_[ch], kBassShelfHz, currentBassDb_, sampleRate_);
        computeHighShelf(treble_[ch], kTrebleShelfHz, currentTrebleDb_, sampleRate_);
    }

    for (int i = 0; i < frames; ++i) {
        for (int ch = 0; ch < channels && ch < MAX_CHANNELS; ++ch) {
            buffer[i * channels + ch] = bass_[ch].process(treble_[ch].process(buffer[i * channels + ch]));
        }
    }
}
