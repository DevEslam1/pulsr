// android/app/src/test/cpp/test_bypass_transparency.cpp
//
// The ExoPlayer PCM tap (NativeDspAudioProcessor) now routes every decoded
// sample through AudioDspEngine, so "all effects off" must be bit-identical to
// the input or every user gets altered audio. These cases pin that down.
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

// Bitwise, not epsilon: "transparent" means the samples were never touched.
bool bitIdentical(const std::vector<float>& a, const std::vector<float>& b) {
    return a.size() == b.size() &&
           std::memcmp(a.data(), b.data(), a.size() * sizeof(float)) == 0;
}

std::shared_ptr<DspParamSnapshot> baseSnapshot() {
    auto snap = std::make_shared<DspParamSnapshot>();
    snap->sampleRate = 48000.0;
    snap->activeStages = 0;
    return snap;
}

// AudioDspEngine holds every stage by value, and SincResampler alone carries a
// 256 KB ring buffer (x3: one direct, two inside ConvolutionReverb's wet path).
// A stack instance blows MSVC's 1 MB default thread stack.
std::unique_ptr<AudioDspEngine> makeEngine() {
    return std::make_unique<AudioDspEngine>();
}

// Runs several blocks so any smoothing ramp inside a stage has to converge, and
// compares every block against the untouched input.
bool runBlocks(AudioDspEngine& engine, std::shared_ptr<const DspParamSnapshot> snap,
               int frames, int channels, int blocks) {
    engine.setSampleRate(snap->sampleRate);
    engine.publishParams(snap);
    const std::vector<float> input = makeSignal(frames, channels);
    for (int b = 0; b < blocks; ++b) {
        std::vector<float> work = input;
        const int out = engine.processInterleaved(work.data(), frames, channels);
        if (out != frames) return false;
        if (!bitIdentical(work, input)) return false;
    }
    return true;
}

} // namespace

int main() {
    std::cout << "[TEST] DSP bypass transparency (PCM tap safety)..." << std::endl;

    const int frames = 512;
    const int channels = 2;

    {
        auto engine = makeEngine();
        auto snap = baseSnapshot();
        check(runBlocks(*engine, snap, frames, channels, 8),
              "all stages off must be bit-identical to the input");
    }

    {
        // Bit-perfect wins over everything upstream of it, including ReplayGain.
        auto engine = makeEngine();
        auto snap = baseSnapshot();
        snap->activeStages = 0xFFFFFFFF;
        snap->bitPerfect.enabled = true;
        snap->eq.enabled = true;
        snap->eq.preampDb = 6.0;
        snap->limiter.enabled = true;
        snap->replayGain.enabled = true;
        snap->replayGain.mode = ReplayGainMode::Track;
        snap->replayGain.trackGainDb = 8.0;
        check(runBlocks(*engine, snap, frames, channels, 8),
              "bit-perfect bypass must be bit-identical with every stage armed");
    }

    {
        // The HAL used to own balance/mono; the native panner owns it now, so a
        // centered panner has to be a true no-op rather than a near-unity gain.
        auto engine = makeEngine();
        auto snap = baseSnapshot();
        snap->activeStages = STAGE_PANNER;
        snap->panner.balance = 0.0;
        snap->panner.monoMix = false;
        check(runBlocks(*engine, snap, frames, channels, 8),
              "centered panner must be bit-identical to the input");
    }

    {
        // Mono downmix is the one stage no Android AudioEffect can do, so it is
        // the reason panner ownership moved to the native chain at all.
        auto engine = makeEngine();
        auto snap = baseSnapshot();
        snap->activeStages = STAGE_PANNER;
        snap->panner.monoMix = true;
        engine->setSampleRate(snap->sampleRate);
        engine->publishParams(snap);

        const std::vector<float> input = makeSignal(frames, channels);
        std::vector<float> work = input;
        engine->processInterleaved(work.data(), frames, channels);

        bool collapsed = true;
        for (int i = 0; i < frames; ++i) {
            const float expected = 0.5f * (input[i * 2] + input[i * 2 + 1]);
            if (work[i * 2] != expected || work[i * 2 + 1] != expected) {
                collapsed = false;
                break;
            }
        }
        check(collapsed, "mono downmix must write 0.5*(L+R) to both channels");
    }

    if (gFailures != 0) {
        std::cout << "[FAIL] " << gFailures << " bypass transparency check(s) failed." << std::endl;
        return 1;
    }
    std::cout << "[PASS] DSP chain is bit-transparent when bypassed; mono downmix verified."
              << std::endl;
    return 0;
}
