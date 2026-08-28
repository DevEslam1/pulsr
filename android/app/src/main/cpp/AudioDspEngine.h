// android/app/src/main/cpp/AudioDspEngine.h
#pragma once

#include "DspParams.h"
#include "ParametricEQ.h"
#include "Crossfeed.h"
#include "LookaheadLimiter.h"
#include "ConvolutionReverb.h"
#include "SincResampler.h"
#include "DsdDecoder.h"
#include "SpatialPanner.h"

#include <vector>
#include <memory>
#include <atomic>
#include <mutex>

enum DspStageMask {
    STAGE_EQ = 1 << 0,
    STAGE_CROSSFEED = 1 << 1,
    STAGE_REVERB = 1 << 2,
    STAGE_PANNER = 1 << 3,
    STAGE_LIMITER = 1 << 4,
    STAGE_RESAMPLER = 1 << 5,
};

template<typename T>
class AtomicSharedPtr {
public:
    AtomicSharedPtr() = default;
    explicit AtomicSharedPtr(std::shared_ptr<T> p) : ptr_(std::move(p)) {}
    std::shared_ptr<T> load(std::memory_order order = std::memory_order_seq_cst) const noexcept {
        return std::atomic_load_explicit(&ptr_, order);
    }
    void store(std::shared_ptr<T> desired, std::memory_order order = std::memory_order_seq_cst) noexcept {
        std::atomic_store_explicit(&ptr_, std::move(desired), order);
    }
private:
    std::shared_ptr<T> ptr_;
};

class AudioDspEngine {
public:
    static AudioDspEngine& instance();

    AudioDspEngine();
    void setSampleRate(double sampleRate);
    double getSampleRate() const { return sampleRate_; }

    void setActiveStages(uint32_t bitmask);
    uint32_t getActiveStages() const;

    // Lock-free atomic parameter snapshot publishing
    void publishParams(std::shared_ptr<const DspParamSnapshot> snapshot);
    std::shared_ptr<const DspParamSnapshot> getParams() const;

    // Stage accessor handles
    ParametricEQ& eq() { return eq_; }
    Crossfeed& crossfeed() { return crossfeed_; }
    LookaheadLimiter& limiter() { return limiter_; }
    ConvolutionReverb& reverb() { return reverb_; }
    SincResampler& resampler() { return resampler_; }
    SpatialPanner& panner() { return panner_; }
    DsdDecoder& dsdDecoder() { return dsdDecoder_; }

    // Combined pipeline latency (lookahead + resampler group delay + reverb partitioned delay) in frames
    int getPipelineLatencyFrames() const {
        return limiter_.getLatencyFrames() + resampler_.getLatencyFrames() + reverb_.getReverbLatencyFrames();
    }

    int processInterleaved(float* buffer, int frames, int channels = 2);
    void reset();

private:
    void setSampleRateInternal(double sampleRate);
    void resetInternal();

    double sampleRate_ = 48000.0;
    std::atomic<uint64_t> snapshotGeneration_{1};
    std::atomic<uint64_t> lastAppliedGeneration_{0};

    // Thread-safe immutable parameter snapshot pointer (C++20 atomic shared_ptr)
    AtomicSharedPtr<const DspParamSnapshot> currentParams_;
    mutable std::mutex publishMutex_;

    ParametricEQ eq_;
    Crossfeed crossfeed_;
    LookaheadLimiter limiter_;
    ConvolutionReverb reverb_;
    SincResampler resampler_;
    SpatialPanner panner_;
    DsdDecoder dsdDecoder_;
};
