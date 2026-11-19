// android/app/src/main/cpp/SdmModulator.h
//
// Single-bit sigma-delta modulator: PCM -> DSD (1-bit), for DSD64/128/256.
//
// Signal chain inside one process() call:
//   PCM (pcmRate)
//     -> Oversampler 8x, Sharp halfband kernel      (352.8 / 384 kHz)
//     -> zero-order hold by dsdMultiple/8           (2.8224 ... 12.288 MHz)
//     -> 1-bit CIFB loop                            (DSD rate)
//     -> LSB-first byte packing
// The 8x pre-interpolation keeps the hold's sinc droop at -0.001 dB at 20 kHz
// (a raw 64x hold would droop -0.95 dB) while the remaining images sit above
// 332 kHz, where the DAC's analogue filter removes them. Cost is dominated by the
// loop, not the interpolator.
//
// Topology: stable CIFB (Cascade of Integrators with distributed FeedBack),
// discrete time, one-bit quantizer:
//
//   s1[n] = s1[n-1] + b1*u[n-1] - a1*v[n-1]
//   si[n] = si[n-1] + rho*s(i-1)[n-1] - ai*v[n-1]      (i = 2..N)
//   v[n]  = sign(sN[n])
//
// with u the (held) PCM input, v the emitted bit (+/-1), rho the inter-stage
// scaling and ai the distributed feedback. For a given NTF denominator
// P(x) = 1 + p1*x + ... + pN*x^N (x = z^-1) the feedback vector satisfies
//
//   P(x) = (1-x)^N + sum_i ai * x^(N-i+1) * prod_{j=i..N-1} c_j * (1-x)^(i-1)
//
// The shipped sets come from P built with Butterworth poles at z = 1 + c*s_k
// (s_k the analog Butterworth poles), which keeps the out-of-band gain H_inf at or
// below 1.6 (Lee-criterion margin). rho is the state scaling; b1 = a1 is what
// makes the signal transfer function unity at DC, i.e. what pins the bit density
// to 0.5 + 0.5*kInputHeadroom*x.
//
// Measured (44.1 kHz -> DSD64, 1 kHz at -1 dBFS, integrated in-band SNR/SINAD over
// 20 Hz..20 kHz): order 2 = 67.8 dB, order 4 = 86.6 dB, order 5 = 87.4 dB;
// DSD256 order 4 = 89.8 dB. Peak integrator state 1.22, longest identical-bit run
// 6 bits. See .agents/reports/oversampling-sdm.md.
//
// Robustness: every integrator state is clamped to +/-kStateClamp and non-finite
// states are caught, so a full-scale input can distort but cannot diverge, and
// process() never allocates, locks, logs or throws.
//
// Bit packing: LSB-first, 8 samples per byte, first sample in bit 0 - the DSF
// convention that DsdNativePacker and the DoP framer (DopFramer.h) expect before
// any MSB-first reversal. Because dsdMultiple is a multiple of 8, every call emits
// a whole number of bytes and pendingBits() is always 0 at call boundaries.
#ifndef PULSR_SDM_MODULATOR_H_
#define PULSR_SDM_MODULATOR_H_

#include "Oversampler.h"

#include <cstdint>
#include <vector>

namespace pulsr {

class SdmModulator {
public:
    static constexpr int kChannels = 2;
    static constexpr int kMinOrder = 1;
    static constexpr int kMaxOrder = 5;

    // Anti-windup bound on every integrator state. Measured peak at 0 dBFS is
    // ~1.4 (order 5), so this leaves nearly 3x margin before the clamp acts.
    static constexpr float kStateClamp = 4.0f;

    // DSD modulation headroom: PCM +/-1.0 maps to +/-0.5 of quantizer full scale.
    // This is the conventional DSD 0 dBFS reference (50 % modulation index) and it
    // is what keeps a 4th/5th-order one-bit loop out of overload at full scale.
    // Consequence: ones density = 0.5 + 0.5 * kInputHeadroom * x.
    static constexpr float kInputHeadroom = 0.5f;

    // Longest run of identical bits accepted as "not overloaded" for a
    // full-scale-adjacent tone. Measured worst case at -1 dBFS is 7 bits.
    static constexpr int kMaxSaturationRunBits = 32;

    // Pre-interpolation factor and the internal PCM chunk it is processed in.
    static constexpr int kPreFactor = 8;
    static constexpr int kPcmChunk = 256;

    SdmModulator() = default;
    SdmModulator(const SdmModulator&) = delete;
    SdmModulator& operator=(const SdmModulator&) = delete;

    // pcmRate must be 44100*2^n or 48000*2^n with n <= 3; dsdMultiple is 64, 128
    // or 256; order is 1..5 (2, 4 and 5 are the validated points). Control path:
    // allocates and builds the interpolator.
    bool configure(double pcmRate, int dsdMultiple, int order);

    // Clears the loop state, the interpolator history and the partial byte. The
    // idle channel then restarts from a balanced 50 % pattern ("silence" for a
    // 1-bit stream is a 50 % density idle pattern, not an all-zero byte, which
    // would be full negative DC).
    void reset();

    // Frees every buffer and disables process().
    void release();

    // Consumes inFrames planar stereo PCM frames and writes inFrames*dsdMultiple
    // bits per channel, LSB-first. Returns bytes written per channel, or -1 if the
    // call was rejected: not configured, null pointers, negative frame count, or
    // outCapacity smaller than the bytes this call would produce. A rejected call
    // writes nothing and leaves the modulator state untouched.
    int process(const float* const* in, int inFrames, uint8_t* outL, uint8_t* outR,
                int outCapacity);

    bool isConfigured() const { return configured_; }
    int order() const { return order_; }
    int dsdMultiple() const { return dsdMultiple_; }
    double dsdRate() const { return dsdRate_; }
    int pendingBits() const { return bitCount_; }
    // Group delay of the 8x pre-interpolation, in PCM frames at pcmRate.
    double latencyPcmFrames() const;
    // Largest |integrator state| seen since the last reset(); telemetry for
    // overload detection.
    float peakStateMagnitude() const { return peakState_; }

private:
    float modulate(int channel, float x);

    float feedback_[kMaxOrder + 1] = {};
    float state_[kChannels][kMaxOrder + 1] = {};
    float lastBit_[kChannels] = {};
    uint8_t accumulator_[kChannels] = {};

    Oversampler upsampler_;
    std::vector<float> upBuf_[kChannels];   // kPcmChunk * kPreFactor
    float* upPtr_[kChannels] = {nullptr, nullptr};

    float b1_ = 0.0f;
    float rho_ = 1.0f;
    float peakState_ = 0.0f;
    double dsdRate_ = 0.0;
    double pcmRate_ = 0.0;
    int order_ = 0;
    int dsdMultiple_ = 0;
    int zoh_ = 1;              // hold repetitions per upsampled frame
    int bitCount_ = 0;
    bool configured_ = false;
};

}  // namespace pulsr

#endif  // PULSR_SDM_MODULATOR_H_
