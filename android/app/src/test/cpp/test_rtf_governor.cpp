#include "AudioDspEngine.h"
#include <algorithm>
#include <iostream>
#include <memory>
#include <vector>

namespace {
void process(AudioDspEngine& engine, double rtf, int blocks) {
    std::vector<float> audio(1024 * 2, 0.02f);
    engine.setSimulatedBlockRtf(rtf);
    for (int i = 0; i < blocks; ++i) {
        std::fill(audio.begin(), audio.end(), 0.02f);
        engine.processInterleaved(audio.data(), 1024, 2);
    }
}

void enableQuranAmbience(AudioDspEngine& engine) {
    engine.setSampleRate(48000);
    engine.updateParams([](DspParamSnapshot& params) {
        params.activeStages = STAGE_REVERB;
        params.reverb.enabled = true;
        params.reverb.wetDry = 0.3;
    });
    engine.setAutoDegradeMonitorEnabled(true);
}
}

int main() {
    int failures = 0;
    auto check = [&](bool condition, const char* message) {
        if (!condition) {
            std::cerr << "FAIL: " << message << '\n';
            ++failures;
        }
    };
    {
        auto engine = std::make_unique<AudioDspEngine>();
        enableQuranAmbience(*engine);
        process(*engine, 0.1, 19);
        // One delayed callback during a screen/power transition must not make
        // the following healthy audio run dry until the recovery window ends.
        process(*engine, 30.0, 1);
        check(engine->getAutoDegradedStages() == 0,
              "one scheduling spike bypassed Quran ambience");
        process(*engine, 0.1, 20);
        check(engine->getAutoDegradedStages() == 0,
              "a historical spike bypassed ambience during healthy callbacks");
    }
    {
        auto engine = std::make_unique<AudioDspEngine>();
        enableQuranAmbience(*engine);
        process(*engine, 0.1, 20);
        process(*engine, 8.0, 3);
        check(engine->getAutoDegradedStages() == 0,
              "a short transition burst bypassed Quran ambience");
    }
    {
        auto engine = std::make_unique<AudioDspEngine>();
        enableQuranAmbience(*engine);
        for (int i = 0; i < 10; ++i) {
            process(*engine, 2.0, 1);
            process(*engine, 0.1, 1);
        }
        check((engine->getAutoDegradedStages() & STAGE_REVERB) != 0,
              "repeated nonconsecutive overload no longer activates protection");
    }
    {
        auto engine = std::make_unique<AudioDspEngine>();
        enableQuranAmbience(*engine);
        process(*engine, 1.2, 40);
        check((engine->getAutoDegradedStages() & STAGE_REVERB) != 0,
              "sustained overload no longer activates protection");
        process(*engine, 0.1, 100);
        check(engine->getAutoDegradedStages() == 0,
              "ambience did not recover after sustained healthy load");
    }
    if (failures) return 1;
    std::cout << "RTF governor transient, sustained-load and recovery checks passed\n";
    return 0;
}
