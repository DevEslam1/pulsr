# Poweramp Parity Implementation Plan (for an autonomous coding agent)

> **Audience:** an autonomous coding agent (referred to below as *the implementer*, e.g. Gemini 3.8).
> **Source of truth for the gap list:** `docs/POWERAMP_COMPARISON.md` §12–§13.
> **Scope:** implement every area where Poweramp is ahead **except the UI ecosystem** (third-party
> skins and Milkdrop visualizations — explicitly out of scope). Minimal settings toggles / entry
> points required to activate a feature are in scope; new visual skinning is not.
> **Repo:** `pulsr` (Flutter + Dart + Drift + native Android Kotlin/C++), package name `pulsr`.

---

## Implementation status (executed pass)

| Task | Status | Evidence |
|---|---|---|
| T2 Follow-Track sample-rate | ✅ DONE | `SettingsState.followTrackSampleRate`, `PlayerCubit._maybeFollowTrackSampleRate` (de-duped), settings toggle. |
| T3 No-Resample / strict bit-perfect | ✅ DONE | `strictBitPerfect` + conflict rules (`AudioConflicts.strictBitPerfectBlockedReason/ActiveReason`), conflict card. |
| T4 Native/DoP DSD | ✅ DONE | `DsdOutputMode` + `HiResDacPlugin.getDopCapabilities` (honest USB probe) + `DopEncoder` routing; defaults to PCM. |
| T5 Wider envelope | ✅ DONE | Capability-filtered rate pills (up to 768k), 32-bit depth; 705.6k validated. 8.24 remains unsupported by native. |
| T7 64-band parametric EQ | ✅ DONE | `EqualizerManager.eqBandCount` (10/32/64) + `custom64Frequencies` + migration; 10/32/64 toggle. |
| T9 Format breadth | ✅ DONE (honest) | Three-tier `AudioFormats`; webm/aiff added as decodable; APE/WMA/TTA/TAK/WV/MPC/mods recognized-but-not-indexed pending a native FFmpeg bridge. |
| T10 CUE playback | ✅ DONE | Schema v10 (`cueStartMs/cueEndMs/cueFile`), `expandCueSheets`, container hiding, cue start/end playback boundaries. |
| T11 Internet radio | ✅ DONE | `RadioStation`/`RadioStationStore`, HTTP/HTTPS stream playback via just_audio, Radio screen + Home entry. |
| T12 PLS/WPL | ✅ DONE | PLS/WPL parsers + exporters, format picker, file-picker extensions. |
| T1 USB Exclusive driver | ⛔ PENDING (native) | Requires a UAC2 exclusive driver + hardware-volume control in native code (see §4.1). Not shipped blind. |
| T6 DVC-equivalent | ⛔ PENDING (native) | Requires a single native direct-gain stage integrated with ducking/crossfade/ReplayGain; unsafe to ship without device validation. |
| T8 System-wide EQ | ⛔ BLOCKED (platform) | Android restricts session-0 global `AudioEffect` to privileged apps. |
| T13 Chromecast | ⛔ BLOCKED (dependency) | Needs Google Cast SDK + registered receiver app id. |
| Skins / Milkdrop | — | Out of scope (UI). |

**Verification of this pass:** `flutter analyze` clean; `flutter test` → 862 passing; native
`./gradlew :app:compileDevDebugKotlin` → BUILD SUCCESSFUL.

---

## 0. Mission & ground rules

**Goal:** close the audiophile-output, format, CUE, radio, cast and EQ gaps vs Poweramp v3
(stable ~build 1024, beta 1028) without regressing the existing 801-passing test suite.

**Non-negotiable ground rules for the implementer:**

1. **Honesty over claims.** Never report a capability the device/native layer does not actually
   perform. If hardware refuses, surface the true reason (follow the existing
   `setBitPerfectMode` fallback pattern in `lib/domain/services/hires_audio_service.dart:179`).
2. **Keep the build green.** After every workstream run:
   `flutter analyze` (must be clean) and `flutter test --no-pub` (must stay ≥ 801 passing).
   Native changes must compile: `flutter build apk --debug` (or `./gradlew :app:compileDebugKotlin`).
3. **No Dart-side fabrications.** Do not add UI copy or badges for features that are stubs.
4. **Migrations are guarded.** New Drift columns/tables must be added with an idempotent
   `hasColumn(...)` guard, matching `lib/data/db/app_database.dart:121`.
5. **Regenerate code after schema/freezed changes:**
   `dart run build_runner build --delete-conflicting-outputs`.
6. **Style:** no comments unless the file already uses them; match neighboring code; guard
   `context.mounted` after awaits; dispose controllers/subscriptions.
7. **One workstream per commit**, Conventional Commits style (`feat(audio): …`). Never commit
   secrets. Do not push unless instructed.
8. **Do not touch** the third_party/just_audio fork unless a task explicitly says so; changes
   there must be minimal and documented in `pubspec.yaml` comments.

**Definition of done for the whole plan:** every task marked **DONE** in §13 has passing tests
and honest capability surface; tasks marked **BLOCKED** have a written technical justification.

---

## 1. Current-state map (verified extension points)

Use these instead of re-discovering:

| Area | File | Notes |
|---|---|---|
| Native hi-res/DAC channel | `android/app/src/main/kotlin/com/pulsr/music/HiResDacPlugin.kt` | Methods: `getAudioOutputInfo`, `isBitPerfectSupported`, `setBitPerfectMode(_Detailed)`, `getBluetoothCodecInfo`, BT codec setters, `setOutputDevice`, `clearOutputDevice`, `openOutputSwitcher`, `getUsbDacCapabilities`, `getDirectCapabilities`, `setTargetOutputFormat`/`configureTargetAudio` (`{sampleRate, bitDepth}`). |
| Dart hi-res facade | `lib/domain/services/hires_audio_service.dart` | `setTargetOutputFormat` already validates rates `{0,44100,48000,88200,96000,176400,192000,352800,384000,768000}` and depths `{0,16,24,32}` (lines 274–305). `selectOutputDevice` returns `requiresSystemPicker` on retail builds. |
| DSP/effects channel | `lib/data/audio/audio_effects_channel.dart`, native `AudioEffectsPlugin.kt` | `setNativeEqBandCount`, `setNativeEqBandsBulk`, `setEqBands`, `setPreamp`, `decodeDsd`, `setDspPreference`, `reapplyToSession`, etc. |
| EQ manager | `lib/data/audio/equalizer_manager.dart` | `is32BandMode` bool + `customFrequencies` / `custom32Frequencies`; `set32BandMode:716` pushes `setNativeEqBandCount(freqs.length)`. Native accepts arbitrary band counts → 64-band is feasible. |
| Native DSP engine | `android/app/src/main/cpp/` (`libpulsr_dsp`) | Receives PCM; has gain-curve, float output hooks via just_audio fork. |
| DSD | `lib/data/audio/dsd_decoder_helper.dart`, native `DsdDecoder.cpp`, channel `decodeDsd` | Currently decodes DSF/DFF → PCM. |
| DoP | `lib/data/audio/dop_encoder.dart` | `encodeToDopPcm24` / `encodeToDopPcm32` implemented but **no caller**. |
| Audio source resolution | `lib/data/audio/audio_handler.dart` `_resolveAudioSource` (~line 1840–1900) | Routes `dsf`/`dff`; where DoP/format routing must be added. |
| MQA/format decoder | `lib/data/audio/format_aware_decoder.dart`, `mqa_decoder_helper.dart` | `decodeForFormat` is now called from `_resolveAudioSource` for local flac/wav. |
| DB schema | `lib/data/db/tables.dart`, `lib/data/db/app_database.dart` | `schemaVersion => 9`; `songs` table columns at `tables.dart:14`. |
| Scanner | `lib/data/scanner/media_scanner_service.dart` | Filters by `AudioFormats.isSupportedExtension`. |
| Formats | `lib/core/constants/audio_formats.dart` | `supportedExtensions` set; `unsupportedExtensions = {wma}`. |
| CUE | `lib/core/utils/cue_parser.dart`, `lib/domain/models/chapter_info.dart` | Fully implemented parser + model, **zero consumers**. Tests: `test/cue_parser_test.dart`. |
| Playlist I/O | `lib/domain/usecases/playlist_io_usecases.dart` | M3U/M3U8 only; export writes `.m3u`. |
| Player cubit/state | `lib/features/player/cubit/player_cubit.dart`, `player_state.dart` (freezed) | Central UI state. |
| Settings cubit/state | `lib/features/settings/cubit/settings_cubit.dart`, `settings_state.dart` (freezed) | Add prefs + toggles here. |
| Prefs keys | `lib/core/constants/prefs_keys.dart` | Add new keys here. |

---

## 2. Scope matrix

| # | Poweramp advantage | Task | Feasibility | Priority |
|---|---|---|---|---|
| A | USB Exclusive driver + hardware volume | **T1** | Native, **High effort** | P0 |
| B | Follow-Track sample-rate switching | **T2** | High (native hook exists) | P0 |
| C | No-Resample / Perfect bit-perfect | **T3** | Medium (extends existing bit-perfect) | P0 |
| D | Native + DoP DSD64–1024 | **T4** | Medium (DoP encoder exists) | P0 |
| E | Wider envelope (384/768k, 8.24/32/float) | **T5** | High (Dart already validates) | P0 |
| F | DVC (Direct Volume Control) | **T6** | Native, **High effort** | P1 |
| G | 64-band parametric EQ | **T7** | High | P1 |
| H | System-wide EQ (other apps) | **T8** | **Blocked on modern Android** (see §4.8) | — |
| I | Format breadth (APE/WMA/TTA/TAK/WV/webm/mods) | **T9** | Medium via decoder plugin (see §4.9) | P1 |
| J | CUE sheet playback | **T10** | High | P1 |
| K | HTTP radio / streams | **T11** | High | P1 |
| L | PLS/WPL playlist import/export | **T12** | High | P1 |
| M | Chromecast | **T13** | **Blocked** (needs Cast SDK/app id) | — |
| — | Skins + Milkdrop visualizations | — | **Out of scope (UI)** | — |

---

## 3. Execution order (suggested)

Independent, low-risk, Dart-only first; native/hardware last:

```
Wave 1  T12 (PLS/WPL)   T10 (CUE)   T7 (64-band EQ)   T5 (envelope)
Wave 2  T11 (radio)     T2 (follow-track)  T3 (no-resample)
Wave 3  T4 (DoP DSD)    T9 (formats)  T1 (USB exclusive)
Wave 4  T6 (DVC)
Docs    T8/T13 blocked write-ups
```

Parallelisation rule: tasks that touch `audio_handler.dart` (T2,T3,T4,T6,T9) must run
**sequentially** or be owned by one agent at a time to avoid merge conflicts. T7 and T12 are
isolated; T10 and T11 add files but both touch `app_router.dart` (serialize those two).

---

## 4. Workstream task details

### T1 — USB Exclusive driver + hardware volume (P0, native, high effort)

**Why:** Poweramp's USB Exclusive bypasses AudioFlinger entirely; Pulsr only offers the system
picker (`hires_audio_service.dart:217`, `requiresSystemPicker`).

**Files:**
- `android/app/src/main/kotlin/com/pulsr/music/HiResDacPlugin.kt` (+ a new
  `android/app/src/main/kotlin/com/pulsr/music/usb/UsbExclusiveDriver.kt`)
- `lib/domain/services/hires_audio_service.dart`
- `lib/features/settings/presentation/widgets/audio_sound_section.dart`
- Native C++ only if a custom UAC2 write path is required.

**Steps:**
1. Add an `AudioDeviceCallback`/`UsbManager` path that claims the USB audio interface via
   `UsbManager.openDevice()` + `claimInterface()` (Android `android.hardware.usb`), then opens an
   `AudioTrack` with `AudioAttributes.USAGE_MEDIA` and a **direct** output path
   (`AudioTrack.Builder().setPerformanceMode(PERFORMANCE_MODE_LOW_LATENCY)` /
   `AudioFormat` at the DAC's native rate) **or** writes raw UAC2 frames to the bulk endpoint.
   *Minimum viable parity:* exclusive `AudioTrack` on the USB device + hardware volume via the
   USB Audio Class volume control rather than a full custom firmware path.
2. Add channel methods on `HiResDacPlugin`:
   - `isUsbExclusiveSupported` → `Bool`
   - `setUsbExclusiveMode` `{enabled: Bool}` → `Map {success, reason}`
   - `setHardwareVolume` `{volume: Int}` → `Bool`
   - event `usbExclusiveState` on the `hiresDacEvents` stream.
3. Add Dart facade methods + a per-output setting in `audio_sound_section.dart` (toggle only,
   with a truthful "unsupported on this device" state when the DAC lacks exclusive access).
4. When exclusive is active, **disable** Android `DspPipeline` gain stages that would resample
   (document the conflict like `AudioConflicts` in `lib/core/constants/audio_feature_info.dart`).

**Native protocol contract (emit on `hires_dac_events`):**
`{ "usbExclusive": true|false, "hardwareVolumeSupported": true|false, "reason": "..." }`

**Tests:** Kotlin unit test for capability detection with a mocked `UsbManager`; Dart test for
the fallback/state machine.
**Acceptance:** With a UAC2 DAC, audio is routed via the exclusive path and the sample rate is the
track's native rate; without a DAC the toggle is disabled and honestly labeled.

---

### T2 — Follow-Track sample-rate switching (P0)

**Why:** Poweramp reconfigures output to the current track's rate. Pulsr exposes only a manual
target rate.

**Files:** `lib/features/player/cubit/player_cubit.dart`, `lib/data/audio/audio_handler.dart`
(`_notifyTrackChanged`), `lib/domain/services/hires_audio_service.dart`,
`lib/features/settings/cubit/settings_cubit.dart` + `settings_state.dart`, `audio_sound_section.dart`.

**Steps:**
1. Add pref `followTrackSampleRate` (`PrefsKeys`) + state field + setter.
2. On track change, if enabled and `song.sampleRate != null`, call
   `HiResAudioService.setTargetOutputFormat(sampleRate: song.sampleRate!, bitDepth: 0)` only when
   the rate changed since the last track (avoid redundant native churn).
3. Skip on Bluetooth unless the codec matches (mirror `setBluetoothSampleRate`).
4. Honor `bitPerfectOutput`: when bit-perfect is active, follow-track is the mechanism that keeps
   it bit-accurate.
5. Add a settings toggle "Follow track sample rate".

**Tests:** unit test that `player_cubit` invokes the service with the song's rate and de-dupes.
**Acceptance:** Playing 44.1k then 96k tracks triggers exactly one native format change each.

---

### T3 — No-Resample / Perfect bit-perfect (P0)

**Why:** Poweramp "Perfect Bit Perfect" disables DSP/gain/crossfade and prevents Android
resampling.

**Files:** `HiResDacPlugin.kt` (`setBitPerfectMode` path), `hires_audio_service.dart`,
`lib/core/constants/audio_feature_info.dart` (`AudioConflicts`),
`lib/features/settings/cubit/settings_cubit.dart`, `audio_sound_section.dart`.

**Steps:**
1. Extend the existing bit-perfect implementation to a **strict** mode that additionally:
   routes at the exact file rate (via T2), sets the native output to bypass any resampler, and
   forces `bypassDspOnBitPerfect` on.
2. Surface a conflict rule when strict bit-perfect is on: disable EQ/ReplayGain/effects/crossfade
   (extend `AudioConflicts` and the settings UI conflict card pattern in
   `lib/features/settings/presentation/widgets/settings_conflict_card.dart`).
3. Make the toggle honest: if native reports it cannot avoid resampling, show that reason.

**Tests:** conflict-rule unit tests; state test that enabling strict disables the DSP snapshot.
**Acceptance:** With a capable path, DSP stages are bypassed and the UI reflects it; otherwise the
reason string is shown.

---

### T4 — Native + DoP DSD output (P0)

**Why:** Pulsr decodes DSD to PCM today; `DopEncoder` is dormant.

**Files:** `lib/data/audio/audio_handler.dart` (`_resolveAudioSource`), `dop_encoder.dart`,
`dsd_decoder_helper.dart`, `lib/domain/models/audio_quality_info.dart`,
`lib/core/constants/audio_feature_info.dart`, `settings_cubit.dart`/`settings_state.dart`.

**Steps:**
1. Add pref `dsdOutputMode` enum `{ pcm, dop }` (default `pcm` for safety) + state + setter.
2. In `_resolveAudioSource`, when the file is `dsf`/`dff` **and** `dsdOutputMode == dop` **and**
   the output device advertises DoP/native-DSD (probe via a new `HiResDacPlugin.isDopSupported`),
   encode using `DopEncoder.encodeToDopPcm24/32` and feed the resulting PCM at
   `dsdRate / 16` (e.g. DSD64 = 2.8224 MHz → DoP PCM = 176.4 kHz) with the 0x05/0xFA markers.
3. If unsupported, fall back to the existing PCM decode and record the reason in
   `AudioQualityInfo` / `AudioFeatureRegistry.dsdNative`.
4. Add channel method `getDopCapabilities` → `{ dsd64, dsd128, dsd256, dop, native }`.

**Tests:** `dop_encoder_test.dart` (already? verify) covering markers and channel interleave;
routing test that selects DoP only when capability + setting align.
**Acceptance:** On a DoP-capable DAC, DSD plays without PCM conversion; otherwise honest PCM.

---

### T5 — Wider output envelope (P0, mostly wired)

**Why:** Poweramp exposes 8.24/32/float; Pulsr validates up to 768k/32 already but the UI may not
surface the full set and `8.24` is absent.

**Files:** `hires_audio_service.dart`, `audio_quality_sheet.dart`,
`lib/features/player/presentation/widgets/audio_quality_sheet.dart`, `audio_sound_section.dart`.

**Steps:**
1. Confirm `setTargetOutputFormat` accepts and forwards `768000`; expose 352.8/384/705.6/768 kHz
   in the sample-rate pills *only when* `getDirectCapabilities`/`AudioOutputInfo` advertises them.
2. Add 32-bit and (if native supports) 8.24 packed depth; extend the native validator in
   `HiResDacPlugin.setTargetOutputFormat` accordingly.
3. Ensure `AudioQualityInfo`/badge reports the actual negotiated format.

**Tests:** Dart tests for validation boundaries; widget test that unsupported rates don't render.
**Acceptance:** Only device-supported rates/depths are selectable; no fake options.

---

### T6 — DVC-equivalent direct volume (P1, native, high effort)

**Why:** Poweramp's DVC gives low-distortion gain with deep bass. Pulsr uses a Dart mixer +
HAL volume boost.

**Files:** native gain stage (C++ `libpulsr_dsp` / `AudioEffectsPlugin.kt`), `audio_handler.dart`
(`_calculateReplayGainVolume`, `PlaybackVolumeController`), `settings_cubit.dart`.

**Steps:**
1. Implement a "Direct volume" mode that pins the system media volume and applies gain in the
   native DSP float path (single gain stage, headroom compensated) instead of scaling via
   AudioTrack system volume.
2. Add conflict rules: direct volume excludes system volume ducking / long-press volume changes;
   coordinate with `DuckingController`.
3. Honest fallback to the current path when the native float pipeline is unavailable.

**Tests:** gain-math unit tests (clamp/headroom), controller state tests.
**Acceptance:** Toggling direct volume changes level without the distortion/quantization of the
system scaler (verify by ear + analyzer); honest "unsupported" otherwise.

---

### T7 — 64-band parametric EQ (P1, high feasibility)

**Why:** Poweramp's flagship is 64-band; Pulsr stops at 32.

**Files:** `lib/data/audio/equalizer_manager.dart`, `lib/domain/models/eq_preset.dart`,
`lib/features/player/presentation/widgets/equalizer_sheet.dart`,
`lib/features/player/cubit/player_cubit.dart`.

**Steps:**
1. Generalise the `is32BandMode` bool into an `int eqBandMode` (10/32/64) or add
   `is64BandMode`; the native `setNativeEqBandCount(n)` already supports arbitrary counts.
2. Add `custom64Frequencies` (log-spaced 20 Hz–20 kHz, 64 points) to `EqPreset`, plus
   interpolation for preset gains.
3. Persist via `PrefsKeys` alongside the existing 32-band key; restore in `_restorePreferences`.
4. Extend the EQ sheet band-count toggle to 10 / 32 / 64 (minimal UI; not new skinning).
5. Migrate existing 32-band user frequencies to 64 by interpolation.

**Tests:** interpolation/migration tests; manager test that band count 64 is pushed to native.
**Acceptance:** 64 sliders render, native receives 64 bands, presets interpolate correctly.

---

### T8 — System-wide EQ for other apps (BLOCKED — document)

**Why:** Poweramp Equalizer applies effects to other apps.

**Technical reality:** Since Android 9/10, third-party apps cannot reliably attach an `AudioEffect`
to audio session `0` (global output) — access is restricted to privileged/system apps or requires
the `MODIFY_AUDIO_ROUTING`/`CAPTURE_AUDIO_OUTPUT` privileged permissions. On rooted or system-
signed builds it works; on retail it does not.

**Deliverable:** A short section appended to `docs/POWERAMP_COMPARISON.md` and a
`lib/core/constants/audio_feature_info.dart` entry making the limitation explicit. **Do not** ship
a non-functional global-EQ toggle.

---

### T9 — Format breadth (P1, decoder-dependent)

**Why:** Poweramp plays APE, WMA, TTA, TAK, WV, tracker mods, WebM.

**Files:** `lib/core/constants/audio_formats.dart`, `media_scanner_service.dart`,
`lib/data/audio/format_aware_decoder.dart`, possibly a new native decoder bridge.

**Steps (honest strategy):**
1. Classify extensions into three tiers in `AudioFormats`:
   - `supportedExtensions` (platform-decodable: keep current + `webm`, `aiff`, `aif`).
   - `nativeDecodableExtensions` (require the native FFmpeg/APE bridge: `ape`, `wma`, `tta`,
     `tak`, `wv`, `mpc`, tracker `mod/it/xm/s3m`).
   - `recognizedExtensions` (scanned but only playable when a decoder is present).
2. To actually decode the native-tier formats, add an FFmpeg-based decoder. Two options, in
   preference order:
   - **(a)** Vendor an FFmpeg `libavcodec`-backed decoder into the existing `libpulsr_dsp` JNI and
     expose `decodeToPcm(path)` returning a PCM stream the handler can play. This is the correct,
     verifiable path.
   - **(b)** Swap the playback backend to a libmpv-based one (`media_kit`). **Do not** do this
     without explicit approval — it is a large architectural change to the just_audio/
     audio_handler stack.
3. Until (2) lands, do **not** claim decode support: the scanner may index the files but the UI
   must mark them "decoder update required" and they must not appear playable.

**Tests:** scanner extension classification tests; decoder bridge test only if (a) is implemented.
**Acceptance:** Every listed "supported" format actually decodes; unsupported ones are honestly
flagged.

---

### T10 — CUE sheet playback (P1, high feasibility)

**Why:** Parser + `ChapterInfo` exist but are unused; Poweramp supports embedded/standalone CUE.

**Files:** `lib/data/db/tables.dart`, `app_database.dart` (migration v9→v10),
`music_repository.dart` + interface, `media_scanner_service.dart`, `audio_handler.dart`,
`player_cubit.dart`/`player_state.dart`, `lib/features/sheets/song_info_sheet.dart` (or the
advanced bar).

**Steps:**
1. **Schema v10.** Add nullable columns to `songs`: `cueStartMs`, `cueEndMs`, `cueFile`
   (`IntColumn/TextColumn`). Migration:
   ```dart
   if (from < 10) {
     if (!await hasColumn('songs', 'cue_start_ms')) await m.addColumn(songsTable, songsTable.cueStartMs);
     if (!await hasColumn('songs', 'cue_end_ms'))   await m.addColumn(songsTable, songsTable.cueEndMs);
     if (!await hasColumn('songs', 'cue_file'))     await m.addColumn(songsTable, songsTable.cueFile);
   }
   ```
   Then `dart run build_runner build --delete-conflicting-outputs`.
2. **Scanner expansion.** When a `.cue` file is found next to an audio file, parse it with
   `CueParser.findAndParseCue`. For a single-file album, create one virtual `songs` row per cue
   track sharing the same `path` but with distinct titles and `cueStartMs`/`cueEndMs`. Assign
   synthetic stable ids (e.g. negative hash of `path + index`, same convention as YTM sentinels
   in `file_intent_handler.dart`). Keep the original full-file row out of the library (or mark it
   hidden) to avoid duplication.
3. **Playback boundaries.** In `audio_handler`, when the current song has `cueEndMs`, seek to
   `cueStartMs` on start and advance to the next track when `position >= cueEndMs` (mirror the
   existing A-B loop wrap logic in `ab_loop_manager.dart` / the position listener).
4. Expose chapters for the currently-playing cue image via `PlayerCubit` state for the advanced
   bar / song info list (tap-to-seek).

**Tests:** repository round-trip for cue columns; scanner cue-expansion test using a fixture
`.cue`; playback-boundary unit test with a fake handler.
**Acceptance:** A single-file FLAC+`.cue` shows individual tracks, each playing its slice.

---

### T11 — HTTP internet radio / streams (P1, high feasibility)

**Why:** Poweramp plays `.m3u` HTTP streams; Pulsr has no generic streaming.

**Files:** new `lib/domain/models/radio_station.dart`, new repository/prefs storage,
`lib/data/audio/audio_handler.dart` (URL source path), new
`lib/features/radio/presentation/radio_screen.dart`, `lib/core/router/app_router.dart`,
`lib/features/shell/presentation/bottom_nav_bar.dart` or a Home entry.

**Steps:**
1. Model `RadioStation { id, name, url, genre, artworkUrl, lastPlayed }` persisted in
   SharedPreferences (JSON) or a new Drift table (prefer a table for large lists; otherwise prefs
   to avoid another migration).
2. Add "Add station" (URL or import a `.m3u` stream playlist). Reuse the M3U path extraction but
   keep only absolute `http(s)://` URLs (these are streams, not local files).
3. Playback: `audio_handler` must accept a station as a playable pseudo-song whose `path` is the
   URL; in `_resolveAudioSource`, if the path starts with `http`, build a
   `just_audio` `AudioSource.uri(Uri.parse(url))` (HLS `.m3u8` is auto-detected by just_audio;
   Icecast/Shoutcast progressive streams play via `setUrl`). Handle ICY metadata best-effort.
4. Media notification should show the station name; disable seek/next where meaningless.
5. Minimal UI: a Radio screen to add/list/play/delete stations. (This is a feature entry, not
   skinned UI.)

**Tests:** URL classification tests; a fake `AudioPlayer` test that a station builds the right
source; import of an `.m3u` stream list.
**Acceptance:** Pasting an HTTP stream URL plays it and appears in the notification.

---

### T12 — PLS / WPL playlist import & export (P1, high feasibility)

**Why:** Poweramp imports m3u/m3u8/pls/wpl; Pulsr only m3u/m3u8.

**Files:** `lib/domain/usecases/playlist_io_usecases.dart`.

**Steps:**
1. Add `parsePlsContent` (`[playlist]`, `FileN=`, `TitleN=`, resolves relative paths).
2. Add `parseWplContent` (XML `<media src="...">`).
3. Detect format by extension/content in `importPlaylistFromFile` and route to the right parser;
   reuse the existing path-matching logic.
4. Extend export: add `generatePlsContent` and `generateWplContent`; let the UI choose format
   (default M3U) — a small format picker is acceptable.
5. Add `m3u8`/`pls`/`wpl` to the file-picker allow-list in
   `playlists_screen.dart` (`allowedExtensions:`).

**Tests:** parser unit tests for PLS and WPL (relative + absolute paths, comments).
**Acceptance:** Import/export round-trips for all four formats.

---

### T13 — Chromecast (BLOCKED — document)

**Why:** Poweramp supports Google Cast.

**Technical reality:** Requires the Google Cast Android SDK, a registered Cast receiver
application id, Play Services Cast framework, and (`flutter_cast_framework` or a custom channel).
It cannot be implemented or verified without the project's Cast developer credentials and changes
the playback routing model (media is sent to the Cast device, not local). This is out of scope for
a local-first player's agent pass.

**Deliverable:** Document the dependency and leave the comparison row as a known gap.

---

## 5. Cross-cutting integration requirements

- **Conflict registry:** every new output mode (T1/T3/T5/T6) must add an entry to
  `lib/core/constants/audio_feature_info.dart` (`AudioFeatureRegistry` / `AudioConflicts`) and the
  settings UI must render the conflict card rather than silently overriding.
- **Settings plumbing:** each pref follows the `SettingsCubit` pattern (private key constant or
  `PrefsKeys`, `_loadPreferences`, setter, `safeEmit`), and each state field is added to the
  freezed `SettingsState` (regen).
- **Capability honesty:** any capability probe that fails must result in a disabled control with a
  reason string, never a pretend-active toggle.
- **Session logs:** new native stages should appear in the DSP inspector
  (`lib/features/player/presentation/widgets/dsp_inspector_sheet.dart`).
- **Localization:** new user-visible strings go into `app_en/ar/es.arb` (3 files in sync) and
  `flutter gen-l10n`.

---

## 6. Test & verification plan

Run after each task:

```bash
flutter analyze
flutter test --no-pub
flutter gen-l10n                     # if ARB changed
dart run build_runner build --delete-conflicting-outputs   # if schema/freezed changed
```

Native compile check (Windows host → Android):
```bash
cd android; ./gradlew :app:compileDebugKotlin
```

**Required new tests (minimum):**
- `test/dop_encoder_test.dart` — marker alternation + interleave (if not already present).
- `test/playlist_pls_wpl_test.dart` — PLS/WPL parsers.
- `test/cue_scanner_test.dart` — cue expansion + repository columns.
- `test/format_classification_test.dart` — three-tier format lists.
- `test/eq_64_band_test.dart` — 64-band interpolation/migration + native push.
- `test/player_follow_track_test.dart` — follow-track dedupe + service call.
- `test/radio_station_test.dart` — URL parsing/import.

**Regression gate:** the existing 801 tests must remain green. If a task changes behavior covered
by a test, update the test to the new intended contract (as was done for pagination and BPM in the
previous remediation).

---

## 7. Risks & mitigations

| Risk | Mitigation |
|---|---|
| USB exclusive breaks normal playback | Gate behind an explicit toggle; keep the existing path as default; auto-revert on `ACTION_USB_DEVICE_DETACHED`. |
| DoP produces silence on non-DAC output | Probe capability first; default `pcm`; never auto-enable. |
| DSF/DFF files with wrong marker endianness | Unit-test `DopEncoder` against known vectors; keep PCM fallback. |
| Schema migration data loss | Idempotent `hasColumn` guards; test upgrade from v9 fixture. |
| Format list bloats with unplayable files | Three-tier classification; only genuinely decodable formats appear playable. |
| `audio_handler.dart` megafile conflicts | Serialize tasks touching it; one owner at a time. |
| Native build not available in CI | Keep native changes behind capability checks so Dart tests pass without a device. |

---

## 8. Hand-off contract for the implementer

For **each** task, report:
1. Task ID + status (`DONE` / `PARTIAL` / `BLOCKED`).
2. Files changed (paths) and new files.
3. Native channel methods added (name + request/response shape).
4. Migration steps + regenerated artifacts.
5. Tests added and the exact commands run, with observed pass counts.
6. Any capability that could not be honestly implemented, with the technical reason.

**Do not** mark a task `DONE` unless `flutter analyze` is clean and `flutter test` passes.

---

## 9. Final acceptance checklist (parity scorecard)

| Poweramp feature | Target | Verified by |
|---|---|---|
| USB Exclusive + hw volume | T1 | Manual on UAC2 DAC + capability test |
| Follow-Track rate switching | T2 | Unit test (service called per rate change) |
| No-Resample / perfect bit-perfect | T3 | Conflict tests + native reason surfaced |
| Native/DoP DSD | T4 | DoP encoder vectors + routing test |
| 384/768k, 32-bit/float envelope | T5 | Validation + capability-gated UI test |
| DVC-equivalent | T6 | Gain math + audible/analyzer check |
| 64-band parametric EQ | T7 | 64 sliders + native count test |
| Format breadth | T9 | Decoder bridge test / honest flags |
| CUE playback | T10 | Scanner + playback-boundary tests |
| HTTP radio | T11 | Import + source-build tests |
| PLS/WPL | T12 | Parser round-trip tests |
| System-wide EQ | BLOCKED | Documented Android restriction |
| Chromecast | BLOCKED | Documented dependency |
| Skins/Milkdrop | OUT OF SCOPE | — |

When all non-blocked rows pass, Pulsr matches or exceeds Poweramp on every axis except the two
documented platform-blocked items.
