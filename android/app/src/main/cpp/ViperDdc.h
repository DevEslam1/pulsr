// android/app/src/main/cpp/ViperDdc.h
#pragma once

#include "DspParams.h"
#include <vector>
#include <string>
#include <memory>
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

    static constexpr int MAX_SECTIONS = 256;

    ViperDdc();
    void setSampleRate(double sampleRate);
    void setEnabled(bool enabled) { enabled_ = enabled; }
    bool isEnabled() const { return enabled_; }
    void applyParams(const ViperDdcParamSet& params);
    void reset();

    bool loadVdcString(const std::string& vdcContent);

    /// Parses a raw .vdc text into coefficient-only sections (both rate
    /// families). Pure/static and allocates only its own output, so it can run
    /// on the control thread; the result is published via the snapshot.
    static bool parseVdcContent(const std::string& vdcContent,
                                std::vector<ViperDdcSection>& out441,
                                std::vector<ViperDdcSection>& out480);

    /// Applies already-parsed coefficient sets without parsing/allocating
    /// (audio-thread entry point; internal vectors are pre-reserved).
    void applyPreparedSections(const std::vector<ViperDdcSection>& s441,
                               const std::vector<ViperDdcSection>& s480);

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

    // Identity of the last published prepared sets, for change detection.
    std::shared_ptr<const std::vector<ViperDdcSection>> prepared441_;
    std::shared_ptr<const std::vector<ViperDdcSection>> prepared480_;

    void updateActiveSections();
};
