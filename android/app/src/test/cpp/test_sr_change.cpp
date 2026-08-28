// android/app/src/test/cpp/test_sr_change.cpp
#include "../../main/cpp/AudioDspEngine.h"
#include <iostream>
#include <vector>
#include <cassert>
#include <cmath>

void runSampleRateChangeTest() {
    std::cout << "\n=== [TEST 10/11] Dynamic Sample Rate Transition Test (48k -> 96k -> 768k) ===" << std::endl;
    auto& engine = AudioDspEngine::instance();

    const double testRates[] = {44100.0, 48000.0, 88200.0, 96000.0, 192000.0, 384000.0, 768000.0, 48000.0};
    const int blockSize = 512;
    const int channels = 2;
    std::vector<float> audio(blockSize * channels);

    for (double sr : testRates) {
        auto snapshot = std::make_shared<DspParamSnapshot>();
        snapshot->generation = static_cast<uint64_t>(sr);
        snapshot->sampleRate = sr;
        snapshot->activeStages = STAGE_EQ | STAGE_REVERB | STAGE_LIMITER;
        snapshot->reverb.enabled = true;
        snapshot->reverb.preset = 3; // Hall
        snapshot->reverb.predelayMs = 80.0;
        snapshot->reverb.wetDry = 0.40;
        snapshot->reverb.damping = 0.5;
        snapshot->limiter.enabled = true;

        engine.publishParams(snapshot);

        for (int b = 0; b < 200; ++b) {
            for (int i = 0; i < blockSize * channels; ++i) {
                audio[i] = std::sin(static_cast<float>(i + b * blockSize) * 0.1f) * 0.8f;
            }

            int outFrames = engine.processInterleaved(audio.data(), blockSize, channels);
            assert(outFrames == blockSize);

            for (int i = 0; i < blockSize * channels; ++i) {
                float sample = audio[i];
                assert(!std::isnan(sample) && !std::isinf(sample));
                assert(std::abs(sample) <= 1.05f); // Limiter ceiling held
            }
        }
    }

    std::cout << "  ✓ All 8 sample rate transitions up to 768kHz remained stable, finite, and bounded." << std::endl;

    // A2 (B-05): Direct ConvolutionReverb::setSampleRate must regenerate preparedIr for non-custom presets
    {
        std::cout << "  Running A2 ConvolutionReverb setSampleRate non-custom regeneration test..." << std::endl;
        ConvolutionReverb reverb;
        reverb.setSampleRate(44100.0);
        reverb.setPreset(ReverbPreset::Hall);
        assert(reverb.getPreparedIr() != nullptr);
        assert(reverb.getPreparedIr()->createdSampleRate == 44100);

        reverb.setSampleRate(96000.0);
        assert(reverb.getPreparedIr() != nullptr);
        assert(reverb.getPreparedIr()->createdSampleRate == 96000);
        std::cout << "  ✓ A2 ConvolutionReverb::setSampleRate successfully regenerated IR at 96kHz." << std::endl;
    }
}
