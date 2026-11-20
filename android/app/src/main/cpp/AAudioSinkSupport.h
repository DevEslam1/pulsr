// Host-testable pieces of AAudioSink. Kept free of AAudio/Android headers so
// the native test suite can exercise them without an Android toolchain.
#pragma once

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdint>

#include "SinkQuantizer.h"

namespace pulsr {

/**
 * Disconnection state machine shared by AAudioSink::Write and
 * RecoverDisconnected.
 *
 * The flag may only be cleared by an opener that actually brought a stream up
 * (TryOpen clears it after requestStart succeeds). A recovery ladder that
 * fails on every rung must leave the flag set so Write's backoff/retry keeps
 * running; clearing it up front would silently park the sink forever.
 */
class AAudioRecoveryState {
public:
    bool isDisconnected() const {
        return disconnected_.load(std::memory_order_acquire);
    }

    void markDisconnected() {
        disconnected_.store(true, std::memory_order_release);
    }

    /** Called by TryOpen only after the new stream is started. */
    void markConnected() {
        disconnected_.store(false, std::memory_order_release);
    }

    /**
     * Runs one recovery ladder. `open` must attempt the ladder and return
     * true only when a stream is live (TryOpen already cleared the flag in
     * that case). On failure the flag stays set.
     */
    template <typename OpenFn>
    bool attempt(OpenFn&& open) {
        const bool recovered = open();
        if (!recovered) {
            markDisconnected();
        }
        return recovered;
    }

private:
    std::atomic<bool> disconnected_{false};
};

/**
 * Stream state staged while a new AAudio stream is being opened. It must only
 * be published after requestStart() succeeds; a failed start leaves the sink's
 * existing counters and connection state untouched.
 */
struct AAudioOpenState {
    int64_t framesWritten = 0;
    int64_t framesWrittenBase = 0;
    int64_t readBase = 0;
    int64_t readOffset = 0;
    int32_t lastXRunCount = 0;
    int32_t initialBufferFrames = 0;
    bool connected = false;
};

/** Publishes `staged` into `live` only when the stream actually started. */
inline bool CommitOpenState(bool startSucceeded, const AAudioOpenState& staged,
                            AAudioOpenState& live) {
    if (!startSucceeded) return false;
    live = staged;
    return true;
}

/**
 * Scales interleaved 24-bit packed PCM by `gain`, saturating to 24-bit.
 *
 * Scaling moves every sample off the integer grid it was quantized to, so this
 * multiply is itself a requantization. Rounding it plainly would put a
 * signal-correlated error after the engine's dither stage — the exact thing
 * SinkQuantizer exists to avoid — so the requantization is dithered. Callers
 * that skip this path entirely (exclusive/bit-perfect run at unity gain) are
 * unaffected.
 */
inline void ApplyI24PackedVolume(uint8_t* data, int32_t byteCount, float gain,
                                 SinkDitherState& st) {
    const int32_t numSamples = byteCount / 3;
    for (int32_t i = 0; i < numSamples; ++i) {
        uint8_t* p = data + i * 3;
        const int32_t raw = static_cast<int32_t>(p[0]) |
                            (static_cast<int32_t>(p[1]) << 8) |
                            (static_cast<int32_t>(static_cast<int8_t>(p[2])) << 16);
        const int64_t scaled = QuantizeLsbWithDither(
            static_cast<double>(raw) * static_cast<double>(gain),
            -8388608, 8388607, st);
        p[0] = static_cast<uint8_t>(scaled & 0xFF);
        p[1] = static_cast<uint8_t>((scaled >> 8) & 0xFF);
        p[2] = static_cast<uint8_t>((scaled >> 16) & 0xFF);
    }
}

/**
 * Scales interleaved 16-bit PCM by `gain`, saturating to the int16 range.
 * Same requantization rule as the 24-bit path above.
 */
inline void ApplyI16Volume(int16_t* data, int32_t sampleCount, float gain,
                           SinkDitherState& st) {
    for (int32_t i = 0; i < sampleCount; ++i) {
        const double scaled = static_cast<double>(data[i]) * static_cast<double>(gain);
        data[i] = static_cast<int16_t>(
            QuantizeLsbWithDither(scaled, -32768, 32767, st));
    }
}

/**
 * Scales interleaved 32-bit PCM by `gain`, saturating to the int32 range.
 * Native 32-bit int carries true 32-bit data (unlike float32), so 1-LSB TPDF
 * dither keeps requantization noise decorrelated when scaling off-grid.
 */
/**
 * Whether the sink may scale this stream at all.
 *
 * A bit-perfect stream and a DoP carrier must stay byte-identical: scaling
 * requantizes the payload and rewrites the 0x05/0xFA marker, which makes a DAC
 * lose DoP framing. The decision is a policy input (the caller's declaration),
 * never inferred from the 24-bit container, because that container also
 * carries ordinary PCM that must keep its volume control.
 *
 * Pure so the rule is host-testable without an AAudio device.
 */
inline bool SinkVolumeAllowed(bool bitPerfect, bool dopCarrier) {
    return !bitPerfect && !dopCarrier;
}

inline void ApplyI32Volume(int32_t* data, int32_t sampleCount, float gain,
                           SinkDitherState& st) {
    for (int32_t i = 0; i < sampleCount; ++i) {
        const double scaled = static_cast<double>(data[i]) * static_cast<double>(gain);
        data[i] = static_cast<int32_t>(
            QuantizeLsbWithDither(scaled, -2147483648LL, 2147483647LL, st));
    }
}

/**
 * Per-frame linear gain ramp for the sink's soft volume.
 *
 * The sink samples volume_ once per Write(); multiplying a whole block by the
 * new value turns a slider drag into one hard gain step per buffer (5-20 ms at
 * typical block sizes) — the textbook zipper artefact. These variants walk the
 * gain from gainStart towards gainEnd across the block instead, and the caller
 * returns the endpoint as the next block's start so the seam is continuous.
 *
 * The step advances once per *frame*, not per sample: every channel of a frame
 * shares one gain, so a ramp cannot shift the stereo image or modulate the
 * inter-channel balance. Requantization follows the constant-gain versions
 * above (TPDF only when the product leaves the integer grid), so a zero-slope
 * ramp is bit-identical to them.
 */
inline void ApplyI16VolumeRamp(int16_t* data, int32_t frameCount,
                               int32_t channelCount, float gainStart,
                               float gainEnd, SinkDitherState& st) {
    if (frameCount <= 0 || channelCount <= 0) return;
    const float step = (gainEnd - gainStart) / static_cast<float>(frameCount);
    float gain = gainStart;
    int16_t* frame = data;
    for (int32_t f = 0; f < frameCount; ++f) {
        for (int32_t c = 0; c < channelCount; ++c) {
            frame[c] = static_cast<int16_t>(QuantizeLsbWithDither(
                static_cast<double>(frame[c]) * static_cast<double>(gain),
                -32768, 32767, st));
        }
        frame += channelCount;
        gain += step;
    }
}

inline void ApplyI24PackedVolumeRamp(uint8_t* data, int32_t frameCount,
                                     int32_t channelCount, float gainStart,
                                     float gainEnd, SinkDitherState& st) {
    if (frameCount <= 0 || channelCount <= 0) return;
    const float step = (gainEnd - gainStart) / static_cast<float>(frameCount);
    float gain = gainStart;
    uint8_t* p = data;
    for (int32_t f = 0; f < frameCount; ++f) {
        for (int32_t c = 0; c < channelCount; ++c) {
            const int32_t raw = static_cast<int32_t>(p[0]) |
                                (static_cast<int32_t>(p[1]) << 8) |
                                (static_cast<int32_t>(static_cast<int8_t>(p[2])) << 16);
            const int64_t scaled = QuantizeLsbWithDither(
                static_cast<double>(raw) * static_cast<double>(gain),
                -8388608, 8388607, st);
            p[0] = static_cast<uint8_t>(scaled & 0xFF);
            p[1] = static_cast<uint8_t>((scaled >> 8) & 0xFF);
            p[2] = static_cast<uint8_t>((scaled >> 16) & 0xFF);
            p += 3;
        }
        gain += step;
    }
}

inline void ApplyI32VolumeRamp(int32_t* data, int32_t frameCount,
                               int32_t channelCount, float gainStart,
                               float gainEnd, SinkDitherState& st) {
    if (frameCount <= 0 || channelCount <= 0) return;
    const float step = (gainEnd - gainStart) / static_cast<float>(frameCount);
    float gain = gainStart;
    int32_t* frame = data;
    for (int32_t f = 0; f < frameCount; ++f) {
        for (int32_t c = 0; c < channelCount; ++c) {
            frame[c] = static_cast<int32_t>(QuantizeLsbWithDither(
                static_cast<double>(frame[c]) * static_cast<double>(gain),
                -2147483648LL, 2147483647LL, st));
        }
        frame += channelCount;
        gain += step;
    }
}

// Computes stream buffer capacity headroom in frames. The builder capacity is
// an immutable ceiling for AAudioStream_setBufferSizeInFrames, so clamping it
// to targetBufferMs prevents CheckAndAdaptBuffer from expanding on XRuns.
inline int32_t ComputeStreamCapacityFrames(int32_t sampleRate,
                                           int32_t targetBufferMs) {
    if (sampleRate <= 0 || targetBufferMs <= 0) return 0;
    const int64_t targetFrames =
        (static_cast<int64_t>(sampleRate) * targetBufferMs) / 1000;
    if (targetFrames <= 0) return 0;
    const int64_t headroom =
        std::max<int64_t>(targetFrames * 4, static_cast<int64_t>(sampleRate) / 2);
    const int64_t ceiling =
        std::max<int64_t>(targetFrames, static_cast<int64_t>(sampleRate) * 2);
    return static_cast<int32_t>(std::min(headroom, ceiling));
}

// Computes initial AAudio buffer size in frames. Starting at only burst*2
// (~2 ms at 48 kHz) starves exclusive streams fed by non-real-time Java
// threads, so start at max(burst*4, targetFrames/2) instead. A small target
// must not clamp that headroom away — an 8 ms target (384 frames at 48 kHz)
// cannot absorb one 4-burst wake-up gap from the Java writer — so the floor is
// min(targetFrames, burst*4): a small target starts at burst*4 (16 ms with a
// 192-frame burst), a deep one (120 ms) still starts at half of it. The result
// never exceeds the reported capacity.
inline int32_t ComputeInitialBufferFrames(int32_t burst, int32_t capacity,
                                          int32_t targetFrames) {
    if (capacity <= 0 && targetFrames <= 0) {
        return burst > 0 ? burst * 4 : 0;
    }
    const int32_t burstHeadroom = burst > 0 ? burst * 4 : 0;
    int32_t desired = burst > 0 ? burstHeadroom : capacity;
    if (targetFrames > 0) {
        const int32_t halfTarget = targetFrames / 2;
        if (halfTarget > desired) desired = halfTarget;
        const int32_t targetFloor = std::min(targetFrames, burstHeadroom);
        if (desired < targetFloor) desired = targetFloor;
    }
    if (capacity > 0 && desired > capacity) {
        desired = capacity;
    }
    return desired;
}

// Determines whether an exclusive AAudio stream should prefer PERFORMANCE_MODE_NONE
// (deep buffering) over PERFORMANCE_MODE_LOW_LATENCY.
//
// In Android AAudio, EXCLUSIVE + LOW_LATENCY forces the hardware MMAP endpoint,
// which locks buffer capacity to 2-4 bursts (8-16 ms) and disables adaptive
// expansion on XRuns. For non-realtime Java writers (Media3/ExoPlayer), an
// 8-16 ms MMAP buffer inevitably starves during GC pauses or thread scheduling jitter.
// Music playback targets >= 50 ms require PERFORMANCE_MODE_NONE to obtain deep
// kernel ring buffering and full capacity headroom.
inline bool ShouldPreferDeepBuffer(int32_t targetBufferMs, bool lowLatency) {
    if (!lowLatency) return true;
    return targetBufferMs >= 50;
}

}  // namespace pulsr
