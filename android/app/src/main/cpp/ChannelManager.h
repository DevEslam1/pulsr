// android/app/src/main/cpp/ChannelManager.h
#pragma once

#include "DspParams.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <vector>

// Multichannel output conditioning: per-channel trim and delay for 2–8 channel
// layouts. This is deliberately a separate stage from EQ/dynamics: it runs after
// the stereo-centric effects and before the limiter, so a boosted surround
// channel is still caught by the brickwall.
//
// Bass management is intentionally not implicit here. Redirecting low bass to
// an LFE needs a channel-layout contract (which channel is LFE, satellite
// crossover, per-channel distance); that belongs in a dedicated layout stage,
// not in a trim/delay helper that would silently alter a 5.1 mix.
class ChannelManager {
public:
    static constexpr int MAX_CHANNELS = 8;
    static constexpr double MAX_DELAY_MS = 50.0;
    static constexpr int MAX_SAMPLE_RATE = 768000;
    static constexpr int MAX_DELAY_SAMPLES =
        static_cast<int>(MAX_SAMPLE_RATE * (MAX_DELAY_MS / 1000.0)) + 1;
    static constexpr double RAMP_MS = 20.0;

    ChannelManager();

    void setSampleRate(double sampleRate);
    void applyParams(const ChannelManagerParamSet& params);
    void reset();

    void processInterleaved(float* buffer, int frames, int channels);

    bool isEnabled() const { return params_.enabled || rampingDown_; }
    bool isRamping() const { return rampingDown_; }
    int getChannelCount() const { return params_.channelCount; }

private:
    double sampleRate_ = 0.0;
    ChannelManagerParamSet params_{};
    bool rampingDown_ = false;

    int delaySamples_[MAX_CHANNELS] = {};
    int maxDelaySamples_ = 1;
    std::array<std::vector<float>, MAX_CHANNELS> delayLines_;
    std::array<int, MAX_CHANNELS> writeIndex_{};

    float currentGain_[MAX_CHANNELS] = {};
    float targetGain_[MAX_CHANNELS] = {};
    float gainStep_[MAX_CHANNELS] = {};
    int rampRemaining_[MAX_CHANNELS] = {};

    void resetChannelState(int channel);
};
