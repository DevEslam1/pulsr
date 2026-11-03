// android/app/src/test/cpp/test_engine_registry.cpp
//
// Engine handle lifetime: slot admission must make stale/double destroy a
// no-op and teardown must wait only for renders on the slot being destroyed.
#include "../../main/cpp/AudioDspEngine.h"

#include <atomic>
#include <chrono>
#include <cstdint>
#include <iostream>
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
        std::thread worker([&]() {
            while (!stop.load(std::memory_order_acquire)) {
                auto lease = registry.acquireForRender(handle);
                if (!lease.engine) {
                    break;
                }
                inRender.store(true, std::memory_order_release);
                ++renders;
                std::this_thread::sleep_for(std::chrono::microseconds(200));
                inRender.store(false, std::memory_order_release);
                registry.releaseForRender(lease.slot);
            }
        });

        for (int spin = 0; spin < 1000 && renders.load() == 0; ++spin) {
            std::this_thread::yield();
        }
        check(renders.load() > 0, "worker acquired a render lease");

        const int slot = registry.beginTeardown(handle);
        check(slot >= 0, "teardown starts while renderer is active");
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

    if (gFailures != 0) {
        std::cout << "[FAIL] " << gFailures << " registry check(s) failed." << std::endl;
        return 1;
    }
    std::cout << "[PASS] Engine registry lifetime is safe." << std::endl;
    return 0;
}
