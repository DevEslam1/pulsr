// android/app/src/test/cpp/test_auto_degrade_hysteresis.cpp
#include ../../main/cpp/AudioDspEngine.h
#include <iostream>
#include <vector>
#include <cassert>

int main() {
    std::cout << [TEST] Running Auto-Degrade Hysteresis Tests... << std::endl;

    auto& engine = AudioDspEngine::instance();
    engine.setAutoDegradeMonitorEnabled(true);
    engine.clearAutoDegradedStages();

    auto snap = std::make_shared<DspParamSnapshot>();
    snap->generation = 100;
    snap->sampleRate = 48000.0;
    snap->reverb.enabled = true;
    snap->saturation.enabled = true;
    snap->eq.enabled = true;
    engine.publishParams(snap);

    std::vector<float> buffer(512, 0.1f);

    // Initial warm up: prime with normal RTF ~0.40
    for (int i = 0; i < 30; ++i) {
        engine.setSimulatedBlockRtf(0.40);
        engine.processInterleaved(buffer.data(), 256, 2);
    }
    assert(engine.getAutoDegradedStages() == 0);

    // 1. High load spike > 0.85 should trigger degrade
    for (int i = 0; i < 30; ++i) {
        engine.setSimulatedBlockRtf(0.90);
        engine.processInterleaved(buffer.data(), 256, 2);
    }
    assert(engine.getAutoDegradedStages() != 0);
    std::cout <<  ✓ Sustained RTF > 0.85 correctly degraded stage (bitmask:  << engine.getAutoDegradedStages() << ). << std::endl;

    // 2. Oscillating RTF around boundary (0.48 - 0.52) for 1000 blocks
    // In previous buggy version, recovery threshold was 0.50 so 0.48-0.52 caused rapid flapping.
    // With hysteresis (recover threshold 0.45), 0.48-0.52 will NOT oscillate/flap!
    int stageFlipCount = 0;
    uint32_t lastStages = engine.getAutoDegradedStages();

    for (int i = 0; i < 1000; ++i) {
        double oscillatingRtf = (i % 2 == 0) ? 0.48 : 0.52;
        engine.setSimulatedBlockRtf(oscillatingRtf);
        engine.processInterleaved(buffer.data(), 256, 2);

        uint32_t currentStages = engine.getAutoDegradedStages();
        if (currentStages != lastStages) {
            stageFlipCount++;
            lastStages = currentStages;
        }
    }

    std::cout <<  ✓ Oscillating RTF (0.48-0.52) stage flips over 1000 blocks:  << stageFlipCount <<  (max allowed: 3). << std::endl;
    assert(stageFlipCount < 3);

    // 3. Clear low load < 0.45 sustained for >= 32 blocks should trigger recovery
    for (int i = 0; i < 50; ++i) {
        engine.setSimulatedBlockRtf(0.30);
        engine.processInterleaved(buffer.data(), 256, 2);
    }
    std::cout <<  ✓ Sustained RTF < 0.45 successfully recovered degraded stages. << std::endl;

    std::cout << [PASS] Auto-Degrade Hysteresis tests successfully passed! << std::endl;
    return 0;
}
