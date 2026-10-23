// android/app/src/main/cpp/LookaheadLimiter.h
#pragma once

#if defined(__FAST_MATH__)
#error "-ffast-math leaked into the DSP build — check CMake / gradle compiler flags"
#endif

#include "DspParams.h"
#include <cmath>
#include <algorithm>
#include <cassert>
#include <atomic>

class LookaheadLimiter {
public:
    static constexpr int MAX_LOOKAHEAD_SAMPLES = 16384;
    static_assert((MAX_LOOKAHEAD_SAMPLES & (MAX_LOOKAHEAD_SAMPLES - 1)) == 0,
                  "MAX_LOOKAHEAD_SAMPLES must be a power of two");
    static_assert(MAX_LOOKAHEAD_SAMPLES >= 768 * 20,
                  "MAX_LOOKAHEAD_SAMPLES must accommodate at least 20ms @ 768kHz");

    static constexpr int INTERP_TAPS = 48;
    static constexpr int INTERP_PHASES = 4;
    static constexpr int TAPS_PER_PHASE = INTERP_TAPS / INTERP_PHASES; // 12

    LookaheadLimiter();
    void setSampleRate(double sampleRate);
    void configure(double lookaheadMs, double thresholdDb, double releaseMs, bool truePeakMode = true);
    void setEnabled(bool enabled);
    bool isEnabled() const { return enabled_; }
    void applyParams(const LimiterParamSet& params);
    void reset();

    // The engine inserts/removes this stage around the rest of the chain. Tell
    // the limiter whether the graph still wants it so it can crossfade between
    // the delayed/limited path and the direct signal instead of dropping its
    // lookahead latency abruptly (a 5 ms time jump at the output).
    void setProcessingActive(bool active);
    bool isDraining() const {
        return bypassPending_ || (bypassTarget_ == 0.0f && bypassMix_ > 0.0f);
    }

    // Read from the control thread (getPipelineLatencyFrames) while the audio
    // thread writes lookaheadSamples_ in configure(); mirror it to an atomic so
    // the query never races the audio thread.
    int getLatencyFrames() const { return latencyFramesAtomic_.load(std::memory_order_relaxed); }
    float getCurrentGainReductionDb() const { return gainReductionDb_.load(std::memory_order_relaxed); }

    void process(float* L, float* R, int frames);
    void processMono(float* inOut, int frames);
    void processInterleaved(float* buffer, int frames, int channels = 2);

    float estimateTruePeak(const float* history);

private:

    double sampleRate_ = 48000.0;
    double lookaheadMs_ = 5.0;
    double thresholdDb_ = -0.2;
    double releaseMs_ = 50.0;
    bool truePeakMode_ = true;
    bool enabled_ = false;

    std::atomic<bool> paramsChanged_{false};
    LimiterParamSet pendingParams_;

    int lookaheadSamples_ = 240;
    // Atomic mirror of lookaheadSamples_ for the control-thread latency query.
    std::atomic<int> latencyFramesAtomic_{240};
    float threshold_ = 0.977237f; // pow(10, -0.2 / 20)
    float fastReleaseCoeff_ = 0.998f;
    float slowReleaseCoeff_ = 0.9995f;
    float avgEnergy_ = 0.0f;
    float transientWeight_ = 0.0f;
    float envelope_ = 1.0f;
    std::atomic<float> gainReductionDb_{0.0f};

    static constexpr int MAX_CHANNELS = 8;
    float delayBuf_[MAX_CHANNELS][MAX_LOOKAHEAD_SAMPLES] = {};
    float gainBuf_[MAX_LOOKAHEAD_SAMPLES] = {};
    int writeIdx_ = 0;
    float minGain_ = 1.0f;

    // Sliding-window monotonic deque for O(1) minimum tracking
    struct DequeNode {
        float gain;
        int64_t idx;
    };
    DequeNode deque_[MAX_LOOKAHEAD_SAMPLES] = {};
    int64_t dequeHead_ = 0;
    int64_t dequeTail_ = 0;
    int64_t sampleCount_ = 0;

    // Bypass/insertion crossfade. bypassMix_ is the weight of the processed
    // (delayed) path: 1 = fully limited, 0 = fully dry. When the stage is
    // inserted after being dormant the mix ramps up so stale delay-line
    // contents never leak into the output; when it is removed the mix ramps
    // down over one lookahead window so the latency change is inaudible.
    float bypassMix_ = 1.0f;
    float bypassTarget_ = 1.0f;
    int bypassHoldRemaining_ = 0;
    bool enableFading_ = false;
    bool bypassPending_ = false;
    bool processingActive_ = false;
    bool disabledSinceProcess_ = false;

    void resetTransientState() {
        dequeHead_ = 0;
        dequeTail_ = 0;
        sampleCount_ = 0;
        envelope_ = 1.0f;
        minGain_ = 1.0f;
        avgEnergy_ = 0.0f;
        transientWeight_ = 0.0f;
        gainReductionDb_.store(0.0f, std::memory_order_relaxed);
    }

    void beginEnableTransition() {
        resetTransientState();
        // The first lookahead window of the delay line still holds samples
        // from before the bypass. Keep outputting the current input, scaled by
        // the limiter's instantaneous gain, until those slots are overwritten,
        // then crossfade to the fresh delayed stream. Muting would click and
        // replaying the stale delay line would leak old audio.
        bypassHoldRemaining_ = lookaheadSamples_;
        bypassMix_ = 0.0f;
        bypassTarget_ = 1.0f;
        enableFading_ = true;
        bypassPending_ = false;
        disabledSinceProcess_ = false;
    }

    void syncPendingParams();

    inline float advanceBypassMix() {
        const int window = std::max(1, lookaheadSamples_);
        const float step = 1.0f / static_cast<float>(window);
        if (bypassMix_ < bypassTarget_) {
            bypassMix_ = std::min(bypassTarget_, bypassMix_ + step);
        } else if (bypassMix_ > bypassTarget_) {
            bypassMix_ = std::max(bypassTarget_, bypassMix_ - step);
        }
        return bypassMix_;
    }

    inline void pushGainDeque(float gain, int64_t idx, int windowSize) {
        constexpr int kMask = MAX_LOOKAHEAD_SAMPLES - 1;
        while (dequeTail_ > dequeHead_ && deque_[(dequeTail_ - 1) & kMask].gain >= gain) {
            dequeTail_--;
        }
        deque_[dequeTail_ & kMask] = { gain, idx };
        dequeTail_++;
        while (dequeHead_ < dequeTail_ && deque_[dequeHead_ & kMask].idx <= idx - windowSize) {
            dequeHead_++;
        }
    }

    inline float getMinGain() const {
        constexpr int kMask = MAX_LOOKAHEAD_SAMPLES - 1;
        return (dequeTail_ > dequeHead_) ? deque_[dequeHead_ & kMask].gain : 1.0f;
    }

    // ITU-R BS.1770-4 4x-oversampling polyphase interpolation table for true-peak detection
    static const float polyphase4x_[INTERP_PHASES][TAPS_PER_PHASE];
};
