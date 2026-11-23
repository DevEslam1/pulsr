// android/app/src/main/cpp/UsbPullRenderer.h
//
// Pull-based renderer for the USB Audio Class output path.
//
// ---------------------------------------------------------------------------
// HONEST SCOPE
// ---------------------------------------------------------------------------
// This class is a bounded byte ring plus bookkeeping. It cannot create audio
// data that a real-time producer has not produced yet: when the ring is empty
// the only options are to emit silence and count an underrun. What it does
// remove is producer-clock *steering*: the producer pushes whole frames and
// the consumer pulls whole frames, so a packet payload is a byte-for-byte copy
// of what the producer wrote. No resampling, no gain, no requantization, no
// partial-frame packing ever happens here. That is what lets the USB sink claim
// bit-exact payloads.
//
// Clock drift is therefore not corrected inside the ring. The caller closes
// the loop externally (async feedback endpoint -> packet cadence, or the
// UsbAsrcClockSync fallback) and checks the result with driftPpm().
//
// ---------------------------------------------------------------------------
// THREADING
// ---------------------------------------------------------------------------
// Single producer / single consumer. write() is called from the audio producer
// thread, pull()/pullExact() from the USB service thread. Indices are
// cache-line separated and exchanged with acquire/release, so no lock is ever
// taken. write() and pull*() do not allocate, do not block, and do not call
// into the platform.
//
// Configure(), reset() and flush() are transport/control operations: they must
// not race with write()/pull*(). They may allocate (Configure only).
//
// ---------------------------------------------------------------------------
// STARTUP GATE
// ---------------------------------------------------------------------------
// Draining before the ring has reached 80% of the configured buffer is the
// fastest way to turn a start-up scheduling hiccup into a permanent underrun
// train. Until prefillSatisfied() latches, pull*() returns 0 frames and does
// not count an underrun: there is nothing wrong yet, playback simply has not
// started. flush() (seek) re-arms the gate; reset() clears everything.
#ifndef PULSR_USB_PULL_RENDERER_H_
#define PULSR_USB_PULL_RENDERER_H_

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <vector>

namespace pulsr {

class UsbPullRenderer {
public:
    // Prefill threshold: 80% of the configured (requested) buffer duration.
    static constexpr int kPrefillNumerator = 4;
    static constexpr int kPrefillDenominator = 5;

    UsbPullRenderer() = default;
    ~UsbPullRenderer() = default;

    // Indices and a ring buffer are not copyable/movable: two copies would
    // silently share a producer/consumer pair. Reconfigure in place instead.
    UsbPullRenderer(const UsbPullRenderer&) = delete;
    UsbPullRenderer& operator=(const UsbPullRenderer&) = delete;
    UsbPullRenderer(UsbPullRenderer&&) = delete;
    UsbPullRenderer& operator=(UsbPullRenderer&&) = delete;

    // Allocates the ring once. sampleRate: 8000..1536000 Hz, channels: 1..32,
    // bytesPerSample: 1..8, bufferMs: 1..60000. Returns false (and leaves the
    // object unconfigured) on bad geometry or an implausible allocation.
    // The ring capacity is rounded up to a power of two frames and is always
    // >= the requested duration, i.e. "multi-second" for bufferMs >= 2000.
    bool Configure(int sampleRate, int channels, int bytesPerSample, int bufferMs);

    bool isConfigured() const { return configured_; }

    // Control-thread operations; the stream must be quiesced.
    // reset(): drop buffered audio AND all counters/state.
    // flush(): drop buffered audio only (seek); counters survive, the prefill
    //          gate is re-armed, pause state is untouched. Safe to call while
    //          the consumer thread is active: advances an atomic watermark and
    //          monotonic read index without zeroing indices or racing copyOut().
    void reset();
    void flush();

    // Paused: pull*() returns 0 frames without consuming data and without
    // counting an underrun. The producer may keep writing (dropout protection
    // still applies), which means a long pause can legitimately fill the ring.
    void setPaused(bool paused);
    bool paused() const { return paused_.load(std::memory_order_acquire); }

    // Producer side. Whole frames only. Returns false when the block does not
    // fit, in which case *nothing* is written and overrunEvents() increments by
    // one: the caller drops the block (or retries later) and never observes a
    // torn frame. src may be null only when frames == 0.
    bool write(const void* src, int frames);

    // Consumer side. Copies up to maxFrames whole frames, returns how many were
    // really available (capped at maxFrames) and never zero-fills. The short
    // return is the signal to the caller that the producer is behind; it is not
    // counted as an underrun (only pullExact() is a hard "must fill" contract).
    int pull(void* dst, int maxFrames);

    // Consumer side. Copies whole frames; if the ring cannot satisfy the whole
    // request the remainder of dst is zero-filled and exactly one underrun
    // event is counted for the call. dst may be null only when frames == 0.
    // Returns the number of real frames copied (< frames on underrun).
    int pullExact(void* dst, int frames);

    // Ring occupancy in milliseconds (rounded down) and in whole frames.
    int fillMs() const;
    size_t availableFrames() const;

    // Latched once occupancy reaches 80% of the configured buffer; cleared by
    // flush()/reset().
    bool prefillSatisfied() const { return prefillSatisfied_.load(std::memory_order_acquire); }

    size_t capacityFrames() const { return capacityFrames_; }
    // The duration asked for in Configure(), which may differ from the rounded
    // power-of-two capacity.
    size_t configuredFrames() const { return requestedFrames_; }

    uint64_t underrunEvents() const { return underrunEvents_.load(std::memory_order_relaxed); }
    uint64_t overrunEvents() const { return overrunEvents_.load(std::memory_order_relaxed); }
    // Real (non-silence) frames handed to the consumer.
    uint64_t framesPulled() const { return framesPulled_.load(std::memory_order_relaxed); }

    // Producer-minus-consumer rate error in parts per million, for telemetry and
    // for asserting that a steering loop actually converged. Positive means the
    // producer is ahead (the ring is filling). Rounds to nearest; clamps to
    // +/-1,000,000 (i.e. +/-100%). Returns 0 when consumerFrames <= 0.
    static int driftPpm(int64_t producerFrames, int64_t consumerFrames);

    int sampleRate() const { return sampleRate_; }
    int channels() const { return channels_; }
    int bytesPerSample() const { return bytesPerSample_; }
    int frameBytes() const { return frameBytes_; }
    int bufferMs() const { return bufferMs_; }

private:
    // Consumer-side copy without counters; returns frames copied. May be
    // called only when the prefill gate and pause gate have been passed.
    // Sets *flushed = true if a concurrent flush() invalidated the copy.
    size_t copyOut(uint8_t* dst, size_t frames, bool* flushed = nullptr);
    // Monotonically advances readIndex_ to at least `target` (never moves backward).
    uint64_t advanceReadIndexAtLeast(uint64_t target) const;

    std::vector<uint8_t> ring_;   // capacityFrames_ * frameBytes_, Configure only
    int sampleRate_ = 0;
    int channels_ = 0;
    int bytesPerSample_ = 0;
    int frameBytes_ = 0;
    int bufferMs_ = 0;
    size_t requestedFrames_ = 0;
    size_t capacityFrames_ = 0;
    size_t capacityMask_ = 0;
    size_t prefillFrames_ = 0;
    bool configured_ = false;

    // Producer-owned cache line(s).
    alignas(64) std::atomic<uint64_t> writeIndex_{0};
    alignas(64) std::atomic<uint64_t> overrunEvents_{0};

    // Consumer-owned cache line(s).
    alignas(64) mutable std::atomic<uint64_t> readIndex_{0};
    alignas(64) std::atomic<uint64_t> framesPulled_{0};
    // Hazard read index while copyOut() is reading ring_ bytes (UINT64_MAX when idle).
    alignas(64) mutable std::atomic<uint64_t> consumerPin_{UINT64_MAX};
    // Monotonic flush watermark: frames < flushWatermark_ are pre-seek and discarded.
    alignas(64) std::atomic<uint64_t> flushWatermark_{0};

    // Written by one side, read by the other.
    alignas(64) std::atomic<uint64_t> underrunEvents_{0};
    alignas(64) std::atomic<bool> paused_{false};
    alignas(64) std::atomic<bool> prefillSatisfied_{false};
};

// The lock-free claim is load-bearing: a non-lock-free atomic would take a
// hidden lock inside write()/pull(), which is not allowed on the audio thread.
static_assert(std::atomic<uint64_t>::is_always_lock_free,
              "USB pull renderer indices must stay lock-free");
static_assert(std::atomic<size_t>::is_always_lock_free,
              "USB pull renderer bookkeeping must stay lock-free");
static_assert(std::atomic<bool>::is_always_lock_free,
              "USB pull renderer pause/prefill flags must stay lock-free");

}  // namespace pulsr

#endif  // PULSR_USB_PULL_RENDERER_H_
