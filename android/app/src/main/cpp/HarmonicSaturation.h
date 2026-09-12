// android/app/src/main/cpp/HarmonicSaturation.h
#pragma once

#include "DspParams.h"
#include <cmath>
#include <algorithm>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

// Harmonic Saturation & Warmth:
// - Mode 0 (Tape): Symmetric tanh waveshaping with HF tilt pre-emphasis (odd harmonics).
// - Mode 1 (Tube / 6J1 Triode): Asymmetric soft-curve generating rich 2nd-order even harmonics for vocal & instrument warmth.
// - Mode 2 (Analog Class-A): Asymmetric transistor soft-clip curve simulating Class-A single-ended amplification.
// All modes run with 4x polyphase sinc oversampling to completely eliminate digital aliasing foldover.
class HarmonicSaturation {
public:
    static constexpr int MAX_CHANNELS = 8;

    HarmonicSaturation();

    void setSampleRate(double sampleRate);
    // drive: 0..1 (0 = linear/transparent), mix: 0..1 wet/dry,
    // tilt: 0..1 HF pre-emphasis amount, mode: 0 = Tape, 1 = Tube, 2 = Analog.
    void configure(double drive, double mix, double tilt, int mode = 0);
    void setEnabled(bool enabled) { enabled_ = enabled; }
    bool isEnabled() const { return enabled_; }
    void applyParams(const SaturationParamSet& params);
    void reset();

    void process(float* L, float* R, int frames);
    void processInterleaved(float* buffer, int frames, int channels = 2);

    double getDriveK() const { return k_; }
    int getMode() const { return mode_; }

private:
    static constexpr int OVERSAMPLE_FACTOR = 4;
    static constexpr int FIR_TAPS = 24;
    static constexpr int TAPS_PER_PHASE = FIR_TAPS / OVERSAMPLE_FACTOR; // 6

    double sampleRate_ = 48000.0;
    double drive_ = 0.0;
    double mix_ = 0.5;
    double tilt_ = 0.0;
    int mode_ = 0;              // 0 = Tape, 1 = Tube, 2 = Analog
    double k_ = 0.0;            // drive sharpness
    float tiltHpCoeff_ = 0.0f;  // one-pole HP coeff for pre-emphasis
    bool enabled_ = false;

    float hpState_[MAX_CHANNELS] = {};
    float history_[MAX_CHANNELS][TAPS_PER_PHASE] = {};

    // DC blocker states for asymmetric modes (Tube & Analog)
    float dcX_[MAX_CHANNELS] = {};
    float dcY_[MAX_CHANNELS] = {};

    static const float polyphase4x_[OVERSAMPLE_FACTOR][TAPS_PER_PHASE];
};
