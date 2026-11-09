// android/app/src/test/cpp/test_engine_registry.cpp
//
// Engine handle lifetime: slot admission must make stale/double destroy a
// no-op and teardown must wait only for renders on the slot being destroyed.
#include "../../main/cpp/AudioDspEngine.h"

#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <future>
#include <thread>
#include <vector>

namespace {
int gFailures = 0;
void check(bool ok, const char* what) {
    if (!ok) {
        std::cout << "[FAIL] " << what << std::endl;
        ++gFailures;
    }
}

int64_t handleOf(AudioDspEngine* engine) {
    return static_cast<int64_t>(reinterpret_cast<intptr_t>(engine));
}
}  // namespace

int main() {
    std::cout << "[TEST] DspEngineRegistry handle lifetime..." << std::endl;
    auto& registry = DspEngineRegistry::instance();

    {
        auto engine = std::make_unique<AudioDspEngine>();
        const int64_t handle = handleOf(engine.get());
        check(registry.registerEngine(engine.get()), "register engine");

        auto lease = registry.acquireForRender(handle);
        check(lease.engine == engine.get() && lease.slot >= 0,
              "acquire returns the live engine and slot");
        registry.releaseForRender(lease.slot);

        const int slot = registry.beginTeardown(handle);
        check(slot >= 0, "first teardown wins the slot");
        check(registry.beginTeardown(handle) < 0,
              "double teardown is refused");
        check(registry.acquireForRender(handle).engine == nullptr,
              "acquire during teardown returns no engine");

        registry.waitForRenderers(slot);
        registry.unregisterEngine(engine.get());
        registry.finishTeardown(slot);

        check(registry.acquireForRender(handle).engine == nullptr,
              "acquire after teardown returns no engine");
        check(registry.beginTeardown(handle) < 0,
              "stale/double destroy is a safe no-op");
    }

    {
        // Concurrent render vs teardown: teardown must wait for the in-flight
        // block, and no new renderer may enter once tearingDown is published.
        auto engine = std::make_unique<AudioDspEngine>();
        const int64_t handle = handleOf(engine.get());
        check(registry.registerEngine(engine.get()), "register concurrent engine");

        std::atomic<bool> stop{false};
        std::atomic<bool> inRender{false};
        std::atomic<int> renders{0};
        std::promise<bool> acquired;
        auto acquiredFuture = acquired.get_future();
        std::promise<void> teardownPublished;
        auto teardownFuture = teardownPublished.get_future();
        std::thread worker([&]() {
            while (!stop.load(std::memory_order_acquire)) {
                auto lease = registry.acquireForRender(handle);
                if (!lease.engine) {
                    if (renders.load() == 0) acquired.set_value(false);
                    break;
                }
                inRender.store(true, std::memory_order_release);
                if (++renders == 1) {
                    acquired.set_value(true);
                    teardownFuture.wait();
                }
                inRender.store(false, std::memory_order_release);
                registry.releaseForRender(lease.slot);
            }
        });

        check(acquiredFuture.get(), "worker acquired a render lease");

        const int slot = registry.beginTeardown(handle);
        check(slot >= 0, "teardown starts while renderer is active");
        teardownPublished.set_value();
        registry.waitForRenderers(slot);
        check(!inRender.load(std::memory_order_acquire),
              "waitForRenderers returns only after the render block exits");

        const int rendersAtTeardown = renders.load();
        std::this_thread::sleep_for(std::chrono::milliseconds(2));
        check(renders.load() == rendersAtTeardown,
              "no renderer enters after teardown is published");

        registry.unregisterEngine(engine.get());
        registry.finishTeardown(slot);
        stop.store(true, std::memory_order_release);
        worker.join();
        check(registry.acquireForRender(handle).engine == nullptr,
              "concurrent teardown leaves no live slot");
    }

    {
        auto first = std::make_unique<AudioDspEngine>();
        check(registry.registerEngine(first.get()), "register before sink opens");
        registry.setSinkBitDepth(16);
        check(first->getSinkBitDepth() == 16, "sink depth reaches existing render engine");

        auto second = std::make_unique<AudioDspEngine>();
        check(registry.registerEngine(second.get()), "register after sink opens");
        check(second->getSinkBitDepth() == 16, "new render engine inherits sink depth");
        second->setSinkBitDepth(24);
        AudioDspEngine::instance().setSinkBitDepth(32);  // independent AAudio open
        AudioDspEngine::instance().setSinkBitDepth(0);   // independent AAudio close
        check(first->getSinkBitDepth() == 16 && second->getSinkBitDepth() == 24,
              "local sinks and AAudio teardown cannot overwrite other render engines");

        auto snap = std::make_shared<DspParamSnapshot>();
        snap->sampleRate = 48000.0;
        snap->activeStages = STAGE_DITHER;
        snap->dither.enabled = true;
        snap->dither.targetBitDepth = 24;
        first->setSampleRate(48000.0);
        snap->generation = first->getPublishedGeneration() + 1;
        first->publishParams(snap);
        auto render = [&](int bits, bool expectFineSamples) {
            auto lease = registry.acquireForRender(handleOf(first.get()));
            check(lease.engine == first.get(), "dither uses registered JNI render target");
            if (!lease.engine) return;
            std::vector<float> pcm(2048, 0.0f);
            check(lease.engine->processInterleaved(pcm.data(), 1024, 2) == 1024,
                  "registered dither preserves frame count");
            registry.releaseForRender(lease.slot);
            bool onGrid = true, nonZero = false, off16Grid = false;
            const double scale = std::ldexp(1.0, bits - 1);
            for (float value : pcm) {
                const double k = value * scale;
                onGrid &= std::abs(k - std::rint(k)) < 1e-6;
                nonZero |= value != 0.0f;
                const double k16 = value * 32768.0;
                off16Grid |= std::abs(k16 - std::rint(k16)) > 1e-6;
            }
            check(onGrid && nonZero, "registered output dithers onto effective sink grid");
            check(off16Grid == expectFineSamples, "sink depth overrides requested 24-bit grid only when coarser");
        };
        render(16, false);

        registry.setSinkBitDepth(0);
        check(first->getSinkBitDepth() == 0 && second->getSinkBitDepth() == 0,
              "sink teardown clears every render engine depth");
        render(24, true);
        auto third = std::make_unique<AudioDspEngine>();
        check(registry.registerEngine(third.get()), "register after sink teardown");
        check(third->getSinkBitDepth() == 0, "new engine does not inherit stale sink depth");

        for (auto* engine : {first.get(), second.get(), third.get()}) {
            const int slot = registry.beginTeardown(handleOf(engine));
            registry.waitForRenderers(slot);
            registry.unregisterEngine(engine);
            registry.finishTeardown(slot);
        }
    }

    if (gFailures != 0) {
        std::cout << "[FAIL] " << gFailures << " registry check(s) failed." << std::endl;
        return 1;
    }
    std::cout << "[PASS] Engine registry lifetime is safe." << std::endl;
    return 0;
}
