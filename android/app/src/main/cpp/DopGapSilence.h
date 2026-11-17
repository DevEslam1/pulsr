// android/app/src/main/cpp/DopGapSilence.h
//
// Item 3: DoP-aware underrun silence for the USB exclusive path.
//
// A DoP (DSD over PCM) stream is not PCM: every 16/24/32-bit word carries an
// alternating 0x05 / 0xFA marker in its MSB and two DSD bytes in the payload.
// Zero-filling a DoP gap therefore destroys the marker pattern, and a
// DoP-capable DAC that loses marker sync treats the gap as noise (or mutes
// until it re-locks). The correct silence is a *valid DoP frame* whose payload
// is zero: the DC level of a DSD "silence" bitstream, which the DAC's own
// low-pass filter renders as silence.
//
// The helper is a pure function so both the sink and the host tests share one
// implementation. Markers alternate per stereo frame (both channels of a frame
// carry the same marker, per DoP Open Standard v1.1); `firstMarker` continues
// the producer's phase across packets.
#ifndef PULSR_DOP_GAP_SILENCE_H_
#define PULSR_DOP_GAP_SILENCE_H_

#include <cstddef>
#include <cstdint>
#include "DopFramer.h"

namespace pulsr {

/// True when `bytesPerSample` is a container this helper can fill.
inline constexpr bool IsDopSilenceContainer(int bytesPerSample) {
    return bytesPerSample == 2 || bytesPerSample == 3 || bytesPerSample == 4;
}

/// Total wire bytes for `frames` DoP frames.
inline constexpr size_t DopSilenceBytes(int frames, int channels, int bytesPerSample) {
    if (frames <= 0 || channels <= 0 || !IsDopSilenceContainer(bytesPerSample)) return 0;
    return static_cast<size_t>(frames) * static_cast<size_t>(channels) *
           static_cast<size_t>(bytesPerSample);
}

/// Fills `frames` DoP frames with valid DoP silence.
///
/// Layout (little-endian, matching FrameDopPlanar): all payload bytes are 0x00
/// and the marker sits in the MSB byte of each sample, i.e.
///   16-bit : [0x00, marker]
///   24-bit : [0x00, 0x00, marker]
///   32-bit : [0x00, 0x00, 0x00, marker]   ("24-in-32" carriers)
/// Markers alternate 0x05 / 0xFA per frame, starting at `firstMarker`.
///
/// Returns the marker the *next* frame of the same stream must use, so a caller
/// can keep the alternation continuous across packets; an invalid container or
/// marker is rejected by returning `firstMarker` unchanged and writing nothing.
inline uint8_t FillDopSilence(uint8_t* dst, int frames, int channels,
                              int bytesPerSample, uint8_t firstMarker) {
    if (dst == nullptr || frames <= 0 || channels <= 0 ||
        !IsDopSilenceContainer(bytesPerSample)) {
        return firstMarker;
    }
    if (firstMarker != kDopMarkerA && firstMarker != kDopMarkerB) return firstMarker;

    const uint8_t flip = (firstMarker == kDopMarkerA) ? kDopMarkerB : kDopMarkerA;
    const size_t sampleBytes = static_cast<size_t>(bytesPerSample);
    uint8_t* cursor = dst;
    for (int f = 0; f < frames; ++f) {
        const uint8_t marker = (f % 2 == 0) ? firstMarker : flip;
        for (int ch = 0; ch < channels; ++ch) {
            for (size_t b = 0; b + 1 < sampleBytes; ++b) {
                cursor[b] = 0x00;
            }
            cursor[sampleBytes - 1] = marker;
            cursor += sampleBytes;
        }
    }
    return (frames % 2 == 0) ? firstMarker : flip;
}

/// Marker implied by the last real DoP frame already written into a packet.
/// A frame is `channels * containerBytes` wide and the marker of channel 0 lives
/// in the container's MSB byte. Returns `fallback` when the byte is not a DoP
/// marker (plain raw PCM, or a producer that is not framing DoP).
inline uint8_t DopMarkerAfterLastFrame(const uint8_t* packet, size_t frames,
                                       int channels, int bytesPerSample,
                                       uint8_t fallback) {
    if (packet == nullptr || frames == 0 || channels <= 0 ||
        !IsDopSilenceContainer(bytesPerSample)) {
        return fallback;
    }
    const size_t frameBytes =
        static_cast<size_t>(channels) * static_cast<size_t>(bytesPerSample);
    const uint8_t marker =
        packet[(frames - 1) * frameBytes + static_cast<size_t>(bytesPerSample) - 1];
    if (marker == kDopMarkerA) return kDopMarkerB;
    if (marker == kDopMarkerB) return kDopMarkerA;
    return fallback;
}

}  // namespace pulsr

#endif  // PULSR_DOP_GAP_SILENCE_H_
