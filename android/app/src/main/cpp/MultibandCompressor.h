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

    MultibandCompressorParamSet params_;

    // 3 Crossovers to split into 4 bands
    LinkwitzRiley4 crossoverMid_; // splits at crossoverFreqs[1] into LowHalf and HighHalf
    LinkwitzRiley4 crossoverLow_; // splits LowHalf at crossoverFreqs[0] into Band 0 & Band 1
    LinkwitzRiley4 crossoverHigh_;// splits HighHalf at crossoverFreqs[2] into Band 2 & Band 3

    // Per-band ballistics
    double attackCoeff_[NUM_BANDS] = {};
    double releaseCoeff_[NUM_BANDS] = {};
    double envelopeDb_[NUM_BANDS] = {};
    double smoothedGainDb_[NUM_BANDS] = {};
    double currentGainReductionDb_[NUM_BANDS] = {};

    // Scratch buffers for chunked processing (zero heap allocation during audio stream)
    float bandBufferL_[NUM_BANDS][MAX_CHUNK_FRAMES] = {};
    float bandBufferR_[NUM_BANDS][MAX_CHUNK_FRAMES] = {};
};
