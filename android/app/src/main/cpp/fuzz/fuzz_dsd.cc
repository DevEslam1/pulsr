// android/app/src/main/cpp/fuzz/fuzz_dsd.cc
#include "../DsdDecoder.h"
#include <cstdint>
#include <cstddef>
#include <vector>
#include <cassert>

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size == 0 || size > 32768) return 0;

    // Split input into two halves for L and R channels
    size_t byteCount = size / 2;
    if (byteCount == 0) return 0;

    const uint8_t* dsdL = data;
    const uint8_t* dsdR = data + byteCount;

    // Test both Sony (LSB_FIRST) and Philips (MSB_FIRST) bit orders
    for (int order = 0; order < 2; ++order) {
        auto bitOrder = (order == 0) ? DsdDecoder::DsdBitOrder::LSB_FIRST
                                     : DsdDecoder::DsdBitOrder::MSB_FIRST;
        DsdDecoder decoder;
        decoder.configure(DsdDecoder::DsdRate::DSD64, 176400, bitOrder);

        int maxFrames = decoder.getExpectedPcmFrames(static_cast<int>(byteCount));
        if (maxFrames <= 0) continue;

        std::vector<float> pcmOut(static_cast<size_t>(maxFrames) * 2, 0.0f);
        int decoded = decoder.decodeDsdBytes(dsdL, dsdR, static_cast<int>(byteCount),
                                            pcmOut.data(), maxFrames);
        assert(decoded <= maxFrames);
    }

    return 0;
}
