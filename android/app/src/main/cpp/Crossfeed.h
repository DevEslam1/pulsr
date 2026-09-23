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
    static constexpr int MAX_DELAY_SAMPLES = 4096;
    static_assert(MAX_DELAY_SAMPLES >= 768 * 2, "Crossfeed buffer must accommodate >= 2ms lookahead/delay at 768kHz");

    Crossfeed();
    void setSampleRate(double sampleRate);
    void configure(double delayUs, double feedDb, double fcut = 650.0);
    void setMode(CrossfeedMode mode);
    CrossfeedMode getMode() const { return mode_; }
    void setEnabled(bool enabled);
    bool isEnabled() const { return enabled_; }
    void applyParams(const CrossfeedParamSet& params);
    void reset();

    double getFcut() const { return fcut_; }
    double getFeedDb() const { return feedDb_; }
    double getDelayUs() const { return delayUs_; }
    double getBs2bA0Lo() const { return bs2b_a0_lo_; }
    double getBs2bB1Lo() const { return bs2b_b1_lo_; }
    double getBs2bA0Hi() const { return bs2b_a0_hi_; }
    double getBs2bGain() const { return bs2b_gain_; }

    void process(float* L, float* R, int frames);
    void processInterleaved(float* buffer, int frames, int channels = 2);

private:
    void initBs2b(double fcut, double feedDb);

    double sampleRate_ = 48000.0;
    CrossfeedMode mode_ = CrossfeedMode::Bs2bDefault;
    double delayUs_ = 350.0;
    double feedDb_ = -9.0;
    double fcut_ = 650.0;
    float delaySamplesFloat_ = 16.8f;
    float targetDelaySamples_ = 16.8f;
    float smoothedDelaySamples_ = 16.8f;
    float targetFeedLevel_ = 0.3548f;
    float smoothedFeedLevel_ = 0.3548f;
    float lpCoeff_ = 0.087f;
    float targetLpCoeff_ = 0.087f;
    float smoothedLpCoeff_ = 0.087f;
    bool enabled_ = false;
    float smoothedEnabledMix_ = 0.0f;

    // Delay-line states (for Custom delay-line mode)
    float delayBufferL_[MAX_DELAY_SAMPLES] = {};
    float delayBufferR_[MAX_DELAY_SAMPLES] = {};
    int writeIdx_ = 0;
    float lpL_ = 0.0f;
    float lpR_ = 0.0f;

    // Authentic BS2B IIR Filter coefficients & states (JamesDSP / Bauer stereophonic-to-binaural)
    double bs2b_a0_lo_ = 0.0;
    double bs2b_b1_lo_ = 0.0;
    double bs2b_a0_hi_ = 0.0;
    double bs2b_a1_hi_ = 0.0;
    double bs2b_b1_hi_ = 0.0;
    double bs2b_gain_ = 1.0;
    double bs2b_lo_[2] = {0.0, 0.0};
    double bs2b_hi_[2] = {0.0, 0.0};
    double bs2b_asis_[2] = {0.0, 0.0};
};
