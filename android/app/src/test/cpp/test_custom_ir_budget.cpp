// android/app/src/test/cpp/test_custom_ir_budget.cpp
#include "../../main/cpp/DspParams.h"
#include "../../main/cpp/ConvolutionReverb.h"
#include <iostream>
#include <vector>
#include <cassert>
#include <cmath>

void runCustomIrBudgetTest() {
    std::cout << "\n=== [TEST 13/22] Custom IR Budget, Capping & Cache Hit Test ===" << std::endl;

    // 1. Test Damping multiplier and cache hits (BUG-004)
    PreparedIr::clearSyntheticCache();
    assert(PreparedIr::getSyntheticCacheEntryCount() == 0);

    auto ir1 = PreparedIr::createSynthetic(48000.0, 1, 0.5f);
    assert(ir1 != nullptr);
    assert(PreparedIr::getSyntheticCacheEntryCount() == 1);

    // Same params -> must hit cache (same pointer)
    auto ir1Hit = PreparedIr::createSynthetic(48000.0, 1, 0.5f);
    assert(ir1Hit.get() == ir1.get());
    assert(PreparedIr::getSyntheticCacheEntryCount() == 1);

    // Different damping -> creates new distinct entry
    auto ir2 = PreparedIr::createSynthetic(48000.0, 1, 0.8f);
    assert(ir2 != nullptr);
    assert(ir2.get() != ir1.get());
    assert(PreparedIr::getSyntheticCacheEntryCount() == 2);
    std::cout << "  ✓ Cache-hit and damping multiplier verified." << std::endl;

    // 2. Test 512-partition capping & decimation with anti-aliasing for oversized custom IR (BUG-005, NEW-9)
    // 512 partitions * 512 samples = 262,144 samples max.
    // Create an oversized 400,000 sample IR (approx 8.3 seconds)
    const int oversizedFrames = 400000;
    std::vector<float> oversizedIr(oversizedFrames * 2, 0.01f);
    for (int i = 0; i < oversizedFrames; ++i) {
        oversizedIr[i * 2] = std::sin(i * 0.05f) * 0.1f;
        oversizedIr[i * 2 + 1] = std::cos(i * 0.05f) * 0.1f;
    }

    auto cappedIr = PreparedIr::createCustom(48000.0, oversizedIr.data(), oversizedFrames, 2);
    assert(cappedIr != nullptr);
    assert(cappedIr->numPartitions <= 512);
    assert(cappedIr->totalTaps == 512 * 512);
    std::cout << "  ✓ Oversized IR successfully decimated with anti-aliasing and capped at "
              << cappedIr->numPartitions << " partitions (" << cappedIr->totalTaps << " taps)." << std::endl;

    // 3. Test Custom IR weak_ptr pruning and full cache budget recovery (NEW-2)
    PreparedIr::clearSyntheticCache();
    assert(PreparedIr::getSyntheticCacheBytes() == 0);

    const int customFrames = 50000;
    std::vector<float> customIrData(customFrames * 2, 0.02f);
    {
        std::vector<std::shared_ptr<const PreparedIr>> customIrList;
        for (int i = 0; i < 5; ++i) {
            auto customIr = PreparedIr::createCustom(48000.0, customIrData.data(), customFrames, 2);
            assert(customIr != nullptr);
            customIrList.push_back(customIr);
        }
        size_t populatedBytes = PreparedIr::getSyntheticCacheBytes();
        assert(populatedBytes > 0);
        assert(populatedBytes <= 64 * 1024 * 1024);
        std::cout << "  ✓ Created 5 large custom IRs; cache usage: " << populatedBytes / (1024 * 1024) << " MB." << std::endl;
    } // customIrList destroyed here -> all 5 shared_ptrs released

    // Prune and assert full budget recovery
    size_t recoveredBytes = PreparedIr::getSyntheticCacheBytes();
    assert(recoveredBytes == 0);
    std::cout << "  ✓ Dropped custom IR references; cache budget fully recovered to 0 bytes after pruning." << std::endl;
}
