// android/app/src/test/cpp/test_tap_src.cpp
//
// Tap-side SRC (AudioDspEngine::resampleForTap): the Media3 PCM tap converts
// source rate -> device rate ahead of the DSP chain so the shared AudioTrack
// opens at the device rate and AudioFlinger's resampler stays out of the path.
// These cases pin the frame-count contract, signal fidelity, chunk/FIFO
// behaviour and rate switching.
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

std::unique_ptr<AudioDspEngine> makeEngine() {
    return std::make_unique<AudioDspEngine>();
}

std::vector<float> sine(int frames, int channels, double rate, double freq,
                        double phase0 = 0.0) {
    std::vector<float> buf(static_cast<size_t>(frames) * channels);
    for (int f = 0; f < frames; ++f) {
        const double v = std::sin(2.0 * M_PI * freq * f / rate + phase0);
        for (int ch = 0; ch < channels; ++ch) {
            buf[static_cast<size_t>(f) * channels + ch] = static_cast<float>(v);
        }
    }
    return buf;
}

// Goertzel magnitude of `freq` over `frames`, normalised so a full-scale sine
// reports ~0.5.
double toneMagnitude(const std::vector<float>& buf, int frames, int channels,
                     double rate, double freq, int skipFrames) {
    if (frames <= skipFrames + 4) return 0.0;
    const int n = frames - skipFrames;
    const double w = 2.0 * M_PI * freq / rate;
    const double coeff = 2.0 * std::cos(w);
    double s1 = 0.0, s2 = 0.0;
    for (int i = 0; i < n; ++i) {
        const double x = buf[(static_cast<size_t>(i + skipFrames)) * channels];
        const double s0 = x + coeff * s1 - s2;
        s2 = s1;
        s1 = s0;
    }
    const double re = s1 - s2 * std::cos(w);
    const double im = s2 * std::sin(w);
    return std::sqrt(re * re + im * im) / n;
}

int maxOutBound(int inFrames, double srcRate, double dstRate) {
    const double ratio = dstRate / srcRate;
    return static_cast<int>(std::ceil(inFrames * ratio)) +
           static_cast<int>(std::ceil(64.0 * ratio)) + 32;
}

} // namespace

int main() {
    std::cout << "[TEST] Tap-side SRC (resampleForTap)..." << std::endl;

    const int channels = 2;

    {
        // Equal rates: transparent copy, exact frame count.
        auto engine = makeEngine();
        const auto input = sine(1024, channels, 48000.0, 997.0);
        std::vector<float> out(input.size());
        const int got = engine->resampleForTap(input.data(), 1024, out.data(),
                                               1024, channels, 48000.0, 48000.0);
        check(got == 1024, "equal rates must return the input frame count");
        check(std::memcmp(input.data(), out.data(), input.size() * sizeof(float)) == 0,
              "equal rates must be a bit-identical copy");
    }

    {
        // 44.1k -> 48k: steady-state output ratio and tone fidelity. The first
        // output frames are the polyphase priming delay (32 input frames), so
        // measure the ratio over many blocks.
        auto engine = makeEngine();
        const int inFrames = 1024;
        int totalIn = 0, totalOut = 0;
        std::vector<float> tail;
        for (int b = 0; b < 64; ++b) {
            const auto input = sine(inFrames, channels, 44100.0, 997.0,
                                    2.0 * M_PI * 997.0 * totalIn / 44100.0);
            const int maxOut = maxOutBound(inFrames, 44100.0, 48000.0);
            std::vector<float> out(static_cast<size_t>(maxOut) * channels);
            const int got = engine->resampleForTap(input.data(), inFrames, out.data(),
                                                   maxOut, channels, 44100.0, 48000.0);
            check(got > 0 && got <= maxOut, "output frames must respect the bound");
            totalIn += inFrames;
            totalOut += got;
            if (b == 63) tail.assign(out.begin(), out.begin() + static_cast<size_t>(got) * channels);
        }
        const double expected = static_cast<double>(totalIn) * 48000.0 / 44100.0;
        check(std::abs(totalOut - expected) < 96.0,
              "cumulative output frames must track the 48/44.1 ratio");
        const double mag = toneMagnitude(tail, tail.size() / channels, channels,
                                         48000.0, 997.0, 64);
        check(std::abs(mag - 0.5) < 0.01,
              "resampled tone must keep full-scale amplitude at the new rate");
    }

    {
        // Chunk continuity: one 4096-frame call must produce exactly the same
        // samples as two 2048-frame calls on a fresh engine (internal chunking
        // at 2048 keeps phase/FIFO state identical).
        const int frames = 4096;
        const auto input = sine(frames, channels, 44100.0, 1234.0);
        const int maxOut = maxOutBound(frames, 44100.0, 48000.0);

        auto single = makeEngine();
        std::vector<float> outSingle(static_cast<size_t>(maxOut) * channels);
        const int gotSingle = single->resampleForTap(input.data(), frames, outSingle.data(),
                                                     maxOut, channels, 44100.0, 48000.0);

        auto split = makeEngine();
        std::vector<float> outSplit(static_cast<size_t>(maxOut) * channels);
        const int halfMax = maxOutBound(frames / 2, 44100.0, 48000.0);
        std::vector<float> half(static_cast<size_t>(halfMax) * channels);
        const int got1 = split->resampleForTap(input.data(), frames / 2, half.data(),
                                               halfMax, channels, 44100.0, 48000.0);
        std::memcpy(outSplit.data(), half.data(),
                    static_cast<size_t>(got1) * channels * sizeof(float));
        const int got2 = split->resampleForTap(input.data() + static_cast<size_t>(frames / 2) * channels,
                                               frames / 2, half.data(),
                                               halfMax, channels, 44100.0, 48000.0);
        std::memcpy(outSplit.data() + static_cast<size_t>(got1) * channels, half.data(),
                    static_cast<size_t>(got2) * channels * sizeof(float));

        check(gotSingle == got1 + got2, "split calls must emit the same frame count");
        check(gotSingle > 0 &&
              std::memcmp(outSingle.data(), outSplit.data(),
                          static_cast<size_t>(gotSingle) * channels * sizeof(float)) == 0,
              "split calls must be sample-identical to one big call");
    }

    {
        // Oversized block (beyond the resampler FIFO limit ~7.9k): internal
        // chunking must convert every frame without drops.
        auto engine = makeEngine();
        const int frames = 16384;
        const auto input = sine(frames, channels, 44100.0, 997.0);
        const int maxOut = maxOutBound(frames, 44100.0, 48000.0);
        std::vector<float> out(static_cast<size_t>(maxOut) * channels);
        const int got = engine->resampleForTap(input.data(), frames, out.data(),
                                               maxOut, channels, 44100.0, 48000.0);
        const double expected = static_cast<double>(frames) * 48000.0 / 44100.0;
        check(std::abs(got - expected) < 96.0,
              "a block larger than the FIFO must convert without dropping frames");
        bool finite = true;
        for (float v : out) {
            if (!std::isfinite(v)) { finite = false; break; }
        }
        check(finite, "oversized-block output must be finite");
    }

    {
        // Downsampling 96k -> 48k halves the frame count and must kill a tone
        // above the new Nyquist (the polyphase table is the anti-alias filter).
        // 40 kHz sits deep in the 64-tap Blackman-Harris stopband (cutoff is
        // 0.45*ratio = 21.6 kHz with a wide transition); unfiltered it would
        // alias to an 8 kHz tone at full amplitude.
        auto engine = makeEngine();
        const int frames = 8192;
        const auto input = sine(frames, channels, 96000.0, 40000.0);
        const int maxOut = maxOutBound(frames, 96000.0, 48000.0);
        std::vector<float> out(static_cast<size_t>(maxOut) * channels);
        int totalOut = 0;
        totalOut = engine->resampleForTap(input.data(), frames, out.data(),
                                          maxOut, channels, 96000.0, 48000.0);
        check(std::abs(totalOut - frames / 2.0) < 64.0,
              "96k -> 48k must halve the frame count");
        // Skip the onset/offset: a gated sine starts and ends on a step whose
        // broadband transient legitimately leaks past the stopband. Measure
        // the settled middle only.
        double peak = 0.0;
        const size_t settle = 512;
        for (size_t i = settle;
             i + settle < static_cast<size_t>(totalOut) * channels; ++i) {
            peak = std::max(peak, static_cast<double>(std::abs(out[i])));
        }
        check(peak < 0.02, "40 kHz input must be rejected by the downsampling filter");
    }

    {
        // Rate switching reconfigures cleanly: 44.1->48 then 48->44.1 must
        // both produce sane ratios on the same engine.
        auto engine = makeEngine();
        const int frames = 2048;
        const auto up = sine(frames, channels, 44100.0, 997.0);
        const int maxUp = maxOutBound(frames, 44100.0, 48000.0);
        std::vector<float> outUp(static_cast<size_t>(maxUp) * channels);
        const int gotUp = engine->resampleForTap(up.data(), frames, outUp.data(),
                                                 maxUp, channels, 44100.0, 48000.0);
        check(std::abs(gotUp - frames * 48000.0 / 44100.0) < 96.0,
              "first rate pair must convert at the 48/44.1 ratio");

        const auto down = sine(frames, channels, 48000.0, 997.0);
        const int maxDown = maxOutBound(frames, 48000.0, 44100.0);
        std::vector<float> outDown(static_cast<size_t>(maxDown) * channels);
        const int gotDown = engine->resampleForTap(down.data(), frames, outDown.data(),
                                                   maxDown, channels, 48000.0, 44100.0);
        check(std::abs(gotDown - frames * 44100.0 / 48000.0) < 96.0,
              "switching rates must reconfigure and convert at the new ratio");
    }

    {
        // Invalid input contracts.
        auto engine = makeEngine();
        std::vector<float> io(64 * 2, 0.0f);
        check(engine->resampleForTap(io.data(), 0, io.data(), 64, 2, 44100.0, 48000.0) == 0,
              "zero frames must be rejected");
        check(engine->resampleForTap(io.data(), 64, io.data(), 64, 9, 44100.0, 48000.0) == 0,
              "more than 8 channels must be rejected");
        check(engine->resampleForTap(io.data(), 64, io.data(), 64, 2, 0.0, 48000.0) == 0,
              "zero source rate must be rejected");
        check(engine->resampleForTap(nullptr, 64, io.data(), 64, 2, 44100.0, 48000.0) == 0,
              "null input must be rejected");
    }

    if (gFailures != 0) {
        std::cout << "[FAIL] " << gFailures << " tap SRC check(s) failed." << std::endl;
        return 1;
    }
    std::cout << "[PASS] Tap-side SRC converts at the correct ratio with polyphase fidelity."
              << std::endl;
    return 0;
}
