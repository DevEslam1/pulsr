// android/app/src/main/cpp/UsbAsrcClockSync.cpp
#include "UsbAsrcClockSync.h"

#include <algorithm>
#include <cmath>
#include <cstring>

namespace pulsr {
namespace {

constexpr double kPi = 3.14159265358979323846;

// Four-term Blackman-Harris. Endpoint value (~6e-5) is subtracted so the
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

}  // namespace

bool UsbAsrcClockSync::configure(int channels, int taps, int phases, bool allowDynamicBypass) {
    if (channels < 1 || channels > kMaxChannels) return false;
    if (taps < kMinTaps || taps > kMaxTaps || (taps & 1) != 0) return false;
    if (phases < kMinPhases || phases > kMaxPhases) return false;

    channels_ = channels;
    taps_ = taps;
    halfTaps_ = taps / 2;
    phases_ = phases;
    allowDynamicBypass_ = allowDynamicBypass;
    coef_.assign(static_cast<size_t>(phases_ + 1) * static_cast<size_t>(taps_), 0.0f);
    buf_.assign(static_cast<size_t>(taps_ + kPendingCapacity) * static_cast<size_t>(channels_),
                0.0f);
    buildKernel();
    configured_ = true;
    ratio_ = 1.0;
    step_ = 1.0;
    bypass_ = allowDynamicBypass_;
    clearStream();
    return true;
}

void UsbAsrcClockSync::setAllowDynamicBypass(bool allow) {
    if (allowDynamicBypass_ == allow) return;
    allowDynamicBypass_ = allow;
    const bool newBypass = allowDynamicBypass_ && (ratio_ == 1.0);
    if (bypass_ != newBypass) {
        bypass_ = newBypass;
        clearStream();
    }
}

void UsbAsrcClockSync::buildKernel() {
    const int h = halfTaps_;
    // One extra row for frac == 1.0. The kernel is continuous in the fractional
    // delay, but it is *not* periodic: at frac -> 1 the delta sits on offset +1,
    // while branch 0 has it on offset 0. Interpolating the last branch against
    // branch 0 would therefore introduce a full-sample jump for the last
    // 1/phases of the phase interval (measured: ~-47 dB THD+N). Row `phases_`
    // is the genuine frac == 1.0 kernel, so every interpolation is between two
    // neighbouring kernels of the same offset grid.
    for (int ph = 0; ph <= phases_; ++ph) {
        const double frac = static_cast<double>(ph) / static_cast<double>(phases_);
        float* row = &coef_[static_cast<size_t>(ph) * static_cast<size_t>(taps_)];
        double sum = 0.0;
        for (int j = 0; j < taps_; ++j) {
            // Offsets -(h-1) .. +h so offset 0 is present: at frac == 0 the
            // kernel collapses to an exact delta and the filter is transparent.
            const double d = static_cast<double>(j - (h - 1));
            const double x = d - frac;
            const double c = sinc(x) * blackmanHarris(x / static_cast<double>(h));
            row[j] = static_cast<float>(c);
            sum += c;
        }
        // Exact unity DC per branch. Without this the passband gain would
        // ripple with the fractional phase and produce sidebands.
        if (std::fabs(sum) > 1e-12) {
            const float inv = static_cast<float>(1.0 / sum);
            for (int j = 0; j < taps_; ++j) row[j] *= inv;
        }
    }
}

void UsbAsrcClockSync::setRatio(double outPerIn) {
    if (!std::isfinite(outPerIn) || outPerIn <= 0.0) return;
    double r = outPerIn;
    if (r > kMaxRatio) r = kMaxRatio;
    if (r < kMinRatio) r = kMinRatio;

    const bool wasBypass = bypass_;
    ratio_ = r;
    step_ = 1.0 / r;
    bypass_ = allowDynamicBypass_ && (r == 1.0);
    if (wasBypass != bypass_) {
        // Control path: entering or leaving the bit-perfect bypass starts from a
        // clean history so no fractional phase can leak into a locked stream.
        clearStream();
    }
}

void UsbAsrcClockSync::reset() { clearStream(); }

void UsbAsrcClockSync::clearStream() {
    if (!buf_.empty()) std::fill(buf_.begin(), buf_.end(), 0.0f);
    pending_ = 0;
    pos_ = 0.0;
    inputFramesConsumed_ = 0;
}

int UsbAsrcClockSync::latencyFrames() const {
    if (!configured_) return 0;
    return static_cast<int>(std::llround(static_cast<double>(halfTaps_) * ratio_));
}

void UsbAsrcClockSync::dropFrames(int frames) {
    const size_t ch = static_cast<size_t>(channels_);
    const int live = pending_ - frames;
    if (live < 0) return;
    // Live region is [frames, taps_ + pending_): that is exactly taps_ frames of
    // history followed by the not-yet-consumed input.
    std::memmove(buf_.data(), buf_.data() + static_cast<size_t>(frames) * ch,
                 static_cast<size_t>(taps_ + live) * ch * sizeof(float));
    pending_ = live;
    pos_ -= static_cast<double>(frames);
    if (pos_ < 0.0) pos_ = 0.0;  // defensive: cannot happen with a positive step
}

int UsbAsrcClockSync::generate(float* out, int maxOut) {
    const int ch = channels_;
    const int H = taps_;
    const int h = halfTaps_;
    int produced = 0;

    while (produced < maxOut) {
        const int i = static_cast<int>(pos_);
        // Need the full right-hand half of the kernel inside buffered input.
        if (i + h > pending_ - 1) break;

        const double frac = pos_ - static_cast<double>(i);
        const double pf = frac * static_cast<double>(phases_);
        int branch = static_cast<int>(pf);
        if (branch >= phases_) branch = phases_ - 1;
        const double t = pf - static_cast<double>(branch);

        const float* c0 = &coef_[static_cast<size_t>(branch) * static_cast<size_t>(H)];
        const float* c1 = &coef_[static_cast<size_t>(branch + 1) * static_cast<size_t>(H)];
        float cbuf[kMaxTaps];
        const float tf = static_cast<float>(t);
        for (int j = 0; j < H; ++j) cbuf[j] = c0[j] + tf * (c1[j] - c0[j]);

        const float* base = &buf_[static_cast<size_t>(H + i - (h - 1)) * static_cast<size_t>(ch)];
        for (int c = 0; c < ch; ++c) {
            const float* p = base + c;
            float acc = 0.0f;
            for (int j = 0; j < H; ++j) {
                acc += cbuf[j] * p[static_cast<size_t>(j) * static_cast<size_t>(ch)];
            }
            // Flush sub-floor values so a decaying tail cannot leave denormals
            // in the history and stall a CPU without FTZ. NaN/Inf pass through.
            if (std::fabs(acc) < kDenormalFloor) acc = 0.0f;
            out[static_cast<size_t>(produced) * static_cast<size_t>(ch) + c] = acc;
        }

        ++produced;
        pos_ += step_;
    }

    const int consumed = static_cast<int>(pos_);
    if (consumed > 0) dropFrames(consumed);
    return produced;
}

int UsbAsrcClockSync::process(const float* in, int inFrames, float* out, int maxOutFrames) {
    inputFramesConsumed_ = 0;
    if (!configured_ || inFrames <= 0 || maxOutFrames <= 0) return 0;
    if (in == nullptr || out == nullptr) return 0;

    const size_t ch = static_cast<size_t>(channels_);

    if (bypass_) {
        // Bit-identical, history untouched.
        const int n = std::min(inFrames, maxOutFrames);
        std::memcpy(out, in, static_cast<size_t>(n) * ch * sizeof(float));
        inputFramesConsumed_ = n;
        return n;
    }

    int produced = 0;
    int consumed = 0;
    while (consumed < inFrames && produced < maxOutFrames) {
        const int room = kPendingCapacity - pending_;
        if (room <= 0) break;  // cannot happen: generate() always drains pending
        const int chunk = std::min(inFrames - consumed, room);
        float* dst = &buf_[(static_cast<size_t>(taps_) + static_cast<size_t>(pending_)) * ch];
        const float* src = &in[static_cast<size_t>(consumed) * ch];
        const size_t count = static_cast<size_t>(chunk) * ch;
        for (size_t k = 0; k < count; ++k) {
            const float v = src[k];
            dst[k] = (std::fabs(v) < kDenormalFloor) ? 0.0f : v;
        }
        pending_ += chunk;
        consumed += chunk;
        produced += generate(&out[static_cast<size_t>(produced) * ch], maxOutFrames - produced);
    }

    inputFramesConsumed_ = consumed;
    return produced;
}

}  // namespace pulsr
