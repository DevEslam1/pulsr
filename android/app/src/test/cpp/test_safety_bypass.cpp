// android/app/src/test/cpp/test_safety_bypass.cpp
//
// Safety stages must survive the two "no DSP" modes. Bit-Perfect output has to
// stay sample-identical while still metering the weekly dose; the level-matched
// A/B bypass must keep the dose meter and safety limiter in the path.
#include "../../main/cpp/AudioDspEngine.h"

#include <algorithm>
#include <cmath>
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

std::vector<float> makeSignal(int frames, int channels, float amplitude) {
    std::vector<float> buf(static_cast<size_t>(frames) * channels);
    for (int i = 0; i < frames; ++i) {
        for (int ch = 0; ch < channels; ++ch) {
            const double phase = (i + ch * 31) * 0.017;
            buf[static_cast<size_t>(i) * channels + ch] =
                amplitude * static_cast<float>(std::sin(phase));
        }
    }
    return buf;
}

bool bitIdentical(const std::vector<float>& a, const std::vector<float>& b) {
    return a.size() == b.size() &&
           std::memcmp(a.data(), b.data(), a.size() * sizeof(float)) == 0;
}

float peak(const std::vector<float>& buf) {
    float p = 0.0f;
    for (float s : buf) p = std::max(p, std::fabs(s));
    return p;
}

std::unique_ptr<AudioDspEngine> makeEngine(double sampleRate) {
    auto engine = std::make_unique<AudioDspEngine>();
    engine->setSampleRate(sampleRate);
    return engine;
}

std::shared_ptr<DspParamSnapshot> baseSnapshot(double sampleRate) {
    auto snap = std::make_shared<DspParamSnapshot>();
    snap->sampleRate = sampleRate;
    snap->activeStages = 0;
    return snap;
}

}  // namespace

int main() {
    std::cout << "[TEST] Bit-perfect / bypass-compare safety invariants..." << std::endl;
    const int frames = 256;
    const int channels = 2;
    const double sr = 48000.0;

    {
        auto engine = makeEngine(sr);
        auto snap = baseSnapshot(sr);
        snap->bitPerfect.enabled = true;
        snap->headphoneSafety.enabled = true;
        snap->headphoneSafety.doseThreshold = 100.0;  // never attenuate
        engine->publishParams(snap);

        const auto input = makeSignal(frames, channels, 0.25f);
        auto work = input;
        check(engine->processInterleaved(work.data(), frames, channels) == frames,
              "bit-perfect must preserve frame count");
        check(bitIdentical(work, input),
              "bit-perfect output must stay sample-identical with safety enabled");
        check(engine->getWeeklyDose() > 0.0,
              "bit-perfect must still meter the weekly dose (read-only)");
        check(!engine->isSafetyAttenuationActive(),
              "bit-perfect metering must not engage attenuation");
    }

    {
        auto engine = makeEngine(sr);
        auto snap = baseSnapshot(sr);
        snap->bypassCompare.enabled = true;
        snap->bypassCompare.gainCompensationLinear = 2.0;
        snap->headphoneSafety.enabled = true;
        // Any non-silent block crosses this, so the attenuation path runs.
        snap->headphoneSafety.doseThreshold = 1e-12;
        engine->publishParams(snap);

        const auto input = makeSignal(frames, channels, 0.05f);
        std::vector<float> work = input;
        for (int b = 0; b < 40; ++b) {
            work = input;
            engine->processInterleaved(work.data(), frames, channels);
        }
        check(engine->getWeeklyDose() > 0.0,
              "bypass-compare must meter the weekly dose");
        check(engine->isSafetyAttenuationActive(),
              "bypass-compare must engage safety attenuation at the threshold");
        // Gain compensation alone would leave ~0.10 peak; the -6 dB safety
        // attenuation must pull it down toward ~0.05.
        check(peak(work) < peak(input) * 2.0f * 0.75f,
              "bypass-compare must apply safety attenuation after gain compensation");
    }

    {
        auto engine = makeEngine(sr);
        auto snap = baseSnapshot(sr);
        snap->bypassCompare.enabled = true;
        snap->bypassCompare.gainCompensationLinear = 0.5;
        snap->headphoneSafety.enabled = false;
        engine->publishParams(snap);

        const auto input = makeSignal(frames, channels, 0.2f);
        auto work = input;
        engine->processInterleaved(work.data(), frames, channels);
        bool scaled = true;
        for (size_t i = 0; i < input.size(); ++i) {
            const float expected = input[i] * 0.5f;
            if (work[i] != expected) {
                scaled = false;
                break;
            }
        }
        check(scaled, "bypass-compare without safety must be pure gain compensation");
        check(engine->getWeeklyDose() == 0.0,
              "disabled headphone safety must not accumulate dose");
    }

    if (gFailures != 0) {
        std::cout << "[FAIL] " << gFailures << " safety bypass check(s) failed." << std::endl;
        return 1;
    }
    std::cout << "[PASS] Safety invariants hold in bit-perfect and A/B bypass." << std::endl;
    return 0;
}
