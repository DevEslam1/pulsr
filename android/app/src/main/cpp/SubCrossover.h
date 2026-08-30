// android/app/src/main/cpp/SubCrossover.h
#pragma once

#include "DspParams.h"
#include <cmath>
#include <algorithm>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

// Subwoofer / LFE crossover for stereo rigs.
//
// HONEST LIMITATION: the current playback pipeline is stereo-only (no
// multichannel/LFE output exists downstream of this engine), so this stage is
// implemented as *bass redirection*, not true multichannel routing: a
// Linkwitz-Riley-style low-passed mono sum (12 or 24 dB/oct) is added back
// into BOTH channels at the user sub gain. Main channels keep full range —
// no high-pass is applied — so this reinforces/re-centres low bass as a
// mono sub tap. UI copy must describe it as "bass redirection".
class SubCrossover {
public:
    static constexpr int MAX_CHANNELS = 8;

    SubCrossover();

    void setSampleRate(double sampleRate);
    // cornerHz: 60..150, slopeDbPerOct: 12 (LR2) or 24 (LR4), subGain: 0..1.
    void configure(double cornerHz, double slopeDbPerOct, double subGain);
    void setEnabled(bool enabled) { enabled_ = enabled; }
    bool isEnabled() const { return enabled_; }
    void applyParams(const SubCrossoverParamSet& params);
    void reset();

    void process(float* L, float* R, int frames);
    void processInterleaved(float* buffer, int frames, int channels = 2);

    double getCornerHz() const { return cornerHz_; }
    double getSlopeDbPerOct() const { return slopeDbPerOct_; }
    double getSubGain() const { return subGain_; }

private:
    struct LpStage { // transposed direct-form II 2nd-order low-pass
        double b0 = 1.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0;
        double z1 = 0.0, z2 = 0.0;
        inline float process(float x) {
            const double y = b0 * x + z1;
            z1 = b1 * x - a1 * y + z2;
            z2 = b2 * x - a2 * y;
            return static_cast<float>(y);
        }
    };

    void computeCoeffs();

    double sampleRate_ = 48000.0;
    double cornerHz_ = 80.0;
    double slopeDbPerOct_ = 24.0;
    double subGain_ = 0.8;
    bool enabled_ = false;
    bool cascade_ = true; // 24 dB/oct = two cascaded sections

    // Per channel: up to two cascaded 2nd-order Butterworth LP sections
    LpStage stage1_[MAX_CHANNELS];
    LpStage stage2_[MAX_CHANNELS];
};
