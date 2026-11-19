// android/app/src/main/cpp/HighQualityResampler.cpp
#include "HighQualityResampler.h"

#include <algorithm>
#include <cmath>
#include <cstring>

namespace pulsr {
namespace {

constexpr double kPi = 3.14159265358979323846;

// Four-term Blackman-Harris. The endpoint value (~6e-5) is subtracted so the
// truncated kernel reaches exactly zero at |u| = 1 instead of leaving a step at
// the window edge; the per-branch DC normalisation below removes the resulting
// gain offset.
constexpr double kBwA0 = 0.35875;
constexpr double kBwA1 = 0.48829;
constexpr double kBwA2 = 0.14128;
constexpr double kBwA3 = 0.01168;
constexpr double kBwEdge = kBwA0 - kBwA1 + kBwA2 - kBwA3;

double blackmanHarris(double u) {
    if (u <= -1.0 || u >= 1.0) return 0.0;
    const double w = kBwA0 + kBwA1 * std::cos(kPi * u) + kBwA2 * std::cos(2.0 * kPi * u) +
                     kBwA3 * std::cos(3.0 * kPi * u);
    return std::max(0.0, w - kBwEdge);
}

double sinc(double x) {
    if (std::fabs(x) < 1e-9) return 1.0;
    const double p = kPi * x;
    return std::sin(p) / p;
}

// Anti-alias cutoff in cycles per input sample for a given ratio. For any
// upsampling ratio the input Nyquist is the lower one, so the cutoff saturates
// at 0.5 * guard; for downsampling it scales down with the ratio so the output
// Nyquist is honoured.
double cutoffFor(double ratio) {
    return 0.5 * HighQualityResampler::kCutoffGuard * std::min(1.0, ratio);
}

}  // namespace

bool HighQualityResampler::configure(int channels, int taps, int phases, double inRate,
                                     double outRate) {
    if (channels < 1 || channels > kMaxChannels) return false;
    if (taps < kMinTaps || taps > kMaxTaps || (taps & 1) != 0) return false;
    if (phases < kMinPhases || phases > kMaxPhases) return false;
    if (!std::isfinite(inRate) || !std::isfinite(outRate)) return false;
    if (inRate <= 0.0 || outRate <= 0.0) return false;
    const double nominal = outRate / inRate;
    if (!std::isfinite(nominal) || nominal < kMinRatio || nominal > kMaxRatio) return false;

    channels_ = channels;
    taps_ = taps;
    halfTaps_ = taps / 2;
    phases_ = phases;
    stride_ = taps_ + kPendingCapacity;
    coef_.assign(static_cast<size_t>(phases_ + 1) * static_cast<size_t>(taps_), 0.0f);
    buf_.assign(static_cast<size_t>(stride_) * static_cast<size_t>(channels_), 0.0f);

    inRate_ = inRate;
    outRate_ = outRate;
    ratio_ = nominal;
    step_ = 1.0 / nominal;
    bypass_ = (std::fabs(nominal - 1.0) < kBypassEpsilon);
    kernelCutoff_ = cutoffFor(nominal);
    buildKernel();

    configured_ = true;
    clearStream();
    return true;
}

void HighQualityResampler::buildKernel() {
    if (taps_ <= 0 || phases_ <= 0 || coef_.empty()) return;
    const int h = halfTaps_;
    const double cut = kernelCutoff_;

    // One row per phase plus the frac == 1.0 row. The kernel is continuous in
    // the fractional delay but not periodic: at frac -> 1 the delta sits on
    // offset +1 while branch 0 has it on offset 0, so interpolating the last
    // branch against branch 0 would jump a whole sample. Row phases_ is the
    // genuine frac == 1.0 kernel on the same offset grid.
    for (int ph = 0; ph <= phases_; ++ph) {
        const double frac = static_cast<double>(ph) / static_cast<double>(phases_);
        float* row = &coef_[static_cast<size_t>(ph) * static_cast<size_t>(taps_)];
        double sum = 0.0;
        for (int j = 0; j < taps_; ++j) {
            // Offsets -(h - 1) .. +h, so offset 0 is present and the kernel is
            // centred on the read position.
            const double d = static_cast<double>(j - (h - 1));
            const double x = d - frac;
            const double c = 2.0 * cut * sinc(2.0 * cut * x) * blackmanHarris(x / static_cast<double>(h));
            row[j] = static_cast<float>(c);
            sum += c;
        }
        // Exact unity DC per branch: without this the passband gain would
        // ripple with the fractional phase and show up as sidebands.
        if (std::fabs(sum) > 1e-12) {
            const float inv = static_cast<float>(1.0 / sum);
            for (int j = 0; j < taps_; ++j) row[j] *= inv;
        }
    }
}

void HighQualityResampler::setRatio(double outPerIn) {
    if (!configured_) return;
    if (!std::isfinite(outPerIn) || outPerIn <= 0.0) return;
    double r = outPerIn;
    if (r < kMinRatio) r = kMinRatio;
    if (r > kMaxRatio) r = kMaxRatio;

    const bool wasBypass = bypass_;
    ratio_ = r;
    step_ = 1.0 / r;
    bypass_ = (std::fabs(r - 1.0) < kBypassEpsilon);

    // The anti-alias cutoff follows the ratio. Rebuild in place (no allocation)
    // only when the required cutoff actually moved; ratios above unity all map
    // to the same cutoff, so a bypass detour through 1.0 costs nothing.
    const double cut = cutoffFor(ratio_);
    if (std::fabs(cut - kernelCutoff_) > 0.005 * kernelCutoff_) {
        kernelCutoff_ = cut;
        buildKernel();
    }

    if (wasBypass != bypass_) {
        // Control path: entering or leaving the bit-perfect bypass starts from
        // a clean history so no fractional phase can leak into a locked stream.
        clearStream();
    }
}

void HighQualityResampler::reset() { clearStream(); }

void HighQualityResampler::release() {
    std::vector<float>().swap(coef_);
    std::vector<float>().swap(buf_);
    channels_ = 0;
    taps_ = 0;
    halfTaps_ = 0;
    phases_ = 0;
    stride_ = 0;
    pending_ = 0;
    readPos_ = 0;
    frac_ = 0.0;
    inRate_ = 0.0;
    outRate_ = 0.0;
    ratio_ = 1.0;
    step_ = 1.0;
    kernelCutoff_ = 0.5;
    bypass_ = true;
    configured_ = false;
}

void HighQualityResampler::clearStream() {
    if (!buf_.empty()) std::fill(buf_.begin(), buf_.end(), 0.0f);
    pending_ = 0;
    readPos_ = 0;
    frac_ = 0.0;
}

int HighQualityResampler::latencyFrames() const {
    if (!configured_) return 0;
    return static_cast<int>(std::llround(static_cast<double>(halfTaps_) * ratio_));
}

void HighQualityResampler::dropFrames(int frames) {
    if (frames <= 0 || pending_ <= 0) return;
    const int live = pending_ - frames;
    if (live < 0) return;  // defensive: never happens with a positive step
    // The live region [frames, taps_ + pending_) is exactly taps_ frames of
    // history followed by the not-yet-consumed input; re-seat it at offset 0.
    for (int c = 0; c < channels_; ++c) {
        float* base = buf_.data() + static_cast<size_t>(c) * static_cast<size_t>(stride_);
        std::memmove(base, base + frames,
                     static_cast<size_t>(taps_ + live) * sizeof(float));
    }
    pending_ = live;
    readPos_ -= frames;
    if (readPos_ < 0) readPos_ = 0;
}

int HighQualityResampler::generate(float* const* out, int outOffset, int maxOut) {
    const int ch = channels_;
    const int H = taps_;
    const int h = halfTaps_;
    int produced = 0;

    while (produced < maxOut) {
        const int i = readPos_;
        // The full right-hand half of the kernel must be buffered.
        if (i + h > pending_ - 1) break;

        const double frac = frac_;
        const double pf = frac * static_cast<double>(phases_);
        int branch = static_cast<int>(pf);
        if (branch >= phases_) branch = phases_ - 1;
        const float t = static_cast<float>(pf - static_cast<double>(branch));

        const float* c0 = &coef_[static_cast<size_t>(branch) * static_cast<size_t>(H)];
        const float* c1 = &coef_[static_cast<size_t>(branch + 1) * static_cast<size_t>(H)];
        float cbuf[kMaxTaps];
        for (int j = 0; j < H; ++j) cbuf[j] = c0[j] + t * (c1[j] - c0[j]);

        const int base = H + i - (h - 1);
        for (int c = 0; c < ch; ++c) {
            const float* p = buf_.data() + static_cast<size_t>(c) * static_cast<size_t>(stride_) +
                             static_cast<size_t>(base);
            float acc = 0.0f;
            for (int j = 0; j < H; ++j) acc += cbuf[j] * p[j];
            // Flush sub-floor values so a decaying tail cannot leave denormals
            // in the history and stall a CPU without FTZ. NaN/Inf pass through.
            if (std::fabs(acc) < kDenormalFloor) acc = 0.0f;
            out[c][outOffset + produced] = acc;
        }

        ++produced;
        frac_ += step_;
        // Exact carry: subtracting the floor of a value already in [0, 2) is
        // representable without rounding, so the integer offset absorbs whole
        // steps and frac_ stays in [0, 1).
        if (frac_ >= 1.0) {
            const double whole = std::floor(frac_);
            readPos_ += static_cast<int>(whole);
            frac_ -= whole;
        }
    }

    if (readPos_ > 0) dropFrames(readPos_);
    return produced;
}

bool HighQualityResampler::pointersValid(const float* const* in, int inFrames,
                                         float* const* out) const {
    if (out == nullptr) return false;
    for (int c = 0; c < channels_; ++c) {
        if (out[c] == nullptr) return false;
        if (inFrames > 0 && in[c] == nullptr) return false;
    }
    return true;
}

int HighQualityResampler::process(const float* const* in, int inFrames, float* const* out,
                                  int maxOutFrames, int& consumed) {
    consumed = 0;
    if (!configured_ || maxOutFrames <= 0 || inFrames < 0) return 0;
    if (inFrames > 0 && in == nullptr) return 0;
    if (!pointersValid(in, inFrames, out)) return 0;

    const int ch = channels_;

    if (bypass_) {
        // Bit-identical, history untouched. A drain call (inFrames == 0, in may
        // be null) has nothing to pass through.
        const int n = std::min(inFrames, maxOutFrames);
        if (n > 0) {
            for (int c = 0; c < ch; ++c) {
                std::memcpy(out[c], in[c], static_cast<size_t>(n) * sizeof(float));
            }
        }
        consumed = n;
        return n;
    }

    int produced = 0;
    while (produced < maxOutFrames) {
        produced += generate(out, produced, maxOutFrames - produced);
        if (produced >= maxOutFrames) break;
        if (consumed >= inFrames) break;

        // Only pull in what the remaining output budget needs: output index k
        // reads input position (readPos_ + frac_) + k * step and needs
        // halfTaps_ frames of lookahead beyond it. Consuming the whole caller
        // block here would report more input taken than the caller's small
        // output buffer paid for, which breaks partial-consumption accounting.
        const double lastPos =
            static_cast<double>(readPos_) + frac_ +
            static_cast<double>(maxOutFrames - produced - 1) * step_;
        const double needD = std::ceil(lastPos + static_cast<double>(halfTaps_) + 1.0) -
                             static_cast<double>(pending_);
        const int room = kPendingCapacity - pending_;
        if (room <= 0) break;  // defensive: generate() always drains pending
        int chunk;
        if (needD >= static_cast<double>(room)) {
            chunk = room;
        } else {
            chunk = (needD < 1.0) ? 1 : static_cast<int>(needD);
        }
        chunk = std::min(chunk, inFrames - consumed);
        if (chunk <= 0) break;

        for (int c = 0; c < ch; ++c) {
            float* dst = buf_.data() + static_cast<size_t>(c) * static_cast<size_t>(stride_) +
                         static_cast<size_t>(taps_) + static_cast<size_t>(pending_);
            const float* src = in[c] + consumed;
            for (int k = 0; k < chunk; ++k) {
                const float v = src[k];
                dst[k] = (std::fabs(v) < kDenormalFloor) ? 0.0f : v;
            }
        }
        pending_ += chunk;
        consumed += chunk;
    }

    return produced;
}

}  // namespace pulsr
