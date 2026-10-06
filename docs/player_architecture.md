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
