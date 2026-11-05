// android/app/src/test/cpp/test_transport_gain.cpp
//
// The transport gain (crossfade/sleep curve x profile transition fade) moved
// from a Java post-chain multiply into AudioDspEngine::processInterleaved,
// applied after the limiter/safety stage and BEFORE the dither/noise-shaping
// stage. Applying gain after dither scales the shaped quantisation noise and
// breaks the shaper transfer function. These cases pin the placement down.
#include "../../main/cpp/AudioDspEngine.h"
#include <cmath>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <memory>
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

bool bitIdentical(const std::vector<float>& a, const std::vector<float>& b) {
    return a.size() == b.size() &&
           std::memcmp(a.data(), b.data(), a.size() * sizeof(float)) == 0;
}

std::shared_ptr<DspParamSnapshot> baseSnapshot() {
    auto snap = std::make_shared<DspParamSnapshot>();
    snap->sampleRate = 48000.0;
    snap->activeStages = 0;
    snap->headphoneSafety.enabled = false;
    return snap;
}

std::unique_ptr<AudioDspEngine> makeEngine() {
    return std::make_unique<AudioDspEngine>();
}

// True when every sample sits on the 16-bit quantisation grid (floats written
// as k/32768 by the native dither stage round-trip near-exactly).
bool onGrid16(const std::vector<float>& buf, double tol = 1e-3) {
    for (float v : buf) {
        const double scaled = static_cast<double>(v) * 32768.0;
        if (std::abs(scaled - std::rint(scaled)) > tol) return false;
    }
    return true;
}

} // namespace

int main() {
    std::cout << "[TEST] Transport gain placement (pre-dither, all paths)..." << std::endl;

    const int frames = 512;
    const int channels = 2;
    const float gain = 0.3f; // deliberately not a power of two

    {
        // Normal path: gain must be applied BEFORE the 16-bit dither, so the
        // output sits on the 16-bit grid and equals input*gain within ~1 LSB.
        // A post-dither gain would leave 0.3*k/32768 off-grid samples.
        auto engine = makeEngine();
        auto snap = baseSnapshot();
        snap->activeStages = STAGE_DITHER;
        snap->dither.enabled = true;
        snap->dither.targetBitDepth = 16;
        engine->setSampleRate(snap->sampleRate);
        engine->publishParams(snap);

        const auto input = makeSignal(frames, channels);
        std::vector<float> gains(static_cast<size_t>(frames), gain);
        auto work = input;
        check(engine->processInterleaved(work.data(), frames, channels, gains.data()) == frames,
              "gain block must preserve frame count");
        check(onGrid16(work), "output must sit on the 16-bit grid (gain applied pre-dither)");
        // Noise-shaped dither legitimately deviates per-sample: error feedback
        // is clamped to +/-0.49 LSB, TPDF adds +/-1 LSB, rounding +/-0.5 LSB.
        double maxErr = 0.0, sumSq = 0.0;
        for (size_t i = 0; i < work.size(); ++i) {
            const double err = std::abs(static_cast<double>(work[i]) -
                                        static_cast<double>(input[i]) * gain);
            maxErr = std::max(maxErr, err);
            sumSq += err * err;
        }
        const double rmsErr = std::sqrt(sumSq / static_cast<double>(work.size()));
        check(maxErr < 2.6 / 32768.0, "output must equal input*gain within the dither bound");
        check(rmsErr < 1.2 / 32768.0, "RMS error must stay near 1 LSB (no gain mismatch)");
    }

    {
        // Per-frame ramp: gain varies linearly 1.0 -> 0.0 across the block and
        // every frame must track its own gain.
        auto engine = makeEngine();
        auto snap = baseSnapshot();
        snap->activeStages = STAGE_DITHER;
        snap->dither.enabled = true;
        snap->dither.targetBitDepth = 16;
        engine->setSampleRate(snap->sampleRate);
        engine->publishParams(snap);

        const auto input = makeSignal(frames, channels);
        std::vector<float> gains(static_cast<size_t>(frames));
        for (int f = 0; f < frames; ++f) {
            gains[f] = 1.0f - static_cast<float>(f) / (frames - 1);
        }
        auto work = input;
        engine->processInterleaved(work.data(), frames, channels, gains.data());
        double maxErr = 0.0, sumSq = 0.0;
        for (int f = 0; f < frames; ++f) {
            for (int ch = 0; ch < channels; ++ch) {
                const size_t i = static_cast<size_t>(f) * channels + ch;
                const double err = std::abs(static_cast<double>(work[i]) -
                                            static_cast<double>(input[i]) * gains[f]);
                maxErr = std::max(maxErr, err);
                sumSq += err * err;
            }
        }
        check(maxErr < 2.6 / 32768.0, "per-frame ramp gain must track each frame's gain");
        check(std::sqrt(sumSq / static_cast<double>(work.size())) < 1.2 / 32768.0,
              "ramp RMS error must stay near 1 LSB");
        check(onGrid16(work), "ramped output must still sit on the 16-bit grid");
    }

    {
        // nullptr gains must stay fully transparent (existing contract).
        auto engine = makeEngine();
        auto snap = baseSnapshot();
        engine->setSampleRate(snap->sampleRate);
        engine->publishParams(snap);
        const auto input = makeSignal(frames, channels);
        auto work = input;
        engine->processInterleaved(work.data(), frames, channels, nullptr);
        check(bitIdentical(work, input), "null transport gains must be bit-identical");
    }

    {
        // Bit-perfect bypass: gains ride on the bypassed bytes; null gains keep
        // the sample-identical contract.
        auto engine = makeEngine();
        auto snap = baseSnapshot();
        snap->bitPerfect.enabled = true;
        engine->setSampleRate(snap->sampleRate);
        engine->publishParams(snap);

        const auto input = makeSignal(frames, channels);
        auto work = input;
        engine->processInterleaved(work.data(), frames, channels, nullptr);
        check(bitIdentical(work, input), "bit-perfect with null gains must be sample-identical");
        check(engine->wasLastBlockBitPerfect(), "bit-perfect flag must be reported");

        std::vector<float> gains(static_cast<size_t>(frames), gain);
        work = input;
        engine->processInterleaved(work.data(), frames, channels, gains.data());
        bool scaled = true;
        for (size_t i = 0; i < work.size(); ++i) {
            if (work[i] != input[i] * gain) { scaled = false; break; }
        }
        check(scaled, "bit-perfect bypass must apply the transport gain exactly");
    }

    {
        // A/B bypass-compare path: gains must still render (applied after the
        // safety stage on that path).
        auto engine = makeEngine();
        auto snap = baseSnapshot();
        snap->bypassCompare.enabled = true;
        snap->bypassCompare.autoGainMatch = false;
        snap->bypassCompare.gainCompensationLinear = 1.0;
        engine->setSampleRate(snap->sampleRate);
        engine->publishParams(snap);

        const auto input = makeSignal(frames, channels);
        std::vector<float> gains(static_cast<size_t>(frames), gain);
        auto work = input;
        engine->processInterleaved(work.data(), frames, channels, gains.data());
        double maxErr = 0.0;
        for (size_t i = 0; i < work.size(); ++i) {
            maxErr = std::max(maxErr, std::abs(static_cast<double>(work[i]) -
                                               static_cast<double>(input[i]) * gain));
        }
        check(maxErr < 1e-6, "A/B bypass path must apply the transport gain");
    }

    {
        // 24-bit target: same placement contract at a finer grid.
        auto engine = makeEngine();
        auto snap = baseSnapshot();
        snap->activeStages = STAGE_DITHER;
        snap->dither.enabled = true;
        snap->dither.targetBitDepth = 24;
        engine->setSampleRate(snap->sampleRate);
        engine->publishParams(snap);

        const auto input = makeSignal(frames, channels);
        std::vector<float> gains(static_cast<size_t>(frames), gain);
        auto work = input;
        engine->processInterleaved(work.data(), frames, channels, gains.data());
        bool grid24 = true;
        for (float v : work) {
            const double scaled = static_cast<double>(v) * 8388608.0;
            if (std::abs(scaled - std::rint(scaled)) > 1e-2) { grid24 = false; break; }
        }
        check(grid24, "24-bit dither target must quantise the gained signal");
    }

    if (gFailures != 0) {
        std::cout << "[FAIL] " << gFailures << " transport gain check(s) failed." << std::endl;
        return 1;
    }
    std::cout << "[PASS] Transport gain applied pre-dither on every engine path." << std::endl;
    return 0;
}
