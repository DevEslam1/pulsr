// android/app/src/test/cpp/test_lfe_crossover.cpp
#include "../../main/cpp/AudioDspEngine.h"
#include "../../main/cpp/LfeCrossover.h"

#include <cassert>
#include <cmath>
#include <cstring>
#include <iostream>
#include <limits>
#include <memory>
#include <vector>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

namespace {

double measureChannelRms(const std::vector<float>& interleaved,
                         int channels,
                         int targetCh,
                         int startFrame,
                         int endFrame) {
    double sumSq = 0.0;
    int count = 0;
    for (int f = startFrame; f < endFrame; ++f) {
        const double v = interleaved[static_cast<size_t>(f) * channels + targetCh];
        sumSq += v * v;
        ++count;
    }
    return count > 0 ? std::sqrt(sumSq / static_cast<double>(count)) : 0.0;
}

std::vector<float> makeInterleavedSine(int frames,
                                       int channels,
                                       int activeChannel,
                                       double freqHz,
                                       double sampleRate,
                                       float amplitude = 0.5f) {
    std::vector<float> buf(static_cast<size_t>(frames) * channels, 0.0f);
    for (int f = 0; f < frames; ++f) {
        const double phase = 2.0 * M_PI * freqHz * static_cast<double>(f) / sampleRate;
        buf[static_cast<size_t>(f) * channels + activeChannel] =
            amplitude * static_cast<float>(std::sin(phase));
    }
    return buf;
}

}  // namespace

int main() {
    std::cout << "[TEST] Running LfeCrossover multichannel bass management tests..." << std::endl;

    constexpr double kSr = 48000.0;
    constexpr int kFrames = 16384;
    constexpr int kSteadyStart = 8192;

    // 1. Stereo (< 3 ch) and out-of-range LFE channel must be bit-exact no-ops.
    {
        LfeCrossover lfe;
        lfe.setSampleRate(kSr);
        lfe.configure(80.0, 120.0, 24.0, 6.0, 3, true);
        lfe.setEnabled(true);
        lfe.reset();

        auto stereo = makeInterleavedSine(1024, 2, 0, 40.0, kSr);
        auto orig = stereo;
        lfe.processInterleaved(stereo.data(), 1024, 2);
        assert(std::memcmp(stereo.data(), orig.data(), stereo.size() * sizeof(float)) == 0 &&
               "LfeCrossover must be bit-exact passthrough for stereo (<3 ch)");

        auto quadInvalidLfe = makeInterleavedSine(1024, 3, 0, 40.0, kSr);
        auto origQuad = quadInvalidLfe;
        lfe.processInterleaved(quadInvalidLfe.data(), 1024, 3); // lfeChannelIndex=3 >= 3
        assert(std::memcmp(quadInvalidLfe.data(), origQuad.data(),
                           quadInvalidLfe.size() * sizeof(float)) == 0 &&
               "LfeCrossover must be no-op when lfeChannelIndex >= channels");
    }
    std::cout << "  ✓ Stereo & out-of-range LFE index bit-exact passthrough verified." << std::endl;

    // 2. 5.1 (6 ch, LFE = ch 3) LR4 24 dB/oct satellite HPF + redirected bass into LFE.
    {
        LfeCrossover lfe;
        lfe.setSampleRate(kSr);
        lfe.configure(80.0, 120.0, 24.0, 0.0, 3, true);
        lfe.setEnabled(true);
        lfe.reset();

        // Sub-bass tone (30 Hz) on FL (ch 0): must be heavily attenuated on FL and appear on LFE (ch 3).
        auto bufLow = makeInterleavedSine(kFrames, 6, 0, 30.0, kSr, 0.5f);
        const double inRms = measureChannelRms(bufLow, 6, 0, kSteadyStart, kFrames);
        lfe.processInterleaved(bufLow.data(), kFrames, 6);
        const double satLowRms = measureChannelRms(bufLow, 6, 0, kSteadyStart, kFrames);
        const double lfeLowRms = measureChannelRms(bufLow, 6, 3, kSteadyStart, kFrames);
        assert(satLowRms < inRms * 0.16 &&
               "LR4 80 Hz HPF must attenuate 30 Hz satellite energy by >16 dB");
        // Power-sum scaling 1/sqrt(5) ~ 0.447; allow filter rolloff margin.
        assert(lfeLowRms > inRms * 0.35 &&
               "30 Hz satellite bass must redirect into LFE channel");

        // Midrange tone (1 kHz) on FL (ch 0): must pass flat on FL and stay silent on LFE.
        lfe.reset();
        auto bufHigh = makeInterleavedSine(kFrames, 6, 0, 1000.0, kSr, 0.5f);
        const double inHighRms = measureChannelRms(bufHigh, 6, 0, kSteadyStart, kFrames);
        lfe.processInterleaved(bufHigh.data(), kFrames, 6);
        const double satHighRms = measureChannelRms(bufHigh, 6, 0, kSteadyStart, kFrames);
        const double lfeHighRms = measureChannelRms(bufHigh, 6, 3, kSteadyStart, kFrames);
        assert(std::abs(satHighRms - inHighRms) < 0.01 &&
               "1 kHz satellite signal must pass through HPF at unity");
        assert(lfeHighRms < 0.002 &&
               "1 kHz satellite signal must not leak into LFE");
    }
    std::cout << "  ✓ 5.1 LR4 satellite HPF and bass redirection verified." << std::endl;

    // 3. Dedicated LFE channel low-pass filtering & LFE gain trim (+6 dB).
    {
        LfeCrossover lfe;
        lfe.setSampleRate(kSr);
        lfe.configure(80.0, 120.0, 24.0, 6.0206, 3, false); // redirectBass=false, +6 dB LFE trim
        lfe.setEnabled(true);
        lfe.reset();

        // Low tone on LFE (40 Hz) -> passes LPF and gets +6 dB (~2x) gain; satellites untouched.
        auto bufLfeLow = makeInterleavedSine(kFrames, 6, 3, 40.0, kSr, 0.25f);
        for (int f = 0; f < kFrames; ++f) {
            bufLfeLow[static_cast<size_t>(f) * 6 + 0] = 0.25f;
        }
        const double lfeInRms = measureChannelRms(bufLfeLow, 6, 3, kSteadyStart, kFrames);
        lfe.processInterleaved(bufLfeLow.data(), kFrames, 6);
        const double lfeOutRms = measureChannelRms(bufLfeLow, 6, 3, kSteadyStart, kFrames);
        assert(std::abs(lfeOutRms / lfeInRms - 2.0) < 0.08 &&
               "40 Hz LFE must receive ~+6 dB gain when lfeGainDb=+6");
        assert(std::abs(bufLfeLow[static_cast<size_t>(kSteadyStart) * 6 + 0] - 0.25f) < 1e-6f &&
               "Satellites must remain untouched when redirectBass=false");

        // High tone on LFE (1 kHz) -> rejected by 120 Hz LFE LPF.
        lfe.reset();
        auto bufLfeHigh = makeInterleavedSine(kFrames, 6, 3, 1000.0, kSr, 0.5f);
        lfe.processInterleaved(bufLfeHigh.data(), kFrames, 6);
        const double lfeOutHighRms = measureChannelRms(bufLfeHigh, 6, 3, kSteadyStart, kFrames);
        assert(lfeOutHighRms < 0.005 &&
               "1 kHz on LFE channel must be rejected by 120 Hz LFE LPF");
    }
    std::cout << "  ✓ Dedicated LFE low-pass & gain trim verified." << std::endl;

    // 4. LR2 (12 dB/oct) slope and click-free disable ramp + NaN scrubbing.
    {
        LfeCrossover lfe;
        lfe.setSampleRate(kSr);
        lfe.configure(100.0, 120.0, 12.0, 0.0, 3, true);
        lfe.setEnabled(true);
        lfe.reset();

        auto buf = makeInterleavedSine(4096, 6, 0, 40.0, kSr, 0.5f);
        buf[600 * 6 + 0] = std::numeric_limits<float>::quiet_NaN();
        buf[600 * 6 + 3] = std::numeric_limits<float>::infinity();
        lfe.processInterleaved(buf.data(), 4096, 6);
        for (float v : buf) {
            assert(std::isfinite(v) && "LfeCrossover must scrub NaN/Inf samples");
        }

        // Disable and verify smooth ramp settles to bit-exact passthrough.
        lfe.setEnabled(false);
        assert(lfe.isRamping() && "Disabling LfeCrossover must ramp smoothly");
        std::vector<float> drain(8192 * 6, 0.0f);
        lfe.processInterleaved(drain.data(), 8192, 6);
        assert(!lfe.isRamping() && "LfeCrossover disable ramp must settle within 8192 frames at 48 kHz");

        auto dry = makeInterleavedSine(512, 6, 0, 40.0, kSr, 0.5f);
        auto dryCopy = dry;
        lfe.processInterleaved(dry.data(), 512, 6);
        assert(std::memcmp(dry.data(), dryCopy.data(), dry.size() * sizeof(float)) == 0 &&
               "Settled disabled LfeCrossover must be bit-exact passthrough");
    }
    std::cout << "  ✓ LR2, NaN scrubbing, and click-free disable ramp verified." << std::endl;

    // 5. AudioDspEngine integration & SanitizeSnapshot contract.
    {
        auto engine = std::make_unique<AudioDspEngine>();
        engine->setSampleRate(kSr);
        engine->setActiveStages(STAGE_LFE_CROSSOVER);
        engine->updateParams([](DspParamSnapshot& snap) {
            snap.lfeCrossover.enabled = true;
            snap.lfeCrossover.crossoverHz = 10.0;   // below min 40 -> clamps to 40
            snap.lfeCrossover.lfeLowPassHz = 500.0; // above max 250 -> clamps to 250
            snap.lfeCrossover.slopeDbPerOct = 12.0;
            snap.lfeCrossover.lfeGainDb = std::numeric_limits<double>::quiet_NaN(); // fallback 0
            snap.lfeCrossover.lfeChannelIndex = 2;  // 2.1 layout LFE = ch 2
            snap.lfeCrossover.redirectBass = true;
        });

        auto snap = engine->getParams();
        assert(snap->lfeCrossover.crossoverHz == 40.0);
        assert(snap->lfeCrossover.lfeLowPassHz == 250.0);
        assert(snap->lfeCrossover.slopeDbPerOct == 12.0);
        assert(snap->lfeCrossover.lfeGainDb == 0.0);
        assert(snap->lfeCrossover.lfeChannelIndex == 2);

        // Process a 3-channel (2.1) 30 Hz sine on ch 0 -> ch 2 receives redirected bass.
        auto stream21 = makeInterleavedSine(kFrames, 3, 0, 30.0, kSr, 0.4f);
        engine->processInterleaved(stream21.data(), kFrames, 3);
        const double lfe21Rms = measureChannelRms(stream21, 3, 2, kSteadyStart, kFrames);
        assert(lfe21Rms > 0.08 && "AudioDspEngine must run LfeCrossover on 3-channel audio");
    }
    std::cout << "  ✓ AudioDspEngine integration & sanitization verified." << std::endl;
    std::cout << "[PASS] LfeCrossover tests passed." << std::endl;
    return 0;
}
