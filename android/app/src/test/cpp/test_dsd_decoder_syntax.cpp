// android/app/src/test/cpp/test_dsd_decoder_syntax.cpp
#include "../../main/cpp/DsdDecoder.h"
#include <iostream>
#include <vector>
#include <cmath>
#include <cassert>

void runDsdDecoderSyntaxAndRatioTest() {
    std::cout << "\n=== [TEST] DSD Decoder Syntax and Decimation Ratio Clamping ===" << std::endl;
    DsdDecoder decoder;

    // Test decimation ratio clamping when targetRate is high (e.g. 768kHz on DSD64)
    decoder.configure(DsdDecoder::DsdRate::DSD64, 768000);
    assert(decoder.getDecimationRatio() == 8.0);
    assert(decoder.getTargetRate() == 352800);
    std::cout << "DSD64 @ 768kHz clamped to ratio: " << decoder.getDecimationRatio()
              << ", targetRate: " << decoder.getTargetRate() << std::endl;

    // Normal configuration (DSD64 @ 176.4kHz -> ratio 16.0)
    decoder.configure(DsdDecoder::DsdRate::DSD64, 176400);
    assert(decoder.getDecimationRatio() == 16.0);
    assert(decoder.getTargetRate() == 176400);

    // Process DSD stream (alternating 0xAA bit pattern)
    const int byteCount = 1024;
    std::vector<uint8_t> dsdL(byteCount, 0xAA);
    std::vector<uint8_t> dsdR(byteCount, 0x55);
    int expectedFrames = decoder.getExpectedPcmFrames(byteCount);
    std::vector<float> pcmOut(expectedFrames * 2, 0.0f);

    int framesDecoded = decoder.decodeDsdBytes(dsdL.data(), dsdR.data(), byteCount, pcmOut.data(), expectedFrames);
    assert(framesDecoded > 0);

    // Verify all samples are valid numbers (no NaN, no Inf)
    for (int i = 0; i < framesDecoded * 2; ++i) {
        float sample = pcmOut[i];
        assert(!std::isnan(sample));
        assert(!std::isinf(sample));
    }
    std::cout << "Decoded " << framesDecoded << " PCM frames cleanly with 0 NaNs and 0 Infs." << std::endl;

    std::cout << "  [PASS] DSD Decoder Syntax and Decimation Ratio Test Passed!" << std::endl;
}

#ifdef STANDALONE_TEST_DSD_SYNTAX
int main() {
    runDsdDecoderSyntaxAndRatioTest();
    return 0;
}
#endif
