<div align="center">

  <img src="assets/app_icon/app_icon.svg" width="128" height="128" alt="Pulsr Music Logo" />

  # Pulsr Music
  ### Premium Offline-First Local Music Player for Android & Beyond

  <p align="center">
    <strong>Studio-grade DSP Suite • 10/32-Band AutoEQ • Room Correction • Synced LRC Lyrics • 8 Aura Themes • Offline-First &amp; Private (Pulsr Pure)</strong>
  </p>

  <p align="center">
    <a href="https://flutter.dev"><img src="https://img.shields.io/badge/Flutter-3.x-02569B?style=for-the-badge&logo=flutter&logoColor=white" alt="Flutter"></a>
    <a href="https://dart.dev"><img src="https://img.shields.io/badge/Dart-3.x-0175C2?style=for-the-badge&logo=dart&logoColor=white" alt="Dart"></a>
    <a href="#"><img src="https://img.shields.io/badge/Android-14%20%2F%2015%20Ready-3DDC84?style=for-the-badge&logo=android&logoColor=white" alt="Android 14/15"></a>
    <a href="https://github.com/DevEslam1/pulsr/releases"><img src="https://img.shields.io/github/downloads/DevEslam1/pulsr/total?style=for-the-badge&color=blueviolet&logo=github" alt="GitHub Total Downloads"></a>
    <a href="LICENSE"><img src="https://img.shields.io/badge/License-GPLv3-blue.svg?style=for-the-badge" alt="License GPLv3"></a>
  </p>

  <p align="center">
    <a href="#-key-features">Features</a> •
    <a href="#-landing-website">Website</a> •
    <a href="#-architecture--tech-stack">Architecture</a> •
    <a href="#-headphone-calibration--autoeq">AutoEQ Profiles</a> •
    <a href="#-getting-started--build-guide">Getting Started</a> •
    <a href="#-permissions--privacy-matrix">Privacy Matrix</a>
  </p>

</div>

---

## 🌟 Overview

**Pulsr Music** is an audiophile-grade, offline-first music player engineered with Flutter, Dart, BLoC, and Drift SQLite. It strips away cloud bloat, algorithmic subscriptions, and privacy-invasive analytics to deliver an ultra-fast, local music playback experience with dynamic aesthetics and hardware-accelerated DSP.

Whether you're listening to 24-bit/192kHz lossless FLAC albums or organizing your local MP3 catalog, Pulsr provides bit-perfect audio decoding, a complete studio DSP chain (10/32-band EQ, spatializer, dynamics, convolution reverb and room correction), interactive karaoke lyrics, and a fluid Aura design system.

---

## 🌐 Landing Website

Pulsr comes with an interactive landing website located in [`website/`](website/):

- **Live Interactive Player Mockup**: Real-time HTML5 audio visualizer, seekbar, and dynamic Aura theme switcher.
- **Parametric 10-Band EQ Sandbox**: Interactive frequency response curve renderer with headphone target presets.
- **Karaoke Lyrics Scroller**: Millisecond-synced lyrics with tap-to-seek preview.
- **Audio Format Compatibility Matrix**: FLAC, ALAC, WAV, AAC, MP3, OPUS, and OGG.
- **Direct APK & SHA-256 Download Hub**: Universal release verification.
- **Complete DSP Suite Showcase**: Every stage of the audio chain, from 10/32-band EQ and room correction to spatializer, dynamics and convolution reverb.
- **Editions, Library Tools & Sync**: Pulsr Pure vs Pulsr Plus, smart playlists, duplicate cleanup, and scrobbling/automation.

> To preview the website locally, open [`website/index.html`](website/index.html) in any modern web browser or serve via `npx serve website` / GitHub Pages.

---

## ✨ Key Features

### 🎧 1. Audiophile Audio Engine & DSP
- **10 / 32 / 64-Band Parametric Equalizer**: Switch between the classic 10-band graphic curve (±12 dB, 31 Hz–16 kHz), a 32-band, or a 64-band parametric engine with a custom frequency editor, A/B flat compare, and four recallable A/B/C/D slots.
- **AutoEQ Headphone Calibration**: Bundled compensation curves for industry-leading headphones (*Harman Target 2019/2018, Apple AirPods Pro, Sony WH-1000XM4/XM5, Sennheiser HD600, Beyerdynamic*), an online AutoEQ search, and per-song auto-apply by name.
- **Full Effects Chain**: Bass boost, per-band mute/solo, manual preamp, 3D spatial virtualizer, multiband dynamics, studio compressor, lookahead brickwall limiter, crossfeed, convolution reverb with custom WAV impulse responses, harmonic saturation/exciter, mid/side stereo width, Fletcher–Munson loudness contour, subwoofer crossover, dynamic EQ, high-quality sinc resampler, and TPDF dither.
- **Room Correction Wizard**: Stepped-sine sweep measurement with mic capture, auto-fitted correction curve, optional stacking with a headphone AutoEQ profile, and linear-phase FIR export.
- **ReplayGain & Per-Song Overrides**: Track/album ReplayGain with preamp, plus per-song EQ, volume and BPM overrides and per-album DSP memory.
- **Bit-Perfect Hi-Res Badging & Output**: Detection for sample rates (44.1 kHz–192 kHz) and bit depths (16/24/32-bit float), bit-perfect mode, **strict no-resample mode**, **follow-track sample-rate switching**, float DSP path, AAudio direct output, USB-DAC negotiation, **DSD over PCM (DoP)** output, and Bluetooth codec control (LDAC/aptX).
- **DSP Inspector & Conflict Guards**: A live view of every active/degraded stage, with protection against mutually exclusive effects (e.g. ReplayGain vs bit-perfect).
- **Audiophile Playback Controls**: Gapless playback with encoder-delay trims, crossfade transitions (curves + BPM sync), variable pitch/playback speed, A-B loop, per-track delay, long-form bookmarks, silence skip, SponsorBlock auto-skip, and sleep timer (duration / end of track / after N tracks / end of queue).

### 💎 2. Aura Dynamic Design System
- **Album-Art Color Extraction**: Dynamic UI palettes generated in real time from album artwork using `palette_generator`.
- **8 Now Playing Themes**:
  1. *Classic Glassmorphism*: Deep blur overlays and ambient neon glow.
  2. *Minimalist*: Clean typography and distraction-free audio controls.
  3. *Card Deck*: Tactile card elevation with swipeable queue gestures.
  4. *Modern Vinyl / Circle*: Rotating vinyl turntable with acoustic concentric rings.
  5. *Retro Cassette Deck*: Spinning spools and a magnetic tape counter.
  6. *Full-Bleed Waveform*: Audio-reactive glowing waveform backdrop.
  7. *Karaoke Lyrics Immersion*: Magnified, lyrics-first singing view.
  8. *Custom Theme Studio*: Build, export and share your own player theme.
- **AMOLED Pure Black & Light Modes**: True `#000000` AMOLED mode plus a high-contrast accessibility theme.
- **Edge-to-Edge Experience**: Fully transparent status bar and gesture navigation bar on Android 14+.
- **Theme Scheduler**: Optional automatic light/dark switching by time of day.

### ⚡ 3. SQLite-Indexed Smart Music Library
- **Blazing Fast Scanning**: Powered by Drift SQLite, scanning and indexing 10,000+ local tracks in under 2 seconds.
- **Multi-Dimensional Navigation**: Browse by *Songs, Albums, Artists, Genres, Folders, Playlists, Years, and Favorites*.
- **Advanced Folder Browser**: Flat or hierarchical folder tree with breadcrumbs, `.nomedia` compliance and custom blacklist folder exclusions.
- **Intelligent Search**: FTS5 full-text search with Arabic diacritic/Latin accent normalization plus whole-library fuzzy fallback.
- **Smart Auto-Playlists**: *Most Played, Recently Added, Recently Played, Forgotten Gems, Top Rated, Long Tracks* — plus a rule builder with combined criteria including BPM.
- **Library Power Tools**: Duplicate finder with keep/delete resolution, missing-artwork online backfill, full-library statistics, an artwork wall, and **CUE sheet playback** (single-file album images expand into virtual tracks).
- **Three Independent Queues**: Persisted queue slots with drag reorder, add-next/add-last, and YTM session position restore.
- **Internet Radio**: Add HTTP/HTTPS stream URLs (with `.m3u` stream-list import) and play them with a dedicated radio management screen.

### 🎤 4. Millisecond Synced LRC Lyrics
- **Kinetic Karaoke Autoscroll**: Millisecond-precision scrolling that tracks the active vocal line, with a dedicated full-screen karaoke view.
- **Interactive Tap-to-Seek**: Tap any lyric line to jump directly to that song timestamp.
- **Offset Calibration**: On-the-fly latency adjuster (±50ms steps) to fix out-of-sync files.
- **Universal Fallback**: Automatic detection of external `.lrc` files, embedded ID3 tags, LRCLIB, YouTube Music, and unsynced plain text lyrics.
- **Lyrics Editor**: Edit and persist synced lyrics to a sidecar `.lrc` file.

### 🏷️ 5. Embedded ID3 & Cover Art Editor
- **Direct In-Place Editing**: Modify Title, Artist, Album, Genre, Year, Track Number, and Disc Number directly in the audio files, including batch multi-select editing.
- **Artwork Injector**: Pick high-res album covers from your gallery or camera and embed them into MP3, FLAC, M4A, OGG, and WAV containers, with optional online metadata matching.

### 📱 6. Deep Android OS Integration
- **Android Home Screen Widgets**: Interactive home screen playback widgets (`home_widget`) with live album art and transport controls.
- **MediaStyle Notifications**: Full notification shade and lockscreen controls with real-time seekbars.
- **Hardware & Headset Events**: Auto-pause on headphone disconnection, Bluetooth AVRCP metadata sync, and audio ducking during GPS navigation/calls.
- **Audio File Intent Handler**: Instantly opens and plays `.mp3`, `.flac`, `.wav`, `.m4a` files opened from file managers or chat apps.

### 🛡️ 7. Privacy-First & Offline-Capable
- **Pulsr Pure (prod flavor) — 100% Offline Operation**: No account creation, no `INTERNET` permission, no trackers, and no ad SDKs. All online initializers are skipped at startup.
- **Standard builds** optionally use network for YouTube Music streaming/downloads, artwork/lyrics metadata, scrobbling, and cloud backup — all gated behind `Offline-only mode` in Settings.
- **Data Safety**: All library indexes, ratings, and playlists remain strictly on your device unless you opt into cloud sync.

### 📡 8. Pulsr Pure & Pulsr Plus (Optional Online)
- **Pulsr Pure**: The Play-Store build ships with the `INTERNET` permission removed at the manifest level, no Firebase/Sentry, and no YouTube code.
- **Pulsr Plus (`ENABLE_YTM=true`)**: Optional account sign-in, search, browse, real radio/mixes, streaming and offline downloads, gated behind a build flag so production builds never expose it.
- **Downloads Manager**: Queue/pause/resume/retry with storage stats and MediaStore export, plus proxy/Wi-Fi-only/adaptive-quality controls.

### 🔄 9. Sync, Scrobble & Automate
- **Scrobbling**: Direct-API Last.fm and ListenBrainz scrobbling with a resilient offline queue and a listening-stats dashboard.
- **Optional Cloud Backup**: Google sign-in to sync favorites and playlists to Firestore — inactive in Pure builds, opt-in elsewhere.
- **Device Profiles**: Auto-apply EQ, effects and output settings per connected device, with Bluetooth/headphone automation triggers.
- **Settings Profiles**: Save and recall complete configuration bundles.

### 🌍 10. Localization
- Full English, Spanish and Arabic (RTL) UI with an in-app language switcher.

---

## 🎧 Headphone Calibration & AutoEQ

Pulsr includes built-in parametric target profiles based on the AutoEQ database and Harman research:

| Profile | Category | Target Curve / Focus | Preamp |
|---|---|---|---|
| **Harman In-Ear (2019)** | Target Curve | Harman Target In-Ear Benchmark | -3.5 dB |
| **Harman Over-Ear (2018)**| Target Curve | Harman Acoustic Target (Over-Ear) | -2.5 dB |
| **Apple AirPods Pro (2nd Gen)** | TWS Earbuds | Neutralized mids + sub-bass extension | -1.5 dB |
| **Apple AirPods Max** | Over-Ear | High-frequency smoothing | -1.5 dB |
| **Sony WH-1000XM5** | Over-Ear ANC | Mid-bass de-bloat & vocal clarity | -2.0 dB |
| **Sony WF-1000XM4** | TWS Earbuds | Upper-treble resonance compensation | -2.0 dB |
| **Sennheiser HD 600** | Open-Back | Sub-bass extension + neutral midrange | -1.5 dB |
| **Beyerdynamic DT 770 Pro** | Studio Monitor| Treble spike smoothing at 6-8kHz | -3.0 dB |
| **Club Bass Boost** | Dynamic DSP | Elevated sub-bass & punchy 60-120Hz | -3.0 dB |
| **Studio Flat** | Bypass | 0dB Bit-perfect neutral bypass | 0.0 dB |

---

## 🏗️ Architecture & Tech Stack

Pulsr is architected around **Clean Architecture** and the **BLoC (Cubit)** state management pattern to ensure testability, separation of concerns, and rock-solid reliability.

```
┌─────────────────────────────────────────────────────────────┐
│                      PRESENTATION LAYER                     │
│  Flutter Widgets • Aura Design Tokens • GoRouter Navigation  │
│  LibraryCubit • PlayerCubit • PlaylistCubit • SettingsCubit │
└──────────────────────────────┬──────────────────────────────┘
                               │ (calls use cases)
┌──────────────────────────────▼──────────────────────────────┐
│                         DOMAIN LAYER                        │
│  Entities • Use Cases (Search, Playlists, Scanners, Audio)  │
│  Repository Interfaces • Functional Failure Types (fpdart)  │
└──────────────────────────────┬──────────────────────────────┘
                               │ (implements interfaces)
┌──────────────────────────────▼──────────────────────────────┐
│                          DATA LAYER                         │
│  Drift SQLite Database • Media Scanner • AudioHandler (DSP) │
│  JustAudio Player • AudioSession • HomeWidget Service       │
└─────────────────────────────────────────────────────────────┘
```

### Tech Stack Summary
- **UI Framework**: [Flutter 3.x](https://flutter.dev) & [Dart 3.x](https://dart.dev)
- **State Management**: [`flutter_bloc`](https://pub.dev/packages/flutter_bloc) (Cubit)
- **Database & Persistence**: [`drift`](https://pub.dev/packages/drift) (Type-safe SQLite) + [`shared_preferences`](https://pub.dev/packages/shared_preferences)
- **Audio Engine**: [`just_audio`](https://pub.dev/packages/just_audio), [`audio_service`](https://pub.dev/packages/audio_service), [`audio_session`](https://pub.dev/packages/audio_session)
- **Media Indexing**: [`on_audio_query`](https://pub.dev/packages/on_audio_query) + direct Storage File Scanner
- **Dynamic Palette**: [`palette_generator`](https://pub.dev/packages/palette_generator)
- **Animations**: [`flutter_animate`](https://pub.dev/packages/flutter_animate)
- **Routing**: [`go_router`](https://pub.dev/packages/go_router)
- **Dependency Injection**: [`get_it`](https://pub.dev/packages/get_it) + [`injectable`](https://pub.dev/packages/injectable)
- **Code Generation**: [`build_runner`](https://pub.dev/packages/build_runner), [`freezed`](https://pub.dev/packages/freezed), [`drift_dev`](https://pub.dev/packages/drift_dev)
- **Functional Programming**: [`fpdart`](https://pub.dev/packages/fpdart)

---

## 📁 Project Structure

```
pulsr/
├── assets/
│   ├── app_icon/             # High-res SVG and PNG app icons
│   ├── eq_profiles/          # AutoEQ headphone JSON calibrations
│   └── fonts/                # Manrope variable typography
├── docs/
│   ├── PULSR_FEATURES_SPEC.md      # Master feature spec + gap audit & remediation status
│   ├── AUDIO_INTERRUPT_MATRIX.md   # Audio focus & ducking test matrix
│   └── PLAY_CONSOLE_READINESS.md   # Google Play data safety & compliance audit
├── RUNBOOK.md                      # Build, release & troubleshooting runbook
├── lib/
│   ├── core/
│   │   ├── config/           # App constants & Sentry crash config
│   │   ├── constants/        # Color tokens, radii, metrics
│   │   ├── di/               # GetIt dependency injection setup
│   │   ├── router/           # GoRouter route definitions
│   │   ├── services/         # File intent handler & restore detection
│   │   └── theme/            # AuraTheme tokens & DynamicThemeCubit
│   ├── data/
│   │   ├── audio/            # JustAudio handler, Equalizer DSP & queue
│   │   ├── db/               # Drift SQLite schema & DAOs
│   │   ├── models/           # Song, Album, Artist, Playlist models
│   │   ├── repositories/     # Concrete MusicRepository implementation
│   │   └── scanner/          # MediaStore & direct file scanner
│   ├── domain/
│   │   ├── entities/         # Core domain entities
│   │   ├── repositories/     # Abstract repository interfaces
│   │   └── usecases/         # Business logic & query use cases
│   ├── features/
│   │   ├── home/             # Dashboard, recent tracks & quick picks
│   │   ├── library/          # Songs, Albums, Artists, Folders tabs
│   │   ├── player/           # Now Playing screen, 4 themes, DSP sheets
│   │   ├── playlists/        # Custom & Smart playlist manager
│   │   ├── queue/            # Interactive queue manager
│   │   ├── search/           # Instant fuzzy search
│   │   ├── settings/         # Equalizer, backup/restore, blacklist
│   │   └── tag_editor/       # In-place ID3 tag & cover art editor
│   ├── l10n/                 # ARB localizations (EN, ES, AR)
│   └── main.dart             # App entrypoint & initialization
├── test/                     # Unit, Cubit & Repository tests
├── website/                  # Landing website & interactive sandbox
│   ├── assets/               # Branding vectors
│   ├── index.html            # Landing page markup
│   ├── styles.css            # Aura glassmorphism stylesheet
│   └── app.js                # Interactive player & EQ canvas logic
└── pubspec.yaml              # Package dependencies & assets config
```

---

## 📚 Documentation

| Document | Purpose |
|---|---|
| [`docs/PULSR_FEATURES_SPEC.md`](docs/PULSR_FEATURES_SPEC.md) | Master spec for every feature, its functions and wiring, plus the prioritized gap audit and remediation status. |
| [`docs/POWERAMP_COMPARISON.md`](docs/POWERAMP_COMPARISON.md) | Feature-by-feature comparison against Poweramp v3. |
| [`docs/POWERAMP_PARITY_PLAN.md`](docs/POWERAMP_PARITY_PLAN.md) | Execution-ready plan to close the Poweramp gaps (workstreams, native contracts, tests). |
| [`docs/AUDIO_INTERRUPT_MATRIX.md`](docs/AUDIO_INTERRUPT_MATRIX.md) | Audio focus, interruption and ducking test matrix. |
| [`docs/PLAY_CONSOLE_READINESS.md`](docs/PLAY_CONSOLE_READINESS.md) | Google Play data-safety and permission compliance audit. |
| [`RUNBOOK.md`](RUNBOOK.md) | Build, release and troubleshooting runbook. |

---

## 🚀 Getting Started & Build Guide

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (`>= 3.24.0` / Dart `>= 3.5.0`)
- [Android Studio](https://developer.android.com/studio) with Android SDK & NDK
- Java Development Kit (JDK 17)

### 1. Clone & Install Dependencies
```bash
git clone https://github.com/DevEslam1/pulsr.git
cd pulsr
flutter pub get
```

### 2. Run Code Generation
Generate Drift SQLite database code, Freezed models, and Injectable DI bindings:
```bash
dart run build_runner build --delete-conflicting-outputs
```

### 3. Run in Debug Mode
Connect an Android device or emulator with USB debugging enabled:
```bash
flutter run
```

### 4. Run Automated Tests
Execute unit tests, Cubit state tests, and repository mocks (800+ tests):
```bash
flutter test
```
Static analysis should be clean:
```bash
flutter analyze
```

### 5. Build Release Artifacts

> **Production builds must pass `--dart-define=ENV=prod`** so the Dart layer runs in production mode (correct app title, reduced Sentry trace sampling). Sentry only initializes when a DSN is supplied via `--dart-define=SENTRY_DSN=<your-dsn>`; omit it to build without crash reporting. The Gradle `--flavor prod` alone does **not** set the Dart environment.

#### Build Universal APK
```bash
flutter build apk --flavor prod --release --dart-define=ENV=prod --dart-define=SENTRY_DSN=$SENTRY_DSN
```
*Output: `build/app/outputs/flutter-apk/app-prod-release.apk`*

#### Build Split Per-ABI APKs (Smaller file size)
```bash
flutter build apk --flavor prod --release --split-per-abi --dart-define=ENV=prod --dart-define=SENTRY_DSN=$SENTRY_DSN
```

#### Build Google Play App Bundle (AAB)
```bash
flutter build appbundle --flavor prod --release --dart-define=ENV=prod --dart-define=SENTRY_DSN=$SENTRY_DSN
```
*Output: `build/app/outputs/bundle/prodRelease/app-prod-release.aab`*

---

## 🔒 Privacy & Permissions Matrix

Pulsr adheres strictly to Google Play Store data safety and permission guidelines:

| Permission | Android Level | Category | Usage Justification |
|---|---|---|---|
| `READ_MEDIA_AUDIO` | API 33+ (Android 13+) | Storage | Discover and index user audio files locally. |
| `READ_EXTERNAL_STORAGE` | API &le; 32 (Legacy) | Storage | Read audio files on older Android devices. |
| `WRITE_EXTERNAL_STORAGE` | API &le; 29 (Legacy) | Storage | Save edited tags / exported artwork on pre-scoped-storage devices. |
| `FOREGROUND_SERVICE` | API 28+ | Background | Continuous audio playback while the screen is locked. |
| `FOREGROUND_SERVICE_MEDIA_PLAYBACK` | API 34+ (Android 14+) | Background | Mandated by Android 14 for media player services. |
| `POST_NOTIFICATIONS` | API 33+ | Notifications| Display MediaStyle playback controls and scrub bars. |
| `RECORD_AUDIO` | All | Optional | Live audio visualizer DSP analysis *(Denied fallback: synthetic waveforms)*. |
| `MODIFY_AUDIO_SETTINGS` | All | Playback | Configure the equalizer and audio output session. |
| `WRITE_SETTINGS` | All | Optional | Set a track as the system ringtone *(user-initiated only, runtime-gated)*. |
| `WAKE_LOCK` | All | Playback | Prevents CPU sleep while streaming local audio. |
| `INTERNET` | All (removed in Pure/prod) | Network | YTM streaming, artwork/lyrics metadata, scrobbling, cloud sync. Not present in Pulsr Pure. |
| `FOREGROUND_SERVICE_DATA_SYNC` | API 34+ | Background | Keeps YTM downloads alive (removed in Pure/prod). |
| `BLUETOOTH_CONNECT` / `BLUETOOTH` | API 31+ / ≤30 | Playback | A2DP device names and codec info for Hi-Res output. |

---

## 🌍 Localization (i18n)

Pulsr natively supports multiple languages with full RTL layout support:
- 🇺🇸 **English** (`en`)
- 🇪🇸 **Spanish** (`es`)
- 🇸🇦 **Arabic** (`ar` - Right-to-Left)

---

## 📄 License

This project is free software licensed under the **[GNU General Public License v3.0](LICENSE)**.

```
Copyright (C) 2026 Pulsr Music Contributors.

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.
```

> **Why GPLv3?** The YouTube Music integration is powered by [NewPipeExtractor](https://github.com/TeamNewPipe/NewPipeExtractor), which is licensed under GPLv3. Linking it obliges the combined work to be released under the same license, so Pulsr as a whole is GPLv3.

---

<div align="center">
  <sub>Crafted with passion for pure sound and design perfection.</sub>
</div>
