// android/app/src/test/cpp/test_dsp_expansion.cpp
// Host-side test suite for the Phase-1 DSP-expansion stages (HarmonicSaturation,
// StereoWidth, LoudnessContour, SubCrossover, DynamicEQ) plus a full-chain
// "low-FLAC" integration test through AudioDspEngine.
//
// Style mirrors test_native_all.cpp / test_dsp_effects.cpp: assert + stdout
// reporting, no third-party deps. All audio is synthesized on the host; the
// processed 44.1 kHz output of the integration test is dumped to a 16-bit WAV
// for manual audit (never committed).

#include "../../main/cpp/AudioDspEngine.h"
#include "../../main/cpp/HarmonicSaturation.h"
#include "../../main/cpp/StereoWidth.h"
#include "../../main/cpp/LoudnessContour.h"
#include "../../main/cpp/SubCrossover.h"
#include "../../main/cpp/DynamicEQ.h"

#include <algorithm>
#include <cassert>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>

#if defined(_MSC_VER) && defined(_DEBUG)
#include <crtdbg.h>
#endif

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

namespace {

// ---- helpers ---------------------------------------------------------------

// Goertzel amplitude estimator over a whole vector. Prefer exact integer
// periods of the probe frequency inside the window to avoid spectral leakage.
template <typename T>
double goertzelAmplitude(const std::vector<T>& x, double fs, double f) {
    const int n = static_cast<int>(x.size());
    if (n == 0) return 0.0;
    const double w = 2.0 * M_PI * f / fs;
    const double coeff = 2.0 * std::cos(w);
    double s1 = 0.0, s2 = 0.0;
    for (int i = 0; i < n; ++i) {
        const double s0 = static_cast<double>(x[i]) + coeff * s1 - s2;
        s2 = s1;
        s1 = s0;
    }
    const double power = s1 * s1 + s2 * s2 - coeff * s1 * s2;
    return (2.0 / n) * std::sqrt(std::max(0.0, power));
}

double rmsOf(const std::vector<float>& x) {
    double sum = 0.0;
    for (float v : x) sum += static_cast<double>(v) * static_cast<double>(v);
    return std::sqrt(sum / std::max(1, static_cast<int>(x.size())));
}

double rmsOf(const std::vector<double>& x) {
    double sum = 0.0;
    for (double v : x) sum += v * v;
    return std::sqrt(sum / std::max(1, static_cast<int>(x.size())));
}

// 16-bit PCM WAV writer (little-endian, 44-byte header). For audit only.
void writeWav16(const std::string& path, const std::vector<float>& interleaved,
                double sampleRate) {
    std::ofstream f(path, std::ios::binary);
    if (!f) {
        std::cout << "  (warn) cannot open WAV output '" << path << "'" << std::endl;
        return;
    }
    const uint32_t numFrames = static_cast<uint32_t>(interleaved.size() / 2);
    const uint32_t dataBytes = numFrames * 2 * 2;
    auto putU32 = [&f](uint32_t v) {
        f.put(static_cast<char>(v & 0xFF));
        f.put(static_cast<char>((v >> 8) & 0xFF));
        f.put(static_cast<char>((v >> 16) & 0xFF));
        f.put(static_cast<char>((v >> 24) & 0xFF));
    };
    auto putU16 = [&f](uint16_t v) {
        f.put(static_cast<char>(v & 0xFF));
        f.put(static_cast<char>((v >> 8) & 0xFF));
    };
    f.write("RIFF", 4);
    putU32(36 + dataBytes);
    f.write("WAVE", 4);
    f.write("fmt ", 4);
    putU32(16);
    putU16(1);              // PCM
    putU16(2);              // stereo
    putU32(static_cast<uint32_t>(sampleRate));
    putU32(static_cast<uint32_t>(sampleRate) * 4);
    putU16(4);              // block align
    putU16(16);             // bits per sample
    f.write("data", 4);
    putU32(dataBytes);
    for (float s : interleaved) {
        const float c = std::clamp(s, -1.0f, 1.0f);
        const int16_t q = static_cast<int16_t>(std::lround(c * 32767.0f));
        putU16(static_cast<uint16_t>(q));
    }
}

// Extract one channel of an interleaved-stereo buffer as a mono vector
// (Goertzel probes must run on mono data at the true sample rate).
template <typename T>
std::vector<T> channelOf(const std::vector<T>& interleaved, int channel) {
    std::vector<T> out;
    out.reserve(interleaved.size() / 2);
    for (size_t i = static_cast<size_t>(channel); i < interleaved.size(); i += 2) {
        out.push_back(interleaved[i]);
    }
    return out;
}

float quantize16(float x) {
    return std::round(std::clamp(x, -1.0f, 1.0f) * 32767.0f) / 32767.0f;
}

// 12 s / 44.1 kHz / 16-bit-stereo program material (the "low-FLAC" scenario):
//   0-4 s   exponential sine sweep 20 Hz -> 16 kHz
//   4-8 s   music-like sum of partials with slow tremolo + L/R decorrelation
//   8-12 s  brief full-scale 997 Hz bursts every 750 ms
// Everything is quantized to 16-bit steps to emulate the decoded-stream domain.
std::vector<float> makeLowFlacProgram(int totalFrames, double fs) {
    std::vector<float> prog(static_cast<size_t>(totalFrames) * 2, 0.0f);
    const int sweepEnd = static_cast<int>(fs * 4.0);
    const int partialsEnd = static_cast<int>(fs * 8.0);
    const double k = std::log(16000.0 / 20.0) / 4.0;
    for (int i = 0; i < totalFrames; ++i) {
        const double t = static_cast<double>(i) / fs;
        double l = 0.0, r = 0.0;
        if (i < sweepEnd) {
            const double phase = 2.0 * M_PI * (20.0 / k) * (std::exp(k * t) - 1.0);
            l = 0.40 * std::sin(phase);
            r = 0.34 * std::sin(phase); // L/R imbalance -> side energy for width stage
        } else if (i < partialsEnd) {
            const double trem = 0.8 + 0.2 * std::sin(2.0 * M_PI * 0.5 * t);
            const double tl = 0.50 * std::sin(2.0 * M_PI * 110.0 * t)
                            + 0.35 * std::sin(2.0 * M_PI * 220.0 * t + 0.3)
                            + 0.25 * std::sin(2.0 * M_PI * 331.0 * t + 1.1)
                            + 0.18 * std::sin(2.0 * M_PI * 443.0 * t + 2.0)
                            + 0.12 * std::sin(2.0 * M_PI * 661.0 * t + 0.7)
                            + 0.08 * std::sin(2.0 * M_PI * 881.0 * t + 1.9);
            const double tr = 0.50 * std::sin(2.0 * M_PI * 110.0 * t + 0.5)
                            + 0.35 * std::sin(2.0 * M_PI * 220.0 * t + 1.2)
                            + 0.25 * std::sin(2.0 * M_PI * 331.0 * t + 0.1)
                            + 0.18 * std::sin(2.0 * M_PI * 443.0 * t + 2.6)
                            + 0.12 * std::sin(2.0 * M_PI * 661.0 * t + 1.4)
                            + 0.08 * std::sin(2.0 * M_PI * 881.0 * t + 0.2);
            l = 0.9 * trem * tl / 1.48;
            r = 0.9 * trem * tr / 1.48;
        } else {
            const double seg = std::fmod(t - 8.0, 0.75);
            if (seg < 0.06) {
                const double burst = std::sin(2.0 * M_PI * 997.0 * t);
                l = burst; // full-scale
                r = burst;
            }
        }
        prog[i * 2 + 0] = quantize16(static_cast<float>(l));
        prog[i * 2 + 1] = quantize16(static_cast<float>(r));
    }
    return prog;
}

// Snapshot with EVERY stage enabled (EQ with a real preset curve, crossfeed,
// reverb low-wet, saturation, width, crossover, loudness contour, dynamic EQ,
// limiter; resampler at ratio 1.0 so the engine bypass guard keeps it transparent).
std::shared_ptr<DspParamSnapshot> makeAllStagesSnapshot(double fs) {
    auto snap = std::make_shared<DspParamSnapshot>();
    snap->generation = 5000;
    snap->sampleRate = fs;
    snap->resetRequested = true;
    snap->activeStages = 0xFFFFFFFF;

    snap->eq.enabled = true;
    snap->eq.preampDb = -1.5;
    snap->eq.bandCount = 10;
    static const double kFreqs[10] = {32, 64, 125, 250, 500, 1000,
                                      2000, 4000, 8000, 16000};
    static const double kGains[10] = {4, 3, -1, -1, 2, 4, 5, 5, 5, 6}; // "Rock"-ish
    for (int b = 0; b < 10; ++b) {
        snap->eq.bands[b].frequency = kFreqs[b];
        snap->eq.bands[b].gainDb = kGains[b];
        snap->eq.bands[b].q = 1.414;
        snap->eq.bands[b].type = FilterType::Peaking;
        snap->eq.bands[b].enabled = true;
    }

    snap->crossfeed.enabled = true;
    snap->crossfeed.delayUs = 350.0;
    snap->crossfeed.feedDb = -9.0;
    snap->crossfeed.fcut = 650.0;

    snap->reverb.enabled = true;
    snap->reverb.wetDry = 0.15; // low wet
    snap->reverb.preset = 0;    // Studio
    snap->reverb.damping = 0.2;
    snap->reverb.preparedIr = PreparedIr::createSynthetic(fs, 0, 0.2f);

    snap->panner.balance = 0.0;
    snap->panner.monoMix = false;

    snap->resampler.enabled = true;
    snap->resampler.inRate = fs;
    snap->resampler.outRate = fs;

    snap->limiter.enabled = true;
    snap->limiter.lookaheadMs = 5.0;
    snap->limiter.thresholdDb = -0.2;
    snap->limiter.releaseMs = 50.0;
    snap->limiter.truePeakMode = true;

    snap->saturation.enabled = true;
    snap->saturation.drive = 0.35;
    snap->saturation.mix = 0.40;
    snap->saturation.tilt = 0.30;

    snap->stereoWidth.enabled = true;
    snap->stereoWidth.width = 1.3;

    snap->loudness.enabled = true;
    snap->loudness.intensity = 0.5;
    snap->loudness.volumeLinear = 0.35;

    snap->subCrossover.enabled = true;
    snap->subCrossover.cornerHz = 80.0;
    snap->subCrossover.slopeDbPerOct = 24.0;
    snap->subCrossover.subGain = 0.8;

    snap->dynamicEq.enabled = true;
    snap->dynamicEq.bandCount = 1;
    snap->dynamicEq.bands[0].frequency = 1000.0;
    snap->dynamicEq.bands[0].q = 2.0;
    snap->dynamicEq.bands[0].thresholdDb = -25.0;
    snap->dynamicEq.bands[0].ratio = 3.0;
    snap->dynamicEq.bands[0].attackMs = 5.0;
    snap->dynamicEq.bands[0].releaseMs = 120.0;
    snap->dynamicEq.bands[0].maxCutDb = -8.0;
    snap->dynamicEq.bands[0].enabled = true;

    return snap;
}

} // namespace

// ---- 1. HarmonicSaturation: bypass transparency ---------------------------------

void runHarmonicSaturationBypassTest() {
    std::cout << "\n=== [EXP 1/8] HarmonicSaturation bypass transparency (drive=0 / mix=0 / disabled) ===" << std::endl;
    const double fs = 44100.0;
    const int frames = 8192;
    std::vector<float> in(frames * 2);
    for (int i = 0; i < frames; ++i) {
        const float s = 0.5f * std::sin(2.0f * static_cast<float>(M_PI) * 997.0f * i / static_cast<float>(fs));
        in[i * 2] = s;
        in[i * 2 + 1] = 0.25f * std::sin(2.0f * static_cast<float>(M_PI) * 331.0f * i / static_cast<float>(fs));
    }

    // drive = 0, mix = 0 -> wet == dry -> bitwise identity.
    {
        HarmonicSaturation sat;
        sat.setSampleRate(fs);
        sat.configure(0.0, 0.0, 0.0);
        sat.setEnabled(true);
        sat.reset();
        std::vector<float> out = in;
        sat.processInterleaved(out.data(), frames, 2);
        assert(std::memcmp(in.data(), out.data(), in.size() * sizeof(float)) == 0);
        std::cout << "  ✓ drive=0/mix=0: byte-for-byte identity (zero added energy)." << std::endl;
    }

    // drive = 0, mix = 0.5 -> wet == dry regardless of mix -> bitwise identity.
    {
        HarmonicSaturation sat;
        sat.setSampleRate(fs);
        sat.configure(0.0, 0.5, 1.0);
        sat.setEnabled(true);
        sat.reset();
        std::vector<float> out = in;
        sat.processInterleaved(out.data(), frames, 2);
        assert(std::memcmp(in.data(), out.data(), in.size() * sizeof(float)) == 0);
        std::cout << "  ✓ drive=0 with any mix/tilt: byte-for-byte identity." << std::endl;
    }

    // Disabled stage -> untouched buffer.
    {
        HarmonicSaturation sat;
        sat.setSampleRate(fs);
        sat.configure(0.8, 1.0, 0.5);
        sat.setEnabled(false);
        sat.reset();
        std::vector<float> out = in;
        sat.processInterleaved(out.data(), frames, 2);
        assert(std::memcmp(in.data(), out.data(), in.size() * sizeof(float)) == 0);
        std::cout << "  ✓ disabled stage: byte-for-byte identity." << std::endl;
    }
}

// ---- 2. HarmonicSaturation: harmonic generation ---------------------------------

void runHarmonicSaturationHarmonicsTest() {
    std::cout << "\n=== [EXP 2/8] HarmonicSaturation spectral probe (220.5 Hz, drive>0) ===" << std::endl;
    const double fs = 44100.0;
    const double f0 = 220.5;            // exactly 200 samples/period @ 44.1k
    const int period = 200;
    const int frames = 200 * 100;       // 100 integer periods -> bin-centered probes
    const int settle = 200 * 10;        // skip first 10 periods

    std::vector<float> in(frames * 2);
    for (int i = 0; i < frames; ++i) {
        const float s = 0.5f * static_cast<float>(std::sin(2.0 * M_PI * f0 * i / fs));
        in[i * 2] = s;
        in[i * 2 + 1] = s;
    }

    const std::vector<float> inMono = channelOf(in, 0);

    double b3Baseline = 1e-6;

    // Baseline (drive = 0): the same probe must stay essentially pure.
    {
        HarmonicSaturation sat;
        sat.setSampleRate(fs);
        sat.configure(0.0, 1.0, 0.0);
        sat.setEnabled(true);
        sat.reset();
        std::vector<float> out = in;
        sat.processInterleaved(out.data(), frames, 2);
        const std::vector<float> outMono = channelOf(out, 0);
        const std::vector<float> tail(outMono.begin() + settle, outMono.end());
        const double b1 = goertzelAmplitude(tail, fs, f0);
        b3Baseline = goertzelAmplitude(tail, fs, 3.0 * f0);
        std::cout << "  Baseline drive=0: h1=" << b1 << " h3=" << b3Baseline << std::endl;
        // At float32 noise floor both are ~0 (EXP 1's memcmp already proved
        // bit-exactness) — gate against an absolute -160 dBFS floor as well.
        assert(b3Baseline < std::max(0.005 * b1, 1e-8));
    }

    // drive = 0.8, mix = 1.0, tilt = 0: tanh waveshaping -> strong ODD harmonics.
    HarmonicSaturation sat;
    sat.setSampleRate(fs);
    sat.configure(0.8, 1.0, 0.0);
    sat.setEnabled(true);
    sat.reset();
    std::vector<float> out = in;
    sat.processInterleaved(out.data(), frames, 2);
    {
        const std::vector<float> outMono = channelOf(out, 0);
        const std::vector<float> tail(outMono.begin() + settle, outMono.end());
        const double o1 = goertzelAmplitude(tail, fs, f0);
        const double o2 = goertzelAmplitude(tail, fs, 2.0 * f0);
        const double o3 = goertzelAmplitude(tail, fs, 3.0 * f0);
        const double o5 = goertzelAmplitude(tail, fs, 5.0 * f0);

        std::cout << "  drive=0.8/mix=1: h1=" << o1 << " h2=" << o2
                  << " h3=" << o3 << " h5=" << o5 << std::endl;

        // The 3rd harmonic must clearly appear (tanh soft-clip), 20x over the
        // drive=0 baseline and > 5% of the fundamental.
        assert(o3 > 0.05 * o1);
        assert(o3 > 20.0 * b3Baseline);
        // 2x stays negligible: tanh is odd-symmetric so even harmonics are absent
        // by design — the exciter produces tape-style odd-order harmonics.
        assert(o2 < 0.30 * o3);
        std::cout << "  ✓ 3rd harmonic generated (" << (20.0 * std::log10(o3 / o1))
                  << " dBc); 2nd harmonic negligible (" << (20.0 * std::log10(o2 / o1))
                  << " dBc) — odd-symmetric tanh, expected for this implementation."
                  << std::endl;
    }
}

// ---- 3. HarmonicSaturation: bounded output -------------------------------------

void runHarmonicSaturationBoundedTest() {
    std::cout << "\n=== [EXP 3/8] HarmonicSaturation bounded output for full-scale input ===" << std::endl;
    const double fs = 48000.0;
    const int frames = 16384;
    std::vector<float> in(frames * 2);
    for (int i = 0; i < frames; ++i) {
        // Mix of worst-case full-scale content: alternating polarity square-ish
        // steps plus an over-full-scale 18 kHz sine.
        const float s = (i % 7 < 3) ? 1.0f : -1.0f;
        const float t = static_cast<float>(i) / static_cast<float>(fs);
        in[i * 2] = s;
        in[i * 2 + 1] = 1.2f * std::sin(2.0f * static_cast<float>(M_PI) * 18000.0f * t);
    }

    HarmonicSaturation sat;
    sat.setSampleRate(fs);
    sat.configure(1.0, 1.0, 1.0); // worst case: full drive, 100% wet, max tilt emphasis
    sat.setEnabled(true);
    sat.reset();
    sat.processInterleaved(in.data(), frames, 2);

    float maxAbs = 0.0f;
    for (float v : in) maxAbs = std::max(maxAbs, std::abs(v));
    std::cout << "  Max |out| = " << maxAbs << " (gate: <= 1.001)" << std::endl;
    assert(maxAbs <= 1.001f);
    std::cout << "  ✓ tanh shaper is amplitude-bounded: |out| <= 1.0 + eps even with tilt emphasis." << std::endl;
}

// ---- 4. StereoWidth: mono collapse / identity / widening -------------------------

void runStereoWidthTest() {
    std::cout << "\n=== [EXP 4/8] StereoWidth mono collapse / identity / widened side ===" << std::endl;
    const double fs = 44100.0;
    const int frames = 8192;
    std::vector<float> in(frames * 2);
    for (int i = 0; i < frames; ++i) {
        const double t = static_cast<double>(i) / fs;
        const float l = 0.5f * std::sin(2.0 * M_PI * 997.0 * t);
        const float r = 0.35f * std::sin(2.0 * M_PI * 1501.0 * t + 1.0);
        in[i * 2] = l;
        in[i * 2 + 1] = r;
    }

    double sideRmsW1 = 0.0, sideRmsW15 = 0.0;

    // width = 0 -> both channels collapse to the mono sum.
    {
        StereoWidth w;
        w.configure(0.0);
        w.setEnabled(true);
        std::vector<float> out = in;
        w.processInterleaved(out.data(), frames, 2);
        double maxDiff = 0.0;
        for (int i = 0; i < frames; ++i) {
            maxDiff = std::max(maxDiff, static_cast<double>(std::abs(out[i * 2] - out[i * 2 + 1])));
        }
        std::cout << "  width=0: max |L-R| = " << maxDiff << std::endl;
        assert(maxDiff < 1e-6);
    }

    // width = 1 -> exact passthrough (fast path).
    {
        StereoWidth w;
        w.configure(1.0);
        w.setEnabled(true);
        std::vector<float> out = in;
        w.processInterleaved(out.data(), frames, 2);
        assert(std::memcmp(in.data(), out.data(), in.size() * sizeof(float)) == 0);
        std::cout << "  ✓ width=1: byte-for-byte identity." << std::endl;
    }

    // width = 1.5 -> side (L-R) RMS grows vs width = 1.
    {
        StereoWidth w;
        w.configure(1.0);
        w.setEnabled(true);
        std::vector<float> out = in;
        w.processInterleaved(out.data(), frames, 2);
        std::vector<float> side(frames);
        for (int i = 0; i < frames; ++i) side[i] = out[i * 2] - out[i * 2 + 1];
        sideRmsW1 = rmsOf(side);
    }
    {
        StereoWidth w;
        w.configure(1.5);
        w.setEnabled(true);
        std::vector<float> out = in;
        w.processInterleaved(out.data(), frames, 2);
        std::vector<float> side(frames);
        for (int i = 0; i < frames; ++i) side[i] = out[i * 2] - out[i * 2 + 1];
        sideRmsW15 = rmsOf(side);
    }
    std::cout << "  Side RMS: width=1 -> " << sideRmsW1 << ", width=1.5 -> " << sideRmsW15 << std::endl;
    assert(sideRmsW15 > 1.4 * sideRmsW1);
    std::cout << "  ✓ width=1.5 scales side energy up ~1.5x (measured " << (sideRmsW15 / sideRmsW1) << "x)." << std::endl;

    // Disabled -> untouched buffer.
    {
        StereoWidth w;
        w.configure(1.5);
        w.setEnabled(false);
        std::vector<float> out = in;
        w.processInterleaved(out.data(), frames, 2);
        assert(std::memcmp(in.data(), out.data(), in.size() * sizeof(float)) == 0);
        std::cout << "  ✓ disabled: byte-for-byte identity." << std::endl;
    }
}

// ---- 5. LoudnessContour: reference-flat / low-volume lift ------------------------

void runLoudnessContourTest() {
    std::cout << "\n=== [EXP 5/8] LoudnessContour reference-flat + monotonic low-volume lift ===" << std::endl;
    const double fs = 44100.0;
    const int frames = static_cast<int>(fs * 1.5);
    const int settle = static_cast<int>(fs * 0.5);

    auto liftAt = [&](double intensity, double volumeLinear, double probeHz, int nFrames, int skip) {
        std::vector<float> in(nFrames * 2);
        const double amp = 0.25;
        for (int i = 0; i < nFrames; ++i) {
            const float s = static_cast<float>(amp * std::sin(2.0 * M_PI * probeHz * i / fs));
            in[i * 2] = s;
            in[i * 2 + 1] = s;
        }
        LoudnessContour lc;
        lc.setSampleRate(fs);
        lc.configure(intensity, volumeLinear);
        lc.setEnabled(true);
        lc.reset();
        lc.processInterleaved(in.data(), nFrames, 2);
        const std::vector<float> mono = channelOf(in, 0);
        const std::vector<float> tail(mono.begin() + skip, mono.end());
        return goertzelAmplitude(tail, fs, probeHz) / amp;
    };

    // Reference volume: volumeLinear = 1.0 -> zero lift -> identity (no tonal delta).
    {
        LoudnessContour lc;
        lc.setSampleRate(fs);
        lc.configure(0.8, 1.0);
        lc.setEnabled(true);
        lc.reset();
        std::vector<float> in(frames * 2);
        for (int i = 0; i < frames; ++i) {
            const float s = 0.25f * std::sin(2.0f * static_cast<float>(M_PI) * 60.0f * i / static_cast<float>(fs));
            in[i * 2] = s;
            in[i * 2 + 1] = s;
        }
        std::vector<float> out = in;
        lc.processInterleaved(out.data(), frames, 2);
        double maxDiff = 0.0;
        for (size_t i = 0; i < in.size(); ++i) {
            maxDiff = std::max(maxDiff, static_cast<double>(std::abs(out[i] - in[i])));
        }
        std::cout << "  volumeLinear=1.0 (intensity 0.8): max |delta| = " << maxDiff << std::endl;
        assert(maxDiff < 1e-6);
        std::cout << "  ✓ full-volume reference: no tonal delta (contour vanishes at unity)." << std::endl;
    }

    // intensity = 0 or disabled -> identity.
    {
        LoudnessContour lc;
        lc.setSampleRate(fs);
        lc.configure(0.0, 0.2);
        lc.setEnabled(true);
        lc.reset();
        std::vector<float> in(frames * 2, 0.1f);
        std::vector<float> out = in;
        lc.processInterleaved(out.data(), frames, 2);
        assert(std::memcmp(in.data(), out.data(), in.size() * sizeof(float)) == 0);
        std::cout << "  ✓ intensity=0: byte-for-byte identity." << std::endl;
    }

    // Low volume + intensity > 0 -> low-band lift, monotonic in intensity;
    // 1 kHz band stays ~neutral (bass shelf only).
    const double lift20 = liftAt(0.2, 0.2, 60.0, frames, settle);
    const double lift50 = liftAt(0.5, 0.2, 60.0, frames, settle);
    const double lift100 = liftAt(1.0, 0.2, 60.0, frames, settle);
    const double lift1k = liftAt(1.0, 0.2, 1000.0, frames, settle);

    std::cout << "  60 Hz lift @ volume 0.2: intensity 0.2 -> " << (20.0 * std::log10(lift20))
              << " dB, 0.5 -> " << (20.0 * std::log10(lift50))
              << " dB, 1.0 -> " << (20.0 * std::log10(lift100)) << " dB" << std::endl;
    std::cout << "  1 kHz delta @ intensity 1.0: " << (20.0 * std::log10(lift1k)) << " dB" << std::endl;

    assert(lift20 > 1.02);
    assert(lift50 > lift20 + 0.05);
    assert(lift100 > lift50 + 0.05);
    assert(lift100 > 1.4);  // > ~3 dB bass lift at full intensity
    assert(std::abs(20.0 * std::log10(lift1k)) < 0.5);
    std::cout << "  ✓ low-volume bass lift is present and strictly monotonic in intensity; 1 kHz unaffected." << std::endl;
}

// ---- 6. SubCrossover: bass redirection (documented behavior) ----------------------
//
// The header explicitly documents this is NOT true LFE routing: a
// Linkwitz-Riley-style low-passed mono sum is ADDED back into both channels
// at subGain; mains keep full range (no high-pass). So below the corner the
// output grows (dry + sub tap) and above the corner the tap attenuates per the
// LR slope while the dry path stays intact. We assert exactly that.
void runSubCrossoverTest() {
    std::cout << "\n=== [EXP 6/8] SubCrossover bass redirection (LR-style tap, no HP on mains) ===" << std::endl;
    const double fs = 44100.0;
    const int settle = 8192;
    const int measure = static_cast<int>(fs); // 1 s, integer Hz probes -> no leakage
    const int frames = settle + measure;

    auto measureTap = [&](SubCrossover& sc, double probeHz) -> double {
        std::vector<float> in(frames * 2);
        const double amp = 0.25;
        for (int i = 0; i < frames; ++i) {
            const float s = static_cast<float>(amp * std::sin(2.0 * M_PI * probeHz * i / fs));
            in[i * 2] = s;
            in[i * 2 + 1] = s;
        }
        std::vector<float> out = in;
        sc.processInterleaved(out.data(), frames, 2);
        std::vector<double> delta(static_cast<size_t>(measure));
        std::vector<double> deltaR(static_cast<size_t>(measure));
        double maxLRDiff = 0.0;
        for (int i = 0; i < measure; ++i) {
            const int idx = settle + i;
            delta[i] = static_cast<double>(out[idx * 2]) - static_cast<double>(in[idx * 2]);
            deltaR[i] = static_cast<double>(out[idx * 2 + 1]) - static_cast<double>(in[idx * 2 + 1]);
            maxLRDiff = std::max(maxLRDiff, std::abs(delta[i] - deltaR[i]));
        }
        assert(maxLRDiff < 1e-6); // the sub tap must be a coherent mono sum
        return goertzelAmplitude(delta, fs, probeHz) / amp;
    };

    // Disabled / subGain=0 -> identity.
    {
        SubCrossover sc;
        sc.setSampleRate(fs);
        sc.setEnabled(false);
        std::vector<float> in(frames * 2, 0.05f);
        std::vector<float> out = in;
        sc.processInterleaved(out.data(), frames, 2);
        assert(std::memcmp(in.data(), out.data(), in.size() * sizeof(float)) == 0);
        std::cout << "  ✓ disabled: byte-for-byte identity." << std::endl;
    }
    {
        SubCrossover sc;
        sc.setSampleRate(fs);
        sc.configure(80.0, 24.0, 0.0);
        sc.setEnabled(true);
        std::vector<float> in(frames * 2, 0.05f);
        std::vector<float> out = in;
        sc.processInterleaved(out.data(), frames, 2);
        assert(std::memcmp(in.data(), out.data(), in.size() * sizeof(float)) == 0);
        std::cout << "  ✓ subGain=0: byte-for-byte identity (early return)." << std::endl;
    }

    // 24 dB/oct (LR4): tap magnitude vs frequency.
    {
        SubCrossover sc;
        sc.setSampleRate(fs);
        sc.configure(80.0, 24.0, 0.8);
        sc.setEnabled(true);
        sc.reset();

        const double t40 = measureTap(sc, 40.0);
        const double t80 = measureTap(sc, 80.0);
        const double t160 = measureTap(sc, 160.0);
        const double t320 = measureTap(sc, 320.0);
        const double t640 = measureTap(sc, 640.0);

        std::cout << "  LR4 tap ratios: 40Hz=" << t40 << " 80Hz=" << t80
                  << " 160Hz=" << t160 << " 320Hz=" << t320 << " 640Hz=" << t640 << std::endl;

        // Below corner: strong redirected tap (DC gain of the LP = 1 -> ~0.8 x input).
        assert(t40 > 0.55 && t40 < 0.95);
        // At corner: LR4 is -6 dB at fc -> tap ~0.4.
        assert(t80 > 0.25 && t80 < 0.55);
        // Slope between one and two octaves above corner must be ~24 dB/oct.
        const double slope1 = -20.0 * std::log10(t320 / t160);
        const double slope2 = -20.0 * std::log10(t640 / t320);
        std::cout << "  Slope: " << slope1 << " dB/oct (160->320), " << slope2 << " dB/oct (320->640)" << std::endl;
        assert(slope1 > 18.0 && slope1 < 30.0);
        assert(slope2 > 18.0 && slope2 < 30.0);
        // Mains keep full range: above the corner the dry path dominates (tap deeply attenuated).
        assert(t640 < 0.005);
        std::cout << "  ✓ LR4 bass redirection: tap 0.8 at LF, ~24 dB/oct slope, dry mains intact (no HP)." << std::endl;
    }

    // 12 dB/oct (LR2): slope about half.
    {
        SubCrossover sc;
        sc.setSampleRate(fs);
        sc.configure(80.0, 12.0, 0.8);
        sc.setEnabled(true);
        sc.reset();

        const double t160 = measureTap(sc, 160.0);
        const double t320 = measureTap(sc, 320.0);
        const double slope = -20.0 * std::log10(t320 / t160);
        std::cout << "  LR2 tap ratios: 160Hz=" << t160 << " 320Hz=" << t320
                  << " (slope " << slope << " dB/oct)" << std::endl;
        assert(slope > 9.0 && slope < 15.0);
        std::cout << "  ✓ LR2 (12 dB/oct) slope verified." << std::endl;
    }
}

// ---- 7. DynamicEQ: threshold ducking / release / disabled --------------------------

void runDynamicEqTest() {
    std::cout << "\n=== [EXP 7/8] DynamicEQ in-band ducking, threshold gate, release ===" << std::endl;
    const double fs = 44100.0;
    const int block = 512;
    const double f0 = 1000.0;

    DynamicEqBandParam band;
    band.frequency = f0;
    band.q = 2.0;
    band.thresholdDb = -30.0;
    band.ratio = 3.0;
    band.attackMs = 5.0;
    band.releaseMs = 120.0;
    band.maxCutDb = -12.0;
    band.enabled = true;

    // Sustained in-band sine ABOVE threshold -> gain reduction approaches max cut.
    {
        DynamicEQ deq;
        deq.setSampleRate(fs);
        deq.setBandCount(1);
        deq.setBand(0, band);
        deq.setEnabled(true);
        deq.reset();

        const double amp = 0.5; // ~ -6 dBFS -> 24 dB over a -30 dB threshold
        const int seconds = 2;
        std::vector<float> buf(block * 2);
        for (int b = 0; b < static_cast<int>(fs * seconds) / block; ++b) {
            for (int i = 0; i < block; ++i) {
                const int idx = b * block + i;
                const float s = static_cast<float>(amp * std::sin(2.0 * M_PI * f0 * idx / fs));
                buf[i * 2] = s;
                buf[i * 2 + 1] = s;
            }
            deq.processInterleaved(buf.data(), block, 2);
        }
        const double gr = deq.getGainReductionDb(0);
        std::cout << "  GR after 2 s loud tone: " << gr << " dB (target max cut: -12 dB)" << std::endl;
        assert(gr <= -10.8); // approaches the implemented max cut
        // Output amplitude at f0 must be reduced by ~the cut (peaking gain at f0 == cut).
        std::vector<float> tailBuf(fs * 2, 0.0f);
        for (int i = 0; i < static_cast<int>(fs); ++i) {
            tailBuf[i * 2] = static_cast<float>(amp * std::sin(2.0 * M_PI * f0 * i / fs));
            tailBuf[i * 2 + 1] = tailBuf[i * 2];
        }
        deq.processInterleaved(tailBuf.data(), static_cast<int>(fs), 2);
        const std::vector<float> tail = channelOf(tailBuf, 0);
        const double outAmp = goertzelAmplitude(tail, fs, f0);
        const double attenDb = 20.0 * std::log10(outAmp / amp);
        std::cout << "  Measured in-band attenuation: " << attenDb << " dB (gate: -18..-6 dB)" << std::endl;
        assert(attenDb > -18.0 && attenDb < -6.0);
        std::cout << "  ✓ sustained in-band tone ducks toward the -12 dB max cut." << std::endl;
    }

    // Below threshold -> ~0 cut, ~identity.
    {
        DynamicEQ deq;
        deq.setSampleRate(fs);
        deq.setBandCount(1);
        deq.setBand(0, band);
        deq.setEnabled(true);
        deq.reset();

        const double amp = 0.02; // -34 dBFS < -30 dB threshold
        std::vector<float> buf(static_cast<int>(fs) * 2);
        for (int i = 0; i < static_cast<int>(fs); ++i) {
            buf[i * 2] = static_cast<float>(amp * std::sin(2.0 * M_PI * f0 * i / fs));
            buf[i * 2 + 1] = buf[i * 2];
        }
        deq.processInterleaved(buf.data(), static_cast<int>(fs), 2);
        const double gr = deq.getGainReductionDb(0);
        const std::vector<float> tail = channelOf(buf, 0);
        const double outAmp = goertzelAmplitude(tail, fs, f0);
        const double deltaDb = 20.0 * std::log10(outAmp / amp);
        std::cout << "  GR below threshold: " << gr << " dB, amplitude delta: " << deltaDb << " dB" << std::endl;
        assert(std::abs(gr) < 0.5);
        assert(std::abs(deltaDb) < 0.5);
        std::cout << "  ✓ below-threshold signal untouched." << std::endl;
    }

    // Release: after the tone stops, gain reduction returns toward 0.
    {
        DynamicEQ deq;
        deq.setSampleRate(fs);
        deq.setBandCount(1);
        deq.setBand(0, band);
        deq.setEnabled(true);
        deq.reset();

        const double amp = 0.5;
        std::vector<float> buf(block * 2);
        for (int b = 0; b < static_cast<int>(fs * 1.0) / block; ++b) {
            for (int i = 0; i < block; ++i) {
                const int idx = b * block + i;
                const float s = static_cast<float>(amp * std::sin(2.0 * M_PI * f0 * idx / fs));
                buf[i * 2] = s;
                buf[i * 2 + 1] = s;
            }
            deq.processInterleaved(buf.data(), block, 2);
        }
        assert(deq.getGainReductionDb(0) <= -9.0); // engaged before release
        std::fill(buf.begin(), buf.end(), 0.0f);
        for (int b = 0; b < static_cast<int>(fs * 1.0) / block; ++b) {
            deq.processInterleaved(buf.data(), block, 2);
        }
        const double gr = deq.getGainReductionDb(0);
        std::cout << "  GR after 1 s of silence: " << gr << " dB (gate: > -0.5 dB)" << std::endl;
        assert(gr > -0.5);
        std::cout << "  ✓ release returns toward 0 after the signal stops." << std::endl;
    }

    // Disabled -> identity.
    {
        DynamicEQ deq;
        deq.setSampleRate(fs);
        deq.setBandCount(1);
        deq.setBand(0, band);
        deq.setEnabled(false);
        deq.reset();
        std::vector<float> in(block * 2);
        for (int i = 0; i < block; ++i) {
            in[i * 2] = 0.5f * std::sin(2.0f * static_cast<float>(M_PI) * f0 * i / static_cast<float>(fs));
            in[i * 2 + 1] = in[i * 2];
        }
        std::vector<float> out = in;
        deq.processInterleaved(out.data(), block, 2);
        assert(std::memcmp(in.data(), out.data(), in.size() * sizeof(float)) == 0);
        std::cout << "  ✓ disabled: byte-for-byte identity." << std::endl;
    }
}

// ---- 8. Full-chain "low-FLAC" integration test ------------------------------------

void runLowFlacFullChainIntegrationTest(const char* wavOutDir) {
    std::cout << "\n=== [EXP 8/8] Full-chain low-FLAC integration (44.1k/16-bit, ALL stages, 12 s) ===" << std::endl;

    const double fs = 44100.0;
    const double ceiling = std::pow(10.0, -0.2 / 20.0); // -0.2 dBFS limiter ceiling
    const int blockSize = 512;
    const int totalFrames = static_cast<int>(fs * 12.0);
    const int blocks = totalFrames / blockSize;

    const std::vector<float> program = makeLowFlacProgram(totalFrames, fs);

    auto& engine = AudioDspEngine::instance();
    engine.setAutoDegradeMonitorEnabled(false); // deterministic host-side measurement
    engine.clearAutoDegradedStages();
    engine.setSampleRate(fs);
    auto snap = makeAllStagesSnapshot(fs);
    engine.publishParams(snap);

    // ---- Run 1: ALL stages enabled ------------------------------------------------
    std::vector<float> out = program;
    for (int b = 0; b < blocks; ++b) {
        engine.processInterleaved(&out[b * blockSize * 2], blockSize, 2);
    }

    // (a) finite
    size_t nonFinite = 0;
    for (float v : out) nonFinite += (!std::isfinite(v)) ? 1u : 0u;
    assert(nonFinite == 0);
    std::cout << "  ✓ (a) all " << out.size() << " output samples finite (0 NaN/Inf)." << std::endl;

    // (b) bounded by the limiter ceiling
    float maxAbs = 0.0f;
    for (float v : out) maxAbs = std::max(maxAbs, std::abs(v));
    std::cout << "  ✓ (b) max |out| = " << maxAbs << " (ceiling " << ceiling << " + 1e-3 slack)"
              << (maxAbs <= ceiling + 1e-3 ? " -> PASS" : " -> FAIL") << std::endl;
    assert(maxAbs <= ceiling + 1e-3);

    // (c) not silent + energy ratio in sane range
    const double outEnergy = rmsOf(out);
    double inEnergy = 0.0;
    {
        double sum = 0.0;
        for (float v : program) sum += static_cast<double>(v) * static_cast<double>(v);
        inEnergy = std::sqrt(sum / static_cast<double>(program.size()));
    }
    const double ratio = (outEnergy > 1e-12) ? outEnergy / inEnergy : 0.0;
    std::cout << "  ✓ (c) out RMS " << outEnergy << " / in RMS " << inEnergy
              << " -> energy ratio " << ratio << " (sane range 0.05..20)" << std::endl;
    assert(outEnergy > 0.01);
    assert(ratio > 0.05 && ratio < 20.0);

    // WAV audit file (temp build dir / caller-supplied dir — never committed)
    std::string wavPath = (wavOutDir && wavOutDir[0] != '\0')
                              ? (std::string(wavOutDir) + "/pulsr_lowflac_processed.wav")
                              : "pulsr_lowflac_processed.wav";
    writeWav16(wavPath, out, fs);
    std::cout << "  ✓ WAV audit file written: " << wavPath << std::endl;

    // (d) bit-perfect bypass: same input, all stages disabled -> bitwise identical
    {
        engine.setActiveStages(0);
        std::vector<float> bypass = program;
        for (int b = 0; b < blocks; ++b) {
            engine.processInterleaved(&bypass[b * blockSize * 2], blockSize, 2);
        }
        assert(std::memcmp(program.data(), bypass.data(), program.size() * sizeof(float)) == 0);
        std::cout << "  ✓ (d) activeStages=0: byte-for-byte identical to input." << std::endl;
        engine.setActiveStages(0xFFFFFFFF);
    }

    // (e) mid-stream stage-mask toggling: no crash, output stays bounded
    const struct { uint32_t mask; const char* name; } kStages[] = {
        {STAGE_EQ, "EQ"},           {STAGE_CROSSFEED, "CROSSFEED"},
        {STAGE_REVERB, "REVERB"},   {STAGE_PANNER, "PANNER"},
        {STAGE_LIMITER, "LIMITER"}, {STAGE_RESAMPLER, "RESAMPLER"},
        {STAGE_SATURATION, "SATURATION"}, {STAGE_WIDTH, "WIDTH"},
        {STAGE_CROSSOVER, "CROSSOVER"},   {STAGE_LOUDNESS, "LOUDNESS"},
        {STAGE_DYNEQ, "DYNEQ"},
    };
    const int halfBlocks = blocks / 2;
    for (const auto& s : kStages) {
        engine.reset();
        engine.setActiveStages(0xFFFFFFFF);
        std::vector<float> run = program;
        bool finite = true;
        float runMax = 0.0f;
        for (int b = 0; b < blocks; ++b) {
            if (b == halfBlocks) {
                engine.setActiveStages(0xFFFFFFFF & ~s.mask); // toggle off mid-stream
            }
            engine.processInterleaved(&run[b * blockSize * 2], blockSize, 2);
            for (int i = 0; i < blockSize * 2; ++i) {
                const float v = run[b * blockSize * 2 + i];
                if (!std::isfinite(v)) finite = false;
                runMax = std::max(runMax, std::abs(v));
            }
        }
        if (s.mask == STAGE_LIMITER) {
            // Limiter off: bounded sanity check only (no ceiling guarantee).
            assert(finite && runMax < 8.0f);
            std::cout << "  ✓ (e) toggle OFF " << s.name << ": finite, max |out| " << runMax
                      << " (limiter off -> sanity bound 8.0)" << std::endl;
        } else {
            assert(finite && runMax <= ceiling + 1e-3);
            std::cout << "  ✓ (e) toggle OFF " << s.name << ": finite, max |out| " << runMax
                      << " <= ceiling " << ceiling << std::endl;
        }
    }
    std::cout << "  ✓ (e) all 11 mid-stream stage toggles survived with bounded output." << std::endl;
}

int main(int argc, char** argv) {
#if defined(_MSC_VER) && defined(_DEBUG)
    // Fail fast in unattended runs: send assert/CRT diagnostics to stderr
    // instead of popping a modal dialog that blocks the process forever.
    _CrtSetReportMode(_CRT_WARN, _CRTDBG_MODE_FILE);
    _CrtSetReportFile(_CRT_WARN, _CRTDBG_FILE_STDERR);
    _CrtSetReportMode(_CRT_ERROR, _CRTDBG_MODE_FILE);
    _CrtSetReportFile(_CRT_ERROR, _CRTDBG_FILE_STDERR);
    _CrtSetReportMode(_CRT_ASSERT, _CRTDBG_MODE_FILE);
    _CrtSetReportFile(_CRT_ASSERT, _CRTDBG_FILE_STDERR);
#endif
    std::cout << std::unitbuf;
    std::cout << "====================================================" << std::endl;
    std::cout << "  Pulsr DSP Expansion Test Suite (5 new stages + full chain)" << std::endl;
    std::cout << "====================================================" << std::endl;

    runHarmonicSaturationBypassTest();
    runHarmonicSaturationHarmonicsTest();
    runHarmonicSaturationBoundedTest();
    runStereoWidthTest();
    runLoudnessContourTest();
    runSubCrossoverTest();
    runDynamicEqTest();
    runLowFlacFullChainIntegrationTest(argc > 1 ? argv[1] : nullptr);

    std::cout << "\n====================================================" << std::endl;
    std::cout << "  [PASS] ALL 8 DSP-EXPANSION TESTS PASSED 100%!" << std::endl;
    std::cout << "====================================================" << std::endl;
    return 0;
}
