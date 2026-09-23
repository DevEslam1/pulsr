// android/app/src/main/cpp/ArbitraryResponseEq.cpp
#include "ArbitraryResponseEq.h"
#include <sstream>
#include <algorithm>
#include <cmath>
#include <cstring>

#if defined(__ARM_NEON) || defined(__ARM_NEON__)
#include <arm_neon.h>
#define PULSR_HAS_NEON 1
#elif defined(__x86_64__) || defined(_M_X64) || defined(__i386__) || defined(_M_IX86)
#include <emmintrin.h>
#include <xmmintrin.h>
#define PULSR_HAS_SSE 1
#endif

namespace {
// A GraphicEq/EqualizerAPO string is untrusted input. Clamp the requested gain
// so a crafted value can never overflow pow() to +inf and poison the FIR taps.
constexpr double kMaxGainDb = 30.0;

double clampGainDb(double gainDb) {
    if (!std::isfinite(gainDb)) return 0.0;
    return std::clamp(gainDb, -kMaxGainDb, kMaxGainDb);
}

double interpolateGain(const std::vector<std::pair<double, double>>& nodes, double f) {
    if (nodes.empty()) return 0.0;
    if (f <= nodes.front().first) return nodes.front().second;
    if (f >= nodes.back().first) return nodes.back().second;

    // Binary search for interval
    auto it = std::upper_bound(nodes.begin(), nodes.end(), f,
        [](double val, const std::pair<double, double>& elem) {
            return val < elem.first;
        });

    if (it == nodes.begin()) return it->second;
    auto prev = it - 1;

    // Log-frequency interpolation. Guard f1 <= f0: duplicate node frequencies
    // would otherwise produce 0/0 = NaN taps.
    double f0 = std::max(prev->first, 1.0);
    double f1 = std::max(it->first, 1.0);
    if (f1 <= f0) return prev->second;
    double curF = std::max(f, 1.0);
    double t = (std::log(curF) - std::log(f0)) / (std::log(f1) - std::log(f0));
    return prev->second + t * (it->second - prev->second);
}
} // namespace

ArbitraryResponseEq::ArbitraryResponseEq() {
    firFilter_.assign(FIR_TAPS, 0.0f);
    firFilter_[0] = 1.0f; // Passthrough impulse
    spectrumScratch_.assign(FFT_SIZE, FftUtil::Complex(0.0f, 0.0f));
    nodes_.reserve(MAX_NODES);
    setSampleRate(48000.0);
    reset();
}

void ArbitraryResponseEq::setSampleRate(double sampleRate, bool resynthesize) {
    if (sampleRate < 8000.0) sampleRate = 8000.0;
    if (sampleRate > 768000.0) sampleRate = 768000.0;
    sampleRate_ = sampleRate;
    // Only re-derive the FIR when requested (off-audio-thread) and a response is loaded;
    // otherwise the constructor's passthrough impulse must be preserved.
    if (resynthesize && hasResponse_) {
        synthesizeFir();
    }
    reset();
}

void ArbitraryResponseEq::reset() {
    std::memset(historyL_, 0, sizeof(historyL_));
    std::memset(historyR_, 0, sizeof(historyR_));
    historyIdx_ = 0;
}

bool ArbitraryResponseEq::parseGraphicEq(
    const std::string& eqString, std::vector<std::pair<double, double>>& outNodes) {
    outNodes.clear();
    if (eqString.empty()) return false;

    // Strip "GraphicEq:" prefix if present
    std::string text = eqString;
    auto prefixPos = text.find("GraphicEq:");
    if (prefixPos != std::string::npos) {
        text = text.substr(prefixPos + 10);
    }

    // Replace ';' with space
    for (char& c : text) {
        if (c == ';') c = ' ';
    }

    std::stringstream ss(text);
    double freq, gain;
    while (ss >> freq >> gain) {
        if (freq > 0.0 && std::isfinite(freq)) {
            outNodes.push_back({freq, clampGainDb(gain)});
            if (static_cast<int>(outNodes.size()) >= ArbitraryResponseEq::MAX_NODES) break;
        }
    }

    std::sort(outNodes.begin(), outNodes.end(),
        [](const std::pair<double, double>& a, const std::pair<double, double>& b) {
            return a.first < b.first;
        });
    // Drop exact duplicate frequencies (log-frequency interpolation is
    // undefined for a zero-width interval).
    outNodes.erase(std::unique(outNodes.begin(), outNodes.end(),
        [](const std::pair<double, double>& a, const std::pair<double, double>& b) {
            return a.first == b.first;
        }), outNodes.end());

    return !outNodes.empty();
}

bool ArbitraryResponseEq::loadGraphicEqString(const std::string& eqString, bool linearPhase) {
    if (eqString.empty()) {
        nodes_.clear();
        loadedString_.clear();
        preparedNodesRef_.reset();
        hasResponse_ = false;
        firFilter_.assign(FIR_TAPS, 0.0f);
        firFilter_[0] = 1.0f;
        return false;
    }

    if (eqString == loadedString_ && linearPhase == linearPhase_) {
        return true;
    }

    std::vector<std::pair<double, double>> parsed;
    if (!parseGraphicEq(eqString, parsed)) {
        return false;
    }

    loadedString_ = eqString;
    linearPhase_ = linearPhase;
    nodes_.assign(parsed.begin(), parsed.end());
    hasResponse_ = !nodes_.empty();
    synthesizeFir();
    reset();
    return hasResponse_;
}

void ArbitraryResponseEq::applyPreparedNodes(
    const std::shared_ptr<const std::vector<std::pair<double, double>>>& nodes,
    bool linearPhase) {
    if (!nodes) return;
    if (nodes == preparedNodesRef_ && std::abs(firSynthesizedRate_ - sampleRate_) < 0.5) {
        linearPhase_ = linearPhase;
        return;
    }
    preparedNodesRef_ = nodes;
    linearPhase_ = linearPhase;
    // nodes_ has enough reserved capacity for MAX_NODES, so this is allocation
    // free for any parsed list.
    nodes_.assign(nodes->begin(), nodes->end());
    hasResponse_ = !nodes_.empty();
    synthesizeFir();
    reset();
}

void ArbitraryResponseEq::synthesizeFir() {
    if (nodes_.empty()) {
        hasResponse_ = false;
        firFilter_.assign(FIR_TAPS, 0.0f);
        firFilter_[0] = 1.0f;
        firSynthesizedRate_ = sampleRate_;
        return;
    }

    // Always synthesize a linear-phase (symmetric) impulse response centred at
    // (FIR_TAPS-1)/2. Previously the non-linear-phase path used delay = 0,
    // which yields an even IR centred at n = 0; keeping only samples [0, 511]
    // then discarded the negative-time half and produced a magnitude/phase that
    // did not match the target. Centring the impulse makes the first 512
    // samples a complete symmetric kernel (h[m] == h[511-m]) for both modes.
    const double delay = static_cast<double>(FIR_TAPS - 1) * 0.5;
    const int half = FFT_SIZE / 2;

    FftUtil::Complex* spectrum = spectrumScratch_.data();
    for (int k = 0; k <= half; ++k) {
        double f = static_cast<double>(k) * sampleRate_ / static_cast<double>(FFT_SIZE);
        double gainDb = clampGainDb(interpolateGain(nodes_, f));
        float mag = static_cast<float>(std::pow(10.0, gainDb / 20.0));
        if (!std::isfinite(mag)) mag = 1.0f;

        if (k == half) {
            // Nyquist bin must be real for a real-valued impulse response.
            spectrum[k] = FftUtil::Complex(mag, 0.0f);
        } else {
            // FftUtil's inverse transform computes h[n] = (1/N) Σ X[k] e^{-j2πkn/N},
            // so a POSITIVE phase term e^{+j2πkd/N} places the impulse at n = d.
            // (The previous negative phase placed it at n = N-d, so keeping the
            // first FIR_TAPS samples captured the wrapped tail, not the kernel.)
            double phase = 2.0 * M_PI * static_cast<double>(k) * delay / static_cast<double>(FFT_SIZE);
            spectrum[k] = FftUtil::Complex(
                mag * static_cast<float>(std::cos(phase)),
                mag * static_cast<float>(std::sin(phase))
            );
            if (k > 0) {
                spectrum[FFT_SIZE - k] = std::conj(spectrum[k]);
            }
        }
    }

    FftUtil::fft(spectrumScratch_, true); // IFFT

    // firFilter_ is already FIR_TAPS long after construction; resize is a no-op
    // in steady state and never allocates here.
    if (static_cast<int>(firFilter_.size()) != FIR_TAPS) {
        firFilter_.assign(FIR_TAPS, 0.0f);
    }
    for (int i = 0; i < FIR_TAPS; ++i) {
        // Hann window tapering to avoid Gibbs phenomenon ringing
        float w = 0.5f * (1.0f - std::cos(2.0f * static_cast<float>(M_PI) * i / (FIR_TAPS - 1)));
        float tap = spectrum[i].real() * w;
        firFilter_[i] = std::isfinite(tap) ? tap : 0.0f;
    }
    hasResponse_ = true;
    firSynthesizedRate_ = sampleRate_;
}

void ArbitraryResponseEq::applyParams(const ArbitraryEqParamSet& params) {
    enabled_ = params.enabled;
    // Preferred path: nodes were pre-parsed off the audio thread by the JNI
    // setter (see nativeLoadArbitraryEq), so applyParams performs no parsing
    // and no heap allocation.
    if (params.parsedNodes) {
        if (params.parsedNodes != preparedNodesRef_ || std::abs(firSynthesizedRate_ - sampleRate_) >= 0.5) {
            loadedString_ = params.graphicEqString;
            applyPreparedNodes(params.parsedNodes, params.linearPhase);
        }
        return;
    }
    if (!params.graphicEqString.empty() &&
        (params.graphicEqString != loadedString_ || params.linearPhase != linearPhase_)) {
        loadGraphicEqString(params.graphicEqString, params.linearPhase);
    }
}

namespace {
inline void convolve512Stereo(
    const float* h,
    const float* ptrL,
    const float* ptrR,
    float& outL,
    float& outR)
{
#if defined(PULSR_HAS_NEON)
    float32x4_t accL0 = vdupq_n_f32(0.0f);
    float32x4_t accR0 = vdupq_n_f32(0.0f);
    float32x4_t accL1 = vdupq_n_f32(0.0f);
    float32x4_t accR1 = vdupq_n_f32(0.0f);

    for (int t = 0; t < ArbitraryResponseEq::FIR_TAPS; t += 8) {
        float32x4_t vH0 = vld1q_f32(&h[t]);
        float32x4_t vPtrL0 = vld1q_f32(ptrL - t - 3);
        float32x4_t vPtrR0 = vld1q_f32(ptrR - t - 3);

        float32x4_t vRevL0 = vcombine_f32(vget_high_f32(vrev64q_f32(vPtrL0)), vget_low_f32(vrev64q_f32(vPtrL0)));
        float32x4_t vRevR0 = vcombine_f32(vget_high_f32(vrev64q_f32(vPtrR0)), vget_low_f32(vrev64q_f32(vPtrR0)));

        accL0 = vfmaq_f32(accL0, vH0, vRevL0);
        accR0 = vfmaq_f32(accR0, vH0, vRevR0);

        float32x4_t vH1 = vld1q_f32(&h[t + 4]);
        float32x4_t vPtrL1 = vld1q_f32(ptrL - t - 7);
        float32x4_t vPtrR1 = vld1q_f32(ptrR - t - 7);

        float32x4_t vRevL1 = vcombine_f32(vget_high_f32(vrev64q_f32(vPtrL1)), vget_low_f32(vrev64q_f32(vPtrL1)));
        float32x4_t vRevR1 = vcombine_f32(vget_high_f32(vrev64q_f32(vPtrR1)), vget_low_f32(vrev64q_f32(vPtrR1)));

        accL1 = vfmaq_f32(accL1, vH1, vRevL1);
        accR1 = vfmaq_f32(accR1, vH1, vRevR1);
    }

    outL = vaddvq_f32(vaddq_f32(accL0, accL1));
    outR = vaddvq_f32(vaddq_f32(accR0, accR1));

#elif defined(PULSR_HAS_SSE)
    __m128 accL0 = _mm_setzero_ps();
    __m128 accR0 = _mm_setzero_ps();
    __m128 accL1 = _mm_setzero_ps();
    __m128 accR1 = _mm_setzero_ps();

    for (int t = 0; t < ArbitraryResponseEq::FIR_TAPS; t += 8) {
        __m128 vH0 = _mm_loadu_ps(&h[t]);
        __m128 vPtrL0 = _mm_loadu_ps(ptrL - t - 3);
        __m128 vPtrR0 = _mm_loadu_ps(ptrR - t - 3);

        __m128 vRevL0 = _mm_shuffle_ps(vPtrL0, vPtrL0, _MM_SHUFFLE(0, 1, 2, 3));
        __m128 vRevR0 = _mm_shuffle_ps(vPtrR0, vPtrR0, _MM_SHUFFLE(0, 1, 2, 3));

        accL0 = _mm_add_ps(accL0, _mm_mul_ps(vH0, vRevL0));
        accR0 = _mm_add_ps(accR0, _mm_mul_ps(vH0, vRevR0));

        __m128 vH1 = _mm_loadu_ps(&h[t + 4]);
        __m128 vPtrL1 = _mm_loadu_ps(ptrL - t - 7);
        __m128 vPtrR1 = _mm_loadu_ps(ptrR - t - 7);

        __m128 vRevL1 = _mm_shuffle_ps(vPtrL1, vPtrL1, _MM_SHUFFLE(0, 1, 2, 3));
        __m128 vRevR1 = _mm_shuffle_ps(vPtrR1, vPtrR1, _MM_SHUFFLE(0, 1, 2, 3));

        accL1 = _mm_add_ps(accL1, _mm_mul_ps(vH1, vRevL1));
        accR1 = _mm_add_ps(accR1, _mm_mul_ps(vH1, vRevR1));
    }

    __m128 sumL = _mm_add_ps(accL0, accL1);
    __m128 sumR = _mm_add_ps(accR0, accR1);

    alignas(16) float arrL[4], arrR[4];
    _mm_store_ps(arrL, sumL);
    _mm_store_ps(arrR, sumR);

    outL = arrL[0] + arrL[1] + arrL[2] + arrL[3];
    outR = arrR[0] + arrR[1] + arrR[2] + arrR[3];

#else
    float sumL = 0.0f;
    float sumR = 0.0f;
    for (int t = 0; t < ArbitraryResponseEq::FIR_TAPS; ++t) {
        sumL += h[t] * ptrL[-t];
        sumR += h[t] * ptrR[-t];
    }
    outL = sumL;
    outR = sumR;
#endif
}
} // namespace

void ArbitraryResponseEq::process(float* L, float* R, int frames) {
    if (!enabled_ || !hasResponse_ || !L || !R || frames <= 0) return;

    const int taps = FIR_TAPS;
    const float* h = firFilter_.data();

    for (int i = 0; i < frames; ++i) {
        float inL = L[i];
        float inR = R[i];
        if (!std::isfinite(inL)) inL = 0.0f;
        if (!std::isfinite(inR)) inR = 0.0f;

        // Doubled circular buffer write: write at historyIdx_ and historyIdx_ + taps
        historyL_[historyIdx_] = inL;
        historyL_[historyIdx_ + taps] = inL;
        historyR_[historyIdx_] = inR;
        historyR_[historyIdx_ + taps] = inR;

        const float* ptrL = &historyL_[historyIdx_ + taps];
        const float* ptrR = &historyR_[historyIdx_ + taps];

        float outL = 0.0f;
        float outR = 0.0f;
        convolve512Stereo(h, ptrL, ptrR, outL, outR);

        historyIdx_ = historyIdx_ + 1;
        if (historyIdx_ >= taps) historyIdx_ = 0;

        L[i] = outL;
        R[i] = outR;
    }
}

void ArbitraryResponseEq::processInterleaved(float* buffer, int frames, int channels) {
    if (!enabled_ || !hasResponse_ || !buffer || frames <= 0 || channels < 2) return;

    const int taps = FIR_TAPS;
    const float* h = firFilter_.data();

    for (int i = 0; i < frames; ++i) {
        float inL = buffer[i * channels];
        float inR = buffer[i * channels + 1];
        if (!std::isfinite(inL)) inL = 0.0f;
        if (!std::isfinite(inR)) inR = 0.0f;

        // Doubled circular buffer write: write at historyIdx_ and historyIdx_ + taps
        historyL_[historyIdx_] = inL;
        historyL_[historyIdx_ + taps] = inL;
        historyR_[historyIdx_] = inR;
        historyR_[historyIdx_ + taps] = inR;

        const float* ptrL = &historyL_[historyIdx_ + taps];
        const float* ptrR = &historyR_[historyIdx_ + taps];

        float outL = 0.0f;
        float outR = 0.0f;
        convolve512Stereo(h, ptrL, ptrR, outL, outR);

        historyIdx_ = historyIdx_ + 1;
        if (historyIdx_ >= taps) historyIdx_ = 0;

        buffer[i * channels] = outL;
        buffer[i * channels + 1] = outR;
    }
}
