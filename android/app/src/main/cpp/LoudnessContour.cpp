// android/app/src/main/cpp/LoudnessContour.cpp
#include "LoudnessContour.h"
#include <cstring>
#include <cmath>

#if defined(__aarch64__) || defined(_M_ARM64)
#include <arm_neon.h>
#define PULSR_HAS_NEON 1
#elif defined(__x86_64__) || defined(_M_X64)
#include <emmintrin.h>
#define PULSR_HAS_SSE2 1
#endif

LoudnessContour::LoudnessContour() {
    setSampleRate(48000.0);
    configure(0.0, 1.0);
}

void LoudnessContour::setSampleRate(double sampleRate) {
    if (sampleRate < 8000.0) sampleRate = 8000.0;
    if (sampleRate > 768000.0) sampleRate = 768000.0;
    sampleRate_ = sampleRate;
    updateTargetGains();
    // Re-derive biquads from current (smoothed) gains at the new rate
    for (int ch = 0; ch < MAX_CHANNELS; ++ch) {
        computeLowShelf(bass_[ch], kBassShelfHz, currentBassDb_, sampleRate_);
        computeHighShelf(treble_[ch], kTrebleShelfHz, currentTrebleDb_, sampleRate_);
    }
}

void LoudnessContour::configure(double intensity, double volumeLinear) {
    intensity_ = std::clamp(intensity, 0.0, 1.0);
    volumeLinear_ = std::clamp(volumeLinear, 0.0, 1.0);
    updateTargetGains();
}

void LoudnessContour::applyParams(const LoudnessContourParamSet& params) {
    enabled_ = params.enabled;
    configure(params.intensity, params.volumeLinear);
}

void LoudnessContour::updateTargetGains() {
    if (!enabled_) {
        targetBassDb_ = 0.0;
        targetTrebleDb_ = 0.0;
        return;
    }
    // Equal-loudness approximation: lift grows as (1 - volume)^1.5 so the
    // contour is most active at low listening levels and vanishes at unity.
    const double loudnessWeight = std::pow(std::clamp(1.0 - volumeLinear_, 0.0, 1.0), 1.5);
    targetBassDb_ = intensity_ * kBassMaxDb * loudnessWeight;
    targetTrebleDb_ = intensity_ * kTrebleMaxDb * loudnessWeight;
}

void LoudnessContour::rampTowardTarget(int frames) {
    // 50 ms time constant exponential smoothing
    const double tauSeconds = 0.050;
    const double coeff = 1.0 - std::exp(-static_cast<double>(frames) / (sampleRate_ * tauSeconds));

    if (std::abs(targetBassDb_ - currentBassDb_) < 1e-4 && std::abs(targetTrebleDb_ - currentTrebleDb_) < 1e-4) {
        currentBassDb_ = targetBassDb_;
        currentTrebleDb_ = targetTrebleDb_;
        return;
    }
    currentBassDb_ += coeff * (targetBassDb_ - currentBassDb_);
    currentTrebleDb_ += coeff * (targetTrebleDb_ - currentTrebleDb_);
}

void LoudnessContour::reset() {
    std::memset(bass_, 0, sizeof(bass_));
    std::memset(treble_, 0, sizeof(treble_));
    currentBassDb_ = targetBassDb_;
    currentTrebleDb_ = targetTrebleDb_;
    lastComputedBassDb_ = currentBassDb_;
    lastComputedTrebleDb_ = currentTrebleDb_;
    for (int ch = 0; ch < MAX_CHANNELS; ++ch) {
        computeLowShelf(bass_[ch], kBassShelfHz, currentBassDb_, sampleRate_);
        computeHighShelf(treble_[ch], kTrebleShelfHz, currentTrebleDb_, sampleRate_);
    }
}

void LoudnessContour::computeLowShelf(Biquad& bq, double f0, double gainDb, double fs) {
    const double A = std::pow(10.0, gainDb / 40.0);
    const double w0 = 2.0 * M_PI * f0 / fs;
    const double cw = std::cos(w0), sw = std::sin(w0);
    const double alpha = sw / 2.0 * std::sqrt((A + 1.0 / A) * (1.0 / 0.85 - 1.0) + 2.0);
    const double twoSqrtA = 2.0 * std::sqrt(A) * alpha;
    const double a0 = (A + 1.0) + (A - 1.0) * cw + twoSqrtA;
    bq.b0 = A * ((A + 1.0) - (A - 1.0) * cw + twoSqrtA) / a0;
    bq.b1 = 2.0 * A * ((A - 1.0) - (A + 1.0) * cw) / a0;
    bq.b2 = A * ((A + 1.0) - (A - 1.0) * cw - twoSqrtA) / a0;
    bq.a1 = -2.0 * ((A - 1.0) + (A + 1.0) * cw) / a0;
    bq.a2 = ((A + 1.0) + (A - 1.0) * cw - twoSqrtA) / a0;
}

void LoudnessContour::computeHighShelf(Biquad& bq, double f0, double gainDb, double fs) {
    const double A = std::pow(10.0, gainDb / 40.0);
    const double w0 = 2.0 * M_PI * f0 / fs;
    const double cw = std::cos(w0), sw = std::sin(w0);
    const double alpha = sw / 2.0 * std::sqrt((A + 1.0 / A) * (1.0 / 0.85 - 1.0) + 2.0);
    const double twoSqrtA = 2.0 * std::sqrt(A) * alpha;
    const double a0 = (A + 1.0) - (A - 1.0) * cw + twoSqrtA;
    bq.b0 = A * ((A + 1.0) + (A - 1.0) * cw + twoSqrtA) / a0;
    bq.b1 = -2.0 * A * ((A - 1.0) + (A + 1.0) * cw) / a0;
    bq.b2 = A * ((A + 1.0) + (A - 1.0) * cw - twoSqrtA) / a0;
    bq.a1 = 2.0 * ((A - 1.0) - (A + 1.0) * cw) / a0;
    bq.a2 = ((A + 1.0) - (A - 1.0) * cw - twoSqrtA) / a0;
}

void LoudnessContour::process(float* L, float* R, int frames) {
    if (!L || !R || frames <= 0) return;
    if (!enabled_ && std::abs(currentBassDb_) < 1e-4 && std::abs(currentTrebleDb_) < 1e-4) return;
    rampTowardTarget(frames);
    if (std::abs(currentBassDb_) < 1e-6 && std::abs(currentTrebleDb_) < 1e-6) return;

    if (std::abs(currentBassDb_ - lastComputedBassDb_) > 0.01 ||
        std::abs(currentTrebleDb_ - lastComputedTrebleDb_) > 0.01) {
        Biquad tempBass, tempTreble;
        computeLowShelf(tempBass, kBassShelfHz, currentBassDb_, sampleRate_);
        computeHighShelf(tempTreble, kTrebleShelfHz, currentTrebleDb_, sampleRate_);
        for (int ch = 0; ch < MAX_CHANNELS; ++ch) {
            bass_[ch].b0 = tempBass.b0;
            bass_[ch].b1 = tempBass.b1;
            bass_[ch].b2 = tempBass.b2;
            bass_[ch].a1 = tempBass.a1;
            bass_[ch].a2 = tempBass.a2;

            treble_[ch].b0 = tempTreble.b0;
            treble_[ch].b1 = tempTreble.b1;
            treble_[ch].b2 = tempTreble.b2;
            treble_[ch].a1 = tempTreble.a1;
            treble_[ch].a2 = tempTreble.a2;
        }
        lastComputedBassDb_ = currentBassDb_;
        lastComputedTrebleDb_ = currentTrebleDb_;
    }

    for (int i = 0; i < frames; ++i) {
        L[i] = bass_[0].process(treble_[0].process(L[i]));
        R[i] = bass_[1].process(treble_[1].process(R[i]));
    }
}

void LoudnessContour::processInterleaved(float* buffer, int frames, int channels) {
    if (!buffer || frames <= 0 || channels <= 0) return;
    if (!enabled_ && std::abs(currentBassDb_) < 1e-4 && std::abs(currentTrebleDb_) < 1e-4) return;
    rampTowardTarget(frames);
    if (std::abs(currentBassDb_) < 1e-6 && std::abs(currentTrebleDb_) < 1e-6) return;

    if (std::abs(currentBassDb_ - lastComputedBassDb_) > 0.01 ||
        std::abs(currentTrebleDb_ - lastComputedTrebleDb_) > 0.01) {
        Biquad tempBass, tempTreble;
        computeLowShelf(tempBass, kBassShelfHz, currentBassDb_, sampleRate_);
        computeHighShelf(tempTreble, kTrebleShelfHz, currentTrebleDb_, sampleRate_);
        for (int ch = 0; ch < MAX_CHANNELS; ++ch) {
            bass_[ch].b0 = tempBass.b0;
            bass_[ch].b1 = tempBass.b1;
            bass_[ch].b2 = tempBass.b2;
            bass_[ch].a1 = tempBass.a1;
            bass_[ch].a2 = tempBass.a2;

            treble_[ch].b0 = tempTreble.b0;
            treble_[ch].b1 = tempTreble.b1;
            treble_[ch].b2 = tempTreble.b2;
            treble_[ch].a1 = tempTreble.a1;
            treble_[ch].a2 = tempTreble.a2;
        }
        lastComputedBassDb_ = currentBassDb_;
        lastComputedTrebleDb_ = currentTrebleDb_;
    }

    if (channels == 2) {
#if defined(PULSR_HAS_NEON) && (defined(__aarch64__) || defined(_M_ARM64))
        const float64x2_t tb0 = vdupq_n_f64(treble_[0].b0);
        const float64x2_t tb1 = vdupq_n_f64(treble_[0].b1);
        const float64x2_t tb2 = vdupq_n_f64(treble_[0].b2);
        const float64x2_t ta1 = vdupq_n_f64(treble_[0].a1);
        const float64x2_t ta2 = vdupq_n_f64(treble_[0].a2);

        const float64x2_t bb0 = vdupq_n_f64(bass_[0].b0);
        const float64x2_t bb1 = vdupq_n_f64(bass_[0].b1);
        const float64x2_t bb2 = vdupq_n_f64(bass_[0].b2);
        const float64x2_t ba1 = vdupq_n_f64(bass_[0].a1);
        const float64x2_t ba2 = vdupq_n_f64(bass_[0].a2);

        float64x2_t tx1 = { treble_[0].x1, treble_[1].x1 };
        float64x2_t tx2 = { treble_[0].x2, treble_[1].x2 };
        float64x2_t ty1 = { treble_[0].y1, treble_[1].y1 };
        float64x2_t ty2 = { treble_[0].y2, treble_[1].y2 };

        float64x2_t bx1 = { bass_[0].x1, bass_[1].x1 };
        float64x2_t bx2 = { bass_[0].x2, bass_[1].x2 };
        float64x2_t by1 = { bass_[0].y1, bass_[1].y1 };
        float64x2_t by2 = { bass_[0].y2, bass_[1].y2 };

        for (int i = 0; i < frames; ++i) {
            double l = buffer[i * 2];
            double r = buffer[i * 2 + 1];
            if (!std::isfinite(l)) l = 0.0;
            if (!std::isfinite(r)) r = 0.0;
            float64x2_t vx = { l, r };

            // Treble shelf biquad: y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            float64x2_t ty = vsubq_f64(
                vaddq_f64(vmulq_f64(tb0, vx), vaddq_f64(vmulq_f64(tb1, tx1), vmulq_f64(tb2, tx2))),
                vaddq_f64(vmulq_f64(ta1, ty1), vmulq_f64(ta2, ty2))
            );
            tx2 = tx1; tx1 = vx;
            ty2 = ty1; ty1 = ty;

            // Bass shelf biquad: y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            float64x2_t by = vsubq_f64(
                vaddq_f64(vmulq_f64(bb0, ty), vaddq_f64(vmulq_f64(bb1, bx1), vmulq_f64(bb2, bx2))),
                vaddq_f64(vmulq_f64(ba1, by1), vmulq_f64(ba2, by2))
            );
            bx2 = bx1; bx1 = ty;
            by2 = by1; by1 = by;

            buffer[i * 2] = static_cast<float>(vgetq_lane_f64(by, 0));
            buffer[i * 2 + 1] = static_cast<float>(vgetq_lane_f64(by, 1));
        }

        treble_[0].x1 = vgetq_lane_f64(tx1, 0); treble_[1].x1 = vgetq_lane_f64(tx1, 1);
        treble_[0].x2 = vgetq_lane_f64(tx2, 0); treble_[1].x2 = vgetq_lane_f64(tx2, 1);
        treble_[0].y1 = vgetq_lane_f64(ty1, 0); treble_[1].y1 = vgetq_lane_f64(ty1, 1);
        treble_[0].y2 = vgetq_lane_f64(ty2, 0); treble_[1].y2 = vgetq_lane_f64(ty2, 1);

        bass_[0].x1 = vgetq_lane_f64(bx1, 0); bass_[1].x1 = vgetq_lane_f64(bx1, 1);
        bass_[0].x2 = vgetq_lane_f64(bx2, 0); bass_[1].x2 = vgetq_lane_f64(bx2, 1);
        bass_[0].y1 = vgetq_lane_f64(by1, 0); bass_[1].y1 = vgetq_lane_f64(by1, 1);
        bass_[0].y2 = vgetq_lane_f64(by2, 0); bass_[1].y2 = vgetq_lane_f64(by2, 1);
        return;
#elif defined(PULSR_HAS_SSE2)
        const __m128d tb0 = _mm_set1_pd(treble_[0].b0);
        const __m128d tb1 = _mm_set1_pd(treble_[0].b1);
        const __m128d tb2 = _mm_set1_pd(treble_[0].b2);
        const __m128d ta1 = _mm_set1_pd(treble_[0].a1);
        const __m128d ta2 = _mm_set1_pd(treble_[0].a2);

        const __m128d bb0 = _mm_set1_pd(bass_[0].b0);
        const __m128d bb1 = _mm_set1_pd(bass_[0].b1);
        const __m128d bb2 = _mm_set1_pd(bass_[0].b2);
        const __m128d ba1 = _mm_set1_pd(bass_[0].a1);
        const __m128d ba2 = _mm_set1_pd(bass_[0].a2);

        __m128d tx1 = _mm_set_pd(treble_[1].x1, treble_[0].x1);
        __m128d tx2 = _mm_set_pd(treble_[1].x2, treble_[0].x2);
        __m128d ty1 = _mm_set_pd(treble_[1].y1, treble_[0].y1);
        __m128d ty2 = _mm_set_pd(treble_[1].y2, treble_[0].y2);

        __m128d bx1 = _mm_set_pd(bass_[1].x1, bass_[0].x1);
        __m128d bx2 = _mm_set_pd(bass_[1].x2, bass_[0].x2);
        __m128d by1 = _mm_set_pd(bass_[1].y1, bass_[0].y1);
        __m128d by2 = _mm_set_pd(bass_[1].y2, bass_[0].y2);

        for (int i = 0; i < frames; ++i) {
            double l = buffer[i * 2];
            double r = buffer[i * 2 + 1];
            if (!std::isfinite(l)) l = 0.0;
            if (!std::isfinite(r)) r = 0.0;
            __m128d vx = _mm_set_pd(r, l);

            __m128d ty = _mm_sub_pd(
                _mm_add_pd(_mm_mul_pd(tb0, vx), _mm_add_pd(_mm_mul_pd(tb1, tx1), _mm_mul_pd(tb2, tx2))),
                _mm_add_pd(_mm_mul_pd(ta1, ty1), _mm_mul_pd(ta2, ty2))
            );
            tx2 = tx1; tx1 = vx;
            ty2 = ty1; ty1 = ty;

            __m128d by = _mm_sub_pd(
                _mm_add_pd(_mm_mul_pd(bb0, ty), _mm_add_pd(_mm_mul_pd(bb1, bx1), _mm_mul_pd(bb2, bx2))),
                _mm_add_pd(_mm_mul_pd(ba1, by1), _mm_mul_pd(ba2, by2))
            );
            bx2 = bx1; bx1 = ty;
            by2 = by1; by1 = by;

            alignas(16) double by_arr[2];
            _mm_store_pd(by_arr, by);
            buffer[i * 2] = static_cast<float>(by_arr[0]);
            buffer[i * 2 + 1] = static_cast<float>(by_arr[1]);
        }

        alignas(16) double t_arr[2], b_arr[2];
        _mm_store_pd(t_arr, tx1); treble_[0].x1 = t_arr[0]; treble_[1].x1 = t_arr[1];
        _mm_store_pd(t_arr, tx2); treble_[0].x2 = t_arr[0]; treble_[1].x2 = t_arr[1];
        _mm_store_pd(t_arr, ty1); treble_[0].y1 = t_arr[0]; treble_[1].y1 = t_arr[1];
        _mm_store_pd(t_arr, ty2); treble_[0].y2 = t_arr[0]; treble_[1].y2 = t_arr[1];

        _mm_store_pd(b_arr, bx1); bass_[0].x1 = b_arr[0]; bass_[1].x1 = b_arr[1];
        _mm_store_pd(b_arr, bx2); bass_[0].x2 = b_arr[0]; bass_[1].x2 = b_arr[1];
        _mm_store_pd(b_arr, by1); bass_[0].y1 = b_arr[0]; bass_[1].y1 = b_arr[1];
        _mm_store_pd(b_arr, by2); bass_[0].y2 = b_arr[0]; bass_[1].y2 = b_arr[1];
        return;
#endif
    }

    const int activeChannels = std::min(channels, MAX_CHANNELS);
    for (int i = 0; i < frames; ++i) {
        for (int ch = 0; ch < activeChannels; ++ch) {
            buffer[i * channels + ch] = bass_[ch].process(treble_[ch].process(buffer[i * channels + ch]));
        }
    }
}
