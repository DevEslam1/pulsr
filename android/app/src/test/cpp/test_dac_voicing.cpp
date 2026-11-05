// android/app/src/test/cpp/test_dac_voicing.cpp
//
// The opt-in DAC voicing stage: 4x oversampled reconstruction with a
// selectable filter character (sharp / slow / minimum-phase) plus an
// even-order harmonic "voicing" knob. Two contracts matter to the app:
//   * a disabled-and-settled stage must be BIT-exact passthrough (the engine
//     still calls stages whose raw activeStages bit is set with the enabled
//     flag off — the 0xFFFFFFFF snapshot pattern), and
//   * when enabled it must behave like the filter design claims: character
//     magnitudes, minimum-phase energy front-loading, aligned latency across
//     characters, and 2nd-harmonic injection exactly proportional to amount.
#include "../../main/cpp/AudioDspEngine.h"
#include "../../main/cpp/DacVoicing.h"
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <memory>
#include <vector>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

namespace {

int gFailures = 0;

void check(bool ok, const char* what) {
    if (!ok) {
        std::cout << "[FAIL] " << what << std::endl;
        ++gFailures;
    }
}

bool bitIdentical(const std::vector<float>& a, const std::vector<float>& b) {
    return a.size() == b.size() &&
           std::memcmp(a.data(), b.data(), a.size() * sizeof(float)) == 0;
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

// DTFT magnitude of a prototype at normalized frequency (cycles/sample).
double protoMagAt(const std::vector<float>& h, double fNorm) {
    const double w = 2.0 * M_PI * fNorm;
    double re = 0.0, im = 0.0;
    for (size_t n = 0; n < h.size(); ++n) {
        re += static_cast<double>(h[n]) * std::cos(w * static_cast<double>(n));
        im -= static_cast<double>(h[n]) * std::sin(w * static_cast<double>(n));
    }
    return std::sqrt(re * re + im * im);
}

// First index whose cumulative energy reaches frac of the total.
int energyIndex(const std::vector<float>& h, double frac) {
    double total = 0.0;
    for (float v : h) total += static_cast<double>(v) * v;
    double run = 0.0;
    for (size_t n = 0; n < h.size(); ++n) {
        run += static_cast<double>(h[n]) * h[n];
        if (run >= frac * total) return static_cast<int>(n);
    }
    return static_cast<int>(h.size()) - 1;
}

// Goertzel-style magnitude of one interleaved channel over [start, start+len).
double toneMag(const std::vector<float>& interleaved, int channels, size_t startFrame,
               size_t len, double freq, double sr) {
    const double w = 2.0 * M_PI * freq / sr;
    double re = 0.0, im = 0.0;
    for (size_t i = 0; i < len; ++i) {
        const double v = interleaved[(startFrame + i) * channels];
        re += v * std::cos(w * static_cast<double>(i));
        im -= v * std::sin(w * static_cast<double>(i));
    }
    return 2.0 * std::sqrt(re * re + im * im) / static_cast<double>(len);
}

DacVoicingParamSet voicingParams(bool enabled, int character, double amount) {
    DacVoicingParamSet p;
    p.enabled = enabled;
    p.character = character;
    p.voicingAmount = amount;
    return p;
}

// Feeds `total` frames of a `freq` Hz sine (amplitude 0.5, both channels)
// through a freshly enabled stage in 256-frame blocks and returns the ramped
// output. total must be a multiple of 256.
std::vector<float> runToneThroughStage(int character, double amount, double freq, int total,
                                       double sr) {
    DacVoicing dv;
    dv.applyParams(voicingParams(true, character, amount));
    dv.setSampleRate(sr);
    dv.setEnabled(true);
    std::vector<float> buf(static_cast<size_t>(total) * 2);
    for (int f = 0; f < total; ++f) {
        const double x = 0.5 * std::sin(2.0 * M_PI * freq * static_cast<double>(f) / sr);
        buf[static_cast<size_t>(f) * 2] = static_cast<float>(x);
        buf[static_cast<size_t>(f) * 2 + 1] = static_cast<float>(x);
    }
    for (int off = 0; off < total; off += 256) {
        dv.processInterleaved(buf.data() + static_cast<size_t>(off) * 2, 256, 2);
    }
    return buf;
}

struct ImpulseResult {
    int peakFrame = -1;
    double peakValue = 0.0;
    int latency = 0;
};

ImpulseResult impulseThroughStage(int character) {
    DacVoicing dv;
    dv.applyParams(voicingParams(true, character, 0.0));
    dv.setSampleRate(48000.0);
    dv.setEnabled(true);
    const int total = 4096;
    std::vector<float> buf(static_cast<size_t>(total) * 2, 0.0f);
    buf[0] = 1.0f;
    buf[1] = 1.0f;
    ImpulseResult r;
    for (int off = 0; off < total; off += 256) {
        dv.processInterleaved(buf.data() + static_cast<size_t>(off) * 2, 256, 2);
    }
    for (int f = 0; f < total; ++f) {
        const double v = std::abs(static_cast<double>(buf[static_cast<size_t>(f) * 2]));
        if (v > r.peakValue) {
            r.peakValue = v;
            r.peakFrame = f;
        }
    }
    r.latency = dv.getLatencyFrames();
    return r;
}

} // namespace

int main() {
    std::cout << "[TEST] DAC voicing stage (filter character + even-harmonic warmth)..."
              << std::endl;

    constexpr double kFc = 0.125; // base Nyquist at the 4x oversampled rate

    // --- Prototype designs (pure, constructor-time math) ---
    {
        const auto sharp = DacVoicing::designPrototype(DacVoicing::Sharp, kFc, 64);
        check(sharp.size() == 64, "sharp prototype length");
        double sum = 0.0;
        for (float v : sharp) sum += v;
        check(std::abs(sum - 1.0) < 1e-3, "sharp prototype DC gain unity");
        bool symmetric = true;
        for (int n = 0; n < 32; ++n) {
            if (std::abs(sharp[n] - sharp[63 - n]) > 1e-6f) symmetric = false;
        }
        check(symmetric, "sharp prototype is linear phase (symmetric taps)");
        // Probe-validated: |H(0.10)| = 0.9296, |H(0.125)| = 0.5, stopband ~1e-5.
        check(std::abs(protoMagAt(sharp, 0.10) - 0.9296) < 0.02, "sharp passband near Nyquist");
        check(std::abs(protoMagAt(sharp, kFc) - 0.5) < 0.02, "sharp half-power at base Nyquist");
        check(protoMagAt(sharp, 0.20) < 1e-3, "sharp stopband rejection");

        const auto slow = DacVoicing::designPrototype(DacVoicing::Slow, kFc, 64);
        // Probe: |H_slow(0.10)| = 0.3066, |H_slow(0.125)| = 0.0063 — the NOS
        // presentation droops well below Nyquist where sharp is still flat.
        check(protoMagAt(slow, 0.10) < 0.35, "slow droops in the sharp passband");
        check(protoMagAt(slow, 0.10) < 0.5 * protoMagAt(sharp, 0.10), "slow vs sharp droop");
        check(protoMagAt(slow, kFc) < 0.02, "slow heavily attenuates base Nyquist");

        const auto minp = DacVoicing::designPrototype(DacVoicing::MinimumPhase, kFc, 64);
        check(minp.size() == 64, "minimum-phase prototype length");
        double mpSum = 0.0;
        for (float v : minp) mpSum += v;
        check(std::abs(mpSum - 1.0) < 1e-3, "minimum-phase DC gain unity");
        // Same magnitude as sharp across the band (probe matched to 4 decimals).
        for (double f : {0.02, 0.05, 0.08, 0.10, 0.125}) {
            const double hs = protoMagAt(sharp, f);
            const double hm = protoMagAt(minp, f);
            check(std::abs(hm - hs) < 0.05 * hs, "minimum-phase magnitude tracks sharp");
        }
        // All energy front-loaded: probe puts 50% at n=8 and 90% at n=14 for
        // minimum phase vs n=31/33 for the symmetric sharp design.
        const int e50m = energyIndex(minp, 0.5);
        const int e50s = energyIndex(sharp, 0.5);
        check(e50m <= 12, "minimum-phase 50% energy front-loaded");
        check(e50m < e50s, "minimum-phase concentrates earlier than sharp");
        check(energyIndex(minp, 0.9) <= 20, "minimum-phase 90% energy front-loaded");
    }

    // --- Disabled stage is bit-exact passthrough ---
    {
        DacVoicing dv;
        const auto input = makeSignal(512, 2);
        auto work = input;
        dv.processInterleaved(work.data(), 512, 2);
        check(bitIdentical(work, input), "fresh disabled stage must be bit-exact");
        check(dv.getLatencyFrames() == 0, "disabled stage must report zero latency");
        check(!dv.isRamping(), "fresh stage must not be ramping");
    }

    // --- Latency and impulse alignment are identical across characters ---
    {
        const ImpulseResult r0 = impulseThroughStage(DacVoicing::Sharp);
        const ImpulseResult r1 = impulseThroughStage(DacVoicing::Slow);
        const ImpulseResult r2 = impulseThroughStage(DacVoicing::MinimumPhase);
        check(r0.latency > 0, "enabled stage reports latency");
        check(r1.latency == r0.latency && r2.latency == r0.latency,
              "character switching must not change reported latency");
        check(r0.peakFrame == r1.peakFrame && r0.peakFrame == r2.peakFrame,
              "impulse must land on the same frame for every character");
        check(r0.peakFrame == r0.latency, "impulse peak must sit at the reported delay");
        check(r0.peakValue > 0.5 && r2.peakValue > 0.5, "impulse must pass through the stage");
    }

    // --- DC passthrough with voicing on (squared term must not add DC) ---
    for (int c : {0, 1, 2}) {
        DacVoicing dv;
        dv.applyParams(voicingParams(true, c, 1.0));
        dv.setSampleRate(48000.0);
        dv.setEnabled(true);
        const int total = 8192;
        std::vector<float> buf(static_cast<size_t>(total) * 2, 0.5f);
        for (int off = 0; off < total; off += 256) {
            dv.processInterleaved(buf.data() + static_cast<size_t>(off) * 2, 256, 2);
        }
        bool ok = true;
        for (size_t i = static_cast<size_t>(total - 1024) * 2; i < buf.size(); ++i) {
            if (std::abs(buf[i] - 0.5f) > 1e-3f) ok = false;
        }
        check(ok, "DC input must pass through unchanged (all characters, voicing on)");
    }

    // --- Even-harmonic injection exactly tracks the amount knob ---
    {
        // Probe-validated: 1 kHz @ 0.5 through amount=1 gives 2k = 0.0436
        // (kVoicingDepth 0.35 * 0.5^2 / 2), 3k stays empty, voicing=0 is pure
        // linear filtering (2k/3k exactly zero).
        const double sr = 48000.0;
        const auto voiced = runToneThroughStage(DacVoicing::Sharp, 1.0, 1000.0, 8192, sr);
        const size_t measStart = 8192 - 3840; // integer cycles of 1k/2k/3k in 3840 frames
        const double m1k = toneMag(voiced, 2, measStart, 3840, 1000.0, sr);
        const double m2k = toneMag(voiced, 2, measStart, 3840, 2000.0, sr);
        const double m3k = toneMag(voiced, 2, measStart, 3840, 3000.0, sr);
        check(m1k > 0.45 && m1k < 0.55, "fundamental passes the reconstruction filter");
        const double ratio = m2k / m1k;
        check(ratio > 0.05 && ratio < 0.12, "amount=1 injects ~-21 dB 2nd harmonic");
        check(m3k < 0.01 * m1k, "square-law voicing adds no 3rd harmonic");
        double dc = 0.0;
        for (size_t f = measStart; f < 8192; ++f) dc += voiced[f * 2];
        dc /= static_cast<double>(3840);
        check(std::abs(dc) < 1e-3, "squared term is DC-blocked");

        const auto linear = runToneThroughStage(DacVoicing::Sharp, 0.0, 1000.0, 8192, sr);
        const double lm2k = toneMag(linear, 2, measStart, 3840, 2000.0, sr);
        const double lm3k = toneMag(linear, 2, measStart, 3840, 3000.0, sr);
        check(lm2k < 1e-6 && lm3k < 1e-6, "amount=0 is an exactly linear filter");
    }

    // --- Enable/disable ramp settles and re-enable flushes stale state ---
    {
        DacVoicing dv;
        dv.applyParams(voicingParams(true, DacVoicing::Sharp, 1.0));
        dv.setSampleRate(48000.0);
        dv.setEnabled(true);
        auto work = makeSignal(1024, 2);
        dv.processInterleaved(work.data(), 1024, 2);
        check(dv.isRamping(), "stage must report ramping right after enabling");
        check(dv.getLatencyFrames() > 0, "ramping stage still reports its delay");

        dv.setEnabled(false);
        check(dv.isRamping(), "disabling starts the ramp down, not an instant drop");
        std::vector<float> sink(static_cast<size_t>(128) * 2, 0.0f);
        for (int b = 0; b < 96; ++b) {
            std::fill(sink.begin(), sink.end(), 0.0f);
            dv.processInterleaved(sink.data(), 128, 2);
        }
        check(!dv.isRamping(), "ramp must settle within ~256 ms");
        check(dv.getLatencyFrames() == 0, "settled disabled stage reports zero latency");
        const auto input = makeSignal(256, 2);
        auto passthrough = input;
        dv.processInterleaved(passthrough.data(), 256, 2);
        check(bitIdentical(passthrough, input),
              "settled disabled stage must be bit-exact passthrough again");

        // Rising-edge reset: after re-enabling, silence in must produce exact
        // silence out (the dry-delay line was flushed, no stale blip).
        dv.setEnabled(true);
        std::vector<float> silence(static_cast<size_t>(256) * 2, 0.0f);
        dv.processInterleaved(silence.data(), 256, 2);
        bool allZero = true;
        for (float v : silence) {
            if (v != 0.0f) allZero = false;
        }
        check(allZero, "re-enable must flush rings (silence in -> exact silence out)");
    }

    // --- Engine integration ---
    {
        // The 0xFFFFFFFF pattern: every stage bit armed, every flag off. The
        // voicing stage is still called and must not touch a single sample.
        auto engine = std::make_unique<AudioDspEngine>();
        auto snap = std::make_shared<DspParamSnapshot>();
        snap->sampleRate = 48000.0;
        snap->activeStages = 0xFFFFFFFFu;
        // Several param sets default to enabled=true (see DspParams.h); clear
        // them explicitly, mirroring test_bypass_transparency.
        snap->eq.enabled = false;
        snap->crossfeed.enabled = false;
        snap->reverb.enabled = false;
        snap->limiter.enabled = false;
        snap->resampler.enabled = false;
        snap->saturation.enabled = false;
        snap->stereoWidth.enabled = false;
        snap->loudness.enabled = false;
        snap->subCrossover.enabled = false;
        snap->dynamicEq.enabled = false;
        snap->multibandCompressor.enabled = false;
        snap->dynamicBass.enabled = false;
        snap->viperDdc.enabled = false;
        snap->arbitraryEq.enabled = false;
        snap->liveProg.enabled = false;
        snap->directVolume.enabled = false;
        snap->replayGain.enabled = false;
        snap->headphoneSafety.enabled = false;
        snap->channelManager.enabled = false;
        snap->dacVoicing.enabled = false;
        engine->setSampleRate(snap->sampleRate);
        engine->publishParams(snap);
        const auto input = makeSignal(512, 2);
        auto work = input;
        check(engine->processInterleaved(work.data(), 512, 2) == 512,
              "engine must preserve frame count");
        check(bitIdentical(work, input),
              "0xFFFFFFFF with voicing flag off must stay bit-exact");
        check(engine->getPipelineLatencyFrames() == 0,
              "disabled voicing must not add pipeline latency");
    }

    {
        // Enabled through the engine: the block must change and the pipeline
        // must report the stage delay (>= the stage's own 15 frames).
        auto engine = std::make_unique<AudioDspEngine>();
        auto snap = std::make_shared<DspParamSnapshot>();
        snap->sampleRate = 48000.0;
        snap->activeStages = STAGE_DAC_VOICING;
        snap->dacVoicing.enabled = true;
        snap->dacVoicing.character = DacVoicing::Sharp;
        snap->dacVoicing.voicingAmount = 1.0;
        engine->setSampleRate(snap->sampleRate);
        engine->publishParams(snap);
        const auto input = makeSignal(512, 2);
        auto work = input;
        bool changed = false;
        for (int b = 0; b < 16; ++b) {
            work = input;
            if (engine->processInterleaved(work.data(), 512, 2) != 512) {
                check(false, "enabled voicing must preserve frame count");
                break;
            }
            if (!bitIdentical(work, input)) changed = true;
        }
        check(changed, "enabled voicing must alter the signal");
        check(engine->getPipelineLatencyFrames() >= engine->dacVoicing().getGroupDelayFrames(),
              "engine must report the voicing stage latency");
    }

    if (gFailures != 0) {
        std::cout << "[FAIL] " << gFailures << " DAC voicing check(s) failed." << std::endl;
        return 1;
    }
    std::cout << "[PASS] DAC voicing: character designs, aligned latency, voicing "
              << "harmonics, and bit-exact bypass all hold." << std::endl;
    return 0;
}
