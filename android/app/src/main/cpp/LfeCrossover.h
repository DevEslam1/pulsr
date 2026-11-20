// android/app/src/main/cpp/LfeCrossover.h
#pragma once

#include "DspParamRanges.h"
#include "DspParams.h"
#include <algorithm>
#include <cmath>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

// Multichannel LFE Bass Management Crossover (3..8 channels).
//
// Unlike SubCrossover (which adds a mono low-passed bass tap back into stereo
// L/R pairs), LfeCrossover operates on multichannel layouts that carry a
// dedicated LFE channel (e.g. 2.1, 5.1, 7.1):
//   1. High-passes each satellite channel (every channel != lfeChannelIndex) at
//      crossoverHz using a Linkwitz-Riley 2nd-order (12 dB/oct) or 4th-order
//      (24 dB/oct) filter when redirectBass is true.
//   2. Low-passes the summed satellite bass (constant-sum scaled by
//      1/satCount, so coherent bass cannot be boosted) at crossoverHz and
//      routes it into the LFE channel.
//   3. Low-passes the dedicated LFE channel itself at lfeLowPassHz (bandwidth
//      limit) and applies lfeGainDb trim (-12..+12 dB).
//
// For streams with < 3 channels (mono/stereo) or an out-of-range
// lfeChannelIndex, processInterleaved() is a bit-exact no-op.
// Real-time safe: all filter states are preallocated fixed arrays; zero heap
// allocations and zero locks in processInterleaved() or setSampleRate().
class LfeCrossover {
public:
    static constexpr int MAX_CHANNELS = 8;
    static constexpr int MIN_MULTICHANNEL = 3;

    LfeCrossover();

    void setSampleRate(double sampleRate);
    void configure(double crossoverHz,
                   double lfeLowPassHz,
                   double slopeDbPerOct,
                   double lfeGainDb,
                   int lfeChannelIndex,
                   bool redirectBass);
    void setEnabled(bool enabled) { enabled_ = enabled; }
    bool isEnabled() const { return enabled_; }
    void applyParams(const LfeCrossoverParamSet& params);
    void reset();

    void processInterleaved(float* buffer, int frames, int channels);

    double getCrossoverHz() const { return crossoverHz_; }
    double getLfeLowPassHz() const { return lfeLowPassHz_; }
    double getSlopeDbPerOct() const { return slopeDbPerOct_; }
    double getLfeGainDb() const { return lfeGainDb_; }
    int getLfeChannelIndex() const { return lfeChannelIndex_; }
    bool isRedirectBass() const { return redirectBass_; }
    double getSmoothedEnabledMix() const { return smoothedEnabledMix_; }
    bool isRamping() const {
        return (!enabled_ && smoothedEnabledMix_ > 1e-4) ||
               (enabled_ && smoothedEnabledMix_ < 0.9999);
    }

private:
    struct BiquadStage {
        double b0 = 1.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0;
        double z1 = 0.0, z2 = 0.0;

        inline float process(float x) {
            if (!std::isfinite(x)) x = 0.0f;
            const double y = b0 * x + z1;
            if (!std::isfinite(y)) {
                z1 = z2 = 0.0;
                return x;
            }
            z1 = b1 * x - a1 * y + z2;
            z2 = b2 * x - a2 * y;
            if (std::abs(z1) < 1e-25) z1 = 0.0;
            if (std::abs(z2) < 1e-25) z2 = 0.0;
            return static_cast<float>(y);
        }

        void clearState() { z1 = z2 = 0.0; }
    };

    static void makeLowPass(double fc, double sampleRate, double q, BiquadStage& out);
    static void makeHighPass(double fc, double sampleRate, double q, BiquadStage& out);
    void computeCoeffs();

    double sampleRate_ = 48000.0;
    double crossoverHz_ = pulsr::dsp::ranges::kLfeCrossoverHz.fallback;
    double lfeLowPassHz_ = pulsr::dsp::ranges::kLfeLowPassHz.fallback;
    double slopeDbPerOct_ = 24.0;
    double lfeGainDb_ = pulsr::dsp::ranges::kLfeGainDb.fallback;
    double targetLfeGainLinear_ = 1.0;
    double smoothedLfeGainLinear_ = 1.0;
    int lfeChannelIndex_ = 3;
    bool redirectBass_ = true;
    bool enabled_ = false;
    bool cascade_ = true; // true = LR4 (24 dB/oct), false = LR2 (12 dB/oct)
    double smoothedEnabledMix_ = 0.0;

    BiquadStage satHp1_[MAX_CHANNELS];
    BiquadStage satHp2_[MAX_CHANNELS];
    BiquadStage redirectLp1_;
    BiquadStage redirectLp2_;
    BiquadStage lfeLp1_;
    BiquadStage lfeLp2_;
};
