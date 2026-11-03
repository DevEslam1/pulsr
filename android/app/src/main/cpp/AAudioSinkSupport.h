// Host-testable pieces of AAudioSink. Kept free of AAudio/Android headers so
// the native test suite can exercise them without an Android toolchain.
#pragma once

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdint>

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

/** Scales interleaved 24-bit packed PCM by `gain`, saturating to 24-bit. */
inline void ApplyI24PackedVolume(uint8_t* data, int32_t byteCount, float gain) {
    const int32_t numSamples = byteCount / 3;
    for (int32_t i = 0; i < numSamples; ++i) {
        uint8_t* p = data + i * 3;
        const int32_t raw = static_cast<int32_t>(p[0]) |
                            (static_cast<int32_t>(p[1]) << 8) |
                            (static_cast<int32_t>(static_cast<int8_t>(p[2])) << 16);
        float v = static_cast<float>(raw) * gain;
        v = std::clamp(v, -8388608.0f, 8388607.0f);
        const int32_t scaled = std::lrintf(v);
        p[0] = static_cast<uint8_t>(scaled & 0xFF);
        p[1] = static_cast<uint8_t>((scaled >> 8) & 0xFF);
        p[2] = static_cast<uint8_t>((scaled >> 16) & 0xFF);
    }
}

}  // namespace pulsr
