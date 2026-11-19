// android/app/src/test/cpp/test_aaudio_sink_support.cpp
//
// Host-testable AAudioSink helpers: the disconnected-flag state machine and
// packed-24 volume scaling.
#include "../../main/cpp/AAudioSinkSupport.h"

#include <cmath>
#include <cstdint>
#include <iostream>
#include <vector>

namespace {
int gFailures = 0;

void check(bool ok, const char* what) {
    if (!ok) {
        std::cout << "[FAIL] " << what << std::endl;
        ++gFailures;
    }
}

void encodeI24(std::vector<uint8_t>& out, int32_t value) {
    out.push_back(static_cast<uint8_t>(value & 0xFF));
    out.push_back(static_cast<uint8_t>((value >> 8) & 0xFF));
    out.push_back(static_cast<uint8_t>((value >> 16) & 0xFF));
}

int32_t decodeI24(const uint8_t* p) {
    const int32_t raw = static_cast<int32_t>(p[0]) |
                        (static_cast<int32_t>(p[1]) << 8) |
                        (static_cast<int32_t>(static_cast<int8_t>(p[2])) << 16);
    return raw;
}
}  // namespace

int main() {
    std::cout << "[TEST] AAudioSink support helpers..." << std::endl;

    {
        pulsr::AAudioRecoveryState state;
        state.markDisconnected();
        for (int i = 0; i < 3; ++i) {
            const bool recovered = state.attempt([&]() {
                // Simulates a TryOpen rung that fails before a stream is live.
                return false;
            });
            check(!recovered, "failed recovery attempt must report false");
            check(state.isDisconnected(),
                  "failed recovery must leave the disconnected flag set for Write's backoff");
        }
        const bool recovered = state.attempt([&]() {
            state.markConnected();  // TryOpen clears only on success
            return true;
        });
        check(recovered, "successful recovery must report true");
        check(!state.isDisconnected(), "successful recovery must clear the flag");
    }

    {
        // Failed requestStart must not publish any staged stream state; a
        // successful one publishes all of it atomically at the state level.
        pulsr::AAudioOpenState live{};
        live.framesWritten = 111;
        live.framesWrittenBase = 222;
        live.readBase = 333;
        live.readOffset = 444;
        live.lastXRunCount = 5;
        live.connected = true;

        pulsr::AAudioOpenState staged{};
        staged.framesWritten = 999;
        staged.framesWrittenBase = 888;
        staged.readBase = 777;
        staged.readOffset = 666;
        staged.lastXRunCount = 9;
        staged.initialBufferFrames = 256;
        staged.connected = true;

        const pulsr::AAudioOpenState before = live;
        check(!pulsr::CommitOpenState(false, staged, live),
              "failed requestStart must not commit staged state");
        check(live.framesWritten == before.framesWritten &&
                  live.framesWrittenBase == before.framesWrittenBase &&
                  live.readBase == before.readBase &&
                  live.readOffset == before.readOffset &&
                  live.lastXRunCount == before.lastXRunCount,
              "failed requestStart must preserve existing frame counters");

        check(pulsr::CommitOpenState(true, staged, live),
              "successful requestStart must commit staged state");
        check(live.framesWritten == 999 && live.readOffset == 666 &&
                  live.initialBufferFrames == 256,
              "successful requestStart must publish the staged counters");
    }

    {
        std::vector<uint8_t> samples;
        encodeI24(samples, 0x7FFFFF);   // +max
        encodeI24(samples, -0x800000);  // -max
        encodeI24(samples, 0x002000);   // 8192

        auto half = samples;
        // Products that land exactly on the 24-bit grid must not be dithered;
        // only genuine half-LSB results may move by one step.
        pulsr::SinkDitherState dither{};
        pulsr::ApplyI24PackedVolume(half.data(), static_cast<int32_t>(half.size()), 0.5f,
                                    dither);
        // +max is odd, so *0.5 lands exactly between two steps. Plain rounding
        // would always pick the same neighbour and correlate that error with the
        // signal; dithered it is +-1 LSB around the midpoint.
        const int32_t halfMax = decodeI24(&half[0]);
        check(halfMax == 4194303 || halfMax == 4194304,
              "I24 +max * 0.5 stays within 1 LSB of the midpoint");
        check(decodeI24(&half[3]) == -4194304, "I24 -max * 0.5");
        check(decodeI24(&half[6]) == 4096, "I24 +8192 * 0.5");

        auto doubled = samples;
        pulsr::ApplyI24PackedVolume(doubled.data(), static_cast<int32_t>(doubled.size()), 2.0f,
                                    dither);
        check(decodeI24(&doubled[0]) == 0x7FFFFF, "I24 +max saturates at +max");
        check(decodeI24(&doubled[3]) == -0x800000, "I24 -max saturates at -max");
        check(decodeI24(&doubled[6]) == 16384, "I24 +8192 * 2");

        // Policy: a bit-perfect stream and a DoP carrier must never be scaled,
        // while ordinary PCM (including 24-bit) keeps its volume control.
        check(pulsr::SinkVolumeAllowed(false, false),
              "shared PCM may be scaled");
        check(!pulsr::SinkVolumeAllowed(true, false),
              "bit-perfect stream is unity-only");
        check(!pulsr::SinkVolumeAllowed(false, true),
              "DoP carrier is unity-only");
        check(!pulsr::SinkVolumeAllowed(true, true),
              "bit-perfect DoP carrier is unity-only");

        std::vector<int32_t> s32 = {
            0x40000000, 0x40000001, 0x7FFFFFFF, static_cast<int32_t>(0x80000000u)
        };
        auto half32 = s32;
        pulsr::ApplyI32Volume(half32.data(), static_cast<int32_t>(half32.size()), 0.5f, dither);
        check(half32[0] == 0x20000000, "I32 even * 0.5 stays exact");
        check(half32[1] == 0x20000000 || half32[1] == 0x20000001,
              "I32 odd * 0.5 stays within 1 LSB of midpoint");
        auto doubled32 = s32;
        pulsr::ApplyI32Volume(doubled32.data(), static_cast<int32_t>(doubled32.size()), 2.0f, dither);
        check(doubled32[2] == 0x7FFFFFFF, "I32 +max saturates at +max");
        check(doubled32[3] == static_cast<int32_t>(0x80000000u),
              "I32 -max saturates at -max");
    }

    {
        // A zero-slope ramp must be bit-identical to the constant-gain path: the
        // per-frame stepping fixes the step at the block seam, it is not a
        // different quantizer. 4 frames x 2 ch, equal dither seeds, so any
        // difference would come from the sampling of the gain itself.
        const std::vector<int16_t> source = {
            1000, -1000, 32767, -32768, 12345, -23456, 777, -778
        };
        std::vector<int16_t> constant = source;
        std::vector<int16_t> ramped = source;
        pulsr::SinkDitherState constantDither{};
        pulsr::SinkDitherState rampDither{};
        pulsr::ApplyI16Volume(constant.data(), static_cast<int32_t>(constant.size()), 0.5f,
                              constantDither);
        pulsr::ApplyI16VolumeRamp(ramped.data(), 4, 2, 0.5f, 0.5f, rampDither);
        check(constant == ramped,
              "zero-slope I16 ramp must match the constant-gain path sample for sample");
    }

    // Initial AAudio buffer sizing must prevent 2 ms exclusive-mode starvation.
    check(pulsr::ComputeInitialBufferFrames(48, 5760, 5760) == 2880,
          "120 ms target at 48 kHz should prefill 60 ms instead of 2 ms");
    check(pulsr::ComputeInitialBufferFrames(48, 1152, 1152) == 576,
          "24 ms target at 48 kHz should start at 12 ms");
    // An 8 ms target cannot be clamped down to itself: one 4-burst wake-up gap
    // from the non-RT Java writer is already longer than the whole target, so the
    // initial size stays at burst*4 (16 ms at a 192-frame burst).
    check(pulsr::ComputeInitialBufferFrames(192, 24000, 384) == 768,
          "8 ms target at 48 kHz must start at burst*4 (16 ms), not at the target");
    check(pulsr::ComputeInitialBufferFrames(192, 512, 384) == 512,
          "burst*4 headroom for a small target must still respect stream capacity");
    check(pulsr::ComputeInitialBufferFrames(960, 1920, 1152) == 1920,
          "burst*4 headroom must be clamped to the reported capacity");
    check(pulsr::ComputeInitialBufferFrames(960, 480, 0) == 480,
          "initial buffer must never exceed reported stream capacity");
    check(pulsr::ComputeInitialBufferFrames(0, 2048, 4096) == 2048,
          "unknown burst must clamp cleanly to stream capacity");

    // Stream capacity must leave headroom above targetBufferMs for adaptive expansion.
    check(pulsr::ComputeStreamCapacityFrames(48000, 120) == 24000,
          "120 ms target at 48 kHz should allow 500 ms capacity headroom");
    check(pulsr::ComputeStreamCapacityFrames(48000, 200) == 38400,
          "200 ms target at 48 kHz should allow 4x capacity headroom");
    check(pulsr::ComputeStreamCapacityFrames(768000, 800) == 1536000,
          "high sample rate capacity should cap at 2 seconds when above 4x target");
    check(pulsr::ComputeStreamCapacityFrames(48000, 3000) == 144000,
          "capacity must stay at least targetFrames even when target exceeds 2 seconds");
    check(pulsr::ComputeStreamCapacityFrames(48000, 0) == 0,
          "non-positive targetBufferMs leaves builder capacity unset");

    if (gFailures != 0) {
        std::cout << "[FAIL] " << gFailures << " AAudioSink support check(s) failed." << std::endl;
        return 1;
    }
    std::cout << "[PASS] AAudioSink support helpers behave as specified." << std::endl;
    return 0;
}
