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

void SincResampler::applyParams(const ResamplerParamSet& params) {
    enabled_ = params.enabled;
    setRates(params.inRate, params.outRate);
}

void SincResampler::reset() {
    phase_ = 0.0;
    writePos_ = 0;
    availableFrames_ = 0;
    std::memset(ringBuf_, 0, sizeof(ringBuf_));
}

int SincResampler::processInterleaved(float* buffer, int frames, int channels) {
    if (!enabled_ || frames <= 0 || std::abs(ratio_ - 1.0) < 1e-5) {
        return frames;
    }

    channels = std::clamp(channels, 1, MAX_CHANNELS);

    const int neededOutputSamples = frames * channels;
    if (static_cast<int>(tempOutBuf_.size()) < neededOutputSamples) {
        tempOutBuf_.resize(neededOutputSamples);
    }

    // Push input frames into ring buffer
    for (int f = 0; f < frames; ++f) {
        for (int ch = 0; ch < channels; ++ch) {
            ringBuf_[ch][writePos_] = buffer[f * channels + ch];
        }
        writePos_ = (writePos_ + 1) % FIFO_CAPACITY;
    }
    availableFrames_ += frames;

    // Sinc interpolation for each of the `frames` output points
    for (int outF = 0; outF < frames; ++outF) {
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
#if defined(__ARM_NEON)
            float32x4_t sumVec = vdupq_n_f32(0.0f);
            for (int tap = 0; tap < TAPS_PER_PHASE; tap += 4) {
                const int readOffset0 = availableFrames_ - baseInt + (tap - HALF_TAPS);
                int ringIndex0 = (writePos_ - readOffset0) % FIFO_CAPACITY;
                if (ringIndex0 < 0) ringIndex0 += FIFO_CAPACITY;

                const int readOffset1 = availableFrames_ - baseInt + (tap + 1 - HALF_TAPS);
                int ringIndex1 = (writePos_ - readOffset1) % FIFO_CAPACITY;
                if (ringIndex1 < 0) ringIndex1 += FIFO_CAPACITY;

                const int readOffset2 = availableFrames_ - baseInt + (tap + 2 - HALF_TAPS);
                int ringIndex2 = (writePos_ - readOffset2) % FIFO_CAPACITY;
                if (ringIndex2 < 0) ringIndex2 += FIFO_CAPACITY;

                const int readOffset3 = availableFrames_ - baseInt + (tap + 3 - HALF_TAPS);
                int ringIndex3 = (writePos_ - readOffset3) % FIFO_CAPACITY;
                if (ringIndex3 < 0) ringIndex3 += FIFO_CAPACITY;

                const float s[4] = {
                    ringBuf_[ch][ringIndex0],
                    ringBuf_[ch][ringIndex1],
                    ringBuf_[ch][ringIndex2],
                    ringBuf_[ch][ringIndex3]
                };

                float32x4_t sampVec = vld1q_f32(s);
                float32x4_t coeffVec = vld1q_f32(&coeffs[tap]);
                sumVec = vmlaq_f32(sumVec, sampVec, coeffVec);
            }
#if defined(__aarch64__)
            const float sum = vaddvq_f32(sumVec);
#else
            float32x2_t sumPair = vadd_f32(vget_low_f32(sumVec), vget_high_f32(sumVec));
            const float sum = vget_lane_f32(vpadd_f32(sumPair, sumPair), 0);
#endif
#else
            float sum = 0.0f;
            for (int tap = 0; tap < TAPS_PER_PHASE; ++tap) {
                // Sinc history lookup relative to current write position & phase
                const int readOffset = availableFrames_ - baseInt + (tap - HALF_TAPS);
                int ringIndex = (writePos_ - readOffset) % FIFO_CAPACITY;
                if (ringIndex < 0) ringIndex += FIFO_CAPACITY;

                sum += ringBuf_[ch][ringIndex] * coeffs[tap];
            }
#endif
            tempOutBuf_[outF * channels + ch] = sum;
        }

        phase_ += ratio_;
    }

    // Wrap / prune phase and ring buffer
    const int consumedInt = static_cast<int>(std::floor(phase_));
    if (consumedInt > 0) {
        phase_ -= static_cast<double>(consumedInt);
        availableFrames_ = std::max(0, availableFrames_ - consumedInt);
    }

    // Prevent availableFrames_ growth past capacity
    if (availableFrames_ > FIFO_CAPACITY - 256) {
        int currentOverflow = ++overflowCount_;
        if (currentOverflow % 100 == 1) {
#if defined(__ANDROID__)
            __android_log_print(ANDROID_LOG_WARN, "PulsrDSP",
                "SincResampler: FIFO buffer overflow (%d > %d), dropping oldest frames (total: %d)",
                availableFrames_, FIFO_CAPACITY - 256, currentOverflow);
#else
            fprintf(stderr, "SincResampler: FIFO buffer overflow (%d > %d), dropping oldest frames (total: %d)\n",
                availableFrames_, FIFO_CAPACITY - 256, currentOverflow);
#endif
        }
        availableFrames_ = FIFO_CAPACITY - 256;
    }

    // Copy interpolated frames back to output
    std::memcpy(buffer, tempOutBuf_.data(), neededOutputSamples * sizeof(float));
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
            float sum = 0.0f;
            for (int tap = 0; tap < TAPS_PER_PHASE; ++tap) {
                const int readOffset = availableFrames_ - baseInt + (tap - HALF_TAPS);
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
        int currentOverflow = ++overflowCount_;
        if (currentOverflow % 100 == 1) {
#if defined(__ANDROID__)
            __android_log_print(ANDROID_LOG_WARN, "PulsrDSP",
                "SincResampler: FIFO buffer overflow (%d > %d), dropping oldest frames (total: %d)",
                availableFrames_, FIFO_CAPACITY - 256, currentOverflow);
#else
            fprintf(stderr, "SincResampler: FIFO buffer overflow (%d > %d), dropping oldest frames (total: %d)\n",
                availableFrames_, FIFO_CAPACITY - 256, currentOverflow);
#endif
        }
        availableFrames_ = FIFO_CAPACITY - 256;
    }

    return outFrames;
}
