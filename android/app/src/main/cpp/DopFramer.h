// android/app/src/main/cpp/DopFramer.h
//
// DoP (DSD over PCM) framing per the DoP Open Standard v1.1.
//
// Input : interleaved stereo 1-bit DSD bytes, two bytes per channel per frame
//         laid out as [L_older, L_newer, R_older, R_newer, ...]. The first byte
//         of each channel pair is temporally OLDER than the second. Every output
//         DoP stereo frame consumes 2 DSD bytes per channel, so the input byte
//         length must be divisible by 4.
// Output: packed 24-bit PCM samples (3 bytes each). Per DoP v1.1 the 24-bit word
//         is [marker | older DSD byte | newer DSD byte] with the marker in the
//         MSB and the oldest DSD bit as the MSB of the audio bits. Stored
//         little-endian in memory that is [newer, older, marker], so each stereo
//         frame is [L_newer, L_older, marker, R_newer, R_older, marker] = 6 bytes.
//         This matches the Dart DopEncoder (dop_encoder.dart). The earlier
//         [older, newer, marker] layout swapped the two DSD bytes in every word,
//         which a DoP-capable DAC decodes as noise.
// Markers alternate 0x05 / 0xFA per sample, per the standard. `firstMarker`
// lets a caller continue an existing alternating stream across buffers.
//
// The PCM stream carrying DoP must run at dsdSampleRate / 16
// (e.g. DSD64 2.8224 MHz -> 176.4 kHz / 24-bit). This module only frames
// bytes; it never opens streams (pure function, unit-tested).
#ifndef PULSR_DOP_FRAMER_H_
#define PULSR_DOP_FRAMER_H_

#include <array>
#include <cstddef>
#include <cstdint>
#include <limits>

namespace pulsr {

inline constexpr uint8_t kDopMarkerA = 0x05;
inline constexpr uint8_t kDopMarkerB = 0xFA;

/// Returns the DoP PCM carrier rate for a DSD multiple (DSD64=64 -> 176400,
/// DSD128=128 -> 352800, DSD256=256 -> 705600), or 0 for unsupported rates.
inline constexpr int32_t DopPcmSampleRate(int32_t dsdRate) {
    if (dsdRate <= 0) return 0;
    if (dsdRate <= 64) return 176400;
    if (dsdRate <= 128) return 352800;
    if (dsdRate <= 256) return 705600;
    return 0;
}

namespace detail {

inline constexpr uint8_t ReverseByteBits(uint8_t v) {
    uint8_t r = 0;
    for (int b = 0; b < 8; ++b) {
        r = static_cast<uint8_t>((r << 1) | (v & 1u));
        v >>= 1;
    }
    return r;
}

inline constexpr std::array<uint8_t, 256> MakeBitReverseLut() {
    std::array<uint8_t, 256> lut{};
    for (int i = 0; i < 256; ++i) {
        lut[static_cast<size_t>(i)] = ReverseByteBits(static_cast<uint8_t>(i));
    }
    return lut;
}

inline constexpr auto kBitReverseLut = MakeBitReverseLut();

}  // namespace detail

inline bool FrameDopInterleaved(const uint8_t* dsd, size_t dsdBytes,
                                uint8_t* out, size_t outCapacity,
                                size_t* outBytes,
                                uint8_t firstMarker = kDopMarkerA,
                                uint8_t* nextMarker = nullptr) {
    if (outBytes != nullptr) *outBytes = 0;
    if (dsd == nullptr || out == nullptr || outBytes == nullptr) return false;
    if (dsdBytes == 0 || (dsdBytes % 4) != 0) return false;
    if (firstMarker != kDopMarkerA && firstMarker != kDopMarkerB) return false;

    const size_t frames = dsdBytes / 4;
    if (frames > (std::numeric_limits<size_t>::max)() / 6) return false;
    const size_t needed = frames * 6;
    if (outCapacity < needed) return false;

    const uint8_t markerFlip =
        (firstMarker == kDopMarkerA) ? kDopMarkerB : kDopMarkerA;
    for (size_t i = 0; i < frames; ++i) {
        const uint8_t marker = (i % 2 == 0) ? firstMarker : markerFlip;
        const size_t in = i * 4;
        const size_t on = i * 6;
        out[on + 0] = dsd[in + 1];   // L newer DSD byte -> LSB
        out[on + 1] = dsd[in + 0];   // L older DSD byte -> middle
        out[on + 2] = marker;        // marker -> MSB
        out[on + 3] = dsd[in + 3];   // R newer DSD byte -> LSB
        out[on + 4] = dsd[in + 2];   // R older DSD byte -> middle
        out[on + 5] = marker;        // marker -> MSB
    }
    if (nextMarker != nullptr) {
        *nextMarker = (frames % 2 == 0) ? firstMarker : markerFlip;
    }
    *outBytes = needed;
    return true;
}

/// Frames planar stereo 1-bit DSD channels into 24-bit packed (6 bytes/frame)
/// or 32-bit zero-padded (8 bytes/frame) DoP v1.1 little-endian PCM frames.
/// When `reverseBits` is true, each byte's bit order is reversed inline
/// (converting LSB-first DSF bytes to MSB-first DoP order without extra copies).
inline bool FrameDopPlanar(const uint8_t* dsdLeft, const uint8_t* dsdRight,
                           size_t channelBytes, int containerBits,
                           bool reverseBits, uint8_t* out, size_t outCapacity,
                           size_t* outBytes,
                           uint8_t firstMarker = kDopMarkerA,
                           uint8_t* nextMarker = nullptr) {
    if (outBytes != nullptr) *outBytes = 0;
    if (outBytes == nullptr) return false;
    if (containerBits != 24 && containerBits != 32) return false;
    if (firstMarker != kDopMarkerA && firstMarker != kDopMarkerB) return false;
    if ((channelBytes % 2) != 0) return false;

    if (channelBytes == 0) {
        if (nextMarker != nullptr) *nextMarker = firstMarker;
        return true;
    }
    if (dsdLeft == nullptr || dsdRight == nullptr || out == nullptr) {
        return false;
    }

    const size_t frames = channelBytes / 2;
    const size_t bytesPerFrame = (containerBits == 32) ? 8 : 6;
    if (frames > (std::numeric_limits<size_t>::max)() / bytesPerFrame) {
        return false;
    }
    const size_t needed = frames * bytesPerFrame;
    if (outCapacity < needed) return false;

    const uint8_t markerFlip =
        (firstMarker == kDopMarkerA) ? kDopMarkerB : kDopMarkerA;

    if (containerBits == 32) {
        for (size_t i = 0; i < frames; ++i) {
            const uint8_t marker = (i % 2 == 0) ? firstMarker : markerFlip;
            const size_t in = i * 2;
            const size_t on = i * 8;
            uint8_t l0 = dsdLeft[in];
            uint8_t l1 = dsdLeft[in + 1];
            uint8_t r0 = dsdRight[in];
            uint8_t r1 = dsdRight[in + 1];
            if (reverseBits) {
                l0 = detail::kBitReverseLut[l0];
                l1 = detail::kBitReverseLut[l1];
                r0 = detail::kBitReverseLut[r0];
                r1 = detail::kBitReverseLut[r1];
            }
            out[on + 0] = 0x00;
            out[on + 1] = l1;
            out[on + 2] = l0;
            out[on + 3] = marker;
            out[on + 4] = 0x00;
            out[on + 5] = r1;
            out[on + 6] = r0;
            out[on + 7] = marker;
        }
    } else {
        for (size_t i = 0; i < frames; ++i) {
            const uint8_t marker = (i % 2 == 0) ? firstMarker : markerFlip;
            const size_t in = i * 2;
            const size_t on = i * 6;
            uint8_t l0 = dsdLeft[in];
            uint8_t l1 = dsdLeft[in + 1];
            uint8_t r0 = dsdRight[in];
            uint8_t r1 = dsdRight[in + 1];
            if (reverseBits) {
                l0 = detail::kBitReverseLut[l0];
                l1 = detail::kBitReverseLut[l1];
                r0 = detail::kBitReverseLut[r0];
                r1 = detail::kBitReverseLut[r1];
            }
            out[on + 0] = l1;
            out[on + 1] = l0;
            out[on + 2] = marker;
            out[on + 3] = r1;
            out[on + 4] = r0;
            out[on + 5] = marker;
        }
    }

    if (nextMarker != nullptr) {
        *nextMarker = (frames % 2 == 0) ? firstMarker : markerFlip;
    }
    *outBytes = needed;
    return true;
}

}  // namespace pulsr

#endif  // PULSR_DOP_FRAMER_H_
