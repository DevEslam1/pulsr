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
    double frequency = 1000.0;
    double targetGainDb = 0.0;
    double smoothedGainDb = 0.0;
    double q = 1.0;
    FilterType type = FilterType::Peaking;
    bool enabled = true;
    bool solo = false;
    bool mute = false;
    bool bypass = false;
    BiquadCoeffs coeffs;
};

class ParametricEQ {
public:
    static constexpr int MAX_BANDS = 32;
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

    EQBandState bands_[MAX_BANDS];
    int bandCount_ = 10;
    double sampleRate_ = 48000.0;
    double targetPreampDb_ = 0.0;
    double smoothedPreampDb_ = 0.0;
    double preampLinear_ = 1.0;
    bool enabled_ = true;

    // Per-channel Transposed Direct Form II state: 2 double-precision registers per band per channel
    double s1_[MAX_CHANNELS][MAX_BANDS] = {};
    double s2_[MAX_CHANNELS][MAX_BANDS] = {};
    std::vector<float> tempBuf_;
};
