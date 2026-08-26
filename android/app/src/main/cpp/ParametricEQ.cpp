#include "ParametricEQ.h"
#include <cstring>

ParametricEQ::ParametricEQ() {
    static const double defaultFreqs[10] = {
        32.0, 64.0, 125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0, 16000.0
    };
    bandCount_ = 10;
    for (int i = 0; i < 10; ++i) {
        bands_[i].frequency = defaultFreqs[i];
        bands_[i].gainDb = 0.0;
        bands_[i].q = 1.414;
        bands_[i].type = FilterType::Peaking;
        bands_[i].enabled = true;
        computeCoeffs(bands_[i]);
    }
    reset();
}

void ParametricEQ::setSampleRate(double sampleRate) {
    if (sampleRate < 8000.0) sampleRate = 8000.0;
    if (sampleRate > 768000.0) sampleRate = 768000.0;
    sampleRate_ = sampleRate;
    for (int i = 0; i < bandCount_; ++i) {
        computeCoeffs(bands_[i]);
    }
}

void ParametricEQ::setBandCount(int count) {
    bandCount_ = std::max(1, std::min(count, MAX_BANDS));
    reset();
}

void ParametricEQ::setBand(int idx, double freq, double gainDb, double q, FilterType type, bool enabled) {
    if (idx < 0 || idx >= MAX_BANDS) return;
    bands_[idx].frequency = std::max(10.0, std::min(freq, sampleRate_ * 0.499));
    bands_[idx].gainDb = std::max(-30.0, std::min(gainDb, 30.0));
    bands_[idx].q = std::max(0.05, std::min(q, 20.0));
    bands_[idx].type = type;
    bands_[idx].enabled = enabled;
    computeCoeffs(bands_[idx]);
}

void ParametricEQ::setPreamp(double preampDb) {
    preampDb_ = std::max(-30.0, std::min(preampDb, 30.0));
    preampLinear_ = std::pow(10.0, preampDb_ / 20.0);
}

void ParametricEQ::setEnabled(bool enabled) {
    enabled_ = enabled;
}

void ParametricEQ::reset() {
    std::memset(x1_, 0, sizeof(x1_));
    std::memset(x2_, 0, sizeof(x2_));
    std::memset(y1_, 0, sizeof(y1_));
    std::memset(y2_, 0, sizeof(y2_));
}

void ParametricEQ::computeCoeffs(EQBand& band) {
    double freq = std::min(band.frequency, sampleRate_ * 0.499);
    double w0 = 2.0 * M_PI * freq / sampleRate_;
    double cosw0 = std::cos(w0);
    double sinw0 = std::sin(w0);
    double A = std::pow(10.0, band.gainDb / 40.0);
    double alpha = sinw0 / (2.0 * band.q);

    double b0 = 1.0, b1 = 0.0, b2 = 0.0, a0 = 1.0, a1 = 0.0, a2 = 0.0;

    switch (band.type) {
        case FilterType::Peaking:
            b0 = 1.0 + alpha * A;
            b1 = -2.0 * cosw0;
            b2 = 1.0 - alpha * A;
            a0 = 1.0 + alpha / A;
            a1 = -2.0 * cosw0;
            a2 = 1.0 - alpha / A;
            break;

        case FilterType::LowShelf: {
            double sqrtA2alpha = 2.0 * std::sqrt(A) * alpha;
            b0 = A * ((A + 1.0) - (A - 1.0) * cosw0 + sqrtA2alpha);
            b1 = 2.0 * A * ((A - 1.0) - (A + 1.0) * cosw0);
            b2 = A * ((A + 1.0) - (A - 1.0) * cosw0 - sqrtA2alpha);
            a0 = (A + 1.0) + (A - 1.0) * cosw0 + sqrtA2alpha;
            a1 = -2.0 * ((A - 1.0) + (A + 1.0) * cosw0);
            a2 = (A + 1.0) + (A - 1.0) * cosw0 - sqrtA2alpha;
            break;
        }

        case FilterType::HighShelf: {
            double sqrtA2alpha = 2.0 * std::sqrt(A) * alpha;
            b0 = A * ((A + 1.0) + (A - 1.0) * cosw0 + sqrtA2alpha);
            b1 = -2.0 * A * ((A - 1.0) + (A + 1.0) * cosw0);
            b2 = A * ((A + 1.0) + (A - 1.0) * cosw0 - sqrtA2alpha);
            a0 = (A + 1.0) - (A - 1.0) * cosw0 + sqrtA2alpha;
            a1 = 2.0 * ((A - 1.0) - (A + 1.0) * cosw0);
            a2 = (A + 1.0) - (A - 1.0) * cosw0 - sqrtA2alpha;
            break;
        }

        case FilterType::LowPass:
            b0 = (1.0 - cosw0) / 2.0;
            b1 = 1.0 - cosw0;
            b2 = (1.0 - cosw0) / 2.0;
            a0 = 1.0 + alpha;
            a1 = -2.0 * cosw0;
            a2 = 1.0 - alpha;
            break;

        case FilterType::HighPass:
            b0 = (1.0 + cosw0) / 2.0;
            b1 = -(1.0 + cosw0);
            b2 = (1.0 + cosw0) / 2.0;
            a0 = 1.0 + alpha;
            a1 = -2.0 * cosw0;
            a2 = 1.0 - alpha;
            break;
    }

    band.coeffs.b0 = b0 / a0;
    band.coeffs.b1 = b1 / a0;
    band.coeffs.b2 = b2 / a0;
    band.coeffs.a1 = a1 / a0;
    band.coeffs.a2 = a2 / a0;
}

void ParametricEQ::process(const float* in, float* out, int frames, int channels) {
    if (!in || !out || frames <= 0 || channels <= 0) return;
    int chCount = std::min(channels, MAX_CHANNELS);
    if (!enabled_) {
        if (in != out) {
            std::memcpy(out, in, frames * channels * sizeof(float));
        }
        return;
    }

    for (int f = 0; f < frames; ++f) {
        for (int ch = 0; ch < chCount; ++ch) {
            double sample = in[f * channels + ch] * preampLinear_;
            for (int b = 0; b < bandCount_; ++b) {
                if (!bands_[b].enabled || std::abs(bands_[b].gainDb) < 0.01) {
                    continue;
                }
                const auto& c = bands_[b].coeffs;
                double y = c.b0 * sample
                         + c.b1 * x1_[ch][b] + c.b2 * x2_[ch][b]
                         - c.a1 * y1_[ch][b] - c.a2 * y2_[ch][b];
                x2_[ch][b] = x1_[ch][b];
                x1_[ch][b] = sample;
                y2_[ch][b] = y1_[ch][b];
                y1_[ch][b] = y;
                sample = y;
            }
            out[f * channels + ch] = static_cast<float>(sample);
        }
    }
}

void ParametricEQ::processInterleaved(float* buffer, int frames, int channels) {
    process(buffer, buffer, frames, channels);
}
