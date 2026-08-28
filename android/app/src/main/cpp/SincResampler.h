// android/app/src/main/cpp/SincResampler.h
#pragma once

#include "DspParams.h"
#include <vector>
#include <cmath>
#include <algorithm>
#include <cstring>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

class SincResampler {
public:
    static constexpr int NUM_PHASES = 32;
    static constexpr int TAPS_PER_PHASE = 64;
    static constexpr int TOTAL_TAPS = NUM_PHASES * TAPS_PER_PHASE;
    static constexpr int HALF_TAPS = TAPS_PER_PHASE / 2;

    SincResampler();
    void setRates(double inRate, double outRate);
    void setEnabled(bool enabled);
    bool isEnabled() const { return enabled_; }
    void applyParams(const ResamplerParamSet& params);
    void reset();

    double getInRate() const { return inRate_; }
    double getOutRate() const { return outRate_; }
    double getRatio() const { return ratio_; }

    // Latency reporting in frames (exact group delay)
    int getLatencyFrames() const { return HALF_TAPS; }

    // HARD CONTRACT: Consumes N input frames and returns exactly N output frames
    int processInterleaved(float* buffer, int frames, int channels = 2);

    // Multi-channel planar processing: consumes inFrames and writes up to maxOutFrames
    int processPlanar(const float* const* in, float* const* out, int inFrames, int channels, int maxOutFrames);

private:
    void generatePolyphaseTable();
    static float sinc(float x);
    static float blackmanHarris(float x, float halfWidth);

    double inRate_ = 48000.0;
    double outRate_ = 48000.0;
    double ratio_ = 1.0;
    double phase_ = 0.0;
    bool enabled_ = false;

    // Polyphase FIR filter coefficients [NUM_PHASES][TAPS_PER_PHASE]
    float polyphaseTable_[NUM_PHASES][TAPS_PER_PHASE] = {};

    // Per-channel FIFO ring buffers
    static constexpr int MAX_CHANNELS = 8;
    static constexpr int FIFO_CAPACITY = 8192;
    float ringBuf_[MAX_CHANNELS][FIFO_CAPACITY] = {};
    int writePos_ = 0;
    int availableFrames_ = 0;

    std::vector<float> tempOutBuf_;
};
