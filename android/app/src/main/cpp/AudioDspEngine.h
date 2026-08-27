#pragma once

#include "ParametricEQ.h"
#include "Crossfeed.h"
#include "LookaheadLimiter.h"
#include "ConvolutionReverb.h"
#include "SincResampler.h"
#include "DsdDecoder.h"
#include "SpatialPanner.h"

#include <vector>

enum DspStageMask {
    STAGE_EQ = 1 << 0,
    STAGE_CROSSFEED = 1 << 1,
    STAGE_REVERB = 1 << 2,
    STAGE_PANNER = 1 << 3,
    STAGE_LIMITER = 1 << 4,
    STAGE_RESAMPLER = 1 << 5,
};

class AudioDspEngine {
public:
    static AudioDspEngine& instance();

    AudioDspEngine();
    void setSampleRate(double sampleRate);
    double getSampleRate() const { return sampleRate_; }

    void setActiveStages(uint32_t bitmask) { activeStages_ = bitmask; }
    uint32_t getActiveStages() const { return activeStages_; }

    ParametricEQ& eq() { return eq_; }
    Crossfeed& crossfeed() { return crossfeed_; }
    LookaheadLimiter& limiter() { return limiter_; }
    ConvolutionReverb& reverb() { return reverb_; }
    SincResampler& resampler() { return resampler_; }
    SpatialPanner& panner() { return panner_; }
    DsdDecoder& dsdDecoder() { return dsdDecoder_; }

    int processInterleaved(float* buffer, int frames, int channels = 2);
    void reset();

private:
    double sampleRate_ = 48000.0;
    uint32_t activeStages_ = 0xFFFFFFFF;
    ParametricEQ eq_;
    Crossfeed crossfeed_;
    LookaheadLimiter limiter_;
    ConvolutionReverb reverb_;
    SincResampler resampler_;
    SpatialPanner panner_;
    DsdDecoder dsdDecoder_;
    std::vector<float> resamplerOutBuf_;
};
