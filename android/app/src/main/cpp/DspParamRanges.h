// android/app/src/main/cpp/DspParamRanges.h
//
// Item 4 of the DSP contract: ONE authoritative table of parameter ranges.
//
// Before this header every stage re-clamped its inputs with its own literals
// (LookaheadLimiter 5..1000 ms release, DynamicEQ -24..24 dB cut/boost, the
// Kotlin plugin -30..0 dB limiter threshold, the JNI bridge 0.01..10 dose, ...).
// A value that passed the Dart contract and SanitizeSnapshot could therefore be
// silently narrowed again by the stage, so the UI showed one number while the
// engine ran another.
//
// This table is the native mirror of `lib/data/audio/dsp_param_ranges.dart`
// (DspParamRanges) and of `AudioEffectsPlugin.kt` (DspParamRanges). The three
// are asserted equal by tests:
//   * android/app/src/test/kotlin/.../DspParamRangesContractTest.kt
//     parses the Dart file and compares it with the Kotlin object.
//   * android/app/src/test/cpp/test_param_ranges.cpp
//     feeds the bounds of this table through SanitizeSnapshot and every
//     per-stage clamp and asserts the values survive unmodified.
//
// RULES
//  1. The value at min/max must be accepted verbatim by BOTH SanitizeSnapshot
//     and the owning stage. Narrowing a stage to a tighter range is a bug, not
//     a safety net, unless this table says so in a comment.
//  2. Where the user-facing (Dart/UI) contract is narrower than what a stage
//     can do, the narrower number wins and the reason is documented here.
//     A widened stage is deliberate: the sanitizer and the UI already accepted
//     the value, so the stage must not re-clamp it.
//  3. `fallback` is the value substituted for a non-finite (NaN/Inf) input and
//     is normally the engine default for that parameter.
//
// RT-safety: plain constexpr aggregates, no allocation, no locks.
#ifndef PULSR_DSP_PARAM_RANGES_H_
#define PULSR_DSP_PARAM_RANGES_H_

#include <cstdint>

namespace pulsr {
namespace dsp {
namespace ranges {

struct Range {
    double min;
    double max;
    double fallback;

    constexpr double clamp(double v) const {
        // std::clamp(NaN, lo, hi) is NaN, so non-finite inputs take the default.
        if (!(v >= min && v <= max)) {
            if (v < min) return min;
            if (v > max) return max;
            return fallback;
        }
        return v;
    }
};

// --- Crossfeed -------------------------------------------------------------
// The stage itself can delay 50..2000 us (Crossfeed::configure) and filter
// 100..5000 Hz, but the product contract is the bs2b "custom" panel, which
// never offers more than 700 us / 2 kHz. The narrower UI range is the contract;
// the stage clamp is widened to it rather than the other way round.
inline constexpr Range kCrossfeedDelayUs{200.0, 700.0, 350.0};
inline constexpr Range kCrossfeedFeedDb{-15.0, -6.0, -9.0};
inline constexpr Range kCrossfeedFcutHz{200.0, 2000.0, 650.0};

// --- Lookahead limiter ----------------------------------------------------
// -60 dB is the documented ceiling range (the shared limiter also backs the
// headphone-safety limiter, whose ceiling may be as low as -40 dB).
inline constexpr Range kLimiterLookaheadMs{0.0, 20.0, 5.0};
inline constexpr Range kLimiterThresholdDb{-60.0, 0.0, -0.2};
inline constexpr Range kLimiterReleaseMs{1.0, 1000.0, 50.0};

// --- Subwoofer crossover --------------------------------------------------
// SubCrossover::configure() clamps the corner to 20..500 Hz (a 1 kHz "sub"
// corner is not a subwoofer split), while the UI only offers 60..150 Hz.
// The contract is the UI range; Kotlin is narrowed to match.
inline constexpr Range kSubCrossoverCornerHz{60.0, 150.0, 80.0};
inline constexpr Range kSubCrossoverGain{0.0, 1.0, 0.8};

// --- Multichannel LFE crossover & ChannelManager ---------------------------
inline constexpr Range kLfeCrossoverHz{40.0, 200.0, 80.0};
inline constexpr Range kLfeLowPassHz{60.0, 250.0, 120.0};
inline constexpr Range kLfeGainDb{-12.0, 12.0, 0.0};
inline constexpr Range kChannelManagerTrimDb{-30.0, 12.0, 0.0};
inline constexpr Range kChannelManagerDelayMs{0.0, 50.0, 0.0};

// --- Dynamic EQ -----------------------------------------------------------
// Q: 20 is the agreed maximum (UI + Kotlin). The sanitizer's historical 100 was
// unreachable and produced numerically fragile biquads near Nyquist.
// Ratio: 1..20; a ratio below 1 would invert the expander direction, so the
// sanitizer's old 0.1 lower bound was never honoured by the stage anyway.
// Cut/boost: +-48 dB is the widest documented contract (the stage used to clamp
// to +-24 dB and silently halved a legal UI value).
inline constexpr Range kDynamicEqFrequencyHz{20.0, 20000.0, 1000.0};
inline constexpr Range kDynamicEqQ{0.1, 20.0, 2.0};
inline constexpr Range kDynamicEqThresholdDb{-80.0, 0.0, -30.0};
inline constexpr Range kDynamicEqRatio{1.0, 20.0, 3.0};
inline constexpr Range kDynamicEqAttackMs{0.1, 200.0, 5.0};
inline constexpr Range kDynamicEqReleaseMs{5.0, 2000.0, 120.0};
inline constexpr Range kDynamicEqMaxCutDb{-48.0, 0.0, -12.0};
inline constexpr Range kDynamicEqMaxBoostDb{0.0, 48.0, 12.0};

// --- Multiband compressor -------------------------------------------------
// Makeup gain is deliberately NON-NEGATIVE: the stage only applies it while the
// band is enabled, and a negative makeup is indistinguishable from (and less
// discoverable than) attenuating the band with the EQ preamp. Documented
// choice: Kotlin's -24..24 is narrowed to 0..24 instead of widening the
// sanitizer, so no stage silently halves a legal value.
inline constexpr Range kMultibandThresholdDb{-60.0, 0.0, -18.0};
inline constexpr Range kMultibandRatio{1.0, 20.0, 2.0};
inline constexpr Range kMultibandAttackMs{0.1, 200.0, 15.0};
inline constexpr Range kMultibandReleaseMs{5.0, 1000.0, 100.0};
inline constexpr Range kMultibandKneeDb{0.0, 12.0, 3.0};
inline constexpr Range kMultibandMakeupGainDb{0.0, 24.0, 0.0};

// --- Headphone safety -----------------------------------------------------
// Daily/weekly dose multiplier. The three stages used to disagree (JNI 0.01..10,
// Kotlin 0.01..100, sanitizer 0.1..100); 0.1..100 is the widest of the three
// that the UI can express, so all three now share it.
inline constexpr Range kSafetyDoseThreshold{0.1, 100.0, 1.0};
inline constexpr Range kSafetyCeilingDb{-40.0, 0.0, -6.0};

// --- Bit-perfect / dither -------------------------------------------------
// Software attenuation fallback for Direct USB PCM output. 1.0 is the only
// bit-exact value; anything below it is a deliberate attenuation.
inline constexpr Range kDirectUsbGain{0.0, 1.0, 1.0};

// Dither is defined only for integer PCM depths. The fallback is 16 because a
// zero/absent depth would disable the quantiser silently.
inline constexpr int32_t kDitherBitDepths[] = {16, 24, 32};
inline constexpr int32_t kDitherBitDepthFallback = 16;

inline constexpr bool IsSupportedDitherDepth(int32_t depth) {
    return depth == 16 || depth == 24 || depth == 32;
}

inline constexpr int32_t ClampDitherBitDepth(int32_t depth) {
    return IsSupportedDitherDepth(depth) ? depth : kDitherBitDepthFallback;
}

}  // namespace ranges
}  // namespace dsp
}  // namespace pulsr

#endif  // PULSR_DSP_PARAM_RANGES_H_
