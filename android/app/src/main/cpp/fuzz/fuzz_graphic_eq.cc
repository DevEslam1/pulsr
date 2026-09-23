// android/app/src/main/cpp/fuzz/fuzz_graphic_eq.cc
#include "../ArbitraryResponseEq.h"
#include <cstdint>
#include <cstddef>
#include <string>
#include <vector>

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size > 65536) return 0; // Bound to realistic GraphicEq configuration size
    std::string input(reinterpret_cast<const char*>(data), size);

    // 1. Fuzz parseGraphicEq
    std::vector<std::pair<double, double>> nodes;
    ArbitraryResponseEq::parseGraphicEq(input, nodes);

    // 2. Fuzz loadGraphicEqString with linear phase
    ArbitraryResponseEq eq;
    eq.setSampleRate(48000.0);
    eq.setEnabled(true);
    bool loaded = eq.loadGraphicEqString(input, true);

    // 3. Process 1 block of 256 frames through the FIR
    if (loaded || !nodes.empty()) {
        float buffer[512] = {0.0f};
        for (int i = 0; i < 512; ++i) {
            buffer[i] = 0.25f;
        }
        eq.processInterleaved(buffer, 256, 2);
    }

    return 0;
}
