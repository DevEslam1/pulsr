// android/app/src/main/cpp/ArbitraryResponseEq.cpp
#include "ArbitraryResponseEq.h"
#include <sstream>
#include <algorithm>
#include <cmath>
#include <cstring>

namespace {
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

    // Log-frequency interpolation
    double f0 = std::max(prev->first, 1.0);
    double f1 = std::max(it->first, 1.0);
    double curF = std::max(f, 1.0);
    double t = (std::log(curF) - std::log(f0)) / (std::log(f1) - std::log(f0));
    return prev->second + t * (it->second - prev->second);
}
} // namespace

ArbitraryResponseEq::ArbitraryResponseEq() {
    firFilter_.assign(FIR_TAPS, 0.0f);
    firFilter_[0] = 1.0f; // Passthrough impulse
    setSampleRate(48000.0);
    reset();
}

void ArbitraryResponseEq::setSampleRate(double sampleRate) {
    if (sampleRate < 8000.0) sampleRate = 8000.0;
    if (sampleRate > 768000.0) sampleRate = 768000.0;
    sampleRate_ = sampleRate;
    synthesizeFir();
    reset();
}

void ArbitraryResponseEq::reset() {
    std::memset(historyL_, 0, sizeof(historyL_));
    std::memset(historyR_, 0, sizeof(historyR_));
}

bool ArbitraryResponseEq::loadGraphicEqString(const std::string& eqString, bool linearPhase) {
    if (eqString.empty()) {
        nodes_.clear();
        loadedString_.clear();
        firFilter_.assign(FIR_TAPS, 0.0f);
        firFilter_[0] = 1.0f;
        return false;
    }

    if (eqString == loadedString_ && linearPhase == linearPhase_) {
        return true;
    }

    loadedString_ = eqString;
    linearPhase_ = linearPhase;
    nodes_.clear();

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
        if (freq > 0.0) {
            nodes_.push_back({freq, gain});
        }
    }

    std::sort(nodes_.begin(), nodes_.end(),
        [](const std::pair<double, double>& a, const std::pair<double, double>& b) {
            return a.first < b.first;
        });

    synthesizeFir();
    reset();
    return !nodes_.empty();
}

void ArbitraryResponseEq::synthesizeFir() {
    if (nodes_.empty()) {
        firFilter_.assign(FIR_TAPS, 0.0f);
        firFilter_[0] = 1.0f;
        return;
    }

    std::vector<FftUtil::Complex> spectrum(FFT_SIZE, FftUtil::Complex(0.0f, 0.0f));
    const int half = FFT_SIZE / 2;
    const double delay = linearPhase_ ? (static_cast<double>(FIR_TAPS) * 0.5) : 0.0;

    for (int k = 0; k <= half; ++k) {
        double f = static_cast<double>(k) * sampleRate_ / static_cast<double>(FFT_SIZE);
        double gainDb = interpolateGain(nodes_, f);
        float mag = static_cast<float>(std::pow(10.0, gainDb / 20.0));

        double phase = -2.0 * M_PI * static_cast<double>(k) * delay / static_cast<double>(FFT_SIZE);
        spectrum[k] = FftUtil::Complex(
            mag * static_cast<float>(std::cos(phase)),
            mag * static_cast<float>(std::sin(phase))
        );
        if (k > 0 && k < half) {
            spectrum[FFT_SIZE - k] = std::conj(spectrum[k]);
        }
    }

    FftUtil::fft(spectrum, true); // IFFT

    firFilter_.resize(FIR_TAPS);
    for (int i = 0; i < FIR_TAPS; ++i) {
        // Hann window tapering to avoid Gibbs phenomenon ringing
        float w = 0.5f * (1.0f - std::cos(2.0f * static_cast<float>(M_PI) * i / (FIR_TAPS - 1)));
        firFilter_[i] = spectrum[i].real() * w;
    }
}

void ArbitraryResponseEq::applyParams(const ArbitraryEqParamSet& params) {
    enabled_ = params.enabled;
    if (!params.graphicEqString.empty() &&
        (params.graphicEqString != loadedString_ || params.linearPhase != linearPhase_)) {
        loadGraphicEqString(params.graphicEqString, params.linearPhase);
    }
}

void ArbitraryResponseEq::process(float* L, float* R, int frames) {
    if (!enabled_ || nodes_.empty() || !L || !R || frames <= 0) return;

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
    if (!enabled_ || nodes_.empty() || !buffer || frames <= 0 || channels < 2) return;

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
