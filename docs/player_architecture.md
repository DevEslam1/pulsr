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

`ThemeRegistry` (`lib/features/player/presentation/themes/theme_registry.dart`) maps `PlayerThemeMode` values to modular widget builders:
1. `PlayerThemeMode.classic` — `ClassicPlayerTheme`
2. `PlayerThemeMode.card` — `CardPlayerTheme`
3. `PlayerThemeMode.circle` — `CirclePlayerTheme`
4. `PlayerThemeMode.minimal` — `MinimalPlayerTheme`
5. `PlayerThemeMode.vinyl` — `VinylPlayerTheme`
6. `PlayerThemeMode.cd` — `CdPlayerTheme` (compact disc with rainbow sheen and rotating optical tray)
7. `PlayerThemeMode.cassette` — `CassettePlayerTheme` (animated magnetic tape spools and tape counter)
8. `PlayerThemeMode.waveform` — `WaveformPlayerTheme`
9. `PlayerThemeMode.lyricsFocus` — `LyricsPlayerTheme`

Each theme composes `PlayerThemeScaffold` and `PlayerThemeChrome` with dedicated canvas painters under `themes/painters/`.

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
- `QuranModeService` coordinates persistent reciter profiles, style presets (Murattal, Mujawwad), mosque ambience convolution reverb, vocal warmth EQ, and ayah-precision bookmarks.
- Supported in UI by `QuranMushafView` (`lib/features/player/presentation/widgets/quran_mushaf_view.dart`) and `QuranRadioHeroCarousel` (`lib/features/home/presentation/widgets/quran_radio_hero_carousel.dart`).

---

## 9. Resilient Stream Resolution & Modern Rhino Deciphering

- **Rhino JS URL Builder (`solveSig` & `solveN`)**:
  - `PlayerJavaScript.kt` runs embedded Rhino 1.8.1 with the player's own authoritative URL builder (`fE -> Vq/Lb`).
  - Deciphers signatures and transforms `n`-throttling parameters reliably across YouTube player rewrites without regex fragility.
- **Age-Gated (+18) Track Fallback**:
  - `InnertubeClient.resolveAgeGatedStream()` retries restricted content using the authenticated `WEB` client carrying the user's session cookies.
