// android/app/src/main/cpp/HarmonicSaturation.cpp
#include "HarmonicSaturation.h"
#include <cstring>

#if defined(__aarch64__) || defined(_M_ARM64)
#include <arm_neon.h>
#define PULSR_HAS_NEON 1
#elif defined(__x86_64__) || defined(_M_X64) || defined(__i386__) || defined(_M_IX86)
#include <emmintrin.h>
#include <xmmintrin.h>
#define PULSR_HAS_SSE 1
#endif

namespace {
constexpr double kMaxDrive = 5.0;
constexpr double kTiltHpHz = 1800.0;
} // namespace

// 24-tap polyphase sinc coefficients windowed with Blackman-Harris across 4 phases (6 taps per phase)
const float HarmonicSaturation::polyphase4x_[OVERSAMPLE_FACTOR][TAPS_PER_PHASE] = {
    { 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 0.0f },                       // Phase 0 (identity)
    { 0.0063f, -0.0984f, 0.8841f, 0.2642f, -0.0682f, 0.0120f },   // Phase 1 (1/4)
    { 0.0152f, -0.1386f, 0.6234f, 0.6234f, -0.1386f, 0.0152f },   // Phase 2 (2/4)
    { 0.0120f, -0.0682f, 0.2642f, 0.8841f, -0.0984f, 0.0063f }    // Phase 3 (3/4)
};

HarmonicSaturation::HarmonicSaturation() {
    setSampleRate(48000.0);
    configure(0.0, 0.5, 0.0, 0);
    reset();
}

void HarmonicSaturation::setSampleRate(double sampleRate) {
    if (sampleRate < 8000.0) sampleRate = 8000.0;
    if (sampleRate > 768000.0) sampleRate = 768000.0;
    sampleRate_ = sampleRate;
    configure(drive_, mix_, tilt_, mode_);
}

void HarmonicSaturation::configure(double drive, double mix, double tilt, int mode, bool multiband) {
    drive_ = std::clamp(drive, 0.0, 1.0);
    mix_ = std::clamp(mix, 0.0, 1.0);
    tilt_ = std::clamp(tilt, 0.0, 1.0);
    mode_ = std::clamp(mode, 0, 2);
    multiband_ = multiband;
    k_ = drive_ * kMaxDrive;

    const double fc = kTiltHpHz / (sampleRate_ * OVERSAMPLE_FACTOR);
    tiltHpCoeff_ = static_cast<float>(1.0 - std::exp(-2.0 * M_PI * fc));

    // DC blocker for the asymmetric modes. Runs at the base rate (after the
    // 4x decimation average), so its pole is derived from sampleRate_ to keep
    // a constant ~5 Hz corner instead of the previous fixed 0.9995 pole, whose
    // corner drifted from ~3.8 Hz @48k up to ~61 Hz @768k (audible bass loss).
    dcCoeff_ = static_cast<float>(std::exp(-2.0 * M_PI * 5.0 / sampleRate_));
}

void HarmonicSaturation::applyParams(const SaturationParamSet& params) {
    enabled_ = params.enabled;
    configure(params.drive, params.mix, params.tilt, params.mode, params.multiband);
}

void HarmonicSaturation::reset() {
    std::memset(hpState_, 0, sizeof(hpState_));
    std::memset(history_, 0, sizeof(history_));
    std::memset(dcX_, 0, sizeof(dcX_));
    std::memset(dcY_, 0, sizeof(dcY_));
    std::memset(decimHistory_, 0, sizeof(decimHistory_));
    decimIdx_ = 0;
}

static inline float shapeSample(float x, double k, float invNorm, int mode) {
    const float xin = static_cast<float>(k) * x;
    if (mode == 1) {
        // Tube (Triode / 6J1): biased soft clip. tanh is strictly monotonic
        // with a bounded (-1, 1) range, and the input bias makes the curve
        // asymmetric, generating even (2nd) harmonics. The resulting DC offset
        // is removed by the post de-emphasis DC blocker. (The previous
        // quadratic ratio was algebraically identical to x for any input, so
        // Tube mode produced no harmonics at all.)
        return std::tanh(xin + 0.40f) * invNorm;
    } else if (mode == 2) {
        // Analog Class-A single-ended transistor: stronger asymmetry for a
        // fatter even-harmonic ratio. Monotonic and bounded, unlike the old
        // cubic curve which folded back above |xin|~1.77 and changed sign.
        return std::tanh(xin + 0.80f) * invNorm;
    }
    // Mode 0: Tape (symmetric tanh)
    return std::tanh(xin) * invNorm;
}

void HarmonicSaturation::process(float* L, float* R, int frames) {
    if (!enabled_ || !L || !R || frames <= 0) return;

    const double k = k_;
    const float mix = static_cast<float>(mix_);
    const float tilt = static_cast<float>(tilt_);
    const float hpCoeff = tiltHpCoeff_;
    const float invNorm = (k > 1e-9) ? static_cast<float>(1.0 / k) : 1.0f;
    const int mode = mode_;
    float& hpL = hpState_[0];
    float& hpR = hpState_[1];

    for (int i = 0; i < frames; ++i) {
        float inL = L[i];
        float inR = R[i];
        if (!std::isfinite(inL)) inL = 0.0f;
        if (!std::isfinite(inR)) inR = 0.0f;

        // Shift history buffers
        for (int t = TAPS_PER_PHASE - 1; t > 0; --t) {
            history_[0][t] = history_[0][t - 1];
            history_[1][t] = history_[1][t - 1];
        }
        history_[0][0] = inL;
        history_[1][0] = inR;

        float wetL = inL;
        float wetR = inR;

        if (k > 1e-9) {
            // 4x oversampled nonlinear waveshaping with polyphase FIR decimation
            for (int p = 0; p < OVERSAMPLE_FACTOR; ++p) {
                float subL = 0.0f;
                float subR = 0.0f;
#if defined(PULSR_HAS_NEON)
                float32x2_t vSub = vdup_n_f32(0.0f);
                for (int t = 0; t < TAPS_PER_PHASE; ++t) {
                    const float coeff = polyphase4x_[p][t];
                    float32x2_t vHist = { history_[0][t], history_[1][t] };
                    vSub = vfma_n_f32(vSub, vHist, coeff);
                }
                subL = vget_lane_f32(vSub, 0);
                subR = vget_lane_f32(vSub, 1);
#elif defined(PULSR_HAS_SSE)
                __m128 vSub = _mm_setzero_ps();
                for (int t = 0; t < TAPS_PER_PHASE; ++t) {
                    const float coeff = polyphase4x_[p][t];
                    __m128 vHist = _mm_set_ps(0.0f, 0.0f, history_[1][t], history_[0][t]);
                    __m128 vC = _mm_set1_ps(coeff);
                    vSub = _mm_add_ps(vSub, _mm_mul_ps(vHist, vC));
                }
                alignas(16) float subArr[4];
                _mm_store_ps(subArr, vSub);
                subL = subArr[0];
                subR = subArr[1];
#else
                for (int t = 0; t < TAPS_PER_PHASE; ++t) {
                    const float coeff = polyphase4x_[p][t];
                    subL += history_[0][t] * coeff;
                    subR += history_[1][t] * coeff;
                }
#endif

                float emphL = subL;
                float emphR = subR;
                if (tilt > 0.0f) {
                    hpL += hpCoeff * (subL - hpL);
                    hpR += hpCoeff * (subR - hpR);
                    if (!std::isfinite(hpL)) hpL = 0.0f;
                    if (!std::isfinite(hpR)) hpR = 0.0f;
                    emphL = subL + tilt * (subL - hpL);
                    emphR = subR + tilt * (subR - hpR);
                }

                // Store shaped outputs into decimation history ring buffer
                const int dIdx = (decimIdx_ + p) % DECIM_HISTORY_LEN;
                decimHistory_[0][dIdx] = shapeSample(emphL, k, invNorm, mode);
                decimHistory_[1][dIdx] = shapeSample(emphR, k, invNorm, mode);
            }
            decimIdx_ = (decimIdx_ + OVERSAMPLE_FACTOR) % DECIM_HISTORY_LEN;

            // Polyphase FIR decimation: convolve shaped history with prototype
            // filter reconstructed from the polyphase bank.
            // h_proto[p * TAPS_PER_PHASE + t] = polyphase4x_[p][t]
            wetL = 0.0f;
            wetR = 0.0f;
#if defined(PULSR_HAS_NEON)
            float32x2_t vWet = vdup_n_f32(0.0f);
            for (int p = 0; p < OVERSAMPLE_FACTOR; ++p) {
                for (int t = 0; t < TAPS_PER_PHASE; ++t) {
                    const int k_idx = p * TAPS_PER_PHASE + t;
                    const int hIdx = (decimIdx_ - 1 - k_idx + DECIM_HISTORY_LEN * 2) % DECIM_HISTORY_LEN;
                    float32x2_t vDecim = { decimHistory_[0][hIdx], decimHistory_[1][hIdx] };
                    vWet = vfma_n_f32(vWet, vDecim, polyphase4x_[p][t]);
                }
            }
            wetL = vget_lane_f32(vWet, 0) * 0.25f;
            wetR = vget_lane_f32(vWet, 1) * 0.25f;
#elif defined(PULSR_HAS_SSE)
            __m128 vWet = _mm_setzero_ps();
            for (int p = 0; p < OVERSAMPLE_FACTOR; ++p) {
                for (int t = 0; t < TAPS_PER_PHASE; ++t) {
                    const int k_idx = p * TAPS_PER_PHASE + t;
                    const int hIdx = (decimIdx_ - 1 - k_idx + DECIM_HISTORY_LEN * 2) % DECIM_HISTORY_LEN;
                    __m128 vDecim = _mm_set_ps(0.0f, 0.0f, decimHistory_[1][hIdx], decimHistory_[0][hIdx]);
                    __m128 vC = _mm_set1_ps(polyphase4x_[p][t]);
                    vWet = _mm_add_ps(vWet, _mm_mul_ps(vDecim, vC));
                }
            }
            alignas(16) float wetArr[4];
            _mm_store_ps(wetArr, vWet);
            wetL = wetArr[0] * 0.25f;
            wetR = wetArr[1] * 0.25f;
#else
            for (int p = 0; p < OVERSAMPLE_FACTOR; ++p) {
                for (int t = 0; t < TAPS_PER_PHASE; ++t) {
                    const int k_idx = p * TAPS_PER_PHASE + t;
                    const int hIdx = (decimIdx_ - 1 - k_idx + DECIM_HISTORY_LEN * 2) % DECIM_HISTORY_LEN;
                    wetL += polyphase4x_[p][t] * decimHistory_[0][hIdx];
                    wetR += polyphase4x_[p][t] * decimHistory_[1][hIdx];
                }
            }
            wetL *= (1.0f / static_cast<float>(OVERSAMPLE_FACTOR));
            wetR *= (1.0f / static_cast<float>(OVERSAMPLE_FACTOR));
#endif

            // DC blocker for asymmetric modes
            if (mode != 0) {
                float yL = wetL - dcX_[0] + dcCoeff_ * dcY_[0];
                float yR = wetR - dcX_[1] + dcCoeff_ * dcY_[1];
                dcX_[0] = wetL;
                dcX_[1] = wetR;
                dcY_[0] = yL;
                dcY_[1] = yR;
                wetL = yL;
                wetR = yR;
            }
        }

        if (!std::isfinite(wetL)) wetL = 0.0f;
        if (!std::isfinite(wetR)) wetR = 0.0f;

        L[i] = (1.0f - mix) * inL + mix * wetL;
        R[i] = (1.0f - mix) * inR + mix * wetR;
    }
}

void HarmonicSaturation::processInterleaved(float* buffer, int frames, int channels) {
    channels = std::clamp(channels, 1, MAX_CHANNELS);
    if (!enabled_ || !buffer || frames <= 0 || channels <= 0) return;

    if (channels == 2) {
        const double k = k_;
        const float mix = static_cast<float>(mix_);
        const float tilt = static_cast<float>(tilt_);
        const float hpCoeff = tiltHpCoeff_;
        const float invNorm = (k > 1e-9) ? static_cast<float>(1.0 / k) : 1.0f;
        const int mode = mode_;
        float& hpL = hpState_[0];
        float& hpR = hpState_[1];

        for (int i = 0; i < frames; ++i) {
            float inL = buffer[i * 2];
            float inR = buffer[i * 2 + 1];
            if (!std::isfinite(inL)) inL = 0.0f;
            if (!std::isfinite(inR)) inR = 0.0f;

            // Shift history buffers
            for (int t = TAPS_PER_PHASE - 1; t > 0; --t) {
                history_[0][t] = history_[0][t - 1];
                history_[1][t] = history_[1][t - 1];
            }
            history_[0][0] = inL;
            history_[1][0] = inR;

            float wetL = inL;
            float wetR = inR;

            if (k > 1e-9) {
                // 4x oversampled nonlinear waveshaping with polyphase FIR decimation
                for (int p = 0; p < OVERSAMPLE_FACTOR; ++p) {
                    float subL = 0.0f;
                    float subR = 0.0f;
#if defined(PULSR_HAS_NEON)
                    float32x2_t vSub = vdup_n_f32(0.0f);
                    for (int t = 0; t < TAPS_PER_PHASE; ++t) {
                        const float coeff = polyphase4x_[p][t];
                        float32x2_t vHist = { history_[0][t], history_[1][t] };
                        vSub = vfma_n_f32(vSub, vHist, coeff);
                    }
                    subL = vget_lane_f32(vSub, 0);
                    subR = vget_lane_f32(vSub, 1);
#elif defined(PULSR_HAS_SSE)
                    __m128 vSub = _mm_setzero_ps();
                    for (int t = 0; t < TAPS_PER_PHASE; ++t) {
                        const float coeff = polyphase4x_[p][t];
                        __m128 vHist = _mm_set_ps(0.0f, 0.0f, history_[1][t], history_[0][t]);
                        __m128 vC = _mm_set1_ps(coeff);
                        vSub = _mm_add_ps(vSub, _mm_mul_ps(vHist, vC));
                    }
                    alignas(16) float subArr[4];
                    _mm_store_ps(subArr, vSub);
                    subL = subArr[0];
                    subR = subArr[1];
#else
                    for (int t = 0; t < TAPS_PER_PHASE; ++t) {
                        const float coeff = polyphase4x_[p][t];
                        subL += history_[0][t] * coeff;
                        subR += history_[1][t] * coeff;
                    }
#endif

                    float emphL = subL;
                    float emphR = subR;
                    if (tilt > 0.0f) {
                        hpL += hpCoeff * (subL - hpL);
                        hpR += hpCoeff * (subR - hpR);
                        if (!std::isfinite(hpL)) hpL = 0.0f;
                        if (!std::isfinite(hpR)) hpR = 0.0f;
                        emphL = subL + tilt * (subL - hpL);
                        emphR = subR + tilt * (subR - hpR);
                    }

                    // Store shaped outputs into decimation history ring buffer
                    const int dIdx = (decimIdx_ + p) % DECIM_HISTORY_LEN;
                    decimHistory_[0][dIdx] = shapeSample(emphL, k, invNorm, mode);
                    decimHistory_[1][dIdx] = shapeSample(emphR, k, invNorm, mode);
                }
                decimIdx_ = (decimIdx_ + OVERSAMPLE_FACTOR) % DECIM_HISTORY_LEN;

                wetL = 0.0f;
                wetR = 0.0f;
#if defined(PULSR_HAS_NEON)
                float32x2_t vWet = vdup_n_f32(0.0f);
                for (int p = 0; p < OVERSAMPLE_FACTOR; ++p) {
                    for (int t = 0; t < TAPS_PER_PHASE; ++t) {
                        const int k_idx = p * TAPS_PER_PHASE + t;
                        const int hIdx = (decimIdx_ - 1 - k_idx + DECIM_HISTORY_LEN * 2) % DECIM_HISTORY_LEN;
                        const float coeff = polyphase4x_[p][t];
                        float32x2_t vDecim = { decimHistory_[0][hIdx], decimHistory_[1][hIdx] };
                        vWet = vfma_n_f32(vWet, vDecim, coeff);
                    }
                }
                wetL = vget_lane_f32(vWet, 0) * (1.0f / static_cast<float>(OVERSAMPLE_FACTOR));
                wetR = vget_lane_f32(vWet, 1) * (1.0f / static_cast<float>(OVERSAMPLE_FACTOR));
#elif defined(PULSR_HAS_SSE)
                __m128 vWet = _mm_setzero_ps();
                for (int p = 0; p < OVERSAMPLE_FACTOR; ++p) {
                    for (int t = 0; t < TAPS_PER_PHASE; ++t) {
                        const int k_idx = p * TAPS_PER_PHASE + t;
                        const int hIdx = (decimIdx_ - 1 - k_idx + DECIM_HISTORY_LEN * 2) % DECIM_HISTORY_LEN;
                        const float coeff = polyphase4x_[p][t];
                        __m128 vDecim = _mm_set_ps(0.0f, 0.0f, decimHistory_[1][hIdx], decimHistory_[0][hIdx]);
                        __m128 vC = _mm_set1_ps(coeff);
                        vWet = _mm_add_ps(vWet, _mm_mul_ps(vDecim, vC));
                    }
                }
                alignas(16) float wetArr[4];
                _mm_store_ps(wetArr, vWet);
                wetL = wetArr[0] * (1.0f / static_cast<float>(OVERSAMPLE_FACTOR));
                wetR = wetArr[1] * (1.0f / static_cast<float>(OVERSAMPLE_FACTOR));
#else
                for (int p = 0; p < OVERSAMPLE_FACTOR; ++p) {
                    for (int t = 0; t < TAPS_PER_PHASE; ++t) {
                        const int k_idx = p * TAPS_PER_PHASE + t;
                        const int hIdx = (decimIdx_ - 1 - k_idx + DECIM_HISTORY_LEN * 2) % DECIM_HISTORY_LEN;
                        wetL += polyphase4x_[p][t] * decimHistory_[0][hIdx];
                        wetR += polyphase4x_[p][t] * decimHistory_[1][hIdx];
                    }
                }
                wetL *= (1.0f / static_cast<float>(OVERSAMPLE_FACTOR));
                wetR *= (1.0f / static_cast<float>(OVERSAMPLE_FACTOR));
#endif

                // DC blocker for asymmetric modes
                if (mode != 0) {
                    float yL = wetL - dcX_[0] + dcCoeff_ * dcY_[0];
                    float yR = wetR - dcX_[1] + dcCoeff_ * dcY_[1];
                    dcX_[0] = wetL;
                    dcX_[1] = wetR;
                    dcY_[0] = yL;
                    dcY_[1] = yR;
                    wetL = yL;
                    wetR = yR;
                }
            }

            if (!std::isfinite(wetL)) wetL = 0.0f;
            if (!std::isfinite(wetR)) wetR = 0.0f;

            buffer[i * 2] = (1.0f - mix) * inL + mix * wetL;
            buffer[i * 2 + 1] = (1.0f - mix) * inR + mix * wetR;
        }
        return;
    }

    const double k = k_;
    const float mix = static_cast<float>(mix_);
    const float tilt = static_cast<float>(tilt_);
    const float hpCoeff = tiltHpCoeff_;
    const float invNorm = (k > 1e-9) ? static_cast<float>(1.0 / k) : 1.0f;
    const int mode = mode_;

    for (int i = 0; i < frames; ++i) {
        for (int ch = 0; ch < channels; ++ch) {
            const int idx = i * channels + ch;
            float inSample = buffer[idx];
            if (!std::isfinite(inSample)) inSample = 0.0f;

            for (int t = TAPS_PER_PHASE - 1; t > 0; --t) {
                history_[ch][t] = history_[ch][t - 1];
            }
            history_[ch][0] = inSample;

            float wet = inSample;

            if (k > 1e-9) {
                // 4x oversampled nonlinear waveshaping with polyphase FIR decimation
                for (int p = 0; p < OVERSAMPLE_FACTOR; ++p) {
                    float sub = 0.0f;
                    for (int t = 0; t < TAPS_PER_PHASE; ++t) {
                        sub += history_[ch][t] * polyphase4x_[p][t];
                    }

                    float emph = sub;
                    if (tilt > 0.0f) {
                        float& hp = hpState_[ch];
                        hp += hpCoeff * (sub - hp);
                        if (!std::isfinite(hp)) hp = 0.0f;
                        emph = sub + tilt * (sub - hp);
                    }

                    // Store shaped output into decimation history ring buffer
                    const int dIdx = (decimIdx_ + p) % DECIM_HISTORY_LEN;
                    decimHistory_[ch][dIdx] = shapeSample(emph, k, invNorm, mode);
                }
                // Only advance decimIdx_ once per frame (after all channels processed)
                if (ch == channels - 1) {
                    decimIdx_ = (decimIdx_ + OVERSAMPLE_FACTOR) % DECIM_HISTORY_LEN;
                }

                // Polyphase FIR decimation
                wet = 0.0f;
                for (int p = 0; p < OVERSAMPLE_FACTOR; ++p) {
                    for (int t = 0; t < TAPS_PER_PHASE; ++t) {
                        const int k_idx = p * TAPS_PER_PHASE + t;
                        const int curDecimIdx = (ch == channels - 1)
                            ? decimIdx_
                            : (decimIdx_ + OVERSAMPLE_FACTOR) % DECIM_HISTORY_LEN;
                        const int hIdx = (curDecimIdx - 1 - k_idx + DECIM_HISTORY_LEN * 2) % DECIM_HISTORY_LEN;
                        wet += polyphase4x_[p][t] * decimHistory_[ch][hIdx];
                    }
                }
                wet *= (1.0f / static_cast<float>(OVERSAMPLE_FACTOR));

                if (mode != 0) {
                    float y = wet - dcX_[ch] + dcCoeff_ * dcY_[ch];
                    dcX_[ch] = wet;
                    dcY_[ch] = y;
                    wet = y;
                }
            }

            if (!std::isfinite(wet)) wet = 0.0f;

            buffer[idx] = (1.0f - mix) * inSample + mix * wet;
        }
    }
}
