#pragma once

#include "ParametricEQ.h"
#include "Crossfeed.h"
#include "LookaheadLimiter.h"
#include "ConvolutionReverb.h"
#include "SincResampler.h"
#include "DsdDecoder.h"
#include "SpatialPanner.h"

class AudioDspEngine {
public:
    static AudioDspEngine& instance();

    AudioDspEngine();
    void setSampleRate(double sampleRate);
    double getSampleRate() const { return sampleRate_; }

    ParametricEQ& eq() { return eq_; }
    Crossfeed& crossfeed() { return crossfeed_; }
    LookaheadLimiter& limiter() { return limiter_; }
    ConvolutionReverb& reverb() { return reverb_; }
    SincResampler& resampler() { return resampler_; }
    SpatialPanner& panner() { return panner_; }
    DsdDecoder& dsdDecoder() { return dsdDecoder_; }

    void processInterleaved(float* buffer, int frames, int channels = 2);
    void reset();

private:
    double sampleRate_ = 48000.0;
    ParametricEQ eq_;
    Crossfeed crossfeed_;
    LookaheadLimiter limiter_;
    ConvolutionReverb reverb_;
    SincResampler resampler_;
    SpatialPanner panner_;
    DsdDecoder dsdDecoder_;
};
