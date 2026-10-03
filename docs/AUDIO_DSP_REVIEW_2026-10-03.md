# Audio DSP, JNI, Android bridge, and Dart review

Reviewed the current working tree on 2026-10-03, including uncommitted changes. Production files were not edited. Scores are subjective engineering assessments of implementation, integration, and verification; they are not listening-test scores or hardware certification. A passing test does not exclude the defects below.

## Layer ratings

| Area | Rating / 10 | Assessment |
| --- | --- | --- |
| C++ effects, considered individually | 8 | Extensive defensive DSP and meaningful numerical tests; playback integration weakens several features. |
| C++ engine and snapshot coordination | 6 | Pending sample-rate and reset commands can be overwritten; latency accounting is incomplete. |
| Android Kotlin / Media3 bridge | 7 | Good ownership and output routing, but some unsupported native operations return success and automatic limiting is not wired. |
| JNI | 8 | Bounds validation, prepared inputs, teardown coordination, and runtime smoke coverage are substantial. Successful smoke tests do not prove all concurrent lifecycle schedules. |
| Dart channel and DSP management | 6.5 | Broad coverage and centralized ranges; restoration depends on native acknowledgement and many setters swallow failure. |
| Overall current audio stack | 7 | Solid foundation with specific remaining correctness and verification gaps. |

## Individual native effect ratings

These scores evaluate the usable feature, including its engine wiring. Ordinary per-effect tests often bypass the problematic engine and platform paths.

| Effect / processing feature | Rating / 10 | Main assessment |
| --- | --- | --- |
| Parametric EQ | 8 | Multi-band, structural-state handling, smoothing, finite guards; track-rate defect can shift the audible response. |
| Crossfeed | 8 | BS2B modes and configurable path; its fade-out processing can be skipped when the engine stage mask is dropped. |
| Lookahead / true-peak limiter | 7 | Standalone numerical tests pass; automatic insertion with the user toggle off is ineffective. |
| Convolution reverb | 8 | Prepared IRs, partitioned processing, bounded resources, and extensive tests. |
| Sinc resampler as a playback feature | 3 | In-place playback entry point is a deliberate passthrough; UI enable/quality/rate settings cannot deliver the advertised conversion there. |
| Sinc planar converter used by reverb | 8 | Actual variable-frame conversion exists; dedicated resampler tests pass. |
| Spatial panner / mono | 8 | Smoothed pan gains and channel-pair handling. |
| Harmonic saturation / exciter | 8 | Oversampling and dry/wet alignment; native latency report omits its delay. |
| Stereo width / multiband imager | 8 | M/S and crossover processing; abrupt engine mask removal can bypass transition smoothing. |
| Loudness contour | 8 | Volume-aware shelves and smoothing; depends on correct volume and rate updates. |
| Sub crossover / bass management | 8 | Ramp-out survives stage removal, unlike several other effects; mono input is guarded. |
| Dynamic EQ | 7.5 | Compression/expansion and finite checks; saved bands can fail to hydrate after a channel error. |
| Multiband compressor | 8 | LR4 split/recombination, phase compensation, and dynamics parameters. |
| Dynamic bass | 8 | Presets, envelope processing, and cutoff-state handling. |
| ViPER-DDC | 8 | Off-render parsing and coefficient validation; correction remains dependent on sample-rate selection. |
| Arbitrary response EQ | 7.5 | Bounded parsing and prepared nodes; FIR delay is omitted from pipeline latency. |
| LiveProg | 7.5 | Prepared bytecode, execution bounds, and output guards; stereo-oriented execution. |
| ReplayGain | 8 | Peak-aware gain and smoothing; boosts share the automatic-limiter integration gap. |
| Direct volume | 7 | Smooth gain stage; boosted output hard-clips when automatic limiting is expected but inactive. |
| TPDF dither | 8 | Depth/route gating and bypass handling; hardware output depth still requires verification. |
| Headphone safety / dose tracking | 6 | Separate enforcement exists; unsupported enable can report success and safety-limiter latency is omitted. |
| A/B comparison bypass | 7.5 | Compensation and finite guards; latency reporting does not account for the early-return path. |
| Bit-perfect DSP bypass | 8.5 | PCM16 and float byte-preservation smoke tests pass; internal bypass does not establish end-to-end device bit perfection. |

Supporting output/conversion code: DSD decoder **8/10**, DoP framing **8/10**, AAudio output **8/10**, USB exclusive output **6.5/10** pending physical DAC verification.

## Confirmed defects and remedies

### 1. P1: A broadcast can overwrite a pending track sample rate

[AudioDspEngine.cpp:548](D:/Courses/Projectss/pulsr/android/app/src/main/cpp/AudioDspEngine.cpp:548)

`resyncForTrack(96000, 2)` publishes 96 kHz but the applied `sampleRate_` remains 48 kHz until rendering. `publishParams()` then preserves that applied value, overwriting the pending 96 kHz command when an effect broadcast arrives before the first block. The probe prints `96000 -> 48000`, and the next block actually applies 48 kHz. This affects rate-dependent filter coefficients and timing even though PCM playback continues.

Preserve the render engine's latest requested track rate separately from the last applied rate, and merge control broadcasts against that requested state. Test resync followed by a broadcast before rendering.

### 2. P2: Reset is lost if another publication arrives first

[AudioDspEngine.cpp:506](D:/Courses/Projectss/pulsr/android/app/src/main/cpp/AudioDspEngine.cpp:506), [AudioDspEngine.cpp:195](D:/Courses/Projectss/pulsr/android/app/src/main/cpp/AudioDspEngine.cpp:195)

`reset()` publishes `resetRequested=true`, but subsequent `updateParams()` or rate publication clears it before audio acknowledges it. A singleton broadcast can replace the local reset too. Probe: pending reset `1 -> 0` after one parameter edit. Old delay/filter/script state can survive an intended reset. The Java reset/flush lifecycle makes preserving this command especially relevant.

Use a monotonic reset generation acknowledged by the renderer rather than a transient boolean inside a replaceable snapshot.

### 3. P2: Playback sinc-resampler controls operate a no-op

[SincResampler.cpp:125](D:/Courses/Projectss/pulsr/android/app/src/main/cpp/SincResampler.cpp:125), [AudioDspEngine.cpp:808](D:/Courses/Projectss/pulsr/android/app/src/main/cpp/AudioDspEngine.cpp:808), [equalizer_manager.dart:2259](D:/Courses/Projectss/pulsr/lib/data/audio/equalizer_manager.dart:2259)

The engine uses `processInterleaved()`, which always returns the input unchanged, even for differing rates. This is a deliberate safe fallback for the fixed-frame contract, but the enabled playback feature and quality controls still imply that native sinc conversion happens. Platform conversion may occur independently. `processPlanar()` is a real converter used by reverb and is a separate path.

Either integrate a variable-frame converter with output-format negotiation, or expose the platform fallback truthfully and disable ineffective quality controls.

### 4. P2: The automatic limiter path cannot activate a disabled limiter

[AudioDspEngine.cpp:914](D:/Courses/Projectss/pulsr/android/app/src/main/cpp/AudioDspEngine.cpp:914), [LookaheadLimiter.cpp:348](D:/Courses/Projectss/pulsr/android/app/src/main/cpp/LookaheadLimiter.cpp:348), [AudioEffectsPlugin.kt:757](D:/Courses/Projectss/pulsr/android/app/src/main/kotlin/com/pulsr/music/AudioEffectsPlugin.kt:757)

The engine has a positive-gain automatic-limiter condition, but Kotlin includes the stage only when explicitly enabled, and the limiter independently returns immediately when its enabled parameter is false. Even forcing the stage bit does not activate it. With input 0.5 and DVC gain 4, the probe reaches the final hard clamp at 1.0 instead of controlled limiting. This is a distortion/protection gap, not an out-of-bounds output bug: the final clamp does bound samples.

Define an effective limiter state from explicit enable OR automatic protection; apply it consistently to both the stage mask and limiter parameters. Cover other boosting stages as well.

### 5. P2: Reported pipeline latency does not represent the actual path

[AudioDspEngine.h:148](D:/Courses/Projectss/pulsr/android/app/src/main/cpp/AudioDspEngine.h:148)

The report uses enabled flags for limiter/resampler/reverb, ignores stage masks, auto-degradation and bypass, and omits safety-limiter, saturation and arbitrary-EQ delays. Probe: bit-perfect bypass reports 240 frames although it returns without DSP; a safety-only path reports zero although it runs a lookahead limiter. A enabled mismatched playback resampler is a passthrough yet can contribute latency.

Publish renderer-observed effective latency from the stages that actually processed the last block. Include every delaying stage and zero it for early-return bypass paths. Check delay alignment with impulse-based tests.

### 6. P2: One native-channel failure aborts saved-state hydration

[equalizer_manager.dart:664](D:/Courses/Projectss/pulsr/lib/data/audio/equalizer_manager.dart:664)

Restoration awaits the bypass channel before hydrating saved dynamic-EQ bands and headphone-profile state. Unlike most setters, bypass errors propagate; the outer restore catch then exits. The existing persistence test fails both in the focused run and in isolation: saved dynamic-EQ frequency 2500 Hz restores as the default 1000 Hz when the channel implementation is missing. This test uses a missing-plugin scenario, not a successful physical Android session; the control flow also applies to a rejected or failed native call.

Hydrate and validate all preferences before native I/O. Then apply separately, retaining native failure status without discarding saved in-memory settings.

### 7. P2: Native-only effects can report success when the engine is unavailable

[AudioEffectsPlugin.kt:2151](D:/Courses/Projectss/pulsr/android/app/src/main/kotlin/com/pulsr/music/AudioEffectsPlugin.kt:2151), [AudioEffectsPlugin.kt:2205](D:/Courses/Projectss/pulsr/android/app/src/main/kotlin/com/pulsr/music/AudioEffectsPlugin.kt:2205), [audio_effects_channel.dart:858](D:/Courses/Projectss/pulsr/lib/data/audio/audio_effects_channel.dart:858)

For example, `setHeadphoneSafetyParams` returns success with no loaded native engine. Several native-only effect handlers similarly update cached flags and return success without applying DSP; Dart's void setters generally swallow platform errors, while managers update their local enabled flags. Controls and inspectors can therefore show an enabled feature that is not audible/active. Missing native libraries are explicitly supported as a degradation scenario by the Java processor.

Return an explicit applied/unsupported result for native-only operations; propagate acknowledgement to managers and commit effective state only on acceptance. Keep desired saved state distinct from applied state.

### 8. P2: The complete native test build is currently broken

[test_dsp_effects.cpp:92](D:/Courses/Projectss/pulsr/android/app/src/test/cpp/test_dsp_effects.cpp:92), [CMakeLists.txt:91](D:/Courses/Projectss/pulsr/android/app/src/test/cpp/CMakeLists.txt:91)

`test_dsp_effects` calls removed APIs, including `MultibandCompressor::setCrossovers/setBand`, `HarmonicSaturation::setParams`, `StereoWidth::setParams`, and the old dynamic-EQ band signature. Its link list also omits several effect implementation files that the test now uses. The full CMake build fails, although the other 12 executables compile and pass.

Migrate the test to current parameter structures and link all referenced implementations. Require an unfiltered build plus all CTest targets before claiming the complete suite is green.

## Additional transition risk from source inspection

`recalculateActiveStages()` immediately removes crossfeed, width, loudness and dynamic-EQ bits when their toggles turn off. Their processors contain fade-out logic, but the engine skips them after the bit disappears. SubCrossover explicitly survives mask removal via `isRamping()`. The same approach should be considered for the other stages. Audible click severity has not been measured in this review.

## Validation performed

- Focused Flutter run: **61 passed, 1 failed**; restoration failure reproduced in isolation.
- Focused Dart analysis: **no issues** in six bridge/manager/controller files.
- CMake build: **failed in `test_dsp_effects`** on stale APIs.
- Other **12 native executables passed** on the x86_64 Android emulator, including the aggregate suite, mutation stress, reverb, limiter, resampler, DSD, bypass, and DoP tests.
- Mutation stress: **2,693,859 parameter swaps in 41,346 ms**, reported no NaN/Inf.
- Four rebuilt Java/JNI smoke harnesses passed against the existing production-library build, which is newer than the reviewed modified C++ sources: AAudio API/bounds/exclusive policy, PCM16 exhaustive quantization and float bypass, AAudio Media3 partial/heap writes, and float/PCM24/PCM32 partial retries.
- Source-name wiring check: **78 Kotlin native declarations** have matching JNI function names; **94 distinct Dart channel calls** have matching Kotlin handler names. This check is name-level, not full ABI-signature certification.
- Dedicated current-source native probe reproduced pending-rate overwrite, reset loss, hard clipping with automatic limiting inactive, and bypass/safety latency errors.
- No new ASan/UBSan run or physical DAC/listening/loopback test was performed. The historical verification document does not establish a clean full build for this current tree.

Evidence and the dedicated probe are in `build/audio-review-*.log` and `build/audio_review_probe.cpp`. Production source remains unchanged.
