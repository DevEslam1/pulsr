# ADR 005: DSP Audio Processing Pipeline and Safety Architecture

## Status
Accepted

## Context
Pulsr provides audiophile-grade digital signal processing (DSP) features including multi-band parametric equalizers (10/32/64-band), convolution reverb via impulse response (IR) files, stereo spatialization, Viper DDC correction, dynamic EQ, and bit-perfect USB streaming.

Historically, managing these complex DSP stages surfaced several operational risks:
1. **Audio Stage Degrades**: Applying heavy biquad cascades or large convolution kernels on lower-power devices could lead to buffer underruns, audio glitches, or battery drain.
2. **Bit-Perfect Conflicts**: Users enabling bit-perfect Direct USB streaming would encounter unexpected audio distortion if DSP stages continued altering PCM samples before DAC handoff.
3. **Comparison Traps**: The "A/B Flat Comparison" feature allowed listeners to momentarily bypass effects to evaluate sound changes. If gestures failed to emit `onTapUp` or state became desynchronized, the audio engine could stay bypassed indefinitely without user awareness.

## Decision
We established a strict sequential DSP execution model and safety guards:

### 1. Sequential Pipeline Topology
The DSP pipeline processes samples in the following fixed deterministic order:
`Source PCM -> Parametric / Graphic EQ -> Viper DDC / Headphone Profile -> Dynamic EQ -> Stereo Width & Crossfeed -> Saturation & Dynamics -> Convolution Reverb / Spatializer -> Limiter & Normalization -> Sink (AAudio / Bit-Perfect Direct USB)`

### 2. Bit-Perfect Hardware Bypass
When bit-perfect streaming is active and target hardware supports direct PCM/DSD output:
- `AudioConflicts.dspBlockedByBitPerfect` identifies active bypass constraints.
- `PlayerDspController` mutes software DSP nodes to guarantee bit-accurate byte passthrough without quantization or resampling artifacts.

### 3. A/B Comparison Safety & 10-Second Auto-Revert
To prevent permanent effect bypass during comparative listening:
- `PlayerDspController.startAbComparison()` arms a 10-second auto-revert timer.
- If no user release action occurs within 10 seconds, `endAbComparison()` is automatically dispatched to restore active listening presets.
- The UI layer (`EqualizerSheet`) mirrors this timer to ensure immediate visual synchronization and haptic consistency.

### 4. Bounded Impulse Response (IR) Memory Safety
- Custom WAV IR files for convolution reverb are capped at 25 MB (`PlayerDspController.maxIrFileSizeBytes`).
- All user-selected file paths are validated using `SafeFilePath.validate` before reading from disk to prevent malformed or oversized file attacks.

## Consequences
### Positive
- Predictable audio latency and phase characteristics across all DSP stages.
- Guaranteed bit-perfect compliance when outputting to external DACs.
- Automatic recovery from stalled A/B comparison touch states.
- Memory protection against out-of-memory crashes on oversized impulse responses.

### Negative / Trade-offs
- Highly customized DSP filter chains cannot be reordered arbitrarily by users.
- A/B listening is limited to a maximum continuous duration of 10 seconds per touch-hold.
