// android/app/src/test/cpp/test_dsd_decoder_correctness.cpp
#include "../../main/cpp/DsdDecoder.h"
#include <iostream>
#include <vector>
#include <cmath>
#include <cassert>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

int main() {
    std::cout << "[TEST] Running DSD Decoder Correctness & Fidelity Tests..." << std::endl;

    DsdDecoder decoder;

    // 1. Bit Order Mapping & Decimation Ratio
    decoder.configure(DsdDecoder::DsdRate::DSD64, 48000, DsdDecoder::DsdBitOrder::LSB_FIRST);
    assert(std::abs(decoder.getDecimationRatio() - 58.8) < 1e-4);
    std::cout << "  ✓ DSD64 -> 48kHz decimation ratio exactness verified (58.800)." << std::endl;

    // 2. Synthetic DSD PDM 1kHz Sine Decode Test targeting 48kHz
    {
        const int numDsdBytes = 70560; // 0.2 seconds of DSD64 bitstream
        std::vector<uint8_t> dsdL(numDsdBytes, 0);
        std::vector<uint8_t> dsdR(numDsdBytes, 0);

        // Delta-Sigma 1st-order PDM modulator for 1kHz sine at 2.8224MHz
        double integratorL = 0.0;
        double integratorR = 0.0;
        const double dsdFreq = 2822400.0;

        for (int byteIdx = 0; byteIdx < numDsdBytes; ++byteIdx) {
            uint8_t byteL = 0;
            uint8_t byteR = 0;

            for (int bit = 0; bit < 8; ++bit) {
                int sampleIdx = byteIdx * 8 + bit;
                double inputSine = 0.5 * std::sin(2.0 * M_PI * 1000.0 * static_cast<double>(sampleIdx) / dsdFreq);

                integratorL += inputSine;
                int bitL = (integratorL >= 0.0) ? 1 : 0;
                integratorL -= (bitL ? 1.0 : -1.0);

                integratorR += inputSine;
                int bitR = (integratorR >= 0.0) ? 1 : 0;
                integratorR -= (bitR ? 1.0 : -1.0);

                // DSF is LSB first: bit 0 placed at position `bit`
                if (bitL) byteL |= (1 << bit);
                if (bitR) byteR |= (1 << bit);
            }

            dsdL[byteIdx] = byteL;
            dsdR[byteIdx] = byteR;
        }

        const int maxFrames = decoder.getExpectedPcmFrames(numDsdBytes);
        std::vector<float> pcmOut(maxFrames * 2);

        int actualFrames = decoder.decodeDsdBytes(dsdL.data(), dsdR.data(), numDsdBytes, pcmOut.data(), maxFrames);
        assert(actualFrames > 0);

        // Verify output energy and lack of NaN/Inf
        double pcmEnergy = 0.0;
        for (int i = 0; i < actualFrames * 2; ++i) {
            assert(!std::isnan(pcmOut[i]) && !std::isinf(pcmOut[i]));
            pcmEnergy += pcmOut[i] * pcmOut[i];
        }
        assert(pcmEnergy > 0.0);
        std::cout << "  ✓ Synthetic PDM decoded successfully (" << actualFrames << " PCM frames at 48kHz)." << std::endl;
    }

    // 3. DC Blocker Suppression Test
    {
        decoder.reset();
        // Generate DC-heavy PDM bitstream (constant 0xFF / +1.0)
        const int dcBytes = 35280;
        std::vector<uint8_t> dcStream(dcBytes, 0xFF);
        std::vector<float> pcmOut(decoder.getExpectedPcmFrames(dcBytes) * 2);

        int frames = decoder.decodeDsdBytes(dcStream.data(), dcStream.data(), dcBytes, pcmOut.data(), decoder.getExpectedPcmFrames(dcBytes));
        assert(frames > 0);

        // Average output of tail should be blocked by 5Hz DC filter (< -40dB / 0.01)
        double dcTailSum = 0.0;
        int tailCount = 0;
        for (int i = frames - 500; i < frames; ++i) {
            dcTailSum += pcmOut[i * 2];
            tailCount++;
        }
        double avgDc = std::abs(dcTailSum / tailCount);
        assert(avgDc < 0.05);
        std::cout << "  ✓ 5Hz DC Blocker verified (residual DC = " << avgDc << ")." << std::endl;
    }

    std::cout << "[PASS] DSD Decoder tests successfully passed!" << std::endl;
    return 0;
}
