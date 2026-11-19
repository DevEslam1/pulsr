// android/app/src/main/cpp/UsbAsrcClockSync.h
//
// Polyphase windowed-sinc asynchronous sample-rate converter, used as the USB
// clock-sync fallback: when the DAC's clock cannot be tracked by steering
// packet cadence alone, the renderer runs at one nominal rate and this stage
// absorbs the remaining (small) rate error by resampling.
//
// ---------------------------------------------------------------------------
// RATIO CONVENTION
// ---------------------------------------------------------------------------
// setRatio(r) takes "output frames per input frame". Output sample n maps to
// input position n / r, so a tone of f Hz on the input appears at f / r Hz on
// the output. A DAC whose clock runs fast needs more frames per unit time, so
// it needs r > 1 and the pitch is pulled down by exactly the clock error.
// The ratio is hard-clamped to +/-0.5% of unity and rejected when it is NaN,
// infinite or <= 0 (the previous ratio is kept in that case).
//
// ---------------------------------------------------------------------------
// QUALITY
// ---------------------------------------------------------------------------
// The kernel is a Blackman-Harris windowed sinc of `taps` input samples with
// `phases` branches. 32 taps / 256 branches already puts the 1 kHz THD+N floor
// well below -90 dB because two extra steps are taken:
//   * every branch is normalised to exact unity DC gain, so gain cannot
//     ripple with the fractional phase (which is what would otherwise show up
//     as sidebands around the tone), and
//   * the residual within a branch interval is handled by interpolating
//     coefficients between the two neighbouring branches. Snapping to the
//     nearest branch alone would leave a timing error of 1/(2*phases) of a
//     sample, i.e. about -72 dB of sideband energy at 1 kHz with 256 phases;
//     coefficient interpolation makes that error second order and pushes it
//     below -140 dB.
//
// ---------------------------------------------------------------------------
// REAL-TIME CONTRACT
// ---------------------------------------------------------------------------
// configure() allocates; process()/reset()/setRatio() never allocate, never
// lock and never call into the platform. process() reads only from `in`, so a
// caller can pass a shared decode buffer. ratio == 1.0 (the default) is an
// exact bypass: a straight memcpy of whole frames, no filter state touched, so
// a locked clock domain stays bit-identical. Entering or leaving that bypass
// clears the filter history from setRatio() (a control operation) so no stale
// fractional phase can leak into the bit-perfect path.
//
// Inputs below 1e-20 (-400 dBFS) are flushed to zero on the way in and outputs
// below the same floor are flushed on the way out. That keeps denormal
// arithmetic out of the filter state on CPUs without FTZ, which is the
// difference between "inaudible" and "a stalled audio thread" at these levels.
#ifndef PULSR_USB_ASRC_CLOCK_SYNC_H_
#define PULSR_USB_ASRC_CLOCK_SYNC_H_

#include <cstddef>
#include <cstdint>
#include <vector>

namespace pulsr {

class UsbAsrcClockSync {
public:
    // Hard clamp: a clock-sync fallback must never be able to change pitch by
    // more than this, whatever a broken feedback decoder reports.
    static constexpr double kMaxRatioDeviation = 0.005;  // +/-0.5 %
    static constexpr double kMinRatio = 1.0 - kMaxRatioDeviation;
    static constexpr double kMaxRatio = 1.0 + kMaxRatioDeviation;

    static constexpr int kDefaultTaps = 32;
    static constexpr int kDefaultPhases = 256;
    static constexpr int kMinTaps = 8;
    static constexpr int kMaxTaps = 64;
    static constexpr int kMinPhases = 32;
    static constexpr int kMaxPhases = 1024;
    static constexpr int kMaxChannels = 8;

    // Internal lookahead window; not part of the public contract. Bounds the
    // working buffer so a caller may pass an arbitrarily large input block.
    static constexpr int kPendingCapacity = 2048;

    // Below this magnitude a float is treated as silence (see header comment).
    static constexpr float kDenormalFloor = 1e-20f;

    UsbAsrcClockSync() = default;
    ~UsbAsrcClockSync() = default;
    UsbAsrcClockSync(const UsbAsrcClockSync&) = delete;
    UsbAsrcClockSync& operator=(const UsbAsrcClockSync&) = delete;
    UsbAsrcClockSync(UsbAsrcClockSync&&) = delete;
    UsbAsrcClockSync& operator=(UsbAsrcClockSync&&) = delete;

    // channels 1..8, taps 8..64 (even), phases 32..1024. Allocates the
    // coefficient table and the working buffers; returns false and leaves the
    // object unusable on bad geometry.
    bool configure(int channels, int taps = kDefaultTaps, int phases = kDefaultPhases);
    bool isConfigured() const { return configured_; }

    // See the ratio convention above. NaN/Inf/<=0 are ignored (previous ratio
    // is kept); everything else is clamped into [kMinRatio, kMaxRatio].
    //
    // Thread ownership: process() and reset()/setRatio() mutate the same filter
    // state, so they must not run concurrently. Call setRatio() from the
    // streaming thread between process() calls (the usual pattern: the feedback
    // loop computes the ratio, then hands it over at a block boundary), or with
    // the stream quiesced.
    void setRatio(double outPerIn);
    double ratio() const { return ratio_; }
    bool bypassed() const { return bypass_; }

    // Consumes input and produces up to maxOutFrames output frames. Returns the
    // number of frames written to `out`. inputFramesConsumed() reports how much
    // of `in` this call actually took: it is less than inFrames only when the
    // output buffer filled up first, in which case the caller should advance
    // its input pointer and call again.
    //
    // A caller sizing `out` as ceil(inFrames * ratio) + taps always sees the
    // whole block consumed.
    int process(const float* in, int inFrames, float* out, int maxOutFrames);
    int inputFramesConsumed() const { return inputFramesConsumed_; }

    // Clears filter history and fractional phase; keeps configuration and
    // ratio. Bit-identical output for bit-identical input after a reset.
    void reset();

    // Nominal group delay of the kernel, expressed in output frames at the
    // current ratio. Output produced before this many frames has been filtered
    // against zero-padded history (a start-up ramp, not a discontinuity).
    int latencyFrames() const;

    int channels() const { return channels_; }
    int taps() const { return taps_; }
    int phases() const { return phases_; }

private:
    // Emits as many frames as the buffered input allows into `out`.
    int generate(float* out, int maxOut);
    // Drops `frames` consumed input frames and re-seats the history window.
    void dropFrames(int frames);
    void buildKernel();
    void clearStream();

    std::vector<float> coef_;  // phases_ * taps_, row = branch, col = tap
    std::vector<float> buf_;   // (taps_ + kPendingCapacity) * channels_
    int channels_ = 0;
    int taps_ = 0;
    int halfTaps_ = 0;
    int phases_ = 0;
    int pending_ = 0;
    int inputFramesConsumed_ = 0;
    double ratio_ = 1.0;
    double step_ = 1.0;
    double pos_ = 0.0;  // fractional read position inside the pending region
    bool bypass_ = true;
    bool configured_ = false;
};

}  // namespace pulsr

#endif  // PULSR_USB_ASRC_CLOCK_SYNC_H_
