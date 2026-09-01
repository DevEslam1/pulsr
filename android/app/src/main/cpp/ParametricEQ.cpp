// android/app/src/main/cpp/ParametricEQ.cpp
#include "ParametricEQ.h"
#include <cstring>
#include <cmath>

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
    enabled_ = params.enabled;
    targetPreampDb_ = std::clamp(params.preampDb, -30.0, 30.0);
    bandCount_ = std::clamp(params.bandCount, 1, MAX_BANDS);

    for (int i = 0; i < bandCount_; ++i) {
        const auto& p = params.bands[i];
        bands_[i].frequency = std::clamp(p.frequency, 10.0, sampleRate_ * 0.499);
        bands_[i].targetGainDb = std::clamp(p.gainDb, -30.0, 30.0);
        bands_[i].q = std::clamp(p.q, 0.05, 30.0);
        bands_[i].type = p.type;
        bands_[i].enabled = p.enabled;
        bands_[i].solo = p.solo;
        bands_[i].mute = p.mute;
        computeCoeffs(bands_[i], bands_[i].smoothedGainDb);
    }
}

void ParametricEQ::reset() {
    std::memset(x1_, 0, sizeof(x1_));
    std::memset(x2_, 0, sizeof(x2_));
    std::memset(y1_, 0, sizeof(y1_));
    std::memset(y2_, 0, sizeof(y2_));
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
    if (!enabled_ && std::abs(targetPreampDb_) < 0.001 && std::abs(smoothedPreampDb_) < 0.001) {
        return;
    }

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

    if (!enabled_) return;

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
                    x1_[ch][b] = x2_[ch][b] = 0.0;
                    y1_[ch][b] = y2_[ch][b] = 0.0;
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
                x1_[ch][b] = x2_[ch][b] = 0.0;
                y1_[ch][b] = y2_[ch][b] = 0.0;
            }
        }
    }

    // Process biquad cascaded filters per band across all channels
    for (int b = 0; b < bandCount_; ++b) {
        const auto& band = bands_[b];
        if (band.bypass) continue;

        const double b0 = band.coeffs.b0;
        const double b1 = band.coeffs.b1;
        const double b2 = band.coeffs.b2;
        const double a1 = band.coeffs.a1;
        const double a2 = band.coeffs.a2;

        for (int ch = 0; ch < channels; ++ch) {
            double x1 = x1_[ch][b];
            double x2 = x2_[ch][b];
            double y1 = y1_[ch][b];
            double y2 = y2_[ch][b];

            float* chPtr = buffer + ch;
            for (int f = 0; f < frames; ++f) {
                const double x0 = static_cast<double>(*chPtr);
                if (!std::isfinite(x0)) {
                    *chPtr = 0.0f;
                    x1 = 0.0;
                    x2 = 0.0;
                    y1 = 0.0;
                    y2 = 0.0;
                    chPtr += channels;
                    continue;
                }

                double y0 = b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;

                if (!std::isfinite(y0)) {
                    // Filter instability/blowup detected — reset biquad state registers immediately
                    x1 = 0.0;
                    x2 = 0.0;
                    y1 = 0.0;
                    y2 = 0.0;
                    y0 = x0; // Fallback to passthrough for corrupted frame
                } else {
                    x2 = x1;
                    x1 = x0;
                    y2 = y1;
                    y1 = y0;
                }

                *chPtr = static_cast<float>(y0);
                chPtr += channels;
            }

            // Flush denormals & ensure state is strictly finite
            if (std::abs(y1) < 1e-25 || !std::isfinite(y1)) y1 = 0.0;
            if (std::abs(y2) < 1e-25 || !std::isfinite(y2)) y2 = 0.0;
            if (std::abs(x1) < 1e-25 || !std::isfinite(x1)) x1 = 0.0;
            if (std::abs(x2) < 1e-25 || !std::isfinite(x2)) x2 = 0.0;

            x1_[ch][b] = x1;
            x2_[ch][b] = x2;
            y1_[ch][b] = y1;
            y2_[ch][b] = y2;
        }
    }
}

