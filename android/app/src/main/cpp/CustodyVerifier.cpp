// android/app/src/main/cpp/CustodyVerifier.cpp
#include "CustodyVerifier.h"

#include <cstring>

CustodyVerifier::CustodyVerifier() {
    // Touch the capture storage once so the pages are resident before the first
    // armed block; a page fault inside processInterleaved() is an underrun.
    std::memset(input_, 0, sizeof(input_));
    std::memset(output_, 0, sizeof(output_));
}

bool CustodyVerifier::arm(int frames, double sampleRate, bool bitPerfect,
                          bool bypassCompare) {
    // arm()/disarm()/take() are control-thread calls and the caller serializes
    // them (AudioEffectsPlugin holds stateLock), so a plain check is enough —
    // the render thread only ever transitions Armed -> Ready.
    if (state_.load(std::memory_order_acquire) != State::Idle) return false;
    if (frames <= 0) frames = kMaxFrames;
    if (frames > kMaxFrames) frames = kMaxFrames;

    windowSampleRate_ = sampleRate;
    windowBitPerfect_ = bitPerfect;
    windowBypassCompare_ = bypassCompare;
    windowTruncated_ = false;

    targetFrames_.store(frames, std::memory_order_relaxed);
    framesCompleted_.store(0, std::memory_order_relaxed);
    resetRequested_.store(true, std::memory_order_relaxed);

    // New epoch first, then Armed: a render thread that reads Armed must also see
    // the epoch this window owns, and one still holding the previous epoch gets
    // rejected by captureOutput()'s token check.
    epoch_.fetch_add(1, std::memory_order_release);

    // Release pairs with the render thread's acquire load of state_: everything
    // above is visible before the window is considered live.
    state_.store(State::Armed, std::memory_order_release);
    return true;
}

void CustodyVerifier::disarm() {
    State armed = State::Armed;
    // Only an in-progress window is abandoned; a captured one stays takeable so
    // a caller that disarms defensively does not lose the result.
    state_.compare_exchange_strong(armed, State::Idle, std::memory_order_acq_rel);
}

bool CustodyVerifier::take(Window& out) {
    State ready = State::Ready;
    if (!state_.compare_exchange_strong(ready, State::Idle, std::memory_order_acq_rel)) {
        return false;
    }
    out.input = input_;
    out.output = output_;
    out.frames = framesCompleted_.load(std::memory_order_acquire);
    out.sampleRate = windowSampleRate_;
    out.activeStages = windowStages_;
    out.snapshotGeneration = windowGeneration_;
    out.bitPerfectAtArm = windowBitPerfect_;
    out.bypassCompareAtArm = windowBypassCompare_;
    out.truncated = windowTruncated_;
    return true;
}

void CustodyVerifier::finishWindow() {
    framesCompleted_.store(writeFrames_, std::memory_order_release);
    State armed = State::Armed;
    // CAS, not store: after disarm() the caller has abandoned the window, and a
    // render thread still inside a block must not resurrect it.
    state_.compare_exchange_strong(armed, State::Ready, std::memory_order_release);
}

void CustodyVerifier::abandon() {
    windowTruncated_ = true;
    pendingFrames_ = 0;
    pendingToken_ = 0;
    finishWindow();
}

uint64_t CustodyVerifier::captureInput(const float* buffer, int frames, int channels,
                                       uint64_t generation, uint32_t activeStages) {
    if (!buffer || frames <= 0) return 0;
    if (state_.load(std::memory_order_acquire) != State::Armed) return 0;

    const uint64_t epoch = epoch_.load(std::memory_order_acquire);

    if (resetRequested_.load(std::memory_order_relaxed)) {
        resetRequested_.store(false, std::memory_order_relaxed);
        writeFrames_ = 0;
        latched_ = false;
    }

    if (channels != kChannels) {
        abandon();
        return 0;
    }

    if (!latched_) {
        // First block of this window defines the chain state it certifies.
        latched_ = true;
        windowGeneration_ = generation;
        windowStages_ = activeStages;
    } else if (generation != windowGeneration_ || activeStages != windowStages_) {
        // The halves would belong to two different chains; certify neither.
        abandon();
        return 0;
    }

    const int target = targetFrames_.load(std::memory_order_relaxed);
    const int avail = target - writeFrames_;
    if (avail <= 0) {
        finishWindow();
        return 0;
    }

    // Both halves always cover the identical frame range of the identical block,
    // so a block that does not fit the window is captured up to the boundary and
    // the window is flagged short rather than losing the pairing.
    const int takeFrames = (frames <= avail) ? frames : avail;
    std::memcpy(input_ + static_cast<size_t>(writeFrames_) * kChannels, buffer,
                static_cast<size_t>(takeFrames) * kChannels * sizeof(float));
    pendingFrames_ = takeFrames;
    pendingOffset_ = writeFrames_;
    pendingToken_ = epoch;
    if (takeFrames < frames) windowTruncated_ = true;
    return epoch;
}

void CustodyVerifier::captureOutput(const float* buffer, int frames, int channels,
                                    uint64_t token) {
    const int pending = pendingFrames_;
    const int offset = pendingOffset_;
    pendingFrames_ = 0;
    pendingToken_ = 0;
    if (pending <= 0 || token == 0) return;  // input side skipped this block
    if (token != static_cast<uint64_t>(epoch_.load(std::memory_order_acquire))) {
        return;  // a re-arm happened mid-block; nothing to close in this window
    }
    if (state_.load(std::memory_order_acquire) != State::Armed) return;
    if (!buffer || frames < pending || channels != kChannels) {
        windowTruncated_ = true;
        finishWindow();
        return;
    }

    std::memcpy(output_ + static_cast<size_t>(offset) * kChannels, buffer,
                static_cast<size_t>(pending) * kChannels * sizeof(float));
    writeFrames_ += pending;

    if (windowTruncated_ || writeFrames_ >= targetFrames_.load(std::memory_order_relaxed)) {
        finishWindow();
    }
}
