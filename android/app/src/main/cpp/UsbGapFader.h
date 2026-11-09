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
// A gap fades the last emitted frame to silence. Recovery crossfades that
// actual emitted frame to the incoming waveform, not merely its amplitude
// envelope, so opposite-polarity recovery cannot step. Shared bounded fade
// progress preserves the image; repeated gaps restart from the emitted sample.
//
// Steady-state cost is one frame unpacked per healthy packet: copied bytes are
// left exactly as packed, so normal playback is bit-identical to not having
// this in the chain at all. Recovery is necessarily non-bit-perfect.
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

    /// fadeMs bounds both the gap fade and the recovery crossfade.
    void configure(double sampleRate, int channels, int bytesPerSample,
                   int fadeMs = 2) {
        channels_ = std::clamp(channels, 1, MAX_CHANNELS);
        bytesPerSample_ = std::clamp(bytesPerSample, 2, 4);
        const double rate = std::isfinite(sampleRate) && sampleRate > 0.0
                                ? std::clamp(sampleRate, 8000.0, 768000.0) : 48000.0;
        fadeSamples_ = std::max(2, static_cast<int>(std::lround(
            rate * std::clamp(fadeMs, 1, 20) / 1000.0)));
        reset();
    }

    void reset() {
        inGap_ = false;
        recoveryFrame_ = fadeSamples_;
        gapFrame_ = 0;
        envelope_ = 1.0;
        for (int c = 0; c < MAX_CHANNELS; ++c) last_[c] = base_[c] = 0.0;
    }

    bool recovering() const { return inGap_ || recoveryFrame_ < fadeSamples_; }

    // Diagnostic fade progress, not a gain for the already-faded last sample.
    double envelope() const { return envelope_; }

    /// Healthy packets remain packed; recovery blends from the last gap frame
    /// to the actual signal over one bounded window, across packet boundaries.
    void applyReal(uint8_t* data, int frames, SinkDitherState& st) {
        if (!data || frames <= 0) return;
        const int frameBytes = FrameBytes();
        if (!recovering()) {
            rememberFrame(data + static_cast<size_t>(frames - 1) * frameBytes);
            return;
        }
        if (inGap_) {
            inGap_ = false;
            recoveryFrame_ = 0;
            for (int c = 0; c < channels_; ++c) base_[c] = last_[c];
        }
        for (int f = 0; f < frames && recoveryFrame_ < fadeSamples_; ++f) {
            uint8_t* frame = data + static_cast<size_t>(f) * frameBytes;
            const double mix = static_cast<double>(recoveryFrame_) / (fadeSamples_ - 1);
            // First frame exactly continues the gap; final frame and all
            // following bytes are the real input without requantization.
            if (mix < 1.0) {
                for (int c = 0; c < channels_; ++c) {
                    uint8_t* p = frame + static_cast<size_t>(c) * bytesPerSample_;
                    Pack(base_[c] + mix * (Unpack(p) - base_[c]), p, st);
                }
            }
            ++recoveryFrame_;
            envelope_ = static_cast<double>(recoveryFrame_) / fadeSamples_;
        }
        rememberFrame(data + static_cast<size_t>(frames - 1) * frameBytes);
    }

    /// Fade the last emitted sample to exact silence. Freeze a fresh base once
    /// per gap, not per packet: multiplying it by an old envelope would apply
    /// attenuation twice when a second gap interrupts recovery.
    void fillGap(uint8_t* data, int frames, SinkDitherState& st) {
        if (!data || frames <= 0) return;
        if (!inGap_) {
            inGap_ = true;
            gapFrame_ = 0;
            recoveryFrame_ = 0;
            for (int c = 0; c < channels_; ++c) base_[c] = last_[c];
        }
        const int frameBytes = FrameBytes();
        for (int f = 0; f < frames; ++f) {
            uint8_t* frame = data + static_cast<size_t>(f) * frameBytes;
            envelope_ = 1.0 - static_cast<double>(gapFrame_) / (fadeSamples_ - 1);
            for (int c = 0; c < channels_; ++c) {
                Pack(base_[c] * envelope_,
                     frame + static_cast<size_t>(c) * bytesPerSample_, st);
            }
            if (gapFrame_ < fadeSamples_ - 1) ++gapFrame_;
        }
        rememberFrame(data + static_cast<size_t>(frames - 1) * frameBytes);
    }

    int fadeSamples() const { return fadeSamples_; }

private:
    int FrameBytes() const { return channels_ * bytesPerSample_; }

    double Unpack(const uint8_t* p) const {
        uint32_t u = static_cast<uint32_t>(p[0]) |
                     (static_cast<uint32_t>(p[1]) << 8);
        if (bytesPerSample_ >= 3) u |= static_cast<uint32_t>(p[2]) << 16;
        if (bytesPerSample_ == 4) u |= static_cast<uint32_t>(p[3]) << 24;
        const int bits = bytesPerSample_ * 8;
        // Unsigned construction avoids shifting negative integers for S24.
        const int64_t raw = (u & (uint32_t{1} << (bits - 1)))
            ? static_cast<int64_t>(u) - (int64_t{1} << bits)
            : static_cast<int64_t>(u);
        return static_cast<double>(raw) / LsbScaleForBits(bits);
    }

    void rememberFrame(const uint8_t* frame) {
        // Double retains every int32 bit: no float roundtrip on healthy audio.
        for (int c = 0; c < channels_; ++c) {
            last_[c] = Unpack(frame + static_cast<size_t>(c) * bytesPerSample_);
        }
    }

    void Pack(double sample, uint8_t* dst, SinkDitherState& st) const {
        const int bits = bytesPerSample_ * 8;
        const int64_t half = int64_t{1} << (bits - 1);
        const int64_t q = QuantizeLsbWithDither(sample * LsbScaleForBits(bits),
            -half, half - 1, st, DitherHelpsAtBits(bits));
        const uint32_t u = static_cast<uint32_t>(q);
        for (int b = 0; b < bytesPerSample_; ++b) {
            dst[b] = static_cast<uint8_t>((u >> (b * 8)) & 0xff);
        }
    }

    int channels_ = 2;
    int bytesPerSample_ = 2;
    int fadeSamples_ = 96;
    bool inGap_ = false;
    int gapFrame_ = 0;
    int recoveryFrame_ = 96;
    double envelope_ = 1.0;
    double last_[MAX_CHANNELS] = {};
    double base_[MAX_CHANNELS] = {};
};

}  // namespace pulsr
