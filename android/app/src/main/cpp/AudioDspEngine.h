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
#if defined(__cpp_lib_atomic_shared_ptr) && __cpp_lib_atomic_shared_ptr >= 201711L
    // C++20 path: lock-free atomic<shared_ptr> when the STL supports it (e.g. libstdc++ on NDK r26+)
    std::shared_ptr<T> load(std::memory_order order = std::memory_order_seq_cst) const noexcept {
        return ptr_.load(order);
    }
    void store(std::shared_ptr<T> desired, std::memory_order order = std::memory_order_seq_cst) noexcept {
        ptr_.store(std::move(desired), order);
    }
private:
    mutable std::atomic<std::shared_ptr<T>> ptr_;
#else
    // Fallback for libc++ on Windows host tests and older NDKs: the old free-function
    // std::atomic_load / std::atomic_store are deprecated in C++20 but remain the only
    // portable way to get atomic shared_ptr. Not guaranteed lock-free (B-11), but the
    // runtime check in test_snapshot_race.cpp verifies lock-freedom where available.
    std::shared_ptr<T> load(std::memory_order order = std::memory_order_seq_cst) const noexcept {
        return std::atomic_load_explicit(&ptr_, order);
    }
    void store(std::shared_ptr<T> desired, std::memory_order order = std::memory_order_seq_cst) noexcept {
        std::atomic_store_explicit(&ptr_, std::move(desired), order);
    }
private:
    std::shared_ptr<T> ptr_;
#endif
};

class AudioDspEngine {
public:
    static AudioDspEngine& instance();

    AudioDspEngine();
    void setSampleRate(double sampleRate);
    double getSampleRate() const { return sampleRate_; }
    double getAppliedSampleRate() const { return sampleRate_; }
    uint64_t getLastAppliedGeneration() const { return lastAppliedGeneration_.load(); }
    uint64_t getPublishedGeneration() const { return snapshotGeneration_.load(); }

    void resyncForTrack(double sampleRate, int channels = 2);

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
        int latency = 0;
        auto snap = getParams();
        if (!snap) return 0;
        if (snap->limiter.enabled) {
            latency += limiter_.getLatencyFrames();
        }
        if (snap->resampler.enabled) {
            latency += resampler_.getLatencyFrames();
        }
        if (snap->reverb.enabled) {
            latency += reverb_.getReverbLatencyFrames();
        }
        return latency;
    }

    // Auto-Degrade Safety Net: tracks stages bypassed due to budget exhaustion
    uint32_t getAutoDegradedStages() const { return autoDegradedStages_.load(); }
    void triggerStageAutoDegrade(uint32_t stageBitmask) { autoDegradedStages_.fetch_or(stageBitmask); }
    void recoverStageAutoDegrade(uint32_t stageBitmask) { autoDegradedStages_.fetch_and(~stageBitmask); }
    void clearAutoDegradedStages() {
        autoDegradedStages_.store(0);
        degradeConsecutiveBlocks_ = 0;
        recoveryConsecutiveBlocks_ = 0;
        rtfCount_ = 0;
        rtfRingHead_ = 0;
    }

    // In-Engine Auto-Degrade Nervous System controls & test hooks
    void setAutoDegradeMonitorEnabled(bool enabled) { autoDegradeMonitorEnabled_.store(enabled); }
    bool isAutoDegradeMonitorEnabled() const { return autoDegradeMonitorEnabled_.load(); }
    void setSimulatedBlockRtf(double rtf) { simulatedBlockRtf_.store(rtf); }
    double getRollingRtf() const { return rollingRtf_.load(); }

    int processInterleaved(float* buffer, int frames, int channels = 2);
    void reset();

private:
    void setSampleRateInternal(double sampleRate);
    void resetInternal();

    double sampleRate_ = 48000.0;
    std::atomic<uint64_t> snapshotGeneration_{1};
    std::atomic<uint64_t> lastAppliedGeneration_{0};
    std::atomic<uint32_t> autoDegradedStages_{0};

    // Rolling RTF monitor (zero heap allocation, preallocated fixed ring buffer)
    static constexpr int kRtfWindowSize = 20;
    static constexpr int kRtfRecoveryWindowSize = 40;
    std::atomic<bool> autoDegradeMonitorEnabled_{true};
    std::atomic<double> simulatedBlockRtf_{-1.0}; // < 0 means measure actual wall-clock
    std::atomic<double> rollingRtf_{0.0};
    float rtfRingBuffer_[kRtfWindowSize] = {};
    int rtfRingHead_ = 0;
    int rtfCount_ = 0;
    int degradeConsecutiveBlocks_ = 0;
    int recoveryConsecutiveBlocks_ = 0;

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
