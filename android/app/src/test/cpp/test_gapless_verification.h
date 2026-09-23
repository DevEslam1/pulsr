// android/app/src/test/cpp/test_gapless_verification.h
#pragma once

#include "../../main/cpp/AudioDspEngine.h"
#include "../../main/cpp/ConvolutionReverb.h"
#include <iostream>
#include <vector>
#include <cmath>
#include <cassert>
#include <memory>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

// 1. Reverb Tail Preservation across Track Transitions (Gapless playback)
inline void runGaplessReverbTailPreservationTest() {
    std::cout << "\n=== [GAPLESS 1/3] Track Transition Reverb Tail Preservation Test ===" << std::endl;
    auto engine = std::make_unique<AudioDspEngine>();
    engine->setSampleRate(48000.0);
    engine->setActiveStages(0xFFFFFFFF);

    auto snap = std::make_shared<DspParamSnapshot>();
    snap->sampleRate = 48000.0;
    snap->activeStages = 0xFFFFFFFF;
    snap->reverb.enabled = true;
    snap->reverb.preset = static_cast<int>(ReverbPreset::Hall);
    snap->reverb.wetDry = 0.50;
    snap->reverb.damping = 0.5;
    snap->reverb.preparedIr = PreparedIr::createSynthetic(48000.0, static_cast<int>(ReverbPreset::Hall), 0.5f);
    engine->publishParams(snap);

    const int blockSize = 512;
    std::vector<float> impulse(blockSize * 2, 0.0f);
    // Excite reverb with burst across multiple blocks on Track 1
    for (int b = 0; b < 3; ++b) {
        for (int i = 0; i < blockSize; ++i) {
            float s = 0.8f * std::sin(2.0f * static_cast<float>(M_PI) * 440.0f * (i + b * blockSize) / 48000.0f);
            impulse[i * 2] = s;
            impulse[i * 2 + 1] = s;
        }
        engine->processInterleaved(impulse.data(), blockSize, 2);
    }

    // Track boundary transition: resyncForTrack for Track 2
    engine->resyncForTrack(48000.0, 2);

    // Feed pure silence on Track 2; the reverb tail from Track 1 MUST continue ringing
    std::vector<float> silence(blockSize * 2, 0.0f);
    engine->processInterleaved(silence.data(), blockSize, 2);

    float tailEnergy = 0.0f;
    for (int i = 0; i < blockSize * 2; ++i) {
        assert(std::isfinite(silence[i]));
        tailEnergy += silence[i] * silence[i];
    }

    assert(tailEnergy > 1e-5f); // Tail is preserved, not hard-muted
    std::cout << "  ✓ Track transition preserved reverb tail into silence (energy: "
              << tailEnergy << " > 1e-5)." << std::endl;
}

// 2. Registry Engine Preservation across Multi-Player Gapless Transitions
inline void runGaplessRegistryPreservationTest() {
    std::cout << "\n=== [GAPLESS 2/3] DspEngineRegistry Multi-Player Parameter Preservation Test ===" << std::endl;
    auto& controlEngine = AudioDspEngine::instance();

    controlEngine.updateParams([](DspParamSnapshot& s) {
        s.eq.preampDb = -3.5;
        s.crossfeed.enabled = true;
        s.limiter.enabled = true;
        s.headphoneSafety.enabled = true;
    });

    const uint64_t baseGen = controlEngine.getPublishedGeneration();

    // Create player engine 1 (representing outgoing track)
    auto engine1 = std::make_unique<AudioDspEngine>();
    engine1->setSampleRate(44100.0);
    DspEngineRegistry::instance().registerEngine(engine1.get());

    auto snap1 = engine1->getParams();
    assert(snap1 != nullptr);
    assert(snap1->eq.preampDb == -3.5);
    assert(snap1->crossfeed.enabled == true);
    assert(snap1->headphoneSafety.enabled == true);
    assert(snap1->generation >= baseGen);

    // Gapless pre-roll: create player engine 2 (representing incoming track)
    auto engine2 = std::make_unique<AudioDspEngine>();
    engine2->setSampleRate(96000.0);
    DspEngineRegistry::instance().registerEngine(engine2.get());

    auto snap2 = engine2->getParams();
    assert(snap2 != nullptr);
    assert(snap2->eq.preampDb == -3.5);
    assert(snap2->crossfeed.enabled == true);
    assert(snap2->headphoneSafety.enabled == true);
    assert(snap2->generation >= snap1->generation); // No generation rollback

    // Outgoing player completes and is unregistered
    DspEngineRegistry::instance().unregisterEngine(engine1.get());

    // Live update while incoming player 2 is running
    controlEngine.updateParams([](DspParamSnapshot& s) {
        s.eq.preampDb = -5.0;
    });

    auto snap2Updated = engine2->getParams();
    assert(snap2Updated->eq.preampDb == -5.0);

    DspEngineRegistry::instance().unregisterEngine(engine2.get());
    std::cout << "  ✓ Parameter snapshot broadcast accurately preserved across engine1 -> engine2 transition with zero rollback."
              << std::endl;
}

// 3. Flush Monotonic Rebase Invariant Test
inline void runGaplessFlushMonotonicRebaseTest() {
    std::cout << "\n=== [GAPLESS 3/3] Flush Position Rebase Monotonic Invariant Test ===" << std::endl;
    // Verify position rebase math:
    // FramesWritten = written > writtenBase ? written - writtenBase : 0
    int64_t framesWritten = 10000;
    int64_t framesWrittenBase = 0;

    auto calcWritten = [&]() -> int64_t {
        return framesWritten > framesWrittenBase ? framesWritten - framesWrittenBase : 0;
    };

    assert(calcWritten() == 10000);

    // Simulate Flush(): rebase to current written position
    framesWrittenBase = framesWritten;
    assert(calcWritten() == 0);

    // Subsequent writes monotonically increase from 0
    int64_t prev = calcWritten();
    for (int i = 1; i <= 5; ++i) {
        framesWritten += 512;
        int64_t cur = calcWritten();
        assert(cur > prev);
        assert(cur == i * 512);
        prev = cur;
    }

    std::cout << "  ✓ Flush rebase reset base to current position; subsequent counter values advanced strictly monotonically."
              << std::endl;
}
