// android/app/src/main/cpp/DynamicEQ.cpp
#include "DynamicEQ.h"
#include <cstring>
#include <cmath>

#if defined(__aarch64__) || defined(_M_ARM64)
#include <arm_neon.h>
#define PULSR_HAS_NEON 1
#elif defined(__x86_64__) || defined(_M_X64)
#include <emmintrin.h>
#define PULSR_HAS_SSE2 1
#endif

DynamicEQ::DynamicEQ() {
    setSampleRate(48000.0);
    reset();
}

void DynamicEQ::setSampleRate(double sampleRate) {
    if (sampleRate < 8000.0) sampleRate = 8000.0;
    if (sampleRate > 768000.0) sampleRate = 768000.0;
    sampleRate_ = sampleRate;
    for (int i = 0; i < MAX_BANDS; ++i) {
        updateBandCache(bands_[i]);
        bands_[i].lastCoeffGainDb = 1e9; // force recompute at new rate
        computeBandCoeffs(bands_[i], bands_[i].currentGainDb);
        // FIX M-7: the detection band-pass and application biquads were just
        // recomputed for the new rate; their retained registers belong to the
        // old coefficients and would thump. computeBandCoeffs only clears the
        // application state when |gain|<1e-6 and never clears the detector
        // state, so flush both explicitly on a rate change (mirrors reset()).
        BandState& band = bands_[i];
        std::memset(band.dx1, 0, sizeof(band.dx1));
        std::memset(band.dx2, 0, sizeof(band.dx2));
        std::memset(band.dy1, 0, sizeof(band.dy1));
        std::memset(band.dy2, 0, sizeof(band.dy2));
        std::memset(band.env, 0, sizeof(band.env));
        std::memset(band.x1, 0, sizeof(band.x1));
        std::memset(band.x2, 0, sizeof(band.x2));
        std::memset(band.y1, 0, sizeof(band.y1));
        std::memset(band.y2, 0, sizeof(band.y2));
    }
}

void DynamicEQ::setBandCount(int count) {
    bandCount_ = std::clamp(count, 0, MAX_BANDS);
}

void DynamicEQ::setBand(int idx, const DynamicEqBandParam& params) {
    if (idx < 0 || idx >= MAX_BANDS) return;
    if (idx >= bandCount_) bandCount_ = idx + 1;
    BandState& band = bands_[idx];

    // FIX M-8: detect a structural change (frequency / Q / filter type) so this
    // band's retained filter state can be cleared below. computeBandCoeffs only
    // zeroes the application state when |gain|<1e-6 (~:137-140) and never
    // touches the detector state, so a retune at non-zero gain otherwise leaves
    // stale registers and clicks. Capture old values before overwriting them.
    const double newFreq = std::clamp(params.frequency, 20.0, sampleRate_ * 0.45);
    const double newQ = std::clamp(params.q, 0.1, 12.0);
    const int newFilterType = std::clamp(params.filterType, 0, 2);
    const bool structureChanged =
        std::abs(newFreq - band.frequency) > 1e-6 ||
        std::abs(newQ - band.q) > 1e-6 ||
        newFilterType != band.filterType;

    band.frequency = newFreq;
    band.q = newQ;
    band.thresholdDb = std::clamp(params.thresholdDb, -80.0, 0.0);
    band.ratio = std::clamp(params.ratio, 1.0, 20.0);
    band.attackMs = std::clamp(params.attackMs, 0.1, 200.0);
    band.releaseMs = std::clamp(params.releaseMs, 5.0, 2000.0);
    band.maxCutDb = std::clamp(params.maxCutDb, -24.0, 0.0);
    band.maxBoostDb = std::clamp(params.maxBoostDb, 0.0, 24.0);
    band.mode = std::clamp(params.mode, 0, 1);
    band.filterType = newFilterType;
    band.enabled = params.enabled;
    updateBandCache(band);
    band.lastCoeffGainDb = 1e9; // force recompute

    // FIX M-8: only the band that actually changed is cleared, so untouched
    // bands keep their filter continuity.
    if (structureChanged) {
        std::memset(band.dx1, 0, sizeof(band.dx1));
        std::memset(band.dx2, 0, sizeof(band.dx2));
        std::memset(band.dy1, 0, sizeof(band.dy1));
        std::memset(band.dy2, 0, sizeof(band.dy2));
        std::memset(band.env, 0, sizeof(band.env));
        std::memset(band.x1, 0, sizeof(band.x1));
        std::memset(band.x2, 0, sizeof(band.x2));
        std::memset(band.y1, 0, sizeof(band.y1));
        std::memset(band.y2, 0, sizeof(band.y2));
    }
}

void DynamicEQ::applyParams(const DynamicEqParamSet& params) {
    enabled_ = params.enabled;
    for (int i = 0; i < MAX_BANDS; ++i) {
        setBand(i, params.bands[i]);
    }
    bandCount_ = std::clamp(params.bandCount, 0, MAX_BANDS);
}

void DynamicEQ::reset() {
    for (int b = 0; b < MAX_BANDS; ++b) {
        BandState& band = bands_[b];
        std::memset(band.dx1, 0, sizeof(band.dx1));
        std::memset(band.dx2, 0, sizeof(band.dx2));
        std::memset(band.dy1, 0, sizeof(band.dy1));
        std::memset(band.dy2, 0, sizeof(band.dy2));
        std::memset(band.env, 0, sizeof(band.env));
        std::memset(band.x1, 0, sizeof(band.x1));
        std::memset(band.x2, 0, sizeof(band.x2));
        std::memset(band.y1, 0, sizeof(band.y1));
        std::memset(band.y2, 0, sizeof(band.y2));
        band.currentGainDb = 0.0;
        band.lastCoeffGainDb = 1e9;
        computeBandCoeffs(band, 0.0);
    }
}

double DynamicEQ::getGainAdjustmentDb(int band) const {
    if (band < 0 || band >= MAX_BANDS) return 0.0;
    return bands_[band].currentGainDb;
}

void DynamicEQ::updateBandCache(BandState& band) {
    const double w0 = 2.0 * M_PI * band.frequency / sampleRate_;
    band.cw = std::cos(w0);
    const double sw = std::sin(w0);
    band.alpha = sw / (2.0 * band.q);

    const double a0 = 1.0 + band.alpha;
    band.detectB0 = band.alpha / a0;
    band.detectB1 = 0.0;
    band.detectB2 = -band.alpha / a0;
    band.detectA1 = (-2.0 * band.cw) / a0;
    band.detectA2 = (1.0 - band.alpha) / a0;
}

void DynamicEQ::computePeakingCoeffs(double& b0, double& b1, double& b2,
                                     double& a1, double& a2,
                                     double cw, double alpha, double A) {
    const double a0 = 1.0 + alpha / A;
    b0 = (1.0 + alpha * A) / a0;
    b1 = (-2.0 * cw) / a0;
    b2 = (1.0 - alpha * A) / a0;
    a1 = (-2.0 * cw) / a0;
    a2 = (1.0 - alpha / A) / a0;
}

void DynamicEQ::computeLowShelfCoeffs(double& b0, double& b1, double& b2,
                                      double& a1, double& a2,
                                      double cw, double alpha, double A) {
    const double twoSqrtAAlpha = 2.0 * std::sqrt(A) * alpha;
    const double a0 = (A + 1.0) + (A - 1.0) * cw + twoSqrtAAlpha;
    b0 = (A * ((A + 1.0) - (A - 1.0) * cw + twoSqrtAAlpha)) / a0;
    b1 = (2.0 * A * ((A - 1.0) - (A + 1.0) * cw)) / a0;
    b2 = (A * ((A + 1.0) - (A - 1.0) * cw - twoSqrtAAlpha)) / a0;
    a1 = (-2.0 * ((A - 1.0) + (A + 1.0) * cw)) / a0;
    a2 = ((A + 1.0) + (A - 1.0) * cw - twoSqrtAAlpha) / a0;
}

void DynamicEQ::computeHighShelfCoeffs(double& b0, double& b1, double& b2,
                                       double& a1, double& a2,
                                       double cw, double alpha, double A) {
    const double twoSqrtAAlpha = 2.0 * std::sqrt(A) * alpha;
    const double a0 = (A + 1.0) - (A - 1.0) * cw + twoSqrtAAlpha;
    b0 = (A * ((A + 1.0) + (A - 1.0) * cw + twoSqrtAAlpha)) / a0;
    b1 = (-2.0 * A * ((A - 1.0) + (A + 1.0) * cw)) / a0;
    b2 = (A * ((A + 1.0) + (A - 1.0) * cw - twoSqrtAAlpha)) / a0;
    a1 = (2.0 * ((A - 1.0) - (A + 1.0) * cw)) / a0;
    a2 = ((A + 1.0) - (A - 1.0) * cw - twoSqrtAAlpha) / a0;
}

void DynamicEQ::computeBandCoeffs(BandState& band, double gainDb) {
    if (std::abs(gainDb) < 1e-6) {
        band.b0 = 1.0; band.b1 = 0.0; band.b2 = 0.0;
        band.a1 = 0.0; band.a2 = 0.0;
        for (int ch = 0; ch < MAX_CHANNELS; ++ch) {
            band.x1[ch] = 0.0; band.x2[ch] = 0.0;
            band.y1[ch] = 0.0; band.y2[ch] = 0.0;
        }
        band.lastCoeffGainDb = 0.0;
        return;
    }

    const double A = std::exp((gainDb / 40.0) * 2.302585092994045684);

    if (band.filterType == 1) {
        computeLowShelfCoeffs(band.b0, band.b1, band.b2, band.a1, band.a2,
                              band.cw, band.alpha, A);
    } else if (band.filterType == 2) {
        computeHighShelfCoeffs(band.b0, band.b1, band.b2, band.a1, band.a2,
                               band.cw, band.alpha, A);
    } else {
        computePeakingCoeffs(band.b0, band.b1, band.b2, band.a1, band.a2,
                             band.cw, band.alpha, A);
    }
    band.lastCoeffGainDb = gainDb;
}

void DynamicEQ::process(float* L, float* R, int frames) {
    if (!L || !R || frames <= 0) return;
    const int n = bandCount_;

    if (!enabled_) {
        bool hasActiveGain = false;
        for (int b = 0; b < n; ++b) {
            if (std::abs(bands_[b].currentGainDb) > 1e-4) {
                hasActiveGain = true;
                break;
            }
        }
        if (!hasActiveGain) return;
    }

    for (int b = 0; b < n; ++b) {
        BandState& band = bands_[b];
        if (!band.enabled || !enabled_) {
            if (std::abs(band.currentGainDb) > 1e-4) {
                const double rampStep = band.currentGainDb / frames;
                for (int i = 0; i < frames; ++i) {
                    double l = L[i];
                    double r = R[i];
                    if (!std::isfinite(l)) l = 0.0;
                    if (!std::isfinite(r)) r = 0.0;
                    band.currentGainDb -= rampStep;
                    if (((i & 15) == 0 || i == frames - 1) &&
                        std::abs(band.currentGainDb - band.lastCoeffGainDb) > 0.05) {
                        computeBandCoeffs(band, band.currentGainDb);
                    }
                    L[i] = static_cast<float>(band.b0 * l + band.b1 * band.x1[0] + band.b2 * band.x2[0]
                                              - band.a1 * band.y1[0] - band.a2 * band.y2[0]);
                    R[i] = static_cast<float>(band.b0 * r + band.b1 * band.x1[1] + band.b2 * band.x2[1]
                                              - band.a1 * band.y1[1] - band.a2 * band.y2[1]);
                    band.x2[0] = band.x1[0]; band.x1[0] = l;
                    band.y2[0] = band.y1[0]; band.y1[0] = L[i];
                    band.x2[1] = band.x1[1]; band.x1[1] = r;
                    band.y2[1] = band.y1[1]; band.y1[1] = R[i];
                }
                band.currentGainDb = 0.0;
                computeBandCoeffs(band, 0.0);
            }
            continue;
        }

        const double attackCoeff = 1.0 - std::exp(-1.0 / (sampleRate_ * band.attackMs * 0.001));
        const double releaseCoeff = 1.0 - std::exp(-1.0 / (sampleRate_ * band.releaseMs * 0.001));

        for (int i = 0; i < frames; ++i) {
            double l = L[i];
            double r = R[i];
            if (!std::isfinite(l)) l = 0.0;
            if (!std::isfinite(r)) r = 0.0;

            // Detection: band-pass -> smoothed envelope
            double envMax = 0.0;
            for (int ch = 0; ch < 2; ++ch) {
                const double x = (ch == 0) ? l : r;
                double bp = band.detectB0 * x
                    + band.detectB1 * band.dx1[ch] + band.detectB2 * band.dx2[ch]
                    - band.detectA1 * band.dy1[ch] - band.detectA2 * band.dy2[ch];
                if (std::abs(bp) < 1e-25) bp = 0.0;
                band.dx2[ch] = band.dx1[ch];
                band.dx1[ch] = x;
                band.dy2[ch] = band.dy1[ch];
                band.dy1[ch] = bp;
                
                const double absBp = std::abs(bp);
                const double coeff = (absBp > band.env[ch]) ? attackCoeff : releaseCoeff;
                band.env[ch] += coeff * (absBp - band.env[ch]);
                if (band.env[ch] > envMax) envMax = band.env[ch];
            }

            // Gain computer: Cut (mode 0) vs Boost (mode 1)
            const double envDb = 20.0 * std::log10(envMax + 1e-12);
            const double overDb = envDb - band.thresholdDb;
            const double ratio = std::max(1.0, band.ratio);

            double targetGainDb = 0.0;
            if (band.mode == 1) {
                // Boost mode: dynamic expansion above threshold
                const double maxBoost = band.maxBoostDb;
                targetGainDb = (overDb > 0.0)
                    ? std::min(maxBoost, overDb * (1.0 - 1.0 / ratio))
                    : 0.0;
            } else {
                // Cut mode: dynamic compression above threshold
                const double maxCutDepth = -band.maxCutDb;
                targetGainDb = (overDb > 0.0)
                    ? -std::min(maxCutDepth, overDb * (1.0 - 1.0 / ratio))
                    : 0.0;
            }

            const double ballisticsCoeff = (std::abs(targetGainDb) > std::abs(band.currentGainDb)) ? attackCoeff : releaseCoeff;
            band.currentGainDb += ballisticsCoeff * (targetGainDb - band.currentGainDb);

            // Application
            if (((i & 15) == 0 || i == frames - 1) &&
                std::abs(band.currentGainDb - band.lastCoeffGainDb) > 0.05) {
                computeBandCoeffs(band, band.currentGainDb);
            }
            double yL = band.b0 * l + band.b1 * band.x1[0] + band.b2 * band.x2[0]
                                      - band.a1 * band.y1[0] - band.a2 * band.y2[0];
            double yR = band.b0 * r + band.b1 * band.x1[1] + band.b2 * band.x2[1]
                                      - band.a1 * band.y1[1] - band.a2 * band.y2[1];
            if (std::abs(yL) < 1e-25) yL = 0.0;
            if (std::abs(yR) < 1e-25) yR = 0.0;

            L[i] = static_cast<float>(yL);
            R[i] = static_cast<float>(yR);
            band.x2[0] = band.x1[0]; band.x1[0] = l;
            band.y2[0] = band.y1[0]; band.y1[0] = yL;
            band.x2[1] = band.x1[1]; band.x1[1] = r;
            band.y2[1] = band.y1[1]; band.y1[1] = yR;
        }
    }
}

void DynamicEQ::processInterleaved(float* buffer, int frames, int channels) {
    if (!buffer || frames <= 0 || channels <= 0) return;
    const int n = bandCount_;
    const int chCount = std::min(channels, MAX_CHANNELS);

    if (!enabled_) {
        bool hasActiveGain = false;
        for (int b = 0; b < n; ++b) {
            if (std::abs(bands_[b].currentGainDb) > 1e-4) {
                hasActiveGain = true;
                break;
            }
        }
        if (!hasActiveGain) return;
    }

    for (int b = 0; b < n; ++b) {
        BandState& band = bands_[b];
        if (!band.enabled || !enabled_) {
            if (std::abs(band.currentGainDb) > 1e-4) {
                const double rampStep = band.currentGainDb / frames;
                for (int i = 0; i < frames; ++i) {
                    band.currentGainDb -= rampStep;
                    if (((i & 15) == 0 || i == frames - 1) &&
                        std::abs(band.currentGainDb - band.lastCoeffGainDb) > 0.05) {
                        computeBandCoeffs(band, band.currentGainDb);
                    }
                    for (int ch = 0; ch < chCount; ++ch) {
                        double x = buffer[i * channels + ch];
                        if (!std::isfinite(x)) x = 0.0;
                        const double y = band.b0 * x + band.b1 * band.x1[ch] + band.b2 * band.x2[ch]
                            - band.a1 * band.y1[ch] - band.a2 * band.y2[ch];
                        band.x2[ch] = band.x1[ch];
                        band.x1[ch] = x;
                        band.y2[ch] = band.y1[ch];
                        band.y1[ch] = y;
                        buffer[i * channels + ch] = static_cast<float>(y);
                    }
                }
                band.currentGainDb = 0.0;
                computeBandCoeffs(band, 0.0);
            }
            continue;
        }

        const double attackCoeff = 1.0 - std::exp(-1.0 / (sampleRate_ * band.attackMs * 0.001));
        const double releaseCoeff = 1.0 - std::exp(-1.0 / (sampleRate_ * band.releaseMs * 0.001));

        for (int i = 0; i < frames; ++i) {
            // FIX M-9: flush non-finite inputs in place before they reach the
            // detector or application biquads. The denormal flush
            // (std::abs(..) < 1e-25) does NOT catch NaN/inf, so one bad sample
            // would otherwise poison env/dx/dy (and y1/y2) and trip the engine's
            // heavy global resetInternal(). The sibling process(L,R) path
            // sanitizes its inputs up front (~:211-212); do the same here so the
            // detection read, the SIMD/scalar application reads and the x-history
            // updates all see finite values.
            for (int ch = 0; ch < chCount; ++ch) {
                if (!std::isfinite(buffer[i * channels + ch])) buffer[i * channels + ch] = 0.0f;
            }

            double envMax = 0.0;
            for (int ch = 0; ch < chCount; ++ch) {
                const double x = buffer[i * channels + ch];
                double bp = band.detectB0 * x
                    + band.detectB1 * band.dx1[ch] + band.detectB2 * band.dx2[ch]
                    - band.detectA1 * band.dy1[ch] - band.detectA2 * band.dy2[ch];
                if (std::abs(bp) < 1e-25) bp = 0.0;
                band.dx2[ch] = band.dx1[ch];
                band.dx1[ch] = x;
                band.dy2[ch] = band.dy1[ch];
                band.dy1[ch] = bp;
                
                const double absBp = std::abs(bp);
                const double coeff = (absBp > band.env[ch]) ? attackCoeff : releaseCoeff;
                band.env[ch] += coeff * (absBp - band.env[ch]);
                if (band.env[ch] > envMax) envMax = band.env[ch];
            }

            const double envDb = 20.0 * std::log10(envMax + 1e-12);
            const double overDb = envDb - band.thresholdDb;
            const double ratio = std::max(1.0, band.ratio);

            double targetGainDb = 0.0;
            if (band.mode == 1) {
                targetGainDb = (overDb > 0.0)
                    ? std::min(band.maxBoostDb, overDb * (1.0 - 1.0 / ratio))
                    : 0.0;
            } else {
                targetGainDb = (overDb > 0.0)
                    ? -std::min(-band.maxCutDb, overDb * (1.0 - 1.0 / ratio))
                    : 0.0;
            }

            const double ballisticsCoeff = (std::abs(targetGainDb) > std::abs(band.currentGainDb)) ? attackCoeff : releaseCoeff;
            band.currentGainDb += ballisticsCoeff * (targetGainDb - band.currentGainDb);

            if (((i & 15) == 0 || i == frames - 1) &&
                std::abs(band.currentGainDb - band.lastCoeffGainDb) > 0.05) {
                computeBandCoeffs(band, band.currentGainDb);
            }

            if (chCount == 2) {
#if defined(PULSR_HAS_NEON) && (defined(__aarch64__) || defined(_M_ARM64))
                float64x2_t vx = { buffer[i * channels], buffer[i * channels + 1] };
                float64x2_t vx1 = { band.x1[0], band.x1[1] };
                float64x2_t vx2 = { band.x2[0], band.x2[1] };
                float64x2_t vy1 = { band.y1[0], band.y1[1] };
                float64x2_t vy2 = { band.y2[0], band.y2[1] };
                float64x2_t vb0 = vdupq_n_f64(band.b0);
                float64x2_t vb1 = vdupq_n_f64(band.b1);
                float64x2_t vb2 = vdupq_n_f64(band.b2);
                float64x2_t va1 = vdupq_n_f64(band.a1);
                float64x2_t va2 = vdupq_n_f64(band.a2);

                float64x2_t vy = vsubq_f64(
                    vaddq_f64(vmulq_f64(vb0, vx), vaddq_f64(vmulq_f64(vb1, vx1), vmulq_f64(vb2, vx2))),
                    vaddq_f64(vmulq_f64(va1, vy1), vmulq_f64(va2, vy2))
                );

                double y0 = vgetq_lane_f64(vy, 0);
                double y1 = vgetq_lane_f64(vy, 1);
                // FIX M-9: flush NaN/inf as well as denormals before the output
                // feeds back into the y1/y2 history.
                if (!std::isfinite(y0) || std::abs(y0) < 1e-25) y0 = 0.0;
                if (!std::isfinite(y1) || std::abs(y1) < 1e-25) y1 = 0.0;

                band.x2[0] = band.x1[0]; band.x2[1] = band.x1[1];
                band.x1[0] = buffer[i * channels]; band.x1[1] = buffer[i * channels + 1];
                band.y2[0] = band.y1[0]; band.y2[1] = band.y1[1];
                band.y1[0] = y0; band.y1[1] = y1;

                buffer[i * channels] = static_cast<float>(y0);
                buffer[i * channels + 1] = static_cast<float>(y1);
#elif defined(PULSR_HAS_SSE2)
                __m128d vx = _mm_set_pd(buffer[i * channels + 1], buffer[i * channels]);
                __m128d vx1 = _mm_set_pd(band.x1[1], band.x1[0]);
                __m128d vx2 = _mm_set_pd(band.x2[1], band.x2[0]);
                __m128d vy1 = _mm_set_pd(band.y1[1], band.y1[0]);
                __m128d vy2 = _mm_set_pd(band.y2[1], band.y2[0]);
                __m128d vb0 = _mm_set1_pd(band.b0);
                __m128d vb1 = _mm_set1_pd(band.b1);
                __m128d vb2 = _mm_set1_pd(band.b2);
                __m128d va1 = _mm_set1_pd(band.a1);
                __m128d va2 = _mm_set1_pd(band.a2);

                __m128d vy = _mm_sub_pd(
                    _mm_add_pd(_mm_mul_pd(vb0, vx), _mm_add_pd(_mm_mul_pd(vb1, vx1), _mm_mul_pd(vb2, vx2))),
                    _mm_add_pd(_mm_mul_pd(va1, vy1), _mm_mul_pd(va2, vy2))
                );

                alignas(16) double y_arr[2];
                _mm_store_pd(y_arr, vy);
                // FIX M-9: flush NaN/inf as well as denormals before the output
                // feeds back into the y1/y2 history.
                if (!std::isfinite(y_arr[0]) || std::abs(y_arr[0]) < 1e-25) y_arr[0] = 0.0;
                if (!std::isfinite(y_arr[1]) || std::abs(y_arr[1]) < 1e-25) y_arr[1] = 0.0;

                band.x2[0] = band.x1[0]; band.x2[1] = band.x1[1];
                band.x1[0] = buffer[i * channels]; band.x1[1] = buffer[i * channels + 1];
                band.y2[0] = band.y1[0]; band.y2[1] = band.y1[1];
                band.y1[0] = y_arr[0]; band.y1[1] = y_arr[1];

                buffer[i * channels] = static_cast<float>(y_arr[0]);
                buffer[i * channels + 1] = static_cast<float>(y_arr[1]);
#else
                for (int ch = 0; ch < 2; ++ch) {
                    const double x = buffer[i * channels + ch];
                    double y = band.b0 * x + band.b1 * band.x1[ch] + band.b2 * band.x2[ch]
                        - band.a1 * band.y1[ch] - band.a2 * band.y2[ch];
                    // FIX M-9: flush NaN/inf as well as denormals before y feeds
                    // back into the y1/y2 history.
                    if (!std::isfinite(y) || std::abs(y) < 1e-25) y = 0.0;

                    band.x2[ch] = band.x1[ch];
                    band.x1[ch] = x;
                    band.y2[ch] = band.y1[ch];
                    band.y1[ch] = y;
                    buffer[i * channels + ch] = static_cast<float>(y);
                }
#endif
            } else {
                for (int ch = 0; ch < chCount; ++ch) {
                    const double x = buffer[i * channels + ch];
                    double y = band.b0 * x + band.b1 * band.x1[ch] + band.b2 * band.x2[ch]
                        - band.a1 * band.y1[ch] - band.a2 * band.y2[ch];
                    // FIX M-9: flush NaN/inf as well as denormals before y feeds
                    // back into the y1/y2 history.
                    if (!std::isfinite(y) || std::abs(y) < 1e-25) y = 0.0;

                    band.x2[ch] = band.x1[ch];
                    band.x1[ch] = x;
                    band.y2[ch] = band.y1[ch];
                    band.y1[ch] = y;
                    buffer[i * channels + ch] = static_cast<float>(y);
                }
            }
        }
    }
}
