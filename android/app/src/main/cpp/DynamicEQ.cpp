// android/app/src/main/cpp/DynamicEQ.cpp
#include "DynamicEQ.h"
#include <cstring>

DynamicEQ::DynamicEQ() {
    setSampleRate(48000.0);
    reset();
}

void DynamicEQ::setSampleRate(double sampleRate) {
    if (sampleRate < 8000.0) sampleRate = 8000.0;
    if (sampleRate > 768000.0) sampleRate = 768000.0;
    sampleRate_ = sampleRate;
    for (int i = 0; i < MAX_BANDS; ++i) {
        bands_[i].lastCoeffGainDb = 1e9; // force recompute at new rate
        computeBandCoeffs(bands_[i], bands_[i].currentGainDb);
    }
}

void DynamicEQ::setBandCount(int count) {
    bandCount_ = std::clamp(count, 0, MAX_BANDS);
}

void DynamicEQ::setBand(int idx, const DynamicEqBandParam& params) {
    if (idx < 0 || idx >= MAX_BANDS) return;
    if (idx >= bandCount_) bandCount_ = idx + 1;
    BandState& band = bands_[idx];
    band.frequency = std::clamp(params.frequency, 20.0, sampleRate_ * 0.45);
    band.q = std::clamp(params.q, 0.1, 12.0);
    band.thresholdDb = std::clamp(params.thresholdDb, -80.0, 0.0);
    band.ratio = std::clamp(params.ratio, 1.0, 20.0);
    band.attackMs = std::clamp(params.attackMs, 0.1, 200.0);
    band.releaseMs = std::clamp(params.releaseMs, 5.0, 2000.0);
    band.maxCutDb = std::clamp(params.maxCutDb, -24.0, 0.0);
    band.maxBoostDb = std::clamp(params.maxBoostDb, 0.0, 24.0);
    band.mode = std::clamp(params.mode, 0, 1);
    band.filterType = std::clamp(params.filterType, 0, 2);
    band.enabled = params.enabled;
    band.lastCoeffGainDb = 1e9; // force recompute
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

// RBJ band-pass (constant 0 dB peak gain) — used for band energy detection.
static void computeDetectCoeffs(double& b0, double& b1, double& b2,
                                double& a1, double& a2,
                                double f0, double q, double fs) {
    const double w0 = 2.0 * M_PI * f0 / fs;
    const double cw = std::cos(w0), sw = std::sin(w0);
    const double alpha = sw / (2.0 * q);
    const double a0 = 1.0 + alpha;
    b0 = alpha / a0;
    b1 = 0.0;
    b2 = -alpha / a0;
    a1 = (-2.0 * cw) / a0;
    a2 = (1.0 - alpha) / a0;
}

double DynamicEQ::computePeakingCoeffs(double& b0, double& b1, double& b2,
                                       double& a1, double& a2,
                                       double f0, double q, double gainDb, double fs) {
    const double A = std::pow(10.0, gainDb / 40.0);
    const double w0 = 2.0 * M_PI * f0 / fs;
    const double cw = std::cos(w0), sw = std::sin(w0);
    const double alpha = sw / (2.0 * q);
    const double a0 = 1.0 + alpha / A;
    b0 = (1.0 + alpha * A) / a0;
    b1 = (-2.0 * cw) / a0;
    b2 = (1.0 - alpha * A) / a0;
    a1 = (-2.0 * cw) / a0;
    a2 = (1.0 - alpha / A) / a0;
    return A;
}

void DynamicEQ::computeLowShelfCoeffs(double& b0, double& b1, double& b2,
                                     double& a1, double& a2,
                                     double f0, double q, double gainDb, double fs) {
    const double A = std::pow(10.0, gainDb / 40.0);
    const double w0 = 2.0 * M_PI * f0 / fs;
    const double cw = std::cos(w0), sw = std::sin(w0);
    const double alpha = sw / (2.0 * q);
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
                                      double f0, double q, double gainDb, double fs) {
    const double A = std::pow(10.0, gainDb / 40.0);
    const double w0 = 2.0 * M_PI * f0 / fs;
    const double cw = std::cos(w0), sw = std::sin(w0);
    const double alpha = sw / (2.0 * q);
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
        band.lastCoeffGainDb = 0.0;
        return;
    }

    if (band.filterType == 1) {
        computeLowShelfCoeffs(band.b0, band.b1, band.b2, band.a1, band.a2,
                              band.frequency, band.q, gainDb, sampleRate_);
    } else if (band.filterType == 2) {
        computeHighShelfCoeffs(band.b0, band.b1, band.b2, band.a1, band.a2,
                               band.frequency, band.q, gainDb, sampleRate_);
    } else {
        computePeakingCoeffs(band.b0, band.b1, band.b2, band.a1, band.a2,
                             band.frequency, band.q, gainDb, sampleRate_);
    }
    band.lastCoeffGainDb = gainDb;
}

void DynamicEQ::process(float* L, float* R, int frames) {
    if (!enabled_ || !L || !R || frames <= 0) return;
    const int n = bandCount_;

    for (int b = 0; b < n; ++b) {
        BandState& band = bands_[b];
        if (!band.enabled) {
            if (std::abs(band.currentGainDb) > 1e-4) {
                const double rampStep = band.currentGainDb / frames;
                for (int i = 0; i < frames; ++i) {
                    const double l = L[i];
                    const double r = R[i];
                    band.currentGainDb -= rampStep;
                    if (std::abs(band.currentGainDb - band.lastCoeffGainDb) > 0.05) {
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

        double detectB0, detectB1, detectB2, detectA1, detectA2;
        computeDetectCoeffs(detectB0, detectB1, detectB2, detectA1, detectA2,
                            band.frequency, band.q, sampleRate_);

        for (int i = 0; i < frames; ++i) {
            double l = L[i];
            double r = R[i];
            if (!std::isfinite(l)) l = 0.0;
            if (!std::isfinite(r)) r = 0.0;

            // Detection: band-pass -> smoothed envelope
            double envMax = 0.0;
            for (int ch = 0; ch < 2; ++ch) {
                const double x = (ch == 0) ? l : r;
                const double bp = detectB0 * x
                    + detectB1 * band.dx1[ch] + detectB2 * band.dx2[ch]
                    - detectA1 * band.dy1[ch] - detectA2 * band.dy2[ch];
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
            if (std::abs(band.currentGainDb - band.lastCoeffGainDb) > 0.05) {
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
    }
}

void DynamicEQ::processInterleaved(float* buffer, int frames, int channels) {
    if (!enabled_ || !buffer || frames <= 0 || channels <= 0) return;
    const int n = bandCount_;
    const int chCount = std::min(channels, MAX_CHANNELS);

    for (int b = 0; b < n; ++b) {
        BandState& band = bands_[b];
        if (!band.enabled) {
            if (std::abs(band.currentGainDb) > 1e-4) {
                const double rampStep = band.currentGainDb / frames;
                for (int i = 0; i < frames; ++i) {
                    band.currentGainDb -= rampStep;
                    if (std::abs(band.currentGainDb - band.lastCoeffGainDb) > 0.05) {
                        computeBandCoeffs(band, band.currentGainDb);
                    }
                    for (int ch = 0; ch < chCount; ++ch) {
                        const double x = buffer[i * channels + ch];
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

        double detectB0, detectB1, detectB2, detectA1, detectA2;
        computeDetectCoeffs(detectB0, detectB1, detectB2, detectA1, detectA2,
                            band.frequency, band.q, sampleRate_);

        for (int i = 0; i < frames; ++i) {
            double envMax = 0.0;
            for (int ch = 0; ch < chCount; ++ch) {
                const double x = buffer[i * channels + ch];
                const double bp = detectB0 * x
                    + detectB1 * band.dx1[ch] + detectB2 * band.dx2[ch]
                    - detectA1 * band.dy1[ch] - detectA2 * band.dy2[ch];
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

            if (std::abs(band.currentGainDb - band.lastCoeffGainDb) > 0.05) {
                computeBandCoeffs(band, band.currentGainDb);
            }

            for (int ch = 0; ch < chCount; ++ch) {
                const double x = buffer[i * channels + ch];
                const double y = band.b0 * x + band.b1 * band.x1[ch] + band.b2 * band.x2[ch]
                    - band.a1 * band.y1[ch] - band.a2 * band.y2[ch];
                band.x2[ch] = band.x1[ch];
                band.x1[ch] = x;
                band.y2[ch] = band.y1[ch];
                band.y1[ch] = y;
                buffer[i * channels + ch] = static_cast<float>(y);
            }
        }
    }
}
