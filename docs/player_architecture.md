# Pulsr Player Architecture (Final Hardened Design)

This document describes the hardened architecture of the Pulsr audio player stack resulting from the structural refactoring pass (PR 2).

---

## 1. Single Volume Authority (`PlaybackVolumeMixer`)

Prior to this refactor, 5 distinct components (`PulsrAudioHandler`, `PlaybackVolumeController`, `CrossfadeManager`, `SleepTimerManager`, and direct DVC callers) made concurrent uncoordinated calls to `AudioPlayer.setVolume()`.

In the new architecture, **`PlaybackVolumeMixer`** (`lib/data/audio/playback_volume_mixer.dart`) is the single authority:
- **Inputs**:
  - `userVolume`: User's global playback volume slider ($0.0 \dots 1.0$).
  - `targetActiveFactor` & `targetInactiveFactor`: ReplayGain, per-track preamp/offset, and album context factors.
  - `duckFactor`: Transient attenuation factor for navigation prompts and speech ($0.05 \dots 1.0$; default $1.0$).
  - `sleepFadeFactor`: Multiplier for monotonic sleep timer gradual fade ($0.0 \dots 1.0$; default $1.0$).
  - `crossfadeOutgoingGain` & `crossfadeIncomingGain`: DSP loudness curve gains managed during track transitions.
  - `dvcEnabled`: Direct Volume Control mode (hardware volume handles user volume, mixer fixes base to unity).
- **Output**:
  - Computes `calculatedActiveVolume` and `calculatedInactiveVolume`.
  - Serializes and coalesces async execution via `apply()`.

---

## 2. Playback Interruption Manager (`PlaybackInterruptionManager`)

All focus losses, noisy unplug events, system sound dings, and call interruptions are mediated through **`PlaybackInterruptionManager`** (`lib/data/audio/playback_interruption_manager.dart`).

### State Transition Table

| Current State | Event | Decision | Next State | Notes |
|---|---|---|---|---|
| **idle (playing: true)** | `duckBegin` | `duck` | **ducked** | Transient speech / navigation prompt |
| **idle (playing: false)** | `duckBegin` | `ignore` | **idle** | Do not duck paused playback |
| **ducked** | `duckBegin` (nested) | `ignore` | **ducked** | Increments duck depth counter |
| **ducked** | `duckEnd` (depth > 1) | `ignore` | **ducked** | Decrements duck depth counter |
| **ducked** | `duckEnd` (depth == 1) | `unduck` | **idle** | Restores volume cleanly via mixer factor |
| **idle (playing: true)** | `pauseInterruptionBegin` | `pause` | **paused(interruption)** | Incoming phone call |
| **idle (playing: false)** | `pauseInterruptionBegin` | `ignore` | **idle** | No auto-resume snapshot taken |
| **paused(interruption)** | `pauseInterruptionEnd` | `resume` / `ignore` | **idle** | Resumes only if `resumeAfterInterruption` is enabled |
| **idle (playing: true)** | `becomingNoisy` | `pause` | **paused(noisy)** | Headphone unplug / disconnect |
| **paused(noisy)** | `deviceReconnect` (< timeout) | `resume` | **idle** | Resumes if route is headset and within window |
| **paused(noisy)** | `deviceReconnect` (> timeout) | `ignore` | **idle** | Timeout expired, stays paused |
| **any** | `userPlay` / `userPause` | `ignore` | **idle** | Unconditionally clears pending auto-resumes |

---

## 3. Playback State Authority & Synchronization

- **Authoritative Source**: `PulsrAudioHandler`'s reactive streams (`playbackState`, `mediaItem`, `queue`) own transport state, playback positions, active track identity, queue items, speed, repeat, and shuffle.
- **`PlayerCubit`**: Acts as a reactive mirror of `PulsrAudioHandler`. Optimistic UI updates occur only in `PlayerTransportController` with timed rollbacks.
- **Favorites**: All toggle favorite actions (App UI, media notification shade, Android Auto) route exclusively through `ToggleFavoriteUseCase` into `updateFavorite()`.

---

## 4. Consolidated Preferences & Typed Access (`PlayerPrefs`)

- All raw preference key strings have been moved into **`PrefsKeys`** (`lib/core/constants/prefs_keys.dart`).
- **`PlayerPrefs`** (`lib/data/audio/player_prefs.dart`) provides a typed, read-only snapshot of cached preferences for the audio handler and playback stack.
- Precedence for streaming quality:
  1. `adaptive_runtime_quality` (if adaptive quality is enabled and active).
  2. `setting_streaming_quality` (user's explicit setting).
  3. Default fallback: `'high'`.

---

## 5. Now Playing Themes Architecture (`ThemeRegistry`)

`ThemeRegistry` (`lib/features/player/presentation/themes/theme_registry.dart`) maps `PlayerThemeMode` values to modular widget builders, built on top of `PlayerSurfaceShell` (`player_surface_shell.dart`) and `PlayerToolsSheet` (`player_tools_sheet.dart`):
1. `PlayerThemeMode.clean` — `CleanPlayerTheme` (Apple Music-inspired borderless artwork, smooth mesh gradient, capsule scrubber)
2. `PlayerThemeMode.card` — `CardPlayerTheme` (spatial live blurred canvas, swipeable stacked album card deck, frosted control card)
3. `PlayerThemeMode.vinyl` — `VinylPlayerTheme` (grooved rotating vinyl, animated tonearm drop/lift, 33⅓ RPM LED, rotary transport)
4. `PlayerThemeMode.cd` — `CdPlayerTheme` (iridescent compact disc, translucent Y2K acrylic jewel case with ribbed spine, dot-matrix LCD)
5. `PlayerThemeMode.cassette` — `CassettePlayerTheme` (full-screen anodized chassis, spinning tape spools, 16-segment LED VU meters, mechanical keys)
6. `PlayerThemeMode.waveform` — `WaveformPlayerTheme` (interactive seekable oscilloscope centerpiece from `WaveformService`, audio telemetry strip)
7. `PlayerThemeMode.lyricsFocus` — `LyricsPlayerTheme` (70% viewport synced scrolling LRC lyrics stage, glowing active line, tap-to-seek)
8. `PlayerThemeMode.milkdrop` — `MilkdropPlayerTheme` (edge-to-edge `shaders/milkdrop.frag` GPU shader surface with Canvas fallback under GPU Saver, tap-to-immerse)

Each theme owns its full-screen visual identity via `PlayerSurfaceShell`, while secondary actions (A/B loop, EQ/DSP, DAC, Speed, Quran, Ambient, Sleep Timer, Party) are housed in `PlayerToolsSheet`. Legacy saved preferences (`classic`, `circle`, `minimal`) gracefully migrate to `clean`, `vinyl`, and `waveform`.

---

## 6. Multi-Slot Queue Persistence (`QueueSlotCodec`)

Queue persistence across application restarts is managed via `QueueSlotCodec` (`lib/features/player/cubit/queue_slot_codec.dart`):
- Supports **3 independent queue slots** (indices 0, 1, 2; `maxSlotIndex = 2`).
- Off-isolate JSON encode/decode using `compute()`.
- Debounced disk writes to avoid main-thread jank during reordering.
- Atomic rollback on failed queue reorders or item removals.

---

## 7. Output Topology & Cached Snapshots (`HiResAudioService`)

- `HiResAudioService.getAudioOutputInfo({bool allowCached = false})`:
  - When `allowCached = true`, route-change callers reuse the fresh snapshot pushed by the native event channel instead of issuing a second probe during Bluetooth/startup connection jank.
  - Method channel probe timeout is set to 8 seconds to prevent false-positive timeouts during heavy JS engine warmup.

---

## 8. Quran Mode Architecture (`QuranModeService`)

- Offline Tanzil 1.1 Uthmani Quran catalog (`assets/quran/`) provides all 114 Surahs offline without network assets.
- `QuranModeService` coordinates persistent reciter profiles, five style presets (Murattal, Mujawwad, Tarawih, Memorization, Sleep), mosque ambience convolution reverb, vocal warmth EQ, tempo steps and ayah-precision bookmarks.
- Supported in UI by `QuranMushafView` (`lib/features/player/presentation/widgets/quran_mushaf_view.dart`) and `QuranRadioHeroCarousel` (`lib/features/home/presentation/widgets/quran_radio_hero_carousel.dart`).

---

## 9. Resilient Stream Resolution & Modern Rhino Deciphering

- **Rhino JS URL Builder (`solveSig` & `solveN`)**:
  - `PlayerJavaScript.kt` runs embedded Rhino 1.8.1 with the player's own authoritative URL builder (`fE -> Vq/Lb`).
  - Deciphers signatures and transforms `n`-throttling parameters reliably across YouTube player rewrites without regex fragility.
- **Age-Gated (+18) Track Fallback**:
  - `InnertubeClient.resolveAgeGatedStream()` retries restricted content using the authenticated `WEB` client carrying the user's session cookies.

---

## 10. Modular PlaybackBackend, FeatureGate & OutputVerdict (§8 Remediation)

To cleanly decouple the media queue and session coordinator from rendering pipelines across local and remote destinations, the player architecture introduces the `PlaybackBackend` seam:

```
PulsrAudioHandler (Queue, Session, MediaNotification, Lockscreen)
       │
       ▼
FeatureGate (Rules, Precedence, Refusal Reasons)
       │
       ▼
OutputVerdictController (Dynamically computes OutputVerdict)
       │
       ├───────────────────┬───────────────────┬───────────────────┐
       ▼                   ▼                   ▼                   ▼
 LocalPcmBackend     LocalDsdBackend      CastBackend        UpnpBackend
(ExoPlayer A/B +    (Dedicated USB Pull  (Google Cast SDK  (DLNA AVTransport
 Native C++ DSP)      NativeDsdSession)    Loopback Proxy)   Remote Renderer)
```

### 10.1 Backends
1. **`LocalPcmBackend` (`lib/data/audio/playback_backend.dart`)**:
   - Wraps the existing A/B ExoPlayer instances and native C++ DSP engine.
   - Supports gapless, crossfade, ReplayGain, local DSP stages, and software volume.
2. **`LocalDsdBackend` (`lib/data/audio/native_dsd_session.dart`)**:
   - Dedicated pull-renderer session for 1-bit DSD audio streams (DSD64/128/256/512).
   - Accurate byte-based position and duration reporting directly from flushed frames; eliminates fake WAV headers.
   - Enforces fixed volume or hardware volume; strictly refuses PCM-domain software volume scaling on 1-bit streams.
3. **`CastBackend` (`lib/data/services/cast_service.dart`)**:
   - Streams media via localhost prebuffer HTTP server (`127.0.0.1`) to Google Cast receivers.
   - Full transport control (Play, Pause, Stop, Seek, Next, Previous) with duration and position synchronization.
4. **`UpnpBackend` (`lib/features/dlna/dlna_renderer_service.dart`)**:
   - Controls DLNA/UPnP renderers via SOAP AVTransport actions.
   - Backed by `UpnpDeviceDescriptionCache` operating on a true LRU cache policy.

### 10.2 FeatureGate & Conflict Precedence
- Centralized policy engine evaluating allowed/blocked actions per backend and route:
  1. **Bit-perfect mode**: strictly blocks software volume, remastering, HRTF, crossfeed, and all DSP stages.
  2. **Native DSD mode**: bypasses PCM DSP, crossfade, and ReplayGain. Requires hardware volume or fixed-volume mode.
  3. **Remaster**: follow-rate integer upsampling (x2/x4/x8) and real-time PCM-to-DSD; mutually exclusive with bit-perfect.
  4. **Low-power bypass**: mutually exclusive with any active DSP stage; server-side interlock rejects bypass when EQ/remaster/HRTF is enabled.
  5. **Spatial exclusivity**: HRTF / SOFA binaural spatializer and BS2B crossfeed are mutually exclusive.

### 10.3 OutputVerdict Derived Status
- Replaces optimistic static flags with a single, immutable `OutputVerdict` computed dynamically from:
  - Negotiated hardware sink format (sample rate, bit depth, encoding).
  - Active backend capabilities.
  - Active native DSP stage bitmask (`DspStageMask`).
  - Actual DSD transport state and output route.
- Recomputed on track transitions, route changes, engine recreation, and mid-track toggle events.
