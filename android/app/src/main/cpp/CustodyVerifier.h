// android/app/src/main/cpp/CustodyVerifier.h
#pragma once

#include <atomic>
#include <cstdint>

/// Lock-free window capture of the PCM that enters and leaves the DSP chain, so
/// "bit-exact output" can be MEASURED (digest of the actual bytes on both sides)
/// instead of inferred from which stages happen to be enabled.
///
/// Real-time rules, identical to AudioDspEngine's: the render thread only
/// memcpy()s into storage allocated at construction and advances atomics. No
/// allocation, no mutex, no exceptions. arm()/disarm()/take() run on a control
/// thread. Because the buffers are never reallocated or freed, a disarm that
/// races an in-flight block is harmless: that block finishes writing into valid
/// memory and its transition to Ready is a compare-exchange, so it either
/// publishes a complete window or does nothing.
class CustodyVerifier {
public:
    static constexpr int kChannels = 2;
    static constexpr int kMaxFrames = 4096;
    static constexpr int kCapacity = kMaxFrames * kChannels;

    struct Window {
        const float* input = nullptr;   // interleaved, frames * kChannels floats
        const float* output = nullptr;
        int frames = 0;
        double sampleRate = 0.0;
        uint32_t activeStages = 0;
        uint64_t snapshotGeneration = 0;
        bool bitPerfectAtArm = false;
        bool bypassCompareAtArm = false;
        /// A non-stereo block, a mid-window channel change, or a disarm cut the
        /// window short. The digests still describe exactly what was captured,
        /// but a short window must not be presented as a full-chain proof.
        bool truncated = false;
    };

    CustodyVerifier();

    /// Control thread. Captures `frames` on both sides of the chain (clamped to
    /// kMaxFrames). Returns false if a window is already armed or ready.
    ///
    /// The snapshot generation and stage mask are NOT parameters here: the
    /// engine re-stamps generation on every publish (AudioDspEngine::
    /// publishParams bumps snapshotGeneration_), so a caller-supplied value
    /// would describe a snapshot that never runs. The verifier latches both from
    /// the first block it captures and abandons the window if either changes.
    bool arm(int frames, double sampleRate, bool bitPerfect, bool bypassCompare);
    void disarm();

    /// Control thread. Claims a finished window; the pointer pair stays valid
    /// until the next arm() writes over it, so consume before re-arming.
    /// Returns false when no complete window is waiting.
    bool take(Window& out);

    bool isArmed() const { return state_.load(std::memory_order_acquire) == State::Armed; }
    bool isReady() const { return state_.load(std::memory_order_acquire) == State::Ready; }
    int capturedFrames() const { return framesCompleted_.load(std::memory_order_acquire); }

    /// Render thread. `generation`/`activeStages` identify the parameter
    /// snapshot the block actually ran under: a window that spans a DSP change
    /// describes two different chains, so it is flagged short rather than
    /// reported as a clean measurement of either.
    ///
    /// Returns the capture token for this block, or 0 when nothing was captured.
    /// The token must be handed back to captureOutput(): arm() increments the
    /// epoch, so a block that entered under a previous window can never write
    /// into the one that replaced it — disarm()+arm() between that block's input
    /// and output halves would otherwise splice two windows together.
    uint64_t captureInput(const float* buffer, int frames, int channels,
                          uint64_t generation, uint32_t activeStages);
    void captureOutput(const float* buffer, int frames, int channels, uint64_t token);

private:
    enum class State : int { Idle = 0, Armed = 1, Ready = 2 };

    /// Publishes whatever has been captured as the window result.
    void finishWindow();
    /// Marks the window unusable-as-proof and publishes the partial capture.
    void abandon();

    float input_[kCapacity];
    float output_[kCapacity];

    std::atomic<State> state_{State::Idle};
    std::atomic<int> targetFrames_{0};
    std::atomic<int> framesCompleted_{0};
    std::atomic<uint64_t> epoch_{0};
    /// Set by arm(), consumed by the render thread at the head of a block. The
    /// write cursor stays render-thread-private so a re-arm can never race it.
    std::atomic<bool> resetRequested_{false};

    double windowSampleRate_ = 0.0;
    bool windowBitPerfect_ = false;
    bool windowBypassCompare_ = false;
    bool windowTruncated_ = false;

    // Render-thread private. Never written by a control thread. Latched from the
    // first captured block so the window describes exactly one chain state.
    uint64_t windowGeneration_ = 0;
    uint32_t windowStages_ = 0;
    bool latched_ = false;
    int writeFrames_ = 0;
    int pendingFrames_ = 0;
    int pendingOffset_ = 0;
    uint64_t pendingToken_ = 0;
};

/// Scope guard so every return path inside processInterleaved() — including the
/// bit-perfect and A/B bypass shortcuts — closes the capture pair. Without it a
/// bypass block would capture an input half and never an output half.
struct CustodyCaptureGuard {
    CustodyVerifier* verifier;
    const float* buffer;
    int frames;
    int channels;
    uint64_t token;

    CustodyCaptureGuard(CustodyVerifier* v, float* buf, int f, int c,
                        uint64_t generation, uint32_t activeStages)
        : verifier(v), buffer(buf), frames(f), channels(c), token(0) {
        if (v != nullptr) token = v->captureInput(buf, f, c, generation, activeStages);
    }
    ~CustodyCaptureGuard() {
        if (token != 0) verifier->captureOutput(buffer, frames, channels, token);
    }

    CustodyCaptureGuard(const CustodyCaptureGuard&) = delete;
    CustodyCaptureGuard& operator=(const CustodyCaptureGuard&) = delete;
};
