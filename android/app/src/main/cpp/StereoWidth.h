// android/app/src/main/cpp/StereoWidth.h
#pragma once

#include "DspParams.h"
#include <cmath>
#include <algorithm>

// Mid/Side stereo width control, independent from Crossfeed and the
// Virtualizer: width 0 = mono collapse, 1 = bit-identical passthrough,
// >1 (up to 2) = widened side energy. Zero latency, no coloration.
class StereoWidth {
public:
    StereoWidth();

    void configure(double width);
    void setEnabled(bool enabled) { enabled_ = enabled; }
    bool isEnabled() const { return enabled_; }
    void applyParams(const StereoWidthParamSet& params);
    void reset();

    double getWidth() const { return width_; }

    void process(float* L, float* R, int frames);
    void processInterleaved(float* buffer, int frames, int channels = 2);

private:
    double width_ = 1.0;
    bool enabled_ = false;
};
