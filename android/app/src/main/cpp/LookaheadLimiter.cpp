// android/app/src/main/cpp/LookaheadLimiter.cpp
#include "LookaheadLimiter.h"
#include <cstring>
#include <cmath>

// 24-tap polyphase sinc coefficients windowed with Blackman-Harris across 4 phases (6 taps per phase)
const float LookaheadLimiter::polyphase4x_[INTERP_PHASES][TAPS_PER_PHASE] = {
    { 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 0.0f }, // Phase 0 (identity)
    { 0.0063f, -0.0984f, 0.8841f, 0.2642f, -0.0682f, 0.0120f }, // Phase 1 (1/4)
    { 0.0152f, -0.1386f, 0.6234f, 0.6234f, -0.1386f, 0.0152f }, // Phase 2 (2/4)
    { 0.0120f, -0.0682f, 0.2642f, 0.8841f, -0.0984f, 0.0063f }  // Phase 3 (3/4)
};

const float LookaheadLimiter::polyphase8x_[8][TAPS_PER_PHASE] = {
    { 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 0.0f },
    { 0.0031f, -0.0520f, 0.9620f, 0.1250f, -0.0420f, 0.0039f },
    { 0.0063f, -0.0984f, 0.8841f, 0.2642f, -0.0682f, 0.0120f },
    { 0.0105f, -0.1280f, 0.7680f, 0.4350f, -0.1050f, 0.0195f },
    { 0.0152f, -0.1386f, 0.6234f, 0.6234f, -0.1386f, 0.0152f },
    { 0.0195f, -0.1050f, 0.4350f, 0.7680f, -0.1280f, 0.0105f },
    { 0.0120f, -0.0682f, 0.2642f, 0.8841f, -0.0984f, 0.0063f },
    { 0.0039f, -0.0420f, 0.1250f, 0.9620f, -0.0520f, 0.0031f }
};

LookaheadLimiter::LookaheadLimiter() {
    configure(5.0, -0.2, 50.0, true);
    reset();
}

void LookaheadLimiter::setSampleRate(double sampleRate) {
    if (sampleRate <= 0.0 || std::abs(sampleRate_ - sampleRate) < 1.0) return;
    sampleRate_ = sampleRate;
    configure(lookaheadMs_, thresholdDb_, releaseMs_, truePeakMode_);
    reset();
}

void LookaheadLimiter::configure(double lookaheadMs, double thresholdDb, double releaseMs, bool truePeakMode) {
    lookaheadMs_ = std::clamp(lookaheadMs, 0.5, 20.0);
    thresholdDb_ = std::clamp(thresholdDb, -24.0, 0.0);
    releaseMs_ = std::clamp(releaseMs, 5.0, 1000.0);
    truePeakMode_ = truePeakMode;

    lookaheadSamples_ = std::clamp(
        static_cast<int>(lookaheadMs_ * 0.001 * sampleRate_),
        TAPS_PER_PHASE + 1,
        MAX_LOOKAHEAD_SAMPLES - 1
    );

    threshold_ = static_cast<float>(std::pow(10.0, thresholdDb_ / 20.0));
    releaseCoeff_ = static_cast<float>(std::exp(-1.0 / (releaseMs_ * 0.001 * sampleRate_)));
}

void LookaheadLimiter::setEnabled(bool enabled) {
    enabled_ = enabled;
}

void LookaheadLimiter::applyParams(const LimiterParamSet& params) {
    enabled_ = params.enabled;
    configure(params.lookaheadMs, params.thresholdDb, params.releaseMs, params.truePeakMode);
}

void LookaheadLimiter::reset() {
    std::memset(delayBuf_, 0, sizeof(delayBuf_));
    std::fill(std::begin(gainBuf_), std::end(gainBuf_), 1.0f);
    writeIdx_ = 0;
    envelope_ = 1.0f;
    minGain_ = 1.0f;
    minGainAge_ = 0;
}

float LookaheadLimiter::estimateTruePeak(const float* history) {
    float peak = std::abs(history[2]); // Central sample in 6-tap window

    if (!truePeakMode_) {
        return peak;
    }

    if (sampleRate_ > 192000.0) {
        // > 192kHz: 1x oversampling (Nyquist is >= 96kHz, intersample peaks negligible)
        return peak;
    } else if (sampleRate_ > 96000.0) {
        // > 96kHz: 8-phase polyphase true peak estimation
        for (int phase = 1; phase < 8; ++phase) {
            float subSample = 0.0f;
            for (int tap = 0; tap < TAPS_PER_PHASE; ++tap) {
                subSample += history[tap] * polyphase8x_[phase][tap];
            }
            peak = std::max(peak, std::abs(subSample));
        }
    } else {
        // <= 96kHz: 4x oversampling (evaluate phases 1, 2, 3)
        for (int phase = 1; phase < INTERP_PHASES; ++phase) {
            float subSample = 0.0f;
            for (int tap = 0; tap < TAPS_PER_PHASE; ++tap) {
                subSample += history[tap] * polyphase4x_[phase][tap];
            }
            peak = std::max(peak, std::abs(subSample));
        }
    }

    return peak;
}

void LookaheadLimiter::process(float* L, float* R, int frames) {
    if (!enabled_ || frames <= 0) return;

    constexpr int kMask = MAX_LOOKAHEAD_SAMPLES - 1;
    float historyWindowL[TAPS_PER_PHASE] = {};
    float historyWindowR[TAPS_PER_PHASE] = {};

    for (int i = 0; i < frames; ++i) {
        const float inL = L[i];
        const float inR = R[i];

        delayBuf_[0][writeIdx_] = std::isfinite(inL) ? inL : 0.0f;
        delayBuf_[1][writeIdx_] = std::isfinite(inR) ? inR : 0.0f;

        // Gather 6-tap history for true-peak interpolation
        for (int tap = 0; tap < TAPS_PER_PHASE; ++tap) {
            int histIdx = (writeIdx_ - (TAPS_PER_PHASE - 1 - tap)) & kMask;
            historyWindowL[tap] = delayBuf_[0][histIdx];
            historyWindowR[tap] = delayBuf_[1][histIdx];
        }

        const float peakL = estimateTruePeak(historyWindowL);
        const float peakR = estimateTruePeak(historyWindowR);
        const float maxPeak = std::max(peakL, peakR);

        // Calculate required instantaneous gain factor for incoming peak
        float requiredGain = 1.0f;
        if (maxPeak > threshold_ && maxPeak > 1e-6f) {
            requiredGain = threshold_ / maxPeak;
        }

        gainBuf_[writeIdx_] = requiredGain;

        minGainAge_++;
        if (requiredGain <= minGain_) {
            minGain_ = requiredGain;
            minGainAge_ = 0;
        } else if (minGainAge_ >= lookaheadSamples_) {
            minGain_ = requiredGain;
            minGainAge_ = 0;
            const int lookaheadN = std::min(lookaheadSamples_, MAX_LOOKAHEAD_SAMPLES - 1);
            for (int k = 1; k <= lookaheadN; ++k) {
                int prevIdx = (writeIdx_ - k) & kMask;
                if (gainBuf_[prevIdx] <= minGain_) {
                    minGain_ = gainBuf_[prevIdx];
                    minGainAge_ = k;
                }
            }
        }

        float targetGain = minGain_;

        // Instantaneous attack to target minimum gain, smooth exponential release when lookahead window clears
        if (targetGain < envelope_) {
            envelope_ = targetGain;
        } else {
            envelope_ = releaseCoeff_ * envelope_ + (1.0f - releaseCoeff_) * targetGain;
            if (envelope_ > 0.99999f) {
                envelope_ = 1.0f;
            }
        }
        if (!std::isfinite(envelope_) || envelope_ <= 0.0f) envelope_ = 1.0f;

        // Read delayed audio from lookahead buffer
        int readIdx = (writeIdx_ - lookaheadSamples_) & kMask;
        if (envelope_ == 1.0f) {
            L[i] = delayBuf_[0][readIdx];
            R[i] = delayBuf_[1][readIdx];
        } else {
            L[i] = delayBuf_[0][readIdx] * envelope_;
            R[i] = delayBuf_[1][readIdx] * envelope_;
        }

        writeIdx_ = (writeIdx_ + 1) & kMask;
    }
}

void LookaheadLimiter::processMono(float* inOut, int frames) {
    if (!enabled_ || frames <= 0) return;

    constexpr int kMask = MAX_LOOKAHEAD_SAMPLES - 1;
    float historyWindow[TAPS_PER_PHASE] = {};

    for (int i = 0; i < frames; ++i) {
        const float inSample = inOut[i];
        delayBuf_[0][writeIdx_] = std::isfinite(inSample) ? inSample : 0.0f;

        for (int tap = 0; tap < TAPS_PER_PHASE; ++tap) {
            int histIdx = (writeIdx_ - (TAPS_PER_PHASE - 1 - tap)) & kMask;
            historyWindow[tap] = delayBuf_[0][histIdx];
        }

        const float peak = estimateTruePeak(historyWindow);

        float requiredGain = 1.0f;
        if (peak > threshold_ && peak > 1e-6f) {
            requiredGain = threshold_ / peak;
        }

        gainBuf_[writeIdx_] = requiredGain;

        minGainAge_++;
        if (requiredGain <= minGain_) {
            minGain_ = requiredGain;
            minGainAge_ = 0;
        } else if (minGainAge_ >= lookaheadSamples_) {
            minGain_ = requiredGain;
            minGainAge_ = 0;
            const int lookaheadN = std::min(lookaheadSamples_, MAX_LOOKAHEAD_SAMPLES - 1);
            for (int k = 1; k <= lookaheadN; ++k) {
                int prevIdx = (writeIdx_ - k) & kMask;
                if (gainBuf_[prevIdx] <= minGain_) {
                    minGain_ = gainBuf_[prevIdx];
                    minGainAge_ = k;
                }
            }
        }

        float targetGain = minGain_;

        if (targetGain < envelope_) {
            envelope_ = targetGain;
        } else {
            envelope_ = releaseCoeff_ * envelope_ + (1.0f - releaseCoeff_) * targetGain;
            if (envelope_ > 0.99999f) {
                envelope_ = 1.0f;
            }
        }
        if (!std::isfinite(envelope_) || envelope_ <= 0.0f) envelope_ = 1.0f;

        int readIdx = (writeIdx_ - lookaheadSamples_) & kMask;
        if (envelope_ == 1.0f) {
            inOut[i] = delayBuf_[0][readIdx];
        } else {
            inOut[i] = delayBuf_[0][readIdx] * envelope_;
        }

        writeIdx_ = (writeIdx_ + 1) & kMask;
    }
}

void LookaheadLimiter::processInterleaved(float* buffer, int frames, int channels) {
    if (!enabled_ || frames <= 0) return;
    channels = std::clamp(channels, 1, MAX_CHANNELS);

    constexpr int kMask = MAX_LOOKAHEAD_SAMPLES - 1;
    float historyWindow[TAPS_PER_PHASE] = {};

    for (int i = 0; i < frames; ++i) {
        float frameMaxPeak = 0.0f;

        for (int ch = 0; ch < channels; ++ch) {
            const float inSample = buffer[i * channels + ch];
            delayBuf_[ch][writeIdx_] = std::isfinite(inSample) ? inSample : 0.0f;

            for (int tap = 0; tap < TAPS_PER_PHASE; ++tap) {
                int histIdx = (writeIdx_ - (TAPS_PER_PHASE - 1 - tap)) & kMask;
                historyWindow[tap] = delayBuf_[ch][histIdx];
            }

            const float chPeak = estimateTruePeak(historyWindow);
            frameMaxPeak = std::max(frameMaxPeak, chPeak);
        }

        float requiredGain = 1.0f;
        if (frameMaxPeak > threshold_ && frameMaxPeak > 1e-6f) {
            requiredGain = threshold_ / frameMaxPeak;
        }

        gainBuf_[writeIdx_] = requiredGain;

        minGainAge_++;
        if (requiredGain <= minGain_) {
            minGain_ = requiredGain;
            minGainAge_ = 0;
        } else if (minGainAge_ >= lookaheadSamples_) {
            minGain_ = requiredGain;
            minGainAge_ = 0;
            const int lookaheadN = std::min(lookaheadSamples_, MAX_LOOKAHEAD_SAMPLES - 1);
            for (int k = 1; k <= lookaheadN; ++k) {
                int prevIdx = (writeIdx_ - k) & kMask;
                if (gainBuf_[prevIdx] <= minGain_) {
                    minGain_ = gainBuf_[prevIdx];
                    minGainAge_ = k;
                }
            }
        }

        float targetGain = minGain_;

        if (targetGain < envelope_) {
            envelope_ = targetGain;
        } else {
            envelope_ = releaseCoeff_ * envelope_ + (1.0f - releaseCoeff_) * targetGain;
            if (envelope_ > 0.99999f) {
                envelope_ = 1.0f;
            }
        }
        if (!std::isfinite(envelope_) || envelope_ <= 0.0f) envelope_ = 1.0f;

        int readIdx = (writeIdx_ - lookaheadSamples_) & kMask;
        if (envelope_ == 1.0f) {
            for (int ch = 0; ch < channels; ++ch) {
                buffer[i * channels + ch] = delayBuf_[ch][readIdx];
            }
        } else {
            for (int ch = 0; ch < channels; ++ch) {
                buffer[i * channels + ch] = delayBuf_[ch][readIdx] * envelope_;
            }
        }

        writeIdx_ = (writeIdx_ + 1) & kMask;
    }
}

