#include "SincResampler.h"
#include <cmath>
#include <cstring>
#include <cstdio>
#include <algorithm>
#if defined(__ANDROID__)
#include <android/log.h>
#endif
#if defined(__ARM_NEON)
#include <arm_neon.h>
#endif

SincResampler::SincResampler() {
    tempOutBuf_.assign(8192 * MAX_CHANNELS, 0.0f);
    setRates(48000.0, 48000.0);
    setEnabled(false);
    reset();
}

float SincResampler::sinc(float x) {
    if (std::abs(x) < 1e-7f) return 1.0f;
    const float px = static_cast<float>(M_PI) * x;
    return std::sin(px) / px;
}

float SincResampler::blackmanHarris(float x, float halfWidth) {
    if (std::abs(x) >= halfWidth) return 0.0f;
    // Normalized to [0, 1]
    const float n = (x + halfWidth) / (2.0f * halfWidth);
    const float a0 = 0.35875f;
    const float a1 = 0.48829f;
    const float a2 = 0.14128f;
    const float a3 = 0.01168f;
    const float twoPiN = 2.0f * static_cast<float>(M_PI) * n;

    return a0 - a1 * std::cos(twoPiN) + a2 * std::cos(2.0f * twoPiN) - a3 * std::cos(3.0f * twoPiN);
}

void SincResampler::generatePolyphaseTable() {
    const float cutoff = 0.45f * static_cast<float>(std::min(1.0, outRate_ / inRate_));
    const float halfWidth = static_cast<float>(TAPS_PER_PHASE) / 2.0f;

    for (int phaseIdx = 0; phaseIdx < NUM_PHASES; ++phaseIdx) {
        const float phaseFraction = static_cast<float>(phaseIdx) / static_cast<float>(NUM_PHASES);
        float sum = 0.0f;

        for (int tap = 0; tap < TAPS_PER_PHASE; ++tap) {
            const float t = static_cast<float>(tap - HALF_TAPS) - phaseFraction;
            const float sincVal = 2.0f * cutoff * sinc(2.0f * cutoff * t);
            const float winVal = blackmanHarris(t, halfWidth);
            const float coeff = sincVal * winVal;

            polyphaseTable_[phaseIdx][tap] = coeff;
            sum += coeff;
        }

        // Normalize DC gain to 1.0 across all phases
        if (std::abs(sum) > 1e-6f) {
            const float invSum = 1.0f / sum;
            for (int tap = 0; tap < TAPS_PER_PHASE; ++tap) {
                polyphaseTable_[phaseIdx][tap] *= invSum;
            }
        }
    }
}

void SincResampler::setRates(double inRate, double outRate) {
    if (inRate <= 0.0 || outRate <= 0.0) return;
    if (std::abs(inRate_ - inRate) < 0.1 && std::abs(outRate_ - outRate) < 0.1) return;

    inRate_ = inRate;
    outRate_ = outRate;
    ratio_ = inRate_ / outRate_;
    generatePolyphaseTable();
    reset();
}

void SincResampler::setEnabled(bool enabled) {
    enabled_ = enabled;
}

void SincResampler::setQuality(int quality) {
    const int q = std::clamp(quality, 0, 3);
    if (q == quality_) return;
    quality_ = q;
    linearQuality_ = q == 0;
    activeHalfTaps_ = q == 0 ? 0 : (q == 1 ? 8 : (q == 2 ? 16 : TAPS_PER_PHASE / 2));
    reset();
}

void SincResampler::applyParams(const ResamplerParamSet& params) {
    setQuality(params.quality);
    enabled_ = params.enabled;
    setRates(params.inRate, params.outRate);
}

void SincResampler::reset() {
    phase_ = 0.0;
    writePos_ = 0;
    availableFrames_ = 0;
    // No ring memset: availableFrames_ == 0 means nothing is readable until new
    // input is written, and this runs on the audio thread (256 KB memset was a
    // measurable callback-time spike on parameter changes).
}

int SincResampler::processInterleaved(float* buffer, int frames, int channels) {
    (void)channels;
    if (!enabled_ || frames <= 0) return frames;

    // The engine passes a fixed block and reuses the same buffer downstream, so
    // the frame count must not change. A causal sample-rate converter cannot
    // satisfy that (downsampling needs more input frames than it emits, and
    // upsampling emits more than it consumes): forcing it either reads
    // future/stale ring samples (gross distortion) or grows/skips the FIFO
    // (periodic dropouts). Pass the audio through untouched and let the
    // platform AudioTrack perform the rate conversion. Ratio-correct conversion
    // is available via processPlanar() (used by the convolution reverb), which
    // is allowed to vary the output frame count.
    return frames;
}

int SincResampler::processPlanar(const float* const* in, float* const* out, int inFrames, int channels, int maxOutFrames) {
    if (!enabled_ || inFrames <= 0 || std::abs(ratio_ - 1.0) < 1e-5) {
        int count = std::min(inFrames, maxOutFrames);
        if (in != out) {
            for (int ch = 0; ch < channels; ++ch) {
                std::memcpy(out[ch], in[ch], count * sizeof(float));
            }
        }
        return count;
    }

    channels = std::clamp(channels, 1, MAX_CHANNELS);

    for (int f = 0; f < inFrames; ++f) {
        for (int ch = 0; ch < channels; ++ch) {
            ringBuf_[ch][writePos_] = in[ch][f];
        }
        writePos_ = (writePos_ + 1) % FIFO_CAPACITY;
    }
    availableFrames_ += inFrames;

    int outFrames = 0;
    while (phase_ < static_cast<double>(availableFrames_ - HALF_TAPS) && outFrames < maxOutFrames) {
        const double samplePos = phase_;
        const int baseInt = static_cast<int>(std::floor(samplePos));
        const double frac = samplePos - static_cast<double>(baseInt);

        const int phaseIdx = std::clamp(
            static_cast<int>(frac * NUM_PHASES),
            0,
            NUM_PHASES - 1
        );

        const float* coeffs = polyphaseTable_[phaseIdx];

        for (int ch = 0; ch < channels; ++ch) {
            if (linearQuality_) {
                // Fast mode: first-order linear interpolation between the two
                // frames surrounding the fractional read position.
                const int off0 = availableFrames_ - baseInt;
                int i0 = (writePos_ - off0) % FIFO_CAPACITY;
                if (i0 < 0) i0 += FIFO_CAPACITY;
                int i1 = (writePos_ - off0 + 1) % FIFO_CAPACITY;
                if (i1 < 0) i1 += FIFO_CAPACITY;
                const float fracF = static_cast<float>(frac);
                out[ch][outFrames] =
                    ringBuf_[ch][i0] * (1.0f - fracF) + ringBuf_[ch][i1] * fracF;
                continue;
            }
            float sum = 0.0f;
            for (int tap = HALF_TAPS - activeHalfTaps_; tap < HALF_TAPS + activeHalfTaps_; ++tap) {
                const int readOffset = availableFrames_ - baseInt + (HALF_TAPS - tap);
                int ringIndex = (writePos_ - readOffset) % FIFO_CAPACITY;
                if (ringIndex < 0) ringIndex += FIFO_CAPACITY;

                sum += ringBuf_[ch][ringIndex] * coeffs[tap];
            }
            out[ch][outFrames] = sum;
        }

        outFrames++;
        phase_ += ratio_;
    }

    const int consumedInt = static_cast<int>(std::floor(phase_));
    if (consumedInt > 0) {
        phase_ -= static_cast<double>(consumedInt);
        availableFrames_ = std::max(0, availableFrames_ - consumedInt);
    }

    if (availableFrames_ > FIFO_CAPACITY - 256) {
#if defined(__ANDROID__)
        __android_log_print(ANDROID_LOG_WARN, "PulsrDSP",
            "SincResampler: FIFO buffer overflow (%d > %d), dropping oldest frames",
            availableFrames_, FIFO_CAPACITY - 256);
#else
        fprintf(stderr, "SincResampler: FIFO buffer overflow (%d > %d), dropping oldest frames\n",
            availableFrames_, FIFO_CAPACITY - 256);
#endif
        availableFrames_ = FIFO_CAPACITY - 256;
    }

    return outFrames;
}
