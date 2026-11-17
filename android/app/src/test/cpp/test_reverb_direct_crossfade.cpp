// android/app/src/test/cpp/test_reverb_direct_crossfade.cpp
//
// Item 2 regression: switching between two DIRECT (<= 1024 tap) IRs while wet
// must complete the crossfade and retire the old kernel.
//
// The old direct path gated the blend on
//     crossfadeIr_->totalTaps <= totalTaps
// and called advanceIrCrossfade() only inside that gate. Loading a SHORTER IR
// (1000 -> 500 taps) therefore skipped the blend entirely: no advance, so
// isIrCrossfadeActive() stayed true forever, the old kernel kept being convolved
// at weight 1 and its shared_ptr was pinned for the lifetime of the stream.
//
// The fix convolves the old kernel over the shared span min(oldTaps, totalTaps)
// and always advances the fade once per frame, so the cosine blend reaches the
// new kernel in 15 ms and retireIr() releases the old one.
#include "../../main/cpp/ConvolutionReverb.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <vector>

namespace {

int gFailures = 0;

void check(bool ok, const char* what) {
    if (!ok) {
        std::printf("[FAIL] %s\n", what);
        ++gFailures;
    }
}

constexpr double kPi = 3.14159265358979323846;

// Short exponential-decay noise-ish IR; deterministic and non-trivial, so a
// truncated kernel genuinely differs from the full one.
std::vector<float> makeIr(int taps, float scale) {
    std::vector<float> ir(static_cast<size_t>(taps) * 2, 0.0f);
    for (int i = 0; i < taps; ++i) {
        const float decay = std::exp(-static_cast<float>(i) / (taps * 0.35f));
        const float v = scale * decay * ((i % 7 == 0) ? 0.7f : 0.25f);
        ir[static_cast<size_t>(i) * 2] = v;
        ir[static_cast<size_t>(i) * 2 + 1] = v * 0.9f;
    }
    return ir;
}

double rms(const std::vector<float>& v, size_t begin, size_t end) {
    if (end <= begin) return 0.0;
    double sum = 0.0;
    for (size_t i = begin; i < end; ++i) sum += static_cast<double>(v[i]) * v[i];
    return std::sqrt(sum / static_cast<double>(end - begin));
}

}  // namespace

int main() {
    std::printf("[TEST] ConvolutionReverb direct-IR crossfade completion...\n");

    ConvolutionReverb reverb;
    reverb.setSampleRate(48000.0);
    reverb.setEnabled(true);
    reverb.setWetDry(1.0);
    reverb.setPredelay(0.0);

    const int longTaps = 1000;
    const int shortTaps = 500;
    auto longIr = makeIr(longTaps, 0.001f);
    auto shortIr = makeIr(shortTaps, 0.001f);

    check(reverb.loadCustomIR(longIr.data(), longTaps, 2),
          "the 1000-tap direct IR must load");
    check(reverb.getHistoryPartitionCount() == 0,
          "a <= 1024 tap IR must stay on the direct path");
    reverb.reset();

    const int block = 64;
    std::vector<float> inL(block);
    std::vector<float> inR(block);
    std::vector<float> outL(block);
    std::vector<float> outR(block);
    std::vector<float> tail;
    double phase = 0.0;

    const auto render = [&](int blocks, std::vector<float>* capture) {
        for (int b = 0; b < blocks; ++b) {
            for (int i = 0; i < block; ++i) {
                const float s = static_cast<float>(0.5 * std::sin(phase));
                inL[i] = s;
                inR[i] = s;
                phase += 2.0 * kPi * 220.0 / 48000.0;
            }
            reverb.process(inL.data(), inR.data(), outL.data(), outR.data(), block);
            if (capture != nullptr) {
                capture->insert(capture->end(), outL.begin(), outL.end());
            }
        }
    };

    // Wet steady state with the long kernel.
    render(16, nullptr);
    tail.clear();
    render(16, &tail);
    const double steadyRms = rms(tail, 0, tail.size());
    check(steadyRms > 1e-4, "the wet path must produce audible output before the swap");

    // Swap to a SHORTER kernel while fully wet: this is the case the old gate
    // rejected outright.
    check(reverb.loadCustomIR(shortIr.data(), shortTaps, 2),
          "the 500-tap direct IR must load while wet");
    check(reverb.isIrCrossfadeActiveForTesting(),
          "a direct-to-direct swap under a live wet path must start a crossfade");

    std::vector<float> swapTail;
    int framesUntilDone = -1;
    int frames = 0;
    for (int b = 0; b < 64; ++b) {
        render(1, &swapTail);
        frames += block;
        if (framesUntilDone < 0 && !reverb.isIrCrossfadeActiveForTesting()) {
            framesUntilDone = frames;
        }
    }
    const int fadeFrames = static_cast<int>(48000.0 * 0.015);  // 720
    std::printf("      crossfade finished after %d frames (fade=%d, processed=%d)\n",
                framesUntilDone, fadeFrames, frames);
    check(framesUntilDone > 0,
          "the crossfade must complete instead of pinning the old IR forever");
    check(framesUntilDone <= fadeFrames + block,
          "the crossfade must complete within 15 ms of frames");

    // Continuity: the swap must not drop or double the wet level.
    const double swapRms = rms(swapTail, 0, static_cast<size_t>(fadeFrames * 2));
    std::printf("      rms before %.5f / during %.5f\n", steadyRms, swapRms);
    check(swapRms > steadyRms * 0.5 && swapRms < steadyRms * 1.5,
          "the wet level must stay continuous across the swap");

    float peak = 0.0f;
    for (float v : swapTail) {
        check(std::isfinite(v), "the swap must not produce non-finite output");
        peak = std::max(peak, std::abs(v));
    }
    check(peak < 1.0f, "the swap must not overshoot full scale");

    // The old kernel must have been retired, and the control thread must be able
    // to drain it (item 7 keeps that drain bounded).
    check(reverb.getRetiredPendingCount() > 0,
          "the replaced kernel must be retained for the control thread");
    reverb.drainRetiredIrs();
    check(reverb.getRetiredPendingCount() == 0,
          "drainRetiredIrs must empty every retained kernel");

    if (gFailures != 0) {
        std::printf("[FAIL] %d direct-IR crossfade check(s) failed.\n", gFailures);
        return 1;
    }
    std::printf("[PASS] Direct-IR crossfade completes and retires the old kernel.\n");
    return 0;
}
