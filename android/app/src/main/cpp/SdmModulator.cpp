// android/app/src/main/cpp/SdmModulator.cpp
#include "SdmModulator.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <limits>

namespace pulsr {
namespace {

// CIFB coefficient sets, one per order. Each entry is the feedback vector
// a[1..N]; the inter-stage gain rho and the input gain b1 are listed alongside.
// Synthesised as described in SdmModulator.h:
//   * NTF zeros at DC, NTF poles = Butterworth prototype mapped by z = 1 + c*s
//   * c = 0.50 (N=1), 0.30 (N=2), 0.20 (N=3..5)  ->  H_inf = 1.33 / 1.27 /
//     1.27 / 1.41 / 1.59
//   * rho = 0.50 (inter-stage state scaling; keeps every integrator within ~1.4
//     of full scale at 0 dBFS, measured)
//   * b1 = a1, which is exactly what makes the signal transfer function unity at
//     DC: STF(0) = b1 * prod(c) / P(1) = b1 / a1. Anything else scales the bit
//     density away from (1 + x) / 2, so this equality is load bearing.
struct CoeffSet {
    float a[5];
    float rho;
    float b1;
};

constexpr CoeffSet kCoeffs[5] = {
    // order 1
    {{0.5f}, 1.0f, 0.5f},
    // order 2
    {{0.18f, 0.424264068712f}, 0.5f, 0.18f},
    // order 3
    {{0.032f, 0.16f, 0.4f}, 0.5f, 0.032f},
    // order 4
    {{0.0128f, 0.08362247f, 0.273075f, 0.522625185951f}, 0.5f, 0.0128f},
    // order 5
    {{0.00512f, 0.0414156f, 0.16761f, 0.41891f, 0.6472135955f}, 0.5f, 0.00512f},
};

// Returns true when `rate` is a power-of-two multiple (<= 8x) of 44100 or 48000.
bool IsSupportedPcmRate(double rate) {
    if (!(rate >= 44100.0 && rate <= 384000.0)) return false;
    const double families[2] = {44100.0, 48000.0};
    for (double f : families) {
        const double ratio = rate / f;
        const double rounded = std::round(ratio);
        if (std::abs(ratio - rounded) > 1e-9) continue;
        if (rounded != 1.0 && rounded != 2.0 && rounded != 4.0 && rounded != 8.0) continue;
        return true;
    }
    return false;
}

}  // namespace

bool SdmModulator::configure(double pcmRate, int dsdMultiple, int order) {
    release();
    if (!IsSupportedPcmRate(pcmRate)) return false;
    if (dsdMultiple != 64 && dsdMultiple != 128 && dsdMultiple != 256) return false;
    if (order < kMinOrder || order > kMaxOrder) return false;
    // Cap the bit rate at DSD512 (24.576 MHz) so a 384 kHz PCM source cannot ask
    // for a stream no transport in this project supports.
    const double rate = pcmRate * double(dsdMultiple);
    if (rate > 24576000.0) return false;
    if (!upsampler_.configure(kChannels, kPreFactor, OversampleKernel::Sharp)) return false;

    const CoeffSet& set = kCoeffs[order - 1];
    for (int i = 0; i < order; ++i) feedback_[i + 1] = set.a[i];
    for (int i = order + 1; i <= kMaxOrder; ++i) feedback_[i] = 0.0f;
    rho_ = set.rho;
    b1_ = set.b1;
    order_ = order;
    dsdMultiple_ = dsdMultiple;
    dsdRate_ = rate;
    pcmRate_ = pcmRate;
    zoh_ = dsdMultiple / kPreFactor;
    if (zoh_ < 1) zoh_ = 1;

    const size_t upFrames = size_t(kPcmChunk) * size_t(kPreFactor);
    for (int ch = 0; ch < kChannels; ++ch) {
        upBuf_[ch].assign(upFrames, 0.0f);
        upPtr_[ch] = upBuf_[ch].data();
    }
    configured_ = true;
    reset();
    return true;
}

void SdmModulator::reset() {
    for (int ch = 0; ch < kChannels; ++ch) {
        for (int i = 0; i <= kMaxOrder; ++i) state_[ch][i] = 0.0f;
        lastBit_[ch] = 0.0f;
        accumulator_[ch] = 0;
    }
    bitCount_ = 0;
    peakState_ = 0.0f;
    upsampler_.reset();
}

void SdmModulator::release() {
    reset();
    upsampler_.release();
    for (int ch = 0; ch < kChannels; ++ch) {
        std::vector<float>().swap(upBuf_[ch]);
        upPtr_[ch] = nullptr;
    }
    for (int i = 0; i <= kMaxOrder; ++i) feedback_[i] = 0.0f;
    b1_ = 0.0f;
    rho_ = 1.0f;
    dsdRate_ = 0.0;
    pcmRate_ = 0.0;
    order_ = 0;
    dsdMultiple_ = 0;
    zoh_ = 1;
    configured_ = false;
}

double SdmModulator::latencyPcmFrames() const {
    if (!configured_ || pcmRate_ <= 0.0) return 0.0;
    // The upsampler reports output-rate frames; convert back to PCM frames.
    const double upRateFrames = double(upsampler_.latencyFrames());
    return upRateFrames / double(kPreFactor);
}

float SdmModulator::modulate(int channel, float x) {
    float* s = state_[channel];
    const float vPrev = lastBit_[channel];
    const float u = kInputHeadroom * b1_ * x;

    for (int i = order_; i >= 1; --i) {
        const float prev = (i == 1) ? u : rho_ * s[i - 1];
        float v = s[i] + prev - feedback_[i] * vPrev;
        // Anti-windup: clamp, and catch a non-finite state in the same compare so
        // the multiply-add chain can never stay NaN.
        if (!(v > -kStateClamp)) v = -kStateClamp;
        if (v > kStateClamp) v = kStateClamp;
        s[i] = v;
        const float mag = std::fabs(v);
        if (mag > peakState_) peakState_ = mag;
    }

    const float v = (s[order_] >= 0.0f) ? 1.0f : -1.0f;
    lastBit_[channel] = v;
    return v;
}

int SdmModulator::process(const float* const* in, int inFrames, uint8_t* outL, uint8_t* outR,
                          int outCapacity) {
    if (!configured_ || in == nullptr || inFrames < 0) return -1;
    if (outL == nullptr || outR == nullptr || outCapacity < 0) return -1;
    if (inFrames == 0) return 0;
    if (in[0] == nullptr || in[1] == nullptr) return -1;
    if (inFrames > (std::numeric_limits<int>::max)() / dsdMultiple_) return -1;

    // Capacity is checked before any state is touched, so a short buffer is a
    // clean rejection rather than a partial write.
    const int bits = bitCount_ + inFrames * dsdMultiple_;
    const int bytes = bits >> 3;
    if (bytes > outCapacity) return -1;

    uint8_t* dstL = outL;
    uint8_t* dstR = outR;
    int written = 0;

    for (int done = 0; done < inFrames; done += kPcmChunk) {
        const int dn = std::min(kPcmChunk, inFrames - done);
        const float* src[kChannels] = {in[0] + done, in[1] + done};
        if (upsampler_.process(src, upPtr_, dn) != dn * kPreFactor) return -1;

        const int upFrames = dn * kPreFactor;
        const float* upL = upBuf_[0].data();
        const float* upR = upBuf_[1].data();
        for (int u = 0; u < upFrames; ++u) {
            const float sampleL = upL[u];
            const float sampleR = upR[u];
            for (int rep = 0; rep < zoh_; ++rep) {
                const int bitL = (modulate(0, sampleL) > 0.0f) ? 1 : 0;
                const int bitR = (modulate(1, sampleR) > 0.0f) ? 1 : 0;
                accumulator_[0] = uint8_t(accumulator_[0] | (bitL << bitCount_));
                accumulator_[1] = uint8_t(accumulator_[1] | (bitR << bitCount_));
                if (++bitCount_ == 8) {
                    dstL[written] = accumulator_[0];
                    dstR[written] = accumulator_[1];
                    ++written;
                    accumulator_[0] = 0;
                    accumulator_[1] = 0;
                    bitCount_ = 0;
                }
            }
        }
    }
    return written;
}

}  // namespace pulsr
