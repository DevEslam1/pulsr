// android/app/src/main/cpp/SpatialPanner.h
#pragma once

#include "DspParams.h"
#include <cmath>
#include <algorithm>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

class SpatialPanner {
public:
    SpatialPanner();
    void setSampleRate(double sampleRate);
    void setBalance(double balance); // -1.0 (left) to +1.0 (right)
    void setMono(bool mono);
    double getBalance() const { return targetBalance_; }
    bool isMono() const { return mono_; }
    void applyParams(const PannerParamSet& params);
    void reset();

    void process(float* L, float* R, int frames);
    void processInterleaved(float* buffer, int frames, int channels = 2);

private:
    double sampleRate_ = 48000.0;
    double targetBalance_ = 0.0;
    double smoothedBalance_ = 0.0;
    bool mono_ = false;
    float gainL_ = 1.0f;
    float gainR_ = 1.0f;
};
