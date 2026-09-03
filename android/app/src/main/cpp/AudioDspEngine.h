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
#include "HarmonicSaturation.h"
#include "StereoWidth.h"
#include "LoudnessContour.h"
#include "SubCrossover.h"
#include "DynamicEQ.h"

#include <vector>
#include <memory>
#include <atomic>
#include <mutex>
#include <functional>

enum DspStageMask {
    STAGE_EQ = 1 << 0,
    STAGE_CROSSFEED = 1 << 1,
    STAGE_REVERB = 1 << 2,
    STAGE_PANNER = 1 << 3,
    STAGE_LIMITER = 1 << 4,
    STAGE_RESAMPLER = 1 << 5,
    // Phase 1 DSP-expansion stages
    STAGE_SATURATION = 1 << 6,
    STAGE_WIDTH = 1 << 7,
    STAGE_LOUDNESS = 1 << 8,
    STAGE_CROSSOVER = 1 << 9,
    STAGE_DYNEQ = 1 << 10,
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

    // Transactional parameter mutation & publishing
    using SnapshotMutator = std::function<void(DspParamSnapshot&)>;
    void updateParams(SnapshotMutator mutator);
    std::shared_ptr<const DspParamSnapshot> getParams() const;

    // Stage accessor handles
    ParametricEQ& eq() { return eq_; }
    Crossfeed& crossfeed() { return crossfeed_; }
    LookaheadLimiter& limiter() { return limiter_; }
    ConvolutionReverb& reverb() { return reverb_; }
    SincResampler& resampler() { return resampler_; }
    SpatialPanner& panner() { return panner_; }
    DsdDecoder& dsdDecoder() { return dsdDecoder_; }
    HarmonicSaturation& saturation() { return saturation_; }
    StereoWidth& stereoWidth() { return stereoWidth_; }
    LoudnessContour& loudnessContour() { return loudnessContour_; }
    SubCrossover& subCrossover() { return subCrossover_; }
    DynamicEQ& dynamicEq() { return dynamicEq_; }

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
    void triggerStageAutoDegrade(uint32_t stageBitmask) {
        autoDegradedStages_.fetch_or(stageBitmask);
        if (stageBitmask == STAGE_SATURATION) {
            stageGainCompensation_.store(1.1885f); // ~1.5 dB linear compensation
        }
    }
    void recoverStageAutoDegrade(uint32_t stageBitmask) {
        autoDegradedStages_.fetch_and(~stageBitmask);
        if (stageBitmask == STAGE_SATURATION) {
            stageGainCompensation_.store(1.0f);
        }
    }
    void clearAutoDegradedStages() {
        autoDegradedStages_.store(0);
        stageGainCompensation_.store(1.0f);
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
    void publishParams(std::shared_ptr<const DspParamSnapshot> snapshot);

private:
    void setSampleRateInternal(double sampleRate);
    void applySampleRateLocked(double sampleRate);
    void resetInternal();

    double sampleRate_ = 48000.0;
    std::atomic<uint64_t> snapshotGeneration_{1};
    std::atomic<uint64_t> lastAppliedGeneration_{0};
    std::atomic<uint32_t> autoDegradedStages_{0};

    // Rolling RTF monitor (zero heap allocation, preallocated fixed ring buffer)
    static constexpr int kRtfWindowSize = 20;
    static constexpr int kRtfRecoveryWindowSize = 32;
    static constexpr float RTF_DEGRADE_THRESHOLD = 0.85f;
    static constexpr float RTF_RECOVER_THRESHOLD = 0.45f;
    static constexpr int RECOVERY_HOLD_BLOCKS = 32;
    std::atomic<bool> autoDegradeMonitorEnabled_{true};
    std::atomic<double> simulatedBlockRtf_{-1.0}; // < 0 means measure actual wall-clock
    std::atomic<double> rollingRtf_{0.0};
    std::atomic<float> stageGainCompensation_{0.0f};
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
    // Real-time zero-allocation PRNG for TPDF dither
    uint32_t ditherPrngState1_ = 0x12345678;
    uint32_t ditherPrngState2_ = 0x87654321;
    double smoothedReplayGain_ = 1.0;
    double targetReplayGain_ = 1.0;

    inline float generateTpdf() {
        ditherPrngState1_ ^= ditherPrngState1_ << 13;
        ditherPrngState1_ ^= ditherPrngState1_ >> 17;
        ditherPrngState1_ ^= ditherPrngState1_ << 5;

        ditherPrngState2_ ^= ditherPrngState2_ << 13;
        ditherPrngState2_ ^= ditherPrngState2_ >> 17;
        ditherPrngState2_ ^= ditherPrngState2_ << 5;

        const float r1 = static_cast<float>(ditherPrngState1_) * (1.0f / 4294967296.0f);
        const float r2 = static_cast<float>(ditherPrngState2_) * (1.0f / 4294967296.0f);
        return r1 - r2;
    }

    // Phase 1 DSP-expansion stages (all zero-latency IIR/pointwise, so they
    // contribute nothing to getPipelineLatencyFrames)
    HarmonicSaturation saturation_;
    StereoWidth stereoWidth_;
    LoudnessContour loudnessContour_;
    SubCrossover subCrossover_;
    DynamicEQ dynamicEq_;
};
