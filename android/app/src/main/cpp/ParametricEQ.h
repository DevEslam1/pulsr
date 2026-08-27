#pragma once

#include <cmath>
#include <vector>
#include <algorithm>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

enum class FilterType {
    Peaking = 0,
    LowShelf = 1,
    HighShelf = 2,
    LowPass = 3,
    HighPass = 4
};

struct BiquadCoeffs {
    double b0 = 1.0, b1 = 0.0, b2 = 0.0;
    double a1 = 0.0, a2 = 0.0;
};

struct EQBand {
    double frequency = 1000.0; // 20 Hz – 20 kHz
    double gainDb = 0.0;       // -24 to +24 dB
    double q = 1.0;            // 0.1 to 10.0
    FilterType type = FilterType::Peaking;
    bool enabled = true;
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
    void setPreamp(double preampDb);
    void setEnabled(bool enabled);
    bool isEnabled() const { return enabled_; }
    void reset();

    void process(const float* in, float* out, int frames, int channels);
    void processInterleaved(float* buffer, int frames, int channels);

private:
    void computeCoeffs(EQBand& band);

    EQBand bands_[MAX_BANDS];
    int bandCount_ = 10;
    double sampleRate_ = 48000.0;
    double preampDb_ = 0.0;
    double preampLinear_ = 1.0;
    bool enabled_ = true;

    // Per-channel state for up to 8 channels (mono, stereo, 5.1, 7.1)
    double x1_[MAX_CHANNELS][MAX_BANDS] = {};
    double x2_[MAX_CHANNELS][MAX_BANDS] = {};
    double y1_[MAX_CHANNELS][MAX_BANDS] = {};
    double y2_[MAX_CHANNELS][MAX_BANDS] = {};
    std::vector<float> tempBuf_;
};
