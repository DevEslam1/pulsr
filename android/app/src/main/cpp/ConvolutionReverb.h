// android/app/src/main/cpp/ConvolutionReverb.h
#pragma once

#include "DspParams.h"
#include "FftUtil.h"
#include "SincResampler.h"
#include <vector>
#include <array>
#include <cmath>
#include <memory>
#include <string>
#include <atomic>
#include <mutex>
// FIX M-15: <thread>/<condition_variable> removed with the dead worker thread.

enum class ReverbPreset {
    Studio = 0,
    Room = 1,
    Chamber = 2,
    Hall = 3,
    ConcertHall = 4,
    Cathedral = 5,
    Plate = 6,
    Spring = 7,
    Custom = 8
};

enum class ReverbThreadingMode {
    SingleThread = 0,
    MultiThread = 1,
    Auto = 2
};

class ConvolutionReverb {
public:
    static constexpr int PARTITION_SIZE = 512;
    static constexpr int FFT_SIZE = PARTITION_SIZE * 2; // 1024
    static constexpr int MAX_PREDELAY_SAMPLES = 153600; // 153,600 samples max predelay capacity (R2)
    static constexpr int MAX_PREALLOC_PARTITIONS = 512;
    static constexpr int MAX_HQ_DRY_DELAY = PARTITION_SIZE * 16 + 1024; // 9216

    ConvolutionReverb();
    ~ConvolutionReverb();
    void setSampleRate(double sampleRate, bool updateIr = true);
    void setPreset(ReverbPreset preset);
    void setWetDry(double wet); // 0.0 (dry) to 1.0 (wet)
    void setPredelay(double predelayMs); // 0.0 to 150.0 ms
    void setDamping(double damping); // 0.0 (bright) to 1.0 (dark/damped)
    void setCrossChannel(double crossChannel) { crossChannel_ = std::clamp(crossChannel, 0.0, 1.0); }
    double getCrossChannel() const { return crossChannel_; }
    void setEnabled(bool enabled) {
        enabled_.store(enabled, std::memory_order_relaxed);
        targetEnabledMix_.store(enabled ? 1.0f : 0.0f, std::memory_order_release);
    }
    bool isEnabled() const {
        return targetEnabledMix_.load(std::memory_order_relaxed) > 1e-4f;
    }
    bool isRamping() const {
        return (smoothedEnabledMix_ > 1e-4f) || (targetEnabledMix_.load(std::memory_order_relaxed) > 1e-4f);
    }
    void setThreadingMode(ReverbThreadingMode mode) { threadingMode_.store(mode, std::memory_order_relaxed); }
    ReverbThreadingMode getThreadingMode() const { return threadingMode_.load(std::memory_order_relaxed); }
    void applyParams(const ReverbParamSet& params);
    void reset();

    bool loadCustomIR(const float* irInterleaved, int frames, int channels, double irSampleRate = 0.0);
    std::shared_ptr<const PreparedIr> getPreparedIr() const { return preparedIr_; }
    ReverbPreset getPreset() const { return preset_; }

    int getReverbLatencyFrames() const {
        if (!isEnabled() && !isRamping()) return 0;
        return reverbLatencyFrames_.load(std::memory_order_relaxed);
    }

    void prepareForBlockSize(int maxFrames);
    void process(const float* inL, const float* inR, float* outL, float* outR, int frames);
    void processInterleaved(float* buffer, int frames, int channels = 2);

    void drainRetiredIrs();

    void ensurePartitionCapacity(int numPartitions);
    size_t getHistoryPartitionCount() const {
        return static_cast<size_t>(historyPartitionCount_.load(std::memory_order_acquire));
    }
    size_t getHistoryAllocatedBytes() const;
    // Item 7 diagnostics (control thread): prepared IRs still retained by the
    // retire ring, the overflow vector and the emergency stash. Zero after
    // drainRetiredIrs().
    size_t getRetiredPendingCount() const;
    // Item 2/8 diagnostics (control thread): the wet path is still blending a
    // previous IR into the current one.
    bool isIrCrossfadeActiveForTesting() const { return isIrCrossfadeActive(); }

private:
    // Item 7: bounded, non-blocking retirement. The audio thread may never block
    // on overflowMutex_ nor destroy a PreparedIr, so the ring is backed by a
    // two-slot emergency stash that drainRetiredIrs() always empties. Retention
    // bound: kMaxRetired (512) ring entries + retiredOverflow_ (reserve 2048) +
    // kMaxEmergencyRetained (2) stashed IRs.
    static constexpr int kMaxRetired = 512;
    static constexpr int kMaxEmergencyRetained = 2;
    std::shared_ptr<const PreparedIr> retiredRing_[kMaxRetired];
    std::atomic<int> retiredHead_{0};
    std::atomic<int> retiredTail_{0};
    std::shared_ptr<const PreparedIr> emergencyIr_[kMaxEmergencyRetained];
    // Item 7: the diagnostics getter (const) also needs the stash guard.
    mutable std::atomic_flag emergencyLock_ = ATOMIC_FLAG_INIT;
    mutable std::mutex overflowMutex_;
    std::vector<std::shared_ptr<const PreparedIr>> retiredOverflow_;
    mutable std::mutex drainMutex_;

    void updatePreparedIr();
    void setPreparedIrPtr(std::shared_ptr<const PreparedIr> ir);
    void retireIr(std::shared_ptr<const PreparedIr> ir);
    bool isIrCrossfadeActive() const {
        return crossfadeIr_ != nullptr && irCrossfadeTotal_ > 0 &&
               irCrossfadeSamples_ < irCrossfadeTotal_;
    }
    void advanceIrCrossfade();
    void accumulatePartitionLeft(const PreparedIr* ir,
                                 std::vector<FftUtil::Complex>& accum,
                                 int numPartitions);
    void accumulatePartitionRight(const PreparedIr* ir,
                                  std::vector<FftUtil::Complex>& accum,
                                  int numPartitions);
    void pushWetFifo(float l, float r);
    bool popWetFifo(float& l, float& r);
    void preparePartitions();
    void ensurePredelayCapacity();
    void ensureScratchCapacity(int frames);
    void processCore(const float* inL, const float* inR, float* outL, float* outR, int frames,
                     float startMix, float mixStep, double startWet, double wetStep);

    double sampleRate_ = 48000.0;
    double coreRate_ = 48000.0;
    ReverbPreset preset_ = ReverbPreset::Room;
    double targetWet_ = 0.20;
    double smoothedWet_ = 0.20;
    double predelayMs_ = 0.0;
    float targetPredelaySamples_ = 0.0f;
    float smoothedPredelaySamples_ = 0.0f;
    double damping_ = 0.5;
    std::atomic<bool> enabled_{false};
    std::atomic<float> targetEnabledMix_{0.0f};
    float smoothedEnabledMix_{0.0f};
    int irCrossfadeSamples_{0};
    int irCrossfadeTotal_{0};
    std::atomic<ReverbThreadingMode> threadingMode_{ReverbThreadingMode::Auto};

    // Fixed-rate wet path resamplers for sample rates > 48kHz
    SincResampler wetInResampler_;
    SincResampler wetOutResampler_;
    std::vector<float> resampleInL_;
    std::vector<float> resampleInR_;
    std::vector<float> resampleWetL_;
    std::vector<float> resampleWetR_;
    std::vector<float> resampleOutL_;
    std::vector<float> resampleOutR_;
    // Absorbs the +/-1 sample rational-resampler jitter across blocks instead
    // of repeating/dropping the last wet sample.
    static constexpr int WET_FIFO_SAMPLES = 64;
    float wetFifoL_[WET_FIFO_SAMPLES] = {};
    float wetFifoR_[WET_FIFO_SAMPLES] = {};
    int wetFifoWrite_ = 0;
    int wetFifoRead_ = 0;
    int wetFifoCount_ = 0;
    // Linear-phase / partition latency alignment for surround channels.
    static constexpr int MAX_SURROUND_CHANNELS = 6;
    float surroundDelay_[MAX_SURROUND_CHANNELS][MAX_HQ_DRY_DELAY] = {};
    int surroundDelayIdx_ = 0;

    // Prepared IR snapshot pointer
    std::shared_ptr<const PreparedIr> preparedIr_;
    // Old live IR kept alive while the wet output crossfades to the new one.
    std::shared_ptr<const PreparedIr> crossfadeIr_;
    std::vector<FftUtil::Complex> accumFreqL2_;
    std::vector<FftUtil::Complex> accumFreqR2_;

    // Latency of the currently prepared IR, mirrored to an atomic so the
    // control-thread latency query never races the audio-thread IR swap.
    std::atomic<int> reverbLatencyFrames_{0};

    // Overlap-save previous block history (P samples)
    std::vector<float> prevBlockL_;
    std::vector<float> prevBlockR_;

    // Current input block (P samples)
    std::vector<float> inputBlockL_;
    std::vector<float> inputBlockR_;
    int inputBlockPos_ = 0;

    // Overlap-save input history ring buffer: [MAX_PREALLOC_PARTITIONS][FFT_SIZE].
    // Item 8: every slot is allocated up front (kHistoryRingSlots) and addressed
    // with the FIXED modulus MAX_PREALLOC_PARTITIONS, so growing the effective
    // partition count for a longer IR can never reinterpret a slot that already
    // holds history from a different modulus. `historyPartitionCount_` only
    // bounds how many partitions the accumulator reads; it does not change the
    // ring geometry, which is what makes an IR growth mid-stream a clean tail
    // fade-in instead of a burst of stale blocks.
    static constexpr int kHistoryRingSlots = MAX_PREALLOC_PARTITIONS;
    std::array<std::vector<FftUtil::Complex>, MAX_PREALLOC_PARTITIONS> inputHistoryFreqL_;
    std::array<std::vector<FftUtil::Complex>, MAX_PREALLOC_PARTITIONS> inputHistoryFreqR_;
    std::atomic<int> historyPartitionCount_{0};
    bool historyRingAllocated_ = false;
    int historyHead_ = 0;

    // Direct convolution ring buffers for short IRs (<= 1024)
    std::vector<float> directRingL_;
    std::vector<float> directRingR_;
    int directPos_ = 0;

    // Predelay circular buffer
    std::vector<float> predelayRingL_;
    std::vector<float> predelayRingR_;
    int predelayWritePos_ = 0;

    // Dry-path delay line (PARTITION_SIZE) used in partitioned mode to time-align dry with wet
    std::vector<float> dryDelayL_;
    std::vector<float> dryDelayR_;
    int dryDelayPos_ = 0;

    // FIX M-14: native-rate dry delay for the >48kHz wet path. That path streams
    // the wet signal through a 48kHz core (down-resample -> partitioned/direct
    // convolution -> up-resample), so the native dry must be delayed by the
    // whole chain's latency (reverbLatencyFrames_) to avoid a comb/doubling at
    // mix<1. Capacity covers the worst case: 16x SR scaling of the 512-sample
    // partition plus resampler group delay. Pre-allocated; never grown on the
    // audio thread.
    std::vector<float> hqDryL_;
    std::vector<float> hqDryR_;
    int hqDryPos_ = 0;


    // Working buffers
    std::vector<FftUtil::Complex> fftWorkL_;
    std::vector<FftUtil::Complex> fftWorkR_;
    std::vector<FftUtil::Complex> accumFreqL_;
    std::vector<FftUtil::Complex> accumFreqR_;

    // Scratch buffers for allocation-free processInterleaved
    std::vector<float> scratchInL_;
    std::vector<float> scratchInR_;
    std::vector<float> scratchOutL_;
    std::vector<float> scratchOutR_;

    // Cached raw custom IR for rate resynchronization
    std::vector<float> rawCustomIr_;
    int rawCustomFrames_ = 0;
    int rawCustomChannels_ = 2;
    double rawCustomSampleRate_ = 48000.0;
    double crossChannel_ = 0.0;

    void processLeftChannelPartition(int numPartitions);
    void processRightChannelPartition(int numPartitions);

    // FIX M-14: recompute the reported reverb latency (native frames), including
    // SR scaling and the wet-path resampler group delay for the >48kHz path.
    void updateReverbLatency();
};
