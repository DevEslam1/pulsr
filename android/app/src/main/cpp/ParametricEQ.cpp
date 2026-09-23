// android/app/src/main/cpp/ParametricEQ.cpp
#include "ParametricEQ.h"
#include <cstring>
#include <cmath>

#if defined(__aarch64__) || defined(_M_ARM64)
#include <arm_neon.h>
#define PULSR_HAS_NEON 1
#elif defined(__x86_64__) || defined(_M_X64)
#include <emmintrin.h>
#define PULSR_HAS_SSE2 1
#endif

static const double kDefaultFrequencies[10] = {
    31.0, 62.0, 125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0, 16000.0
};

static const double kDefaultQ[10] = {
    1.414, 1.414, 1.414, 1.414, 1.414, 1.414, 1.414, 1.414, 1.414, 1.414
};

ParametricEQ::ParametricEQ() {
    for (int i = 0; i < 10; ++i) {
        bands_[i].frequency = kDefaultFrequencies[i];
        bands_[i].q = kDefaultQ[i];
        bands_[i].targetGainDb = 0.0;
        bands_[i].smoothedGainDb = 0.0;
        bands_[i].type = (i == 0) ? FilterType::LowShelf : (i == 9 ? FilterType::HighShelf : FilterType::Peaking);
        bands_[i].enabled = true;
        bands_[i].solo = false;
        bands_[i].mute = false;
        computeCoeffs(bands_[i], 0.0);
    }
    reset();
}

void ParametricEQ::setSampleRate(double sampleRate) {
    if (sampleRate <= 0.0 || std::abs(sampleRate_ - sampleRate) < 1.0) return;
    sampleRate_ = sampleRate;
    for (int i = 0; i < bandCount_; ++i) {
        computeCoeffs(bands_[i], bands_[i].smoothedGainDb);
    }
}

void ParametricEQ::setBandCount(int count) {
    bandCount_ = std::clamp(count, 1, MAX_BANDS);
    reset();
}

void ParametricEQ::setDynamicBands(int count, const double* freqs, const double* qs) {
    bandCount_ = std::clamp(count, 1, MAX_BANDS);
    for (int i = 0; i < bandCount_; ++i) {
        bands_[i].frequency = freqs[i];
        bands_[i].q = qs ? qs[i] : 1.414;
        bands_[i].targetGainDb = 0.0;
        bands_[i].smoothedGainDb = 0.0;
        bands_[i].type = FilterType::Peaking;
        bands_[i].enabled = true;
        bands_[i].solo = false;
        bands_[i].mute = false;
        computeCoeffs(bands_[i], 0.0);
    }
    reset();
}

void ParametricEQ::setBand(int idx, double freq, double gainDb, double q, FilterType type, bool enabled) {
    if (idx < 0 || idx >= MAX_BANDS) return;
    if (idx >= bandCount_) bandCount_ = idx + 1;

    bands_[idx].frequency = std::clamp(freq, 10.0, sampleRate_ * 0.499);
    bands_[idx].targetGainDb = std::clamp(gainDb, -30.0, 30.0);
    bands_[idx].q = std::clamp(q, 0.05, 30.0);
    bands_[idx].type = type;
    bands_[idx].enabled = enabled;
    computeCoeffs(bands_[idx], bands_[idx].smoothedGainDb);
}

void ParametricEQ::setBandSolo(int idx, bool solo) {
    if (idx >= 0 && idx < bandCount_) {
        bands_[idx].solo = solo;
    }
}

void ParametricEQ::setBandMute(int idx, bool mute) {
    if (idx >= 0 && idx < bandCount_) {
        bands_[idx].mute = mute;
    }
}

void ParametricEQ::setPreamp(double preampDb) {
    targetPreampDb_ = std::clamp(preampDb, -30.0, 30.0);
}

void ParametricEQ::setEnabled(bool enabled) {
    enabled_ = enabled;
}

void ParametricEQ::applyParams(const EqParamSet& params) {
    const int newBandCount = std::clamp(params.bandCount, 1, MAX_BANDS);
    // FIX M-3: clear filter delay registers when band count or structure changes
    if (newBandCount != bandCount_) {
        std::memset(s1_, 0, sizeof(s1_));
        std::memset(s2_, 0, sizeof(s2_));
    }
    enabled_ = params.enabled;
    targetPreampDb_ = std::clamp(params.preampDb, -30.0, 30.0);
    bandCount_ = newBandCount;

    for (int i = 0; i < bandCount_; ++i) {
        const auto& p = params.bands[i];
        const double newFreq = std::clamp(p.frequency, 10.0, sampleRate_ * 0.499);
        const double newQ = std::clamp(p.q, 0.05, 30.0);
        // Clear filter state when the structure changes (frequency, Q, type,
        // enable or mute), not just frequency: a type/Q switch with retained
        // state otherwise leaves stale registers and clicks. Only re-derive
        // coefficients when something structural moved; a pure gain change is
        // applied through the per-block smoothed-gain path in process(), which
        // avoids recomputing every band's transcendentals on every parameter
        // generation.
        const bool structureChanged =
            std::abs(newFreq - bands_[i].frequency) > 1.0 ||
            std::abs(newQ - bands_[i].q) > 1e-6 ||
            p.type != bands_[i].type ||
            p.enabled != bands_[i].enabled ||
            p.mute != bands_[i].mute;
        if (structureChanged) {
            for (int ch = 0; ch < MAX_CHANNELS; ++ch) {
                s1_[ch][i] = s2_[ch][i] = 0.0;
            }
        }
        bands_[i].frequency = newFreq;
        bands_[i].targetGainDb = std::clamp(p.gainDb, -30.0, 30.0);
        bands_[i].q = newQ;
        bands_[i].type = p.type;
        bands_[i].enabled = p.enabled;
        bands_[i].solo = p.solo;
        bands_[i].mute = p.mute;
        if (structureChanged) {
            computeCoeffs(bands_[i], bands_[i].smoothedGainDb);
        }
    }
}

void ParametricEQ::reset() {
    std::memset(s1_, 0, sizeof(s1_));
    std::memset(s2_, 0, sizeof(s2_));
    smoothedPreampDb_ = targetPreampDb_;
    preampLinear_ = std::pow(10.0, smoothedPreampDb_ / 20.0);
    for (int i = 0; i < bandCount_; ++i) {
        bands_[i].smoothedGainDb = bands_[i].targetGainDb;
        computeCoeffs(bands_[i], bands_[i].smoothedGainDb);
    }
}


void ParametricEQ::computeCoeffs(EQBandState& band, double gainDb) {
    // Check if bypass optimization applies
    if (!band.enabled || band.mute) {
        band.bypass = true;
        band.coeffs = {1.0, 0.0, 0.0, 0.0, 0.0};
        return;
    }

    if (band.type == FilterType::Peaking || band.type == FilterType::LowShelf || band.type == FilterType::HighShelf) {
        if (std::abs(gainDb) < 0.01) {
            band.bypass = true;
            band.coeffs = {1.0, 0.0, 0.0, 0.0, 0.0};
            return;
        }
    }
    band.bypass = false;

    const double f0 = std::clamp(band.frequency, 10.0, sampleRate_ * 0.499);
    const double w0 = 2.0 * M_PI * f0 / sampleRate_;
    const double cosW = std::cos(w0);
    const double sinW = std::sin(w0);
    const double A = std::pow(10.0, gainDb / 40.0);
    const double q = std::max(band.q, 0.05);
    const double alpha = sinW / (2.0 * q);

    double b0 = 1.0, b1 = 0.0, b2 = 0.0, a0 = 1.0, a1 = 0.0, a2 = 0.0;

    switch (band.type) {
        case FilterType::Peaking: {
            b0 = 1.0 + alpha * A;
            b1 = -2.0 * cosW;
            b2 = 1.0 - alpha * A;
            a0 = 1.0 + alpha / A;
            a1 = -2.0 * cosW;
            a2 = 1.0 - alpha / A;
            break;
        }

        case FilterType::LowShelf: {
            const double sqrtA = std::sqrt(A);
            const double twoSqrtAAlpha = 2.0 * sqrtA * alpha;
            b0 = A * ((A + 1.0) - (A - 1.0) * cosW + twoSqrtAAlpha);
            b1 = 2.0 * A * ((A - 1.0) - (A + 1.0) * cosW);
            b2 = A * ((A + 1.0) - (A - 1.0) * cosW - twoSqrtAAlpha);
            a0 = (A + 1.0) + (A - 1.0) * cosW + twoSqrtAAlpha;
            a1 = -2.0 * ((A - 1.0) + (A + 1.0) * cosW);
            a2 = (A + 1.0) + (A - 1.0) * cosW - twoSqrtAAlpha;
            break;
        }

        case FilterType::HighShelf: {
            const double sqrtA = std::sqrt(A);
            const double twoSqrtAAlpha = 2.0 * sqrtA * alpha;
            b0 = A * ((A + 1.0) + (A - 1.0) * cosW + twoSqrtAAlpha);
            b1 = -2.0 * A * ((A - 1.0) + (A + 1.0) * cosW);
            b2 = A * ((A + 1.0) + (A - 1.0) * cosW - twoSqrtAAlpha);
            a0 = (A + 1.0) - (A - 1.0) * cosW + twoSqrtAAlpha;
            a1 = 2.0 * ((A - 1.0) - (A + 1.0) * cosW);
            a2 = (A + 1.0) - (A - 1.0) * cosW - twoSqrtAAlpha;
            break;
        }

        case FilterType::LowPass:
            b0 = (1.0 - cosW) / 2.0;
            b1 = 1.0 - cosW;
            b2 = (1.0 - cosW) / 2.0;
            a0 = 1.0 + alpha;
            a1 = -2.0 * cosW;
            a2 = 1.0 - alpha;
            break;

        case FilterType::HighPass:
            b0 = (1.0 + cosW) / 2.0;
            b1 = -(1.0 + cosW);
            b2 = (1.0 + cosW) / 2.0;
            a0 = 1.0 + alpha;
            a1 = -2.0 * cosW;
            a2 = 1.0 - alpha;
            break;

        case FilterType::Notch:
            b0 = 1.0;
            b1 = -2.0 * cosW;
            b2 = 1.0;
            a0 = 1.0 + alpha;
            a1 = -2.0 * cosW;
            a2 = 1.0 - alpha;
            break;

        case FilterType::BandPass:
            b0 = alpha;
            b1 = 0.0;
            b2 = -alpha;
            a0 = 1.0 + alpha;
            a1 = -2.0 * cosW;
            a2 = 1.0 - alpha;
            break;

        case FilterType::AllPass:
            b0 = 1.0 - alpha;
            b1 = -2.0 * cosW;
            b2 = 1.0 + alpha;
            a0 = 1.0 + alpha;
            a1 = -2.0 * cosW;
            a2 = 1.0 - alpha;
            break;
    }

    const double invA0 = 1.0 / a0;
    band.coeffs.b0 = b0 * invA0;
    band.coeffs.b1 = b1 * invA0;
    band.coeffs.b2 = b2 * invA0;
    band.coeffs.a1 = a1 * invA0;
    band.coeffs.a2 = a2 * invA0;
}

void ParametricEQ::process(const float* in, float* out, int frames, int channels) {
    if (in != out) {
        std::memcpy(out, in, frames * channels * sizeof(float));
    }
    processInterleaved(out, frames, channels);
}

void ParametricEQ::processInterleaved(float* buffer, int frames, int channels) {
    // A disabled EQ is a true bypass: the preamp is part of the EQ and must not
    // leak gain while the stage is off.
    if (!enabled_) return;

    channels = std::clamp(channels, 1, MAX_CHANNELS);

    // One-pole smoother coefficient for ~20ms time constant (tau = 0.020s)
    const double tau = 0.020;
    const double smoothFactor = 1.0 - std::exp(-static_cast<double>(frames) / (sampleRate_ * tau));

    // Smooth preamp gain
    if (std::abs(smoothedPreampDb_ - targetPreampDb_) > 1e-4) {
        smoothedPreampDb_ += smoothFactor * (targetPreampDb_ - smoothedPreampDb_);
        preampLinear_ = std::pow(10.0, smoothedPreampDb_ / 20.0);
    } else {
        smoothedPreampDb_ = targetPreampDb_;
        preampLinear_ = std::pow(10.0, smoothedPreampDb_ / 20.0);
    }

    // Apply smoothed preamp
    if (std::abs(preampLinear_ - 1.0) > 1e-4) {
        const float pLinear = static_cast<float>(preampLinear_);
        const int totalSamples = frames * channels;
        for (int i = 0; i < totalSamples; ++i) {
            buffer[i] *= pLinear;
        }
    }

    // Check if any band is soloed
    bool hasSolo = false;
    for (int b = 0; b < bandCount_; ++b) {
        if (bands_[b].solo) {
            hasSolo = true;
            break;
        }
    }

    // Update and smooth band gains & recompute coeffs
    for (int b = 0; b < bandCount_; ++b) {
        auto& band = bands_[b];
        const bool wasBypass = band.bypass;
        if (hasSolo && !band.solo) {
            band.bypass = true;
            if (!wasBypass) {
                for (int ch = 0; ch < MAX_CHANNELS; ++ch) {
                    s1_[ch][b] = s2_[ch][b] = 0.0;
                }
            }
            continue;
        }

        if (std::abs(band.smoothedGainDb - band.targetGainDb) > 1e-4) {
            band.smoothedGainDb += smoothFactor * (band.targetGainDb - band.smoothedGainDb);
            computeCoeffs(band, band.smoothedGainDb);
        } else if (band.smoothedGainDb != band.targetGainDb) {
            band.smoothedGainDb = band.targetGainDb;
            computeCoeffs(band, band.smoothedGainDb);
        }

        if (wasBypass && !band.bypass) {
            for (int ch = 0; ch < MAX_CHANNELS; ++ch) {
                s1_[ch][b] = s2_[ch][b] = 0.0;
            }
        }
    }

    // Process biquad cascaded filters per band across all channels (TDF-II)
    for (int b = 0; b < bandCount_; ++b) {
        const auto& band = bands_[b];
        if (band.bypass) continue;

        const double b0 = band.coeffs.b0;
        const double b1 = band.coeffs.b1;
        const double b2 = band.coeffs.b2;
        const double a1 = band.coeffs.a1;
        const double a2 = band.coeffs.a2;

        if (channels == 2) {
#if defined(PULSR_HAS_NEON)
            const float64x2_t vb0 = vdupq_n_f64(b0);
            const float64x2_t vb1 = vdupq_n_f64(b1);
            const float64x2_t vb2 = vdupq_n_f64(b2);
            const float64x2_t va1 = vdupq_n_f64(a1);
            const float64x2_t va2 = vdupq_n_f64(a2);

            // Load stereo state: lane 0 = L (ch 0), lane 1 = R (ch 1)
            double s1_arr[2] = { s1_[0][b], s1_[1][b] };
            double s2_arr[2] = { s2_[0][b], s2_[1][b] };
            float64x2_t vs1 = vld1q_f64(s1_arr);
            float64x2_t vs2 = vld1q_f64(s2_arr);

            float* chPtr = buffer;
            for (int f = 0; f < frames; ++f) {
                float32x2_t vf = vld1_f32(chPtr);
                float64x2_t vx = vcvt_f64_f32(vf);

                double x0 = vgetq_lane_f64(vx, 0);
                double x1 = vgetq_lane_f64(vx, 1);
                if (!std::isfinite(x0) || !std::isfinite(x1)) {
                    if (!std::isfinite(x0)) { x0 = 0.0; s1_[0][b] = 0.0; s2_[0][b] = 0.0; }
                    if (!std::isfinite(x1)) { x1 = 0.0; s1_[1][b] = 0.0; s2_[1][b] = 0.0; }
                    s1_arr[0] = s1_[0][b]; s1_arr[1] = s1_[1][b];
                    s2_arr[0] = s2_[0][b]; s2_arr[1] = s2_[1][b];
                    vs1 = vld1q_f64(s1_arr);
                    vs2 = vld1q_f64(s2_arr);
                    double x_clean[2] = { x0, x1 };
                    vx = vld1q_f64(x_clean);
                }

                // y[n] = b0 * x[n] + s1[n-1]
                float64x2_t vy = vaddq_f64(vmulq_f64(vb0, vx), vs1);

                // s1[n] = b1 * x[n] - a1 * y[n] + s2[n-1]
                float64x2_t vs1_next = vaddq_f64(vsubq_f64(vmulq_f64(vb1, vx), vmulq_f64(va1, vy)), vs2);
                // s2[n] = b2 * x[n] - a2 * y[n]
                float64x2_t vs2_next = vsubq_f64(vmulq_f64(vb2, vx), vmulq_f64(va2, vy));

                double y0 = vgetq_lane_f64(vy, 0);
                double y1 = vgetq_lane_f64(vy, 1);
                if (!std::isfinite(y0) || !std::isfinite(y1)) {
                    if (!std::isfinite(y0)) { y0 = x0; s1_arr[0] = 0.0; s2_arr[0] = 0.0; }
                    else { s1_arr[0] = vgetq_lane_f64(vs1_next, 0); s2_arr[0] = vgetq_lane_f64(vs2_next, 0); }

                    if (!std::isfinite(y1)) { y1 = x1; s1_arr[1] = 0.0; s2_arr[1] = 0.0; }
                    else { s1_arr[1] = vgetq_lane_f64(vs1_next, 1); s2_arr[1] = vgetq_lane_f64(vs2_next, 1); }

                    chPtr[0] = static_cast<float>(y0);
                    chPtr[1] = static_cast<float>(y1);
                    vs1 = vld1q_f64(s1_arr);
                    vs2 = vld1q_f64(s2_arr);
                } else {
                    vs1 = vs1_next;
                    vs2 = vs2_next;
                    float32x2_t vy_f32 = vcvt_f32_f64(vy);
                    vst1_f32(chPtr, vy_f32);
                }

                chPtr += 2;
            }

            vst1q_f64(s1_arr, vs1);
            vst1q_f64(s2_arr, vs2);
            for (int ch = 0; ch < 2; ++ch) {
                if (std::abs(s1_arr[ch]) < 1e-25 || !std::isfinite(s1_arr[ch])) s1_arr[ch] = 0.0;
                if (std::abs(s2_arr[ch]) < 1e-25 || !std::isfinite(s2_arr[ch])) s2_arr[ch] = 0.0;
                s1_[ch][b] = s1_arr[ch];
                s2_[ch][b] = s2_arr[ch];
            }
#elif defined(PULSR_HAS_SSE2)
            const __m128d vb0 = _mm_set1_pd(b0);
            const __m128d vb1 = _mm_set1_pd(b1);
            const __m128d vb2 = _mm_set1_pd(b2);
            const __m128d va1 = _mm_set1_pd(a1);
            const __m128d va2 = _mm_set1_pd(a2);

            __m128d vs1 = _mm_set_pd(s1_[1][b], s1_[0][b]);
            __m128d vs2 = _mm_set_pd(s2_[1][b], s2_[0][b]);

            float* chPtr = buffer;
            for (int f = 0; f < frames; ++f) {
                __m128d vx = _mm_set_pd(static_cast<double>(chPtr[1]), static_cast<double>(chPtr[0]));

                alignas(16) double x_arr[2];
                _mm_store_pd(x_arr, vx);

                if (!std::isfinite(x_arr[0]) || !std::isfinite(x_arr[1])) {
                    if (!std::isfinite(x_arr[0])) { x_arr[0] = 0.0; s1_[0][b] = 0.0; s2_[0][b] = 0.0; }
                    if (!std::isfinite(x_arr[1])) { x_arr[1] = 0.0; s1_[1][b] = 0.0; s2_[1][b] = 0.0; }
                    vs1 = _mm_set_pd(s1_[1][b], s1_[0][b]);
                    vs2 = _mm_set_pd(s2_[1][b], s2_[0][b]);
                    vx = _mm_set_pd(x_arr[1], x_arr[0]);
                }

                // y[n] = b0 * x[n] + s1[n-1]
                __m128d vy = _mm_add_pd(_mm_mul_pd(vb0, vx), vs1);

                // s1[n] = b1 * x[n] - a1 * y[n] + s2[n-1]
                __m128d vs1_next = _mm_add_pd(_mm_sub_pd(_mm_mul_pd(vb1, vx), _mm_mul_pd(va1, vy)), vs2);
                // s2[n] = b2 * x[n] - a2 * y[n]
                __m128d vs2_next = _mm_sub_pd(_mm_mul_pd(vb2, vx), _mm_mul_pd(va2, vy));

                alignas(16) double y_arr[2];
                _mm_store_pd(y_arr, vy);

                if (!std::isfinite(y_arr[0]) || !std::isfinite(y_arr[1])) {
                    alignas(16) double s1_arr[2], s2_arr[2];
                    _mm_store_pd(s1_arr, vs1_next);
                    _mm_store_pd(s2_arr, vs2_next);

                    if (!std::isfinite(y_arr[0])) { y_arr[0] = x_arr[0]; s1_arr[0] = 0.0; s2_arr[0] = 0.0; }
                    if (!std::isfinite(y_arr[1])) { y_arr[1] = x_arr[1]; s1_arr[1] = 0.0; s2_arr[1] = 0.0; }

                    chPtr[0] = static_cast<float>(y_arr[0]);
                    chPtr[1] = static_cast<float>(y_arr[1]);
                    vs1 = _mm_set_pd(s1_arr[1], s1_arr[0]);
                    vs2 = _mm_set_pd(s2_arr[1], s2_arr[0]);
                } else {
                    vs1 = vs1_next;
                    vs2 = vs2_next;
                    chPtr[0] = static_cast<float>(y_arr[0]);
                    chPtr[1] = static_cast<float>(y_arr[1]);
                }

                chPtr += 2;
            }

            alignas(16) double s1_out[2], s2_out[2];
            _mm_store_pd(s1_out, vs1);
            _mm_store_pd(s2_out, vs2);

            for (int ch = 0; ch < 2; ++ch) {
                double s1 = s1_out[ch];
                double s2 = s2_out[ch];
                if (std::abs(s1) < 1e-25 || !std::isfinite(s1)) s1 = 0.0;
                if (std::abs(s2) < 1e-25 || !std::isfinite(s2)) s2 = 0.0;
                s1_[ch][b] = s1;
                s2_[ch][b] = s2;
            }
#else
            for (int ch = 0; ch < 2; ++ch) {
                double s1 = s1_[ch][b];
                double s2 = s2_[ch][b];
                float* chPtr = buffer + ch;
                for (int f = 0; f < frames; ++f) {
                    const double x0 = static_cast<double>(*chPtr);
                    if (!std::isfinite(x0)) {
                        *chPtr = 0.0f;
                        s1 = 0.0;
                        s2 = 0.0;
                        chPtr += 2;
                        continue;
                    }
                    double y0 = b0 * x0 + s1;
                    if (!std::isfinite(y0)) {
                        s1 = 0.0;
                        s2 = 0.0;
                        y0 = x0;
                    } else {
                        s1 = b1 * x0 - a1 * y0 + s2;
                        s2 = b2 * x0 - a2 * y0;
                    }
                    *chPtr = static_cast<float>(y0);
                    chPtr += 2;
                }
                if (std::abs(s1) < 1e-25 || !std::isfinite(s1)) s1 = 0.0;
                if (std::abs(s2) < 1e-25 || !std::isfinite(s2)) s2 = 0.0;
                s1_[ch][b] = s1;
                s2_[ch][b] = s2;
            }
#endif
        } else {
            for (int ch = 0; ch < channels; ++ch) {
                double s1 = s1_[ch][b];
                double s2 = s2_[ch][b];

                float* chPtr = buffer + ch;
                for (int f = 0; f < frames; ++f) {
                    const double x0 = static_cast<double>(*chPtr);
                    if (!std::isfinite(x0)) {
                        *chPtr = 0.0f;
                        s1 = 0.0;
                        s2 = 0.0;
                        chPtr += channels;
                        continue;
                    }

                    double y0 = b0 * x0 + s1;

                    if (!std::isfinite(y0)) {
                        s1 = 0.0;
                        s2 = 0.0;
                        y0 = x0;
                    } else {
                        s1 = b1 * x0 - a1 * y0 + s2;
                        s2 = b2 * x0 - a2 * y0;
                    }

                    *chPtr = static_cast<float>(y0);
                    chPtr += channels;
                }

                if (std::abs(s1) < 1e-25 || !std::isfinite(s1)) s1 = 0.0;
                if (std::abs(s2) < 1e-25 || !std::isfinite(s2)) s2 = 0.0;

                s1_[ch][b] = s1;
                s2_[ch][b] = s2;
            }
        }
    }
}

