// android/app/src/main/cpp/HarmonicSaturation.h
#pragma once

#include "DspParams.h"
#include <cmath>
#include <algorithm>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

// Tube/tape-style harmonic exciter: tanh waveshaping with drive amount,
// wet/dry mix and a tape-like HF pre-emphasis (tilt) that feeds the shaper
// so high frequencies saturate first. The stage is pointwise (zero latency)
// and fully bypass-transparent when disabled.
class HarmonicSaturation {
public:
    static constexpr int MAX_CHANNELS = 8;

    HarmonicSaturation();

    void setSampleRate(double sampleRate);
    // drive: 0..1 (0 = linear/transparent), mix: 0..1 wet/dry,
    // tilt: 0..1 HF pre-emphasis amount into the shaper.
    void configure(double drive, double mix, double tilt);
    void setEnabled(bool enabled) { enabled_ = enabled; }
    bool isEnabled() const { return enabled_; }
    void applyParams(const SaturationParamSet& params);
    void reset();

    void process(float* L, float* R, int frames);
    void processInterleaved(float* buffer, int frames, int channels = 2);

    // Effective tanh sharpness (diagnostics/tests)
    double getDriveK() const { return k_; }

private:
    double sampleRate_ = 48000.0;
    double drive_ = 0.0;
    double mix_ = 0.5;
    double tilt_ = 0.0;
    double k_ = 0.0;        // tanh sharpness: drive * kMax
    float tiltHpCoeff_ = 0.0f; // one-pole HP coeff for pre-emphasis
    bool enabled_ = false;

    float hpState_[MAX_CHANNELS] = {};
};
