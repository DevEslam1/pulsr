#pragma once

#include <vector>
#include <cmath>
#include <string>
#include <algorithm>

enum class ReverbPreset {
    StudioRoom = 0,
    ConcertHall = 1,
    WarmTube = 2,
    PlateReverb = 3,
    Custom = 4
};

class ConvolutionReverb {
public:
    ConvolutionReverb();
    void setSampleRate(double sampleRate);
    void setPreset(ReverbPreset preset);
    void loadCustomIR(const float* irSamples, int sampleCount);
    void setWetDry(float wetRatio); // 0.0 (all dry) to 1.0 (all wet)
    void setQualityStep(int step) { qualityStep_ = std::max(1, std::min(step, 4)); }
    int getQualityStep() const { return qualityStep_; }
    void setEnabled(bool enabled);
    bool isEnabled() const { return enabled_; }
    void reset();

    void process(float* L, float* R, int frames);
    void processInterleaved(float* buffer, int frames);

private:
    void generatePresetIR(ReverbPreset preset);

    double sampleRate_ = 48000.0;
    float wetRatio_ = 0.20f;
    int qualityStep_ = 2; // High-detail convolution step
    bool enabled_ = false;
    ReverbPreset currentPreset_ = ReverbPreset::StudioRoom;

    std::vector<float> irL_;
    std::vector<float> irR_;
    int irLength_ = 0;

    std::vector<float> historyL_;
    std::vector<float> historyR_;
    int historyIdx_ = 0;
};
