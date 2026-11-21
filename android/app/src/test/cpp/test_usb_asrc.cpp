// android/app/src/test/cpp/test_usb_asrc.cpp
//
// Host-side proof for the polyphase-sinc clock-sync fallback:
//   * ratio == 1.0 is a bit-identical bypass (and stays bit-identical after a
//     detour through a real ratio),
//   * the ratio is hard-clamped to +/-0.5% and NaN/0 are ignored,
//   * a swept ratio tracks the input frequency to within 1 ppm,
//   * 1 kHz THD+N at 1.0002 is better than -90 dB,
//   * the impulse response is finite, bounded and decays to exact silence,
//   * sub-floor inputs (denormals) neither stall nor leak into the output,
//   * channels are independent and reset() is bit-reproducible.
#include "../../main/cpp/UsbAsrcClockSync.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <limits>
#include <new>
#include <vector>

using pulsr::UsbAsrcClockSync;

// Proves "no allocation after configure()" instead of asserting it in a comment.
static std::atomic<uint64_t> gAllocations{0};
void* operator new(std::size_t size) {
    gAllocations.fetch_add(1, std::memory_order_relaxed);
    if (void* p = std::malloc(size ? size : 1)) return p;
    throw std::bad_alloc();
}
void* operator new[](std::size_t size) { return ::operator new(size); }
void operator delete(void* p) noexcept { std::free(p); }
void operator delete[](void* p) noexcept { std::free(p); }
void operator delete(void* p, std::size_t) noexcept { std::free(p); }
void operator delete[](void* p, std::size_t) noexcept { std::free(p); }

namespace {

int gFailures = 0;
int gChecks = 0;

void check(bool ok, const char* what) {
    ++gChecks;
    if (!ok) {
        std::cout << "[FAIL] " << what << std::endl;
        ++gFailures;
    }
}

constexpr double kPi = 3.14159265358979323846;

uint32_t gRng = 0x1234567u;
uint32_t nextRandom() {
    gRng = gRng * 1664525u + 1013904223u;
    return gRng >> 8;
}

float randomFloat() {
    // Full-scale range including exact rails and tiny magnitudes.
    const uint32_t r = nextRandom();
    switch (r & 7u) {
        case 0: return 1.0f;
        case 1: return -1.0f;
        case 2: return 0.0f;
        case 3: return 1e-30f;
        default: break;
    }
    return static_cast<float>(static_cast<int32_t>(r)) / 2147483648.0f;
}

std::vector<float> sineInput(int frames, int channels, double freq, double rate,
                             double amplitude = 0.5) {
    std::vector<float> in(static_cast<size_t>(frames) * channels);
    for (int n = 0; n < frames; ++n) {
        const double v = amplitude * std::sin(2.0 * kPi * freq * n / rate);
        for (int c = 0; c < channels; ++c) {
            in[static_cast<size_t>(n) * channels + c] =
                static_cast<float>(c == 0 ? v : v * 0.5);
        }
    }
    return in;
}

// Feeds `in` through the converter in fixed chunks and appends every produced
// frame to `out` (interleaved, same channel count).
void streamThrough(UsbAsrcClockSync& asrc, const std::vector<float>& in, int inFrames,
                   int channels, double ratio, std::vector<float>& out) {
    const int chunkIn = 480;
    const int chunkOut = static_cast<int>(std::ceil(chunkIn * ratio)) + 128;
    std::vector<float> scratch(static_cast<size_t>(chunkOut) * channels);
    int consumed = 0;
    while (consumed < inFrames) {
        const int n = std::min(chunkIn, inFrames - consumed);
        const int got = asrc.process(&in[static_cast<size_t>(consumed) * channels], n,
                                     scratch.data(), chunkOut);
        check(got >= 0 && got <= chunkOut, "process must never exceed maxOutFrames");
        check(asrc.inputFramesConsumed() == n, "an adequately sized output buffer must consume all input");
        out.insert(out.end(), scratch.begin(), scratch.begin() + static_cast<size_t>(got) * channels);
        consumed += n;
    }
}

// Positive-going zero crossings with linear interpolation, then
// f = cycles / (time between the first and last crossing).
double measureFrequency(const std::vector<float>& y, int channels, int channel,
                        double rate, int skip) {
    const int frames = static_cast<int>(y.size() / static_cast<size_t>(channels));
    double first = -1.0;
    double last = -1.0;
    long cycles = 0;
    for (int n = skip + 1; n < frames; ++n) {
        const float a = y[static_cast<size_t>(n - 1) * channels + channel];
        const float b = y[static_cast<size_t>(n) * channels + channel];
        if (a <= 0.0f && b > 0.0f) {
            const double frac = -static_cast<double>(a) / (static_cast<double>(b) - a);
            const double x = static_cast<double>(n - 1) + frac;
            if (first < 0.0) {
                first = x;
            } else {
                last = x;
                ++cycles;
            }
        }
    }
    if (cycles <= 0 || last <= first) return 0.0;
    return static_cast<double>(cycles) * rate / (last - first);
}

// Least-squares fit of A*sin + B*cos + DC over the whole block; returns
// 10*log10(residual power / fundamental power) in dB.
double measureThdDb(const std::vector<float>& y, int channels, int channel,
                    double freq, double rate) {
    const int frames = static_cast<int>(y.size() / static_cast<size_t>(channels));
    const double w = 2.0 * kPi * freq / rate;
    double Sss = 0, Scc = 0, Ssc = 0, Ss = 0, Sc = 0, N = 0;
    double Ssy = 0, Scy = 0, Sy = 0;
    for (int n = 0; n < frames; ++n) {
        const double s = std::sin(w * n);
        const double c = std::cos(w * n);
        const double v = y[static_cast<size_t>(n) * channels + channel];
        Sss += s * s;
        Scc += c * c;
        Ssc += s * c;
        Ss += s;
        Sc += c;
        N += 1.0;
        Ssy += s * v;
        Scy += c * v;
        Sy += v;
    }
    // 3x3 normal equations, Cramer's rule.
    const double det = Sss * (Scc * N - Sc * Sc) - Ssc * (Ssc * N - Sc * Ss) +
                       Ss * (Ssc * Sc - Scc * Ss);
    if (std::fabs(det) < 1e-9) return 0.0;
    const double detA = Ssy * (Scc * N - Sc * Sc) - Ssc * (Scy * N - Sc * Sy) +
                        Ss * (Scy * Sc - Scc * Sy);
    const double detB = Sss * (Scy * N - Sy * Sc) - Ssy * (Ssc * N - Sc * Ss) +
                        Ss * (Ssc * Sy - Scy * Ss);
    const double detD = Sss * (Scc * Sy - Scy * Sc) - Ssc * (Ssc * Sy - Scy * Ss) +
                        Ssy * (Ssc * Sc - Scc * Ss);
    const double a = detA / det;
    const double b = detB / det;
    const double d = detD / det;

    double residual = 0.0;
    double signal = 0.0;
    for (int n = 0; n < frames; ++n) {
        const double s = std::sin(w * n);
        const double c = std::cos(w * n);
        const double fitSin = a * s + b * c;
        const double model = fitSin + d;
        const double v = y[static_cast<size_t>(n) * channels + channel];
        residual += (v - model) * (v - model);
        signal += fitSin * fitSin;
    }
    if (signal <= 0.0) return 0.0;
    return 10.0 * std::log10(residual / signal);
}

// ---- 1. Exact bypass -----------------------------------------------------
void testBypass() {
    for (int channels : {1, 2, 6}) {
        UsbAsrcClockSync asrc;
        check(asrc.configure(channels), "configure must succeed for 1/2/6 channels");
        check(asrc.bypassed(), "a freshly configured converter must be in exact bypass");
        check(asrc.ratio() == 1.0, "the default ratio must be exactly 1.0");

        const int frames = 20000;
        std::vector<float> in(static_cast<size_t>(frames) * channels);
        for (auto& v : in) v = randomFloat();
        const std::vector<float> before = in;
        std::vector<float> out(in.size(), 0.25f);

        const int got = asrc.process(in.data(), frames, out.data(), frames);
        check(got == frames, "bypass must return every input frame");
        check(std::memcmp(out.data(), in.data(), in.size() * sizeof(float)) == 0,
              "bypass output must be bit-identical to the input");
        check(in == before, "bypass must never mutate the caller's buffer");

        // A detour through a real ratio must not corrupt the bit-perfect path.
        asrc.setRatio(1.0002);
        check(!asrc.bypassed(), "1.0002 must leave bypass");
        std::vector<float> scratch(static_cast<size_t>(frames) * channels);
        (void)asrc.process(in.data(), 1000, scratch.data(), frames);
        asrc.setRatio(1.0);
        check(asrc.bypassed(), "returning to ratio 1.0 must re-enter exact bypass");
        std::vector<float> out2(in.size(), 0.0f);
        const int got2 = asrc.process(in.data(), frames, out2.data(), frames);
        check(got2 == frames, "post-detour bypass must still return every frame");
        check(std::memcmp(out2.data(), in.data(), in.size() * sizeof(float)) == 0,
              "post-detour bypass output must be bit-identical to the input");
    }
}

// ---- 2. Ratio clamping and rejection ------------------------------------
void testRatioClamp() {
    UsbAsrcClockSync asrc;
    check(asrc.configure(2), "configure for ratio clamp must succeed");

    asrc.setRatio(1.10);
    check(asrc.ratio() == UsbAsrcClockSync::kMaxRatio, "1.10 must clamp to +0.5%");
    asrc.setRatio(0.50);
    check(asrc.ratio() == UsbAsrcClockSync::kMinRatio, "0.50 must clamp to -0.5%");

    const double kept = asrc.ratio();
    asrc.setRatio(std::numeric_limits<double>::quiet_NaN());
    check(asrc.ratio() == kept, "NaN must be ignored, keeping the previous ratio");
    asrc.setRatio(0.0);
    check(asrc.ratio() == kept, "0.0 must be ignored, keeping the previous ratio");
    asrc.setRatio(-1.0);
    check(asrc.ratio() == kept, "a negative ratio must be ignored");
    asrc.setRatio(std::numeric_limits<double>::infinity());
    check(asrc.ratio() == kept, "an infinite ratio must be ignored");

    asrc.setRatio(1.0);
    check(asrc.bypassed(), "ratio 1.0 must restore exact bypass");
    asrc.setRatio(1.0 + 1e-9);
    check(!asrc.bypassed(), "a ratio that is not exactly 1.0 must leave bypass");
    check(std::fabs(asrc.ratio() - 1.0) < 2e-9, "a tiny ratio error must be preserved, not quantized");
    check(asrc.latencyFrames() == 16, "32 taps at unity ratio is 16 frames of group delay");
}

// ---- 3. Ratio sweep tracks frequency within 1 ppm ------------------------
void testRatioSweep() {
    const double rate = 48000.0;
    const double tone = 997.0;
    for (double ratio : {0.995, 0.9975, 0.999, 1.0, 1.0002, 1.001, 1.005}) {
        UsbAsrcClockSync asrc;
        check(asrc.configure(1, 32, 256), "configure(1,32,256) must succeed");
        asrc.setRatio(ratio);

        const int inFrames = static_cast<int>(2.4 * rate * ratio);
        const std::vector<float> in = sineInput(inFrames, 1, tone, rate);
        std::vector<float> out;
        out.reserve(static_cast<size_t>(inFrames * ratio) + 4096);
        streamThrough(asrc, in, inFrames, 1, ratio, out);

        const int skip = 4800;  // start-up ramp and settled fractional phase
        const double measured = measureFrequency(out, 1, 0, rate, skip);
        const double expected = tone / ratio;
        const double relPpm = (measured - expected) / expected * 1e6;
        if (std::fabs(relPpm) > 1.0) {
            std::cout << "[INFO] ratio " << ratio << " measured " << measured
                      << " Hz, expected " << expected << " Hz (" << relPpm << " ppm)"
                      << std::endl;
        }
        check(std::fabs(relPpm) <= 1.0,
              "resampled frequency must track the ratio within 1 ppm");
    }
}

// ---- 4. THD+N at 1.0002 --------------------------------------------------
void testThd() {
    const double rate = 48000.0;
    const double tone = 1000.0;
    const double ratio = 1.0002;
    const double amplitude = 0.5;

    UsbAsrcClockSync asrc;
    check(asrc.configure(1, 32, 256), "configure(1,32,256) must succeed");
    asrc.setRatio(ratio);

    const int inFrames = static_cast<int>(2.5 * rate * ratio);
    const std::vector<float> in = sineInput(inFrames, 1, tone, rate, amplitude);
    std::vector<float> out;
    out.reserve(static_cast<size_t>(inFrames * ratio) + 4096);
    streamThrough(asrc, in, inFrames, 1, ratio, out);
    check(out.size() > static_cast<size_t>(rate), "THD test needs at least a second of output");

    // Drop the start-up ramp, then fit exactly one second.
    const int skip = 4800;
    const int window = 48000;
    check(out.size() >= static_cast<size_t>(skip + window), "THD window must fit");
    std::vector<float> block(out.begin() + skip, out.begin() + skip + window);

    bool finite = true;
    bool inRange = true;
    for (float v : block) {
        if (!std::isfinite(v)) finite = false;
        if (v > 1.0f || v < -1.0f) inRange = false;
    }
    check(finite, "the resampled tone must contain no NaN/Inf");
    check(inRange, "a -6 dBFS input must not clip above 1.0");

    const double thd = measureThdDb(block, 1, 0, tone / ratio, rate);
    std::cout << "[INFO] THD+N at 1 kHz, 48 kHz, ratio " << ratio << ": " << thd
              << " dB" << std::endl;
    check(thd < -90.0, "1 kHz THD+N must be better than -90 dB with 32 taps / 256 phases");

    // The fundamental must survive at the input level (no silent or 2x path).
    double peak = 0.0;
    for (float v : block) peak = std::max(peak, std::fabs(static_cast<double>(v)));
    check(peak > amplitude * 0.9 && peak < amplitude * 1.1,
          "the resampled tone must keep its amplitude");
}

// ---- 5. Impulse response -------------------------------------------------
void testImpulse() {
    const double rate = 48000.0;
    const double ratio = 1.0002;
    UsbAsrcClockSync asrc;
    check(asrc.configure(1, 32, 256), "configure for impulse must succeed");
    asrc.setRatio(ratio);

    std::vector<float> in(4000, 0.0f);
    in[100] = 1.0f;
    std::vector<float> out;
    out.reserve(8192);
    streamThrough(asrc, in, static_cast<int>(in.size()), 1, ratio, out);
    check(out.size() > 3000, "impulse processing must produce output");

    bool finite = true;
    for (float v : out) {
        if (!std::isfinite(v)) finite = false;
    }
    check(finite, "impulse response must be finite everywhere");

    double peak = 0.0;
    double sum = 0.0;
    for (float v : out) {
        peak = std::max(peak, std::fabs(static_cast<double>(v)));
        sum += v;
    }
    check(peak > 0.5 && peak <= 1.05, "impulse response peak must stay near unity");
    check(std::fabs(sum - ratio) < 0.02 * ratio,
          "the summed impulse response must equal the DC gain (ratio)");

    bool tailSilent = true;
    for (size_t i = out.size() - 200; i < out.size(); ++i) {
        if (out[i] != 0.0f) tailSilent = false;
    }
    check(tailSilent, "the impulse response tail must decay to exact silence");
}

// ---- 6. Denormals cannot stall the thread --------------------------------
void testDenormals() {
    UsbAsrcClockSync asrc;
    check(asrc.configure(2), "configure for denormal test must succeed");
    asrc.setRatio(1.0002);

    const int frames = 480;
    std::vector<float> in(static_cast<size_t>(frames) * 2);
    for (int i = 0; i < frames; ++i) {
        for (int c = 0; c < 2; ++c) {
            // Sub-floor, still finite: this is what a decaying reverb tail or a
            // dithered fade-out looks like.
            in[static_cast<size_t>(i) * 2 + c] =
                (c == 0 ? 1e-30f : -3e-38f) * static_cast<float>(1 + (i & 7));
        }
    }
    std::vector<float> out(static_cast<size_t>(frames + 16) * 2);
    const auto start = std::chrono::steady_clock::now();
    int produced = 0;
    for (int chunk = 0; chunk < 120; ++chunk) {  // ~1.2 s of output
        const int got = asrc.process(in.data(), frames, out.data(), frames + 8);
        produced += got;
        for (int i = 0; i < got * 2; ++i) {
            if (out[static_cast<size_t>(i)] != 0.0f) {
                check(false, "sub-floor input must be flushed to exact zero");
                return;
            }
        }
    }
    const double seconds = std::chrono::duration<double>(
                               std::chrono::steady_clock::now() - start).count();
    std::cout << "[INFO] denormal pass: " << produced << " frames in " << seconds
              << " s" << std::endl;
    check(produced > 50000, "the denormal pass must actually produce audio");
    check(seconds < 0.25, "sub-floor input must not stall the filter on denormals");
}

// ---- 7. Channel independence and reset determinism -----------------------
void testChannelsAndReset() {
    const int channels = 3;
    const double ratio = 1.0003;
    UsbAsrcClockSync asrc;
    check(asrc.configure(channels, 32, 256), "configure(3ch) must succeed");
    asrc.setRatio(ratio);

    const int frames = 12000;
    std::vector<float> in(static_cast<size_t>(frames) * channels);
    for (int n = 0; n < frames; ++n) {
        for (int c = 0; c < channels; ++c) {
            in[static_cast<size_t>(n) * channels + c] = static_cast<float>(
                0.4 * std::sin(2.0 * kPi * (300.0 + 200.0 * c) * n / 48000.0) +
                0.05 * std::sin(2.0 * kPi * 3100.0 * n / 48000.0 + c));
        }
    }

    std::vector<float> out;
    streamThrough(asrc, in, frames, channels, ratio, out);

    for (int c = 0; c < channels; ++c) {
        std::vector<float> monoIn(static_cast<size_t>(frames));
        for (int n = 0; n < frames; ++n) {
            monoIn[static_cast<size_t>(n)] = in[static_cast<size_t>(n) * channels + c];
        }
        UsbAsrcClockSync mono;
        check(mono.configure(1, 32, 256), "mono reference must configure");
        mono.setRatio(ratio);
        std::vector<float> monoOut;
        streamThrough(mono, monoIn, frames, 1, ratio, monoOut);

        bool identical = monoOut.size() == out.size() / channels;
        if (identical) {
            for (size_t n = 0; n < monoOut.size(); ++n) {
                if (monoOut[n] != out[n * channels + c]) identical = false;
            }
        }
        check(identical, "each channel must be filtered independently and identically");
    }

    // reset() must reproduce a cold start bit for bit.
    asrc.reset();
    std::vector<float> again;
    streamThrough(asrc, in, frames, channels, ratio, again);
    check(again.size() == out.size() &&
              std::memcmp(again.data(), out.data(), out.size() * sizeof(float)) == 0,
          "reset() must make processing bit-reproducible");
}

// ---- 8. No allocation after configure ------------------------------------
void testNoAllocation() {
    UsbAsrcClockSync asrc;
    check(asrc.configure(2, 32, 256), "configure for the allocation test must succeed");
    asrc.setRatio(1.0002);
    std::vector<float> in(480 * 2, 0.1f);
    std::vector<float> out(512 * 2, 0.0f);
    const uint64_t before = gAllocations.load(std::memory_order_relaxed);
    bool ok = true;
    for (int i = 0; i < 500; ++i) {
        if (asrc.process(in.data(), 480, out.data(), 512) <= 0) ok = false;
    }
    const uint64_t after = gAllocations.load(std::memory_order_relaxed);
    check(ok, "the allocation-test stream must keep producing output");
    check(after == before, "process()/setRatio() must not allocate after configure()");
}

// ---- 9. Mid-stream transitions across 1.0 with allowDynamicBypass = false ---
void testNoDynamicBypassSmoothTransition() {
    UsbAsrcClockSync asrc;
    check(asrc.configure(2, 32, 256, /*allowDynamicBypass=*/false),
          "configure with allowDynamicBypass=false must succeed");
    check(!asrc.allowDynamicBypass(), "allowDynamicBypass must report false");
    check(!asrc.bypassed(),
          "converter must not be bypassed even at initial ratio 1.0 when dynamic bypass is disabled");

    const int channels = 2;
    const double sampleRate = 48000.0;
    const double freq = 1000.0;
    const float amp = 0.5f;
    const int chunkFrames = 480;
    const int chunksPerStage = 25;  // 12,000 frames (~250 ms) per stage

    std::vector<float> inputChunk(static_cast<size_t>(chunkFrames) * channels);
    std::vector<float> outputChunk(static_cast<size_t>(chunkFrames + 128) * channels);
    std::vector<float> continuousOut;
    continuousOut.reserve(static_cast<size_t>(chunksPerStage * 3 * (chunkFrames + 128)) * channels);

    double phase = 0.0;
    const double phaseStep = 2.0 * kPi * freq / sampleRate;

    auto streamStage = [&](double ratio) {
        asrc.setRatio(ratio);
        check(!asrc.bypassed(),
              "must remain in resampler (not bypass) during clock-sync ratio change");
        check(std::fabs(asrc.ratio() - ratio) < 1e-9, "ratio must match set value");

        for (int chk = 0; chk < chunksPerStage; ++chk) {
            for (int n = 0; n < chunkFrames; ++n) {
                const float s = static_cast<float>(amp * std::sin(phase));
                phase += phaseStep;
                if (phase >= 2.0 * kPi) phase -= 2.0 * kPi;
                inputChunk[static_cast<size_t>(n) * channels + 0] = s;
                inputChunk[static_cast<size_t>(n) * channels + 1] = s * 0.8f;
            }

            const int got = asrc.process(inputChunk.data(), chunkFrames,
                                         outputChunk.data(),
                                         static_cast<int>(outputChunk.size() / channels));
            check(got > 0, "process() must continuously produce output frames");
            check(asrc.inputFramesConsumed() == chunkFrames,
                  "process() must consume all input frames");

            continuousOut.insert(continuousOut.end(),
                                 outputChunk.begin(),
                                 outputChunk.begin() + static_cast<size_t>(got) * channels);
        }
    };

    // Stage 1: Fast clock ratio (1.0005)
    streamStage(1.0005);
    const size_t stage1Frames = continuousOut.size() / channels;

    // Stage 2: Crossing exact nominal rate 1.0 (must NOT wipe filter history or enter bit-identical bypass)
    streamStage(1.0000);
    const size_t stage2Frames = continuousOut.size() / channels;

    // Stage 3: Slow clock ratio (0.9995)
    streamStage(0.9995);
    const size_t totalFrames = continuousOut.size() / channels;

    check(stage1Frames > 0 && stage2Frames > stage1Frames && totalFrames > stage2Frames,
          "all three ratio stages must produce output frames");

    // Skip initial filter warm-up latency (group delay is taps/2 = 16 frames)
    const size_t warmUp = 64;
    check(totalFrames > warmUp, "total output must exceed warmup");

    // Check sample continuity across the entire stream (especially transitions at stage1Frames and stage2Frames).
    // For 1 kHz sine at 48 kHz with amplitude 0.5: max sample-to-sample difference is ~0.5 * 2 * pi * 1000 / 48000 ≈ 0.0655.
    // An abrupt filter reset or bypass phase jump of ~16 samples latency would produce jumps > 0.40.
    float maxDeltaCh0 = 0.0f;
    float maxDeltaCh1 = 0.0f;
    for (size_t n = warmUp + 1; n < totalFrames; ++n) {
        const float d0 = std::fabs(continuousOut[n * channels + 0] - continuousOut[(n - 1) * channels + 0]);
        const float d1 = std::fabs(continuousOut[n * channels + 1] - continuousOut[(n - 1) * channels + 1]);
        if (d0 > maxDeltaCh0) maxDeltaCh0 = d0;
        if (d1 > maxDeltaCh1) maxDeltaCh1 = d1;
    }

    check(maxDeltaCh0 < 0.10f,
          "ch0 must be smooth across nominal rate transition (no click/wipe/discontinuity)");
    check(maxDeltaCh1 < 0.10f,
          "ch1 must be smooth across nominal rate transition (no click/wipe/discontinuity)");

    // Dynamic bypass enabled contrast check:
    UsbAsrcClockSync asrcBypass;
    check(asrcBypass.configure(2, 32, 256, /*allowDynamicBypass=*/true),
          "configure with allowDynamicBypass=true must succeed");
    check(asrcBypass.allowDynamicBypass(), "allowDynamicBypass must report true");
    check(asrcBypass.bypassed(), "converter starts in bypass when allowDynamicBypass=true");
    asrcBypass.setRatio(1.0005);
    check(!asrcBypass.bypassed(), "ratio 1.0005 leaves bypass");
    asrcBypass.setRatio(1.0000);
    check(asrcBypass.bypassed(), "ratio 1.0 re-enters bypass when allowDynamicBypass=true");

    // Runtime toggle validation:
    asrcBypass.setAllowDynamicBypass(false);
    check(!asrcBypass.allowDynamicBypass(), "setAllowDynamicBypass(false) must update getter");
    check(!asrcBypass.bypassed(),
          "setAllowDynamicBypass(false) at ratio 1.0 must immediately leave bypass");
    asrcBypass.setAllowDynamicBypass(true);
    check(asrcBypass.allowDynamicBypass(), "setAllowDynamicBypass(true) must update getter");
    check(asrcBypass.bypassed(),
          "setAllowDynamicBypass(true) at ratio 1.0 must immediately enter bypass");
}

}  // namespace

int main() {
    std::cout << "[TEST] USB polyphase-sinc clock-sync ASRC..." << std::endl;

    testBypass();
    testRatioClamp();
    testRatioSweep();
    testThd();
    testImpulse();
    testDenormals();
    testChannelsAndReset();
    testNoAllocation();
    testNoDynamicBypassSmoothTransition();

    if (gFailures != 0) {
        std::cout << "[FAIL] " << gFailures << " of " << gChecks
                  << " USB ASRC check(s) failed." << std::endl;
        return 1;
    }
    std::cout << "[PASS] USB ASRC: " << gChecks
              << " checks (bypass, clamp, 1 ppm tracking, THD+N, impulse, denormals, no-dynamic-bypass)."
              << std::endl;
    return 0;
}
