#pragma once

#include <vector>
#include <cstdint>
#include <cstddef>

class DsdDecoder {
public:
    enum class DsdRate {
        DSD64 = 64,    // 2.8224 MHz
        DSD128 = 128,  // 5.6448 MHz
        DSD256 = 256   // 11.2896 MHz
    };

    enum class DsdBitOrder {
        MSB_FIRST = 0, // DSF format standard
        LSB_FIRST = 1  // DFF (DSD Interchange) format standard
    };

    DsdDecoder();
    void configure(DsdRate rate, int targetPcmSampleRate = 176400, DsdBitOrder bitOrder = DsdBitOrder::MSB_FIRST);
    void setBitOrder(DsdBitOrder bitOrder) { bitOrder_ = bitOrder; }
    DsdBitOrder getBitOrder() const { return bitOrder_; }
    void reset();

    // Decodes DSD bytes (LSB or MSB first) to interleaved float PCM [-1.0, 1.0]
    int decodeDsdBytes(const uint8_t* dsdL, const uint8_t* dsdR, int byteCount,
                       float* pcmOutInterleaved, int maxPcmFrames);

private:
    static constexpr int FIR_TAPS = 64;
    float firCoeffs_[FIR_TAPS] = {};
    float historyL_[FIR_TAPS] = {};
    float historyR_[FIR_TAPS] = {};
    int historyIdx_ = 0;

    int decimationRatio_ = 16; // e.g. 2.8224MHz / 16 = 176.4kHz
    DsdRate dsdRate_ = DsdRate::DSD64;
    DsdBitOrder bitOrder_ = DsdBitOrder::MSB_FIRST;
    int targetRate_ = 176400;
};
