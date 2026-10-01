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
// All modes run with 4x polyphase sinc oversampling with a 32-tap linear-phase
// decimation filter, which substantially suppresses (but does not fully
// eliminate) digital aliasing foldover.
class HarmonicSaturation {
public:
    static constexpr int MAX_CHANNELS = 8;

    HarmonicSaturation();

    void setSampleRate(double sampleRate);
    // drive: 0..1 (0 = linear/transparent), mix: 0..1 wet/dry,
    // tilt: 0..1 HF pre-emphasis amount, mode: 0 = Tape, 1 = Tube, 2 = Analog,
    // multiband: true = 6-band crossover mid-band warmth mode
    void configure(double drive, double mix, double tilt, int mode = 0, bool multiband = false);
    void setEnabled(bool enabled) { enabled_ = enabled; }
    bool isEnabled() const { return enabled_; }
    bool isMultiband() const { return multiband_; }
    void applyParams(const SaturationParamSet& params);
    void reset();

    void process(float* L, float* R, int frames);
    void processInterleaved(float* buffer, int frames, int channels = 2);

    double getDriveK() const { return k_; }
    int getMode() const { return mode_; }

private:
    static constexpr int OVERSAMPLE_FACTOR = 4;
    // FIX M-23: lengthened the anti-alias polyphase FIR from 24 to 32 taps
    // (6 -> 8 taps/phase) at the same 4x oversampling for a deeper decimation
    // stopband (image rejection re DC improves from ~2 dB to ~12 dB above
    // 0.15*Fs_os and from ~5 dB to ~37 dB above 0.20*Fs_os). The prototype is a
    // true linear-phase Blackman-Harris windowed sinc, so the combined up+down
    // group delay is an exact integer 7 base-rate samples (was ~5), tracked by
    // DRY_DELAY below. DC gain stays 1.0 (each phase sums to 1).
    static constexpr int FIR_TAPS = 32;
    static constexpr int TAPS_PER_PHASE = FIR_TAPS / OVERSAMPLE_FACTOR; // 8

    double sampleRate_ = 48000.0;
    double drive_ = 0.0;
    double mix_ = 0.5;
    double tilt_ = 0.0;
    int mode_ = 0;              // 0 = Tape, 1 = Tube, 2 = Analog
    bool multiband_ = false;    // 6-band crossover mid-band warmth mode
    double k_ = 0.0;            // drive sharpness
    float tiltHpCoeff_ = 0.0f;  // one-pole HP coeff for pre-emphasis
    float dcCoeff_ = 0.9995f;   // DC-blocker pole (rate-derived in configure)
    bool enabled_ = false;

    float hpState_[MAX_CHANNELS] = {};
    float history_[MAX_CHANNELS][TAPS_PER_PHASE] = {};

    // DC blocker states for asymmetric modes (Tube & Analog)
    float dcX_[MAX_CHANNELS] = {};
    float dcY_[MAX_CHANNELS] = {};

    // Decimation history: stores shaped oversampled outputs for proper
    // polyphase FIR decimation (replaces the boxcar average).
    // DECIM_HISTORY_LEN = TAPS_PER_PHASE * OVERSAMPLE_FACTOR = 32 entries
    static constexpr int DECIM_HISTORY_LEN = FIR_TAPS;  // 32
    float decimHistory_[MAX_CHANNELS][DECIM_HISTORY_LEN] = {};
    int decimIdx_ = 0;

    // FIX M-13: dry-path delay line. The wet signal is delayed by the up+down
    // oversampling FIR group delay (the interpolation prototype convolved with
    // the matching decimation prototype peaks at the combined group delay), so
    // the parallel dry tap must be delayed by the same integer amount or the
    // dry/wet sum combs at mix<1. Fixed-size per-channel ring, allocation-free.
    // FIX M-23: with the 32-tap linear-phase prototype the combined impulse
    // response is symmetric and peaks exactly at base sample 7 (was 5 for the
    // 24-tap prototype), so DRY_DELAY tracks that longer group delay.
    static constexpr int DRY_DELAY = 7;
    float dryDelay_[MAX_CHANNELS][DRY_DELAY] = {};
    int dryDelayPos_ = 0;

    static const float polyphase4x_[OVERSAMPLE_FACTOR][TAPS_PER_PHASE];
};
