// android/app/src/main/cpp/ArbitraryResponseEq.h
#pragma once

#include "DspParams.h"
#include "FftUtil.h"
#include <vector>
#include <string>
#include <utility>

class ArbitraryResponseEq {
public:
    static constexpr int FIR_TAPS = 512;
    static constexpr int FFT_SIZE = FIR_TAPS * 2; // 1024

    ArbitraryResponseEq();
    void setSampleRate(double sampleRate);
    void setEnabled(bool enabled) { enabled_ = enabled; }
    bool isEnabled() const { return enabled_; }
    void applyParams(const ArbitraryEqParamSet& params);
    void reset();

    bool loadGraphicEqString(const std::string& eqString, bool linearPhase = false);
    int getNodeCount() const { return static_cast<int>(nodes_.size()); }
    const std::string& getLoadedString() const { return loadedString_; }

    void process(float* L, float* R, int frames);
    void processInterleaved(float* buffer, int frames, int channels = 2);

private:
    double sampleRate_ = 48000.0;
    bool enabled_ = false;
    bool linearPhase_ = false;
    std::string loadedString_;
    std::vector<std::pair<double, double>> nodes_; // {freqHz, gainDb}

    std::vector<float> firFilter_; // FIR_TAPS length

    // Overlap-add convolution state
    float historyL_[FIR_TAPS] = {};
    float historyR_[FIR_TAPS] = {};

    void synthesizeFir();
};
