// android/app/src/test/cpp/test_oversampler.cpp
//
// Host test for pulsr::Oversampler (Contract C). Everything here is measured from
// the public process() path: frame accounting, impulse-response magnitude via DFT,
// latency against the measured impulse-response peak, linear-phase symmetry,
// minimum-phase sanity, silence, and per-channel state isolation.
#include "../../main/cpp/Oversampler.h"
#include "../../main/cpp/FftUtil.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <limits>
#include <vector>

namespace {

int gFailures = 0;

void Check(bool ok, const char* what) {
    if (!ok) {
        std::printf("  FAIL %s\n", what);
        ++gFailures;
    }
}

void CheckNear(double got, double want, double tol, const char* what) {
    if (!(std::abs(got - want) <= tol)) {
        std::printf("  FAIL %s: got %.6f want %.6f (tol %.6g)\n", what, got, want, tol);
        ++gFailures;
    }
}

const char* KernelName(pulsr::OversampleKernel k) {
    switch (k) {
        case pulsr::OversampleKernel::Sharp: return "Sharp";
        case pulsr::OversampleKernel::Slow: return "Slow";
        case pulsr::OversampleKernel::MinimumPhase: return "MinimumPhase";
        case pulsr::OversampleKernel::Apodizing: return "Apodizing";
    }
    return "?";
}

// Runs one unit impulse through the public API and returns the whole response.
std::vector<float> ImpulseResponse(int factor, pulsr::OversampleKernel kernel, int inFrames,
                                   int* latency = nullptr, bool* configured = nullptr) {
    pulsr::Oversampler os;
    const bool ok = os.configure(1, factor, kernel);
    if (configured != nullptr) *configured = ok;
    std::vector<float> out(size_t(inFrames) * size_t(factor), 0.0f);
    if (!ok) return out;
    std::vector<float> in(size_t(inFrames), 0.0f);
    in[0] = 1.0f;
    const float* pin[1] = {in.data()};
    float* pout[1] = {out.data()};
    const int emitted = os.process(pin, pout, inFrames);
    Check(emitted == inFrames * factor, "impulse probe emitted the expected frame count");
    if (latency != nullptr) *latency = os.latencyFrames();
    return out;
}

// Magnitude response in dB, normalised to DC, on an fftSize grid.
std::vector<float> MagnitudeDb(const std::vector<float>& ir, int fftSize) {
    std::vector<FftUtil::Complex> buf(size_t(fftSize), FftUtil::Complex(0.0f, 0.0f));
    for (size_t i = 0; i < ir.size() && i < size_t(fftSize); ++i) {
        buf[i] = FftUtil::Complex(ir[i], 0.0f);
    }
    FftUtil::fft(buf);
    std::vector<float> db(size_t(fftSize / 2 + 1), 0.0f);
    const float ref = std::max(std::abs(buf[0]), 1e-20f);
    for (size_t k = 0; k < db.size(); ++k) {
        db[k] = 20.0f * std::log10(std::max(std::abs(buf[k]), 1e-20f) / ref);
    }
    return db;
}

// Frequency (as a fraction of the DFT band, 0..0.5 = 0..Nyquist) where the
// response first falls below `thresholdDb`, linearly interpolated between bins.
double CrossingFrequency(const std::vector<float>& db, double thresholdDb) {
    for (size_t k = 1; k < db.size(); ++k) {
        if (db[k] <= thresholdDb) {
            const double prev = db[k - 1];
            const double frac = (prev - thresholdDb) / std::max(1e-9, prev - db[k]);
            return (double(k - 1) + std::clamp(frac, 0.0, 1.0)) / double(db.size() - 1);
        }
    }
    return 0.5;
}

int ArgMaxAbs(const std::vector<float>& v) {
    int best = 0;
    float bestMag = 0.0f;
    for (size_t i = 0; i < v.size(); ++i) {
        const float m = std::abs(v[i]);
        if (m > bestMag) {
            bestMag = m;
            best = int(i);
        }
    }
    return best;
}

// Independently measured DC group delay (first moment) of an impulse response.
// For a symmetric response this equals the constant group delay exactly; for a
// minimum-phase response it is the low-frequency delay.
int CentroidDelay(const std::vector<float>& ir) {
    double moment = 0.0;
    double sum = 0.0;
    for (size_t i = 0; i < ir.size(); ++i) {
        moment += double(i) * double(ir[i]);
        sum += double(ir[i]);
    }
    if (std::abs(sum) < 1e-12) return -1;
    return int(std::ceil(moment / sum - 1e-9));
}

// Largest |ir[peak+k] - ir[peak-k]| over the valid range: 0 for a symmetric
// (linear-phase) response, clearly non-zero for a minimum-phase one.
double SymmetryError(const std::vector<float>& ir, int peak) {
    double worst = 0.0;
    const int limit = std::min(peak, int(ir.size()) - 1 - peak);
    for (int k = 1; k <= limit; ++k) {
        worst = std::max(worst, double(std::abs(ir[size_t(peak + k)] - ir[size_t(peak - k)])));
    }
    return worst;
}

void TestFrameAccounting() {
    std::printf("[TEST] exact frame accounting (factors 2/4/8, odd block sizes)\n");
    const int factors[3] = {2, 4, 8};
    const int blocks[6] = {0, 1, 7, 511, 512, 1000};
    for (int factor : factors) {
        for (int block : blocks) {
            for (pulsr::OversampleKernel kernel :
                 {pulsr::OversampleKernel::Sharp, pulsr::OversampleKernel::MinimumPhase}) {
                pulsr::Oversampler os;
                Check(os.configure(2, factor, kernel), "configure(2 channels)");
                const int outFrames = block * factor;
                std::vector<float> lIn(size_t(block), 0.25f), rIn(size_t(block), -0.25f);
                // One guard sample past the end of each channel buffer so an
                // over-write is detectable.
                std::vector<float> lOut(size_t(outFrames) + 1, -12345.0f);
                std::vector<float> rOut(size_t(outFrames) + 1, -12345.0f);
                const float* pin[2] = {lIn.data(), rIn.data()};
                float* pout[2] = {lOut.data(), rOut.data()};
                const int emitted = os.process(pin, pout, block);
                if (emitted != outFrames) {
                    std::printf("  FAIL factor %d block %d: emitted %d want %d\n", factor, block,
                                emitted, outFrames);
                    ++gFailures;
                }
                if (lOut[size_t(outFrames)] != -12345.0f || rOut[size_t(outFrames)] != -12345.0f) {
                    std::printf("  FAIL factor %d block %d: wrote past the output buffer\n", factor,
                                block);
                    ++gFailures;
                }
            }
        }
    }
    std::printf("  OK 2/4/8 x {0,1,7,511,512,1000} frames emit exactly N*factor\n");
}

void TestRejection() {
    std::printf("[TEST] invalid configuration and null arguments are rejected\n");
    pulsr::Oversampler os;
    std::vector<float> buf(64, 0.0f);
    const float* pin[2] = {buf.data(), buf.data()};
    float* pout[2] = {buf.data(), buf.data()};
    Check(os.process(pin, pout, 8) == -1, "process before configure returns -1");
    Check(!os.configure(0, 2, pulsr::OversampleKernel::Sharp), "channels=0 rejected");
    Check(!os.configure(9, 2, pulsr::OversampleKernel::Sharp), "channels=9 rejected");
    Check(!os.configure(2, 3, pulsr::OversampleKernel::Sharp), "factor=3 rejected");
    Check(!os.configure(2, 16, pulsr::OversampleKernel::Sharp), "factor=16 rejected");
    Check(os.configure(2, 2, pulsr::OversampleKernel::Sharp), "valid configure accepted");
    Check(os.process(nullptr, pout, 8) == -1, "null input rejected");
    Check(os.process(pin, nullptr, 8) == -1, "null output rejected");
    Check(os.process(pin, pout, -1) == -1, "negative frame count rejected");
    const float* badIn[2] = {buf.data(), nullptr};
    float* badOut[2] = {buf.data(), buf.data()};
    Check(os.process(badIn, badOut, 8) == -1, "null channel pointer rejected");
    const float* oneIn[2] = {buf.data(), buf.data()};
    Check(os.process(oneIn, badOut, 8) == 16, "valid stereo pair accepted");
    os.release();
    Check(os.process(pin, pout, 8) == -1, "process after release returns -1");
    Check(os.latencyFrames() == 0, "released latency is 0");
    std::printf("  OK rejection paths leave the object usable/released as documented\n");
}

void TestStopbandAndRolloff() {
    std::printf("[TEST] impulse-response magnitude (DFT) - sharp stopband, apodizing rolloff\n");
    const int fftSize = 16384;
    const int factors[3] = {2, 4, 8};
    for (int factor : factors) {
        const std::vector<float> ir = ImpulseResponse(factor, pulsr::OversampleKernel::Sharp, 512);
        const std::vector<float> db = MagnitudeDb(ir, fftSize);
        // 0.55 * fs/2 of the output rate == bin 0.275 * fftSize.
        const size_t firstStop = size_t(0.275 * double(fftSize));
        float worst = -1000.0f;
        size_t worstBin = 0;
        for (size_t k = firstStop; k < db.size(); ++k) {
            if (db[k] > worst) {
                worst = db[k];
                worstBin = k;
            }
        }
        const double worstFreq = 2.0 * double(worstBin) / double(fftSize);
        std::printf("  factor %d Sharp: worst stopband %.1f dB at %.3f*Fs_out/2\n", factor, worst,
                    worstFreq);
        if (worst > -90.0f) {
            std::printf("  FAIL factor %d Sharp stopband %.1f dB is above -90 dB\n", factor, worst);
            ++gFailures;
        }
        // Passband must stay flat up to 0.45 * Nyquist_in. Nyquist_in is
        // Fs_out/(2*factor), i.e. bin fftSize/(2*factor).
        const size_t passBins = size_t(0.45 * double(fftSize) / (2.0 * double(factor)));
        float worstPass = -1000.0f;
        for (size_t k = 0; k < passBins && k < db.size(); ++k) worstPass = std::max(worstPass, db[k]);
        Check(worstPass < 0.05f && worstPass > -0.05f, "Sharp passband within +/-0.05 dB");
        std::printf("  factor %d Sharp: passband deviation %.3f dB\n", factor, worstPass);
    }

    const std::vector<float> sharpIr = ImpulseResponse(2, pulsr::OversampleKernel::Sharp, 512);
    const std::vector<float> apodIr = ImpulseResponse(2, pulsr::OversampleKernel::Apodizing, 512);
    const std::vector<float> slowIr = ImpulseResponse(2, pulsr::OversampleKernel::Slow, 512);
    const std::vector<float> sharpDb = MagnitudeDb(sharpIr, fftSize);
    const std::vector<float> apodDb = MagnitudeDb(apodIr, fftSize);
    const std::vector<float> slowDb = MagnitudeDb(slowIr, fftSize);
    const double sharpCross = CrossingFrequency(sharpDb, -3.0);
    const double apodCross = CrossingFrequency(apodDb, -3.0);
    const double slowCross = CrossingFrequency(slowDb, -3.0);
    std::printf("  -3 dB point (x Fs_out/2): Sharp %.4f, Apodizing %.4f, Slow %.4f\n",
                sharpCross, apodCross, slowCross);
    Check(apodCross < 0.5 * 0.97, "Apodizing -3 dB point is below the input Nyquist");
    Check(apodCross < sharpCross * 0.97, "Apodizing rolls off earlier than Sharp");
    Check(slowCross <= sharpCross, "Slow does not extend above Sharp");
    // Slope sanity: the apodizing transition is gentle, i.e. it loses 20 dB more
    // than 0.1 * Nyquist_in away from its -3 dB point.
    const size_t apodThird = size_t((apodCross + 0.05) * double(fftSize / 2));
    std::printf("  Apodizing %.1f dB at -3dB+0.05 (gentle transition)\n",
                apodThird < apodDb.size() ? apodDb[apodThird] : 0.0f);
    Check(apodThird < apodDb.size() && apodDb[apodThird] < -3.0f, "Apodizing keeps rolling off");
}

void TestLatency() {
    std::printf("[TEST] latencyFrames() vs measured impulse-response group delay\n");
    const int factors[3] = {2, 4, 8};
    int sharpLatency8 = 0;
    for (int factor : factors) {
        for (pulsr::OversampleKernel kernel :
             {pulsr::OversampleKernel::Sharp, pulsr::OversampleKernel::Slow,
              pulsr::OversampleKernel::MinimumPhase, pulsr::OversampleKernel::Apodizing}) {
            int latency = 0;
            bool ok = false;
            const std::vector<float> ir = ImpulseResponse(factor, kernel, 512, &latency, &ok);
            Check(ok, "configure for latency probe");
            const int peak = ArgMaxAbs(ir);
            const int measured = CentroidDelay(ir);
            std::printf("  factor %d %-12s latency %4d measured %4d peak %4d (of %zu)\n", factor,
                        KernelName(kernel), latency, measured, peak, ir.size());
            Check(latency > 0, "latency is non-zero");
            if (measured != latency) {
                std::printf("  FAIL factor %d %s: latency %d != measured group delay %d\n", factor,
                            KernelName(kernel), latency, measured);
                ++gFailures;
            }
            if (kernel != pulsr::OversampleKernel::MinimumPhase && peak != latency) {
                std::printf("  FAIL factor %d %s: latency %d != measured peak %d\n", factor,
                            KernelName(kernel), latency, peak);
                ++gFailures;
            }
            if (kernel == pulsr::OversampleKernel::Sharp && factor == 8) sharpLatency8 = latency;
        }
    }
    // Linear phase kernels: symmetric impulse response about the reported latency.
    for (int factor : factors) {
        for (pulsr::OversampleKernel kernel : {pulsr::OversampleKernel::Sharp,
                                               pulsr::OversampleKernel::Slow,
                                               pulsr::OversampleKernel::Apodizing}) {
            int latency = 0;
            const std::vector<float> ir = ImpulseResponse(factor, kernel, 512, &latency);
            const double asym = SymmetryError(ir, latency);
            std::printf("  factor %d %-12s symmetry error %.3e (linear phase)\n", factor,
                        KernelName(kernel), asym);
            if (asym > 1e-6) {
                std::printf("  FAIL %s is not linear phase about the reported latency\n",
                            KernelName(kernel));
                ++gFailures;
            }
        }
    }
    // Minimum phase: verified as spectrally factored, genuinely asymmetric, and
    // with much less bulk delay than the linear-phase kernel of the same length.
    int mpLatency = 0;
    bool mpOk = false;
    const std::vector<float> mpIr = ImpulseResponse(8, pulsr::OversampleKernel::MinimumPhase, 512,
                                                    &mpLatency, &mpOk);
    Check(mpOk, "minimum-phase probe configured");
    pulsr::Oversampler mp;
    mp.configure(2, 8, pulsr::OversampleKernel::MinimumPhase);
    Check(mp.minimumPhaseVerified(), "MinimumPhase kernel passed its spectral-factor check");
    std::printf("  MinimumPhase: verified=%d max magnitude error %.4f dB\n",
                int(mp.minimumPhaseVerified()), double(mp.minimumPhaseMaxErrorDb()));
    Check(mp.minimumPhaseMaxErrorDb() < 0.05f, "minimum-phase magnitude matches the prototype");
    const double mpAsym = SymmetryError(mpIr, mpLatency);
    const int mpMeasured = CentroidDelay(mpIr);
    std::printf("  MinimumPhase: latency %d measured %d (Sharp 8x %d), symmetry error %.3e\n",
                mpLatency, mpMeasured, sharpLatency8, mpAsym);
    Check(mpMeasured == mpLatency, "MinimumPhase latency matches its measured group delay");
    Check(mpAsym > 1e-3, "MinimumPhase impulse response is asymmetric (not linear phase)");
    Check(mpLatency * 2 < sharpLatency8, "MinimumPhase bulk delay is well below Sharp's");
}

void TestSilenceAndIsolation() {
    std::printf("[TEST] silence in -> silence out, per-channel state isolation\n");
    pulsr::Oversampler os;
    Check(os.configure(2, 8, pulsr::OversampleKernel::Sharp), "configure stereo 8x");
    const int frames = 700;  // > one internal chunk, not a multiple of it
    std::vector<float> lIn(size_t(frames), 0.0f), rIn(size_t(frames), 0.0f);
    std::vector<float> lOut(size_t(frames) * 8), rOut(size_t(frames) * 8);
    const float* pin[2] = {lIn.data(), rIn.data()};
    float* pout[2] = {lOut.data(), rOut.data()};
    Check(os.process(pin, pout, frames) == frames * 8, "silence block frame count");
    float peak = 0.0f;
    for (float v : lOut) peak = std::max(peak, std::abs(v));
    for (float v : rOut) peak = std::max(peak, std::abs(v));
    std::printf("  silence peak %.3e\n", double(peak));
    Check(peak == 0.0f, "silence produces exactly zero");

    // Channel 0 carries a tone, channel 1 stays silent: the silent channel must
    // remain bit-exact zero, which fails immediately if history is shared.
    for (int n = 0; n < frames; ++n) {
        lIn[size_t(n)] = 0.5f * std::sin(0.07f * float(n));
        rIn[size_t(n)] = 0.0f;
    }
    Check(os.process(pin, pout, frames) == frames * 8, "isolation block frame count");
    float silentPeak = 0.0f;
    float loudPeak = 0.0f;
    bool finite = true;
    for (size_t i = 0; i < rOut.size(); ++i) {
        silentPeak = std::max(silentPeak, std::abs(rOut[i]));
        loudPeak = std::max(loudPeak, std::abs(lOut[i]));
        finite = finite && std::isfinite(lOut[i]) && std::isfinite(rOut[i]);
    }
    std::printf("  tone channel peak %.3f, silent channel peak %.3e, all finite=%d\n",
                double(loudPeak), double(silentPeak), int(finite));
    Check(silentPeak == 0.0f, "silent channel is not contaminated by the driven channel");
    Check(loudPeak > 0.1f, "driven channel produced signal");
    Check(finite, "no NaN/Inf in the output");

    // Reverse the roles to catch an off-by-one in the history stride. Reset first so
    // the first block's tail cannot ring into the silent channel.
    os.reset();
    for (int n = 0; n < frames; ++n) {
        lIn[size_t(n)] = 0.0f;
        rIn[size_t(n)] = -0.5f * std::sin(0.07f * float(n));
    }
    Check(os.process(pin, pout, frames) == frames * 8, "isolation (reversed) frame count");
    float leftPeak = 0.0f;
    float rightPeak = 0.0f;
    for (size_t i = 0; i < lOut.size(); ++i) {
        leftPeak = std::max(leftPeak, std::abs(lOut[i]));
        rightPeak = std::max(rightPeak, std::abs(rOut[i]));
    }
    std::printf("  reversed: left %.3e right %.3f\n", double(leftPeak), double(rightPeak));
    Check(leftPeak == 0.0f, "left channel clean when only right is driven");
    Check(rightPeak > 0.1f, "right channel produced signal");

    // reset() must clear history: after a burst, a zero block is exactly silent.
    os.reset();
    std::fill(lIn.begin(), lIn.end(), 0.0f);
    std::fill(rIn.begin(), rIn.end(), 0.0f);
    Check(os.process(pin, pout, frames) == frames * 8, "post-reset frame count");
    float afterReset = 0.0f;
    for (float v : lOut) afterReset = std::max(afterReset, std::abs(v));
    for (float v : rOut) afterReset = std::max(afterReset, std::abs(v));
    Check(afterReset == 0.0f, "reset() clears the filter history");
    std::printf("  OK silence/reset/isolation\n");
}

void TestHalfbandBranch() {
    std::printf("[TEST] 2x halfband stage: one polyphase branch is a pure delay\n");
    // For a halfband prototype every odd tap except the centre is zero, so the odd
    // output samples are an exact delayed copy of the input. Finding that delay by
    // search proves the structure is really halfband (not a generic 2-phase FIR).
    const int frames = 256;
    pulsr::Oversampler os;
    Check(os.configure(1, 2, pulsr::OversampleKernel::Sharp), "configure 2x sharp");
    std::vector<float> in(size_t(frames), 0.0f);
    std::vector<float> out(size_t(frames) * 2, 0.0f);
    for (int n = 0; n < frames; ++n) {
        in[size_t(n)] = 0.7f * std::sin(0.31f * float(n)) + 0.2f * std::cos(0.013f * float(n));
    }
    const float* pin[1] = {in.data()};
    float* pout[1] = {out.data()};
    Check(os.process(pin, pout, frames) == frames * 2, "halfband probe frame count");
    int bestDelay = -1;
    double bestErr = 1e9;
    for (int d = 0; d < frames / 2; ++d) {
        double err = 0.0;
        for (int m = d; m < frames; ++m) {
            err = std::max(err, double(std::abs(out[size_t(2 * m + 1)] - in[size_t(m - d)])));
        }
        if (err < bestErr) {
            bestErr = err;
            bestDelay = d;
        }
    }
    std::printf("  odd branch = input delayed by %d, max error %.3e\n", bestDelay, bestErr);
    Check(bestDelay >= 0 && bestErr < 1e-4, "odd branch is an exact delayed copy of the input");
}

}  // namespace

int main() {
    std::setvbuf(stdout, nullptr, _IONBF, 0);
    std::printf("[TEST] Running Oversampler tests...\n");
    TestFrameAccounting();
    TestRejection();
    TestStopbandAndRolloff();
    TestLatency();
    TestSilenceAndIsolation();
    TestHalfbandBranch();

    if (gFailures == 0) {
        std::printf("[TEST] Oversampler: all checks passed.\n");
        return 0;
    }
    std::printf("[TEST] Oversampler: %d failure(s).\n", gFailures);
    return 1;
}
