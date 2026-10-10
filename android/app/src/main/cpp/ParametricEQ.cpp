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
        bands_[i].smoothedFrequency = kDefaultFrequencies[i];
        bands_[i].q = kDefaultQ[i];
        bands_[i].smoothedQ = kDefaultQ[i];
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
    // Bands outside the current bandCount_ keep old-rate coefficients; force
    // applyParams() to recompute every band that appears in the next snapshot.
    coeffsStale_ = true;
    // FIX M-7: a rate change swaps every band's coefficient set, so the
    // retained TDF-II delay registers (s1_/s2_) belong to the old coefficients
    // and thump on the first block. applyParams only clears state on a
    // structural change (~:120-130), so a pure rate change never clears it
    // otherwise. Mirror SubCrossover/LookaheadLimiter and flush all delay
    // registers after recompute.
    std::memset(s1_, 0, sizeof(s1_));
    std::memset(s2_, 0, sizeof(s2_));
}

void ParametricEQ::setBandCount(int count) {
    bandCount_ = std::clamp(count, 1, MAX_BANDS);
    reset();
}

void ParametricEQ::setDynamicBands(int count, const double* freqs, const double* qs) {
    // FIX M-10: guard the raw freqs pointer. qs is already null-guarded below
    // (qs ? qs[i] : ...), but freqs[i] is dereferenced unconditionally, so a
    // null or empty list would crash.
    if (!freqs || count <= 0) return;
    bandCount_ = std::clamp(count, 1, MAX_BANDS);
    for (int i = 0; i < bandCount_; ++i) {
        bands_[i].frequency = freqs[i];
        bands_[i].smoothedFrequency = freqs[i];
        bands_[i].q = qs ? qs[i] : 1.414;
        bands_[i].smoothedQ = bands_[i].q;
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
    // Direct programmatic set: snap the smoothed freq/Q so coeffs reflect the new
    // band immediately (the snapshot/applyParams path is what sweeps click-free).
    bands_[idx].smoothedFrequency = bands_[idx].frequency;
    bands_[idx].smoothedQ = bands_[idx].q;
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

void ParametricEQ::beginEnableRamp() {
    std::memset(s1_, 0, sizeof(s1_));
    std::memset(s2_, 0, sizeof(s2_));
    std::memset(soloSkipped_, 0, sizeof(soloSkipped_));
    smoothedPreampDb_ = 0.0;
    preampLinear_ = 1.0;
    for (int i = 0; i < bandCount_; ++i) {
        bands_[i].smoothedGainDb = 0.0;
        // Only gain fades in on enable; freq/Q start at target (no sweep).
        bands_[i].smoothedFrequency = bands_[i].frequency;
        bands_[i].smoothedQ = bands_[i].q;
        computeCoeffs(bands_[i], 0.0);
    }
}

void ParametricEQ::beginDisableRamp() {
    // Symmetric to beginEnableRamp: don't clear state or jump to bypass. process()
    // keeps running (see fadeOutActive_) with every gain/preamp smoothing toward
    // unity, then hard-bypasses once the ramp has settled. Settle over ~5 of the
    // 20 ms smoothing time constants (~100 ms) so the gains are within ~0.7% of
    // unity before the stage drops out, which keeps the transition click-free.
    fadeOutActive_ = true;
    fadeOutFrames_ = static_cast<long long>(std::ceil(sampleRate_ * 0.100));
}

void ParametricEQ::setEnabled(bool enabled) {
    if (enabled && !enabled_) {
        fadeOutActive_ = false; // cancel any in-flight disable fade
        beginEnableRamp();
    } else if (!enabled && enabled_) {
        beginDisableRamp();
    }
    enabled_ = enabled;
}

void ParametricEQ::applyParams(const EqParamSet& params) {
    const int newBandCount = std::clamp(params.bandCount, 1, MAX_BANDS);
    // FIX M-3: clear filter delay registers when band count or structure changes
    if (newBandCount != bandCount_) {
        std::memset(s1_, 0, sizeof(s1_));
        std::memset(s2_, 0, sizeof(s2_));
    }
    // A sample-rate change invalidates every retained coefficient set. Consume
    // the flag here (setSampleRate runs immediately before applyParams in the
    // engine) so bands previously outside bandCount_ are recomputed too.
    const bool rateStale = coeffsStale_;
    coeffsStale_ = false;
    if (rateStale) {
        std::memset(s1_, 0, sizeof(s1_));
        std::memset(s2_, 0, sizeof(s2_));
    }
    const bool turningOn = params.enabled && !enabled_;
    const bool turningOff = !params.enabled && enabled_;
    enabled_ = params.enabled;
    targetPreampDb_ = std::clamp(params.preampDb, -30.0, 30.0);
    bandCount_ = newBandCount;

    for (int i = 0; i < bandCount_; ++i) {
        const auto& p = params.bands[i];
        const double newFreq = std::clamp(p.frequency, 10.0, sampleRate_ * 0.499);
        const double newQ = std::clamp(p.q, 0.05, 30.0);
        // Only DISCRETE changes (type/enable/mute, or a rate change) clear state
        // and recompute instantly: those cannot be coefficient-interpolated. A
        // freq/Q change is NOT treated as structural here — clearing state and
        // snapping coeffs on every automation step is exactly what clicks. Instead
        // we just move the smoothing TARGET (bands_[i].frequency / .q) and let the
        // per-block smoother in process() sweep smoothedFrequency/smoothedQ toward
        // it with the filter state preserved, so freq/Q sweeps stay click-free.
        const bool discreteChanged =
            rateStale ||
            p.type != bands_[i].type ||
            p.enabled != bands_[i].enabled ||
            p.mute != bands_[i].mute;
        if (discreteChanged) {
            for (int ch = 0; ch < MAX_CHANNELS; ++ch) {
                s1_[ch][i] = s2_[ch][i] = 0.0;
            }
        }
        bands_[i].frequency = newFreq;              // smoothing target
        bands_[i].targetGainDb = std::clamp(p.gainDb, -30.0, 30.0);
        bands_[i].q = newQ;                          // smoothing target
        bands_[i].type = p.type;
        bands_[i].enabled = p.enabled;
        bands_[i].solo = p.solo;
        bands_[i].mute = p.mute;
        if (discreteChanged) {
            // A discrete switch has no meaningful coefficient interpolation
            // (e.g. peaking<->shelf), so start from the new freq/Q directly.
            bands_[i].smoothedFrequency = newFreq;
            bands_[i].smoothedQ = newQ;
            computeCoeffs(bands_[i], bands_[i].smoothedGainDb);
        }
    }
    if (turningOn) {
        fadeOutActive_ = false;
        beginEnableRamp();
    } else if (turningOff) {
        beginDisableRamp();
    }
}

void ParametricEQ::reset() {
    std::memset(s1_, 0, sizeof(s1_));
    std::memset(s2_, 0, sizeof(s2_));
    std::memset(soloSkipped_, 0, sizeof(soloSkipped_));
    coeffsStale_ = false;
    fadeOutActive_ = false;
    fadeOutFrames_ = 0;
    smoothedPreampDb_ = targetPreampDb_;
    preampLinear_ = std::pow(10.0, smoothedPreampDb_ / 20.0);
    for (int i = 0; i < bandCount_; ++i) {
        bands_[i].smoothedGainDb = bands_[i].targetGainDb;
        bands_[i].smoothedFrequency = bands_[i].frequency;
        bands_[i].smoothedQ = bands_[i].q;
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

    // Coefficients are derived from the per-block SMOOTHED freq/Q (not the raw
    // targets) so freq/Q automation sweeps the biquad continuously instead of
    // jumping. The smoother in process() advances these toward band.frequency/q.
    const double f0 = std::clamp(band.smoothedFrequency, 10.0, sampleRate_ * 0.499);
    const double w0 = 2.0 * M_PI * f0 / sampleRate_;
    const double cosW = std::cos(w0);
    const double sinW = std::sin(w0);
    const double A = std::pow(10.0, gainDb / 40.0);
    const double q = std::max(band.smoothedQ, 0.05);
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
    // leak gain while the stage is off. While a disable fade-out is still in
    // flight (fadeOutActive_) we keep processing so the gains can ramp to unity.
    if (!enabled_ && !fadeOutActive_) return;

    // Keep the real interleave stride; clamp only how many channels we process.
    // Clamping the stride itself garbles any stream wider than MAX_CHANNELS.
    const int stride = channels > 0 ? channels : 1;
    channels = std::clamp(channels, 1, MAX_CHANNELS);

    // One-pole smoother coefficient for ~20ms time constant (tau = 0.020s)
    const double tau = 0.020;
    const double smoothFactor = 1.0 - std::exp(-static_cast<double>(frames) / (sampleRate_ * tau));

    // During a disable fade-out every gain/preamp target is unity (0 dB) so the
    // EQ smoothly approaches dry before it hard-bypasses (see fade countdown
    // below); otherwise they track the user's requested values.
    const double preampTarget = fadeOutActive_ ? 0.0 : targetPreampDb_;

    // Smooth preamp gain
    if (std::abs(smoothedPreampDb_ - preampTarget) > 1e-4) {
        smoothedPreampDb_ += smoothFactor * (preampTarget - smoothedPreampDb_);
        preampLinear_ = std::pow(10.0, smoothedPreampDb_ / 20.0);
    } else {
        smoothedPreampDb_ = preampTarget;
        preampLinear_ = std::pow(10.0, smoothedPreampDb_ / 20.0);
    }

    // Apply smoothed preamp
    if (std::abs(preampLinear_ - 1.0) > 1e-4) {
        const float pLinear = static_cast<float>(preampLinear_);
        for (int f = 0; f < frames; ++f) {
            for (int ch = 0; ch < channels; ++ch) {
                buffer[f * stride + ch] *= pLinear;
            }
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
        // Solo is a runtime mask, NOT a coefficient property: writing
        // band.bypass here used to strand every non-soloed band bypassed after
        // solo was switched off (computeCoeffs only reruns on a structural or
        // gain change, neither of which happens when solo is cleared).
        const bool skip = hasSolo && !band.solo;
        const bool wasSkipped = soloSkipped_[b];
        soloSkipped_[b] = skip;
        if (skip) {
            if (!wasSkipped) {
                for (int ch = 0; ch < MAX_CHANNELS; ++ch) {
                    s1_[ch][b] = s2_[ch][b] = 0.0;
                }
            }
            continue;
        }

        const bool wasBypass = band.bypass;
        // Smooth gain, frequency and Q together so freq/Q automation sweeps the
        // biquad continuously (click-free) just like the gain path. During a
        // disable fade-out the gain target is forced to unity so the band ramps
        // to bypass. Any of the three moving requires a coefficient recompute.
        const double gainTarget = fadeOutActive_ ? 0.0 : band.targetGainDb;
        bool recompute = false;

        if (std::abs(band.smoothedGainDb - gainTarget) > 1e-4) {
            band.smoothedGainDb += smoothFactor * (gainTarget - band.smoothedGainDb);
            recompute = true;
        } else if (band.smoothedGainDb != gainTarget) {
            band.smoothedGainDb = gainTarget;
            recompute = true;
        }

        if (std::abs(band.smoothedFrequency - band.frequency) > 1e-3) {
            band.smoothedFrequency += smoothFactor * (band.frequency - band.smoothedFrequency);
            recompute = true;
        } else if (band.smoothedFrequency != band.frequency) {
            band.smoothedFrequency = band.frequency;
            recompute = true;
        }

        if (std::abs(band.smoothedQ - band.q) > 1e-6) {
            band.smoothedQ += smoothFactor * (band.q - band.smoothedQ);
            recompute = true;
        } else if (band.smoothedQ != band.q) {
            band.smoothedQ = band.q;
            recompute = true;
        }

        if (recompute) {
            computeCoeffs(band, band.smoothedGainDb);
        }

        if ((wasBypass && !band.bypass) || wasSkipped) {
            for (int ch = 0; ch < MAX_CHANNELS; ++ch) {
                s1_[ch][b] = s2_[ch][b] = 0.0;
            }
        }
    }

    // Process biquad cascaded filters per band across all channels (TDF-II)
    for (int b = 0; b < bandCount_; ++b) {
        const auto& band = bands_[b];
        if ((hasSolo && !band.solo) || band.bypass) continue;

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
                    // Snapshot the RUNNING vector state, not the block-start
                    // values still sitting in s1_/s2_ (they are only written
                    // after the frame loop). Reading memory here used to roll
                    // the clean channel's state back to the block start.
                    vst1q_f64(s1_arr, vs1);
                    vst1q_f64(s2_arr, vs2);
                    if (!std::isfinite(x0)) { x0 = 0.0; s1_arr[0] = 0.0; s2_arr[0] = 0.0; }
                    if (!std::isfinite(x1)) { x1 = 0.0; s1_arr[1] = 0.0; s2_arr[1] = 0.0; }
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
                    // Snapshot the RUNNING vector state so zeroing the poisoned
                    // lane does not roll back the clean channel to the block
                    // start (s1_/s2_ are only updated after the frame loop).
                    alignas(16) double s1_cur[2], s2_cur[2];
                    _mm_store_pd(s1_cur, vs1);
                    _mm_store_pd(s2_cur, vs2);
                    if (!std::isfinite(x_arr[0])) { x_arr[0] = 0.0; s1_cur[0] = 0.0; s2_cur[0] = 0.0; }
                    if (!std::isfinite(x_arr[1])) { x_arr[1] = 0.0; s1_cur[1] = 0.0; s2_cur[1] = 0.0; }
                    vs1 = _mm_set_pd(s1_cur[1], s1_cur[0]);
                    vs2 = _mm_set_pd(s2_cur[1], s2_cur[0]);
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
                        chPtr += stride;
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
                    chPtr += stride;
                }

                if (std::abs(s1) < 1e-25 || !std::isfinite(s1)) s1 = 0.0;
                if (std::abs(s2) < 1e-25 || !std::isfinite(s2)) s2 = 0.0;

                s1_[ch][b] = s1;
                s2_[ch][b] = s2;
            }
        }
    }

    // Disable fade-out countdown. The gains above have been ramping toward unity
    // for this block; once enough frames have elapsed for the exponential ramp to
    // settle, drop the stage into true bypass. By then output ≈ dry, so the
    // hard-bypass on the next block introduces no click.
    if (fadeOutActive_) {
        fadeOutFrames_ -= frames;
        if (fadeOutFrames_ <= 0) {
            fadeOutActive_ = false;
            fadeOutFrames_ = 0;
        }
    }
}

