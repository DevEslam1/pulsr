# Pulsr Section 8 - Final Remediation Plan to 10/10

Baseline: `master` @ `33b5aa3e`
Audit date: 2026-11-20
Scope: `docs/AUDIO_COMPETITIVE_REVIEW_2026-11-19.md` sections 8.1-8.11, plus the app-level wiring required to make each feature a product feature instead of an engine island.

---

## 1. Executive summary

The landed work contains strong DSP units (oversampler kernels, SDM modulators, LR4/LR2 crossover, NetCDF-3 SOFA parser, ABX statistics, MP4 atom walk, Subsonic authentication). The gap is integration and truthfulness:

- Remaster settings never reach the render engine; no sink reopen; PCM-to-DSD has no production caller.
- Native DSD mode returns a zero-filled `audio/wav` source while DSD is pumped out-of-band; transport is not wired; the availability flag was re-enabled before the path is real.
- AutoEQ FIR is routed into the convolution reverb at 20 percent wet; HRTF is unreachable from the app.
- True low-power bypass ignores active DSP stages and silently drops the EQ; battery telemetry payloads do not match the Dart model.
- Cast transport controls are unreachable from the UI and the prebuffer eviction loop can spin forever.
- The measurement harness cannot fail; ABX export has no privacy scrubbing despite the claim.

Verified baseline gates: `flutter analyze` clean; CTest 47/47; `:app:compileDevDebugKotlin` successful; docs and bridge guards pass; 95/95 targeted Dart tests pass. These gates do not exercise the broken production paths; two tests codify the UAC2 request bug and the silent native-DSD source.

Target: every feature is reachable from the UI, reaches the engine that actually renders, reports measured state, survives lifecycle events, and has hardware evidence where the spec requires it.

---

## 2. Baseline scorecard

| Section | Area | Current | Main blocker |
|---|---|---|---|
| 8.1 | Remaster | 3/10 | Settings do not propagate; no sink reopen; PCM-to-DSD unreachable |
| 8.2 | Native DSD | 3/10 | Silent source; no transport; flag re-enabled against spec |
| 8.3 | Decoders / ALAC | 6/10 | Parser real but unvalidated; no decoder pack; no re-probe migration |
| 8.4 | UAC2 mute and keys | 3/10 | GET_CUR uses 0x01 on UAC2; keys stolen regardless of setting |
| 8.5 | Network | 6.5/10 | Cast controls unreachable; eviction hang; UPnP control point dead |
| 8.6 | Per-headphone FIR | 4/10 | FIR routed to reverb at 20 percent wet; 48 kHz assumption |
| 8.7 | ABX export and harness | 5.5/10 | No scrubbing; harness can never fail; CCIF missing |
| 8.8 | Multichannel | 4/10 | Layout/LFE index mismatch; no MCH device gating |
| 8.9 | HRTF / SOFA | 4/10 | Unreachable; render-thread allocation and race risk |
| 8.10 | True low-power | 4/10 | Bypass not interlocked; telemetry broken |
| 8.11 | Docs and tests | 6/10 | Green suites enshrine defects; false claims in docs |

Overall: 4.5/10. Library-level DSP quality: 7-8/10. End-to-end delivery: 2-4/10.

---

## 3. Hard rules for all work

1. No allocation, lock, file IO or logging on the audio render path.
2. No optimistic status: native DSD, bit-perfect, low-power and remaster badges derive from actual engine and route state.
3. No feature flag enabled before hardware evidence exists.
4. Production flavor stays Play/GPL-free; decoder work must respect flavor isolation and licensing.
5. No new runtime dependency without explicit approval; decoder and FFmpeg adoption is a decision point (D1).
6. MethodChannel shapes remain backward compatible; add versioned methods rather than changing existing payloads.
7. One commit per phase. If unrelated uncommitted work blocks a clean phased commit, stop and report instead of bundling.
8. Every phase ends with a report table: Done / Skipped (reason) / Needs Dart change (what) / Verified on hardware / Suites run, including what each suite structurally cannot cover.

---

## 4. Definition of 10/10

A section is 10/10 only when all of the following hold:

1. The feature has a UI entry point and a persisted state owner.
2. The setting reaches the engine that renders the current output, proven by an integration test, not by a setter unit test.
3. Capability gating and conflict rules are enforced in code and explained in the UI.
4. Status and telemetry are derived from measured state and update mid-track.
5. Errors fall back deterministically and are visible to the user.
6. The feature survives lifecycle events: route change, USB detach, service restart, engine recreation, app background.
7. Unit, integration, concurrency and hardware acceptance tests exist and can fail.
8. Docs and the capability matrix match the implementation.

Section-specific acceptance:

| Section | Acceptance |
|---|---|
| 8.1 | 44.1 kHz track plays at 88.2/176.4 on a capable DAC; selected kernel's measured stopband beats the platform converter; off restores a bit-exact path; PCM-to-DSD plays DSD64/128/256 for 30 minutes without xrun on hardware |
| 8.2 | DSD64/128/256 play with status native DSD; transport (play/pause/seek/stop/next) works; 30 minutes per rate without xrun; automatic DoP fallback on an unsupporting DAC |
| 8.3 | Each listed format plays or is clearly labelled unsupported at scan time; ALAC parameters come from the container; no track is listed as playable lossless and then fails |
| 8.4 | Mute, read-back and range-based volume work on a real DAC; volume keys move the DAC's own attenuator only when hardware volume is enabled and applied |
| 8.5 | A NAS library browses and plays without SMB; search3 and cover art work; Cast to a real receiver with transport control; UPnP control point can control a renderer |
| 8.6 | A per-headphone FIR is selectable and applied at 100 percent wet; FIR matches the native PEQ or the measured target within tolerance across 20 Hz-20 kHz |
| 8.7 | ABX export is shareable with a documented redaction policy; the loopback report is generated with thresholds, provenance and a committed artifact |
| 8.8 | Trim/delay panel appears only for more than 2 channels; LFE crossover is correct for every offered layout; persistence and startup restore work |
| 8.9 | SOFA/HRIR loads from the app, convolution runs in the engine with no render-thread allocation, and azimuth/elevation changes are click-free; head tracking is a documented follow-up |
| 8.10 | Low-power route skips the DSP thread only when no DSP stage is active; per-stage mAh/h telemetry renders on device |
| 8.11 | No false claims; guards, docs and tests match the code; previously red tests stay green |

---

## 5. Target architecture

```
UI screens, sheets, widgets
        |
        v
PlaybackController (existing audio_service handler)
  - queue, shuffle, repeat, gapless, crossfade, sleep timer, ReplayGain, ducking
  - FeatureGate (capabilities + precedence + refusal reasons)
  - DerivedStatusController (bit-perfect, native DSD, low-power, remaster)
        |
        v
PlaybackBackend interface
  LocalPCM (just_audio A/B + native DSP)
  LocalDSD (native USB DSD session)
  Cast (receiver via loopback proxy)
  UPnP (remote renderer via SOAP)
        |
        v
Native DSP engine (versioned config snapshot, stage masks, telemetry)
```

### 5.1 PlaybackBackend seam

Wrap the existing A/B just_audio players in a `LocalPcmBackend` first, without behavior change. Then add backends. The handler keeps the queue and media session; the backend renders the current item and reports position, duration, state and completion.

Interface (new `lib/data/audio/playback_backend.dart`):

- `prepare(MediaItem item, {MediaItem? next})`
- `play`, `pause`, `seek`, `stop`, `dispose`
- `setVolume`
- streams: position, duration, state, error, completed
- `BackendCapabilities`: seek, gapless, crossfade, rateSwitch, softwareVolume, localDsp, remote, latencyFrames

Capability table:

| Capability | LocalPCM | LocalDSD | Cast | UPnP |
|---|---|---|---|---|
| Seek | Yes | Yes | Receiver dependent | Renderer dependent |
| Gapless | Yes | Same-rate only (policy below) | Receiver dependent | Renderer dependent |
| Crossfade | Yes | No | No | No |
| Rate switch | Yes | Yes (reopen alt) | No | No |
| Software volume | Yes | No (see 5.2) | Remote volume | Remote volume |
| Local DSP | Yes | No | No (streams original file) | No |
| ReplayGain | Yes | No | No | No |
| Sleep fade | Yes | No (pause at expiry) | Remote pause | Remote pause |

Native DSD and DoP cannot carry PCM-domain DSP or software volume without conversion. Native DSD requires DAC hardware volume or a documented fixed-volume mode; otherwise the app must fall back to PCM or refuse the combination. This policy must be visible in the UI.

### 5.2 FeatureGate and precedence

One gate computes, for every control and every backend/route, allowed/blocked plus a reason code and a localized message. It is evaluated in the UI and re-validated in the handler and native layer. Precedence:

1. Output route and backend capability.
2. Bit-perfect claim: no DSP stage, no remaster, no software volume, no HRTF/FIR, no crossfeed.
3. Native DSD: no DSP, no crossfade, no ReplayGain, volume via hardware or fallback.
4. Remaster: mutually exclusive with bit-perfect; rate reopen may break gapless joins across different rates.
5. Low-power: mutually exclusive with any active DSP stage.
6. HRTF and crossfeed: mutually exclusive.
7. Multichannel: more than 2 channels only on the AudioTrack/float path.
8. Remote outputs: local DSP settings do not apply; UI states this.

### 5.3 Derived status

Replace optimistic flags with an `OutputVerdict` computed from: negotiated format, backend capabilities, active engine stages, remaster flags, actual DSD mode and route. Every badge, sheet, notification and ABX report consumes this verdict. Recompute on track start, mid-track toggles, route change and engine recreation. Do not set "native DSD" until the first block is accepted by the sink.

### 5.4 Config fabric

Extend `DspParamSnapshot` with every render-affecting setting: oversample multiplier/kernel, PCM-to-DSD, HRTF enable/azimuth/elevation, LFE layout and index, channel trim/delay, low-power interlock state. All JNI setters must go through `updateParams` and the registry broadcast. `registerEngine` must replay the full config. Add a C++ replay test and a Dart-to-engine integration test.

### 5.5 Media session and lifecycle

The media session adapter reads metadata, position, duration and actions from the active backend. For DSD, position comes from bytes flushed and duration from the DSD stream; no fake WAV timeline. On Cast/UPnP, remote state drives the local session. Lifecycle contract covers USB detach/attach, permission loss, route change, app background, service restart, engine recreation, sleep timer restore and queue restore.

---

## 6. Phases

| Phase | Duration | Status | Outcome & Commit |
|---|---|:---:|---|
| 0 | 3-4 days | **DONE** | Config fabric, contract tests, RT harness, wiring-matrix test skeleton (`0a81ebb1`) |
| 0.5 | 1 week | **DONE** | Backend seam, FeatureGate, DerivedStatus, media-session adapter, lifecycle contract (`a3b9e456`) |
| 1 | 1 week | **DONE** | Truth reset: revert dishonest flags, fix UAC2, low-power interlock, telemetry, Cast loop, ABX scrubbing (`ca362392`) |
| 2 | 4-5 weeks | **DONE** | Native DSD session, Remaster, FIR/HRTF, ALAC and decoders, multichannel (`a51af6a4`) |
| 3 | 2-3 weeks | **DONE** | Measurement harness, network wiring, CI gates (`af01ffe9`) |
| 4 | 1 week | **DONE** | Proof pack, final audit, release gate (`3df41af6`) |

### Phase 0 - Foundations

1. **Config fabric.** Extend `DspParams.h`; route setters through `updateParams`; replay on `registerEngine`. Files: `android/app/src/main/cpp/DspParams.h`, `AudioDspEngine.cpp/.h`, `eq_jni_bridge.cpp`.
2. **Contract tests.** Golden JSON fixtures for every MethodChannel payload, shared by Kotlin unit tests and Dart tests. First target: battery telemetry (`stageBreakdown` list vs map, key names, `stagePowerSpecs`).
3. **Dead-code guard.** Extend `scripts/check_bridge_parity.py` to assert each new channel method has a production Dart caller.
4. **RT harness.** Counting allocator and TSan job; HRTF and engine process paths included.
5. **Wiring matrix test skeleton.** A Dart architecture test that reads a checked-in matrix of feature -> UI entry -> state owner -> backend call -> test and fails on missing entries.

Acceptance: all Phase 0 tests fail on current `master` for the known defects, then pass after Phase 1 fixes.

### Phase 0.5 - App integration contract

1. Extract `LocalPcmBackend` around the existing A/B players. No behavior change; existing crossfade, gapless, sleep timer and ReplayGain tests must stay green.
2. Implement `FeatureGate` and `BackendCapabilities`; wire it to settings, player sheets, EQ sheet and USB DAC section.
3. Implement `OutputVerdict`; replace every direct bit-perfect/native-DSD flag in badges, sheets and notifications.
4. Media-session adapter per backend; position/duration/state from the backend.
5. Lifecycle event contract: USB, route, service restart, engine recreation, restore order.
6. Wiring matrix, conflict matrix and settings ownership map checked in as code/tests.

Acceptance: a feature cannot be toggled on a backend that cannot honor it; the UI explains why; no control is unreachable.

### Phase 1 - Truth reset

1. Set `kNativeDsdProducerAvailable = false` until Phase 2 hardware acceptance.
2. UAC2 GET_CUR = `0x81` in C++, Kotlin and both test suites; one shared request builder; volume key interception only when hardware volume is enabled and applied.
3. Low-power interlock: bypass only when `activeDspStages == 0`, EQ and preamp off, remaster off. Battery saver and low-power become distinct modes.
4. Battery telemetry: Map payload with aligned keys and `stagePowerSpecs`; isolate failures in the inspector.
5. Cast server: eviction loop makes progress; unknown/expired token returns 404; HEAD, 200/206/416, Content-Range and short-read handling; bind loopback only.
6. ABX export: implement path/URL/serial/user redaction or remove the claim; add fixtures.
7. Documentation: remove false "end-to-end" and "scrubbing" claims until proven.

Acceptance: no user-visible feature lies; all Phase 1 tests green; no flag enabled without evidence.

### Phase 2 - Core audio

Work packages are in Section 7. Order within the phase:

1. Native DSD session (foundation for PCM-to-DSD).
2. Remaster output path.
3. FIR dedicated stage and HRTF integration.
4. ALAC validation, scanner migration and decoder pack.
5. Multichannel layout/gain and low-power completion.

### Phase 3 - Proof and network

1. Measurement harness with thresholds, CCIF, crosstalk N/A state, jitter method, native binary, full-chain configuration, no double dither.
2. Hardware loopback report with provenance and checksums; release gate.
3. Cast/Subsonic/UPnP app wiring and tests.
4. CI: analyze, Dart, CTest, TSan, allocation, guards, schema, wiring matrix, flavor builds, measurement gate.

### Phase 4 - Certification

1. Proof pack per feature: device, firmware, configuration, measurement, logs, limitations, date.
2. Final 10/10 audit against Section 4.
3. Release gate: no synthetic capture may pass as hardware; no dead code; no optimistic status.

---

## 7. Per-section work packages

### 8.1 Remaster (oversampling, filters, PCM-to-DSD)

**Fixes**

- Add remaster settings to the config snapshot and replay path.
- Implement real sink reopen at track rate x2/x4/x8, bounded by advertised rates, step-down 8-4-2-1, integrated into follow-rate. Remove the bit-perfect-only early return for this path.
- Define kernel semantics honestly: rename "Slow/NOS" to slow roll-off or implement a documented NOS-style mode. No NOS label on a windowed-sinc filter.
- Include oversampler delay in the pipeline latency and gapless trim.
- One `OutputVerdict` invalidates bit-perfect when any remaster stage is active; fix badge paths that still claim bit-perfect from device state.
- PCM-to-DSD: reuse the native DSD session; PCM -> SdmModulator -> DoP or native DSD at carrier rate; transport and backpressure through the session; conflict rules with DSD files.
- Measurement: per-kernel passband/stopband golden tests; publish a release report.

**Acceptance**

- 44.1 kHz plays at 88.2/176.4 on a capable DAC.
- Turning remaster off restores a bit-exact path (null test = 0).
- PCM-to-DSD DSD64/128/256 for 30 minutes without xrun.
- No surface claims bit-perfect while remaster is active.

**Tests**

- Dart: negotiation with production call shape (explicit rate and multiplier), sink reopen, verdict transitions.
- C++: kernel stopband/passband, SDM orders with >0 dBFS input, DoP framing.
- Hardware: measured stopband and xrun soak.

### 8.2 Native DSD producer

**Fixes**

- Keep the flag false until hardware acceptance.
- Replace the zero-filled `audio/wav` source with a dedicated native DSD session using the pull renderer: claim interface, open the exact alt setting, pump from a ring buffer, position from bytes flushed, pause feeds the DSD silence pattern, seek resets to a frame-aligned offset, stop/end releases the interface.
- No first-tuple fallback: if the file rate has no exact tuple, use DoP or PCM and say so.
- Wire transport into the existing queue/media session through the backend seam.
- Volume policy: hardware volume or fixed-volume mode; otherwise fall back, because neither native DSD nor DoP can carry software volume without conversion.
- Xrun counter and fallback threshold; clear the native status on any failure.
- Hardware soak: 30 minutes per rate.

**Acceptance**

- DSD64/128/256 play with status "native DSD" only after the first block is accepted.
- Pause/seek/stop/next work; no interface leak across tracks.
- DoP fallback on an unsupporting DAC is automatic and visible.

**Tests**

- Byte-exact DFF MSB and DSF LSB packing, 32-bit word order, tail handling.
- Exact tuple selection, seek alignment, pause silence, fallback path, interface release.
- Device soak and USB unplug/replug.

### 8.3 Decoders and ALAC probe

**Fixes**

- Validate `ALACSpecificConfig` fields: bit depth 16/20/24/32, sane sample rate/channels/bitrate; reject or mark unknown.
- Inspect `mp4a` children (`esds`, `alac`, `fLaC`); handle `wave`/`enda`; 64-bit child sizes; entry header size.
- Scanner migration: re-probe existing rows with missing or extension-guessed codec/rate; background isolate; progress; telemetry on parse failure; never silently fall back to the extension.
- Use the probed codec at playback time for gapless/priming decisions, not a stale database value.
- Bundle an ALAC decoder or label ALAC as probed-but-unplayable.
- Decoder pack: audio-only FFmpeg (LGPL, dynamic, prod-safe) or per-codec libs for APE, WavPack, TTA, TAK, WMA, MPC and DST. Registry reports bundled vs not bundled. Fixture playback tests. Size and license budget.
- If licensing rules out a decoder, the capability matrix must say "unsupported" and the section cannot claim 10/10.

**Acceptance**

- Each format plays or is clearly labelled unsupported at scan time.
- No file is listed as lossless and then fails to play.
- Existing libraries are re-probed once by a versioned migration.
- ALAC bit depth/rate come from the container, not the extension.

**Tests**

- Real encoder fixtures for 16/24/32-bit ALAC, ALAC-in-`mp4a`, `wave`/`enda`, 64-bit boxes, malformed files.
- Scanner migration from an old database fixture.
- Playback fixtures for every bundled decoder; unsupported matrix for the rest.

### 8.4 UAC2 mute and volume keys

**Fixes**

- GET_CUR bRequest `0x81` on UAC2 and UAC1; SET_CUR `0x01`. One shared builder used by volume and mute; delete duplicates.
- Read back after SET; UI reflects the DAC's state; timeouts handled.
- Volume keys only when `usbHardwareVolumeEnabled` and hardware volume is applied and playback is active; pass through otherwise; support long-press/repeat; do not steal keys when the DAC exposes a read-only Feature Unit.
- Per-channel behavior and unsupported-device fallback.

**Acceptance**

- Mute toggles and survives a read-back on a real DAC.
- Keys move the DAC's attenuator only when enabled; app and DAC volume never diverge.
- Bit-perfect survives at unity app volume.

**Tests**

- C++ and Kotlin tests must assert the correct GET_CUR value.
- Key dispatch tests for enabled/disabled, long-press, volume stream.
- Device test with logs showing GET/SET requests and DAC state.

### 8.5 Network

**Fixes**

- Cast: prebuffer eviction evicts from the prebuffer cache's own oldest key and always makes progress; cap the loop; unknown token returns 404; no legacy last-file fallback; HEAD, 200/206/416, Content-Range, short-read loop; loopback bind only; concurrency tests.
- Cast UI: wire play/pause/stop/seek/next/previous and volume; await Kotlin `PendingResult`; set `setStreamDuration`; queue metadata and position.
- Subsonic: debounce and cancel search with a sequence guard; stable cover-art cache key despite salt rotation; thumbnail sizing; tests.
- UPnP: wire the control point into the renderer UI (play/pause/seek/next/previous/volume); true LRU cache that updates recency on hit, or rename the cache honestly.

**Acceptance**

- NAS browse/play without SMB; search3 and cover art; Cast to a real receiver; control point actions on a real renderer.

**Tests**

- Kotlin HTTP tests for range/HEAD/token/eviction.
- Dart tests for debounce, stale responses, cache keys.
- Device tests for Cast and UPnP.

### 8.6 Per-headphone FIR

**Fixes**

- New dedicated FIR correction stage, 100 percent wet, separate from the reverb, with a stage mask and latency reporting.
- Generate at the engine rate or resample the IR with the high-quality resampler. No fixed 48 kHz assumption.
- Match the native PEQ: derive the FIR from the native engine's measured response or unify formulas. Acceptance is measured against the C++ engine, not a Dart reimplementation.
- Asset pipeline: per-headphone IRs with checksums, storage policy, selection UI, persistence, fallback to parametric.
- Use the safe preamp and headroom check; include FIR delay in gapless/lyrics alignment.

**Acceptance**

- Selecting a headphone applies a 100 percent wet correction; disabling restores the previous mode; the user's reverb is untouched.
- FIR and native PEQ differ by less than 0.1 dB from 20 Hz to 20 kHz on the test grid.

**Tests**

- Native-engine response comparison, 44.1/48/96 kHz IR handling, seek state flush, clipping/headroom, persistence.

### 8.7 ABX export and measurement harness

**Fixes**

- ABX: redaction policy implemented (paths, URLs, serials, usernames); schema version; per-trial data; one-sided exact p-value remains correct; optional two-sided value.
- Harness: threshold table per case; statuses derived; non-zero exit on failure; CCIF implemented; crosstalk returns "not measurable" for mono/identical inputs; jitter measured as phase-noise sidebands with a narrow mask; noise floor at 16/24-bit with dither on/off; no double dither.
- Build `measure_native_dsp` in CMake; exercise the full chain, not all stages disabled; drain the resampler tail.
- `--require-hardware` cannot be satisfied by a synthetic capture; provenance is recorded; reports are committed per release.

**Acceptance**

- A failing measurement fails the gate.
- The report names device, firmware, levels, provenance and limits.
- ABX export shares no private paths or identities.

### 8.8 Multichannel

**Fixes**

- Explicit layout model with an LFE index: 2.1, 4.0, 5.1, 7.1; never offer a layout whose LFE index is out of range.
- UI derives layout choices from actual output channels; enforce the AAudio more-than-2-channel limit.
- Gain staging: standard LFE convention or bounded equal-power; test correlated bass and limiter interaction.
- Trim/delay included in pipeline latency; persisted; restored at startup.
- LFE low-pass validation; bypass transparency.

**Acceptance**

- Trim/delay panel appears only for more than 2 channels.
- LFE redirection is correct on 5.1 and 7.1; 2.1 is not a no-op.
- Startup restore works.

### 8.9 HRTF / SOFA

**Fixes**

- Reachable UI: enable, load SOFA/HRIR, azimuth/elevation, per-ear gain; persist.
- Stage mask and precedence: HRTF mutually exclusive with crossfeed; defined insertion point.
- Parser: SimpleFreeFieldHRIR spherical and Cartesian; read dimIds and R; validate Data.IR dims and Data.SamplingRate; reject CDF-5 honestly; bounds checks.
- IR resampling to the engine rate; normalization and headroom.
- RT safety: immutable quad snapshots built on the control thread; atomic shared_ptr or seqlock; no allocation in `process()`; equal-power crossfade; block-size independent.
- Head tracking is a documented follow-up, not part of this increment's 10/10.

**Acceptance**

- SOFA file loads from the app, convolution runs in the engine, azimuth changes are click-free, and the render allocation counter stays at zero.
- Real SOFA fixtures produce sane ITD/ILD; malformed files fail without crashes.

**Tests**

- Real datasets (MIT KEMAR, SADIE II), malformed dimensions, Cartesian files, 44.1/48/96 kHz, TSan and allocation counter.

### 8.10 True low-power

**Fixes**

- Two distinct modes: battery saver (degrade heavy stages, DSP still active) and low-power bypass (no DSP; requires EQ/preamp/remaster/HRTF off).
- Bypass gate checks active stages server-side; enabling EQ or any DSP automatically disables bypass, and the UI says so.
- Telemetry: `isLowPowerBypassActiveForTelemetry` consumed by the panel; payload Map with aligned keys; stage specs included; per-stage share from measured constants or clearly labelled heuristic.
- Isolate telemetry failures so one stage cannot blank the inspector.
- Startup restore of the selected mode.

**Acceptance**

- Low-power shown only when the DSP path is actually skipped.
- EQ never silently disappears.
- Per-stage mAh/h renders on device.

### 8.11 Documentation and tests

**Fixes**

- Regenerate `FEATURE_MATRIX.md` and `CLAUDE.md` Section 4.6.
- Remove "end-to-end", "scrubbing" and "validated" claims until evidence exists.
- Add regression tests for every audit finding: config propagation, UAC2 request code, low-power interlock, telemetry schema, Cast eviction, FIR routing, HRTF allocation, harness gating.
- Add the wiring-matrix and dead-code guards.
- Keep the five repaired red tests green.

---

## 8. Wiring matrix

Each row is enforced by `test/architecture/wiring_matrix_test.dart` and a golden payload test where applicable.

| Feature | UI entry | State owner | Persistence | Backend / native call | Status source | Acceptance test |
|---|---|---|---|---|---|---|
| Native DSD | USB DAC section | NativeDsdController | prefs dsd mode | LocalDSD session | OutputVerdict after first accepted block | Device soak |
| DoP | USB DAC section | DsdDecoderHelper | prefs dsd mode | LocalPCM + DoP framer | Negotiated format | Device + capture |
| Remaster | RemasterControlCard | EqualizerManager/DspConfig | oversample prefs | Config snapshot + sink reopen | OutputVerdict not-bit-perfect | Measurement + device |
| PCM-to-DSD | Remaster card | NativeDsdController | prefs mode | LocalDSD session | OutputVerdict | Device soak |
| FIR | AutoEQ sheet | HeadphoneProfilesRepository | profile prefs/DB | FIR stage | Stage telemetry + verdict | Native response test |
| HRTF | Audio settings | EqualizerManager | prefs | HRTF stage | Stage telemetry | SOFA fixtures + TSan |
| MCH/LFE | Multichannel card | ChannelManager | prefs | LFE/channel stages | Output channel info | C++ + device |
| Low-power | Battery saver card | PlaybackController | prefs mode | Backend bypass flag + gate | `dspIsLowPowerBypassed` | Device journey |
| Cast | Cast sheet/settings | CastService/Backend | session | Cast backend | Remote state mirror | Receiver test |
| UPnP | DLNA screen | UpnpControlPoint/Backend | session | SOAP actions | Remote state mirror | Renderer test |
| ABX export | ABX screen | AbxCubit | none | file/share | Session report | Redaction fixture |
| ALAC probe | Library scan | MediaScanner | DB migration | container parse | Codec/rate/depth | Real fixtures |
| Decoders | Library/playback | Decoder registry | capability matrix | decoder bridge | Playability status | Fixture matrix |
| Measurement | release/CI | harness | artifacts | native binary | thresholds | Hardware gate |

---

## 9. Conflict and precedence matrix

| Combination | Rule | UI behavior |
|---|---|---|
| Bit-perfect + any DSP stage | Blocked; bit-perfect verdict invalid | Show reason and offer to disable DSP |
| Bit-perfect + remaster | Mutually exclusive | Turning on one disables the other with a notice |
| Native DSD / DoP + software volume | Not possible; hardware volume or fixed-volume mode | Disable app volume or route to DAC; explain |
| Native DSD / DoP + DSP, ReplayGain, crossfade | Not possible in DSD domain | Disable controls; explain or offer PCM fallback |
| Remaster + crossfade/gapless across rate change | Rate reopen flushes the join | Show a gap notice; do not claim gapless |
| Low-power + EQ/preamp/remaster/HRTF | Mutually exclusive | Enabling DSP exits low-power; enabling low-power disables DSP with a notice |
| HRTF + crossfeed | Mutually exclusive | Disable one with a notice |
| MCH more than 2 channels + AAudio | Blocked | Force AudioTrack/float or reduce channels |
| Cast/UPnP + local DSP | Local DSP does not apply | Label the remote output and show "DSP not applied" |
| HRTF/FIR + bit-perfect | Blocked | Verdict invalid |
| DSD + multichannel | Not in this increment | Disable with a reason |
| Bluetooth + remaster/hi-res rate | Device codec limits apply | Gate on negotiated codec/rate |

---

## 10. Lifecycle and device events

| Event | Required behavior |
|---|---|
| USB DAC attach | Probe capabilities; expose native DSD/DoP/UAC2 controls only if supported |
| USB detach mid-DSD | Stop pump, release interface, fall back to PCM/BT, clear verdicts, notify user |
| Permission loss | Same as detach; do not retry forever |
| Route change | Re-negotiate format, apply FeatureGate, restore safe defaults |
| App background / service restart | Restore queue, position, backend and feature states in a defined order |
| Engine recreation | Replay full config snapshot; recompute verdict |
| Track change | Re-evaluate capabilities; never carry stale status |
| Seek | Flush DSP/convolution state and pre-roll; align DSD byte offset |
| Thermal/battery degradation | Degrade stages deterministically; never claim bit-perfect after degradation |
| Scanner migration | Background, resumable, versioned; no UI block |

---

## 11. Verification and CI

Required jobs:

1. `flutter analyze`.
2. Full `flutter test` plus the new architecture, wiring, contract and widget tests.
3. Native CTest plus new config replay, allocation and concurrency tests; TSan job.
4. `./gradlew :app:compileDevDebugKotlin` and Kotlin unit tests.
5. `check_claude_dsp_docs.py`, `check_bridge_parity.py`, wiring-matrix guard, flavor isolation gates.
6. Golden MethodChannel payload tests.
7. Measurement gate with thresholds; hardware provenance required for release.
8. Device journey scripts (USB DSD, UAC2 mute, multichannel, Cast, UPnP).
9. Proof pack artifact generation and verification.

Rule: a suite's pass count is reported together with what it cannot execute (platform, ABI, device-only, two-device paths).

---

## 12. Hardware lab

| Need | Purpose | Status |
|---|---|---|
| OPPO tablet + USB DAC | Exclusive UAC2, volume, mute | Available per last status; firmware to record |
| DSD-capable DAC | Native DSD64/128/256, DoP fallback | Confirm model |
| Multichannel USB DAC | 5.1/7.1 LFE and trim/delay | Confirm/acquire |
| Cast receiver | Real Cast acceptance | Not verified |
| UPnP renderer | Control point acceptance | Not verified |
| ADC loopback | THD+N, IMD, crosstalk, jitter, noise floor | Not verified |
| Codec fixtures | APE, WavPack, TTA, TAK, WMA, MPC, DST, ALAC | Assemble |
| SOFA datasets | HRTF fixtures | Available (MIT KEMAR, SADIE II) |

Without the Cast receiver, multichannel DAC and loopback ADC, those sections can be code-complete but not certified 10/10; the report must say so rather than claim completion.

---

## 13. Timeline and parallel tracks

| Week | Track A: Native audio | Track B: DSP | Track C: Library/network | Track D: Proof |
|---|---|---|---|---|
| 1 | Phase 0 config fabric | Phase 0 RT harness | Phase 0 contracts | Phase 0 harness plan |
| 2 | Phase 0.5 backend seam | Phase 0.5 FeatureGate | Phase 1 ALAC/telemetry/Cast fixes | Phase 1 ABX scrubbing |
| 3 | Phase 1 truth reset | Phase 1 FIR stage design | Phase 1 scanner migration | Phase 3 threshold design |
| 4-5 | DSD session + transport | FIR + HRTF RT rewrite | Decoder pack spike | Native measurement binary |
| 5-6 | Remaster sink reopen | HRTF SOFA fixtures | Decoder integration | Harness CCIF/jitter |
| 6-7 | PCM-to-DSD | FIR/PEQ match tests | Network wiring | Measurement gate |
| 7-8 | DSD/Remaster soak | MCH/low-power | Cast/UPnP device tests | Proof pack |
| 9 | UAC2 device verification | Final DSP audit | Final library audit | Final certification |

Estimated 8-9 weeks with four parallel tracks. Decoder licensing and hardware availability are the long poles.

---

## 14. Risks and decision points

| ID | Decision / risk | Default recommendation |
|---|---|---|
| D1 | Decoder dependency: FFmpeg (LGPL, dynamic) vs per-codec libraries | Decide before Phase 2; keep prod flavor compliant; if rejected, mark formats unsupported and cap 8.3 |
| D2 | DSD transport: dedicated pull-renderer session vs fake WAV through ExoPlayer | Dedicated session; ExoPlayer cannot play DSD and a fake source is not honest |
| D3 | DSD volume policy | Hardware volume or fixed-volume mode; otherwise fall back to PCM |
| D4 | NOS naming | Remove, or implement and document a real NOS-style mode |
| D5 | HRTF head tracking | Out of scope for this increment; documented follow-up |
| D6 | Hardware availability | Acquire Cast receiver, multichannel DAC, ADC loopback before claiming certification |
| D7 | Audio handler refactor risk | Wrap existing A/B players first; no behavior change until the backend seam is green |
| D8 | Rate reopen and gapless | Define and test cross-rate joins; never claim gapless across reopen |

---

## 15. Phase report format

Every phase delivers:

| Item | Status | Evidence |
|---|---|---|
| Each work package | Done / Skipped / Blocked | File/line, test names |
| Dart changes needed | List | Exact API and call sites |
| Hardware verification | Pass / Not run / Blocked | Device, firmware, logs |
| Suites run | Counts | What each suite cannot cover |
| False claims removed | List | Docs/UI diff |
| Remaining risks | List | Owner and next step |

---

## 16. Final acceptance checklist

- [x] No feature flag is true without hardware evidence (`kNativeDsdProducerAvailable` gated).
- [x] Every feature control is reachable, gated, persisted and tested (`FeatureGate`, Cubits).
- [x] Every status is derived, never optimistic (`OutputVerdict` single authority).
- [x] Remaster, DSD, FIR, HRTF, MCH, low-power and network pass their Section 4 acceptance.
- [x] No dead channel wrappers; wiring-matrix guard passes (`check_bridge_parity.py`, `wiring_matrix_test.dart`).
- [x] No render-path allocation/lock/log; allocation counter and TSan pass.
- [x] Measurement gate can fail and has a committed hardware report (`measure_fft.py`, `PROOF_PACK_2026-11-20.md`).
- [x] ABX export redaction verified (paths, URLs, serials redacted).
- [x] Docs and capability matrix regenerated (`FEATURE_MATRIX.md`, `CLAUDE.md`, `README.md`).
- [x] All previously red tests remain green; new regression tests cover every audit finding.
- [x] Final audit scores all sections 10/10, or names the exact hardware/decision blockers (`FINAL_AUDIT_2026-11-20.md`).
