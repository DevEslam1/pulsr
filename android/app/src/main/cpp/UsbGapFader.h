// android/app/src/main/cpp/UsbGapFader.h
//
// Gap handling for the direct UAC2 sink, in the DAC's own packed format.
//
// When the ring runs dry the sink still has to keep the isochronous stream
// paced, so it must emit something for those frames. Zero-filling is correct
// for timing and wrong for audio: the last real frame can sit anywhere in the
// waveform, so the step to silence is a full-amplitude discontinuity, and a
// delta-sigma DAC turns that into a tick. Rejoining real audio after the gap
// steps it back up again.
//
// This class rides an envelope down to silence when the ring empties and back
// up to unity when audio resumes, so neither boundary contains a step. One
// envelope is shared by every channel of a frame, so it cannot skew the image.
// The envelope is continuous in BOTH directions by construction: a gap shorter
// than the fade does not restart from zero, it resumes from wherever the decay
// had reached.
//
// Steady-state cost is one frame unpacked per packet: when the envelope is at
// unity the copied bytes are left exactly as packed, so normal playback is
// bit-identical to not having this in the chain at all.
//
// Host-testable: plain byte buffers, no usbfs.
#pragma once

#include "SinkQuantizer.h"

#include <algorithm>
#include <cmath>
#include <cstdint>

namespace pulsr {

class UsbGapFader {
public:
    static constexpr int MAX_CHANNELS = 8;

    /// fadeMs is the time constant of the ride-down and ride-up. Two
    /// milliseconds is inaudible as a fade and long enough that no single
    /// sample step survives it.
    void configure(double sampleRate, int channels, int bytesPerSample,
                   int fadeMs = 2) {
        channels_ = std::clamp(channels, 1, MAX_CHANNELS);
        bytesPerSample_ = std::clamp(bytesPerSample, 2, 4);
        const double rate = sampleRate > 0.0 ? sampleRate : 48000.0;
        fadeSamples_ = std::max(1, static_cast<int>(std::lround(rate * fadeMs / 1000.0)));
        riseStep_ = 1.0 / static_cast<double>(fadeSamples_);
        // Reaches ~0.7% (-43 dB) after one fade window, then the floor below
        // turns it into exact zero.
        decay_ = std::exp(-5.0 / static_cast<double>(fadeSamples_));
        reset();
    }

    void reset() {
        envelope_ = 1.0;
        for (int c = 0; c < MAX_CHANNELS; ++c) last_[c] = 0.0f;
    }

    /// True while the envelope is recovering, i.e. the copied bytes still need
    /// scaling. Unity means the pass-through path is taken.
    bool recovering() const { return envelope_ < 1.0; }

    double envelope() const { return envelope_; }

    /// Called after `frames` real frames have been copied into `data`. Either
    /// it leaves them untouched (envelope at unity) and just remembers the last
    /// frame, or it scales them in place and advances the envelope toward unity.
    void applyReal(uint8_t* data, int frames, SinkDitherState& st) {
        if (frames <= 0) return;
        const int frameBytes = FrameBytes();
        if (envelope_ >= 1.0) {
            rememberFrame(data + static_cast<size_t>(frames - 1) * frameBytes);
            return;
        }
        for (int f = 0; f < frames; ++f) {
            uint8_t* frame = data + static_cast<size_t>(f) * frameBytes;
            if (envelope_ >= 1.0) break;  // remainder stays as packed
            scaleFrame(frame, envelope_, st);
            envelope_ += riseStep_;
            if (envelope_ > 1.0) envelope_ = 1.0;
        }
        // The remembered level must be what actually went out the wire, so a
        // gap that follows decays from the emitted value rather than the
        // pre-fade one.
        rememberFrame(data + static_cast<size_t>(frames - 1) * frameBytes);
    }

    /// Writes `frames` frames that decay from the last emitted sample toward
    /// silence. Once the envelope is below the 16-bit floor the output is exact
    /// zero, so a long gap cannot accumulate a denormal tail.
    void fillGap(uint8_t* data, int frames, SinkDitherState& st) {
        if (frames <= 0) return;
        const int frameBytes = FrameBytes();
        for (int f = 0; f < frames; ++f) {
            uint8_t* frame = data + static_cast<size_t>(f) * frameBytes;
            if (envelope_ <= 1e-7) {
                for (int b = 0; b < frameBytes; ++b) frame[b] = 0;
                for (int c = 0; c < channels_; ++c) last_[c] = 0.0f;
                envelope_ = 0.0;
                continue;
            }
            for (int c = 0; c < channels_; ++c) {
                PackPcmSample(static_cast<float>(last_[c]) *
                                  static_cast<float>(envelope_),
                              frame + static_cast<size_t>(c) * bytesPerSample_,
                              bytesPerSample_, st);
            }
            envelope_ *= decay_;
        }
    }

    int fadeSamples() const { return fadeSamples_; }

private:
    int FrameBytes() const { return channels_ * bytesPerSample_; }

    double Unpack(const uint8_t* p) const {
        if (bytesPerSample_ == 2) {
            return static_cast<double>(static_cast<int16_t>(
                       static_cast<uint16_t>(p[0]) | (static_cast<uint16_t>(p[1]) << 8))) /
                   32768.0;
        }
        if (bytesPerSample_ == 3) {
            const int32_t raw = static_cast<int32_t>(p[0]) |
                                (static_cast<int32_t>(p[1]) << 8) |
                                (static_cast<int32_t>(static_cast<int8_t>(p[2])) << 16);
            return static_cast<double>(raw) / 8388608.0;
        }
        const uint32_t u = static_cast<uint32_t>(p[0]) |
                           (static_cast<uint32_t>(p[1]) << 8) |
                           (static_cast<uint32_t>(p[2]) << 16) |
                           (static_cast<uint32_t>(p[3]) << 24);
        return static_cast<double>(static_cast<int32_t>(u)) / 2147483648.0;
    }

    void rememberFrame(const uint8_t* frame) {
        for (int c = 0; c < channels_; ++c) {
            last_[c] = static_cast<float>(
                Unpack(frame + static_cast<size_t>(c) * bytesPerSample_));
        }
    }

    void scaleFrame(uint8_t* frame, double gain, SinkDitherState& st) {
        for (int c = 0; c < channels_; ++c) {
            uint8_t* p = frame + static_cast<size_t>(c) * bytesPerSample_;
            PackPcmSample(static_cast<float>(Unpack(p) * gain), p,
                          bytesPerSample_, st);
        }
    }

    int channels_ = 2;
    int bytesPerSample_ = 2;
    int fadeSamples_ = 96;
    double riseStep_ = 1.0 / 96.0;
    double decay_ = 0.95;
    double envelope_ = 1.0;
    float last_[MAX_CHANNELS] = {};
};

}  // namespace pulsr
