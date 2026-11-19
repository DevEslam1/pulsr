// android/app/src/main/cpp/Oversampler.h
//
// Integer-factor (2x / 4x / 8x) polyphase FIR upsampler for the 44.1/48 kHz
// family PCM path. 4x and 8x are built as a cascade of 2x stages so a single
// prototype design feeds every factor.
//
// Design summary (see Oversampler.cpp for the coefficient construction):
//   * Sharp        - long Kaiser-windowed halfband, ~-100 dB images
//   * Slow         - short halfband with a very wide transition (NOS-adjacent)
//   * Apodizing    - gentle early rolloff, -3 dB before the input Nyquist
//   * MinimumPhase - true minimum phase, obtained by homomorphic spectral
//                    factorization (log magnitude -> real cepstrum -> fold ->
//                    exponentiate) of the Sharp prototype. The factor keeps the
//                    prototype's full length and is verified in configure()
//                    against that magnitude; costs about 2x a halfband kernel.
//
// Real-time contract: configure() allocates; process()/reset() do not allocate,
// lock, log or throw. Frames are processed in fixed internal chunks, so callers
// may pass any block size.
//
// Latency: latencyFrames() is the group delay expressed in *output-rate* frames,
// rounded up to the next whole frame. It is measured at configure() time from the
// first moment of the composite impulse response, which for the linear-phase
// kernels is exactly their constant group delay. For MinimumPhase the group delay
// is frequency dependent by construction, so the reported value is the delay at
// DC (the largest in-band delay) - it is never a linear-phase number in disguise.
#ifndef PULSR_OVERSAMPLER_H_
#define PULSR_OVERSAMPLER_H_

#include <cstdint>
#include <vector>

namespace pulsr {

enum class OversampleKernel { Sharp, Slow, MinimumPhase, Apodizing };

class Oversampler {
public:
    static constexpr int kMaxChannels = 8;
    static constexpr int kMaxFactor = 8;
    static constexpr int kMaxStages = 3;      // log2(kMaxFactor)
    static constexpr int kChunkFrames = 512;  // internal block, bounds scratch use

    Oversampler() = default;
    Oversampler(const Oversampler&) = delete;
    Oversampler& operator=(const Oversampler&) = delete;

    // Control path: builds coefficients and all buffers. Returns false for an
    // unsupported channel count / factor and leaves the object released.
    bool configure(int channels, int factor, OversampleKernel kernel);

    // Clears every filter history (no allocation). Silence in -> silence out.
    void reset();

    // Frees every buffer. process() then returns -1 until configure() is called.
    void release();

    // Group delay in output frames; 0 when not configured.
    int latencyFrames() const { return configured_ ? latencyFrames_ : 0; }

    // Consumes exactly inFrames input frames per channel and emits exactly
    // inFrames * factor() output frames per channel. Returns the number of
    // output frames emitted per channel, or -1 if the call was rejected
    // (not configured, null pointers, negative frame count). Nothing is written
    // on rejection.
    int process(const float* const* in, float* const* out, int inFrames);

    bool isConfigured() const { return configured_; }
    int channels() const { return channels_; }
    int factor() const { return factor_; }
    int stages() const { return stages_; }
    OversampleKernel kernel() const { return kernel_; }

    // Introspection for tests and telemetry.
    int stageTaps(int stage) const;
    bool minimumPhaseVerified() const { return minimumPhaseVerified_; }
    float minimumPhaseMaxErrorDb() const { return minimumPhaseErrorDb_; }

private:
    struct Stage {
        std::vector<float> phase0;  // taps h[0], h[2], h[4], ...
        std::vector<float> phase1;  // taps h[1], h[3], h[5], ...
        int taps = 0;               // prototype length (odd)
        int phaseTaps = 0;          // padded taps per phase, (taps + 1) / 2
        int delay = 0;              // (taps - 1) / 2, at this stage's output rate
        // A halfband prototype leaves phase1 with a single non-zero tap, which
        // collapses the odd output to a pure delay (one multiply per frame).
        bool phase1IsDelay = false;
        int phase1DelayTaps = 0;
        float phase1Gain = 0.0f;
    };

    void buildStage(int stage, const std::vector<float>& prototype);
    void runStage(int stage, int channel, const float* in, float* out, int frames);
    void runCascade(int channel, const float* in, float* out, int frames);
    int measureLatency();

    Stage stageChain_[kMaxStages];
    std::vector<float> history_[kMaxStages];  // channels * (phaseTaps - 1)
    std::vector<float> stageBuf_[kMaxStages]; // kChunkFrames << (stage + 1)
    std::vector<float> scratch_;              // max(phaseTaps - 1) + kChunkFrames * factor / 2

    int channels_ = 0;
    int factor_ = 0;
    int stages_ = 0;
    int latencyFrames_ = 0;
    OversampleKernel kernel_ = OversampleKernel::Sharp;
    bool configured_ = false;
    bool minimumPhaseVerified_ = false;
    float minimumPhaseErrorDb_ = 0.0f;
};

}  // namespace pulsr

#endif  // PULSR_OVERSAMPLER_H_
