// android/app/src/test/cpp/test_param_ranges.cpp
//
// Item 4 regression: the range table (DspParamRanges.h) is the single source of
// truth, and neither SanitizeSnapshot nor a per-stage clamp may narrow a value
// that sits on a table bound.
//
// For every entry the test pushes the table's min and max through
//   (a) AudioDspEngine::updateParams -> SanitizeSnapshot -> getParams(), and
//   (b) the owning stage's setter, read back through its own getter,
// and asserts the value survives unmodified. It also asserts a non-finite input
// lands on the table's documented fallback.
//
// MultibandCompressor is the one stage with no parameter getter: its band values
// are applied verbatim (params_ = pendingParams_) and only attack/release are
// clamped inside updateCoefficients(), using the same table bounds. The sanitizer
// check below is therefore the contract check for that stage.
#include "../../main/cpp/AudioDspEngine.h"
#include "../../main/cpp/DspParamRanges.h"
#include "../../main/cpp/LookaheadLimiter.h"
#include "../../main/cpp/Crossfeed.h"
#include "../../main/cpp/SubCrossover.h"
#include "../../main/cpp/DynamicEQ.h"

#include <cmath>
#include <cstdio>
#include <functional>
#include <limits>
#include <string>
#include <vector>

namespace ranges = pulsr::dsp::ranges;

namespace {

int gFailures = 0;

void check(bool ok, const std::string& what) {
    if (!ok) {
        std::printf("[FAIL] %s\n", what.c_str());
        ++gFailures;
    }
}

struct SnapshotCase {
    std::string name;
    std::function<void(DspParamSnapshot&, double)> set;
    std::function<double(const DspParamSnapshot&)> get;
    ranges::Range range;
};

bool nearlyEqual(double a, double b) {
    return std::abs(a - b) <= 1e-9 * std::max(1.0, std::abs(b));
}

}  // namespace

int main() {
    std::printf("[TEST] DSP parameter range contract (sanitizer + stage clamps)...\n");

    std::vector<SnapshotCase> cases = {
        {"crossfeed.delayUs",
         [](DspParamSnapshot& s, double v) { s.crossfeed.delayUs = v; },
         [](const DspParamSnapshot& s) { return s.crossfeed.delayUs; },
         ranges::kCrossfeedDelayUs},
        {"crossfeed.feedDb",
         [](DspParamSnapshot& s, double v) { s.crossfeed.feedDb = v; },
         [](const DspParamSnapshot& s) { return s.crossfeed.feedDb; },
         ranges::kCrossfeedFeedDb},
        {"crossfeed.fcut",
         [](DspParamSnapshot& s, double v) { s.crossfeed.fcut = v; },
         [](const DspParamSnapshot& s) { return s.crossfeed.fcut; },
         ranges::kCrossfeedFcutHz},
        {"limiter.lookaheadMs",
         [](DspParamSnapshot& s, double v) { s.limiter.lookaheadMs = v; },
         [](const DspParamSnapshot& s) { return s.limiter.lookaheadMs; },
         ranges::kLimiterLookaheadMs},
        {"limiter.thresholdDb",
         [](DspParamSnapshot& s, double v) { s.limiter.thresholdDb = v; },
         [](const DspParamSnapshot& s) { return s.limiter.thresholdDb; },
         ranges::kLimiterThresholdDb},
        {"limiter.releaseMs",
         [](DspParamSnapshot& s, double v) { s.limiter.releaseMs = v; },
         [](const DspParamSnapshot& s) { return s.limiter.releaseMs; },
         ranges::kLimiterReleaseMs},
        {"subCrossover.cornerHz",
         [](DspParamSnapshot& s, double v) { s.subCrossover.cornerHz = v; },
         [](const DspParamSnapshot& s) { return s.subCrossover.cornerHz; },
         ranges::kSubCrossoverCornerHz},
        {"subCrossover.subGain",
         [](DspParamSnapshot& s, double v) { s.subCrossover.subGain = v; },
         [](const DspParamSnapshot& s) { return s.subCrossover.subGain; },
         ranges::kSubCrossoverGain},
        {"dynamicEq[0].frequency",
         [](DspParamSnapshot& s, double v) { s.dynamicEq.bands[0].frequency = v; },
         [](const DspParamSnapshot& s) { return s.dynamicEq.bands[0].frequency; },
         ranges::kDynamicEqFrequencyHz},
        {"dynamicEq[0].q",
         [](DspParamSnapshot& s, double v) { s.dynamicEq.bands[0].q = v; },
         [](const DspParamSnapshot& s) { return s.dynamicEq.bands[0].q; },
         ranges::kDynamicEqQ},
        {"dynamicEq[0].thresholdDb",
         [](DspParamSnapshot& s, double v) { s.dynamicEq.bands[0].thresholdDb = v; },
         [](const DspParamSnapshot& s) { return s.dynamicEq.bands[0].thresholdDb; },
         ranges::kDynamicEqThresholdDb},
        {"dynamicEq[0].ratio",
         [](DspParamSnapshot& s, double v) { s.dynamicEq.bands[0].ratio = v; },
         [](const DspParamSnapshot& s) { return s.dynamicEq.bands[0].ratio; },
         ranges::kDynamicEqRatio},
        {"dynamicEq[0].attackMs",
         [](DspParamSnapshot& s, double v) { s.dynamicEq.bands[0].attackMs = v; },
         [](const DspParamSnapshot& s) { return s.dynamicEq.bands[0].attackMs; },
         ranges::kDynamicEqAttackMs},
        {"dynamicEq[0].releaseMs",
         [](DspParamSnapshot& s, double v) { s.dynamicEq.bands[0].releaseMs = v; },
         [](const DspParamSnapshot& s) { return s.dynamicEq.bands[0].releaseMs; },
         ranges::kDynamicEqReleaseMs},
        {"dynamicEq[0].maxCutDb",
         [](DspParamSnapshot& s, double v) { s.dynamicEq.bands[0].maxCutDb = v; },
         [](const DspParamSnapshot& s) { return s.dynamicEq.bands[0].maxCutDb; },
         ranges::kDynamicEqMaxCutDb},
        {"dynamicEq[0].maxBoostDb",
         [](DspParamSnapshot& s, double v) { s.dynamicEq.bands[0].maxBoostDb = v; },
         [](const DspParamSnapshot& s) { return s.dynamicEq.bands[0].maxBoostDb; },
         ranges::kDynamicEqMaxBoostDb},
        {"multibandCompressor[0].thresholdDb",
         [](DspParamSnapshot& s, double v) { s.multibandCompressor.bands[0].thresholdDb = v; },
         [](const DspParamSnapshot& s) { return s.multibandCompressor.bands[0].thresholdDb; },
         ranges::kMultibandThresholdDb},
        {"multibandCompressor[0].ratio",
         [](DspParamSnapshot& s, double v) { s.multibandCompressor.bands[0].ratio = v; },
         [](const DspParamSnapshot& s) { return s.multibandCompressor.bands[0].ratio; },
         ranges::kMultibandRatio},
        {"multibandCompressor[0].attackMs",
         [](DspParamSnapshot& s, double v) { s.multibandCompressor.bands[0].attackMs = v; },
         [](const DspParamSnapshot& s) { return s.multibandCompressor.bands[0].attackMs; },
         ranges::kMultibandAttackMs},
        {"multibandCompressor[0].releaseMs",
         [](DspParamSnapshot& s, double v) { s.multibandCompressor.bands[0].releaseMs = v; },
         [](const DspParamSnapshot& s) { return s.multibandCompressor.bands[0].releaseMs; },
         ranges::kMultibandReleaseMs},
        {"multibandCompressor[0].kneeDb",
         [](DspParamSnapshot& s, double v) { s.multibandCompressor.bands[0].kneeDb = v; },
         [](const DspParamSnapshot& s) { return s.multibandCompressor.bands[0].kneeDb; },
         ranges::kMultibandKneeDb},
        {"multibandCompressor[0].makeupGainDb",
         [](DspParamSnapshot& s, double v) { s.multibandCompressor.bands[0].makeupGainDb = v; },
         [](const DspParamSnapshot& s) { return s.multibandCompressor.bands[0].makeupGainDb; },
         ranges::kMultibandMakeupGainDb},
        {"headphoneSafety.doseThreshold",
         [](DspParamSnapshot& s, double v) { s.headphoneSafety.doseThreshold = v; },
         [](const DspParamSnapshot& s) { return s.headphoneSafety.doseThreshold; },
         ranges::kSafetyDoseThreshold},
        {"headphoneSafety.safetyCeilingDb",
         [](DspParamSnapshot& s, double v) { s.headphoneSafety.safetyCeilingDb = v; },
         [](const DspParamSnapshot& s) { return s.headphoneSafety.safetyCeilingDb; },
         ranges::kSafetyCeilingDb},
        {"bitPerfect.directUsbGain",
         [](DspParamSnapshot& s, double v) { s.bitPerfect.directUsbGain = v; },
         [](const DspParamSnapshot& s) { return s.bitPerfect.directUsbGain; },
         ranges::kDirectUsbGain},
    };

    AudioDspEngine& engine = AudioDspEngine::instance();
    engine.setSampleRate(48000.0);

    for (const auto& c : cases) {
        for (double bound : {c.range.min, c.range.max}) {
            engine.updateParams([&](DspParamSnapshot& s) { c.set(s, bound); });
            const auto published = engine.getParams();
            const double actual = c.get(*published);
            check(nearlyEqual(actual, bound),
                  c.name + ": SanitizeSnapshot must accept " + std::to_string(bound) +
                      " unmodified (got " + std::to_string(actual) + ")");
        }
        // NaN must land on the documented fallback, never propagate.
        engine.updateParams([&](DspParamSnapshot& s) {
            c.set(s, std::numeric_limits<double>::quiet_NaN());
        });
        const double fallback = c.get(*engine.getParams());
        check(nearlyEqual(fallback, c.range.fallback),
              c.name + ": NaN must fall back to " + std::to_string(c.range.fallback) +
                  " (got " + std::to_string(fallback) + ")");
    }

    // ---- Per-stage clamps -------------------------------------------------
    {
        LookaheadLimiter limiter;
        limiter.setSampleRate(48000.0);
        for (double threshold : {ranges::kLimiterThresholdDb.min, ranges::kLimiterThresholdDb.max}) {
            for (double release : {ranges::kLimiterReleaseMs.min, ranges::kLimiterReleaseMs.max}) {
                for (double lookahead : {ranges::kLimiterLookaheadMs.min,
                                         ranges::kLimiterLookaheadMs.max}) {
                    limiter.configure(lookahead, threshold, release, true);
                    check(nearlyEqual(limiter.getThresholdDb(), threshold),
                          "LookaheadLimiter must not re-clamp thresholdDb");
                    check(nearlyEqual(limiter.getReleaseMs(), release),
                          "LookaheadLimiter must not re-clamp releaseMs");
                    check(nearlyEqual(limiter.getLookaheadMs(), lookahead),
                          "LookaheadLimiter must not re-clamp lookaheadMs");
                }
            }
        }
    }
    {
        Crossfeed crossfeed;
        crossfeed.setSampleRate(48000.0);
        crossfeed.configure(ranges::kCrossfeedDelayUs.min, ranges::kCrossfeedFeedDb.min,
                            ranges::kCrossfeedFcutHz.min);
        check(nearlyEqual(crossfeed.getDelayUs(), ranges::kCrossfeedDelayUs.min) &&
                  nearlyEqual(crossfeed.getFeedDb(), ranges::kCrossfeedFeedDb.min) &&
                  nearlyEqual(crossfeed.getFcut(), ranges::kCrossfeedFcutHz.min),
              "Crossfeed must accept the table minimum");
        crossfeed.configure(ranges::kCrossfeedDelayUs.max, ranges::kCrossfeedFeedDb.max,
                            ranges::kCrossfeedFcutHz.max);
        check(nearlyEqual(crossfeed.getDelayUs(), ranges::kCrossfeedDelayUs.max) &&
                  nearlyEqual(crossfeed.getFeedDb(), ranges::kCrossfeedFeedDb.max) &&
                  nearlyEqual(crossfeed.getFcut(), ranges::kCrossfeedFcutHz.max),
              "Crossfeed must accept the table maximum");
    }
    {
        SubCrossover crossover;
        crossover.setSampleRate(48000.0);
        crossover.configure(ranges::kSubCrossoverCornerHz.min, 24.0,
                            ranges::kSubCrossoverGain.min, true, true);
        check(nearlyEqual(crossover.getCornerHz(), ranges::kSubCrossoverCornerHz.min) &&
                  nearlyEqual(crossover.getSubGain(), ranges::kSubCrossoverGain.min),
              "SubCrossover must accept the table minimum");
        crossover.configure(ranges::kSubCrossoverCornerHz.max, 24.0,
                            ranges::kSubCrossoverGain.max, true, true);
        check(nearlyEqual(crossover.getCornerHz(), ranges::kSubCrossoverCornerHz.max) &&
                  nearlyEqual(crossover.getSubGain(), ranges::kSubCrossoverGain.max),
              "SubCrossover must accept the table maximum");
    }
    {
        DynamicEQ dsp;
        dsp.setSampleRate(48000.0);
        DynamicEqBandParam band;
        band.frequency = ranges::kDynamicEqFrequencyHz.min;
        band.q = ranges::kDynamicEqQ.min;
        band.thresholdDb = ranges::kDynamicEqThresholdDb.min;
        band.ratio = ranges::kDynamicEqRatio.min;
        band.attackMs = ranges::kDynamicEqAttackMs.min;
        band.releaseMs = ranges::kDynamicEqReleaseMs.min;
        band.maxCutDb = ranges::kDynamicEqMaxCutDb.min;
        band.maxBoostDb = ranges::kDynamicEqMaxBoostDb.min;
        dsp.setBand(0, band);
        DynamicEqBandParam applied = dsp.getBandParams(0);
        check(nearlyEqual(applied.frequency, band.frequency) &&
                  nearlyEqual(applied.q, band.q) &&
                  nearlyEqual(applied.thresholdDb, band.thresholdDb) &&
                  nearlyEqual(applied.ratio, band.ratio) &&
                  nearlyEqual(applied.attackMs, band.attackMs) &&
                  nearlyEqual(applied.releaseMs, band.releaseMs) &&
                  nearlyEqual(applied.maxCutDb, band.maxCutDb) &&
                  nearlyEqual(applied.maxBoostDb, band.maxBoostDb),
              "DynamicEQ must accept every table minimum unmodified");

        band.frequency = ranges::kDynamicEqFrequencyHz.max;
        band.q = ranges::kDynamicEqQ.max;
        band.thresholdDb = ranges::kDynamicEqThresholdDb.max;
        band.ratio = ranges::kDynamicEqRatio.max;
        band.attackMs = ranges::kDynamicEqAttackMs.max;
        band.releaseMs = ranges::kDynamicEqReleaseMs.max;
        band.maxCutDb = ranges::kDynamicEqMaxCutDb.max;
        band.maxBoostDb = ranges::kDynamicEqMaxBoostDb.max;
        dsp.setBand(0, band);
        applied = dsp.getBandParams(0);
        check(nearlyEqual(applied.frequency, band.frequency) &&
                  nearlyEqual(applied.q, band.q) &&
                  nearlyEqual(applied.thresholdDb, band.thresholdDb) &&
                  nearlyEqual(applied.ratio, band.ratio) &&
                  nearlyEqual(applied.attackMs, band.attackMs) &&
                  nearlyEqual(applied.releaseMs, band.releaseMs) &&
                  nearlyEqual(applied.maxCutDb, band.maxCutDb) &&
                  nearlyEqual(applied.maxBoostDb, band.maxBoostDb),
              "DynamicEQ must accept every table maximum unmodified");
    }

    // ---- Dither depth is a discrete set (item 11) --------------------------
    {
        engine.updateParams([](DspParamSnapshot& s) { s.dither.targetBitDepth = 20; });
        check(engine.getParams()->dither.targetBitDepth == 16,
              "an unsupported dither depth must fall back to 16");
        engine.updateParams([](DspParamSnapshot& s) { s.dither.targetBitDepth = 24; });
        check(engine.getParams()->dither.targetBitDepth == 24,
              "a supported dither depth must survive");
        engine.updateParams([](DspParamSnapshot& s) { s.bitPerfect.directUsbGain = 4.0; });
        check(nearlyEqual(engine.getParams()->bitPerfect.directUsbGain, 1.0),
              "direct USB gain above unity must clamp to 1.0");
        engine.updateParams([](DspParamSnapshot& s) { s.bitPerfect.directUsbGain = -2.0; });
        check(nearlyEqual(engine.getParams()->bitPerfect.directUsbGain, 0.0),
              "direct USB gain below zero must clamp to 0.0");
    }

    if (gFailures != 0) {
        std::printf("[FAIL] %d parameter-range check(s) failed.\n", gFailures);
        return 1;
    }
    std::printf("[PASS] Every table bound survives the sanitizer and the stage clamps.\n");
    return 0;
}
