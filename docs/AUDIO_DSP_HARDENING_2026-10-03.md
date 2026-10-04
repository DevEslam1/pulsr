# Audio DSP hardening and playback startup repair

This follows `AUDIO_DSP_REVIEW_2026-10-03.md`. The original ratings describe the pre-fix implementation. The changes below improve correctness; they do not establish a universal 10/10 listening score or hardware certification.

## Implemented fixes

- Preserve the latest requested track sample rate across effect broadcasts before rendering.
- Latch reset commands with a generation counter so later parameter publications cannot cancel them.
- Run automatic gain protection independently of the manual limiter switch and stage bit, including direct-volume boosts and custom processing. Export actual limiter activity through JNI to the Android debug report.
- Publish render-observed pipeline latency atomically. Include automatic limiting, headphone safety, FIR EQ, saturation and reverb; report zero for bypass and the fixed-frame resampler fallback.
- Continue crossfeed, width, loudness and dynamic-EQ fade-out after their stage bits are removed.
- Hydrate stored dynamic-EQ/profile configuration before fallible native restoration.
- Reject unavailable native-only Android operations and propagate setter rejection to Dart. Commit effect enable flags after native acknowledgement; check profile-loading results.
- Disable ineffective native playback sinc controls and explain Android's conversion in English, Arabic and Spanish. The working planar converter remains available internally to reverb.
- Repair the native effects test target's stale APIs and missing source files, and add engine command/integration regression tests.

## Playback regression found during follow-up

The stricter unsupported-resampler error exposed an unconditional quality setter in `PulsrAudioHandler._init`. The installed Android app reproduced `DSP_UNSUPPORTED` escaping startup, before late playback collaborators were initialized. This prevented songs from playing.

Startup now uses the playback-facing setter, which skips unsupported native conversion and treats optional quality restoration as best effort. Explicit native setters still report rejection. A regression test exercises the actual streaming mixin setter with a rejecting method channel. Invalid UI theme/spacing references encountered while rebuilding were also corrected.

Android playback testing then exposed a separate queue regression: the current single-track and gapless paths called `play()` without assigning an audio source. Both paths now resolve and load their sources before playback, preserving the selected index/position and checking generation cancellation across asynchronous work. The queue mixin explicitly depends on the streaming mixin's source resolver.

A repeatable cold-start smoke test also exposed an engine-switch race when restoring saved gapless settings. A pending Play request is now retained until source preparation reaches playback, and engine switches preserve it. Explicit pause/stop clear that request. Paused queue loading also assigns the source and preserves the requested seek position.

## Verification

- Original hardening pass: 113 focused Dart tests passed across two groups; these include persistence, bypass, output-path and native-error contracts.
- Final release-parity Android x86_64 native pass: all 13 executable suites passed, including engine command contracts, numerical DSP tests, real-time allocation checks and snapshot races. Mutation stress completed 4,128,648 swaps without NaN/Inf.
- Actual production Java/JNI smoke: four harnesses passed, covering all 65,536 PCM16 values, native output lifecycle, float/PCM24/PCM32 bypass transitions, partial writes and retries.
- Android Kotlin and native production build succeeded for arm64-v8a, armeabi-v7a and x86_64.
- Android ASan/UBSan effects suite passed. Android vptr checks are excluded because NDK libc++ RTTI failed at `std::ostream` before DSP test code; leak detection was disabled. The interrupted aggregate sanitizer run is not recorded as a pass.
- Playback follow-up: 20 focused Dart tests passed; analysis of the repaired startup path and tested shell widgets was clean.
- Source-loading follow-up: 24 tests passed, including startup, DSP contracts, playback collaborators and player-controller delegation. The transport test mock now supplies the real playback-state stream expected by the controller.
- Rebuilt `app-ytm-debug.apk` and installed it on the Android emulator. Cold-start local WAV playback reached `PLAYING`, buffered all 60 seconds, advanced to approximately 24 seconds, paused at that position and resumed with no startup `DSP_UNSUPPORTED`, late-initialization error or playback exception in the captured logs.
- Added `scripts/run_audio_playback_smoke.ps1` to exercise actual app startup/source loading rather than just isolated JNI/DSP. Two successive builds passed cold-start playback, progress (5,928 ms and 5,688 ms), pause and resume with the saved gapless preference disabled. The final APK's logs contained no unsupported-resampler, late-initialization, unhandled asynchronous, playback-failure or fatal exception entries. Final analysis of all five affected audio modules was clean.

## Remaining evidence and implementation gaps

A true native playback sinc converter needs a variable-frame streaming contract and output-format negotiation. The current fixed-frame processor cannot implement rate conversion, and its controls are now truthfully disabled. Physical USB DAC output, end-to-end device bit perfection, listening quality, and sustained thermal/load behavior still require device measurements. Emulator and unit-test results do not certify those properties.
