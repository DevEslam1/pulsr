// android/app/src/main/cpp/SubCrossover.h
#pragma once

#include "DspParams.h"
#include <cmath>
#include <algorithm>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

// Subwoofer / Bass Management:
// 1. Bass Redirection: low-passed mono sum tap added back to both channels
// 2. Bass Mono: subtracts low-frequency side channel below cornerHz to force low bass into mono,
//    eliminating low-end phase cancellation and tightening punch
// 3. Anti-Pop: soft-saturation tanh limiting on high-transient bass bursts to protect voice coils
class SubCrossover {
public:
    static constexpr int MAX_CHANNELS = 8;

    SubCrossover();

    void setSampleRate(double sampleRate);
    void configure(double cornerHz, double slopeDbPerOct, double subGain, bool bassMono = true, bool antiPop = true);
    void setEnabled(bool enabled) { enabled_ = enabled; }
    bool isEnabled() const { return enabled_; }
    void applyParams(const SubCrossoverParamSet& params);
    void reset();

    void process(float* L, float* R, int frames);
    void processInterleaved(float* buffer, int frames, int channels = 2);

    double getCornerHz() const { return cornerHz_; }
    double getSlopeDbPerOct() const { return slopeDbPerOct_; }
    double getSubGain() const { return subGain_; }
    double getSmoothedEnabledMix() const { return smoothedEnabledMix_; }
    bool isRamping() const { return smoothedEnabledMix_ > 1e-4; }
    bool isBassMono() const { return bassMono_; }
    bool isAntiPop() const { return antiPop_; }

private:
    struct LpStage { // transposed direct-form II 2nd-order low-pass
        double b0 = 1.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0;
        double z1 = 0.0, z2 = 0.0;
        inline float process(float x) {
            if (!std::isfinite(x)) x = 0.0f;
            double y = b0 * x + z1;
            if (!std::isfinite(y)) { y = x; z1 = z2 = 0.0; }
            z1 = b1 * x - a1 * y + z2;
            z2 = b2 * x - a2 * y;
            if (std::abs(z1) < 1e-25) z1 = 0.0;
            if (std::abs(z2) < 1e-25) z2 = 0.0;
            return static_cast<float>(y);
        }
    };

    void computeCoeffs();

    double sampleRate_ = 48000.0;
    double cornerHz_ = 80.0;
    double slopeDbPerOct_ = 24.0;
    double targetSubGain_ = 0.8;
    double smoothedSubGain_ = 0.8;
    double subGain_ = 0.8;
    bool bassMono_ = true;
    bool antiPop_ = true;
    bool enabled_ = false;
    double smoothedEnabledMix_ = 0.0;
    bool cascade_ = true; // 24 dB/oct = two cascaded sections

    static constexpr int MAX_PAIRS = MAX_CHANNELS / 2; // 4 stereo pairs

    LpStage stage1_[MAX_PAIRS];
    LpStage stage2_[MAX_PAIRS];
    // Filter stages for side channel lowpass in Bass Mono
    LpStage stageSide1_[MAX_PAIRS];
    LpStage stageSide2_[MAX_PAIRS];
};
