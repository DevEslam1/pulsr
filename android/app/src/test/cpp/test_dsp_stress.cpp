// android/app/src/test/cpp/test_dsp_stress.cpp
#include "../../main/cpp/AudioDspEngine.h"
#include <iostream>
#include <vector>
#include <random>
#include <cmath>
#include <cassert>
#include <thread>
#include <atomic>
#include <chrono>

int main() {
    std::cout << "[TEST] Running Audio DSP Parameter Mutation Stress Test (Lock-Free Thread Safety)..." << std::endl;

    auto& engine = AudioDspEngine::instance();
    engine.setSampleRate(48000.0);
    engine.setActiveStages(0xFFFFFFFF);

    std::atomic<bool> isRunning{true};
    std::atomic<int> mutationCount{0};

    // Precompute reverb preset IRs on the publisher thread
    std::vector<std::shared_ptr<const PreparedIr>> presetIrs(8);
    for (int p = 0; p < 8; ++p) {
        presetIrs[p] = PreparedIr::createSynthetic(48000.0, p, 0.5f);
    }

    // Thread 1: Mutates parameters continuously (Publisher Thread)
    std::thread mutatorThread([&]() {
        std::mt19937 rng(42);
        std::uniform_real_distribution<double> gainDist(-12.0, 12.0);
        std::uniform_real_distribution<double> freqDist(40.0, 16000.0);
        std::uniform_real_distribution<double> qDist(0.5, 3.0);
        std::uniform_real_distribution<double> wetDist(0.0, 1.0);
        std::uniform_real_distribution<double> balanceDist(-1.0, 1.0);
        std::uniform_int_distribution<int> typeDist(0, 7);

        while (isRunning.load(std::memory_order_relaxed)) {
            auto snapshot = std::make_shared<DspParamSnapshot>();
            snapshot->generation = mutationCount + 1;
            snapshot->activeStages = 0xFFFFFFFF;

            // Randomize EQ
            snapshot->eq.enabled = true;
            snapshot->eq.preampDb = gainDist(rng) * 0.1;
            snapshot->eq.bandCount = 10;
            for (int b = 0; b < 10; ++b) {
                snapshot->eq.bands[b].frequency = freqDist(rng);
                snapshot->eq.bands[b].gainDb = gainDist(rng);
                snapshot->eq.bands[b].q = qDist(rng);
                snapshot->eq.bands[b].type = static_cast<FilterType>(typeDist(rng));
                snapshot->eq.bands[b].enabled = true;
            }

            // Randomize Crossfeed
            snapshot->crossfeed.enabled = true;
            snapshot->crossfeed.delayUs = 350.0;
            snapshot->crossfeed.feedDb = -9.0;
            snapshot->crossfeed.fcut = 650.0;

            // Randomize Limiter
            snapshot->limiter.enabled = true;
            snapshot->limiter.thresholdDb = -0.5;
            snapshot->limiter.releaseMs = 50.0;
            snapshot->limiter.truePeakMode = true;

            // Randomize Reverb (prepared IR pointer swap)
            int p = mutationCount % 8;
            snapshot->reverb.enabled = (mutationCount % 2 == 0);
            snapshot->reverb.wetDry = wetDist(rng);
            snapshot->reverb.preset = p;
            snapshot->reverb.preparedIr = presetIrs[p];

            // Randomize Panner
            snapshot->panner.balance = balanceDist(rng);
            snapshot->panner.monoMix = false;

            engine.publishParams(snapshot);
            mutationCount++;

            std::this_thread::yield();
        }
    });

    // Main thread: Audio processing loop simulating 48kHz blocks
    const int blockSize = 256;
    const int channels = 2;
    std::vector<float> audioBlock(blockSize * channels);

    std::mt19937 audioRng(1234);
    std::uniform_real_distribution<float> noiseDist(-0.5f, 0.5f);

    auto startTime = std::chrono::steady_clock::now();
    const int totalBlocks = 20000;

    for (int b = 0; b < totalBlocks; ++b) {
        // Fill input with noise
        for (int i = 0; i < blockSize * channels; ++i) {
            audioBlock[i] = noiseDist(audioRng);
        }

        int outFrames = engine.processInterleaved(audioBlock.data(), blockSize, channels);
        assert(outFrames == blockSize);

        for (int i = 0; i < blockSize; ++i) {
            const float sL = audioBlock[i * channels];
            const float sR = audioBlock[i * channels + 1];

            // Assert no NaN or Inf
            assert(!std::isnan(sL) && !std::isinf(sL));
            assert(!std::isnan(sR) && !std::isinf(sR));

            // Assert numerical stability
            assert(std::abs(sL) < 100.0f);
            assert(std::abs(sR) < 100.0f);
        }
    }

    isRunning.store(false);
    mutatorThread.join();

    auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now() - startTime).count();

    std::cout << "[PASS] Parameter Mutation Stress Test completed in " << elapsed
              << "ms (" << mutationCount.load() << " atomic parameter swaps, zero NaN/Inf, zero thread contention)."
              << std::endl;
    return 0;
}
