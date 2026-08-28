// android/app/src/main/cpp/LookaheadLimiter.h
#pragma once

#if defined(__FAST_MATH__)
#error "-ffast-math leaked into the DSP build — check CMake / gradle compiler flags"
#endif

#include "DspParams.h"
#include <cmath>
#include <algorithm>
#include <cassert>

class LookaheadLimiter {
public:
    static constexpr int MAX_LOOKAHEAD_SAMPLES = 8192;
    static constexpr int INTERP_TAPS = 24;
    static constexpr int INTERP_PHASES = 4;
    static constexpr int TAPS_PER_PHASE = INTERP_TAPS / INTERP_PHASES; // 6

    LookaheadLimiter();
    void setSampleRate(double sampleRate);
    void configure(double lookaheadMs, double thresholdDb, double releaseMs, bool truePeakMode = true);
    void setEnabled(bool enabled);
    bool isEnabled() const { return enabled_; }
    void applyParams(const LimiterParamSet& params);
    void reset();

    int getLatencyFrames() const { return lookaheadSamples_; }

    void process(float* L, float* R, int frames);
    void processMono(float* inOut, int frames);
    void processInterleaved(float* buffer, int frames, int channels = 2);

    float estimateTruePeak(const float* history);

private:

    double sampleRate_ = 48000.0;
    double lookaheadMs_ = 5.0;
    double thresholdDb_ = -0.2;
    double releaseMs_ = 50.0;
    bool truePeakMode_ = true;
    bool enabled_ = false;

    int lookaheadSamples_ = 240;
    float threshold_ = 0.977237f; // pow(10, -0.2 / 20)
    float releaseCoeff_ = 0.9995f;
    float envelope_ = 1.0f;

    static constexpr int MAX_CHANNELS = 8;
    float delayBuf_[MAX_CHANNELS][MAX_LOOKAHEAD_SAMPLES] = {};
    float gainBuf_[MAX_LOOKAHEAD_SAMPLES] = {};
    int writeIdx_ = 0;
    float minGain_ = 1.0f;
    int minGainAge_ = 0;

    // 4x oversampling polyphase interpolation table for true peak detection
    static const float polyphase4x_[INTERP_PHASES][TAPS_PER_PHASE];
};
