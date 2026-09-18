// android/app/src/main/cpp/ArbitraryResponseEq.cpp
#include "ArbitraryResponseEq.h"
#include <sstream>
#include <algorithm>
#include <cmath>
#include <cstring>

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

void ArbitraryResponseEq::setSampleRate(double sampleRate) {
    if (sampleRate < 8000.0) sampleRate = 8000.0;
    if (sampleRate > 768000.0) sampleRate = 768000.0;
    sampleRate_ = sampleRate;
    // Only re-derive the FIR when a response is loaded; otherwise the
    // constructor's passthrough impulse must be preserved.
    if (hasResponse_) {
        synthesizeFir();
    }
    reset();
}

void ArbitraryResponseEq::reset() {
    std::memset(historyL_, 0, sizeof(historyL_));
    std::memset(historyR_, 0, sizeof(historyR_));
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
    if (nodes == preparedNodesRef_) {
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
}

void ArbitraryResponseEq::applyParams(const ArbitraryEqParamSet& params) {
    enabled_ = params.enabled;
    // Preferred path: nodes were pre-parsed off the audio thread by the JNI
    // setter (see nativeLoadArbitraryEq), so applyParams performs no parsing
    // and no heap allocation.
    if (params.parsedNodes) {
        if (params.parsedNodes != preparedNodesRef_) {
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

void ArbitraryResponseEq::process(float* L, float* R, int frames) {
    if (!enabled_ || !hasResponse_ || !L || !R || frames <= 0) return;

    const int taps = FIR_TAPS;
    const float* h = firFilter_.data();

    for (int i = 0; i < frames; ++i) {
        float inL = L[i];
        float inR = R[i];
        if (!std::isfinite(inL)) inL = 0.0f;
        if (!std::isfinite(inR)) inR = 0.0f;

        // Shift history
        for (int t = taps - 1; t > 0; --t) {
            historyL_[t] = historyL_[t - 1];
            historyR_[t] = historyR_[t - 1];
        }
        historyL_[0] = inL;
        historyR_[0] = inR;

        float outL = 0.0f;
        float outR = 0.0f;
        for (int t = 0; t < taps; ++t) {
            outL += h[t] * historyL_[t];
            outR += h[t] * historyR_[t];
        }

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

        for (int t = taps - 1; t > 0; --t) {
            historyL_[t] = historyL_[t - 1];
            historyR_[t] = historyR_[t - 1];
        }
        historyL_[0] = inL;
        historyR_[0] = inR;

        float outL = 0.0f;
        float outR = 0.0f;
        for (int t = 0; t < taps; ++t) {
            outL += h[t] * historyL_[t];
            outR += h[t] * historyR_[t];
        }

        buffer[i * channels] = outL;
        buffer[i * channels + 1] = outR;
    }
}
