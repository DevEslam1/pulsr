// android/app/src/main/cpp/SinkQuantizer.h
//
// The last quantizer before bytes leave the process. Every output path ends up
// converting float DSP output into the integer PCM container the device was
// opened at, and plain rounding there correlates the error with the signal —
// which on a low-impedance IEM reads as graininess on quiet fades and decays.
//
// The convention this file enforces (already used by the fork's Java
// Pcm16Quantizer on the default path) is:
//   * requantizing something NOT already on the target grid  -> add TPDF;
//   * requantizing something that IS exactly on the grid      -> add nothing.
// The second rule is what keeps the native engine's noise-shaped dither and
// this stage from stacking two dither layers (+3 dB of noise floor for nothing).
//
// Host-testable: no AAudio/usbfs types, so the native test suite exercises it
// directly.
#pragma once

#include <cmath>
#include <cstdint>

namespace pulsr {

/// Per-stream TPDF state. Two xorshift32 generators, the same construction the
/// engine uses; RT-safe (no allocation, no locks, no system calls).
struct SinkDitherState {
    uint32_t s1 = 0x9E3779B9u;
    uint32_t s2 = 0x85EBCA6Bu;
};

/// Triangular probability density over (-1, +1) LSB: the difference of two
/// independent uniform draws.
inline double SinkTpdf(SinkDitherState& st) {
    st.s1 ^= st.s1 << 13;
    st.s1 ^= st.s1 >> 17;
    st.s1 ^= st.s1 << 5;
    st.s2 ^= st.s2 << 13;
    st.s2 ^= st.s2 >> 17;
    st.s2 ^= st.s2 << 5;
    const double r1 = static_cast<double>(st.s1) * (1.0 / 4294967296.0);
    const double r2 = static_cast<double>(st.s2) * (1.0 / 4294967296.0);
    return r1 - r2;
}

/// True when a value scaled into LSB units already sits on an integer step, so
/// an upstream stage quantized at this same depth.
///
/// The window is absolute in LSB units, not relative: engine output is
/// `integer * 2^-(bits-1)` re-read as float32, which is exact for 16 and 24-bit
/// grids, so anything further than 1e-4 LSB from a step genuinely was not
/// quantized here.
inline bool IsOnQuantGrid(double scaledToLsb) {
    return std::abs(scaledToLsb - std::rint(scaledToLsb)) < 1e-4;
}

/// Rounds a value already scaled into LSB units, adding TPDF only when the
/// sample is not already on the grid. Saturates to [lo, hi] and maps
/// non-finite input to silence rather than letting NaN become a full-scale
/// sample (which is what a raw cast would do).
///
/// `allowDither` is false for a container finer than the float32 signal's own
/// mantissa, where TPDF would only add noise below the representation floor
/// (see DitherHelpsAtBits).
inline int64_t QuantizeLsbWithDither(double scaledToLsb, int64_t lo, int64_t hi,
                                     SinkDitherState& st, bool allowDither = true) {
    if (!std::isfinite(scaledToLsb)) return 0;
    double v = (allowDither && !IsOnQuantGrid(scaledToLsb))
        ? scaledToLsb + SinkTpdf(st)
        : scaledToLsb;
    double r = std::rint(v);
    if (r > static_cast<double>(hi)) return hi;
    if (r < static_cast<double>(lo)) return lo;
    return static_cast<int64_t>(r);
}

/// Full-scale integer step count for a signed PCM depth: 1 LSB = 1/2^(bits-1).
/// Returns 0 for a depth the callers must not quantize at (anything not
/// 16/24/32), so a mis-set depth fails loudly into the caller's guard instead
/// of silently packing at the wrong scale.
inline double LsbScaleForBits(int bits) {
    switch (bits) {
        case 16: return 32768.0;     // 2^15
        case 24: return 8388608.0;   // 2^23
        case 32: return 2147483648.0; // 2^31
        default: return 0.0;
    }
}

/// A float32 signal carries ~24 bits of mantissa, so dithering into a 32-bit
/// container adds noise below the representation's own floor. Packing at 32
/// bits therefore rounds plainly — same conclusion the engine reaches when its
/// target depth is 32.
inline bool DitherHelpsAtBits(int bits) { return bits < 32; }

/// Packs one float [-1,1] sample into `dst` as little-endian signed integer PCM
/// of `bytesPerSample` (2=S16_LE, 3=S24_3LE, 4=S32_LE), dithered per the rules
/// above. Returns the number of bytes written, or 0 when the container is not
/// one this function understands — a caller must not silently write garbage
/// bytes for an unexpected subslot size.
///
/// Negative values are shifted with sign but every byte is masked, so the
/// result is the two's-complement little-endian the UAC/AAudio containers
/// expect.
inline bool IsPcmWireFormat(int bytesPerSample, int validBits) {
    return bytesPerSample >= 2 && bytesPerSample <= 4 &&
        (validBits == 16 || validBits == 24 || validBits == 32) &&
        validBits <= bytesPerSample * 8;
}

// Integer transport never passes through float: prepend zero low bytes so the
// source sign bit stays at the wire subslot's MSB, including negative samples.
inline int PackRawPcmSample(const uint8_t* src, int sourceBits, uint8_t* dst,
                            int bytesPerSample, int validBits) {
    if (!src || !dst || !IsPcmWireFormat(bytesPerSample, validBits) ||
        (sourceBits != 16 && sourceBits != 24 && sourceBits != 32) ||
        sourceBits > validBits) return 0;
    const int sourceBytes = sourceBits / 8;
    const int padding = bytesPerSample - sourceBytes;
    for (int b = 0; b < padding; ++b) dst[b] = 0;
    for (int b = 0; b < sourceBytes; ++b) dst[padding + b] = src[b];
    return bytesPerSample;
}

inline int PackPcmSample(float v, uint8_t* dst, int bytesPerSample,
                         SinkDitherState& st, int validBitDepth = 0) {
    if (bytesPerSample < 2 || bytesPerSample > 4) return 0;
    const int bits = validBitDepth == 0 ? bytesPerSample * 8 : validBitDepth;
    if (!IsPcmWireFormat(bytesPerSample, bits)) return 0;
    const double scale = LsbScaleForBits(bits);
    if (scale == 0.0 || dst == nullptr) return 0;
    const int64_t half = static_cast<int64_t>(1) << (bits - 1);
    const double scaled =
        std::isfinite(v) ? static_cast<double>(v) * scale : 0.0;
    const int64_t q = QuantizeLsbWithDither(scaled, -half, half - 1, st,
                                           DitherHelpsAtBits(bits));
    const uint32_t wire = static_cast<uint32_t>(q) << (bytesPerSample * 8 - bits);
    for (int b = 0; b < bytesPerSample; ++b) {
        dst[b] = static_cast<uint8_t>(wire >> (8 * b));
    }
    return bytesPerSample;
}

// Gap processing may operate on the whole wire grid. Requantize its output at
// the DAC's valid depth without a float roundtrip or biased padding truncation.
inline int RequantizePcmValidBits(uint8_t* data, int bytesPerSample, int validBits,
                                  SinkDitherState& st) {
    if (!data || !IsPcmWireFormat(bytesPerSample, validBits)) return 0;
    const int wireBits = bytesPerSample * 8;
    const int shift = wireBits - validBits;
    if (shift == 0) return bytesPerSample;
    uint32_t u = 0;
    for (int b = 0; b < bytesPerSample; ++b) u |= static_cast<uint32_t>(data[b]) << (8 * b);
    const int64_t signedValue = (u & (uint32_t{1} << (wireBits - 1)))
        ? static_cast<int64_t>(u) - (int64_t{1} << wireBits) : static_cast<int64_t>(u);
    const int64_t half = int64_t{1} << (validBits - 1);
    const int64_t q = QuantizeLsbWithDither(
        static_cast<double>(signedValue) / (uint64_t{1} << shift),
        -half, half - 1, st, DitherHelpsAtBits(validBits));
    u = static_cast<uint32_t>(q) << shift;
    for (int b = 0; b < bytesPerSample; ++b) data[b] = static_cast<uint8_t>(u >> (8 * b));
    return bytesPerSample;
}

}  // namespace pulsr
