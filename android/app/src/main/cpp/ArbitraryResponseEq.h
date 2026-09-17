// android/app/src/main/cpp/ArbitraryResponseEq.h
#pragma once

#include "DspParams.h"
#include "FftUtil.h"
#include <vector>
#include <string>
#include <memory>
#include <utility>

class ArbitraryResponseEq {
public:
    static constexpr int FIR_TAPS = 512;
    static constexpr int FFT_SIZE = FIR_TAPS * 2; // 1024
    static constexpr int MAX_NODES = 1024;

    ArbitraryResponseEq();
    void setSampleRate(double sampleRate);
    void setEnabled(bool enabled) { enabled_ = enabled; }
    bool isEnabled() const { return enabled_; }
    void applyParams(const ArbitraryEqParamSet& params);
    void reset();

    bool loadGraphicEqString(const std::string& eqString, bool linearPhase = false);

    /// Applies an already-parsed and sorted node list (prepared off the audio
    /// thread by the JNI setter). This is the audio-thread entry point: it only
    /// copies the nodes into pre-reserved storage and runs the small FIR
    /// synthesis, with no heap allocation when the node count stays within
    /// capacity.
    void applyPreparedNodes(
        const std::shared_ptr<const std::vector<std::pair<double, double>>>& nodes,
        bool linearPhase);

    int getNodeCount() const { return static_cast<int>(nodes_.size()); }
    const std::string& getLoadedString() const { return loadedString_; }

    /// Parses a "GraphicEq: f g; f g; ..." string into sorted, clamped nodes.
    /// Performed on the control thread so the audio thread never allocates.
    static bool parseGraphicEq(const std::string& eqString,
                               std::vector<std::pair<double, double>>& outNodes);

    void process(float* L, float* R, int frames);
    void processInterleaved(float* buffer, int frames, int channels = 2);

private:
    double sampleRate_ = 48000.0;
    bool enabled_ = false;
    bool linearPhase_ = false;
    bool hasResponse_ = false;
    std::string loadedString_;
    std::vector<std::pair<double, double>> nodes_; // {freqHz, gainDb}

    std::vector<float> firFilter_; // FIR_TAPS length

    // Reusable FFT scratch so synthesis never allocates on the audio thread.
    std::vector<FftUtil::Complex> spectrumScratch_;

    // Overlap-add convolution state
    float historyL_[FIR_TAPS] = {};
    float historyR_[FIR_TAPS] = {};

    std::shared_ptr<const std::vector<std::pair<double, double>>> preparedNodesRef_;

    void synthesizeFir();
};
