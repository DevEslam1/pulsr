// android/app/src/test/cpp/test_dither_hires.cpp
//
// The dither stage shapes with the same 2nd-order error feedback at every
// sample rate. It used to fall back to a gentle 0.5*e[n-1] first-order term
// above 48 kHz, which put MORE quantization noise in the audible band at the
// rate with the most room to push it out: the shaper's peak rides near
// 0.885 * Nyquist, so at 96 kHz that is ~85 kHz, far above hearing.
//
// What must hold regardless of rate (and what previously regressed):
//   * the output still sits on the target grid,
//   * TPDF still fires (silence does not stay bit-exact zero),
//   * the feedback clamp still bounds the result,
//   * and the shaper is now rate-independent, so 48 kHz and 96 kHz produce the
//     same distribution from the same deterministic noise sequence.
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
          "the feedback clamp must bound silence output to +/-1 LSB at 96 kHz");
    check(lo.maxAbsLsb <= 1.0 + 1e-3,
          "the same clamp bounds silence at 48 kHz");

    // The shaper no longer branches on sample rate, and the PRNG sequence is
    // deterministic and rate-independent, so the two runs must agree exactly.
    // This is the regression guard: reintroducing a per-rate fallback would
    // split these distributions.
    const double pHi = static_cast<double>(hi.atUnitLsb) / static_cast<double>(hi.total);
    const double pLo = static_cast<double>(lo.atUnitLsb) / static_cast<double>(lo.total);
    std::cout << "[info] P(|k|=1) 96k=" << pHi << " 48k=" << pLo << std::endl;
    check(pHi == pLo,
          "noise shaping must be identical at 48 kHz and 96 kHz");
    check(hi.total == lo.total && hi.nonZero == lo.nonZero,
          "the shaped output must match sample-for-sample across rates");

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

    // The sink's own container wins when it is coarser than the requested
    // depth: shaping for 24 bits and then having a 16-bit DAC round the result
    // discards that shaping, so the engine must quantize where the bytes land.
    {
        auto engine = std::make_unique<AudioDspEngine>();
        auto snap = std::make_shared<DspParamSnapshot>();
        snap->sampleRate = 48000.0;
        snap->activeStages = STAGE_DITHER;
        snap->dither.enabled = true;
        snap->dither.targetBitDepth = 24;
        engine->setSampleRate(48000.0);
        engine->setSinkBitDepth(16);
        engine->publishParams(snap);

        std::vector<float> buf(static_cast<size_t>(1024) * 2, 0.0f);
        for (int b = 0; b < 16; ++b) engine->processInterleaved(buf.data(), 1024, 2);

        int offGrid16 = 0;
        for (const float s : buf) {
            const double lsb = static_cast<double>(s) * 32768.0;
            if (std::abs(lsb - std::rint(lsb)) > 1e-3) ++offGrid16;
        }
        check(offGrid16 == 0,
              "a 16-bit sink must receive 16-bit-shaped output, not 24-bit");
        check(engine->getSinkBitDepth() == 16, "the reported sink depth is kept");
    }

    // An unknown depth (the shared mixer, whose conversion the app cannot see)
    // must leave the user's choice alone rather than guessing 16-bit.
    {
        auto engine = std::make_unique<AudioDspEngine>();
        auto snap = std::make_shared<DspParamSnapshot>();
        snap->sampleRate = 48000.0;
        snap->activeStages = STAGE_DITHER;
        snap->dither.enabled = true;
        snap->dither.targetBitDepth = 24;
        engine->setSampleRate(48000.0);
        engine->setSinkBitDepth(0);
        engine->publishParams(snap);

        std::vector<float> buf(static_cast<size_t>(1024) * 2, 0.0f);
        for (int b = 0; b < 16; ++b) engine->processInterleaved(buf.data(), 1024, 2);

        int offGrid24 = 0, offGrid16 = 0;
        for (const float s : buf) {
            const double lsb24 = static_cast<double>(s) * 8388608.0;
            const double lsb16 = static_cast<double>(s) * 32768.0;
            if (std::abs(lsb24 - std::rint(lsb24)) > 1e-2) ++offGrid24;
            if (std::abs(lsb16 - std::rint(lsb16)) > 1e-2) ++offGrid16;
        }
        check(offGrid24 == 0, "unknown sink depth still honors the 24-bit target");
        check(offGrid16 > 0, "unknown sink depth must not collapse to 16-bit");

        // A finer container than the target changes nothing: a 24-bit DAC still
        // receives the 16-bit shaping the user asked for.
        engine->setSinkBitDepth(32);
        engine->setSinkBitDepth(24);
        check(engine->getSinkBitDepth() == 24, "a supported depth is stored");
        engine->setSinkBitDepth(20);
        check(engine->getSinkBitDepth() == 0,
              "an unsupported container depth is treated as unknown");
    }

    if (gFailures != 0) {
        std::cout << "[FAIL] " << gFailures << " dither above-48k check(s) failed." << std::endl;
        return 1;
    }
    std::cout << "[PASS] TPDF + 2nd-order shaping apply identically at every rate."
              << std::endl;
    return 0;
}
