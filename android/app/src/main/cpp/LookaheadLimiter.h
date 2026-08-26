#pragma once

#include <cmath>
#include <algorithm>

class LookaheadLimiter {
public:
    static constexpr int MAX_LOOKAHEAD_SAMPLES = 2048; // ~42ms at 48kHz

    LookaheadLimiter();
    void setSampleRate(double sampleRate);
    void configure(double lookaheadMs, double thresholdDb, double releaseMs);
    void setEnabled(bool enabled);
    bool isEnabled() const { return enabled_; }
    void reset();

    void process(float* L, float* R, int frames);
    void processMono(float* inOut, int frames);
    void processInterleaved(float* buffer, int frames);

private:
    double sampleRate_ = 48000.0;
    double lookaheadMs_ = 3.0;     // ~3 ms lookahead
    double thresholdDb_ = -0.2;    // -0.2 dB true ceiling
    double releaseMs_ = 50.0;      // 50 ms release
    int lookaheadSamples_ = 144;
    float threshold_ = 0.977f;
    float releaseCoeff_ = 0.9995f;
    float envelope_ = 1.0f;
    bool enabled_ = false;

    float delayBuf_[2][MAX_LOOKAHEAD_SAMPLES] = {};
    int writeIdx_ = 0;
};
