# CLAUDE.md — Pulsr Music Codebase & Architecture Guide

> **Target Audience:** AI Models (Claude, Gemini, Cursor, Copilot) & Human Engineers  
> **Repository:** `pulsr` — Premium Offline-First Audiophile Music Player  
> **Frameworks & Languages:** Flutter 3.41+ (Dart >=3.0 <4.0), C++17 (Native DSP Engine), Kotlin (Android Platform Channels), Go 1.22+ (Party Sync Server), GLSL (Custom Shaders).

---

## 1. System Overview & Architecture

**Pulsr Music** is a high-performance, offline-first audiophile music player for Android, desktop, and web with integrated YouTube Music streaming/downloading, real-time synchronized group listening ("Pulsr Party"), and a custom C++ real-time Digital Signal Processing (DSP) audio engine.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            PRESENTATION LAYER                               │
│  GoRouter · AppShell · MiniPlayer · NowPlayingScreen (9 Skeuomorphic Themes)│
│  BLoC / Cubits: PlayerCubit, LibraryCubit, SettingsCubit, DownloadsCubit... │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
┌──────────────────────────────────────▼──────────────────────────────────────┐
│                              DOMAIN LAYER                                   │
│  Entities (Freezed) · Clean Interfaces · Granular UseCases                  │
│  SmartAudioPlan · HeadphoneDeviceMatcher · SmartPlaylistCriteria            │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
┌──────────────────────────────────────▼──────────────────────────────────────┐
│                               DATA LAYER                                    │
│  Drift SQLite DB · MusicRepository · MediaScanner · DownloadRepository      │
│  PulsrAudioHandler (audio_service) · Collaborative Audio Controllers        │
└──────────────────┬────────────────────────────────────────┬─────────────────┘
                   │                                        │
┌──────────────────▼──────────────────┐  ┌──────────────────▼─────────────────┐
│     NATIVE C++ DSP ENGINE           │  │      PULSR PARTY SERVER (GO)       │
│  libpulsr_dsp (CMake / JNI)         │  │  server/pulsr_party                │
│  AAudioSink · Bit-Perfect USB DAC   │  │  Low-Drift Clocks · WebSockets     │
│  PEQ · Convolution · ViPER-DDC      │  │  Real-Time Room Synchronizer       │
└─────────────────────────────────────┘  └────────────────────────────────────┘
```

### Core Architecture Patterns
1. **Clean Architecture & Feature-Driven Structure:** Code is divided into `core/`, `data/`, `domain/`, and `features/`. Every feature encapsulates its own presentation, state (Cubit), and private sub-widgets.
2. **State Management:** `flutter_bloc` (`Cubit` pattern) with `freezed` immutable states. Side effects and async guards are managed via functional programming concepts (`fpdart` / `Result<T>`).
3. **Dependency Injection:** `get_it` + `injectable` (`lib/core/di/injection.dart`). All major services, repositories, and handlers are registered as lazy singletons or factories.
4. **Local Database:** `drift` (SQLite ORM) with type-safe queries, streams, reactive tables, and automated schema migration.
5. **Dual Audio Playback Pipelines:**
   - **ExoPlayer / Media3 (via vendored `just_audio`):** Standard playback with decoded PCM stream forwarded directly to `libpulsr_dsp`.
   - **Native Low-Latency AAudio / USB Exclusive Engine:** Directly buffers PCM audio from C++ sinks to hardware endpoints without Android audio flinger resampling.

---

## 2. Core Feature Matrix

| Feature Domain | Capabilities & Implementation Details | Key Files |
| :--- | :--- | :--- |
| **Audiophile Playback** | Bit-perfect playback, gapless playback, crossfade state machine, ReplayGain (EBU R128), A/B loop, dynamic silence skip, sleep timer with gradual volume fade, DoP/DSD decoder, MQA helper, and CUE sheet parsing. | `lib/data/audio/` |
| **Native C++ DSP Engine** | 10-band graphic & arbitrary frequency EQ, 128-band parametric EQ, convolution reverb (IR files), lookahead peak limiter, multiband compressor, dynamic bass boost, loudness contour, sinc resampler, spatial panner, stereo widener, ViPER-DDC presets, and LiveProg JSFX scripting. | `android/app/src/main/cpp/`, `lib/features/player/cubit/controllers/` |
| **Local Music Library** | Complete MediaStore & filesystem scanner, metadata enrichment, embedded ID3 tag editor with artwork extraction, album/artist/genre/folder/year indexer, duplicate audio finder, and library statistics. | `lib/data/scanner/`, `lib/features/library/`, `lib/features/tag_editor/` |
| **YouTube Music Integration** | InnerTube catalog search, stream pre-resolution, chunked background audio downloader with resumable storage, rate limiting, circuit breaker, OAuth / WebView session login, and geo-block recovery. | `lib/core/services/ytm_*`, `lib/core/services/yt_download_*`, `lib/features/ytm_search/` |
| **Skeuomorphic Player Themes** | 9 distinct Now Playing designs: Vinyl Deck (spinning disc), Cassette Tape (custom animated spools), CD Player (reflective surface), Circle, Classic, Minimal, Card, Waveform, and Lyrics-focused. Custom Theme Builder included. | `lib/features/player/presentation/themes/` |
| **Synchronized Lyrics & Karaoke** | Real-time synchronized LRC parser, LRCLIB API client, millisecond offset manual editor, multi-language lyrics translation, lyric card sharing, and Karaoke mode screen. | `lib/data/lyrics/`, `lib/features/player/presentation/widgets/lyrics*` |
| **Pulsr Party (Listen Together)** | Low-latency room-based group listening over WebSockets; sub-millisecond drift clock synchronization, host-only or democratic queue control. | `server/pulsr_party/`, `lib/data/party/`, `lib/features/party/` |
| **Visualizers & Shaders** | Real-time audio reactive Milkdrop visualizer powered by a custom OpenGL fragment shader (`shaders/milkdrop.frag`) and platform audio visualizer taps. | `shaders/milkdrop.frag`, `lib/features/player/presentation/widgets/visualizer/` |
| **Smart Playlists** | Dynamic rule-based query engine filtering by play count, rating, bitrate, date added, duration, genre, and artist. | `lib/data/repositories/smart_playlist_engine.dart`, `lib/features/smart_playlist_builder/` |
| **Quran Mode** | Specialized recitation experience with surah/ayah tracking, dedicated audio profiles, bookmarking, and automated state restoration. | `lib/core/services/quran_mode_service.dart`, `lib/features/quran_mode/` |
| **System Integrations** | Android home-screen widgets (`home_widget`), Last.fm & ListenBrainz scrobbling, Discord Rich Presence, SponsorBlock segment skipping, AutoEq headphone profile auto-matcher, and Bluetooth latency calibration. | `lib/core/services/`, `lib/services/` |

---

## 3. Top-Level Directory Layout

```
pulsr/
├── android/                 # Android native runner, Kotlin plugins & C++ DSP engine
│   └── app/src/main/
│       ├── cpp/             # C++ DSP engine (AudioDspEngine, AAudio, PEQ, Reverb)
│       └── kotlin/          # MethodChannel plugins (USB DAC, Visualizer, Scrobbler)
├── assets/                  # App icons, headphone AutoEq profiles, fonts (Manrope)
├── lib/                     # Main Flutter Dart codebase
│   ├── core/                # Cross-cutting foundational modules, DI, router, base widgets
│   ├── data/                # Database, repositories, audio player implementation, scanner
│   ├── domain/              # Entities, interfaces, use cases, domain services
│   ├── features/            # Feature-first presentation & BLoC state modules
│   ├── l10n/                # Localization ARB files (en, ar, es) & generated code
│   └── services/            # Standalone services (Discord RPC, Canvas video, Updater)
├── scripts/                 # Test runners, audio gap analysis, AutoEq dataset tools
├── server/pulsr_party/      # Go 1.22 real-time group listening backend
├── shaders/                 # GLSL fragment shaders (milkdrop.frag)
└── third_party/             # Vendored just_audio fork with native PCM hook & Media3
```

---

## 4. Detailed File-by-File Breakdown & Responsibilities

### 4.1 Root Entrypoint & Configuration
- **`lib/main.dart`**: Application entrypoint. Configures image cache memory limits, global HTTP overrides (`AppHttpOverrides`), dependency injection (`configureDependencies()`), Sentry crash logging, global error boundary (`ErrorWidget.builder`), BLoC multi-providers (`PlayerCubit`, `LibraryCubit`, `SettingsCubit`, etc.), dynamic color extraction, and localized MaterialApp.
- **`lib/firebase_options.dart`**: Auto-generated Firebase configuration options for Android/iOS.

---

### 4.2 `lib/core/` — Foundational Utilities & Infrastructure

#### `core/config/`, `core/constants/`, `core/di/`, `core/errors/`
- **`core/config/app_config.dart`**: Runtime environment parameters, release flags, and startup validation logic.
- **`core/constants/app_colors.dart`**: Color tokens, dynamic theme surface palettes, and contrast ramps.
- **`core/constants/app_typography.dart`**: Manrope font styles, line heights, and letter spacing tokens.
- **`core/constants/app_spacing.dart` & `app_radii.dart`**: Layout grids, padding scales, and corner radii.
- **`core/constants/app_timing.dart` & `core/motion/pulsr_motion.dart`**: Standard animation curves and durations.
- **`core/constants/audio_formats.dart`**: Audio format definitions (FLAC, MP3, AAC, ALAC, DSD, WAV, OGG, Opus).
- **`core/constants/audio_feature_info.dart`**: Informational text and tooltips for audiophile toggles.
- **`core/constants/prefs_keys.dart`**: Centralized keys for `SharedPreferences`.
- **`core/constants/pulsr_icons.dart` & `app_icons.dart`**: Custom icon sets and glyphs.
- **`core/di/injection.dart`**: Service locator setup using `GetIt`. Registers singletons, audio handlers, cubits, and pre-warms critical async services.
- **`core/errors/failures.dart` & `app_error.dart`**: Sealed failure hierarchy (`AudioFailure`, `StorageFailure`, `NetworkFailure`).
- **`core/errors/error_message_resolver.dart`**: Translates internal error codes into localized user-friendly messages.
- **`core/errors/ytm_error_classifier.dart`**: Classifies network and YouTube Music HTTP failures (Geo-block, Rate-limit, IP-ban).

#### `core/network/`, `core/performance/`, `core/responsive/`, `core/router/`
- **`core/network/app_http_overrides.dart`**: Custom HTTP client override supporting proxy bypass and user-agent spoofing.
- **`core/network/proxy_config.dart` & `network_change_monitor.dart`**: SOCKS5/HTTP proxy settings and network connectivity transition listeners.
- **`core/performance/gpu_budget.dart`**: Controls frame rate limits and shader complexity based on device capability.
- **`core/responsive/breakpoints.dart`**: Screen size thresholds for phone, foldables, tablets, and desktop.
- **`core/responsive/two_pane_scaffold.dart` & `detail_scaffold.dart`**: Responsive layouts for large screens/foldables.
- **`core/responsive/pulsr_fluid_scale.dart` & `pulsr_typography.dart`**: Dynamic font and layout scaling calculations.
- **`core/router/app_router.dart`**: GoRouter routing tree, shell route configuration, page transitions (`PulsrMotion.page`), and route guards.
- **`core/router/safe_navigation.dart`**: Guards against duplicate navigation and invalid push actions.

#### `core/services/` (Cross-Cutting Core Services)
- **`core/services/artist_bio_service.dart`**: Fetches artist biographies and summaries from online APIs.
- **`core/services/artwork_cache_manager.dart`**: Disk and memory caching for embedded and remote artwork.
- **`core/services/auth_service.dart`**: Firebase Authentication and user profile state management.
- **`core/services/automation_rules_service.dart` & `automation_trigger_service.dart`**: Event triggers (headphone connect, time of day, charging) to execute playback rules.
- **`core/services/battery_optimization_service.dart`**: Checks and prompts for Android battery optimization exemptions.
- **`core/services/bluetooth_latency_calibrator.dart`**: Audio-latency calibration tool for Bluetooth headsets.
- **`core/services/chain_of_custody_service.dart`**: Diagnostic trace verifying audio sample rate and bit-depth from source to DAC output.
- **`core/services/cloud_sync_service.dart`**: Cloud backup and synchronization of user playlists, favorites, and settings.
- **`core/services/device_profile_service.dart`**: Saves distinct EQ and volume presets per connected audio output device.
- **`core/services/duplicate_finder_service.dart`**: Identifies duplicate songs based on duration, title, and audio fingerprints.
- **`core/services/file_intent_handler.dart`**: Handles opening audio files sent from external apps (e.g. file managers).
- **`core/services/hires_audio_service.dart`**: Detects 24-bit/96kHz+ tracks and monitors DAC sample rate output.
- **`core/services/library_cache_manager.dart`**: In-memory caching layer for instant library screen rendering.
- **`core/services/lrclib_service.dart`**: Client for the open-source LRCLIB lyrics API.
- **`core/services/missing_artwork_service.dart`**: Scans and fetches missing cover art online.
- **`core/services/playlist_suggestions_service.dart`**: Recommends tracks to add to playlists based on audio attributes.
- **`core/services/quran_mode_service.dart`**: Manages Quran mode active state, recitation playback rate, and reciter profiles.
- **`core/services/radio_station_store.dart`**: Curated internet radio stations directory.
- **`core/services/room_correction_service.dart`**: Computes room acoustic impulse response filters.
- **`core/services/scrobbler_service.dart`**: Scrobbler dispatcher for Last.fm and ListenBrainz.
- **`core/services/settings_cache.dart` & `settings_profiles_service.dart`**: Quick-access settings cache and configuration profiles.
- **`core/services/smart_audio_service.dart`**: Evaluates audio hardware capabilities and configures the optimal playback plan.
- **`core/services/sound_dose_tracker_service.dart`**: Monitors volume levels and listening time to prevent hearing fatigue (WHO standard).
- **`core/services/sound_feedback_service.dart`**: Plays subtle haptic and sound effects on UI interactions.
- **`core/services/sponsorblock_service.dart`**: Queries and skips non-music segments (intros, outros, ads) in online tracks.
- **`core/services/theme_scheduler_service.dart`**: Automatically switches themes based on sunrise/sunset or system schedule.
- **`core/services/waveform_service.dart`**: Computes and caches visual waveform peaks for audio files.
- **`core/services/ytm_service.dart`, `ytm_browse_service.dart`, `ytm_account_service.dart`**: Core YouTube Music API clients.
- **`core/services/ytm_oauth_service.dart` & `ytm_client_version_resolver.dart`**: Handles InnerTube authentication tokens and client version spoofing.
- **`core/services/yt_download_service.dart`**: Multithreaded background audio downloader with chunking and tag writing.

#### `core/utils/` & `core/widgets/`
- **`core/utils/yin_pitch_detector.dart`**: YIN pitch detection algorithm for live vocal pitch tracking in Karaoke mode.
- **`core/utils/lrc_parser.dart` & `cue_parser.dart`**: High-performance parsers for `.lrc` lyrics files and `.cue` sheet audio splits.
- **`core/utils/pulsr_haptics.dart` & `haptic_patterns.dart`**: Native haptic feedback orchestration.
- **`core/utils/song_classification.dart`**: Helper to categorize songs (Classical, Podcast, Quran, Music) by length and tags.
- **`core/widgets/glass_container.dart`**: Frosted glass container with real-time backdrop blur.
- **`core/widgets/spinning_vinyl_disc.dart`**: Realistic spinning vinyl record with grooved texture and center label.
- **`core/widgets/marquee_text.dart`**: Smooth scrolling marquee for long track and artist titles.
- **`core/widgets/song_tile.dart`**: Standard track item tile with play indicator, popover menu, and artwork badge.
- **`core/widgets/pulsr_adaptive_sheet.dart` & `pulsr_bottom_sheet.dart`**: Fluid bottom sheet primitives.

---

### 4.3 `lib/data/` — Data Layer, Persistence & Audio Engine

#### `data/audio/` (The Audio Playback Core)
- **`data/audio/audio_handler.dart` (`PulsrAudioHandler`)**: Concrete `BaseAudioHandler` implementation interfacing with `audio_service`. Manages Android media notifications, lock screen playback controls, ExoPlayer state, and background foreground service.
- **`data/audio/collaborators/`**: Sub-controllers refactored from `PulsrAudioHandler` to maintain single responsibility:
  - `aaudio_output_controller.dart`: Controls direct AAudio output routing and low-latency flags.
  - `float_output_controller.dart`: Enforces 32-bit floating point audio rendering when supported.
  - `playback_preload_orchestrator.dart`: Manages preloading the next track in queue to guarantee zero-gap playback.
  - `playback_state_coordinator.dart`: Coordinates media state transitions (buffering, playing, paused, completed).
  - `playback_volume_controller.dart`: Handles software volume scaling, ducking, and ReplayGain volume multiplier.
  - `stream_resolution_pipeline.dart`: Resolves online audio streams with fallback mirrors.
- **`data/audio/equalizer_manager.dart`**: Coordinates graphic, parametric, and arbitrary EQ bands. Restores EQ states across app launches.
- **`data/audio/crossfade_manager.dart`**: Executes linear or exponential crossfading between consecutive tracks.
- **`data/audio/gain_staging_budget.dart` & `replay_gain_math.dart`**: Computes peak-normalized headroom to prevent digital clipping when applying heavy EQ bass boost.
- **`data/audio/headphone_profiles_repository.dart`**: Parses and provides over 4,000 AutoEq frequency compensation profiles for specific headphone models.
- **`data/audio/multi_output_router.dart`**: Listens to Android audio routing changes (Headphones plugged/unplugged, Bluetooth connected).
- **`data/audio/ab_loop_manager.dart`**: Precise A-B loop point management with microsecond accuracy.
- **`data/audio/silence_skip_controller.dart`**: Fast-forwards through dead silence at track starts and ends.
- **`data/audio/sleep_timer_manager.dart`**: Configurable sleep timer that fades audio volume to zero before pausing.
- **`data/audio/dop_encoder.dart` & `dsd_decoder_helper.dart`**: DSD-over-PCM (DoP) packing logic for native DSD playback on compatible USB DACs.
- **`data/audio/automix/bpm_detector.dart` & `automix_transition_planner.dart`**: Audio analysis detecting BPM and key to create seamless DJ-style automix transitions.

#### `data/db/` (Database & Tables)
- **`data/db/app_database.dart` (`AppDatabase`)**: The central Drift SQLite database instance. Exposes reactive streams (`watchSongs()`, `watchAlbums()`, `watchPlaylists()`).
- **`data/db/tables.dart`**: Schema definitions for all tables:
  - `SongsTable`: Local and online tracks with metadata, sample rate, bit depth, codec, CUE sheet bounds, ReplayGain, play count, and remote URL.
  - `AlbumsTable` & `ArtistsTable`: Normalized album and artist collections.
  - `PlaylistsTable` & `PlaylistEntriesTable`: User and smart playlists with sort orders.
  - `PlayHistoryTable`: Chronological play logs for statistics and scrobbling.
  - `QueueItemsTable`: Persisted playback queue state across application restarts.
  - `ExcludedFoldersTable`: Directories hidden or excluded from library scanning.

#### `data/repositories/` & `data/scanner/`
- **`data/repositories/music_repository.dart`**: High-level data accessor implementing `MusicRepositoryInterface`. Glues SQLite database queries with media scanner and audio cache.
- **`data/repositories/smart_playlist_engine.dart`**: Translates `SmartPlaylistCriteria` rules into Drift SQL queries.
- **`data/scanner/media_scanner_service.dart`**: Scans device storage using `on_audio_query`, extracts real metadata from file headers via native channels, and synchronizes the Drift database.

---

### 4.4 `lib/domain/` — Domain Entities, Interfaces & Use Cases

- **`domain/models/audio_effects_config.dart`**: Value object encapsulating all active DSP settings (EQ gains, compressor threshold, reverb size).
- **`domain/models/dsp_telemetry.dart`**: Live telemetry reports from the C++ DSP engine (CPU load, buffer underruns, output latency, sample rate).
- **`domain/models/eq_preset.dart`**: Preset model containing band frequency, gain, and Q-factor values.
- **`domain/models/lyrics_line.dart`**: Data model for a single timed lyric segment (`timestampMs`, `text`, `translation`).
- **`domain/models/smart_playlist_criteria.dart`**: Criteria models for dynamic smart playlists (e.g., `PlayCountFilter`, `GenreFilter`, `YearRangeFilter`).
- **`domain/usecases/`**: Granular single-purpose use case classes (`GetSongsUseCase`, `GetAlbumsUseCase`, `ToggleFavoriteUseCase`, `SearchMusicUseCase`, `QueueDownloadUseCase`, `ObserveDownloadsUseCase`, `PlaylistUseCases`, `FolderUseCases`).

---

### 4.5 `lib/features/` — Feature Modules & Presentation

#### `features/player/` (Now Playing UI & Player State)
- **`features/player/cubit/player_cubit.dart`**: Central coordinator for playback state. Subdivided via mixins:
  - `player_transport_mixin.dart`: Play, pause, seek, stop, toggle loop/shuffle.
  - `player_queue_mixin.dart`: Add to queue, move items, clear, save queue.
  - `player_dsp_mixin.dart`: Update EQ, change reverb, toggle limiter, adjust pitch/speed.
  - `player_playback_options_mixin.dart`: ReplayGain toggle, gapless toggle, silence skip, sleep timer.
- **`features/player/cubit/controllers/`**: Granular controllers handling specific player sub-tasks (`player_dsp_controller.dart`, `player_queue_controller.dart`, `player_lyrics_manager.dart`, `player_sponsorblock_manager.dart`, `player_quran_manager.dart`).
- **`features/player/presentation/now_playing_screen.dart`**: Main player screen supporting swipe-down dismissal, lyrics view, queue overlay, and responsive layouts.
- **`features/player/presentation/mini_player.dart`**: Persistent bottom mini player widget with progress bar, play/pause, and swipe to skip.
- **`features/player/presentation/themes/` (The 9 Player Themes)**:
  - `vinyl_player_theme.dart`: Realistic rotating vinyl record on turntable deck.
  - `cassette_player_theme.dart`: Retro cassette tape with spinning spools and magnetic tape rendering.
  - `cd_player_theme.dart`: Compact disc with iridescent rainbow reflection.
  - `circle_player_theme.dart`: Modern circular artwork layout with radial progress indicator.
  - `classic_player_theme.dart`: Standard high-density card and cover art view.
  - `minimal_player_theme.dart`: Clean, typography-first interface with discreet controls.
  - `card_player_theme.dart`: Elevated floating cover art card.
  - `lyrics_player_theme.dart`: Fullscreen scrolling lyrics with playback controls anchored at bottom.
  - `waveform_player_theme.dart`: Dynamic audio waveform track visualization.
  - `custom_theme_builder_screen.dart`: Visual tool allowing users to customize player layout and colors.
- **`features/player/presentation/widgets/`**:
  - `equalizer_sheet.dart` & `arbitrary_eq_sheet.dart`: Interactive 10-band & parametric EQ sliders with frequency curve preview (`eq_curve_visualizer.dart`).
  - `autoeq_search_sheet.dart`: Headphone search sheet to import AutoEq frequency profiles.
  - `compressor_limiter_sheet.dart`: Dynamic range compressor controls (Threshold, Ratio, Attack, Release).
  - `dsp_inspector_sheet.dart`: Live diagnostic view of the DSP processing chain and audio buffer status.
  - `lyrics_view.dart` & `advanced_lyrics_view.dart`: Karaoke-style auto-scrolling lyrics with tap-to-seek.
  - `lyrics_editor_sheet.dart`: Manual editor to fix lyric timing offsets.
  - `karaoke_mode_screen.dart`: Interactive sing-along screen with vocal pitch detector overlay.
  - `visualizer/milkdrop_renderer.dart`: OpenGL shader renderer drawing real-time visuals based on music frequencies.

#### `features/library/` (Local Music Collection)
- **`features/library/cubit/library_cubit.dart`**: Manages library filtering, sorting (Title, Artist, Album, Year, Date Added), and search query state.
- **`features/library/presentation/library_screen.dart`**: Main tabbed library (Songs, Albums, Artists, Playlists, Folders, Genres).
- **`features/library/presentation/widgets/folder_browser_tab.dart` & `folder_tree_browser_tab.dart`**: Hierarchical filesystem audio browser.
- **`features/library/presentation/duplicate_finder_screen.dart`**: Identifies duplicate files and offers batch cleanup.
- **`features/library/presentation/library_stats_screen.dart`**: Insights into total play time, most played artists, and library format breakdown (FLAC vs MP3).

#### `features/home/` (Discovery & Dashboard)
- **`features/home/presentation/home_screen.dart`**: Personalized home dashboard.
- Displays: `hero_mix_card.dart` (personalized mix), `quick_discovery_header.dart`, `recently_played_section.dart`, `recently_added_section.dart`, and online recommendations.

#### `features/playlists/` & `features/playlist_detail/`
- **`features/playlists/presentation/playlists_screen.dart`**: Grid/list of custom playlists, smart playlists, and favorites.
- **`features/playlists/presentation/widgets/spotify_import_dialog.dart`**: Imports public Spotify playlists via web scraping / metadata lookup.
- **`features/playlist_detail/presentation/playlist_detail_screen.dart`**: Playlist tracks, duration calculation, and reordering.
- **`features/smart_playlist_builder/`**: Interactive visual rule editor for building dynamic smart playlists.

#### `features/ytm_search/` & `features/ytm_browse/` & `features/downloads/`
- **`features/ytm_search/presentation/ytm_search_screen.dart`**: Real-time search interface for YouTube Music tracks, albums, and artists.
- **`features/ytm_browse/presentation/ytm_browse_screen.dart`**: Explores YouTube Music charts, new releases, and mood categories.
- **`features/downloads/presentation/downloads_screen.dart`**: Download queue dashboard with download speed, paused tasks, completed files, and disk storage stats.

#### `features/settings/` (65+ Configuration Screens & Sections)
- **`features/settings/presentation/settings_screen.dart`**: Central settings navigation hub.
- Sub-sections:
  - `audio_dsp_section.dart`: Native DSP engine controls, resampler quality, and limiter headroom.
  - `audio_output_section.dart`: Bit-perfect AAudio toggle, USB DAC exclusive mode, and floating-point audio.
  - `audio_gain_section.dart`: ReplayGain preamp gains for tagged and untagged tracks.
  - `appearance_section.dart`: Theme selection, dynamic color extraction, and OLED pure black mode.
  - `scrobbler_settings_modal.dart`: Last.fm and ListenBrainz account authentication.
  - `discord_rpc_sheet.dart`: Discord Rich Presence display settings.
  - `cloud_backup_dashboard_screen.dart`: Cloud database backup export/import.
  - `proxy_settings_screen.dart`: Custom SOCKS5/HTTP proxy setup.

#### `features/party/` & `features/quran_mode/` & `features/tag_editor/`
- **`features/party/presentation/party_sheet.dart`**: Join or host a "Pulsr Party" room with live sync status.
- **`features/quran_mode/presentation/quran_mode_screen.dart`**: Dedicated interface for Quran recitations with surah selector and bookmark manager.
- **`features/tag_editor/tag_editor_screen.dart`**: Direct ID3 tag editor (Title, Artist, Album, Genre, Year, Track Number, Artwork).

---

### 4.6 Native & Backend Subsystems

#### `android/app/src/main/cpp/` (Native C++ DSP Engine)
- **`AudioDspEngine.cpp / .h`**: Central DSP graph manager. Receives raw decoded PCM buffers from ExoPlayer or file streams and runs them through the active DSP chain.
- **`AAudioSink.cpp / .h`**: High-performance, low-latency audio output stream using the Android AAudio native API with `AAUDIO_PERFORMANCE_MODE_LOW_LATENCY`.
- **`UsbAudioSink.cpp / .h`**: Direct USB Audio Class 2.0 driver handling bit-perfect output directly to connected external DACs.
- **`ParametricEQ.cpp / .h` & `ArbitraryResponseEq.cpp / .h`**: Biquad IIR filter arrays providing parametric and arbitrary graphic EQ adjustments.
- **`ConvolutionReverb.cpp / .h`**: Frequency-domain FFT-based fast convolution engine for realistic acoustic impulse responses (IR).
- **`LookaheadLimiter.cpp / .h`**: Brickwall peak limiter with lookahead window to prevent digital clipping distortion.
- **`MultibandCompressor.cpp / .h`**: 4-band audio compressor with independent threshold, ratio, attack, and release parameters.
- **`DynamicBass.cpp / .h` & `DynamicEQ.cpp / .h`**: Psychoacoustic bass enhancer and dynamic EQ adjusting curve based on listening volume.
- **`LoudnessContour.cpp / .h`**: ISO 226 equal-loudness contour compensation for low-volume listening.
- **`SincResampler.cpp / .h`**: Bandlimited Kaiser-windowed sinc interpolation resampler for sample rate conversions.
- **`SpatialPanner.cpp / .h` & `StereoWidth.cpp / .h`**: Binaural spatial audio panner and M/S matrix stereo width expansion.
- **`ViperDdc.cpp / .h`**: Parser and convolver for ViPER4Android `.vdc` Device Dynamic Correction files.
- **`LiveProg.cpp / .h`**: Embedded JSFX-compatible dynamic audio scripting engine.
- **`DsdDecoder.cpp / .h`**: Converts 1-bit DSD (DSD64/DSD128/DSD256) bitstreams into 24-bit/32-bit linear PCM.
- **`aaudio_jni_bridge.cpp` & `eq_jni_bridge.cpp`**: JNI bridges binding C++ methods to Kotlin and Dart method channels.

#### `server/pulsr_party/` (Go Real-Time Group Listening Server)
- **`main.go`**: Entrypoint initializing the HTTP server and WebSocket upgrade endpoints (`/ws`).
- **`hub/hub.go`**: Central in-memory registry managing active party rooms and message fan-out.
- **`party/party.go`**: Room lifecycle manager maintaining current track, queue, playing state, host ID, and member permissions.
- **`clock/clock.go`**: Implements NTP-style timestamp exchange to establish sub-millisecond clock synchronization across clients over high-latency networks.
- **`protocol/protocol.go`**: JSON frame definitions (`welcome`, `sync`, `control`, `state`, `queue`, `ping`, `pong`).

#### `shaders/`
- **`shaders/milkdrop.frag`**: GLSL audio-reactive fragment shader drawing mesmerizing frequency visualizers.

---

## 5. Development Guidelines & Best Practices for AI Models

### 5.1 Code Generation Rules
1. **Never Bypass Freezed Immutability:** All domain state classes in `cubit/` must use Freezed annotations (`@freezed`). Always generate `.freezed.dart` classes using:
   ```bash
   flutter pub run build_runner build --delete-conflicting-outputs
   ```
2. **Preserve Audio Pipeline Headroom:** When modifying `AudioDspEngine` or `EqualizerManager`, verify that gain increases are matched with preamp attenuation in `GainStagingBudget` to avoid clipping.
3. **Keep Audio Handler Methods Non-Blocking:** `PulsrAudioHandler` and its collaborators run on the main platform thread. Never perform heavy file I/O or HTTP requests directly inside playback callbacks (`onPlay`, `onSkipToNext`); delegate them to background isolates or async services.
4. **Use Safe Navigation:** Always navigate via `context.go()` or `context.push()` using routes defined in `AppRouter`. Never instantiate screens with `Navigator.push(MaterialPageRoute(...))` directly.
5. **Database Queries:** When fetching library items, prefer reactive Drift streams (`watch()`) over one-shot futures (`get()`) so UI views update automatically on library scans or tag edits.
6. **Thread Safety in C++:** `AudioDspEngine::process()` runs on real-time audio threads. Never allocate heap memory (`new` / `malloc`), acquire blocking mutexes, or log to disk inside the DSP process loop.

---

## 6. Common Developer Commands

```bash
# Install dependencies
flutter pub get

# Run build_runner for Drift & Freezed code generation
flutter pub run build_runner build --delete-conflicting-outputs

# Watch build_runner for active development
flutter pub run build_runner watch --delete-conflicting-outputs

# Run Flutter linter & static analysis
flutter analyze

# Run all unit and widget tests
flutter test

# Run Go Party Server locally
cd server/pulsr_party && go run main.go

# Run native DSP smoke tests (requires Android NDK)
./scripts/run_native_dsp_tests.sh
```
