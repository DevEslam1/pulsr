// android/app/src/main/cpp/DacVoicing.h
#pragma once

#include "DspParams.h"
#include <vector>
#include <cstdint>

// DacVoicing: an opt-in output "voicing" stage that emulates the two things a
// premium DAC's analog-like presentation is usually attributed to:
//
//   1. Reconstruction-filter CHARACTER. The codebase previously only ever used
//      a sharp linear-phase windowed-sinc (which pre-rings). High-end DACs let
//      you pick the filter; the audible differences are pre-/post-ringing and
//      roll-off steepness. This stage offers three:
//        Sharp        - linear-phase, steep (accurate, symmetric pre+post ring)
//        Slow         - linear-phase, gentle roll-off (NOS-like, less pre-ring)
//        MinimumPhase - same magnitude as Sharp, all post-ring, no pre-ring
//      The minimum-phase prototype is derived from the Sharp magnitude by the
//      real-cepstrum method (FftUtil), so its passband matches Sharp exactly.
//
//   2. A subtle EVEN-ORDER harmonic "voicing" (2nd-harmonic triode warmth),
//      injected at 4x oversampling so its images land above the base Nyquist
//      and are removed by the reconstruction filter (aliasing-free). amount=0
//      adds no harmonics - only the filter character is applied.
//
// Design notes / honest scope:
//   * Oversampling is fixed at 4x. The audible knob that matters is the filter
//     character, not the ratio, so 2x/4x selection was dropped for simplicity.
//   * When enabled the stage is ALL-WET (the filtered+voiced signal IS the
//     output); enable/disable crossfades a dry tap delayed by the SAME integer
//     group delay every character reports, so toggling or switching character
//     cannot click, comb, or change the pipeline latency.
//   * RT-safe: prototype tables and group-delay measurement are computed in the
//     constructor (engine construction happens off the render thread); the
//     audio thread only reads fixed-size tables and per-channel rings.
//   * Bit-perfect never reaches this stage (the engine returns before effects).
class DacVoicing {
public:
    static constexpr int MAX_CHANNELS = 8;
    static constexpr int OVERSAMPLE = 4;
    static constexpr int FIR_TAPS = 64;
    static constexpr int TAPS_PER_PHASE = FIR_TAPS / OVERSAMPLE; // 16
    // Long enough for the linear-phase combined group delay (~16 base samples)
    // with headroom; measured delays are clamped below this.
    static constexpr int MAX_DELAY = 48;

    enum Character : int {
        Sharp = 0,
        Slow = 1,
        MinimumPhase = 2,
    };

    DacVoicing();

    void setSampleRate(double sampleRate);
    void applyParams(const DacVoicingParamSet& params);
    // Rising edge flushes the rings so a stale dry-delay line cannot blip when
    // the stage comes back after a long bypass.
    void setEnabled(bool enabled);
    bool isEnabled() const { return enabled_; }
    bool isRamping() const;
    // Integer base-rate group delay of the wet path (0 when bypassed). The same
    // value for every character (see the pad note in the class comment).
    int getLatencyFrames() const;
    void reset();

    void processInterleaved(float* buffer, int frames, int channels = 2);

    // --- Pure, host-verifiable filter design (constructor-time only) ---
    // Returns a taps-length prototype for the given character. fcNorm is the
    // cutoff in cycles/sample at the OVERSAMPLE rate (Nyquist = 0.5); the base
    // Nyquist for 4x is 0.125.
    static std::vector<float> designPrototype(int character, double fcNorm, int taps);
    // Converts a real prototype into a minimum-phase impulse response of length
    // outLen via the real-cepstrum method (same magnitude, no pre-ringing).
    static std::vector<float> toMinimumPhase(const std::vector<float>& prototype, int outLen);

    int getCharacter() const { return character_; }
    double getVoicingAmount() const { return voicingAmount_; }
    int getGroupDelayFrames() const { return delayBase_; }

private:
    // Builds the polyphase table for one character (each phase DC-normalised)
    // and simulates an impulse through interpolate->decimate to measure its
    // integer base-rate group delay. Constructor-time only.
    static void buildCharacter(int character, float table[OVERSAMPLE][TAPS_PER_PHASE]);
    static int measureGroupDelay(const float table[OVERSAMPLE][TAPS_PER_PHASE]);

    double sampleRate_ = 48000.0;
    int character_ = Sharp;
    double voicingAmount_ = 0.0;
    bool enabled_ = false;
    float smoothedEnable_ = 0.0f;
    float smoothedVoicing_ = 0.0f;

    // Prebuilt at construction for all three characters; the audio thread only
    // indexes by character_. Interpolation and decimation share the prototype
    // (same table), matching the saturation stage's structure.
    float tables_[3][OVERSAMPLE][TAPS_PER_PHASE] = {};
    // Unified pipeline delay = max measured character delay; shorter-delay
    // characters (minimum phase) pad their wet path so alignment and reported
    // latency never change when the user switches character.
    int delayBase_ = 0;
    int padAmount_[3] = {};

    float inHistory_[MAX_CHANNELS][TAPS_PER_PHASE] = {};
    float decimHistory_[MAX_CHANNELS][FIR_TAPS] = {};
    int decimIdx_ = 0;
    float dryDelay_[MAX_CHANNELS][MAX_DELAY] = {};
    float wetPad_[MAX_CHANNELS][MAX_DELAY] = {};
    int dryPos_ = 0;

    // DC blocker on the squared (2nd-harmonic) term at the oversampled rate, so
    // the even-order injection adds no DC. voicing=0 skips it entirely.
    float sqDcX_[MAX_CHANNELS] = {};
    float sqDcY_[MAX_CHANNELS] = {};
    float dcCoeffOs_ = 0.9997f;
};
