// android/app/src/main/cpp/StereoWidth.h
#pragma once

#include "DspParams.h"
#include "CrossoverUtil.h"
#include <cmath>
#include <algorithm>

// Mid/Side stereo width control with 3-band Multiband Stereo Imager and Bass Mono:
// - Low band: user-adjustable width (defaults to 0.0 = Bass Mono, avoiding low-end phase cancellation)
// - Mid band: standard width (0.0 to 2.0)
// - High band: high-frequency spatial widening (0.0 to 2.0)
// When multiband is disabled, acts as a pristine broadband Mid/Side matrix with zero latency.
class StereoWidth {
public:
    StereoWidth();

    void setSampleRate(double sampleRate);
    void configure(double width);
    void configureMultiband(bool multiband, double lowWidth, double midWidth, double highWidth,
                            double lowCrossoverHz, double highCrossoverHz);
    void setEnabled(bool enabled) { enabled_ = enabled; }
    bool isEnabled() const { return enabled_; }
    bool isRamping() const {
        return !enabled_ && (std::abs(smoothedWidth_ - 1.0) > 1e-4 ||
            (multiband_ && (std::abs(smoothedLowWidth_ - 1.0) > 1e-4 ||
             std::abs(smoothedMidWidth_ - 1.0) > 1e-4 || std::abs(smoothedHighWidth_ - 1.0) > 1e-4)));
    }
    void applyParams(const StereoWidthParamSet& params);
    void reset();

    double getWidth() const { return targetWidth_; }
    bool isMultiband() const { return multiband_; }
    double getLowWidth() const { return targetLowWidth_; }
    double getMidWidth() const { return targetMidWidth_; }
    double getHighWidth() const { return targetHighWidth_; }

    void process(float* L, float* R, int frames);
    void processInterleaved(float* buffer, int frames, int channels = 2);

private:
    void updateCrossovers();

    double sampleRate_ = 48000.0;
    double targetWidth_ = 1.0;
    double smoothedWidth_ = 1.0;
    bool enabled_ = false;

    // Multiband imaging state
    bool multiband_ = false;
    double targetLowWidth_ = 0.0;  // Bass Mono by default
    double smoothedLowWidth_ = 0.0;
    double targetMidWidth_ = 1.0;
    double smoothedMidWidth_ = 1.0;
    double targetHighWidth_ = 1.5;
    double smoothedHighWidth_ = 1.5;
    double lowCrossoverHz_ = 160.0;
    double highCrossoverHz_ = 4000.0;

    LinkwitzRiley4 crossoverLow_;  // Splits Low vs Mid+High
    LinkwitzRiley4 crossoverHigh_; // Splits Mid vs High
    // FIX M-22: the low band bypasses the high crossover, so without an allpass
    // the 3-way LR4 reconstruction is only approximately flat and is phase-
    // incoherent at the summing junction. This LR4, tuned to highCrossoverHz_,
    // synthesizes the complementary 2nd-order allpass (AP = LP+HP of an LR4) that
    // the mid+high sum already carries, and is applied to the low band so the
    // three bands sum phase-coherently. Separate state from crossoverHigh_ since
    // it filters the low band, not mid+high.
    LinkwitzRiley4 lowBandAllpass_;
};
