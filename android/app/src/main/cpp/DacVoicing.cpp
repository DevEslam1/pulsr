// android/app/src/main/cpp/DacVoicing.cpp
#include "DacVoicing.h"
#include "FftUtil.h"

#include <algorithm>
#include <cmath>
#include <cstring>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

namespace {

// Even-order injection depth at voicingAmount = 1.0: a full-scale sine gets a
// 2nd harmonic around -15 dB, which is already a bold "tube DAC" coloration.
constexpr float kVoicingDepth = 0.35f;
// Base Nyquist as a fraction of the 4x oversampled rate.
constexpr double kFcNorm = 0.125;

double sincPi(double x) {
    if (std::abs(x) < 1e-9) return 1.0;
    return std::sin(M_PI * x) / (M_PI * x);
}

} // namespace

std::vector<float> DacVoicing::designPrototype(int character, double fcNorm, int taps) {
    if (taps <= 0) return {};
    if (character == MinimumPhase) {
        const std::vector<float> sharp = designPrototype(Sharp, fcNorm, taps);
        return toMinimumPhase(sharp, taps);
    }

    // Slow drops the cutoff to 0.75 of base Nyquist and uses a Hann window, so
    // the passband droops gently well below Nyquist (the NOS presentation).
    // Sharp keeps the full-bandwidth Blackman-Harris design used elsewhere in
    // the codebase (steep transition, deep stopband, symmetric pre-ringing).
    const double fc = (character == Slow) ? fcNorm * 0.75 : fcNorm;
    std::vector<float> h(static_cast<size_t>(taps));
    const double half = taps / 2.0;
    double sum = 0.0;
    for (int n = 0; n < taps; ++n) {
        const double t = static_cast<double>(n) - (taps - 1) / 2.0;
        const double sincV = sincPi(2.0 * fc * t);
        double w;
        if (character == Slow) {
            w = 0.5 - 0.5 * std::cos(2.0 * M_PI * (static_cast<double>(n) + 0.5) /
                                     static_cast<double>(taps));
        } else {
            // 4-term Blackman-Harris, same coefficients as SincResampler.
            const double nn = (t + half) / (2.0 * half);
            const double twoPiN = 2.0 * M_PI * nn;
            w = 0.35875 - 0.48829 * std::cos(twoPiN) + 0.14128 * std::cos(2.0 * twoPiN) -
                0.01168 * std::cos(3.0 * twoPiN);
        }
        h[static_cast<size_t>(n)] = static_cast<float>(2.0 * fc * sincV * w);
        sum += h[static_cast<size_t>(n)];
    }
    if (std::abs(sum) > 1e-9) {
        for (float& v : h) v = static_cast<float>(v / sum);
    }
    return h;
}

std::vector<float> DacVoicing::toMinimumPhase(const std::vector<float>& prototype, int outLen) {
    if (prototype.empty() || outLen <= 0) return {};
    constexpr int N = 512; // power of two, >= 4x the prototype length

    // 1) Magnitude response of the prototype on the N-point grid.
    std::vector<FftUtil::Complex> spec(static_cast<size_t>(N), FftUtil::Complex(0.0f, 0.0f));
    for (size_t i = 0; i < prototype.size() && i < static_cast<size_t>(N); ++i) {
        spec[i] = FftUtil::Complex(prototype[i], 0.0f);
    }
    FftUtil::fft(spec, false);
    float maxMag = 0.0f;
    for (int k = 0; k < N; ++k) {
        maxMag = std::max(maxMag, std::abs(spec[static_cast<size_t>(k)]));
    }
    if (maxMag <= 0.0f) return std::vector<float>(static_cast<size_t>(outLen), 0.0f);
    const float magFloor = maxMag * 1e-5f; // ~-100 dB: keep log finite in the stopband

    // 2) Real cepstrum: IFFT of the log magnitude.
    std::vector<FftUtil::Complex> cep(static_cast<size_t>(N));
    for (int k = 0; k < N; ++k) {
        cep[static_cast<size_t>(k)] = FftUtil::Complex(
            std::log(std::max(std::abs(spec[static_cast<size_t>(k)]), magFloor)), 0.0f);
    }
    FftUtil::fft(cep, true);

    // 3) Fold the cepstrum (keep n=0, double 1..N/2, zero the rest). The FFT of
    //    the folded cepstrum is log|H| + j*phi_min: the Hilbert-transform pair
    //    that makes the magnitude realizable with all-post-ringing energy.
    cep[0] = FftUtil::Complex(cep[0].real(), 0.0f);
    for (int n = 1; n < N / 2; ++n) {
        cep[static_cast<size_t>(n)] *= 2.0f;
    }
    cep[static_cast<size_t>(N / 2)] = FftUtil::Complex(
        cep[static_cast<size_t>(N / 2)].real(), 0.0f);
    for (int n = N / 2 + 1; n < N; ++n) {
        cep[static_cast<size_t>(n)] = FftUtil::Complex(0.0f, 0.0f);
    }
    FftUtil::fft(cep, false);

    // 4) Exponentiate back to a spectrum and invert to the time domain.
    for (int k = 0; k < N; ++k) {
        cep[static_cast<size_t>(k)] = std::exp(cep[static_cast<size_t>(k)]);
    }
    FftUtil::fft(cep, true);

    std::vector<float> h(static_cast<size_t>(outLen), 0.0f);
    double sum = 0.0;
    for (int n = 0; n < outLen; ++n) {
        h[static_cast<size_t>(n)] = cep[static_cast<size_t>(n)].real();
        sum += h[static_cast<size_t>(n)];
    }
    // Truncation to outLen loses a little DC gain; restore unity.
    if (std::abs(sum) > 1e-6) {
        for (float& v : h) v = static_cast<float>(v / sum);
    }
    return h;
}

void DacVoicing::buildCharacter(int character, float table[OVERSAMPLE][TAPS_PER_PHASE]) {
    const std::vector<float> h = designPrototype(character, kFcNorm, FIR_TAPS);
    for (int p = 0; p < OVERSAMPLE; ++p) {
        float sum = 0.0f;
        for (int t = 0; t < TAPS_PER_PHASE; ++t) {
            const float c = (static_cast<size_t>(t * OVERSAMPLE + p) < h.size())
                                ? h[static_cast<size_t>(t * OVERSAMPLE + p)]
                                : 0.0f;
            table[p][t] = c;
            sum += c;
        }
        // Per-phase unity DC so a constant input interpolates to the same
        // constant and the decimation sum (OVERSAMPLE phases) divides back to 1.
        if (std::abs(sum) > 1e-6f) {
            const float inv = 1.0f / sum;
            for (int t = 0; t < TAPS_PER_PHASE; ++t) table[p][t] *= inv;
        }
    }
}

int DacVoicing::measureGroupDelay(const float table[OVERSAMPLE][TAPS_PER_PHASE]) {
    // Simulate the exact interpolate->shape(skip)->decimate round trip with a
    // unit impulse and find the output peak position. This is the same
    // "measured peak" approach the saturation stage's DRY_DELAY documents.
    float hist[TAPS_PER_PHASE] = {};
    float ring[FIR_TAPS] = {};
    int idx = 0;
    double peak = 0.0;
    int peakN = 0;
    const int frames = FIR_TAPS + MAX_DELAY;
    for (int n = 0; n < frames; ++n) {
        const float x = (n == 0) ? 1.0f : 0.0f;
        for (int t = TAPS_PER_PHASE - 1; t > 0; --t) hist[t] = hist[t - 1];
        hist[0] = x;
        for (int p = 0; p < OVERSAMPLE; ++p) {
            float os = 0.0f;
            for (int t = 0; t < TAPS_PER_PHASE; ++t) os += table[p][t] * hist[t];
            ring[(idx + p) % FIR_TAPS] = os;
        }
        float wet = 0.0f;
        for (int k = 0; k < FIR_TAPS; ++k) {
            const float c = table[k % OVERSAMPLE][k / OVERSAMPLE];
            const int hIdx = (idx + OVERSAMPLE - 1 - k + FIR_TAPS * 2) % FIR_TAPS;
            wet += c * ring[hIdx];
        }
        wet *= 1.0f / static_cast<float>(OVERSAMPLE);
        if (std::abs(static_cast<double>(wet)) > peak) {
            peak = std::abs(static_cast<double>(wet));
            peakN = n;
        }
        idx = (idx + OVERSAMPLE) % FIR_TAPS;
    }
    return std::clamp(peakN, 0, MAX_DELAY - 1);
}

DacVoicing::DacVoicing() {
    int maxDelay = 0;
    int measured[3] = {};
    for (int c = 0; c < 3; ++c) {
        buildCharacter(c, tables_[c]);
        measured[c] = measureGroupDelay(tables_[c]);
        maxDelay = std::max(maxDelay, measured[c]);
    }
    delayBase_ = maxDelay;
    for (int c = 0; c < 3; ++c) {
        padAmount_[c] = maxDelay - measured[c];
    }
    setSampleRate(48000.0);
}

void DacVoicing::setSampleRate(double sampleRate) {
    if (!(sampleRate > 0.0)) return;
    sampleRate_ = sampleRate;
    // ~10 Hz DC blocker pole at the 4x oversampled rate.
    dcCoeffOs_ = static_cast<float>(
        std::exp(-2.0 * M_PI * 10.0 / (sampleRate * OVERSAMPLE)));
}

void DacVoicing::applyParams(const DacVoicingParamSet& params) {
    character_ = std::clamp(params.character, 0, 2);
    voicingAmount_ = std::clamp(params.voicingAmount, 0.0, 1.0);
}

void DacVoicing::setEnabled(bool enabled) {
    if (enabled && !enabled_ && smoothedEnable_ <= 1e-4f) {
        reset();
    }
    enabled_ = enabled;
}

bool DacVoicing::isRamping() const {
    const float target = enabled_ ? 1.0f : 0.0f;
    return std::abs(smoothedEnable_ - target) > 1e-4f;
}

int DacVoicing::getLatencyFrames() const {
    return (enabled_ || smoothedEnable_ > 1e-4f) ? delayBase_ : 0;
}

void DacVoicing::reset() {
    std::memset(inHistory_, 0, sizeof(inHistory_));
    std::memset(decimHistory_, 0, sizeof(decimHistory_));
    std::memset(dryDelay_, 0, sizeof(dryDelay_));
    std::memset(wetPad_, 0, sizeof(wetPad_));
    std::memset(sqDcX_, 0, sizeof(sqDcX_));
    std::memset(sqDcY_, 0, sizeof(sqDcY_));
    decimIdx_ = 0;
    dryPos_ = 0;
    smoothedEnable_ = 0.0f;
    smoothedVoicing_ = 0.0f;
}

void DacVoicing::processInterleaved(float* buffer, int frames, int channels) {
    if (!buffer || frames <= 0 || channels <= 0) return;
    channels = std::min(channels, MAX_CHANNELS);

    // Fully bypassed: bit-exact passthrough (the engine may still call the
    // stage on a raw activeStages bit with the enabled flag off).
    if (!enabled_ && smoothedEnable_ <= 1e-4f) return;

    const float* table = &tables_[character_][0][0];
    const int pad = padAmount_[character_];
    const float targetEnable = enabled_ ? 1.0f : 0.0f;
    // 20 ms ramp, per frame.
    const float step = static_cast<float>(
        1.0 - std::exp(-1.0 / (sampleRate_ * 0.020)));

    for (int f = 0; f < frames; ++f) {
        smoothedEnable_ += step * (targetEnable - smoothedEnable_);
        smoothedVoicing_ += step * (static_cast<float>(voicingAmount_) - smoothedVoicing_);
        if (std::abs(smoothedEnable_ - targetEnable) < 1e-5f) smoothedEnable_ = targetEnable;
        if (std::abs(smoothedVoicing_ - static_cast<float>(voicingAmount_)) < 1e-6f) {
            smoothedVoicing_ = static_cast<float>(voicingAmount_);
        }
        const float s = smoothedEnable_;
        const float voicing = smoothedVoicing_;

        for (int ch = 0; ch < channels; ++ch) {
            float in = buffer[f * channels + ch];
            if (!std::isfinite(in)) in = 0.0f;

            const int dryRead = (dryPos_ - delayBase_ + MAX_DELAY * 2) % MAX_DELAY;
            const float dryOut = dryDelay_[ch][dryRead];
            dryDelay_[ch][dryPos_] = in;

            float* hist = inHistory_[ch];
            for (int t = TAPS_PER_PHASE - 1; t > 0; --t) hist[t] = hist[t - 1];
            hist[0] = in;

            float* ring = decimHistory_[ch];
            for (int p = 0; p < OVERSAMPLE; ++p) {
                float os = 0.0f;
                const float* phase = table + p * TAPS_PER_PHASE;
                for (int t = 0; t < TAPS_PER_PHASE; ++t) os += phase[t] * hist[t];
                if (voicing > 1e-5f) {
                    // Even-order (2nd-harmonic) injection: the squared term is
                    // DC-blocked at the oversampled rate so it adds harmonics
                    // without a DC offset. Images fold above base Nyquist and
                    // are removed by the decimation filter.
                    const float sq = os * os;
                    const float y = sq - sqDcX_[ch] + dcCoeffOs_ * sqDcY_[ch];
                    sqDcX_[ch] = sq;
                    sqDcY_[ch] = y;
                    if (!std::isfinite(sqDcY_[ch])) {
                        sqDcX_[ch] = 0.0f;
                        sqDcY_[ch] = 0.0f;
                    } else {
                        os += kVoicingDepth * voicing * y;
                    }
                }
                ring[(decimIdx_ + p) % FIR_TAPS] = os;
            }

            float wet = 0.0f;
            for (int k = 0; k < FIR_TAPS; ++k) {
                const float c = table[k % OVERSAMPLE * TAPS_PER_PHASE + k / OVERSAMPLE];
                const int hIdx = (decimIdx_ + OVERSAMPLE - 1 - k + FIR_TAPS * 2) % FIR_TAPS;
                wet += c * ring[hIdx];
            }
            wet *= 1.0f / static_cast<float>(OVERSAMPLE);
            if (!std::isfinite(wet)) wet = 0.0f;

            if (pad > 0) {
                const int padRead = (dryPos_ - pad + MAX_DELAY * 2) % MAX_DELAY;
                const float delayed = wetPad_[ch][padRead];
                wetPad_[ch][dryPos_] = wet;
                wet = delayed;
            }

            buffer[f * channels + ch] = s * wet + (1.0f - s) * dryOut;
        }

        decimIdx_ = (decimIdx_ + OVERSAMPLE) % FIR_TAPS;
        dryPos_ = (dryPos_ + 1) % MAX_DELAY;
    }
}
