# Player Architecture Audit (Phase 0)

This audit documents the state of the Pulsr audio player stack prior to the structural refactoring pass (PR 2). It identifies all direct volume writers, state duplication, raw preference keys, mutable interruption/crossfade flags, bare catch blocks, and Freezed `copyWith` null-handling semantics.

---

## 1. Calls to `setVolume` on `AudioPlayer`

The following table lists every call to `setVolume` on any `AudioPlayer` instance across the player and data audio stack:

| File | Line | Function / Context | Target Player | Note |
|---|---|---|---|---|
| `lib/data/audio/audio_handler.dart` | 1216 | `setVolume` | `_activePlayer` | Normal volume adjustment |
| `lib/data/audio/audio_handler.dart` | 1244 | `_reapplyActiveVolume` | `_activePlayer` | Reapplying volume when DSP or RG changes |
| `lib/data/audio/audio_handler.dart` | 2084 | Focus duck listener (duck ramp) | `_activePlayer` | Transient focus ducking |
| `lib/data/audio/audio_handler.dart` | 2087 | Focus duck listener (duck ramp) | `_inactivePlayer` | Inactive player during crossfade duck |
| `lib/data/audio/audio_handler.dart` | 2097 | Focus duck listener (immediate) | `_activePlayer` | Non-smooth ducking |
| `lib/data/audio/audio_handler.dart` | 2100 | Focus duck listener (immediate) | `_inactivePlayer` | Inactive player ducking |
| `lib/data/audio/audio_handler.dart` | 2173 | Focus duck end (restore) | `_activePlayer` | Restoring pre-duck active volume |
| `lib/data/audio/audio_handler.dart` | 2190 | Focus duck end (restore) | `_inactivePlayer` | Restoring pre-duck inactive volume |
| `lib/data/audio/audio_handler.dart` | 3087 | `duckForTransientAudio` (restore) | `_activePlayer` | System UI transient sound restore |
| `lib/data/audio/audio_handler.dart` | 3094 | `duckForTransientAudio` (duck) | `_activePlayer` | System UI transient sound duck |
| `lib/data/audio/audio_handler_queue_engine.dart` | 207 | `_playIndex` | `_activePlayer` | Setting initial active volume |
| `lib/data/audio/audio_handler_queue_engine.dart` | 223 | `_playIndex` | `_activePlayer` | Fallback load error volume reset |
| `lib/data/audio/audio_handler_queue_engine.dart` | 228 | `_playIndex` | `_inactivePlayer` | Zeroing inactive player |
| `lib/data/audio/audio_handler_queue_engine.dart` | 261 | `_playIndex` | `_activePlayer` | Initial track setup |
| `lib/data/audio/audio_handler_queue_engine.dart` | 287 | `_playIndex` | `_activePlayer` | Retrying local track |
| `lib/data/audio/audio_handler_queue_engine.dart` | 301 | `_playIndex` | `_activePlayer` | Retrying network track |
| `lib/data/audio/audio_handler_queue_engine.dart` | 316 | `_playIndex` | `_activePlayer` | Cache hit playback setup |
| `lib/data/audio/audio_handler_queue_engine.dart` | 328 | `_playIndex` | `_activePlayer` | Fallback URL playback setup |
| `lib/data/audio/audio_handler_queue_engine.dart` | 344 | `_playIndex` | `_activePlayer` | Resolving stream fallback |
| `lib/data/audio/audio_handler_queue_engine.dart` | 383 | `_playIndex` | `_activePlayer` | Final player volume prep |
| `lib/data/audio/audio_handler_queue_engine.dart` | 419 | `_playIndex` | `active` | Recovery player branch |
| `lib/data/audio/audio_handler_queue_engine.dart` | 430 | `_playIndex` | `active` | Inactive recovery branch |
| `lib/data/audio/audio_handler_queue_engine.dart` | 473 | `_playIndex` | `outgoingAfterDelay` | Track delay volume restore |
| `lib/data/audio/audio_handler_queue_engine.dart` | 519 | `_playIndex` | `_activePlayer` | Post-load volume settle |
| `lib/data/audio/audio_handler_queue_engine.dart` | 750 | `_applyReplayGain` | `_activePlayer` | Direct ReplayGain application |
| `lib/data/audio/audio_handler_queue_engine.dart` | 857 | `_applyDvcVolume` | `_activePlayer` | Direct Volume Control (DVC) mode |
| `lib/data/audio/audio_handler_queue_engine.dart` | 1082, 1084 | `_onPlaybackCompleted` | `_activePlayer` | Loop/advance next track reset |
| `lib/data/audio/audio_handler_queue_engine.dart` | 1226 | `_preloadNextTrack` | `_activePlayer` | Preload transition target |
| `lib/data/audio/audio_handler_queue_engine.dart` | 1367 | `_reconcilePlayback` | `_activePlayer` | Reconciliation volume set |
| `lib/data/audio/collaborators/playback_volume_controller.dart` | 161, 172 | `applyVolume` | `player` | Instant volume application |
| `lib/data/audio/collaborators/playback_volume_controller.dart` | 203 | `applyVolume` (smooth) | `player` | Stepped smooth volume ramp (500ms) |
| `lib/data/audio/crossfade_manager.dart` | 359, 365 | `fadeVolume` | `player` | Stepped fade-in / fade-out |
| `lib/data/audio/crossfade_manager.dart` | 393, 420 | `fadeVolume` | `player` | Linear fade step |
| `lib/data/audio/crossfade_manager.dart` | 447, 465 | `crossfadeVolumes` | `player` | Stepped dual-player crossfade |
| `lib/data/audio/crossfade_manager.dart` | 510, 511 | `crossfadeVolumes` | `active`, `inactive` | Immediate crossfade cut |
| `lib/data/audio/crossfade_manager.dart` | 516, 517 | `crossfadeVolumes` | `active`, `inactive` | Fallback crossfade cut |
| `lib/data/audio/crossfade_manager.dart` | 596, 598 | `crossfadeVolumes` | `active`, `inactive` | Stepped gain curve step |
| `lib/data/audio/crossfade_manager.dart` | 619, 620 | `crossfadeVolumes` | `active`, `inactive` | Final transition settle |
| `lib/data/audio/crossfade_manager.dart` | 698, 699 | `cancelCrossfade` | `inactivePlayer`, `activePlayer` | Cancellation restore |
| `lib/data/audio/sleep_timer_manager.dart` | 389 | `_applyFadeOutStep` | `player` | Standalone sleep fade step |
| `lib/data/audio/sleep_timer_manager.dart` | 457, 504 | `_fadeBeforePause` / `_cancelFade` | `player` | Sleep fade finish / cancel |

---

## 2. Mutable Flags Participating in Interruption, Duck, Noisy, Crossfade, Sleep, Gapless

| Flag / Variable | Owner File | Read By | Written By | Purpose |
|---|---|---|---|---|
| `_duckActive` | `audio_handler.dart` | Focus listener, `duckForTransientAudio`, `_reapplyActiveVolume` | Focus listener, `duckForTransientAudio`, `_handleBecomingNoisy` | Tracks if audio duck factor is active |
| `_duckDepthCounter` | `audio_handler.dart` | Focus listener | Focus listener, `_duckDepthCounter++` / `--` | Handles nested/stacked duck events |
| `_preDuckVolume` | `audio_handler.dart` | Focus listener, restore | Focus listener (snapshot) | Pre-duck volume of active player |
| `_preDuckInactiveVolume` | `audio_handler.dart` | Focus listener, restore | Focus listener (snapshot) | Pre-duck volume of inactive player |
| `_pausedForNoisy` | `audio_handler.dart` | `_maybeAutoResumeOnReconnect`, `devicesStream` | Becoming noisy listener, user `play()`, `pause()`, stop | Guards auto-resume after headphone unplug |
| `_lastNoisyTime` | `audio_handler.dart` | Becoming noisy listener | Becoming noisy listener | Debounces rapid unplug events |
| `_noisyPauseTime` | `audio_handler.dart` | `_maybeAutoResumeOnReconnect` | Becoming noisy listener | Timeout calculation for auto-resume |
| `_interruption` (`InterruptionStateMachine`) | `audio_handler.dart` | `play()`, `pause()`, focus listener | Focus listener, `handleMediaButtonLongPress`, `onUserPause` | State machine for call/focus loss resume |
| `_crossfadeStartInFlight` | `audio_handler_queue_engine.dart` | `_startCrossfade` | `_startCrossfade` (set true, reset in finally) | Re-entrancy latch for crossfade start |
| `_crossfadeManager.isCrossfading` | `crossfade_manager.dart` | `audio_handler.dart`, `queue_engine.dart` | `CrossfadeManager.crossfadeVolumes` | Prevents volume collisions during crossfade |
| `_sleepFadeFactor` | `audio_handler.dart` | `setVolume`, `_reapplyActiveVolume` | Sleep timer callback (`onFadeFactor`) | Attenuation factor for sleep timer fade-out |
| `_isFadeOutActive` | `sleep_timer_manager.dart` | `SleepTimerManager` | `SleepTimerManager` fade steps | Guard for sleep timer volume ramp |
| `_gaplessActive` | `audio_handler_queue_engine.dart` | `_playIndex`, completion | Transition arbitrator | Gapless transition mode active |

---

## 3. Raw String Preference Keys Used Outside `PrefsKeys`

The following raw string keys are used directly instead of constants in `PrefsKeys`:

1. `'setting_streaming_quality'` (`audio_handler.dart`, `audio_handler_playback_extras.dart`, `stream_resolution_pipeline.dart`)
2. `'adaptive_runtime_quality'` (`audio_handler.dart`, `audio_handler_playback_extras.dart`, `settings_audio_actions.dart`)
3. `'setting_offline_only_mode'` (`audio_handler.dart`, `stream_resolution_pipeline.dart`)
4. `'setting_wifi_only_mode'` (`audio_handler.dart`, `stream_resolution_pipeline.dart`)
5. `'hedged_resolution_enabled'` (`audio_handler.dart`, `audio_handler_playback_extras.dart`)
6. `'adaptive_quality_enabled'` (`audio_handler.dart`, `audio_handler_playback_extras.dart`)
7. `'setting_language'` (`audio_handler.dart`)
8. `'audio_normalization_enabled'` (`audio_handler_streaming.dart`)
9. `'audio_ducking_mode_v1'` (`ducking_controller.dart`)
10. `'audio_ducking_level_v1'` (`ducking_controller.dart`)

All of these will be consolidated into `PrefsKeys` preserving exact string values.

---

## 4. Bare `catch (_) {}` Audit & Verdict

| File | Line | Context | Verdict | Rationale |
|---|---|---|---|---|
| `audio_handler_queue_engine.dart` | 420, 428, 431 | Cache pre-resolution & player cleanup | **Replace** | Swallowed errors here hide player reset failures; rate-limit log. |
| `audio_handler_queue_engine.dart` | 467, 472, 483 | Track delay timer cancel / seek | **Replace** | Log unexpected timer cancellation errors. |
| `audio_handler_queue_engine.dart` | 511, 514, 517, 520 | Secondary player stop / release | **Keep** | Expected no-ops if player is already stopped or idle. Add comment. |
| `audio_handler_queue_engine.dart` | 744, 749, 856, 863 | ReplayGain & DVC volume apply | **Replace** | Volume failures lead to blast/mute bugs; rate-limit log. |
| `audio_handler_queue_engine.dart` | 1053, 1064, 1078, 1095 | Playback completion advance | **Replace** | Failures during completion cause stuck queue; log with context. |
| `audio_handler_queue_engine.dart` | 1308, 1311, 1366, 1449 | Queue reconciliation & prefetch | **Replace** | Log failures with rate limiting. |
| `audio_handler_streaming.dart` | 15, 228, 358, 399, 424 | Bit-perfect check, normalization | **Replace** | Log codec/DSP query errors. |
| `audio_handler_transport.dart` | 13, 32, 43 | Seek & pause error suppression | **Replace** | Log transport exceptions. |
| `audio_handler_transport.dart` | 235, 249, 257 | Headset hook click timeouts | **Keep** | Timer cancellations on rapid clicks are expected. Add comment. |
| `audio_handler_transport.dart` | 402, 447, 470, 541, 554 | Speed/pitch/rewind operations | **Replace** | Log audio rate setting errors. |
| `collaborators/playback_volume_controller.dart` | 173, 204 | Smooth ramp volume step | **Keep** | Volume step failure during dispose or superseded fade is expected. |
| `collaborators/stream_resolution_pipeline.dart` | 102, 138, 162, 198, 260 | Hedged stream cancel & fallback | **Replace** | Swallows network stream diagnostics. Rate-limit log. |
| `crossfade_manager.dart` | 322, 394, 421, 466, 621 | Player volume step & DSP curve | **Keep** | Player can be disposed mid-fade or curve unsupported on platform. Add comment. |
| `ducking_controller.dart` | 43, 51 | SharedPreferences load/save | **Replace** | Pref disk I/O errors should be logged. |
| `sleep_timer_manager.dart` | 366, 390, 419, 449, 459, 492, 500, 505, 511, 579 | Sleep fade steps & pref clears | **Replace** | Log timer/ramp errors; keep pref clear failures silent if key absent. |
| `player_cubit.dart` | 791, 840 | Position stream error / session ID | **Replace** | Log stream faults. |
| `player_widget_coordinator.dart` | 114, 135 | Platform widget channel updates | **Keep** | Channel missing or app backgrounded is benign. Add comment. |

---

## 5. State Duplicated Between `PlayerCubit` and `PulsrAudioHandler`

| State Property | Authority | Duplicated In `PlayerCubit` | Resolution in Phase 4 |
|---|---|---|---|
| `isPlaying` | `PulsrAudioHandler.playbackState.playing` | `PlayerState.playback.isPlaying` | Cubit mirrors handler; transport controller uses timed optimistic override. |
| `position` | `PulsrAudioHandler.compensatedPositionStream` | `PlayerState.playback.position` | Position stream feeds Cubit directly. |
| `duration` | `PulsrAudioHandler.mediaItem.duration` | `PlayerState.playback.duration` | Resolved from mediaItem and song metadata helper. |
| `repeatMode` | `PulsrAudioHandler.playbackState.repeatMode` | `PlayerState.playback.repeatMode` | Cubit maps strictly from `playbackState.repeatMode`. |
| `isShuffle` | `PulsrAudioHandler.playbackState.shuffleMode` | `PlayerState.playback.isShuffle` | Cubit maps strictly from `playbackState.shuffleMode`. |
| `queue` | `PulsrAudioHandler.queue` | `PlayerState.queueSlice.queue` | Cubit synchronizes from `audioHandler.queue`. |
| `currentIndex` | `PulsrAudioHandler.playbackState.queueIndex` | `PlayerState.queueSlice.currentIndex` | Driven by handler's authoritative queue index. |
| `isFavorite` | Database / MediaItem extras | Song objects in `QueueSlice` & `PlaybackSlice` | Unified via `ToggleFavoriteUseCase`. |

---

## 6. Freezed `copyWith` Null-Handling Semantics

### Analysis of Generated Code
In Freezed-generated classes (`_$PlaybackSliceCopyWithImpl`, etc.):
```dart
$Res call({
  Object? currentSong = freezed,
  Object? errorMessage = freezed,
  ...
}) {
  return _then(PlaybackSlice(
    currentSong: freezed == currentSong
        ? _self.currentSong
        : currentSong as SongsTableData?,
    errorMessage: freezed == errorMessage
        ? _self.errorMessage
        : errorMessage as String?,
    ...
  ));
}
```
Passing `null` explicitly (e.g. `errorMessage: null` or `currentSong: null`) passes `currentSong = null != freezed`, which **DOES** set the field to `null`! Passing `null` only keeps the old value if the caller omits the argument, because the default argument is `freezed` (a unique sentinel object), NOT `null`.

### Verification of Calls
1. `playback.copyWith(errorMessage: null)`: Correctly clears `errorMessage` to `null`.
2. `playback.copyWith(currentSong: null)`: Correctly clears `currentSong` to `null`.
3. `playback.copyWith(sleepTimerRemaining: null)`: Correctly clears the sleep timer duration.

**Verdict:** The Freezed implementation in this codebase correctly distinguishes omitted arguments (`freezed`) from explicit `null` arguments. Explicitly passing `null` clears the field as intended.
