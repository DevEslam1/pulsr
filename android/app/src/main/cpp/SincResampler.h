#pragma once

#include <vector>
#include <cmath>
#include <algorithm>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

class SincResampler {
public:
    static constexpr int TAPS = 64;
    static constexpr int HALF_TAPS = TAPS / 2;

    SincResampler();
    void setRates(double inRate, double outRate);
    void setEnabled(bool enabled);
    bool isEnabled() const { return enabled_; }
    void reset();

    int getExpectedOutFrames(int inFrames) const;
    int process(const float* inL, const float* inR, int inFrames,
                float* outL, float* outR, int maxOutFrames);
    int processInterleaved(const float* in, int inFrames,
                           float* out, int maxOutFrames);

private:
    float sinc(float x) const;
    float blackmanHarris(float x) const; // x in [-HALF_TAPS, HALF_TAPS]

    double inRate_ = 44100.0;
    double outRate_ = 48000.0;
    double ratio_ = 44100.0 / 48000.0; // inFrames per outFrame
    double phase_ = 0.0;
    bool enabled_ = true;

    std::vector<float> historyL_;
    std::vector<float> historyR_;
    std::vector<float> bufL_;
    std::vector<float> bufR_;
    int bufCapacity_ = 0;

    std::vector<float> inL_;
    std::vector<float> inR_;
    std::vector<float> outL_;
    std::vector<float> outR_;
};
