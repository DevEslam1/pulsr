// android/app/src/main/cpp/ViperDdc.h
#pragma once

#include "DspParams.h"
#include <vector>
#include <string>
#include <cmath>

class ViperDdc {
public:
    struct Section {
        double b0 = 1.0;
        double b1 = 0.0;
        double b2 = 0.0;
        double a1 = 0.0;
        double a2 = 0.0;
        double v1L = 0.0;
        double v2L = 0.0;
        double v1R = 0.0;
        double v2R = 0.0;
    };

    ViperDdc();
    void setSampleRate(double sampleRate);
    void setEnabled(bool enabled) { enabled_ = enabled; }
    bool isEnabled() const { return enabled_; }
    void applyParams(const ViperDdcParamSet& params);
    void reset();

    bool loadVdcString(const std::string& vdcContent);
    int getSectionCount() const;
    const std::string& getProfileName() const { return profileName_; }

    void process(float* L, float* R, int frames);
    void processInterleaved(float* buffer, int frames, int channels = 2);

private:
    double sampleRate_ = 48000.0;
    bool enabled_ = false;
    std::string profileName_;
    std::string loadedContent_;

    std::vector<Section> sections441_;
    std::vector<Section> sections480_;
    std::vector<Section> activeSections_;

    void updateActiveSections();
};
