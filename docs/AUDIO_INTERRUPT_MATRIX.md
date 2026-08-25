# Pulsr Audio Interruption & Focus Matrix

This document outlines the audio focus policies, interruption lifecycles, and edge case handling implemented in **Pulsr Music**.

---

## 1. Audio Focus & Interruption Matrix

| Event / Trigger | AudioSession / System Signal | Pulsr Action | Verification Method |
|---|---|---|---|
| **Incoming Phone Call** | `AudioInterruptionType.pause` (Transient Loss) | Pauses playback immediately; caches playback offset. | Verified in `AudioHandler` session stream. |
| **Call Ended / Rejected** | `AudioInterruptionType.pause` (Resumption Allowed) | Resumes playback if `resumeAfterInterruption` is enabled in Settings. | Verified with simulated focus loss. |
| **GPS / Nav Prompts** | `AudioInterruptionType.duck` | Temporarily lowers volume to **30%** of previous level; restores original level when prompt finishes. | Verified in `AudioHandler._preDuckVolume`. |
| **Headphone Unplugged / BT Disconnect** | `becomingNoisyEventStream` | Pauses playback immediately without audio leakage to loudspeaker. | Verified in `AudioSession` noisy listener. |
| **Bluetooth Headset Reconnect** | System audio route update | Retains paused state; allows user to resume with headset media button. | Verified via `MediaButtonReceiver`. |
| **Another Music App Started** | `AudioInterruptionType.unknown` / permanent loss | Releases audio focus, unbinds hardware audio effects, and updates notification state. | Verified via `releaseEffects()`. |
| **Alarm Ringing** | `AudioInterruptionType.pause` | Pauses playback for alarm duration; restores when alarm dismissed. | Handled via transient loss policy. |
| **Process Death (OS Memory Reclaim)** | System kill / low memory | Continuous **1500ms debounced persistence** in Drift SQLite; state restored paused on launch. | Verified via `test/player_cubit_test.dart`. |
| **OEM Background App Kill** | Doze mode / Vendor optimization | Exemption guides provided via `BatteryOptimizationService` + settings card. | Verified via `test/battery_optimization_service_test.dart`. |
| **Device Lock / AOD** | Screen off | Foreground service with `MediaStyle` notification and lock screen playback controls. | Handled by `audio_service` + `NowPlayingWidget`. |

---

## 2. Hardware Audio Effects Session Discipline

- **Equalizer, BassBoost, Virtualizer, DynamicsProcessing**:
  - Bound strictly to active ExoPlayer `audioSessionId`.
  - On stop, focus abandonment, or app termination, `releaseEffects()` is invoked over JNI to release audio DSP hardware nodes.
