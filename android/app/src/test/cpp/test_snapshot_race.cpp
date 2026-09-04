// android/app/src/test/cpp/test_snapshot_race.cpp
#include "../../main/cpp/AudioDspEngine.h"
#include <iostream>
#include <vector>
#include <cassert>
#include <thread>
#include <atomic>
#include <random>

void runSnapshotRaceTest() {
    std::cout << "\n=== [TEST 11/11] High-Concurrency Snapshot Race Test (4 Writers vs 1 Audio Reader) ===" << std::endl;
    auto& engine = AudioDspEngine::instance();
    engine.setSampleRate(48000.0);
    engine.setActiveStages(0xFFFFFFFF);

    std::atomic<bool> isRunning{true};
    std::atomic<uint64_t> totalMutations{0};
    const int numWriters = 4;
    std::vector<std::thread> writers;

    for (int t = 0; t < numWriters; ++t) {
        writers.emplace_back([&, t]() {
            std::mt19937 rng(100 + t);
            std::uniform_real_distribution<double> dist(-10.0, 10.0);

            while (isRunning.load(std::memory_order_relaxed)) {
                auto current = engine.getParams();
                auto updated = std::make_shared<DspParamSnapshot>(*current);
                updated->generation = totalMutations.fetch_add(1, std::memory_order_relaxed) + 1;
                updated->eq.preampDb = dist(rng) * 0.1;
                updated->panner.balance = dist(rng) * 0.05;
                updated->reverb.wetDry = std::abs(dist(rng) * 0.05);

                engine.publishParams(updated);
                std::this_thread::yield();
            }
        });
    }

    const int blockSize = 256;
    const int channels = 2;
    std::vector<float> audio(blockSize * channels, 0.05f);

    const int readerIterations = 20000;
    for (int i = 0; i < readerIterations; ++i) {
        int out = engine.processInterleaved(audio.data(), blockSize, channels);
        assert(out == blockSize);
        for (float s : audio) {
            assert(!std::isnan(s) && !std::isinf(s));
        }
    }

    isRunning.store(false);
    for (auto& w : writers) {
        if (w.joinable()) w.join();
    }

    std::cout << "  ✓ Concurrent race test completed cleanly with " << totalMutations.load() << " snapshot mutations." << std::endl;

    // 2. Interleaved setSampleRate + setActiveStages race test (R3)
    {
        std::cout << "  Running 2-writer setSampleRate + setActiveStages interleaved race test..." << std::endl;
        const int iterations = 1000;
        const double testRates[] = {44100.0, 48000.0, 88200.0, 96000.0, 192000.0};
        const uint32_t testStages[] = {STAGE_EQ | STAGE_LIMITER, STAGE_CROSSFEED | STAGE_REVERB, 0xFFFFFFFF, STAGE_PANNER};

        std::thread writerSR([&]() {
            for (int i = 0; i < iterations; ++i) {
                engine.setSampleRate(testRates[i % 5]);
                std::this_thread::yield();
            }
        });

        std::thread writerStages([&]() {
            for (int i = 0; i < iterations; ++i) {
                engine.setActiveStages(testStages[i % 4]);
                std::this_thread::yield();
            }
        });

        writerSR.join();
        writerStages.join();

        auto finalParams = engine.getParams();
        assert(finalParams != nullptr);
        assert(finalParams->sampleRate == testRates[(iterations - 1) % 5]);
        assert(finalParams->activeStages == testStages[(iterations - 1) % 4]);
        std::cout << "  ✓ Interleaved 2-writer test completed with zero lost updates." << std::endl;
    }
}
