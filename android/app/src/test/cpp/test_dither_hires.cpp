// android/app/src/test/cpp/test_dither_hires.cpp
//
// The dither stage gates NOISE SHAPING on the sample rate
// (useShaping = sampleRate_ <= 48000): above 48 kHz it falls back to the
// gentle 0.5*e[n-1] first-order feedback instead of the 1.62/0.82 shaper.
// That fallback must not also drop the TPDF itself or the requantization —
// 96 kHz material still leaves the engine at 16/24-bit, and undithered
// requantization there correlates the truncation error with the signal
// (granular distortion on quiet passages). These cases pin the contract:
//   * above 48 kHz the output is still on the target grid,
//   * TPDF still decorrelates (silence in -> bounded noise out),
//   * the lighter above-48k feedback reaches |k| = 1 LSB less often than
//     the shaped path does at <= 48 kHz.
#include "../../main/cpp/AudioDspEngine.h"
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <memory>
#include <vector>

namespace {

int gFailures = 0;

void check(bool ok, const char* what) {
    if (!ok) {
        std::cout << "[FAIL] " << what << std::endl;
        ++gFailures;
    }
}

struct DitherStats {
    bool onGrid = true;
    double maxAbsLsb = 0.0;     // max |out| in LSB units
    long nonZero = 0;
    long atUnitLsb = 0;         // samples with |k| == 1 exactly
    long total = 0;
};

// Feeds `frames` frames of `level` (one value, both channels) through a
// dither-only engine at `sr` and quantizes the result to LSB-domain stats.
DitherStats runDitherEngine(double sr, int frames, double level) {
    auto engine = std::make_unique<AudioDspEngine>();
    auto snap = std::make_shared<DspParamSnapshot>();
    snap->sampleRate = sr;
    snap->activeStages = STAGE_DITHER;
    snap->dither.enabled = true;
    snap->dither.targetBitDepth = 16;
    engine->setSampleRate(sr);
    engine->publishParams(snap);

    DitherStats st;
    std::vector<float> buf(static_cast<size_t>(512) * 2);
    int done = 0;
    while (done < frames) {
        const int n = std::min(512, frames - done);
        for (int i = 0; i < n * 2; ++i) buf[static_cast<size_t>(i)] = static_cast<float>(level);
        if (engine->processInterleaved(buf.data(), n, 2) != n) {
            check(false, "dither block must preserve frame count");
            return st;
        }
        done += n;
        for (float v : buf) {
            const double k = static_cast<double>(v) * 32768.0;
            st.total++;
            if (std::abs(k - std::rint(k)) > 1e-3) st.onGrid = false;
            st.maxAbsLsb = std::max(st.maxAbsLsb, std::abs(k));
            if (v != 0.0f) st.nonZero++;
            if (std::abs(std::abs(k) - 1.0) < 1e-3) st.atUnitLsb++;
        }
    }
    return st;
}

} // namespace

int main() {
    std::cout << "[TEST] Dither above 48 kHz (TPDF survives the shaping fallback)..."
              << std::endl;

    const int frames = 32768;

    const DitherStats hi = runDitherEngine(96000.0, frames, 0.0);
    const DitherStats lo = runDitherEngine(48000.0, frames, 0.0);

    std::cout << "[info] 96k: P(|k|=1)=" << static_cast<double>(hi.atUnitLsb) / hi.total
              << " maxLsb=" << hi.maxAbsLsb << " nonZero=" << hi.nonZero
              << " | 48k: P=" << static_cast<double>(lo.atUnitLsb) / lo.total
              << " maxLsb=" << lo.maxAbsLsb << std::endl;

    // Above 48 kHz: requantization must still happen (grid) and TPDF must
    // still fire (silence does not stay bit-exact zero).
    check(hi.onGrid, "96 kHz output must still sit on the 16-bit grid");
    check(hi.nonZero > 0, "96 kHz silence must still be dithered (TPDF applied)");
    check(hi.nonZero >= hi.total / 5,
          "TPDF must produce a healthy stream of non-zero samples at 96 kHz");
    // 0.5*e[n-1] feedback stays below the 0.49 clamp, so |quantInput| <=
    // 0.25 + 1.0 (TPDF) < 1.5 -> the requantized sample can never exceed 1 LSB.
    check(hi.maxAbsLsb <= 1.0 + 1e-3,
          "first-order fallback must bound silence output to +/-1 LSB at 96 kHz");

    // The shaped path at <= 48 kHz drives |k| = 1 noticeably more often than
    // the gentle first-order feedback above 48 kHz (1.62/0.82 saturates the
    // +/-0.49 clamp; 0.5 does not). Deterministic xorshift -> stable margin.
    const double pHi = static_cast<double>(hi.atUnitLsb) / static_cast<double>(hi.total);
    const double pLo = static_cast<double>(lo.atUnitLsb) / static_cast<double>(lo.total);
    check(pLo > pHi, "noise shaping must push more +/-1 LSB steps than the 96k fallback");

    // A quiet tone below the grid still gets requantized at 96 kHz, within
    // the dither bound of the exact rounded value.
    {
        auto engine = std::make_unique<AudioDspEngine>();
        auto snap = std::make_shared<DspParamSnapshot>();
        snap->sampleRate = 96000.0;
        snap->activeStages = STAGE_DITHER;
        snap->dither.enabled = true;
        snap->dither.targetBitDepth = 16;
        engine->setSampleRate(96000.0);
        engine->publishParams(snap);
        std::vector<float> buf(static_cast<size_t>(512) * 2, 0.0f);
        long gridMiss = 0;
        for (int b = 0; b < frames / 512; ++b) {
            const double t = static_cast<double>(b * 512) / 96000.0;
            for (int i = 0; i < 512; ++i) {
                const double s =
                    0.3 * std::sin(2.0 * 3.14159265358979323846 * 211.0 *
                                   (t + static_cast<double>(i) / 96000.0));
                buf[static_cast<size_t>(i) * 2] = static_cast<float>(s);
                buf[static_cast<size_t>(i) * 2 + 1] = static_cast<float>(s);
            }
            engine->processInterleaved(buf.data(), 512, 2);
            for (int i = 0; i < 512 * 2; ++i) {
                const double k = static_cast<double>(buf[static_cast<size_t>(i)]) * 32768.0;
                if (std::abs(k - std::rint(k)) > 1e-3) ++gridMiss;
            }
        }
        check(gridMiss == 0, "tonal input at 96 kHz must be requantized to the 16-bit grid");
    }

    // Dither OFF at 96 kHz must be bit-transparent: the same silence stays
    // exactly zero (the stage does not touch the buffer without its bit).
    {
        auto engine = std::make_unique<AudioDspEngine>();
        auto snap = std::make_shared<DspParamSnapshot>();
        snap->sampleRate = 96000.0;
        snap->activeStages = STAGE_DITHER;
        snap->dither.enabled = false;
        engine->setSampleRate(96000.0);
        engine->publishParams(snap);
        std::vector<float> buf(static_cast<size_t>(512) * 2, 0.0f);
        std::vector<float> zero = buf;
        for (int b = 0; b < 8; ++b) {
            engine->processInterleaved(buf.data(), 512, 2);
        }
        check(buf == zero, "dither flag off at 96 kHz must not touch silence");
    }

    if (gFailures != 0) {
        std::cout << "[FAIL] " << gFailures << " dither above-48k check(s) failed." << std::endl;
        return 1;
    }
    std::cout << "[PASS] TPDF + requantization still apply above 48 kHz, with the "
              << "documented lighter feedback." << std::endl;
    return 0;
}
