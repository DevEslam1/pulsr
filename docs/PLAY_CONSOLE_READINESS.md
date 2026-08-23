# Google Play Console Readiness & Store Policy Compliance

This document contains the release compliance audit, permission justifications, and Google Play Data Safety declarations for **Pulsr Music**.

---

## 1. Target SDK & Platform Compliance
- **Target SDK**: `34` (Android 14) / `35` (Android 15 ready).
- **Min SDK**: `24` (Android 7.0 Nougat).
- **64-bit Compliance**: Native libraries (`libsqlite3`, etc.) include `arm64-v8a` and `x86_64` ABIs.
- **R8 / ProGuard Minification**: Configured with keep rules for Drift, Jaudiotagger, JustAudio, AudioService, and Sentry.
- **App Bundle (AAB)**: Supported with resource splitting and keystore fail-fast verification.

---

## 2. Android Permissions & Policy Justifications

| Permission | API Level | Category | Play Console Justification |
|---|---|---|---|
| `READ_MEDIA_AUDIO` | API 33+ | Storage | Required to discover, index, and play user-stored audio files. |
| `READ_EXTERNAL_STORAGE` | API <= 32 | Storage (Legacy) | Required to discover, index, and play audio files on older Android versions. |
| `WRITE_EXTERNAL_STORAGE` | API <= 29 | Storage (Legacy) | Persist edited audio tags and exported artwork on pre-scoped-storage devices. |
| `FOREGROUND_SERVICE` | API 28+ | Background | Essential for continuous background audio playback while the screen is locked or another app is open. |
| `FOREGROUND_SERVICE_MEDIA_PLAYBACK` | API 34+ | Background (A14+) | Mandated by Android 14+ for foreground services handling media playback. |
| `POST_NOTIFICATIONS` | API 33+ | Notifications | Displaying interactive Now Playing media controls on the lock screen and notification shade. |
| `RECORD_AUDIO` | All | Optional Feature | Required solely for the live audio visualizer DSP analysis. If denied, Pulsr gracefully falls back to synthetic simulated waveforms with zero functionality loss. |
| `MODIFY_AUDIO_SETTINGS` | All | Playback | Required to configure the 10-band equalizer and manage the audio output session. |
| `WRITE_SETTINGS` | All | Optional Feature | Used only for the user-initiated "Set as Ringtone" action; requires the system Modify-Settings grant and is never written silently. |
| `WAKE_LOCK` | All | Core | Prevents CPU sleep while processing audio playback streams. |

---

## 3. Data Safety Form Declaration

- **Data Collection**: **None** (No user data, identifiers, financial information, contacts, or location collected).
- **Data Sharing**: **None** (Zero third-party data sharing).
- **Security Practices**:
  - All library metadata and playback state stored locally in SQLite database.
  - Device backups exclude DB to prevent cross-device restore corruption.
  - Sentry crash reporting is stripped of all PII (user identifiers, IP addresses, filenames) and enabled only in release builds with opt-in control.

---

## 4. Store Listing Information

### App Title
- **EN**: Pulsr Music - Offline Player
- **ES**: Pulsr Música - Reproductor
- **AR**: بولسر للموسيقى - مشغل دون اتصال

### Short Description
- **EN**: Premium offline music player with 10-band EQ, synced lyrics, and themes.
- **ES**: Reproductor de música offline con ecualizador de 10 bandas y letras sincronizadas.
- **AR**: مشغل موسيقى راقٍ دون اتصال مع معادل صوتي وكلمات متزامنة وثيمات مميزة.
