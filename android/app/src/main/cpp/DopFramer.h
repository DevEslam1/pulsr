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
        out[on + 0] = dsd[in + 1];   // L newer DSD byte -> LSB
        out[on + 1] = dsd[in + 0];   // L older DSD byte -> middle
        out[on + 2] = marker;        // marker -> MSB
        out[on + 3] = dsd[in + 3];   // R newer DSD byte -> LSB
        out[on + 4] = dsd[in + 2];   // R older DSD byte -> middle
        out[on + 5] = marker;        // marker -> MSB
    }
    *outBytes = needed;
    return true;
}

}  // namespace pulsr

#endif  // PULSR_DOP_FRAMER_H_
