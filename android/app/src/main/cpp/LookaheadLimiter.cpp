// android/app/src/main/cpp/LookaheadLimiter.cpp
#include "LookaheadLimiter.h"
#include <cstring>
#include <cmath>

#if defined(__aarch64__) || defined(_M_ARM64)
#include <arm_neon.h>
#define PULSR_HAS_NEON 1
#elif defined(__x86_64__) || defined(_M_X64) || defined(__i386__) || defined(_M_IX86)
#include <emmintrin.h>
#include <xmmintrin.h>
#define PULSR_HAS_SSE 1
#endif

// FIX M-2: replace the ad-hoc 6-tap-per-phase sinc with the ITU-R BS.1770-4
// true-peak 4x-oversampling FIR: 48 taps split into 4 polyphase branches of 12
// taps each (coefficients are the standard's values, quantised to multiples of
// 1/8192, e.g. 0.9721679687500 = 7963/8192). Phase 0 aligns to the integer
// sample, phases 1-3 evaluate the 1/4, 2/4, 3/4 inter-sample positions. Phase 3
// is the time-reverse of phase 0 and phase 2 of phase 1 (linear-phase symmetry).
// Per-phase DC gain (sum of the 12 taps): phase 0/3 = 1.0015869, phase 1/2 =
// 0.9730225 — this is the standard filter's small passband ripple. The raw-sample
// floor in estimateTruePeak() guarantees the estimate never drops below an actual
// sample value despite the sub-unity branches.
const float LookaheadLimiter::polyphase4x_[INTERP_PHASES][TAPS_PER_PHASE] = {
    // Phase 0 (integer sample position)
    {  0.0017089843750f,  0.0109863281250f, -0.0196533203125f,  0.0332031250000f,
      -0.0594482421875f,  0.1373291015625f,  0.9721679687500f, -0.1022949218750f,
       0.0476074218750f, -0.0266113281250f,  0.0148925781250f, -0.0083007812500f },
    // Phase 1 (1/4 inter-sample)
    { -0.0291748046875f,  0.0292968750000f, -0.0517578125000f,  0.0891113281250f,
      -0.1665039062500f,  0.4650878906250f,  0.7797851562500f, -0.2003173828125f,
       0.1015625000000f, -0.0582275390625f,  0.0330810546875f, -0.0189208984375f },
    // Phase 2 (2/4 inter-sample)
    { -0.0189208984375f,  0.0330810546875f, -0.0582275390625f,  0.1015625000000f,
      -0.2003173828125f,  0.7797851562500f,  0.4650878906250f, -0.1665039062500f,
       0.0891113281250f, -0.0517578125000f,  0.0292968750000f, -0.0291748046875f },
    // Phase 3 (3/4 inter-sample)
    { -0.0083007812500f,  0.0148925781250f, -0.0266113281250f,  0.0476074218750f,
      -0.1022949218750f,  0.9721679687500f,  0.1373291015625f, -0.0594482421875f,
       0.0332031250000f, -0.0196533203125f,  0.0109863281250f,  0.0017089843750f }
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
    // Match the Dart contract (DspParamRanges.limiterThresholdDb) and the
    // snapshot sanitizer (-60..0) so a valid UI value is not silently clamped.
    // The shared class also serves the headphone-safety limiter, whose ceiling
    // may be as low as -40 dB.
    thresholdDb_ = std::clamp(thresholdDb, -60.0, 0.0);
    releaseMs_ = std::clamp(releaseMs, 5.0, 1000.0);
    truePeakMode_ = truePeakMode;

    const int newLookahead = std::clamp(
        static_cast<int>(lookaheadMs_ * 0.001 * sampleRate_),
        TAPS_PER_PHASE + 1,
        MAX_LOOKAHEAD_SAMPLES - 1
    );

    // FIX M-3: the delay-line read index is (writeIdx_ - lookaheadSamples_), so
    // changing the lookahead length mid-stream would jump the read position and
    // the min-gain deque window, producing a click. Detect the change and
    // re-prime: reset() clears the delay line, the monotonic deque and the gain
    // state so the new latency starts from a clean (silent) buffer rather than a
    // discontinuous read. latencyFramesAtomic_ is stored in lockstep below so
    // getLatencyFrames() always reports the length actually in effect.
    const bool lookaheadChanged = (newLookahead != lookaheadSamples_);
    lookaheadSamples_ = newLookahead;
    latencyFramesAtomic_.store(lookaheadSamples_, std::memory_order_relaxed);

    threshold_ = static_cast<float>(std::pow(10.0, thresholdDb_ / 20.0));
    fastReleaseCoeff_ = static_cast<float>(std::exp(-1.0 / (0.015 * sampleRate_))); // 15ms fast transient release
    // Honour the user's release time (clamped to [5, 1000] ms in configure).
    slowReleaseCoeff_ = static_cast<float>(std::exp(-1.0 / (releaseMs_ * 0.001 * sampleRate_)));

    if (lookaheadChanged) {
        reset();
    }
}

void LookaheadLimiter::setEnabled(bool enabled) {
    if (enabled == enabled_) return;
    enabled_ = enabled;
    if (enabled) {
        // Re-entering the stage after being bypassed must not replay stale
        // delay-line contents or old gain state. Hold the current input
        // (with instantaneous limiting) until the window is fresh, then
        // fade the delayed stream in.
        beginEnableTransition();
    } else {
        // Direct disable bypasses immediately. The engine's main limiter
        // fades out instead by keeping enabled_ true and calling
        // setProcessingActive(false) until isDraining() clears.
        bypassPending_ = false;
        bypassTarget_ = 0.0f;
        bypassMix_ = 0.0f;
        bypassHoldRemaining_ = 0;
        enableFading_ = false;
        disabledSinceProcess_ = false;
    }
}

void LookaheadLimiter::setProcessingActive(bool active) {
    if (active == processingActive_) return;
    processingActive_ = active;
    if (active) {
        if (disabledSinceProcess_ || bypassMix_ <= 0.0f) {
            beginEnableTransition();
        } else {
            // Re-enable during the release/bypass fade: reverse the ramp
            // instead of snapping to either side.
            bypassPending_ = false;
            bypassTarget_ = 1.0f;
        }
    } else if (bypassMix_ > 0.0f) {
        // The engine keeps calling process() while isDraining() is true; the
        // fade-out starts once any insertion fade has finished and the gain
        // envelope has settled.
        disabledSinceProcess_ = true;
        bypassPending_ = true;
    } else {
        bypassPending_ = false;
        bypassTarget_ = 0.0f;
        bypassHoldRemaining_ = 0;
        enableFading_ = false;
        disabledSinceProcess_ = false;
    }
}

void LookaheadLimiter::applyParams(const LimiterParamSet& params) {
    pendingParams_ = params;
    paramsChanged_.store(true, std::memory_order_release);
}

void LookaheadLimiter::syncPendingParams() {
    if (!paramsChanged_.load(std::memory_order_acquire)) return;
    const bool wasEnabled = enabled_;
    enabled_ = pendingParams_.enabled;
    configure(pendingParams_.lookaheadMs, pendingParams_.thresholdDb, pendingParams_.releaseMs, pendingParams_.truePeakMode);
    paramsChanged_.store(false, std::memory_order_release);

    if (enabled_ && !wasEnabled) {
        // The stage may have been dormant while processingActive_ was already
        // true (e.g. the engine requested it for safety gain while the user
        // had it disabled). Its delay line was not advanced during that time,
        // so always discard it rather than replaying stale samples.
        beginEnableTransition();
    } else if (!enabled_ && wasEnabled) {
        bypassPending_ = false;
        bypassTarget_ = 0.0f;
        bypassMix_ = 0.0f;
        bypassHoldRemaining_ = 0;
        enableFading_ = false;
        disabledSinceProcess_ = false;
    }
}

void LookaheadLimiter::reset() {
    std::memset(delayBuf_, 0, sizeof(delayBuf_));
    std::fill(std::begin(gainBuf_), std::end(gainBuf_), 1.0f);
    std::memset(deque_, 0, sizeof(deque_));
    writeIdx_ = 0;
    envelope_ = 1.0f;
    minGain_ = 1.0f;
    dequeHead_ = 0;
    dequeTail_ = 0;
    sampleCount_ = 0;
    avgEnergy_ = 0.0f;
    transientWeight_ = 0.0f;
    gainReductionDb_.store(0.0f, std::memory_order_relaxed);
    bypassMix_ = 1.0f;
    bypassTarget_ = 1.0f;
    bypassHoldRemaining_ = 0;
    enableFading_ = false;
    bypassPending_ = false;
    processingActive_ = false;
    disabledSinceProcess_ = false;
}

float LookaheadLimiter::estimateTruePeak(const float* history) {
    // history[0..TAPS_PER_PHASE-1] runs oldest -> newest (history[11] is the
    // sample just written). The BS.1770-4 4x filter aligns phase 0 to history[6]
    // and phase 3 to history[5], so the oversampled interval evaluated here is
    // [history[5], history[6]]. Seed the estimate with the raw sample at
    // history[6] so it can never read below the actual sample value; history[5]
    // is floored the same way by the previous frame's history[6], so every
    // integer sample is protected while phases 0-3 add the inter-sample maxima.
    float peak = std::abs(history[6]);

    if (!truePeakMode_) {
        return peak;
    }

    if (sampleRate_ > 192000.0) {
        // Nyquist >= 96 kHz: inter-sample peaks are negligible, 1x is enough.
        return peak;
    }

    // 4x oversampling: evaluate all four polyphase branches, keep the max |.|.
#if defined(PULSR_HAS_NEON)
    // kPhaseCoeffs[tap] = { phase0, phase1, phase2, phase3 } (polyphase4x_
    // transposed), so one fused multiply-add per tap accumulates all four branch
    // sums across the 4 SIMD lanes; vmaxvq then reduces to the max over phases.
    alignas(16) static const float kPhaseCoeffs[TAPS_PER_PHASE][4] = {
        {  0.0017089843750f, -0.0291748046875f, -0.0189208984375f, -0.0083007812500f },
        {  0.0109863281250f,  0.0292968750000f,  0.0330810546875f,  0.0148925781250f },
        { -0.0196533203125f, -0.0517578125000f, -0.0582275390625f, -0.0266113281250f },
        {  0.0332031250000f,  0.0891113281250f,  0.1015625000000f,  0.0476074218750f },
        { -0.0594482421875f, -0.1665039062500f, -0.2003173828125f, -0.1022949218750f },
        {  0.1373291015625f,  0.4650878906250f,  0.7797851562500f,  0.9721679687500f },
        {  0.9721679687500f,  0.7797851562500f,  0.4650878906250f,  0.1373291015625f },
        { -0.1022949218750f, -0.2003173828125f, -0.1665039062500f, -0.0594482421875f },
        {  0.0476074218750f,  0.1015625000000f,  0.0891113281250f,  0.0332031250000f },
        { -0.0266113281250f, -0.0582275390625f, -0.0517578125000f, -0.0196533203125f },
        {  0.0148925781250f,  0.0330810546875f,  0.0292968750000f,  0.0109863281250f },
        { -0.0083007812500f, -0.0189208984375f, -0.0291748046875f,  0.0017089843750f }
    };
    float32x4_t vAcc = vdupq_n_f32(0.0f);
    for (int t = 0; t < TAPS_PER_PHASE; ++t) {
        float32x4_t vC = vld1q_f32(kPhaseCoeffs[t]);
        vAcc = vfmaq_n_f32(vAcc, vC, history[t]);
    }
    float32x4_t vAbs = vabsq_f32(vAcc);
    peak = std::max(peak, vmaxvq_f32(vAbs));
#elif defined(PULSR_HAS_SSE)
    alignas(16) static const float kPhaseCoeffs[TAPS_PER_PHASE][4] = {
        {  0.0017089843750f, -0.0291748046875f, -0.0189208984375f, -0.0083007812500f },
        {  0.0109863281250f,  0.0292968750000f,  0.0330810546875f,  0.0148925781250f },
        { -0.0196533203125f, -0.0517578125000f, -0.0582275390625f, -0.0266113281250f },
        {  0.0332031250000f,  0.0891113281250f,  0.1015625000000f,  0.0476074218750f },
        { -0.0594482421875f, -0.1665039062500f, -0.2003173828125f, -0.1022949218750f },
        {  0.1373291015625f,  0.4650878906250f,  0.7797851562500f,  0.9721679687500f },
        {  0.9721679687500f,  0.7797851562500f,  0.4650878906250f,  0.1373291015625f },
        { -0.1022949218750f, -0.2003173828125f, -0.1665039062500f, -0.0594482421875f },
        {  0.0476074218750f,  0.1015625000000f,  0.0891113281250f,  0.0332031250000f },
        { -0.0266113281250f, -0.0582275390625f, -0.0517578125000f, -0.0196533203125f },
        {  0.0148925781250f,  0.0330810546875f,  0.0292968750000f,  0.0109863281250f },
        { -0.0083007812500f, -0.0189208984375f, -0.0291748046875f,  0.0017089843750f }
    };
    __m128 vAcc = _mm_setzero_ps();
    for (int t = 0; t < TAPS_PER_PHASE; ++t) {
        __m128 vC = _mm_load_ps(kPhaseCoeffs[t]);
        __m128 vH = _mm_set1_ps(history[t]);
        vAcc = _mm_add_ps(vAcc, _mm_mul_ps(vH, vC));
    }
    __m128 vAbs = _mm_and_ps(vAcc, _mm_castsi128_ps(_mm_set1_epi32(0x7fffffff)));
    alignas(16) float sub[4];
    _mm_store_ps(sub, vAbs);
    peak = std::max(peak, std::max(std::max(sub[0], sub[1]), std::max(sub[2], sub[3])));
#else
    for (int phase = 0; phase < INTERP_PHASES; ++phase) {
        float subSample = 0.0f;
        for (int tap = 0; tap < TAPS_PER_PHASE; ++tap) {
            subSample += history[tap] * polyphase4x_[phase][tap];
        }
        peak = std::max(peak, std::abs(subSample));
    }
#endif

    return peak;
}

void LookaheadLimiter::process(float* L, float* R, int frames) {
    syncPendingParams();

    if (!enabled_ || frames <= 0) return;
    disabledSinceProcess_ = false;

    constexpr int kMask = MAX_LOOKAHEAD_SAMPLES - 1;
    float historyWindowL[TAPS_PER_PHASE] = {};
    float historyWindowR[TAPS_PER_PHASE] = {};
    float blockMinEnvelope = 1.0f;

    for (int i = 0; i < frames; ++i) {
        const float inL = L[i];
        const float inR = R[i];

        delayBuf_[0][writeIdx_] = std::isfinite(inL) ? inL : 0.0f;
        delayBuf_[1][writeIdx_] = std::isfinite(inR) ? inR : 0.0f;

        // Gather TAPS_PER_PHASE (12) samples of history for true-peak interpolation
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

        pushGainDeque(requiredGain, sampleCount_++, lookaheadSamples_);
        float targetGain = getMinGain();

        // Dynamic transient tracking for program-dependent release
        const float energyCoeff = 0.001f;
        avgEnergy_ += energyCoeff * (maxPeak - avgEnergy_);
        if (avgEnergy_ < 1e-6f) avgEnergy_ = 1e-6f;
        const float crest = maxPeak / avgEnergy_;
        float currentTransient = std::clamp((crest - 1.2f) / 2.0f, 0.0f, 1.0f);
        if (currentTransient > transientWeight_) {
            transientWeight_ = currentTransient;
        } else {
            transientWeight_ *= 0.999f;
        }
        const float effectiveReleaseCoeff = (1.0f - transientWeight_) * slowReleaseCoeff_ + transientWeight_ * fastReleaseCoeff_;

        // Instantaneous attack to target minimum gain, smooth exponential release when lookahead window clears
        if (targetGain < envelope_) {
            const float attackStep = 1.0f / static_cast<float>(lookaheadSamples_);
            envelope_ = std::max(targetGain, envelope_ - attackStep);
        } else {
            envelope_ = effectiveReleaseCoeff * envelope_ + (1.0f - effectiveReleaseCoeff) * targetGain;
            if (envelope_ > 0.99999f) {
                envelope_ = 1.0f;
            }
        }
        if (!std::isfinite(envelope_) || envelope_ <= 0.0f) envelope_ = 1.0f;
        blockMinEnvelope = std::min(blockMinEnvelope, envelope_);

        if (bypassPending_ && !enableFading_ && envelope_ >= 0.999f) {
            bypassTarget_ = 0.0f;
            bypassHoldRemaining_ = 0;
        }
        float mix = 0.0f;
        if (bypassHoldRemaining_ > 0) {
            --bypassHoldRemaining_;
        } else {
            mix = advanceBypassMix();
        }

        // Read delayed audio from lookahead buffer
        int readIdx = (writeIdx_ - lookaheadSamples_) & kMask;
        const float wetL = delayBuf_[0][readIdx] * envelope_;
        const float wetR = delayBuf_[1][readIdx] * envelope_;
        // While inserting the stage, the current input stands in for the not
        // yet fresh delay line. Scale it by the instantaneous limiter gain so
        // the lead-in cannot exceed the ceiling; after the hold it crossfades
        // to the properly delayed stream. The lookahead estimate is centred on
        // an older history sample, so include the current sample explicitly.
        const float dryRawL = delayBuf_[0][writeIdx_];
        const float dryRawR = delayBuf_[1][writeIdx_];
        const float dryPeak = std::max(
            maxPeak, std::max(std::abs(dryRawL), std::abs(dryRawR)));
        const float dryGain = (bypassTarget_ > 0.0f && dryPeak > 1e-6f)
            ? std::min(targetGain, threshold_ / dryPeak)
            : 1.0f;
        const float dryL = dryRawL * dryGain;
        const float dryR = dryRawR * dryGain;
        if (mix >= 1.0f) {
            enableFading_ = false;
            L[i] = wetL;
            R[i] = wetR;
        } else if (mix <= 0.0f) {
            L[i] = dryL;
            R[i] = dryR;
        } else {
            L[i] = dryL + mix * (wetL - dryL);
            R[i] = dryR + mix * (wetR - dryR);
        }
        if (bypassTarget_ == 0.0f && bypassMix_ <= 0.0f) {
            bypassPending_ = false;
        }

        writeIdx_ = (writeIdx_ + 1) & kMask;
    }
    const float gr = (blockMinEnvelope < 1.0f && blockMinEnvelope > 0.0f) ? (20.0f * std::log10(blockMinEnvelope)) : 0.0f;
    gainReductionDb_.store(gr, std::memory_order_relaxed);
}

void LookaheadLimiter::processMono(float* inOut, int frames) {
    syncPendingParams();

    if (!enabled_ || frames <= 0) return;
    disabledSinceProcess_ = false;

    constexpr int kMask = MAX_LOOKAHEAD_SAMPLES - 1;
    float historyWindow[TAPS_PER_PHASE] = {};
    float blockMinEnvelope = 1.0f;

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

        pushGainDeque(requiredGain, sampleCount_++, lookaheadSamples_);
        float targetGain = getMinGain();

        const float energyCoeff = 0.001f;
        avgEnergy_ += energyCoeff * (peak - avgEnergy_);
        if (avgEnergy_ < 1e-6f) avgEnergy_ = 1e-6f;
        const float crest = peak / avgEnergy_;
        float currentTransient = std::clamp((crest - 1.2f) / 2.0f, 0.0f, 1.0f);
        if (currentTransient > transientWeight_) {
            transientWeight_ = currentTransient;
        } else {
            transientWeight_ *= 0.999f;
        }
        const float effectiveReleaseCoeff = (1.0f - transientWeight_) * slowReleaseCoeff_ + transientWeight_ * fastReleaseCoeff_;

        if (targetGain < envelope_) {
            const float attackStep = 1.0f / static_cast<float>(lookaheadSamples_);
            envelope_ = std::max(targetGain, envelope_ - attackStep);
        } else {
            envelope_ = effectiveReleaseCoeff * envelope_ + (1.0f - effectiveReleaseCoeff) * targetGain;
            if (envelope_ > 0.99999f) {
                envelope_ = 1.0f;
            }
        }
        if (!std::isfinite(envelope_) || envelope_ <= 0.0f) envelope_ = 1.0f;
        blockMinEnvelope = std::min(blockMinEnvelope, envelope_);

        if (bypassPending_ && !enableFading_ && envelope_ >= 0.999f) {
            bypassTarget_ = 0.0f;
            bypassHoldRemaining_ = 0;
        }
        float mix = 0.0f;
        if (bypassHoldRemaining_ > 0) {
            --bypassHoldRemaining_;
        } else {
            mix = advanceBypassMix();
        }

        int readIdx = (writeIdx_ - lookaheadSamples_) & kMask;
        const float wet = delayBuf_[0][readIdx] * envelope_;
        const float dryRaw = delayBuf_[0][writeIdx_];
        const float dryPeak = std::max(peak, std::abs(dryRaw));
        const float dryGain = (bypassTarget_ > 0.0f && dryPeak > 1e-6f)
            ? std::min(targetGain, threshold_ / dryPeak)
            : 1.0f;
        const float dry = dryRaw * dryGain;
        if (mix >= 1.0f) {
            enableFading_ = false;
            inOut[i] = wet;
        } else if (mix <= 0.0f) {
            inOut[i] = dry;
        } else {
            inOut[i] = dry + mix * (wet - dry);
        }
        if (bypassTarget_ == 0.0f && bypassMix_ <= 0.0f) {
            bypassPending_ = false;
        }

        writeIdx_ = (writeIdx_ + 1) & kMask;
    }
    const float gr = (blockMinEnvelope < 1.0f && blockMinEnvelope > 0.0f) ? (20.0f * std::log10(blockMinEnvelope)) : 0.0f;
    gainReductionDb_.store(gr, std::memory_order_relaxed);
}

void LookaheadLimiter::processInterleaved(float* buffer, int frames, int channels) {
    syncPendingParams();

    if (!enabled_ || frames <= 0) return;
    disabledSinceProcess_ = false;
    // Keep the real interleave stride; clamp only the number of channels we
    // process. Using the clamped count as the stride garbles wide streams.
    const int stride = channels > 0 ? channels : 1;
    const int processChannels = std::clamp(channels, 1, MAX_CHANNELS);

    constexpr int kMask = MAX_LOOKAHEAD_SAMPLES - 1;
    float historyWindow[TAPS_PER_PHASE] = {};
    float blockMinEnvelope = 1.0f;

    for (int i = 0; i < frames; ++i) {
        float frameMaxPeak = 0.0f;

        for (int ch = 0; ch < processChannels; ++ch) {
            const float inSample = buffer[i * stride + ch];
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

        pushGainDeque(requiredGain, sampleCount_++, lookaheadSamples_);
        float targetGain = getMinGain();

        const float energyCoeff = 0.001f;
        avgEnergy_ += energyCoeff * (frameMaxPeak - avgEnergy_);
        if (avgEnergy_ < 1e-6f) avgEnergy_ = 1e-6f;
        const float crest = frameMaxPeak / avgEnergy_;
        float currentTransient = std::clamp((crest - 1.2f) / 2.0f, 0.0f, 1.0f);
        if (currentTransient > transientWeight_) {
            transientWeight_ = currentTransient;
        } else {
            transientWeight_ *= 0.999f;
        }
        const float effectiveReleaseCoeff = (1.0f - transientWeight_) * slowReleaseCoeff_ + transientWeight_ * fastReleaseCoeff_;

        // Attack ramps linearly across the lookahead window instead of stepping
        // instantly. A constant 1/lookaheadSamples rate is guaranteed to reach
        // any targetGain before the peak that produced it reaches the output
        // (the peak is delayed by exactly lookaheadSamples_), so the ceiling is
        // still enforced while the gain discontinuity is removed.
        if (targetGain < envelope_) {
            const float attackStep = 1.0f / static_cast<float>(lookaheadSamples_);
            envelope_ = std::max(targetGain, envelope_ - attackStep);
        } else {
            envelope_ = effectiveReleaseCoeff * envelope_ + (1.0f - effectiveReleaseCoeff) * targetGain;
            if (envelope_ > 0.99999f) {
                envelope_ = 1.0f;
            }
        }
        if (!std::isfinite(envelope_) || envelope_ <= 0.0f) envelope_ = 1.0f;
        blockMinEnvelope = std::min(blockMinEnvelope, envelope_);

        if (bypassPending_ && !enableFading_ && envelope_ >= 0.999f) {
            bypassTarget_ = 0.0f;
            bypassHoldRemaining_ = 0;
        }
        float mix = 0.0f;
        if (bypassHoldRemaining_ > 0) {
            --bypassHoldRemaining_;
        } else {
            mix = advanceBypassMix();
        }

        int readIdx = (writeIdx_ - lookaheadSamples_) & kMask;
        float dryPeak = frameMaxPeak;
        for (int ch = 0; ch < processChannels; ++ch) {
            dryPeak = std::max(dryPeak, std::abs(delayBuf_[ch][writeIdx_]));
        }
        const float dryGain = (bypassTarget_ > 0.0f && dryPeak > 1e-6f)
            ? std::min(targetGain, threshold_ / dryPeak)
            : 1.0f;
        for (int ch = 0; ch < processChannels; ++ch) {
            const float wet = delayBuf_[ch][readIdx] * envelope_;
            const float dry = delayBuf_[ch][writeIdx_] * dryGain;
            if (mix >= 1.0f) {
                buffer[i * stride + ch] = wet;
            } else if (mix <= 0.0f) {
                buffer[i * stride + ch] = dry;
            } else {
                buffer[i * stride + ch] = dry + mix * (wet - dry);
            }
        }
        if (mix >= 1.0f) {
            enableFading_ = false;
        }
        if (bypassTarget_ == 0.0f && bypassMix_ <= 0.0f) {
            bypassPending_ = false;
        }

        writeIdx_ = (writeIdx_ + 1) & kMask;
    }
    const float gr = (blockMinEnvelope < 1.0f && blockMinEnvelope > 0.0f) ? (20.0f * std::log10(blockMinEnvelope)) : 0.0f;
    gainReductionDb_.store(gr, std::memory_order_relaxed);
}

