// android/app/src/main/cpp/ParametricEQ.h
#pragma once

#include "DspParams.h"
#include <cmath>
#include <vector>
#include <algorithm>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

struct BiquadCoeffs {
    double b0 = 1.0, b1 = 0.0, b2 = 0.0;
    double a1 = 0.0, a2 = 0.0;
};

struct EQBandState {
    double frequency = 1000.0;        // smoothing target frequency
    double smoothedFrequency = 1000.0; // per-block interpolated frequency used for coeffs
    double targetGainDb = 0.0;
    double smoothedGainDb = 0.0;
    double q = 1.0;                   // smoothing target Q
    double smoothedQ = 1.0;           // per-block interpolated Q used for coeffs
    FilterType type = FilterType::Peaking;
    bool enabled = true;
    bool solo = false;
    bool mute = false;
    bool bypass = false;
    BiquadCoeffs coeffs;
};

class ParametricEQ {
public:
    static constexpr int MAX_BANDS = 64;
    static constexpr int MAX_CHANNELS = 8;

    ParametricEQ();
    void setSampleRate(double sampleRate);
    void setBandCount(int count);
    int getBandCount() const { return bandCount_; }
    void setDynamicBands(int count, const double* freqs, const double* qs);
    void setBand(int idx, double freq, double gainDb, double q, FilterType type = FilterType::Peaking, bool enabled = true);
    void setBandSolo(int idx, bool solo);
    void setBandMute(int idx, bool mute);
    void setPreamp(double preampDb);
    void setEnabled(bool enabled);
    bool isEnabled() const { return enabled_; }
    void applyParams(const EqParamSet& params);
    void reset();

    void process(const float* in, float* out, int frames, int channels);
    void processInterleaved(float* buffer, int frames, int channels);

private:
    void computeCoeffs(EQBandState& band, double gainDb);
    // Off->on transition: clear stale filter memory and restart preamp/band
    // gains from flat so the smoother fades the EQ in instead of clicking.
    void beginEnableRamp();
    // On->off transition: keep processing while the preamp and every band gain
    // ramp down to unity, then hard-bypass, so disable fades out symmetrically
    // with beginEnableRamp instead of clicking / jumping level.
    void beginDisableRamp();

    EQBandState bands_[MAX_BANDS];
    int bandCount_ = 10;
    double sampleRate_ = 48000.0;
    double targetPreampDb_ = 0.0;
    double smoothedPreampDb_ = 0.0;
    double preampLinear_ = 1.0;
    bool enabled_ = true;

    // Disable fade-out state (symmetric to beginEnableRamp). While fadeOutActive_
    // is set, process() keeps running with every gain/preamp smoothing toward
    // unity even though enabled_ is already false; after fadeOutFrames_ frames
    // (several smoothing time constants) the stage hard-bypasses click-free.
    bool fadeOutActive_ = false;
    long long fadeOutFrames_ = 0;

    // Set when the sample rate changes so applyParams() force-recomputes every
    // band in the incoming snapshot at the new rate, including bands that were
    // outside the previous bandCount_ (whose retained coefficients belong to the
    // old rate and would otherwise be kept because their stored freq/Q/type match).
    bool coeffsStale_ = false;
    // Tracks which bands were muted by the solo state on the previous block so a
    // band re-entering can have its delay registers cleared without touching
    // band.bypass (which computeCoeffs() owns).
    bool soloSkipped_[MAX_BANDS] = {};

    // Per-channel Transposed Direct Form II state: 2 double-precision registers per band per channel
    double s1_[MAX_CHANNELS][MAX_BANDS] = {};
    double s2_[MAX_CHANNELS][MAX_BANDS] = {};
    std::vector<float> tempBuf_;
};
