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
#include <cstring>
#include <iterator>

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
    // The true-peak interpolation is centered between history[5] and history[6]
    // (i.e. 5..6 samples behind the write head). The output delay is
    // lookaheadSamples_ + FILTER_DELAY; the gain deque window (lookahead + 2)
    // keeps the min-gain entry alive until the detected peak leaves readIdx.
    static constexpr int FILTER_DELAY = 6;

    LookaheadLimiter();
    void setSampleRate(double sampleRate);
    void configure(double lookaheadMs, double thresholdDb, double releaseMs, bool truePeakMode = true);
    void setEnabled(bool enabled);
    bool isEnabled() const { return enabled_.load(std::memory_order_relaxed); }
    void applyParams(const LimiterParamSet& params);
    void reset();

    // The engine inserts/removes this stage around the rest of the chain. Tell
    // the limiter whether the graph still wants it so it can crossfade between
    // the delayed/limited path and the direct signal instead of dropping its
    // lookahead latency abruptly (a 5 ms time jump at the output).
    void setProcessingActive(bool active);
    bool isDraining() const {
        return bypassPending_ ||
               (bypassTarget_.load(std::memory_order_relaxed) == 0.0f &&
                bypassMix_.load(std::memory_order_relaxed) > 0.0f);
    }

    // Read from the control thread (getPipelineLatencyFrames) while the audio
    // thread writes lookaheadSamples_ in configure(); the mirror is atomic so
    // the query never races the render thread. A fully bypassed/dormant stage
    // reports zero latency.
    int getLatencyFrames() const {
        if (!enabled_.load(std::memory_order_relaxed) ||
            (bypassTarget_.load(std::memory_order_relaxed) == 0.0f &&
             bypassMix_.load(std::memory_order_relaxed) <= 0.0f)) {
            return 0;
        }
        return latencyFramesAtomic_.load(std::memory_order_relaxed);
    }
    float getCurrentGainReductionDb() const { return gainReductionDb_.load(std::memory_order_relaxed); }

    /** Sample index of the min-gain entry at the deque head. */
    int64_t getMinGainSampleIndex() const {
        constexpr int kMask = MAX_LOOKAHEAD_SAMPLES - 1;
        return (dequeTail_ > dequeHead_) ? deque_[dequeHead_ & kMask].idx
                                         : sampleCount_ - 1;
    }

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
    std::atomic<bool> enabled_{false};

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
    // Earliest output index of a peak the current attack ramp must cover. When
    // a newer, lower target arrives while already attacking, the deadline is
    // kept so the earlier peak cannot slip over the ceiling.
    int64_t attackDeadlineIdx_ = 0;
    bool attackActive_ = false;
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
    std::atomic<float> bypassMix_{1.0f};
    std::atomic<float> bypassTarget_{1.0f};
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
        attackDeadlineIdx_ = 0;
        attackActive_ = false;
        avgEnergy_ = 0.0f;
        transientWeight_ = 0.0f;
        gainReductionDb_.store(0.0f, std::memory_order_relaxed);
    }

    void beginEnableTransition() {
        resetTransientState();
        // Discard every sample/state from the previous session: a stale delay
        // line would convolve old audio with the new stream, and stale gainBuf_
        // entries could keep the envelope pinned low after re-enable.
        std::memset(delayBuf_, 0, sizeof(delayBuf_));
        std::fill(std::begin(gainBuf_), std::end(gainBuf_), 1.0f);
        std::memset(deque_, 0, sizeof(deque_));
        // Keep outputting the current input, scaled by the limiter's
        // instantaneous gain, until the window is fresh, then crossfade to the
        // delayed stream.
        bypassHoldRemaining_ = lookaheadSamples_ + FILTER_DELAY;
        bypassMix_.store(0.0f, std::memory_order_relaxed);
        bypassTarget_.store(1.0f, std::memory_order_relaxed);
        enableFading_ = true;
        bypassPending_ = false;
        disabledSinceProcess_ = false;
    }

    void syncPendingParams();

    inline float advanceBypassMix() {
        const int window = std::max(1, lookaheadSamples_ + FILTER_DELAY);
        const float step = 1.0f / static_cast<float>(window);
        const float target = bypassTarget_.load(std::memory_order_relaxed);
        float mix = bypassMix_.load(std::memory_order_relaxed);
        if (mix < target) {
            mix = std::min(target, mix + step);
        } else if (mix > target) {
            mix = std::max(target, mix - step);
        }
        bypassMix_.store(mix, std::memory_order_relaxed);
        return mix;
    }

    inline void pushGainDeque(float gain, int64_t idx, int windowSize) {
        constexpr int kMask = MAX_LOOKAHEAD_SAMPLES - 1;
        // Strict '>': keep the OLDEST entry among equal gains. Popping equals
        // would move the head to the newest sample each block and reset the
        // attack ramp's remaining time, turning the intended linear ramp into
        // an exponential approach that never reaches target before the peak.
        while (dequeTail_ > dequeHead_ && deque_[(dequeTail_ - 1) & kMask].gain > gain) {
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
