// android/app/src/main/cpp/Crossfeed.h
#pragma once

#include "DspParams.h"
#include <cmath>
#include <algorithm>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

class Crossfeed {
public:
    static constexpr int MAX_DELAY_SAMPLES = 2048;

    Crossfeed();
    void setSampleRate(double sampleRate);
    void configure(double delayUs, double feedDb, double fcut = 650.0);
    void setEnabled(bool enabled);
    bool isEnabled() const { return enabled_; }
    void applyParams(const CrossfeedParamSet& params);
    void reset();

    double getFcut() const { return fcut_; }
    double getFeedDb() const { return feedDb_; }
    double getDelayUs() const { return delayUs_; }

    void process(float* L, float* R, int frames);
    void processInterleaved(float* buffer, int frames);

private:
    double sampleRate_ = 48000.0;
    double delayUs_ = 350.0;
    double feedDb_ = -9.0;
    double fcut_ = 650.0;
    int delaySamples_ = 17;
    float feedLevel_ = 0.3548f;
    float lpCoeff_ = 0.087f;
    bool enabled_ = false;

    float delayBufferL_[MAX_DELAY_SAMPLES] = {};
    float delayBufferR_[MAX_DELAY_SAMPLES] = {};
    int writeIdx_ = 0;
    float lpL_ = 0.0f;
    float lpR_ = 0.0f;
};
