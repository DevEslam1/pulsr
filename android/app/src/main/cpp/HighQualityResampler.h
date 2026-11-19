// android/app/src/main/cpp/HighQualityResampler.h
//
// High-quality arbitrary-ratio sample-rate converter for the player's final
// rate-conversion tap (44.1 <-> 48 <-> 96 ...). Deliberately a *separate*
// component from SincResampler: the convolution reverb's wet path is built on
// that class's fixed 32-phase / 64-tap geometry, so touching it would change
// reverb output. This one carries its own table, its own ratio handling and a
// streaming API sized for a sink tap.
//
// ---------------------------------------------------------------------------
// RATIO CONVENTION
// ---------------------------------------------------------------------------
// setRatio(r) takes "output frames per input frame" and process() maps output
// frame n onto input position n / r. The pitch of a tone is therefore
// preserved: resampling 44100 -> 48000 uses r = 48000 / 44100 = 1.0884, emits
// 1.0884 frames per input frame, and a 1 kHz input tone stays at 1 kHz at the
// output rate. configure() seeds the ratio from outRate / inRate; setRatio()
// is for arbitrary conversions and runtime corrections afterwards.
//
// The ratio is clamped into [kMinRatio, kMaxRatio] = [1/16, 16]. NaN, Inf and
// <= 0 are ignored (the previous ratio is kept). A nominal ratio outside that
// band is rejected by configure() rather than silently clamped: a silent clamp
// would resample at the wrong pitch.
//
// ---------------------------------------------------------------------------
// QUALITY
// ---------------------------------------------------------------------------
// Blackman-Harris-windowed sinc, one coefficient branch per phase, evaluated
// with the two tricks UsbAsrcClockSync.h documents:
//   * every branch is normalised to exact unity DC gain, so gain cannot ripple
//     with the fractional phase (that ripple is what shows up as sidebands
//     around the tone), and
//   * coefficients are interpolated between the two neighbouring branches at
//     run time. Snapping to the nearest branch alone leaves a timing error of
//     1/(2*phases) of a sample, which is only about -72 dB of sidebands at
//     1 kHz with 256 phases. Interpolating makes that error second order.
// phases_ + 1 rows are tabulated so the interpolation for frac -> 1 uses the
// genuine next-offset kernel instead of wrapping to branch 0 (which would be a
// full-sample jump and costs about -47 dB THD+N).
//
// The cutoff sits at the lower of the two Nyquist frequencies with a small
// guard band (kCutoffGuard), so upsampling never passes images and downsampling
// never folds the source's top octave back into the audible band. The table is
// rebuilt (in place, no allocation) when a ratio change moves that cutoff by
// more than 0.5 %, which is how the class stays honest for arbitrary ratios.
//
// ---------------------------------------------------------------------------
// REAL-TIME CONTRACT
// ---------------------------------------------------------------------------
// configure() allocates. process() never allocates, never locks, never logs and
// never throws; it reads only from `in`, so a caller may pass a shared decode
// buffer. reset()/setRatio() are control operations: they must not run
// concurrently with process(), which is the usual pattern of computing a new
// ratio at a block boundary or with the stream quiesced.
//
// |ratio - 1| < kBypassEpsilon is an exact bypass: whole frames are memcpy'd,
// no filter state is touched, so a locked clock domain stays bit-identical.
// Entering or leaving that bypass clears the history from setRatio() so no
// stale fractional phase can leak into the bit-perfect path.
//
// Inputs below kDenormalFloor (-400 dBFS) are flushed to zero on the way in and
// outputs below the same floor are flushed on the way out, keeping denormal
// arithmetic out of the filter state on CPUs without FTZ.
//
// ---------------------------------------------------------------------------
// STREAMING / PARTIAL CONSUMPTION
// ---------------------------------------------------------------------------
// process() consumes at most inFrames and produces at most maxOutFrames; it
// reports through `consumed` exactly how many input frames it took, which is
// fewer than inFrames when the output buffer filled first. Unconsumed input is
// never dropped: the caller advances its pointers and calls again. Frames that
// were consumed but not yet emitted (the kernel's lookahead) stay buffered, and
// a final call with inFrames == 0 and in == nullptr drains them.
//
// A caller sizing `out` as ceil(inFrames * ratio) + taps always has every input
// frame consumed in one call. Because the kernel needs `taps/2` frames of
// lookahead, a single call emits about ceil((inFrames - taps/2) * ratio) frames;
// the remainder is the filter tail and appears on the drain call.
#ifndef PULSR_HIGH_QUALITY_RESAMPLER_H_
#define PULSR_HIGH_QUALITY_RESAMPLER_H_

#include <vector>

namespace pulsr {

class HighQualityResampler {
public:
    static constexpr int kMinTaps = 64;
    static constexpr int kMaxTaps = 512;
    static constexpr int kMinPhases = 64;
    static constexpr int kMaxPhases = 2048;
    static constexpr int kMaxChannels = 8;

    // The engine accepts 8 kHz - 768 kHz on both sides, i.e. ratios up to
    // 96:1. Those extremes are functional (frame accounting stays exact) but
    // their transition band is necessarily wide; real playback stays inside a
    // few octaves. The limit only rejects a ratio that would overflow the
    // phase accumulator.
    static constexpr double kMinRatio = 1.0 / 256.0;
    static constexpr double kMaxRatio = 256.0;
    // Below this distance from unity the converter is a bit-exact passthrough.
    static constexpr double kBypassEpsilon = 1e-9;

    // Fraction of the lower Nyquist frequency the kernel passes. The remainder
    // is the transition band, which keeps images and aliases out of the band.
    static constexpr double kCutoffGuard = 0.96;

    // Frames of pending input the working buffer holds beyond the kernel
    // history. Bounds the buffer so an arbitrarily large block can be streamed.
    static constexpr int kPendingCapacity = 4096;

    static constexpr float kDenormalFloor = 1e-20f;

    HighQualityResampler() = default;
    ~HighQualityResampler() = default;
    HighQualityResampler(const HighQualityResampler&) = delete;
    HighQualityResampler& operator=(const HighQualityResampler&) = delete;
    HighQualityResampler(HighQualityResampler&&) = delete;
    HighQualityResampler& operator=(HighQualityResampler&&) = delete;

    // channels 1..8, taps 64..512 (even), phases 64..2048, finite rates > 0.
    // Allocates the coefficient table and the working buffer; returns false and
    // leaves the object unusable on bad geometry or a nominal ratio outside
    // [kMinRatio, kMaxRatio].
    bool configure(int channels, int taps, int phases, double inRate, double outRate);
    bool isConfigured() const { return configured_; }

    // Planar float in / planar float out. Returns the number of frames written
    // to `out` and reports the number of input frames taken through `consumed`.
    // inFrames == 0 with in == nullptr drains the buffered filter tail.
    int process(const float* const* in, int inFrames, float* const* out, int maxOutFrames,
                int& consumed);

    // See the ratio convention above. Clamped; NaN/Inf/<=0 keep the previous
    // ratio. Ignored before configure(). A change that moves the anti-alias
    // cutoff by more than 0.5 % rebuilds the coefficient table (no allocation,
    // but O(phases*taps)), so call it at a block boundary or with the stream
    // quiesced.
    void setRatio(double outPerIn);
    double ratio() const { return ratio_; }
    bool bypassed() const { return bypass_; }

    // Nominal group delay in *output* frames at the current ratio: taps/2 input
    // frames of lookahead. Stable for a given (taps, ratio). In exact bypass the
    // effective delay is 0 because no filtering happens.
    int latencyFrames() const;

    // Clears filter history, fractional phase and buffered input; keeps the
    // configuration and the ratio. Bit-identical output for bit-identical input.
    void reset();

    // Frees the tables. configure() is required again afterwards.
    void release();

    int channels() const { return channels_; }
    int taps() const { return taps_; }
    int phases() const { return phases_; }
    double inRate() const { return inRate_; }
    double outRate() const { return outRate_; }

private:
    // Emits as many frames as the buffered input allows into out[c][outOffset..].
    int generate(float* const* out, int outOffset, int maxOut);
    // Drops `frames` consumed input frames and re-seats the kernel history.
    void dropFrames(int frames);
    void buildKernel();
    void clearStream();
    bool pointersValid(const float* const* in, int inFrames, float* const* out) const;

    // (phases_ + 1) * taps_ floats; row = branch, column = tap.
    std::vector<float> coef_;
    // channels_ laid out channel-major, stride_ frames per channel.
    std::vector<float> buf_;

    int channels_ = 0;
    int taps_ = 0;
    int halfTaps_ = 0;
    int phases_ = 0;
    int stride_ = 0;
    int pending_ = 0;
    double inRate_ = 0.0;
    double outRate_ = 0.0;
    double ratio_ = 1.0;
    double step_ = 1.0;
    // Cutoff (cycles per input sample) the table was built for.
    double kernelCutoff_ = 0.5;
    // Integer read offset and fractional phase are kept separate so buffering
    // and history re-seating can never change how the phase accumulates: every
    // drop is an exact integer subtraction. Mixing them in one double makes the
    // output depend on the caller's block size in the last bits.
    int readPos_ = 0;
    double frac_ = 0.0;
    bool bypass_ = true;
    bool configured_ = false;
};

}  // namespace pulsr

#endif  // PULSR_HIGH_QUALITY_RESAMPLER_H_
