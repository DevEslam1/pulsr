// android/app/src/main/cpp/DopFramer.h
//
// DoP (DSD over PCM) framing per the DoP Open Standard v1.1.
//
// Input : interleaved stereo 1-bit DSD bytes (L0, R0, L1, R1, ...). Every
//         output DoP stereo frame consumes 2 DSD bytes per channel, so the
//         input byte length must be divisible by 4.
// Output: packed 24-bit PCM samples (3 bytes each, little-endian in memory:
//         DSD0, DSD1, marker) laid out per stereo frame as
//         [L0, L1, marker, R0, R1, marker] = 6 bytes.
// Markers alternate 0x05 / 0xFA per sample, per the standard. `firstMarker`
// lets a caller continue an existing alternating stream across buffers.
//
// The PCM stream carrying DoP must run at dsdSampleRate / 16
// (e.g. DSD64 2.8224 MHz -> 176.4 kHz / 24-bit). This module only frames
// bytes; it never opens streams (pure function, unit-tested).
#ifndef PULSR_DOP_FRAMER_H_
#define PULSR_DOP_FRAMER_H_

#include <cstddef>
#include <cstdint>

namespace pulsr {

inline constexpr uint8_t kDopMarkerA = 0x05;
inline constexpr uint8_t kDopMarkerB = 0xFA;

inline bool FrameDopInterleaved(const uint8_t* dsd, size_t dsdBytes,
                                uint8_t* out, size_t outCapacity,
                                size_t* outBytes,
                                uint8_t firstMarker = kDopMarkerA) {
    if (outBytes != nullptr) *outBytes = 0;
    if (dsd == nullptr || out == nullptr || outBytes == nullptr) return false;
    if (dsdBytes == 0 || (dsdBytes % 4) != 0) return false;

    const size_t frames = dsdBytes / 4;
    const size_t needed = frames * 6;
    if (outCapacity < needed) return false;

    const uint8_t markerFlip =
        (firstMarker == kDopMarkerA) ? kDopMarkerB : kDopMarkerA;
    for (size_t i = 0; i < frames; ++i) {
        const uint8_t marker = (i % 2 == 0) ? firstMarker : markerFlip;
        const size_t in = i * 4;
        const size_t on = i * 6;
        out[on + 0] = dsd[in + 0];   // L DSD0
        out[on + 1] = dsd[in + 1];   // L DSD1
        out[on + 2] = marker;
        out[on + 3] = dsd[in + 2];   // R DSD0
        out[on + 4] = dsd[in + 3];   // R DSD1
        out[on + 5] = marker;
    }
    *outBytes = needed;
    return true;
}

}  // namespace pulsr

#endif  // PULSR_DOP_FRAMER_H_
