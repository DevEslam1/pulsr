// android/app/src/test/cpp/test_custody_verifier.cpp
//
// The chain-of-custody certificate claims bit-exactness only when it can prove
// the bytes leaving the DSP chain equal the bytes entering it. These cases pin
// down that the measurement (a) reports exactness for a bypassed chain, (b)
// actually reports non-exactness when a stage moves samples — otherwise the
// certificate would be trivially true — and (c) never splices or races windows
// when a control thread re-arms mid-block.
#include "../../main/cpp/AudioDspEngine.h"
#include "../../main/cpp/CustodyVerifier.h"

#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <memory>
#include <thread>
#include <vector>

namespace {

int gFailures = 0;

void check(bool ok, const char* what) {
    if (!ok) {
        std::cout << "[FAIL] " << what << std::endl;
        ++gFailures;
    }
}

std::vector<float> makeSignal(int frames, int channels) {
    std::vector<float> buf(static_cast<size_t>(frames) * channels);
    for (int i = 0; i < frames; ++i) {
        for (int ch = 0; ch < channels; ++ch) {
            const double phase = (i + ch * 37) * 0.031;
            buf[static_cast<size_t>(i) * channels + ch] =
                static_cast<float>(0.61 * std::sin(phase) + 0.17 * std::sin(phase * 7.3));
        }
    }
    return buf;
}

bool bitIdentical(const float* a, const float* b, size_t floats) {
    return std::memcmp(a, b, floats * sizeof(float)) == 0;
}

std::shared_ptr<DspParamSnapshot> baseSnapshot(uint64_t generation) {
    auto snap = std::make_shared<DspParamSnapshot>();
    snap->sampleRate = 48000.0;
    snap->activeStages = 0;
    snap->generation = generation;
    return snap;
}

std::unique_ptr<AudioDspEngine> makeEngine() {
    // Engine holds stages by value; a stack instance risks the 1 MB default
    // thread stack (same reason test_bypass_transparency heap-allocates).
    return std::make_unique<AudioDspEngine>();
}

bool feedBlocks(AudioDspEngine& engine, const std::vector<float>& signal, int frames,
                int channels, int blocks) {
    for (int b = 0; b < blocks; ++b) {
        std::vector<float> work = signal;
        if (engine.processInterleaved(work.data(), frames, channels) != frames) return false;
    }
    return true;
}

}  // namespace

int main() {
    std::cout << "[TEST] Measured chain-of-custody verification..." << std::endl;
    constexpr int kFrames = 512;
    constexpr int kChannels = 2;

    {
        // The headline claim: with the chain bypassed, the captured halves must
        // be byte-identical, measured rather than inferred from the stage mask.
        auto engine = makeEngine();
        auto snap = baseSnapshot(1);
        snap->bitPerfect.enabled = true;
        engine->setSampleRate(snap->sampleRate);
        engine->publishParams(snap);

        check(engine->custody().arm(kFrames * 2, 48000.0, true, false),
              "arm must succeed on an idle verifier");

        const auto input = makeSignal(kFrames, kChannels);
        check(feedBlocks(*engine, input, kFrames, kChannels, 4), "blocks must process");

        CustodyVerifier::Window window;
        check(engine->custody().take(window), "window must complete after 4 blocks");
        check(window.frames == kFrames * 2, "window must cover the requested frames");
        check(!window.truncated, "aligned stereo blocks must not truncate the window");
        check(window.bitPerfectAtArm, "armed bit-perfect flag must survive to take()");
        check(window.snapshotGeneration != 0,
              "the window must latch the generation it actually ran under");
        check(bitIdentical(window.input, window.output,
                           static_cast<size_t>(window.frames) * kChannels),
              "bypassed chain must measure bit-exact");
    }

    {
        // Counter-case: a live stage must break the measurement. Without this the
        // bit-exact check above could pass while the capture silently compared
        // a buffer against itself.
        auto engine = makeEngine();
        auto snap = baseSnapshot(1);
        snap->activeStages = STAGE_EQ;
        snap->eq.enabled = true;
        snap->eq.preampDb = 6.0;
        snap->eq.bands[0].enabled = true;
        snap->eq.bands[0].frequency = 1000.0;
        snap->eq.bands[0].gainDb = 8.0;
        snap->eq.bands[0].q = 1.0;
        snap->eq.bands[0].type = FilterType::Peaking;
        snap->eq.bandCount = 1;
        engine->setSampleRate(snap->sampleRate);
        engine->publishParams(snap);

        check(engine->custody().arm(kFrames, 48000.0, false, false),
              "arm must succeed for a DSP-active window");
        const auto input = makeSignal(kFrames, kChannels);
        check(feedBlocks(*engine, input, kFrames, kChannels, 1), "EQ blocks must process");

        CustodyVerifier::Window window;
        check(engine->custody().take(window), "single aligned block must complete");
        check(window.frames == kFrames, "window frame count must match the arm request");
        check((window.activeStages & STAGE_EQ) != 0,
              "the latched stage mask must report the EQ that actually ran");
        check(!bitIdentical(window.input, window.output,
                            static_cast<size_t>(window.frames) * kChannels),
              "an active EQ must NOT measure as bit-exact");
    }

    {
        // Two engines with identical parameters and identical input must produce
        // an identical output window: that reproducibility is what the
        // certificate reports as the chain digest under active DSP. Comparing
        // two windows from ONE engine would instead measure the filter's carried
        // IIR history, which legitimately differs between runs.
        std::vector<float> first;
        std::vector<float> second;
        for (int pass = 0; pass < 2; ++pass) {
            auto engine = makeEngine();
            auto snap = baseSnapshot(1);
            snap->activeStages = STAGE_EQ;
            snap->eq.enabled = true;
            snap->eq.preampDb = 3.0;
            snap->eq.bandCount = 0;
            engine->setSampleRate(snap->sampleRate);
            engine->publishParams(snap);

            check(engine->custody().arm(kFrames, 48000.0, false, false),
                  "arm must succeed on a fresh engine");
            const auto input = makeSignal(kFrames, kChannels);
            check(feedBlocks(*engine, input, kFrames, kChannels, 1), "pass must process");
            CustodyVerifier::Window window;
            check(engine->custody().take(window), "pass window must complete");
            check(!bitIdentical(window.input, window.output,
                                 static_cast<size_t>(window.frames) * kChannels),
                  "a live preamp gain must move samples on this pass too");
            std::vector<float>& dest = pass == 0 ? first : second;
            dest.assign(window.output, window.output + window.frames * kChannels);
        }
        check(!first.empty(), "the first window must carry captured frames");
        check(first == second, "identical chain state must produce an identical output window");
    }

    {
        // A block larger than the remaining window is captured up to the
        // boundary on BOTH halves, so the comparison stays frame-aligned.
        auto engine = makeEngine();
        auto snap = baseSnapshot(1);
        snap->bitPerfect.enabled = true;
        engine->setSampleRate(snap->sampleRate);
        engine->publishParams(snap);

        check(engine->custody().arm(100, 48000.0, true, false),
              "arm with a short window must succeed");
        const auto input = makeSignal(kFrames, kChannels);
        check(feedBlocks(*engine, input, kFrames, kChannels, 1), "oversized block must process");

        CustodyVerifier::Window window;
        check(engine->custody().take(window), "short window must still complete");
        check(window.frames == 100, "window must stop exactly at the requested frame count");
        check(window.truncated, "an oversized block must be reported as a short window");
        check(bitIdentical(window.input, window.output,
                           static_cast<size_t>(window.frames) * kChannels),
              "partial window halves must stay aligned and bit-exact");
    }

    {
        // Surround layout is outside the verifier's contract: it must refuse the
        // window rather than hash a misaligned stereo interpretation of it.
        CustodyVerifier verifier;
        check(verifier.arm(kFrames, 48000.0, true, false), "arm must succeed");
        const auto input = makeSignal(kFrames, 6);
        const uint64_t token = verifier.captureInput(input.data(), kFrames, 6, 1, 0);
        verifier.captureOutput(input.data(), kFrames, 6, token);
        CustodyVerifier::Window window;
        check(verifier.take(window), "non-stereo abort must still publish a result");
        check(window.truncated && window.frames == 0,
              "non-stereo capture must yield no usable frames");
    }

    {
        // A parameter publish inside a window means the halves do not belong to
        // one chain, so the window must be flagged, not silently merged.
        auto engine = makeEngine();
        auto snap = baseSnapshot(10);
        snap->bitPerfect.enabled = true;
        engine->setSampleRate(snap->sampleRate);
        engine->publishParams(snap);

        check(engine->custody().arm(kFrames * 2, 48000.0, true, false),
              "arm must succeed before a generation change");
        const auto input = makeSignal(kFrames, kChannels);
        check(feedBlocks(*engine, input, kFrames, kChannels, 1), "first block must process");

        auto next = baseSnapshot(11);  // new generation, still bypassed
        engine->publishParams(next);
        check(feedBlocks(*engine, input, kFrames, kChannels, 1), "second block must process");

        CustodyVerifier::Window window;
        check(engine->custody().take(window), "generation change must publish a result");
        check(window.truncated, "a mid-window generation change must invalidate the window");
        check(window.frames == kFrames,
              "invalidated window must keep only the frames from the original chain");
    }

    {
        // Control-side state machine: no double arm, no premature take, and a
        // disarm must not be resurrected by a render thread already mid-block.
        CustodyVerifier verifier;
        CustodyVerifier::Window window;
        check(!verifier.take(window), "take on an idle verifier must fail");
        check(verifier.arm(200, 48000.0, false, false), "first arm must succeed");
        check(!verifier.arm(200, 48000.0, false, false), "second arm must fail");
        check(!verifier.take(window), "take before completion must fail");
        verifier.disarm();
        check(verifier.arm(200, 48000.0, false, false),
              "arm after disarm must be accepted again");

        const auto signal = makeSignal(100, kChannels);
        const uint64_t staleToken = verifier.captureInput(signal.data(), 100, kChannels, 1, 0);
        check(staleToken != 0, "capture under an armed window must return a token");
        verifier.disarm();
        verifier.captureOutput(signal.data(), 100, kChannels, staleToken);
        check(!verifier.take(window), "a disarmed window must never become takeable");
    }

    {
        // Re-arming between one block's input and output halves must not let that
        // block's output land in the replacement window.
        CustodyVerifier verifier;
        CustodyVerifier::Window window;
        const auto signal = makeSignal(kFrames, kChannels);

        check(verifier.arm(kFrames, 48000.0, true, false), "first window must arm");
        const uint64_t firstToken =
            verifier.captureInput(signal.data(), kFrames, kChannels, 5, 0);
        verifier.disarm();
        check(verifier.arm(kFrames, 48000.0, true, false), "replacement window must arm");
        verifier.captureOutput(signal.data(), kFrames, kChannels, firstToken);
        check(!verifier.take(window), "the straddling block must not complete the new window");

        const uint64_t secondToken =
            verifier.captureInput(signal.data(), kFrames, kChannels, 5, 0);
        verifier.captureOutput(signal.data(), kFrames, kChannels, secondToken);
        check(verifier.take(window), "the new window must still complete normally");
        check(window.frames == kFrames, "no frames may leak in from the abandoned window");
        check(bitIdentical(window.input, window.output,
                           static_cast<size_t>(window.frames) * kChannels),
              "replacement window must be a clean bit-exact pair");
    }

    {
        // The window is filled from the render thread while a control thread
        // polls arm/take. Sanitizer builds catch the races here.
        auto engine = makeEngine();
        auto snap = baseSnapshot(1);
        snap->bitPerfect.enabled = true;
        engine->setSampleRate(snap->sampleRate);
        engine->publishParams(snap);

        std::atomic<bool> stop{false};
        std::atomic<int> completed{0};
        std::atomic<int> mismatches{0};

        const auto input = makeSignal(kFrames, kChannels);
        std::thread render([&] {
            while (!stop.load(std::memory_order_relaxed)) {
                std::vector<float> work = input;
                engine->processInterleaved(work.data(), kFrames, kChannels);
            }
        });

        std::thread control([&] {
            for (int attempt = 0; attempt < 40 && !stop.load(std::memory_order_relaxed);
                 ++attempt) {
                if (engine->custody().arm(kFrames, 48000.0, true, false)) {
                    CustodyVerifier::Window window;
                    const auto deadline = std::chrono::steady_clock::now() +
                                          std::chrono::milliseconds(200);
                    while (!engine->custody().take(window)) {
                        if (std::chrono::steady_clock::now() > deadline) break;
                        std::this_thread::yield();
                    }
                    if (window.frames > 0) {
                        ++completed;
                        if (!bitIdentical(window.input, window.output,
                                          static_cast<size_t>(window.frames) * kChannels)) {
                            ++mismatches;
                        }
                    }
                    engine->custody().disarm();
                } else {
                    std::this_thread::yield();
                }
            }
        });

        control.join();
        stop.store(true, std::memory_order_relaxed);
        render.join();

        check(mismatches.load() == 0, "concurrent capture must never report a bypass mismatch");
        check(completed.load() > 0, "control thread must observe at least one completed window");
    }

    if (gFailures != 0) {
        std::cout << "[FAIL] " << gFailures << " custody check(s) failed." << std::endl;
        return 1;
    }
    std::cout << "[PASS] custody windows measure bit-exactness, detect live DSP, "
                 "reject straddled re-arms, and survive concurrent arm/take." << std::endl;
    return 0;
}
