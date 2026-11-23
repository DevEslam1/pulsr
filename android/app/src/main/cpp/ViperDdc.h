// android/app/src/main/cpp/ViperDdc.h
#pragma once

#include "DspParams.h"
#include <vector>
#include <string>
#include <memory>
#include <cmath>

class ViperDdc {
public:
    static constexpr int MAX_CHANNELS = 8;
    struct Section {
        double b0 = 1.0;
        double b1 = 0.0;
        double b2 = 0.0;
        double a1 = 0.0;
        double a2 = 0.0;
#if defined(PULSR_F32_BIQUADS)
        float v1[MAX_CHANNELS] = {};
        float v2[MAX_CHANNELS] = {};
#else
        double v1[MAX_CHANNELS] = {};
        double v2[MAX_CHANNELS] = {};
#endif
    };

    static constexpr int MAX_SECTIONS = 256;

    ViperDdc();
    void setSampleRate(double sampleRate);
    void setEnabled(bool enabled) { enabled_ = enabled; }
    bool isEnabled() const { return enabled_; }
    bool isRamping() const {
        const bool shouldBeOn = enabled_ && !activeSections_.empty();
        return (!shouldBeOn && smoothedEnabledMix_ >= 1e-4f) ||
               (shouldBeOn && smoothedEnabledMix_ < 0.9999f) ||
               (sectionCrossfadeProgress_ < 1.0f && !crossfadeSections_.empty());
    }
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
    float smoothedEnabledMix_ = 0.0f;
    std::string profileName_;
    std::string loadedContent_;

    std::vector<Section> sections441_;
    std::vector<Section> sections480_;
    std::vector<Section> activeSections_;
    std::vector<Section> crossfadeSections_;
    float sectionCrossfadeProgress_ = 1.0f;

    // Identity of the last published prepared sets, for change detection.
    std::shared_ptr<const std::vector<ViperDdcSection>> prepared441_;
    std::shared_ptr<const std::vector<ViperDdcSection>> prepared480_;

    void updateActiveSections();
};
