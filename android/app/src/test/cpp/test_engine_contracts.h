#pragma once
#include <cassert>
#include <algorithm>
#include <memory>
#include <vector>

void runEngineCommandContractsTest() {
    auto engine = std::make_unique<AudioDspEngine>();
    auto params = std::make_shared<DspParamSnapshot>();
    params->eq.enabled = false;
    params->crossfeed.enabled = false;
    params->limiter.enabled = false;
    params->activeStages = 0;
    std::vector<float> pcm(1024, 0.25f);
    engine->publishParams(params);
    engine->processInterleaved(pcm.data(), 512, 2);

    engine->resyncForTrack(96000, 2);
    engine->publishParams(params); // control broadcast before first track block
    engine->processInterleaved(pcm.data(), 512, 2);
    assert(engine->getSampleRate() == 96000);

    params->directVolume.enabled = true;
    params->directVolume.gainLinear = 0.5;
    engine->publishParams(params);
    for (int k = 0; k < 100; ++k) {
        std::fill(pcm.begin(), pcm.end(), 0.25f);
        engine->processInterleaved(pcm.data(), 512, 2);
    }
    assert(std::abs(pcm[0] - 0.125f) < 0.001f);
    engine->reset();
    engine->updateParams([](DspParamSnapshot& p) { p.panner.balance = 0.0; });
    engine->resyncForTrack(96000, 2);
    engine->publishParams(params);
    std::fill(pcm.begin(), pcm.end(), 0.25f);
    engine->processInterleaved(pcm.data(), 512, 2);
    assert(std::abs(pcm[0] - 0.25f) < 0.001f); // reset survived all publications
    const float resetBlockEnd = pcm.back();
    engine->updateParams([](DspParamSnapshot& p) { p.panner.balance = 0.0; });
    std::fill(pcm.begin(), pcm.end(), 0.25f);
    engine->processInterleaved(pcm.data(), 512, 2);
    assert(std::abs(pcm[0] - resetBlockEnd) < 0.001f); // no repeated reset

    params->directVolume.gainLinear = 4.0;
    params->limiter.thresholdDb = -1.0;
    engine->publishParams(params); // limiter toggle AND stage mask remain OFF
    for (int k = 0; k < 100; ++k) {
        std::fill(pcm.begin(), pcm.end(), 0.5f);
        engine->processInterleaved(pcm.data(), 512, 2);
    }
    assert(*std::max_element(pcm.begin(), pcm.end()) < 0.90f);
    assert(pcm[200] > 0.5f);
    assert(engine->getPipelineLatencyFrames() > 0);
    assert(engine->isLimiterActive());

    params->bitPerfect.enabled = true;
    engine->publishParams(params);
    std::fill(pcm.begin(), pcm.end(), 0.25f);
    engine->processInterleaved(pcm.data(), 512, 2);
    assert(pcm[0] == 0.25f && engine->getPipelineLatencyFrames() == 0);
    assert(!engine->isLimiterActive());
    params->bitPerfect.enabled = false;
    params->directVolume.enabled = false;
    params->headphoneSafety.enabled = true;
    engine->publishParams(params);
    // Reset smoothed DVC so only the safety limiter contributes delay.
    engine->reset();
    engine->processInterleaved(pcm.data(), 512, 2);
    assert(engine->getPipelineLatencyFrames() == 480); // 5ms at 96kHz
    params->headphoneSafety.enabled = false;
    params->resampler.enabled = true;
    params->resampler.inRate = 44100;
    params->resampler.outRate = 48000;
    engine->publishParams(params);
    engine->processInterleaved(pcm.data(), 512, 2);
    assert(engine->getPipelineLatencyFrames() == 0); // in-place fallback adds no delay

    params->resampler.enabled = false;
    params->crossfeed.enabled = true;
    params->activeStages = STAGE_CROSSFEED;
    engine->publishParams(params);
    for (int k = 0; k < 100; ++k) {
        for (int f = 0; f < 512; ++f) { pcm[f*2] = 0.25f; pcm[f*2+1] = 0; }
        engine->processInterleaved(pcm.data(), 512, 2);
    }
    params->crossfeed.enabled = false;
    params->activeStages = 0;
    engine->publishParams(params);
    for (int f = 0; f < 512; ++f) { pcm[f*2] = 0.25f; pcm[f*2+1] = 0; }
    engine->processInterleaved(pcm.data(), 512, 2);
    assert(pcm[1] > 0.001f); // fade-out executes despite dropped stage bit
    for (int k = 0; k < 100; ++k) engine->processInterleaved(pcm.data(), 512, 2);
    assert(!engine->crossfeed().isRamping());
    std::cout << "  PASS: pending rate/reset commands, automatic limiting, actual latency, and fade-out contracts\n";
}
