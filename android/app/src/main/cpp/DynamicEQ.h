// android/app/src/main/cpp/DynamicEQ.h
#pragma once

#include "DspParams.h"
#include <cmath>
#include <algorithm>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

// Dynamic EQ: bands apply dynamic gain reduction (Cut/Compression) or dynamic
// expansion (Boost/Lift) when signal energy inside the band exceeds threshold.
// Supports Peaking, Low-Shelf, and High-Shelf dynamic filter sections.
class DynamicEQ {
public:
    static constexpr int MAX_BANDS = DynamicEqParamSet::MAX_BANDS;
    static constexpr int MAX_CHANNELS = 8;

    DynamicEQ();

    void setSampleRate(double sampleRate);
    void setBandCount(int count);
    int getBandCount() const { return bandCount_; }
    void setBand(int idx, const DynamicEqBandParam& params);
    void setEnabled(bool enabled) { enabled_ = enabled; }
    bool isEnabled() const { return enabled_; }
    void applyParams(const DynamicEqParamSet& params);
    void reset();

    void process(float* L, float* R, int frames);
    void processInterleaved(float* buffer, int frames, int channels = 2);

    // Current smoothed gain adjustment per band (dB, cut <= 0, boost >= 0)
    double getGainAdjustmentDb(int band) const;
    double getGainReductionDb(int band) const { return getGainAdjustmentDb(band); }

private:
    struct BandState {
        // Static params
        double frequency = 1000.0;
        double q = 2.0;
        double thresholdDb = -30.0;
        double ratio = 3.0;
        double attackMs = 5.0;
        double releaseMs = 120.0;
        double maxCutDb = -12.0;
        double maxBoostDb = 12.0;
        int mode = 0;        // 0 = Cut, 1 = Boost
        int filterType = 0;  // 0 = Peaking, 1 = LowShelf, 2 = HighShelf
        bool enabled = true;
        // Detection: band-pass biquad state + smoothed |bp| envelope per channel
        double dx1[MAX_CHANNELS] = {}, dx2[MAX_CHANNELS] = {};
        double dy1[MAX_CHANNELS] = {}, dy2[MAX_CHANNELS] = {};
        double env[MAX_CHANNELS] = {};
        // Application: biquad with modulated gain per channel
        double b0 = 1.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0;
        double x1[MAX_CHANNELS] = {}, x2[MAX_CHANNELS] = {};
        double y1[MAX_CHANNELS] = {}, y2[MAX_CHANNELS] = {};
        double currentGainDb = 0.0; // smoothed dynamic gain (cut <= 0 or boost >= 0)
        double lastCoeffGainDb = 0.0;
        
        // Cached terms
        double cw = 1.0;
        double alpha = 0.0;
        double detectB0 = 1.0, detectB1 = 0.0, detectB2 = 0.0;
        double detectA1 = 0.0, detectA2 = 0.0;
    };

    void updateBandCache(BandState& band);
    void computeBandCoeffs(BandState& band, double gainDb);
    static void computePeakingCoeffs(double& b0, double& b1, double& b2,
                                     double& a1, double& a2,
                                     double cw, double alpha, double A);
    static void computeLowShelfCoeffs(double& b0, double& b1, double& b2,
                                      double& a1, double& a2,
                                      double cw, double alpha, double A);
    static void computeHighShelfCoeffs(double& b0, double& b1, double& b2,
                                       double& a1, double& a2,
                                       double cw, double alpha, double A);

    double sampleRate_ = 48000.0;
    int bandCount_ = 1;
    bool enabled_ = false;
    BandState bands_[MAX_BANDS];
};
