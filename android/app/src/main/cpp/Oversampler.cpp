// android/app/src/main/cpp/Oversampler.cpp
#include "Oversampler.h"

#include "FftUtil.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <limits>

namespace pulsr {
namespace {

constexpr double kPi = 3.14159265358979323846;

// Largest distance from the nominal band edge, as a fraction of the stage
// output rate, that the prototype is allowed to occupy. Used for validation.
constexpr int kMinimumTaps = 3;

double Sinc(double x) {
    if (std::abs(x) < 1e-12) return 1.0;
    return std::sin(kPi * x) / (kPi * x);
}

// Modified Bessel function of the first kind, order 0 (power series; the Kaiser
// window only needs ~1e-18 relative accuracy for beta <= 12).
double BesselI0(double x) {
    double sum = 1.0;
    double term = 1.0;
    const double q = 0.25 * x * x;
    for (int k = 1; k < 64; ++k) {
        term *= q / (double(k) * double(k));
        sum += term;
        if (term < 1e-18 * sum) break;
    }
    return sum;
}

double KaiserWindow(double beta, int index, int length) {
    if (length <= 1) return 1.0;
    const double r = 2.0 * double(index) / double(length - 1) - 1.0;
    const double t = 1.0 - r * r;
    return BesselI0(beta * std::sqrt(std::max(0.0, t))) / BesselI0(beta);
}

struct KernelSpec {
    int taps;
    double cutoff;  // normalised to the *stage output* rate, 0..0.5
    double beta;    // Kaiser shape
    bool halfband;  // cutoff is exactly 0.25 -> force the zero taps
};

KernelSpec SpecFor(OversampleKernel kernel) {
    switch (kernel) {
        case OversampleKernel::Sharp:
            // Long, ~-110 dB design: 163 taps with a 0.10 (of Fs_out) transition.
            return {163, 0.25, 10.0, true};
        case OversampleKernel::Slow:
            // NOS-adjacent: 31 taps leave a very wide, gentle transition and only
            // modest image rejection, trading accuracy for minimal time smear.
            return {31, 0.25, 4.0, true};
        case OversampleKernel::Apodizing:
            // -3 dB at ~0.45*Fs_in because the cut-off sits below Nyquist.
            return {95, 0.225, 6.5, false};
        case OversampleKernel::MinimumPhase:
            // The prototype whose magnitude response is spectrally factored; the
            // factor keeps the full length, so this kernel costs ~2x a halfband one.
            return {163, 0.25, 10.0, true};
    }
    return {163, 0.25, 10.0, true};
}

// Builds a symmetric windowed-sinc lowpass sampled at the 2x (stage output) rate.
// Normalised so that the zero-stuffed interpolator has unity DC gain: sum == 2,
// which is what makes both polyphase branches sum to ~1 (the residual difference
// is the response at Fs_out/2, i.e. the image rejection itself).
std::vector<float> DesignPrototype(int taps, double cutoff, double beta, bool halfband) {
    std::vector<float> h;
    if (taps < kMinimumTaps || (taps % 2) == 0) return h;
    if (!(cutoff > 0.0 && cutoff < 0.5)) return h;

    h.assign(size_t(taps), 0.0f);
    const int centre = (taps - 1) / 2;
    double sum = 0.0;
    for (int k = 0; k < taps; ++k) {
        const int d = k - centre;
        double v = 2.0 * cutoff * Sinc(2.0 * cutoff * double(d)) *
                   KaiserWindow(beta, k, taps);
        if (halfband && d != 0 && (d % 2) == 0) {
            v = 0.0;  // exact halfband zeros, free of sin(pi*n/2) residue
        }
        h[size_t(k)] = float(v);
        sum += v;
    }
    if (!(sum > 1e-9)) {
        h.clear();
        return h;
    }
    const float scale = float(2.0 / sum);
    for (int k = 0; k < taps; ++k) h[size_t(k)] *= scale;
    return h;
}

// True minimum-phase spectral factor of a real, symmetric FIR prototype via the
// homomorphic (cepstral) method:
//   log|H(w)| --IFFT--> real cepstrum --fold--> causal cepstrum --FFT--> log Hmin
//   --exp--> Hmin(w) --IFFT--> h_min[n]
// The result is causal with every zero inside the unit circle and has the same
// magnitude response as the prototype. `out` receives the (taps+1)/2 samples that
// carry the whole response; `maxErrorDb` reports the worst |magnitude| mismatch
// measured against the prototype over the band where the prototype is >= -100 dB.
bool MinimumPhaseFactor(const std::vector<float>& prototype, int fftSize,
                        std::vector<float>* out, float* maxErrorDb) {
    if (out == nullptr || maxErrorDb == nullptr) return false;
    const int taps = int(prototype.size());
    if (taps < kMinimumTaps || (taps % 2) == 0) return false;
    if (fftSize < 8 * taps || (fftSize & (fftSize - 1)) != 0) return false;

    const int m = fftSize;
    std::vector<FftUtil::Complex> spectrum(size_t(m), FftUtil::Complex(0.0f, 0.0f));
    for (int k = 0; k < taps; ++k) spectrum[size_t(k)] = FftUtil::Complex(prototype[size_t(k)], 0.0f);
    FftUtil::fft(spectrum);

    std::vector<FftUtil::Complex> magnitude(size_t(m), FftUtil::Complex(0.0f, 0.0f));
    for (int k = 0; k < m; ++k) {
        const float mag = std::abs(spectrum[size_t(k)]);
        magnitude[size_t(k)] = FftUtil::Complex(std::log(std::max(mag, 1e-30f)), 0.0f);
    }
    // Real cepstrum. log|H| is real and even, so the cepstrum is real and even.
    FftUtil::fft(magnitude, /*invert=*/true);

    // Fold the two-sided cepstrum onto the causal axis: this is the step that
    // turns "same magnitude" into "minimum phase".
    std::vector<FftUtil::Complex> cepstrum(size_t(m), FftUtil::Complex(0.0f, 0.0f));
    cepstrum[0] = magnitude[0];
    for (int n = 1; n < m / 2; ++n) cepstrum[size_t(n)] = magnitude[size_t(n)] * 2.0f;
    cepstrum[size_t(m / 2)] = magnitude[size_t(m / 2)];
    FftUtil::fft(cepstrum);  // log Hmin(w) = log|H| + j*Hilbert(log|H|)

    for (int k = 0; k < m; ++k) cepstrum[size_t(k)] = std::exp(cepstrum[size_t(k)]);
    FftUtil::fft(cepstrum, /*invert=*/true);

    // The minimum-phase factor of a length-N prototype is itself length N: the
    // cepstral reconstruction puts the whole response inside the prototype's span.
    const int minTaps = taps;
    std::vector<float> hmin(size_t(minTaps), 0.0f);
    double tailEnergy = 0.0;
    double totalEnergy = 0.0;
    for (int k = 0; k < minTaps; ++k) {
        hmin[size_t(k)] = cepstrum[size_t(k)].real();
        totalEnergy += double(hmin[size_t(k)]) * double(hmin[size_t(k)]);
    }
    for (int k = minTaps; k < m / 2; ++k) {
        const double v = cepstrum[size_t(k)].real();
        tailEnergy += v * v;
    }
    if (!(totalEnergy > 0.0)) return false;
    // Truncation must not throw away anything meaningful, and a minimum-phase
    // lowpass always starts with positive energy at n = 0.
    if (tailEnergy > 1e-9 * totalEnergy) return false;
    if (!(hmin[0] > 0.0f)) return false;

    // Verify the magnitude reconstruction before claiming minimum phase.
    std::vector<FftUtil::Complex> check(size_t(m), FftUtil::Complex(0.0f, 0.0f));
    for (int k = 0; k < minTaps; ++k) check[size_t(k)] = FftUtil::Complex(hmin[size_t(k)], 0.0f);
    FftUtil::fft(check);
    // Verify against the prototype over the range where a float FFT can resolve it
    // (-80 dB); below that the log-domain round trip has no meaning.
    float worst = 0.0f;
    float worstPass = 0.0f;
    for (int k = 0; k <= m / 2; ++k) {
        const float ref = std::abs(spectrum[size_t(k)]);
        if (ref <= 1e-4f) continue;
        const float got = std::abs(check[size_t(k)]);
        const float errDb = std::abs(20.0f * std::log10(std::max(got, 1e-30f) / ref));
        worst = std::max(worst, errDb);
        if (ref > 0.1f) worstPass = std::max(worstPass, errDb);
    }
    if (worst > 0.05f || worstPass > 0.01f) return false;

    *maxErrorDb = worst;
    out->swap(hmin);
    return true;
}

// Documented causal approximation used only if the homomorphic factor fails its
// own verification: keep the causal half of the symmetric prototype and taper the
// truncation edge. This is *not* minimum phase (it keeps the prototype's zeros
// outside the unit circle in part), so the caller records the downgrade instead of
// labelling it minimum phase.
std::vector<float> CausalHalfFallback(const std::vector<float>& prototype) {
    const int taps = int(prototype.size());
    const int half = (taps + 1) / 2;
    const int centre = (taps - 1) / 2;
    std::vector<float> h(size_t(half), 0.0f);
    double sum = 0.0;
    for (int k = 0; k < half; ++k) {
        double taper = 1.0;
        const int taperLen = std::max(1, half / 4);
        if (k >= half - taperLen) {
            const double t = double(k - (half - taperLen)) / double(taperLen);
            taper = 0.5 + 0.5 * std::cos(kPi * std::min(1.0, t));
        }
        const double v = double(prototype[size_t(centre + k)]) * taper;
        h[size_t(k)] = float(v);
        sum += v;
    }
    if (sum > 1e-9) {
        const float scale = float(1.0 / sum);
        for (int k = 0; k < half; ++k) h[size_t(k)] *= scale;
    }
    return h;
}

}  // namespace

int Oversampler::stageTaps(int stage) const {
    if (!configured_ || stage < 0 || stage >= stages_) return 0;
    return stageChain_[stage].taps;
}

void Oversampler::buildStage(int index, const std::vector<float>& prototype) {
    Stage& st = stageChain_[index];
    st.taps = int(prototype.size());
    st.delay = (st.taps - 1) / 2;
    st.phaseTaps = (st.taps + 1) / 2;
    st.phase0.assign(size_t(st.phaseTaps), 0.0f);
    st.phase1.assign(size_t(st.phaseTaps), 0.0f);
    for (int k = 0; k < st.taps; ++k) {
        if ((k & 1) == 0) {
            st.phase0[size_t(k / 2)] = prototype[size_t(k)];
        } else {
            st.phase1[size_t(k / 2)] = prototype[size_t(k)];
        }
    }
    int nonZero = 0;
    int delayTaps = 0;
    float gain = 0.0f;
    for (int j = 0; j < st.phaseTaps; ++j) {
        const float v = st.phase1[size_t(j)];
        if (v != 0.0f) {
            ++nonZero;
            delayTaps = j;
            gain = v;
        }
    }
    st.phase1IsDelay = (nonZero == 1);
    st.phase1DelayTaps = delayTaps;
    st.phase1Gain = gain;
}

void Oversampler::runStage(int index, int channel, const float* in, float* out, int frames) {
    const Stage& st = stageChain_[index];
    const int p = st.phaseTaps;
    const int histLen = p - 1;
    float* hist = history_[index].data() + size_t(channel) * size_t(histLen);
    float* ext = scratch_.data();
    std::memcpy(ext, hist, size_t(histLen) * sizeof(float));
    std::memcpy(ext + histLen, in, size_t(frames) * sizeof(float));

    const float* a = st.phase0.data();
    const float* b = st.phase1.data();
    if (st.phase1IsDelay) {
        // Halfband structure: one phase is a pure delay, so each output pair costs
        // phaseTaps multiplies instead of 2 * phaseTaps.
        const int d = st.phase1DelayTaps;
        const float g = st.phase1Gain;
        for (int m = 0; m < frames; ++m) {
            const float* base = ext + histLen + m;
            double acc = 0.0;
            for (int j = 0; j < p; ++j) acc += double(a[j]) * double(base[-j]);
            out[2 * m] = float(acc);
            out[2 * m + 1] = g * base[-d];
        }
    } else {
        for (int m = 0; m < frames; ++m) {
            const float* base = ext + histLen + m;
            double accEven = 0.0;
            double accOdd = 0.0;
            for (int j = 0; j < p; ++j) {
                const double v = double(base[-j]);
                accEven += double(a[j]) * v;
                accOdd += double(b[j]) * v;
            }
            out[2 * m] = float(accEven);
            out[2 * m + 1] = float(accOdd);
        }
    }
    // The last histLen samples of [history | in] become the new history; this also
    // handles the first, short block correctly.
    std::memcpy(hist, ext + frames, size_t(histLen) * sizeof(float));
}

void Oversampler::runCascade(int channel, const float* in, float* out, int frames) {
    const float* src = in;
    int n = frames;
    for (int s = 0; s < stages_; ++s) {
        float* dst = (s == stages_ - 1) ? out : stageBuf_[s].data();
        runStage(s, channel, src, dst, n);
        src = dst;
        n *= 2;
    }
}

int Oversampler::measureLatency() {
    // Control-path probe: one unit impulse through the real cascade, then the first
    // moment of the composite impulse response. For a real filter that moment is the
    // group delay at DC; for the symmetric kernels it coincides exactly with the
    // constant group delay (and with the impulse-response peak). For MinimumPhase,
    // where the group delay is frequency dependent, it is the largest in-band delay
    // and therefore the honest number to report.
    constexpr int kProbeFrames = 256;
    const int outFrames = kProbeFrames * factor_;
    if (channels_ < 1 || outFrames <= 0) return 0;
    std::vector<float> probeIn(size_t(kProbeFrames), 0.0f);
    std::vector<float> probeOut(size_t(outFrames), 0.0f);
    probeIn[0] = 1.0f;
    runCascade(0, probeIn.data(), probeOut.data(), kProbeFrames);
    double moment = 0.0;
    double sum = 0.0;
    for (int i = 0; i < outFrames; ++i) {
        const double v = double(probeOut[size_t(i)]);
        moment += double(i) * v;
        sum += v;
    }
    if (!(std::abs(sum) > 1e-9)) return 0;
    const double centroid = moment / sum;
    if (!(centroid >= 0.0)) return 0;
    // Round up: the smallest whole-frame delay that covers the group delay. Exact
    // for the linear-phase kernels (integer by construction), and never reports 0
    // for a minimum-phase kernel whose centroid is below one frame.
    return int(std::ceil(centroid - 1e-9));
}

bool Oversampler::configure(int channels, int factor, OversampleKernel kernel) {
    release();
    if (channels <= 0 || channels > kMaxChannels) return false;
    if (factor != 2 && factor != 4 && factor != 8) return false;

    int stages = 0;
    for (int f = factor; f > 1; f >>= 1) ++stages;

    const KernelSpec spec = SpecFor(kernel);
    std::vector<float> prototype = DesignPrototype(spec.taps, spec.cutoff, spec.beta, spec.halfband);
    if (prototype.empty()) return false;

    bool verified = false;
    float errorDb = 0.0f;
    if (kernel == OversampleKernel::MinimumPhase) {
        std::vector<float> factorTaps;
        if (MinimumPhaseFactor(prototype, 4096, &factorTaps, &errorDb)) {
            verified = true;
            prototype.swap(factorTaps);
        } else {
            // Never label a linear-phase kernel minimum phase: fall back to the
            // documented causal approximation and record that it was used.
            prototype = CausalHalfFallback(prototype);
            errorDb = -1.0f;
        }
        if (prototype.empty()) return false;
    }

    channels_ = channels;
    factor_ = factor;
    stages_ = stages;
    kernel_ = kernel;
    minimumPhaseVerified_ = verified;
    minimumPhaseErrorDb_ = errorDb;

    int maxHist = 0;
    for (int s = 0; s < stages_; ++s) {
        buildStage(s, prototype);
        const int histLen = stageChain_[s].phaseTaps - 1;
        maxHist = std::max(maxHist, histLen);
        history_[s].assign(size_t(channels_) * size_t(histLen), 0.0f);
        stageBuf_[s].assign(size_t(kChunkFrames) << (s + 1), 0.0f);
    }
    // Stage s processes kChunkFrames << s input frames, so the scratch buffer must
    // cover the largest stage, not just stage 0.
    const int maxStageFrames = kChunkFrames << (stages_ - 1);
    scratch_.assign(size_t(maxHist) + size_t(maxStageFrames), 0.0f);

    configured_ = true;
    latencyFrames_ = measureLatency();
    reset();  // the probe left history behind
    return true;
}

void Oversampler::reset() {
    if (!configured_) return;
    for (int s = 0; s < stages_; ++s) std::fill(history_[s].begin(), history_[s].end(), 0.0f);
}

void Oversampler::release() {
    for (int s = 0; s < kMaxStages; ++s) {
        stageChain_[s] = Stage{};
        std::vector<float>().swap(history_[s]);
        std::vector<float>().swap(stageBuf_[s]);
    }
    std::vector<float>().swap(scratch_);
    channels_ = 0;
    factor_ = 0;
    stages_ = 0;
    latencyFrames_ = 0;
    configured_ = false;
    minimumPhaseVerified_ = false;
    minimumPhaseErrorDb_ = 0.0f;
}

int Oversampler::process(const float* const* in, float* const* out, int inFrames) {
    if (!configured_ || in == nullptr || out == nullptr || inFrames < 0) return -1;
    if (inFrames == 0) return 0;
    if (inFrames > (std::numeric_limits<int>::max)() / factor_) return -1;
    for (int c = 0; c < channels_; ++c) {
        if (in[c] == nullptr || out[c] == nullptr) return -1;
    }
    int done = 0;
    while (done < inFrames) {
        const int n = std::min(kChunkFrames, inFrames - done);
        for (int c = 0; c < channels_; ++c) {
            runCascade(c, in[c] + done, out[c] + size_t(done) * size_t(factor_), n);
        }
        done += n;
    }
    return inFrames * factor_;
}

}  // namespace pulsr
