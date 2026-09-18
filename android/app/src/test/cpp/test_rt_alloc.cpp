// android/app/src/test/cpp/test_rt_alloc.cpp
#include "../../main/cpp/AudioDspEngine.h"
#include <iostream>
#include <vector>
#include <cassert>
#include <cstdlib>
#include <new>
#include <atomic>
#include <functional>

static std::atomic<bool> g_rt_guard_enabled{false};
static std::atomic<uint64_t> g_rt_alloc_count{0};

void* operator new(std::size_t size) {
    if (g_rt_guard_enabled.load(std::memory_order_relaxed)) {
        g_rt_alloc_count.fetch_add(1, std::memory_order_relaxed);
    }
    void* p = std::malloc(size);
    if (!p) throw std::bad_alloc();
    return p;
}

void operator delete(void* p) noexcept {
    std::free(p);
}

void operator delete(void* p, std::size_t) noexcept {
    std::free(p);
}

void* operator new[](std::size_t size) {
    if (g_rt_guard_enabled.load(std::memory_order_relaxed)) {
        g_rt_alloc_count.fetch_add(1, std::memory_order_relaxed);
    }
    void* p = std::malloc(size);
    if (!p) throw std::bad_alloc();
    return p;
}

void operator delete[](void* p) noexcept {
    std::free(p);
}

void operator delete[](void* p, std::size_t) noexcept {
    std::free(p);
}

void runRtAllocGuardTest() {
    std::cout << "\n=== [TEST 9/12] Real-Time Audio Zero-Allocation & Zero-Lock Guard Test (BUG-001) ===" << std::endl;
    auto& engine = AudioDspEngine::instance();
    engine.setSampleRate(48000.0);

    auto snapshot = std::make_shared<DspParamSnapshot>();
    snapshot->generation = 100;
    snapshot->activeStages = 0xFFFFFFFF; // Enable all stages: EQ, Crossfeed, Reverb, Panner, Resampler, Limiter
    snapshot->eq.enabled = true;
    snapshot->crossfeed.enabled = true;
    snapshot->reverb.enabled = true;
    snapshot->reverb.wetDry = 0.50;
    snapshot->reverb.predelayMs = 20.0;
    snapshot->reverb.preset = 1; // Room
    snapshot->reverb.preparedIr = PreparedIr::createSynthetic(48000.0, 1, 0.5f);
    snapshot->panner.balance = 0.2;
    snapshot->resampler.enabled = true;
    snapshot->resampler.inRate = 48000.0;
    snapshot->resampler.outRate = 48000.0;
    snapshot->limiter.enabled = true;

    engine.publishParams(snapshot);

    const int blockSize = 512;
    const int channels = 2;
    std::vector<float> audio(blockSize * channels, 0.1f);

    // Warm-up pass to let internal buffers initialize
    engine.processInterleaved(audio.data(), blockSize, channels);

    g_rt_alloc_count.store(0);
    PreparedIr::resetCacheMutexLockCount();
    g_rt_guard_enabled.store(true);

    const int testIterations = 5000;
    for (int i = 0; i < testIterations; ++i) {
        audio[0] = 0.05f * (i % 10);
        audio[1] = -0.05f * (i % 10);
        int out = engine.processInterleaved(audio.data(), blockSize, channels);
        assert(out == blockSize);
    }
    g_rt_guard_enabled.store(false);

    assert(g_rt_alloc_count.load() == 0);
    assert(PreparedIr::getCacheMutexLockCount() == 0);

    // Extended test (BUG-001): Sweep preset changes (0..7)
    for (int p = 0; p < 8; ++p) {
        g_rt_guard_enabled.store(false);
        auto snap = std::make_shared<DspParamSnapshot>(*engine.getParams());
        snap->generation = 200 + p;
        snap->reverb.preset = p;
        snap->reverb.preparedIr = PreparedIr::createSynthetic(snap->sampleRate, p, static_cast<float>(snap->reverb.damping));
        engine.publishParams(snap);

        PreparedIr::resetCacheMutexLockCount();
        g_rt_alloc_count.store(0);
        g_rt_guard_enabled.store(true);

        for (int i = 0; i < 50; ++i) {
            int out = engine.processInterleaved(audio.data(), blockSize, channels);
            assert(out == blockSize);
        }
        g_rt_guard_enabled.store(false);

        assert(g_rt_alloc_count.load() == 0);
        assert(PreparedIr::getCacheMutexLockCount() == 0);
    }

    // Extended test (BUG-001): Sweep damping changes (0.1 .. 0.9)
    for (float d = 0.1f; d <= 0.9f; d += 0.2f) {
        g_rt_guard_enabled.store(false);
        auto snap = std::make_shared<DspParamSnapshot>(*engine.getParams());
        snap->generation = 300 + static_cast<int>(d * 10);
        snap->reverb.damping = d;
        snap->reverb.preparedIr = PreparedIr::createSynthetic(snap->sampleRate, snap->reverb.preset, d);
        engine.publishParams(snap);

        PreparedIr::resetCacheMutexLockCount();
        g_rt_alloc_count.store(0);
        g_rt_guard_enabled.store(true);

        for (int i = 0; i < 50; ++i) {
            int out = engine.processInterleaved(audio.data(), blockSize, channels);
            assert(out == blockSize);
        }
        g_rt_guard_enabled.store(false);

        assert(g_rt_alloc_count.load() == 0);
        assert(PreparedIr::getCacheMutexLockCount() == 0);
    }

    // Extended test (BUG-001): Null preparedIr snapshot must not allocate or acquire mutex on RT thread
    {
        g_rt_guard_enabled.store(false);
        auto snap = std::make_shared<DspParamSnapshot>(*engine.getParams());
        snap->generation = 400;
        snap->reverb.preset = 4; // Change preset but with null preparedIr
        snap->reverb.preparedIr = nullptr;
        engine.publishParams(snap);

        PreparedIr::resetCacheMutexLockCount();
        g_rt_alloc_count.store(0);
        g_rt_guard_enabled.store(true);

        for (int i = 0; i < 50; ++i) {
            int out = engine.processInterleaved(audio.data(), blockSize, channels);
            assert(out == blockSize);
        }
        g_rt_guard_enabled.store(false);

        assert(g_rt_alloc_count.load() == 0);
        assert(PreparedIr::getCacheMutexLockCount() == 0);
    }

    // Extended test: Prewarmed sample rate changes (e.g. 48000 -> 96000 -> 44100 -> 192000 -> 48000)
    const double testRates[] = {96000.0, 44100.0, 88200.0, 192000.0, 48000.0};
    for (double newRate : testRates) {
        g_rt_guard_enabled.store(false);
        engine.setSampleRate(newRate); // Prewarms IR on control thread

        PreparedIr::resetCacheMutexLockCount();
        g_rt_alloc_count.store(0);
        g_rt_guard_enabled.store(true);

        // Audio thread processing must apply new sample rate with 0 allocations & 0 mutex locks
        for (int i = 0; i < 200; ++i) {
            audio[0] = 0.02f * (i % 10);
            audio[1] = -0.02f * (i % 10);
            int out = engine.processInterleaved(audio.data(), blockSize, channels);
            assert(out == blockSize);
        }
        g_rt_guard_enabled.store(false);

        assert(g_rt_alloc_count.load() == 0);
        assert(PreparedIr::getCacheMutexLockCount() == 0);
    }

    std::cout << "  RT Allocations: " << g_rt_alloc_count.load()
              << " | RT Cache Mutex Locks: " << PreparedIr::getCacheMutexLockCount() << std::endl;
    std::cout << "  ✓ Zero allocations and zero mutex locks on real-time audio thread verified 100%." << std::endl;
}

// Verifies that applying prepared ViperDDC / LiveProg / ArbitraryResponseEq
// payloads (parsed/compiled off the audio thread) performs no heap allocation
// in the audio callback. Uses two distinct payload sets so the engine's
// generation change actually re-applies them while the guard is armed.
void runRtPreparedPayloadTest() {
    std::cout << "\n=== [RT 2/2] Prepared ViperDDC/LiveProg/ArbEq apply (zero RT allocations) ===" << std::endl;
    auto& engine = AudioDspEngine::instance();
    engine.setSampleRate(48000.0);

    const int blockSize = 512;
    const int channels = 2;
    std::vector<float> audio(blockSize * channels, 0.1f);

    // Warm all three so their capacities are reserved off the guarded section.
    {
        auto s = std::make_shared<DspParamSnapshot>();
        s->generation = 900;
        s->activeStages = STAGE_VIPER_DDC | STAGE_LIVE_PROG | STAGE_ARBITRARY_EQ;
        std::vector<ViperDdcSection> a, b;
        ViperDdc::parseVdcContent("SR_48000 1.0 0.0 0.0 0.05 -0.04", a, b);
        s->viperDdc.enabled = true;
        s->viperDdc.sections441 = std::make_shared<const std::vector<ViperDdcSection>>(a);
        s->viperDdc.sections480 = std::make_shared<const std::vector<ViperDdcSection>>(b);
        LiveProg v;
        v.loadCode("@sample\n spl0 = spl0;");
        s->liveProg.enabled = true;
        s->liveProg.program = v.buildProgram();
        std::vector<std::pair<double, double>> n;
        ArbitraryResponseEq::parseGraphicEq("GraphicEq: 100 2; 1000 0", n);
        s->arbitraryEq.enabled = true;
        s->arbitraryEq.parsedNodes = std::make_shared<const std::vector<std::pair<double, double>>>(n);
        engine.publishParams(s);
        engine.processInterleaved(audio.data(), blockSize, channels);
    }

    auto isolate = [&](const char* name, int slot, const std::function<void(DspParamSnapshot&)>& build) {
        auto s = std::make_shared<DspParamSnapshot>();
        s->generation = 910 + slot;
        s->activeStages = STAGE_VIPER_DDC | STAGE_LIVE_PROG | STAGE_ARBITRARY_EQ;
        build(*s);
        engine.publishParams(s);
        PreparedIr::resetCacheMutexLockCount();
        g_rt_alloc_count.store(0);
        g_rt_guard_enabled.store(true);
        for (int i = 0; i < 2000; ++i) {
            audio[0] = 0.01f * (i % 7);
            audio[1] = -0.01f * (i % 7);
            engine.processInterleaved(audio.data(), blockSize, channels);
        }
        g_rt_guard_enabled.store(false);
        const uint64_t allocs = g_rt_alloc_count.load();
        std::cout << "  ✓ " << name << " prepared payload applied with " << allocs
                  << " RT allocations." << std::endl;
        return allocs;
    };

    uint64_t allocs = 0;
    allocs += isolate("Viper", 0, [](DspParamSnapshot& s) {
        std::vector<ViperDdcSection> a, b;
        ViperDdc::parseVdcContent("SR_48000 1.0 0.0 0.0 0.04 -0.03", a, b);
        s.viperDdc.enabled = true;
        s.viperDdc.sections441 = std::make_shared<const std::vector<ViperDdcSection>>(a);
        s.viperDdc.sections480 = std::make_shared<const std::vector<ViperDdcSection>>(b);
    });
    allocs += isolate("LiveProg", 1, [](DspParamSnapshot& s) {
        LiveProg v;
        v.loadCode("@sample\n spl0 = spl0 * 0.9;");
        s.liveProg.enabled = true;
        s.liveProg.program = v.buildProgram();
    });
    allocs += isolate("ArbEq", 2, [](DspParamSnapshot& s) {
        std::vector<std::pair<double, double>> n;
        ArbitraryResponseEq::parseGraphicEq("GraphicEq: 200 1; 1000 0; 5000 -1", n);
        s.arbitraryEq.enabled = true;
        s.arbitraryEq.parsedNodes = std::make_shared<const std::vector<std::pair<double, double>>>(n);
    });

    assert(allocs == 0);
    for (int i = 0; i < blockSize * channels; ++i) {
        assert(std::isfinite(audio[i]));
    }
    std::cout << "  ✓ Prepared payload re-application allocated 0 times on the audio thread." << std::endl;

    engine.setActiveStages(0xFFFFFFFF);
}

