// android/app/src/main/cpp/DsdDecoder.h
#pragma once

#include <vector>
#include <cstdint>
#include <cstddef>
#include <cmath>
#include <algorithm>

class DsdDecoder {
public:
    enum class DsdRate {
        DSD64 = 64,    // 2.8224 MHz (64 * 44.1 kHz)
        DSD128 = 128,  // 5.6448 MHz
        DSD256 = 256   // 11.2896 MHz
    };

    enum class DsdBitOrder {
        LSB_FIRST = 0, // DSF format specification (Sony standard): bit 0 transmitted first
        MSB_FIRST = 1  // DFF / DSDIFF specification (Philips standard): bit 7 transmitted first
    };

    DsdDecoder();
    void configure(DsdRate rate, int targetPcmSampleRate = 176400, DsdBitOrder bitOrder = DsdBitOrder::LSB_FIRST);
    void setBitOrder(DsdBitOrder bitOrder) { bitOrder_ = bitOrder; }
    DsdBitOrder getBitOrder() const { return bitOrder_; }
    double getDecimationRatio() const { return decimationRatio_; }
    int getExpectedPcmFrames(int byteCount) const {
        if (decimationRatio_ <= 0.0 || byteCount <= 0) return 0;
        return static_cast<int>(std::ceil((byteCount * 8.0) / decimationRatio_)) + 64;
    }
    void reset();

    // Decodes DSD bitstream to interleaved float PCM [-1.0, 1.0] with 3dB headroom and 5Hz DC blocking
    int decodeDsdBytes(const uint8_t* dsdL, const uint8_t* dsdR, int byteCount,
                       float* pcmOutInterleaved, int maxPcmFrames);

private:
    void generateFilters();

    // Stage 2 Anti-Aliasing Decimation FIR filter coefficients
    static constexpr int DECIMATION_TAPS = 383;
    static constexpr int DECIMATION_HALF = DECIMATION_TAPS / 2;
    float decimationCoeffs_[DECIMATION_TAPS] = {};

    // CIC stage 1 integrators & combs (uint32_t for well-defined mod 2^32 wrap)
    struct CicState {
        uint32_t int1 = 0, int2 = 0, int3 = 0;
        uint32_t comb1 = 0, comb2 = 0, comb3 = 0;
        uint32_t comb1_d = 0, comb2_d = 0, comb3_d = 0;
    };
    CicState cicL_;
    CicState cicR_;
    int cicCount_ = 0;

    // Stage 2 ring buffer
    float stage2RingL_[DECIMATION_TAPS] = {};
    float stage2RingR_[DECIMATION_TAPS] = {};
    int stage2WriteIdx_ = 0;

    // 5Hz DC blocker states
    float dcPrevInL_ = 0.0f, dcPrevOutL_ = 0.0f;
    float dcPrevInR_ = 0.0f, dcPrevOutR_ = 0.0f;
    float dcPole_ = 0.9993f;

    double decimationRatio_ = 16.0;
    double phaseAcc_ = 0.0;
    DsdRate dsdRate_ = DsdRate::DSD64;
    DsdBitOrder bitOrder_ = DsdBitOrder::LSB_FIRST;
    int targetRate_ = 176400;
};
