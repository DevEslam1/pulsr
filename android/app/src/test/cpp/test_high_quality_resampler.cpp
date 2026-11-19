// android/app/src/test/cpp/test_high_quality_resampler.cpp
//
// Host-side proof for the tap sample-rate converter:
//   1. ratio 1.0 is bit-identical (memcmp) for random input, including after a
//      detour through a real ratio,
//   2. 44100 -> 48000 on a 1 kHz sine: frame-count accounting, no NaN, amplitude
//      preserved and THD+N better than -90 dB over one second,
//   3. a 20 kHz tone at 44.1 -> 48 creates no image above -80 dB,
//   4. a too-small output buffer consumes fewer input frames and loses nothing
//      (concatenated output is bit-identical to one big call), and process()
//      does not allocate,
//   5. latency is non-zero and stable, reset() makes output bit-reproducible,
//   6. 8 channels work and no channel leaks into another.
#include "../../main/cpp/HighQualityResampler.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <limits>
#include <new>
#include <vector>

using pulsr::HighQualityResampler;

// Proves "no allocation in process()" instead of asserting it in a comment.
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

uint32_t gRng = 0x243f6a88u;
uint32_t nextRandom() {
    gRng = gRng * 1664525u + 1013904223u;
    return gRng >> 8;
}

float randomFloat() {
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

// Planar float buffer: one vector per channel, all the same length.
struct Planar {
    int channels = 0;
    std::vector<std::vector<float>> ch;

    void init(int c, int frames) {
        channels = c;
        ch.assign(static_cast<size_t>(c), std::vector<float>(static_cast<size_t>(frames), 0.0f));
    }
    int frames() const { return ch.empty() ? 0 : static_cast<int>(ch[0].size()); }

    std::vector<const float*> inPtrs(int offset) const {
        std::vector<const float*> p(static_cast<size_t>(channels));
        for (int c = 0; c < channels; ++c) p[c] = ch[c].data() + offset;
        return p;
    }
    std::vector<float*> outPtrs(int offset = 0) {
        std::vector<float*> p(static_cast<size_t>(channels));
        for (int c = 0; c < channels; ++c) p[c] = ch[c].data() + offset;
        return p;
    }
    void append(const std::vector<float*>& src, int frames) {
        if (frames <= 0) return;
        for (int c = 0; c < channels; ++c) {
            const size_t base = ch[c].size();
            ch[c].resize(base + static_cast<size_t>(frames));
            std::memcpy(ch[c].data() + base, src[c], static_cast<size_t>(frames) * sizeof(float));
        }
    }
};

void fillSine(Planar& p, double freq, double rate, double amp, int channel = -1) {
    for (int n = 0; n < p.frames(); ++n) {
        const double v = amp * std::sin(2.0 * kPi * freq * n / rate);
        for (int c = 0; c < p.channels; ++c) {
            if (channel >= 0 && c != channel) continue;
            p.ch[c][n] = static_cast<float>(v);
        }
    }
}

// Feeds `in` through `rs` in blocks of blockIn input frames with a blockOut
// output budget, then drains the buffered lookahead. Returns total input frames
// consumed; *partialCalls counts calls that took fewer frames than were offered
// because the output buffer filled first.
int streamThrough(HighQualityResampler& rs, const Planar& in, int blockIn, int blockOut,
                  Planar& out, int* partialCalls) {
    out.init(in.channels, 0);
    Planar scratch;
    scratch.init(in.channels, blockOut);

    int consumedTotal = 0;
    bool stalled = false;
    while (consumedTotal < in.frames()) {
        const int n = std::min(blockIn, in.frames() - consumedTotal);
        const std::vector<const float*> ip = in.inPtrs(consumedTotal);
        int consumed = 0;
        while (consumed < n) {
            const int offered = n - consumed;
            std::vector<const float*> ipc(static_cast<size_t>(in.channels));
            for (int c = 0; c < in.channels; ++c) ipc[c] = ip[c] + consumed;
            std::vector<float*> op = scratch.outPtrs();
            int used = 0;
            const int got = rs.process(ipc.data(), offered, op.data(), blockOut, used);
            check(got >= 0 && got <= blockOut, "process() must never exceed maxOutFrames");
            out.append(op, got);
            consumed += used;
            consumedTotal += used;
            if (used < offered && partialCalls != nullptr) ++*partialCalls;
            if (got == 0 && used == 0) {
                stalled = true;  // defensive: no progress, do not spin forever
                break;
            }
        }
        if (stalled) break;
    }

    for (;;) {
        std::vector<float*> op = scratch.outPtrs();
        int used = 0;
        const int got = rs.process(nullptr, 0, op.data(), blockOut, used);
        if (got <= 0) break;
        out.append(op, got);
    }
    return consumedTotal;
}

struct ToneFit {
    double amp = 0.0;
    double residualDb = 0.0;
};

// Least-squares fit of A*sin + B*cos + DC at `freq` over the whole block.
// residualDb is 10*log10(residual power / fundamental power).
ToneFit fitTone(const std::vector<float>& y, double freq, double rate) {
    ToneFit fit;
    const int n = static_cast<int>(y.size());
    if (n < 16) return fit;
    const double w = 2.0 * kPi * freq / rate;
    double Sss = 0, Scc = 0, Ssc = 0, Ss = 0, Sc = 0, N = 0;
    double Ssy = 0, Scy = 0, Sy = 0;
    for (int i = 0; i < n; ++i) {
        const double s = std::sin(w * i);
        const double c = std::cos(w * i);
        const double v = y[static_cast<size_t>(i)];
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
    if (std::fabs(det) < 1e-9) return fit;
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
    for (int i = 0; i < n; ++i) {
        const double s = std::sin(w * i);
        const double c = std::cos(w * i);
        const double model = a * s + b * c;
        const double v = y[static_cast<size_t>(i)];
        residual += (v - (model + d)) * (v - (model + d));
        signal += model * model;
    }
    fit.amp = std::sqrt(a * a + b * b);
    fit.residualDb = (signal > 0.0) ? 10.0 * std::log10(residual / signal) : 0.0;
    return fit;
}

// Folds `hz` into [0, outRate/2].
double foldToOutput(double hz, double outRate) {
    double f = std::fmod(hz, outRate);
    if (f < 0.0) f += outRate;
    if (f > outRate * 0.5) f = outRate - f;
    return f;
}

// ---- 1. Exact bypass -----------------------------------------------------
void testBypass() {
    for (int channels : {1, 2, 8}) {
        HighQualityResampler rs;
        check(rs.configure(channels, 256, 512, 44100.0, 44100.0),
              "configure must succeed for 1/2/8 channels at unity rate");
        check(rs.bypassed(), "a unity-rate configuration must start in exact bypass");
        check(rs.ratio() == 1.0, "the unity-rate nominal ratio must be exactly 1.0");
        check(rs.latencyFrames() == 128, "256 taps at unity is 128 frames of nominal delay");

        Planar in;
        in.init(channels, 20000);
        for (int c = 0; c < channels; ++c) {
            for (int n = 0; n < in.frames(); ++n) in.ch[c][n] = randomFloat();
        }
        const Planar before = in;

        Planar out;
        out.init(channels, 20000);
        out.ch[0].assign(20000, 0.25f);        std::vector<const float*> ip = in.inPtrs(0);
        std::vector<float*> op = out.outPtrs();
        int consumed = 0;

        int got = rs.process(ip.data(), in.frames(), op.data(), in.frames(), consumed);
        check(got == in.frames(), "bypass must return every input frame");
        check(consumed == in.frames(), "bypass must consume every input frame");
        bool identical = true;
        for (int c = 0; c < channels; ++c) {
            if (std::memcmp(out.ch[c].data(), in.ch[c].data(),
                            static_cast<size_t>(in.frames()) * sizeof(float)) != 0) {
                identical = false;
            }
        }
        check(identical, "bypass output must be bit-identical to the input");
        bool inputUntouched = true;
        for (int c = 0; c < channels; ++c) {
            if (std::memcmp(before.ch[c].data(), in.ch[c].data(),
                            static_cast<size_t>(in.frames()) * sizeof(float)) != 0) {
                inputUntouched = false;
            }
        }
        check(inputUntouched, "bypass must never mutate the caller's buffer");

        // A detour through a real ratio must not corrupt the bit-perfect path.
        rs.setRatio(48000.0 / 44100.0);
        check(!rs.bypassed(), "a non-unity ratio must leave bypass");
        Planar scratch;
        scratch.init(channels, 2048);
        std::vector<float*> sp = scratch.outPtrs();
        (void)rs.process(ip.data(), 2048, sp.data(), 2048, consumed);

        rs.setRatio(1.0);
        check(rs.bypassed(), "returning to ratio 1.0 must re-enter exact bypass");
        Planar out2;
        out2.init(channels, 20000);
        std::vector<float*> op2 = out2.outPtrs();
        got = rs.process(ip.data(), in.frames(), op2.data(), in.frames(), consumed);
        check(got == in.frames(), "post-detour bypass must still return every frame");
        identical = true;
        for (int c = 0; c < channels; ++c) {
            if (std::memcmp(out2.ch[c].data(), in.ch[c].data(),
                            static_cast<size_t>(in.frames()) * sizeof(float)) != 0) {
                identical = false;
            }
        }
        check(identical, "post-detour bypass output must be bit-identical to the input");

        // The bypass band is |ratio - 1| < 1e-9, not a float equality.
        rs.setRatio(1.0 + 1e-10);
        check(rs.bypassed(), "a ratio within 1e-9 of unity must stay in bypass");
        rs.setRatio(1.0 + 1e-8);
        check(!rs.bypassed(), "a ratio 1e-8 off unity must leave bypass");
    }

    // Ratio validation: clamp to the sane band, ignore non-finite values.
    HighQualityResampler rs;
    check(rs.configure(2, 256, 512, 44100.0, 48000.0), "configure for ratio clamp must succeed");
    rs.setRatio(1e6);
    check(rs.ratio() == HighQualityResampler::kMaxRatio, "a huge ratio must clamp to kMaxRatio");
    rs.setRatio(1e-6);
    check(rs.ratio() == HighQualityResampler::kMinRatio, "a tiny ratio must clamp to kMinRatio");
    const double kept = rs.ratio();
    rs.setRatio(std::numeric_limits<double>::quiet_NaN());
    check(rs.ratio() == kept, "NaN must keep the previous ratio");
    rs.setRatio(0.0);
    check(rs.ratio() == kept, "0.0 must keep the previous ratio");
    rs.setRatio(-2.0);
    check(rs.ratio() == kept, "a negative ratio must keep the previous ratio");
    rs.setRatio(std::numeric_limits<double>::infinity());
    check(rs.ratio() == kept, "Inf must keep the previous ratio");

    // Geometry validation.
    check(!rs.configure(0, 256, 512, 44100.0, 48000.0), "0 channels must be rejected");
    check(!rs.configure(9, 256, 512, 44100.0, 48000.0), "9 channels must be rejected");
    check(!rs.configure(2, 62, 512, 44100.0, 48000.0), "taps below 64 must be rejected");
    check(!rs.configure(2, 514, 512, 44100.0, 48000.0), "taps above 512 must be rejected");
    check(!rs.configure(2, 255, 512, 44100.0, 48000.0), "odd taps must be rejected");
    check(!rs.configure(2, 256, 32, 44100.0, 48000.0), "phases below 64 must be rejected");
    check(!rs.configure(2, 256, 4096, 44100.0, 48000.0), "phases above 2048 must be rejected");
    check(!rs.configure(2, 256, 512, 0.0, 48000.0), "a zero input rate must be rejected");
    check(!rs.configure(2, 256, 512, 44100.0, -1.0), "a negative output rate must be rejected");
    check(!rs.configure(2, 256, 512, std::numeric_limits<double>::quiet_NaN(), 48000.0),
          "a NaN rate must be rejected");
    check(!rs.configure(2, 256, 512, 44100.0, std::numeric_limits<double>::infinity()),
          "an infinite rate must be rejected");

    // Unconfigured and released objects must be inert, not crash.
    HighQualityResampler fresh;
    check(!fresh.isConfigured(), "a default-constructed converter is not configured");
    check(fresh.latencyFrames() == 0, "an unconfigured converter reports no latency");
    fresh.setRatio(0.5);  // must be inert: the coefficient table does not exist yet
    check(fresh.ratio() == 1.0, "setRatio before configure() must be ignored");
    const float* noIn[2] = {nullptr, nullptr};
    float* noOut[2] = {nullptr, nullptr};
    int used = 0;
    check(fresh.process(noIn, 16, noOut, 16, used) == 0,
          "an unconfigured converter must produce nothing");
    check(used == 0, "an unconfigured converter must consume nothing");

    check(rs.configure(2, 128, 128, 44100.0, 48000.0), "re-configure before release must work");
    rs.release();
    check(!rs.isConfigured(), "release() must clear the configuration");
    check(rs.channels() == 0 && rs.taps() == 0 && rs.phases() == 0,
          "release() must clear the reported geometry");
    check(rs.latencyFrames() == 0, "a released converter reports no latency");
    check(rs.process(noIn, 16, noOut, 16, used) == 0, "a released converter must produce nothing");
    check(rs.configure(2, 256, 512, 44100.0, 48000.0), "configure() after release() must work");
}

// ---- 2. 44100 -> 48000: frame accounting, amplitude, THD+N ----------------
void testUpsampleThd() {
    const double inRate = 44100.0;
    const double outRate = 48000.0;
    const double ratio = outRate / inRate;
    const double tone = 1000.0;
    const double amp = 0.5;
    const int taps = 512;

    HighQualityResampler rs;
    check(rs.configure(1, taps, 1024, inRate, outRate), "configure(1,512,1024,44.1k,48k)");
    check(!rs.bypassed(), "44.1 -> 48 must not be in bypass");
    check(std::fabs(rs.latencyFrames() - 256.0 * ratio) <= 1.0,
          "latency must be taps/2 input frames scaled to output frames");

    const int inFrames = static_cast<int>(1.2 * inRate);  // 52920
    Planar in;
    in.init(1, inFrames);
    fillSine(in, tone, inRate, amp);

    // One call with the capacity a well-behaved caller would size:
    // ceil(inFrames * ratio) + taps.
    const int expected = static_cast<int>(std::ceil(static_cast<double>(inFrames) * ratio));
    const int cap = expected + taps;
    Planar out;
    out.init(1, cap);
    std::vector<const float*> ip = in.inPtrs(0);
    std::vector<float*> op = out.outPtrs();
    int consumed = 0;
    const auto started = std::chrono::steady_clock::now();
    const int produced = rs.process(ip.data(), inFrames, op.data(), cap, consumed);
    const double elapsedMs = std::chrono::duration<double, std::milli>(
                                 std::chrono::steady_clock::now() - started)
                                 .count();
    check(consumed == inFrames, "a ceil(in*ratio)+taps buffer must consume the whole block");
    check(produced <= expected, "a causal converter cannot emit more than ceil(in*ratio) frames");
    check(produced >= expected - taps,
          "output must be within one filter length of ceil(in*ratio) (lookahead tail)");
    std::cout << "[INFO] 44100->48000: in " << inFrames << " frames, produced " << produced
              << ", ceil(in*ratio) " << expected << ", tail " << (expected - produced)
              << " frames" << std::endl;
    std::cout << "[INFO] 512-tap mono pass: " << elapsedMs << " ms for 1.2 s of audio ("
              << (1200.0 / std::max(elapsedMs, 1e-9)) << "x real time on this host)" << std::endl;

    // Drain the tail and check the total accounting.
    int drained = 0;
    std::vector<float> tail(static_cast<size_t>(taps + 4096));
    for (;;) {
        float* tp = tail.data();
        int used = 0;
        const int got = rs.process(nullptr, 0, &tp, static_cast<int>(tail.size()), used);
        if (got <= 0) break;
        drained += got;
    }
    // A causal filter cannot emit the last taps/2 frames: the right-hand half
    // of their kernel needs input that does not exist yet. The honest total is
    // therefore ceil(in*ratio) minus that lookahead, never the full count.
    const int total = produced + drained;
    check(total <= expected, "the drained total must not exceed ceil(in*ratio)");
    check(total + taps >= expected,
          "the drained total must be within one filter length of ceil(in*ratio)");
    check(drained <= taps, "the buffered tail must not exceed one filter length");
    check(std::abs((expected - total) - rs.latencyFrames()) <= 2,
          "the frame-count deficit must equal the reported latency (the lookahead)");
    std::cout << "[INFO] after drain: " << total << " frames total (deficit " << (expected - total)
              << " vs ceil, lookahead " << (taps / 2) << " input frames)" << std::endl;

    // Drop the start-up ramp, then fit exactly one second of the output.
    const int skip = 4096;
    const int window = 48000;
    check(produced >= skip + window, "the THD window must fit in the produced output");
    std::vector<float> block(out.ch[0].begin() + skip, out.ch[0].begin() + skip + window);

    bool finite = true;
    bool inRange = true;
    for (float v : block) {
        if (!std::isfinite(v)) finite = false;
        if (v > 1.0f || v < -1.0f) inRange = false;
    }
    check(finite, "the resampled tone must contain no NaN/Inf");
    check(inRange, "a -6 dBFS input must not clip above 1.0");

    const ToneFit fit = fitTone(block, tone, outRate);
    std::cout << "[INFO] THD+N 1 kHz, 44100->48000, 512 taps / 1024 phases: "
              << fit.residualDb << " dB (amplitude " << fit.amp << " of " << amp << ")"
              << std::endl;
    check(fit.amp > amp * 0.9 && fit.amp < amp * 1.1,
          "the resampled tone must keep its amplitude (0.9..1.1)");
    check(fit.residualDb < -90.0, "1 kHz THD+N must be better than -90 dB");

    // Independent cross-check of the aggregate number: each harmonic on its own.
    // Every one of these frequencies is an integer number of cycles in the
    // 48000-sample window, so the projections are orthogonal to the fundamental.
    double worstHarmonicDb = -1000.0;
    int worstHarmonic = 0;
    for (int h = 2; h <= 10; ++h) {
        const ToneFit harmonic = fitTone(block, tone * h, outRate);
        const double db = 20.0 * std::log10(std::max(harmonic.amp, 1e-30) / fit.amp);
        if (db > worstHarmonicDb) {
            worstHarmonicDb = db;
            worstHarmonic = h;
        }
    }
    std::cout << "[INFO] worst harmonic H2..H10 (H" << worstHarmonic << "): " << worstHarmonicDb
              << " dB" << std::endl;
    check(worstHarmonicDb < -90.0, "every harmonic 2..10 must stay below -90 dB");
}

// ---- 3. Image rejection at 20 kHz ---------------------------------------
void testImageRejection() {
    const double inRate = 44100.0;
    const double outRate = 48000.0;
    const double ratio = outRate / inRate;
    const double tone = 20000.0;
    const double amp = 0.5;

    HighQualityResampler rs;
    check(rs.configure(1, 512, 1024, inRate, outRate), "configure for the image test");

    const int inFrames = static_cast<int>(1.2 * inRate);
    Planar in;
    in.init(1, inFrames);
    fillSine(in, tone, inRate, amp);

    Planar out;
    const int blockOut = static_cast<int>(std::ceil(static_cast<double>(inFrames) * ratio)) + 512;
    const int consumedTotal = streamThrough(rs, in, inFrames, blockOut, out, nullptr);
    check(consumedTotal == inFrames, "the image test must consume every input frame");
    check(out.frames() >= 4096 + 48000, "the image test needs a full second of output");

    const int skip = 4096;
    const int window = 48000;
    std::vector<float> block(out.ch[0].begin() + skip, out.ch[0].begin() + skip + window);

    const ToneFit fundamental = fitTone(block, tone, outRate);
    check(fundamental.amp > amp * 0.9 && fundamental.amp < amp * 1.1,
          "the 20 kHz tone must survive at its input amplitude");

    // Every image of a tone at f sits at f + k*inRate in the output domain,
    // folded into [0, outRate/2]; the k = -1 one lands at 23900 Hz here and is
    // the hardest to reject because it is closest to the cutoff.
    double worstDb = -1000.0;
    double worstHz = 0.0;
    std::cout << "[INFO] 20 kHz at 44100->48000, fundamental " << fundamental.amp
              << ", broadband residual " << fundamental.residualDb << " dB" << std::endl;
    for (int k = -8; k <= 8; ++k) {
        if (k == 0) continue;
        const double f = foldToOutput(tone + static_cast<double>(k) * inRate, outRate);
        if (f < 50.0 || f > outRate * 0.5 - 50.0) continue;
        if (std::fabs(f - tone) < 200.0) continue;
        const ToneFit image = fitTone(block, f, outRate);
        if (fundamental.amp <= 0.0) continue;
        const double db = 20.0 * std::log10(std::max(image.amp, 1e-30) / fundamental.amp);
        if (k == -1 || k == 1) {
            std::cout << "[INFO]   image k=" << k << " at " << f << " Hz: " << db << " dB"
                      << std::endl;
        }
        if (db > worstDb) {
            worstDb = db;
            worstHz = f;
        }
    }
    std::cout << "[INFO] worst image: " << worstHz << " Hz at " << worstDb
              << " dB; out-of-band residual " << fundamental.residualDb << " dB" << std::endl;
    check(worstDb < -80.0, "no image may exceed -80 dB at 44.1 -> 48");
    check(fundamental.residualDb < -80.0, "total out-of-band energy must stay below -80 dB");
}

// ---- 4. Partial consumption, no loss, no allocation ----------------------
void testPartialConsumption() {
    const int channels = 2;
    const double ratio = 48000.0 / 44100.0;
    const int frames = 20000;
    const int taps = 256;

    Planar in;
    in.init(channels, frames);
    for (int c = 0; c < channels; ++c) {
        for (int n = 0; n < frames; ++n) in.ch[c][n] = randomFloat() * 0.5f;
    }

    HighQualityResampler small;
    HighQualityResampler big;
    check(small.configure(channels, taps, 512, 44100.0, 48000.0), "configure the small-buffer run");
    check(big.configure(channels, taps, 512, 44100.0, 48000.0), "configure the single-call run");

    // Deliberately tiny output budget: 128 frames per call against 4096-frame
    // input blocks.
    Planar smallOut;
    int partialCalls = 0;
    const int smallConsumed = streamThrough(small, in, 4096, 128, smallOut, &partialCalls);
    check(partialCalls > 0, "a 128-frame output buffer must consume only part of a 4096-frame block");

    Planar bigOut;
    const int bigBlockOut = static_cast<int>(std::ceil(static_cast<double>(frames) * ratio)) + taps;
    const int bigConsumed = streamThrough(big, in, frames, bigBlockOut, bigOut, nullptr);

    check(smallConsumed == frames, "the small-buffer run must consume every input frame eventually");
    check(bigConsumed == frames, "the single-call run must consume every input frame");
    check(smallOut.frames() == bigOut.frames(),
          "chunked and single-call output must have the same frame count");
    check(smallOut.frames() >= static_cast<int>(std::ceil(static_cast<double>(frames) * ratio)) - taps,
          "the drained output must reach the expected frame count");

    bool identical = smallOut.frames() == bigOut.frames();
    if (identical) {
        for (int c = 0; c < channels; ++c) {
            if (std::memcmp(smallOut.ch[c].data(), bigOut.ch[c].data(),
                            static_cast<size_t>(smallOut.frames()) * sizeof(float)) != 0) {
                identical = false;
            }
        }
    }
    check(identical, "concatenated small-buffer output must be bit-identical to one big call");
    std::cout << "[INFO] partial consumption: " << partialCalls << " partial calls, "
              << smallOut.frames() << " frames, identical to the single-call run" << std::endl;

    // process() must not allocate once configured.
    std::vector<std::vector<float>> inBuf(static_cast<size_t>(channels),
                                          std::vector<float>(480, 0.1f));
    std::vector<std::vector<float>> outBuf(static_cast<size_t>(channels),
                                           std::vector<float>(512, 0.0f));
    std::vector<const float*> ip(static_cast<size_t>(channels));
    std::vector<float*> op(static_cast<size_t>(channels));
    for (int c = 0; c < channels; ++c) {
        ip[c] = inBuf[static_cast<size_t>(c)].data();
        op[c] = outBuf[static_cast<size_t>(c)].data();
    }
    const uint64_t before = gAllocations.load(std::memory_order_relaxed);
    int used = 0;
    bool progressed = true;
    for (int i = 0; i < 500; ++i) {
        if (small.process(ip.data(), 480, op.data(), 512, used) <= 0) progressed = false;
    }
    const uint64_t after = gAllocations.load(std::memory_order_relaxed);
    check(progressed, "the allocation probe must keep producing output");
    check(after == before, "process() must not allocate after configure()");
}

// ---- 5. Latency stability and reset determinism -------------------------
void testLatencyAndReset() {
    const int channels = 2;
    HighQualityResampler rs;
    check(rs.configure(channels, 256, 512, 44100.0, 48000.0), "configure for the latency test");

    const int lat = rs.latencyFrames();
    check(lat > 0, "latency must be non-zero for a real ratio");
    check(lat < 256, "latency must stay inside one filter length");

    Planar in;
    in.init(channels, 12000);
    for (int n = 0; n < in.frames(); ++n) {
        in.ch[0][n] = static_cast<float>(0.4 * std::sin(2.0 * kPi * 997.0 * n / 44100.0));
        in.ch[1][n] = static_cast<float>(0.3 * std::sin(2.0 * kPi * 3271.0 * n / 44100.0));
    }

    Planar first;
    const int blockOut = 4096;
    streamThrough(rs, in, 2048, blockOut, first, nullptr);
    check(rs.latencyFrames() == lat, "latency must not drift while streaming");

    rs.reset();
    check(rs.latencyFrames() == lat, "reset() must not change the reported latency");
    Planar second;
    streamThrough(rs, in, 2048, blockOut, second, nullptr);

    check(first.frames() == second.frames(), "reset() must reproduce the same frame count");
    bool identical = first.frames() == second.frames();
    if (identical) {
        for (int c = 0; c < channels; ++c) {
            if (std::memcmp(first.ch[c].data(), second.ch[c].data(),
                            static_cast<size_t>(first.frames()) * sizeof(float)) != 0) {
                identical = false;
            }
        }
    }
    check(identical, "reset() must make the output bit-for-bit repeatable");
    std::cout << "[INFO] latency " << lat << " output frames, stable across 12000 frames and reset"
              << std::endl;
}

// ---- 6. Eight channels, no leakage --------------------------------------
void testEightChannels() {
    const int channels = 8;
    const int taps = 256;
    HighQualityResampler rs;
    check(rs.configure(channels, taps, 512, 44100.0, 48000.0), "configure(8 channels)");

    const int frames = 12000;
    Planar in;
    in.init(channels, frames);
    for (int c = 0; c < channels; ++c) {
        if (c == 5) continue;  // channel 5 stays exactly silent
        const double freq = 200.0 + 350.0 * c;
        for (int n = 0; n < frames; ++n) {
            in.ch[c][n] = static_cast<float>(0.05 * (c + 1) *
                                             std::sin(2.0 * kPi * freq * n / 44100.0 + 0.3 * c));
        }
    }

    Planar out;
    const int blockOut = 2048;
    const int consumedAll = streamThrough(rs, in, 1000, blockOut, out, nullptr);
    check(consumedAll == frames, "the 8-channel run must consume every input frame");
    check(out.frames() > 0, "the 8-channel run must produce output");
    check(out.channels == channels, "the 8-channel run must keep its channel count");

    bool silent = true;
    for (float v : out.ch[5]) {
        if (v != 0.0f) silent = false;
    }
    check(silent, "a silent channel must stay at exact zero (no leakage in)");

    bool finite = true;
    for (int c = 0; c < channels; ++c) {
        for (float v : out.ch[c]) {
            if (!std::isfinite(v)) finite = false;
        }
    }
    check(finite, "the 8-channel output must be finite everywhere");

    // Each channel must match an independent mono run bit for bit.
    bool allMatch = true;
    for (int c = 0; c < channels; ++c) {
        Planar monoIn;
        monoIn.init(1, frames);
        monoIn.ch[0] = in.ch[c];

        HighQualityResampler mono;
        check(mono.configure(1, taps, 512, 44100.0, 48000.0), "configure a mono reference");
        Planar monoOut;
        streamThrough(mono, monoIn, 1000, blockOut, monoOut, nullptr);

        if (monoOut.frames() != out.frames()) {
            allMatch = false;
            continue;
        }
        if (std::memcmp(monoOut.ch[0].data(), out.ch[c].data(),
                        static_cast<size_t>(out.frames()) * sizeof(float)) != 0) {
            allMatch = false;
        }
    }
    check(allMatch, "every channel must be filtered independently and identically (no leakage)");
    std::cout << "[INFO] 8 channels: " << out.frames() << " output frames, channel 5 silent, "
              << "each channel bit-identical to a mono run" << std::endl;
}

// ---- 7. Downsampling moves the anti-alias cutoff ------------------------
// Not one of the six required cases; this guards the "arbitrary ratio" claim.
// Configured at unity and then asked for 2:1, the kernel must be rebuilt with
// the cutoff halved, or a 30 kHz tone at 96 k folds straight to 18 kHz.
void testDownsampleRebuild() {
    const double inRate = 96000.0;
    const double outRate = 48000.0;
    const double tone = 30000.0;

    HighQualityResampler rs;
    check(rs.configure(1, 512, 1024, inRate, inRate), "configure the downsample host at unity");
    check(rs.bypassed(), "a unity configuration starts in bypass");
    rs.setRatio(outRate / inRate);
    check(!rs.bypassed(), "a 2:1 ratio must leave bypass");
    check(std::fabs(rs.ratio() - 0.5) < 1e-12, "the 2:1 ratio must be accepted");
    check(rs.latencyFrames() == 128, "latency at ratio 0.5 is taps/4 output frames");

    Planar in;
    in.init(1, static_cast<int>(1.2 * inRate));
    fillSine(in, tone, inRate, 0.5);

    Planar out;
    const int blockOut = static_cast<int>(std::ceil(static_cast<double>(in.frames()) * 0.5)) + 512;
    const int consumedAll = streamThrough(rs, in, in.frames(), blockOut, out, nullptr);
    check(consumedAll == in.frames(), "the downsample run must consume every input frame");
    check(out.frames() >= 4096 + 48000, "the downsample run needs a full second of output");

    const int skip = 4096;
    const int window = 48000;
    std::vector<float> block(out.ch[0].begin() + skip, out.ch[0].begin() + skip + window);
    bool finite = true;
    for (float v : block) {
        if (!std::isfinite(v)) finite = false;
    }
    check(finite, "the downsampled output must be finite");

    // The 30 kHz tone cannot exist at 48 k, so whatever survives folds to 18 kHz.
    const ToneFit alias = fitTone(block, 18000.0, outRate);
    const double db = 20.0 * std::log10(std::max(alias.amp, 1e-30) / 0.5);
    std::cout << "[INFO] 30 kHz at 96000->48000: alias energy at 18 kHz " << db << " dB"
              << std::endl;
    check(db < -80.0, "an out-of-band tone must not fold back above -80 dB");
}

}  // namespace

int main() {
    std::cout << "[TEST] HighQualityResampler (tap SRC)..." << std::endl;

    testBypass();
    testUpsampleThd();
    testImageRejection();
    testPartialConsumption();
    testLatencyAndReset();
    testEightChannels();
    testDownsampleRebuild();

    if (gFailures != 0) {
        std::cout << "[FAIL] " << gFailures << " of " << gChecks
                  << " HighQualityResampler check(s) failed." << std::endl;
        return 1;
    }
    std::cout << "[PASS] HighQualityResampler: " << gChecks
              << " checks (bypass, THD+N, images, partial consumption, latency/reset, channels)."
              << std::endl;
    return 0;
}
