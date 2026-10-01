// android/app/src/main/cpp/MultibandCompressor.h
#pragma once

#include "DspParams.h"
#include <cmath>
#include <algorithm>
#include <cstring>
#include <vector>

#include "CrossoverUtil.h"

class MultibandCompressor {
public:
    static constexpr int NUM_BANDS = 4;
    static constexpr int MAX_CHUNK_FRAMES = 1024;

    MultibandCompressor();

    void setSampleRate(double sampleRate);
    void applyParams(const MultibandCompressorParamSet& params);
    void setEnabled(bool enabled) { enabled_ = enabled; }
    bool isEnabled() const { return enabled_; }
    void reset();

    void processInterleaved(float* buffer, int frames, int channels = 2);

    double getBandGainReductionDb(int band) const {
        if (band >= 0 && band < NUM_BANDS) return currentGainReductionDb_[band];
        return 0.0;
    }

private:
    void updateCoefficients();
    double computeBandGain(int band, double envDb);

    bool enabled_ = false;
    double sampleRate_ = 48000.0;

    std::atomic<bool> paramsChanged_{false};
    MultibandCompressorParamSet pendingParams_;
    MultibandCompressorParamSet params_;

    // 3 Crossovers to split into 4 bands
    LinkwitzRiley4 crossoverMid_; // splits at crossoverFreqs[1] into LowHalf and HighHalf
    LinkwitzRiley4 crossoverLow_; // splits LowHalf at crossoverFreqs[0] into Band 0 & Band 1
    LinkwitzRiley4 crossoverHigh_;// splits HighHalf at crossoverFreqs[2] into Band 2 & Band 3

    // FIX M-11: allpass phase-compensation for flat (unity-bypass) reconstruction.
    // When each half's two sub-bands recombine they are multiplied by the allpass
    // of their own sub-crossover (an LR4 section's LP+HP is a 2nd-order allpass):
    // the low half gains AP_f0 (from crossoverLow_), the high half gains AP_f2
    // (from crossoverHigh_). Those differ (f0 != f2), so the halves meet at the f1
    // split with mismatched phase -> magnitude ripple near the crossovers. To
    // match them, cross-apply each sibling's complementary allpass:
    //   - allpassLowPath_  (configured at f2) filters the LOW  half -> adds AP_f2
    //   - allpassHighPath_ (configured at f0) filters the HIGH half -> adds AP_f0
    // Both halves then carry the common factor AP_f0*AP_f2 and sum to
    // AP_f0*AP_f2*(LP_f1 + HP_f1) = AP_f0*AP_f2*AP_f1 -> unity magnitude.
    // We reuse LinkwitzRiley4 (no dedicated allpass exists in CrossoverUtil) and
    // read its allpass as the lp+hp output sum; same cutoff + Butterworth Q as the
    // sibling crossover guarantees an exact phase match.
    LinkwitzRiley4 allpassLowPath_;  // allpass @ f2, applied to the low half
    LinkwitzRiley4 allpassHighPath_; // allpass @ f0, applied to the high half

    // Per-band ballistics
    double attackCoeff_[NUM_BANDS] = {};
    double releaseCoeff_[NUM_BANDS] = {};
    double envelopeDb_[NUM_BANDS] = {};    // linear amplitude envelope per band (attack/release smoothed)
    double smoothedGainDb_[NUM_BANDS] = {};
    double currentGainReductionDb_[NUM_BANDS] = {};

    // Scratch buffers for chunked processing (zero heap allocation during audio stream)
    float bandBufferL_[NUM_BANDS][MAX_CHUNK_FRAMES] = {};
    float bandBufferR_[NUM_BANDS][MAX_CHUNK_FRAMES] = {};
};
