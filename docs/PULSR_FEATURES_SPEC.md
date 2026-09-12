# Pulsr Music — Master Feature Specification & Gap Audit

> Single source of truth for **every app feature**, the **functions** that implement it, the
> **best (gold-standard) behavior + wiring** it should have, and a **per-feature comparison**
> against the current codebase. Deficits are collected into a prioritized **Gap Register**
> (§30) and a phased **Implementation Roadmap** (§31).
>
> This document is the audit baseline. A remediation pass has since been applied to the
> codebase; completed/deferred items are marked in the **Implementation Status** table
> immediately below and cross-referenced by Gap ID.

---

## Implementation Status (remediation pass — 2026-09-12)

Legend: **DONE** = implemented/wired; **FIXED** = bug corrected; **CLEANED** = dead code
removed or made honest; **HONEST** = capability now reported truthfully; **SKIPPED** =
intentionally out of scope (Firebase/cloud, per project instruction); **DEFERRED** = not
done this pass, with reason.

| ID | Status | Result |
|---|---|---|
| F-01 | DONE | Onboarding copy standardized to 10-band EQ. |
| F-02 | DONE | Sentry gated on `isTelemetryAllowed`; Pure skips all online init. |
| F-03 | DONE | `scanProgress` surfaced in Settings via `StreamBuilder`. |
| F-04 | DONE | Router error page localized (en/es/ar). |
| F-05 | DONE | Duplicate Cleaner now has resolve actions. |
| F-06 | DONE | Home chips point at working tools. |
| F-07 | FIXED | Removed 1k cap in `GetSongsUseCase`; pagination works over full library. |
| F-08 | CLEANED | Removed unused batch/true-peak/LRA helpers. |
| F-09 | DONE | `clearNomediaCache()` invoked on rescan/auto-hide changes. |
| F-10 | DONE | "Remove missing files" action in Settings. |
| F-11 | FIXED | Select All resolves full library; batch actions fetch missing rows. |
| F-12 | DONE | Shared `song_classification.dart` used by Library tab and `/favorites`. |
| F-13 | DONE | Path-only folder aggregation + SQL-prefixed folder song watch. |
| F-14 | DONE | Genre hierarchy view toggle in Genres tab. |
| F-15 | DONE | Folder tree view toggle in Folders tab. |
| F-16 | FIXED | Fuzzy fallback scans the entire library (was first 300). |
| F-17 | DONE | BPM smart rule evaluates manual overrides (Dart post-filter, no migration). |
| F-18 | DONE | Playlist share routed through `PlaylistShareService`. |
| F-19 | DONE | "Suggested for you" section in Playlists. |
| F-20 | DEFERRED | `createPlaybackSnapshot` is referenced by tests; retained. |
| F-21 | CLEANED | Removed 4 unused audio collaborators. |
| F-22 | CLEANED | `StreamResolutionPipeline` retained (its `invalidateCache` is used). |
| F-23 | DONE | `AdvancedPlaybackBar` rendered in all 8 themes. |
| F-24 | DONE | Duplicate Finder uses DI, full library, delete/keep actions. |
| F-25 | DONE | Sleep timer end-of-queue mode wired and exposed in the sheet. |
| F-26 | DONE | Extended speed range (0.1–8.0x) toggle in Settings. |
| F-27 | DONE | Audio normalization toggle in Settings. |
| F-28 | DONE | "Save DSP settings for this album" action. |
| F-29 | DEFERRED | Native ReplayGain stage parity (documented as Dart-only). |
| F-30 | DONE | Karaoke screen has an entry point; fake score replaced with real progress. |
| F-31 | DONE | Lyrics editor reachable; edits persist to `.lrc` sidecar. |
| F-32 | DONE | 10/32-band toggle + custom frequency editor in EQ sheet. |
| F-33 | DONE | Manual preamp slider with clipping warning. |
| F-34 | CLEANED | Removed unused `applyGenreBasedEq`. |
| F-35 | DONE | Per-band mute/solo toggles in EQ sheet. |
| F-36 | DEFERRED | Test-referenced; retained. |
| F-37 | DONE | Room-correction merge with AutoEQ + FIR export wired. |
| F-38 | DONE | Device Profiles section re-mounted in Settings. |
| F-39 | DONE | Preamp persistence verified in restore path. |
| F-40 | DONE | MQA detection/unfold wired into source resolution; status reported honestly. |
| F-41 | HONEST | Native DSD/DoP documented as unsupported; encoder left dormant. |
| F-42 | DONE | Production backend abstraction removed; interface relocated to test seam. |
| F-43 | DONE | `trackSeed` passed to the visualizer per track. |
| F-44 | DEFERRED | Test-referenced; retained. |
| F-45 | CLEANED | Removed unused analytics error-counter methods. |
| F-46 | CLEANED | Removed `LatencyOptimizer` and its handler hook. |
| F-47 | DONE | Theme scheduler started and consumed; appearance toggle added. |
| F-48 | DONE | High-contrast theme toggle added. |
| F-49 | SKIPPED | Cloud Backup dashboard (Firebase/cloud out of scope). |
| F-50 | CLEANED | Deleted 7 dead settings section widgets. |
| F-51 | DONE | Privacy Guarantee and About tiles wired. |
| F-52 | DONE | Flagged sheets (cache/scrobbler/YTM/duration) + new UI localized en/es/ar. |
| F-53 | DONE | YTM moods use real bridge data; radio uses real mix with honest fallback. |
| F-54 | DONE | Metadata service docs corrected to iTunes-only. |
| F-55 | DONE | YTM cache size gated on YTM and refreshed after clear. |
| F-56 | SKIPPED | Cloud card in Pure (cloud out of scope). |
| F-57 | DONE | Bookmark controls added to Song Info. |
| F-58 | DONE | Missing-artwork backfill persists URLs to the albums table. |
| F-59 | DONE | Library Stats loads the full library for accurate totals. |
| F-60 | CLEANED | Removed dead `findDuplicatesSync`. |
| F-61 | CLEANED | Removed unused capability getters. |
| F-62 | DONE | Widget action whitelist + scheme filter. |
| F-63 | DONE | Automation triggers (Bluetooth/headphones) + rules UI. |
| F-64 | DONE | Bluetooth "Auto-calibrate" action wired (codec-derived estimate). |
| F-65 | CLEANED | Removed dead `SubsonicService` + DI registration. |
| F-66 | DONE | Pure builds skip all online/YTM/auth initializers at startup. |
| F-67 | DONE | SponsorBlock enable/category controls in Settings. |

**Verification:** `flutter analyze` clean; `flutter test` — **801 passing** after the pass.
A second remediation pass completed F-02, F-12, F-13, F-42, F-52 and F-66 (new ARB keys
across en/es/ar).

**Remaining open (14 → 6):** F-49/F-56 are skipped by design (Firebase/cloud out of scope);
F-20, F-29, F-36 and F-44 are test-locked or documented as intentional design — see their
rows above.

**Housekeeping:** `lib/core/di/injection.config.dart` was hand-edited for the removed
Subsonic registration; run `dart run build_runner build --delete-conflicting-outputs` to
regenerate it cleanly before release.

---

## 0. How to read this document

Each feature area (§1–§29) is described as:

- **What it is** — one-line intent.
- **Best behavior** — the gold standard the app should meet (industry-best for a premium,
  offline-first local player; anchored to what the codebase already intends, not a rewrite).
- **Functions & wiring** — one row per user-facing function:
  `Function | Implementation (file:line) | Wiring (Cubit/state → usecase/repo → native) | UI entry | Status`.
- **Gaps / bugs** — concrete deficits with evidence and the recommended fix, each cross-referenced
  to a Gap ID in §30.

### Status legend

| Status | Meaning |
|---|---|
| **Full** | Wired end-to-end: UI → cubit → usecase/repo/native, with persistence where relevant. |
| **Partial** | Works but incomplete, window-limited, bypassed, or missing a UX control. |
| **Stub** | Returns placeholder/fake/approximate data or logic. |
| **Dead** | Code exists (often DI-registered or authored) but nothing references/instantiates it. |
| **Gated** | Present but compiled/redirected out of Pure builds (`ENABLE_YTM`, native stub, manifest strip). |
| **Pure-only** | Available even in the offline Play-Store build. |

### Priority legend

| Priority | Meaning |
|---|---|
| **P0** | Correctness/data-loss/user-visible bug; fix before next release. |
| **P1** | Feature is present but unusable/unreachable; high value to wire up. |
| **P2** | Polish, consistency, dead-code cleanup, localization. |

---

## 1. Architecture & wiring spine

Pulsr is Clean-Architecture + BLoC (Cubit) + Drift SQLite.

```
PRESENTATION   Flutter widgets, Aura design tokens, GoRouter
      │        (features/*/presentation, features/*/cubit)
      ▼
   CUBIT       PlayerCubit, LibraryCubit, PlaylistCubit, SearchCubit,
      │        SettingsCubit, AuthCubit, DownloadsCubit, Ytm*Cubit,
      │        DynamicThemeCubit, TagEditorCubit, SmartPlaylistBuilderCubit
      ▼
   DOMAIN      entities/models, repository interfaces, usecases, services (interfaces)
      ▼
    DATA       Drift DB + DAOs, MusicRepository, MediaScannerService,
               PulsrAudioHandler + ~40 audio collaborators, native channels
```

**Key wiring files**

| Concern | File |
|---|---|
| Entry / DI bootstrap / root providers | `lib/main.dart` |
| Dependency injection graph | `lib/core/di/injection.dart`, `lib/core/di/injection.config.dart` |
| Routing | `lib/core/router/app_router.dart` |
| Shared prefs keys | `lib/core/constants/prefs_keys.dart` (+ private keys in `settings_cubit.dart`) |
| Native method channels | `lib/core/constants/channels.dart` |
| Flavor/env gating | `lib/core/config/app_config.dart` |
| Theme system | `lib/core/theme/aura_theme.dart`, `lib/core/theme/dynamic_theme_cubit.dart` |
| Audio engine | `lib/data/audio/audio_handler.dart` (`PulsrAudioHandler`) |
| DB schema | `lib/data/db/app_database.dart`, `lib/data/db/tables.dart` |
| Repository | `lib/data/repositories/music_repository.dart` |
| Scanner | `lib/data/scanner/media_scanner_service.dart` |

**State management pattern.** Every cubit extends `PulsrCubit<S>` (`lib/core/bloc/base_cubit.dart`).
`getIt` singletons are exposed with `BlocProvider.value`; per-screen cubits are created via
`getIt` in `main.dart` (comment at `main.dart:334` documents why `value:` avoids disposing
shared instances).

**Database (Drift, schema v9).** Tables: `songs`, `albums`, `artists`, `playlists`
(`isSmart`/`smartCriteria`), `playlist_entries`, `play_history`, `queue_items`,
`excluded_folders`; FTS5 virtual table `songs_fts` (`app_database.dart:31`).

**Native channels** (`channels.dart` / `PulsrChannels`): `audio_effects`, `tag_editor`,
`visualizer`, `visualizer_stream`, `ringtone`, `scrobbler`, `ytm`, `yt_download`, `waveform`,
`proxy`, `hires_dac`, `hires_dac_events`, `file_opener`, `lyrics`, `battery_optimization`,
`room_correction`, `room_correction_pcm`; vendored just_audio fork adds `dspSetGainCurve`,
`dspSetFloatOutput`, `dspSetAaudioOutput`.

**Flavor / environment matrix** (`app_config.dart:6`)

| Build | `flavor` | `ENABLE_YTM` | App label / id | Manifest |
|---|---|---|---|---|
| Dev | `dev` | `true` | "Pulsr Plus" / `.plus` | `src/dev` |
| YTM | `ytm` | `true` | "Pulsr Music" / `.ytm` | `src/ytm` |
| Prod (Pure) | `prod` | `false` | "Pulsr Music" / `.music` | `src/prod`, INTERNET stripped |

`AppConfig.validateConfiguration()` throws if `prod` + YTM or `prod` + `ENV=dev`
(`app_config.dart:69`). Prod isolation is also enforced by a Gradle task
`validateProdIsolation` (`android/app/build.gradle.kts:300`) that scans for YouTube/NewPipe strings.

---

## 2. Startup, Splash, Onboarding & Permissions

**What it is.** Cold-start bootstrap, first-run walkthrough, storage permission acquisition,
restore detection, initial file/session-intent handling, and network/auth monitors.

**Best behavior.** First frame within one frame budget (no awaited I/O before `runApp`); heavy
init deferred and fault-isolated; permission asked with rationale and a settings fallback;
onboarding copy matches the shipped DSP (10-band); scan shows real progress; external audio
intents play immediately; an expired YTM session prompts re-login exactly once.

### Functions & wiring

| Function | Implementation | Wiring | UI entry | Status |
|---|---|---|---|---|
| Bootstrap | `main()` `main.dart:54` | `ensureInitialized`, `HttpOverrides`, `validateConfiguration`, `ErrorLogger`, edge-to-edge, `configureDependencies().timeout(15s)` | — | Full |
| Deferred post-startup | `firePostStartupTasks()` `main.dart:92` | rate-limiter restore, `AuthService.initialize`, `YtmAccountService.init`, `YtmService.preWarm` (fire-and-forget) | — | Full |
| Crash reporting | `main.dart:129` | Sentry if `sentryDsn.isNotEmpty`; `ErrorLogger.onCrashReported` `main.dart:64` | — | Full (gate note) |
| Splash | `SplashScreen._checkNextScreen` `features/splash/presentation/splash_screen.dart:22` | reads `onboarding_completed`, 1.6 s, routes `/onboarding` or `/` | `/splash` (`app_router.dart:81`) | Full |
| Onboarding wizard | `OnboardingScreen` `features/onboarding/presentation/onboarding_screen.dart:14` | 3 pages, `_nextPage:78`, `_skipToFinal:87`, sets `onboarding_completed` | `/onboarding` (`app_router.dart:86`) | Full |
| Grant access | `_handleGrantAccess` `onboarding_screen.dart:34` | `MediaScannerService.requestPermission()` + notification permission + `scanDeviceLibrary()`; denied → `openAppSettings()` | page 3 button `:182` | Full |
| Permission check | `MediaScannerService.checkPermission/requestPermission` `media_scanner_service.dart:47,59` | Android `Permission.audio`/`storage`, iOS `mediaLibrary`; desktop returns true `:56` | onboarding, main auto-scan | Full |
| Restore detection | `RestoreDetectionService.checkAndHandleRestore` `core/services/restore_detection_service.dart:58` | invoked `main.dart:281` | — | Full |
| Auto-scan on startup | `_autoScanOnStartup` `main.dart:276` | if permission and no songs → `SettingsCubit.rescanLibrary()` | — | Full |
| Initial audio intent | `_checkInitialAudioIntent` `main.dart:263` → `FileIntentHandler.checkInitialUri` `core/services/file_intent_handler.dart:50` | `file_opener` channel | external file open | Full |
| YTM session-expiry prompt | `_listenForYtmSessionExpiry` `main.dart:198` | `YtmService.onAuthExpired` → snackbar → `YtmWebLoginSheet.show` | root overlay | Gated |
| Network-change monitor | `_startNetworkChangeMonitor` `main.dart:230` | `NetworkChangeMonitor` → `YtmService.handleNetworkChange`, `PulsrAudioHandler.clearNetworkCaches` | — | Full |
| Memory-pressure trim | `didHaveMemoryPressure` `main.dart:182` | `ArtworkCacheManager.clearAllCache`, `ArtworkLruCache.trimForMemoryPressure` | — | Full |

### Gaps / bugs

- **F-01 (P2):** Onboarding copy contradicts the shipped DSP — page 2 says "5-Band EQ" then
  "10-band graphic equalizer" (`onboarding_screen.dart:363,385`). Fix copy to 10-band.
- **F-02 (P2):** `main.dart:129` gates Sentry on DSN alone; `AppConfig.isTelemetryAllowed`,
  `isPure`, `isDev` are never referenced outside `app_config.dart`. Fix: gate on
  `AppConfig.isTelemetryAllowed` (or document why DSN-only is intentional).
- **F-03 (P2):** `MediaScannerService.scanProgress`/`scanErrors` streams
  (`media_scanner_service.dart:32`) have **no consumer**; UI only shows an indeterminate spinner.
  Wire progress into `SettingsState`/library refresh for a real progress bar, and surface errors.

---

## 3. Navigation, Shell & Layout

**What it is.** The persistent shell (bottom nav on phones, sidebar on landscape/tablet), the
route table, mini-player placement, and error handling.

**Best behavior.** Instant tab switches with preserved state; route redirects respect flavor
gating; deep links and pushed pages keep platform back semantics; a localized, recoverable
"not found" page.

### Functions & wiring

| Function | Implementation | Wiring | UI entry | Status |
|---|---|---|---|---|
| Tab shell | `AppShell` `features/shell/presentation/app_shell.dart:92` | `StatefulShellRoute.indexedStack`, 5 branches | bottom nav | Full |
| Bottom nav | `BottomNavBar` `features/shell/presentation/bottom_nav_bar.dart` | Home/Library/Search/Playlists/Settings | — | Full |
| Landscape sidebar | `LandscapeSidebar` `features/shell/presentation/widgets/landscape_sidebar.dart` | adaptive | tablet/landscape | Full |
| Stacked dock | `StackedBottomDock` `features/shell/presentation/widgets/stacked_bottom_dock.dart` | mini player + nav | — | Full |
| Tablet inspector | `TabletSideInspector` `features/shell/presentation/widgets/tablet_side_inspector.dart` | adaptive | tablet | Full |
| Route table | `createRouter` `core/router/app_router.dart:50` | 5 branches + ~30 root routes | — | Full |
| YTM route gate | `app_router.dart:54` | redirects `/ytm-search`, `/ytm-explore`, `/downloads` → `/` when `!ytmEnabled` | — | Gated |
| Error page | `errorBuilder` `app_router.dart:61` | hardcoded English, "Page Not Found" | deep link miss | Partial |
| Back scoping | `PulsrPagePopScope`, `PulsrBackButton` `core/widgets/` | per-page | — | Full |

### Gaps / bugs

- **F-04 (P2):** `errorBuilder` strings are hardcoded English (`app_router.dart:61-78`) while the
  rest of the app is localized (en/es/ar). Move to ARB.

---

## 4. Home / Dashboard

**What it is.** The landing surface: greeting, quick-access cards, recent tracks, quick picks,
and discovery chips into library tools and (gated) YTM.

**Best behavior.** Fast, informative, personalized to listening habits; only surfaces features
that actually work; pull-to-refresh rescans; online tab appears only when YTM is enabled and
offline mode is off.

### Functions & wiring

| Function | Implementation | Wiring | UI entry | Status |
|---|---|---|---|---|
| Local/Online split | `home_screen.dart:205` | `showOnlineTab = ytmEnabled && !offlineOnly` | Home | Full |
| Quick cards | `home_screen.dart:476` | Favorites `/favorites`; Daily Drive shuffle-all; Focus Flow top-played | Home | Full |
| Recent tracks | `home_screen.dart:1279` | "See All" → `/recents` | Home | Full |
| Discovery chips | `home_screen.dart:340` | `/ytm-explore`, `/artwork-grid`, `/library-stats`, `/duplicate-finder`, `/theme-studio`, `/queue`, `/downloads` | Home | Partial |
| Pull-to-refresh | `home_screen.dart:217` | rescan / reload | Home | Full |
| Empty-state scan | `_EmptyLibrary._scan` `home_screen.dart:1445` | `scanDeviceLibrary` | Home | Full |

### Gaps / bugs

- **F-05 (P1):** Discovery chip "Duplicate Cleaner" leads to a read-only screen (see §25/F-24).
- **F-06 (P2):** Home exposes dead/near-dead tools (artwork wall is fine; duplicate cleaner and
  library stats are window-limited). Align chips with working features or fix the tools.

---

## 5. Media Scanning & Indexing

**What it is.** Permission-gated scan of the device audio collection into the Drift index, with
`.nomedia`/excluded-folder/system-media filtering, isolate parsing, quality enrichment, and
single-file rescan.

**Best behavior.** 10k+ tracks indexed quickly off the UI thread; deterministic filters with a
preview; incremental updates without losing ratings/play history; real progress + error reporting;
no orphan rows.

### Functions & wiring

| Function | Implementation | Wiring | UI entry | Status |
|---|---|---|---|---|
| Full scan | `MediaScannerService.scanDeviceLibrary` `data/scanner/media_scanner_service.dart:185` | isolate `_parseScannedMediaInIsolate:502`; excluded paths via `IMusicRepository.getExcludedFolderPaths` `music_repository.dart:1086`; `syncScannedMusic:1157` + `cleanupOrphanedSongs:1184` | Settings rescan, Home/Library refresh, onboarding | Full |
| Filters | `media_scanner_service.dart:80,112,137` | min duration `minDurationSec` (default 30), min size, `autoHideSystemMedia`, `.nomedia`, excluded dirs, `AudioFormats.isSupportedExtension` | Settings sliders/chips | Full |
| `.nomedia` cache | `isInNomediaDirectory:137`, `clearNomediaCache:183` | process-level cache | — | Partial |
| Single-file rescan | `rescanSingleFile:285` | `tag_editor` channel read; `updateSongTags` | Tag editor save | Full |
| Quality enrichment | `enrichAudioQuality:336`, `enrichAudioQualityBatch:384`, `computeTruePeak:412`, `computeLoudnessRange:444` | `updateAudioQuality:1629`; batch/peak/LRA helpers | player badge | Partial |
| Scan progress/errors | `scanProgress`/`scanErrors` `:32` | none | — | Dead |
| Orphan hard delete | `IMusicRepository.hardDeleteMissingSongs` `music_repository.dart:1325` | no caller | — | Dead |
| Rescan orchestration | `SettingsCubit.rescanLibrary` `features/settings/cubit/settings_cubit.dart:1211` | wraps scan, updates `isScanning`, `scanResultCount` | Library section, Hidden folders | Full |

### Gaps / bugs

- **F-07 (P0):** `GetSongsUseCase` clamps `limit` to `[0,1000]` (`domain/usecases/get_songs_usecase.dart:21`),
  so `LibraryCubit.loadMoreSongs` cannot page past 1,000 rows and **Library Stats / Duplicate Finder
  undercount large libraries**. Fix: remove/raise the clamp or paginate by offset.
- **F-03 (P2):** scan progress/error streams unconsumed (see §2).
- **F-08 (P2):** `enrichAudioQualityBatch`, `computeTruePeak`, `computeLoudnessRange` are never
  called (`media_scanner_service.dart:384,412,444`); true-peak/LRA data is never shown.
- **F-09 (P2):** `clearNomediaCache()` is never called, so `.nomedia` changes require a full
  process restart to take effect.
- **F-10 (P2):** `hardDeleteMissingSongs` has no UI/use-case caller; missing files linger.

---

## 6. Library Browsing

**What it is.** The multi-dimensional browser: Songs, Albums, Artists, Genres, Years, Folders,
Favorites, plus a Downloaded filter, sort/filter sheet, A–Z scrubber, grid/list, multi-select
batch actions, and pagination.

**Best behavior.** True pagination over the entire library; stable sort with SQL push-down where
possible; grid/list persisted; unlimited-scope multi-select; no duplicated screens.

### Functions & wiring

| Function | Implementation | Wiring | UI entry | Status |
|---|---|---|---|---|
| Cubit subscriptions | `LibraryCubit.init` `features/library/cubit/library_cubit.dart:82` | watches songs/albums/artists/genres/years/favorites, `loadFolders` | `/library` branch | Full |
| Songs tab + sort/filter | `library_screen.dart:313`; `SortFilterSheet` `features/sheets/sort_filter_sheet.dart:7` | `GetSongsUseCase.watchSongs`; SQL sort `music_repository.dart:77`; rating sorted in Dart `library_cubit.dart:169` | Library | Full |
| Pagination | `loadMoreSongs` `library_cubit.dart:194`, `songsPageSize=500` | `_subscribeSongs:120`, `_songsLimit` | scroll near bottom `library_screen.dart:60` | Partial |
| Multi-select batch | `toggleSongSelection:433`, `selectAllSongs:448`, `getSelectedSongs:457` | app bar `library_screen.dart:108` | long-press | Partial |
| Grid/list + A–Z | `toggleViewMode:311`; `_scrollToLetter` `library_screen.dart:72` | prefs `library_view_mode`, `library_sort_*` | Library | Full |
| Albums | `_buildAlbumsTab` `library_screen.dart:859` | `GetAlbumsUseCase` → `watchAlbums:683` | Library → `/album` | Full |
| Artists | `_buildArtistsTab` `library_screen.dart:966` | `GetArtistsUseCase` → `watchArtists:758` | Library → `/artist` | Full |
| Genres | `_buildGenresTab` `library_screen.dart:1068` | `GetGenresUseCase` → `watchGenres:1656` | Library → `/genre` | Full |
| Years | `_buildYearsTab` `library_screen.dart:1093` | `GetYearsUseCase` → `watchYears:1750` | Library → `/year` | Full |
| Favorites tab | `_buildFavoritesTab` `library_screen.dart:1140` | `GetFavoritesUseCase` → `watchFavorites:407`; YTM import `:1243` | Library | Full |
| Downloaded filter | `_buildDownloadedTab` `library_screen.dart:588`, `_isOnlineDownload:845` | `state.songs` filtered by `isDownloaded`/`remoteId` | Library | Full |
| Folder browser (flat) | `FolderBrowserTab` `widgets/folder_browser_tab.dart:12` | `LibraryCubit.loadFolders` → `FolderUseCases.getFolderHierarchy` `folder_usecases.dart:42` | Library tab 6 | Full |
| Recent playback | `RecentsScreen` `presentation/recents_screen.dart:20` | `GetSongsUseCase.watchRecentlyPlayed/clearRecentlyPlayed` | `/recents` | Full |

### Gaps / bugs

- **F-07 (P0):** pagination capped at 1,000 (see §5).
- **F-11 (P1):** `selectAllSongs` only selects the loaded window (`library_cubit.dart:448`), so
  "Select All → Add to Queue/Playlist" silently misses the rest of the library. Fix: select by
  query/IDs, not the in-memory window.
- **F-12 (P2):** Favorites are implemented twice (`LibraryScreen` favorites tab vs
  `FavoritesScreen` at `/favorites`) with diverging search behavior (`favorites_screen.dart:51`
  in-memory search). Consolidate into one reusable widget.
- **F-13 (P2):** `loadFolders` loads **all** songs and computes counts in Dart
  (`folder_usecases.dart:42`); `watchFolderSongs` watches the unfiltered song table
  (`folder_usecases.dart:90`). Push aggregation/filtering into SQL.

---

## 7. Detail Screens (Album / Artist / Genre / Year / Folder)

**What it is.** Drill-down screens with track lists and contextual actions.

**Best behavior.** Header art, metadata, play/shuffle/queue-all, artist bio (online-gated),
related content, and consistent SongTile actions.

### Functions & wiring

| Function | Implementation | Wiring | UI entry | Status |
|---|---|---|---|---|
| Album detail | `AlbumDetailScreen` `features/album_detail/presentation/album_detail_screen.dart:19` | `watchAlbumSongs:697` | `/album` | Full |
| Artist detail | `ArtistDetailScreen` `:22` | `watchArtistSongs:773`, `watchArtistAlbums:821`, `ArtistBioService` `:104` | `/artist` | Full |
| Genre detail | `GenreDetailScreen` `:20` | `watchGenreSongs:1714` | `/genre` | Full |
| Year detail | `YearDetailScreen` `:19` | `watchYearSongs:1782` | `/year` | Full |
| Folder detail | `FolderDetailScreen` `:20` | `FolderUseCases.watchFolderSongs` | `/folder` | Full |
| Genre hierarchy | `GenreHierarchyView` `library/presentation/widgets/genre_hierarchy_view.dart:15` | none | — | Dead |
| Folder tree | `FolderTreeBrowserTab` `library/presentation/widgets/folder_tree_browser_tab.dart:10` | none | — | Dead |

### Gaps / bugs

- **F-14 (P1):** `GenreHierarchyView` (7-category grouping with Arabic keyword matching,
  `genre_hierarchy_view.dart:20`) is never mounted; the Genres tab is flat. Wire it as a toggle.
- **F-15 (P1):** `FolderTreeBrowserTab` (breadcrumbs, parent navigation) is never mounted; only the
  flat `FolderBrowserTab` is used. Wire the tree view for deep storage hierarchies.
- **F-13 (P2):** folder detail watches the whole unfiltered song table (see §6).

---

## 8. Search

**What it is.** Instant local search (FTS5 + Arabic/Latin normalization + fuzzy fallback) plus an
optional online (YTM) search path.

**Best behavior.** <250 ms debounce, FTS-first, bounded fuzzy fallback over the whole library,
persisted history, and clear online/offline separation.

### Functions & wiring

| Function | Implementation | Wiring | UI entry | Status |
|---|---|---|---|---|
| Local search | `SearchCubit.onQueryChanged` `features/search/cubit/search_cubit.dart:47` | `SearchMusicUseCase.searchSongs` → `watchAllSongs(searchQuery:)` → FTS `_watchSongsFts` `music_repository.dart:169`; `toFtsQuery:154` | `/search` | Full |
| Normalization | `search_cubit.dart:161` | Arabic tashkeel/Alef, Latin accents | — | Full |
| Fuzzy fallback | `_filterWithFuzzy:192`, `_levenshtein:241` | bounded to first 300 songs `:134` | — | Partial |
| History | `_persistHistory:61`, `clearHistory:73` | prefs | Search | Full |
| Online search | `search_screen.dart:38,90` | `YtmSearchCubit` | Search (YTM) | Gated |

### Gaps / bugs

- **F-16 (P1):** fuzzy fallback scans only the first 300 songs (`search_cubit.dart:134`), so
  non-prefix matches in large libraries are missed. Fix: SQL-prefilter then fuzzy-rank, or index
  a normalized search column.

---

## 9. Playlists (Manual, Smart, Import/Export, Share, Suggestions)

**What it is.** Manual playlists, a rule-based smart-playlist engine, M3U import/export, management
screens, and online YTM playlist caching, plus (authored but unwired) share and suggestion services.

**Best behavior.** Full CRUD, live smart previews, portable M3U, share sheets, and proactive
suggestions; every rule type actually evaluates.

### Functions & wiring

| Function | Implementation | Wiring | UI entry | Status |
|---|---|---|---|---|
| Playlist cubit | `PlaylistCubit` `features/playlists/cubit/playlist_cubit.dart:123` | local CRUD + online YTM cache `:190,232`; smart counts `:273`; seeding `:256` | `/playlists` | Full |
| Smart engine | `SmartPlaylistEngine` `data/repositories/smart_playlist_engine.dart:12` | `_buildQuery:17`, `_buildRuleExpression:100`, `evaluateCriteria:393`, `watchCriteria:420` | builder/detail | Full |
| Smart criteria model | `SmartCriteria` `domain/models/smart_playlist_criteria.dart`; presets `:173` | JSON (de)code | builder | Full |
| Default smart playlists | `seedDefaultSmartPlaylists` `domain/usecases/playlist_usecases.dart:68` | 6 defaults | Playlists | Full |
| Builder | `SmartPlaylistBuilderScreen` `features/smart_playlist_builder/smart_playlist_builder_screen.dart:19` | `SmartPlaylistBuilderCubit` live preview `:86`, `savePlaylist:100` | `/smart-playlist-builder` | Full |
| Manage / detail | `ManagePlaylistScreen`, `PlaylistDetailScreen` `features/playlist_detail/...` | `watchPlaylistSongs`, smart resolve `playlist_detail_screen.dart:127` | `/playlist/manage`, `/playlist` | Full |
| Import/export | `PlaylistExportUseCase`/`PlaylistImportUseCase` `domain/usecases/playlist_io_usecases.dart:13,61` | `file_picker` | Playlists/detail | Full |
| Online playlists | `OnlinePlaylistDetailScreen` | `YtmAccountService.fetchAccountPlaylists:973` | `/online-playlist` | Gated |
| Share | `PlaylistShareService` `core/services/playlist_share_service.dart:63` | none | — | Dead |
| Suggestions | `PlaylistSuggestionsService` `core/services/playlist_suggestions_service.dart:18` | none | — | Dead |
| Playback snapshot | `SmartPlaylistEngine.createPlaybackSnapshot:566` | none | — | Dead |

### Gaps / bugs

- **F-17 (P1):** BPM is a stub smart rule — `SmartRuleField.bpm` logs "ignored — BPM column not
  indexed" and returns null (`smart_playlist_engine.dart:313`), and the builder hides it
  (`smart_playlist_builder_screen.dart:543`). Add a BPM column + persist from `BpmOverrideStore`
  and re-enable the rule.
- **F-18 (P1):** `PlaylistShareService` is fully authored but unused (`playlist_share_service.dart:63`);
  wire share buttons to it.
- **F-19 (P2):** `PlaylistSuggestionsService.generateSuggestions` has no consumer
  (`playlist_suggestions_service.dart:33`). Surface on Home/Playlists or remove.
- **F-20 (P2):** `createPlaybackSnapshot` unused (`smart_playlist_engine.dart:566`).

---

## 10. Queue

**What it is.** The playback queue with reorder, remove, add-next/add-last, clear, multi-slot
(Q1/Q2/Q3) switching, persistence, and prefetch.

**Best behavior.** Stable reordering, per-slot persistence including online tracks, gapless-safe
auto-advance, and no dead collaborators.

### Functions & wiring

| Function | Implementation | Wiring | UI entry | Status |
|---|---|---|---|---|
| Load/advance queue | `PulsrAudioHandler.loadQueue` `data/audio/audio_handler.dart:2999`; `_getNextIndex:2813`, `_getPreviousIndex:2864` | `state.queue`, `state.currentIndex` | queue view | Full |
| Add/reorder/remove/clear | `PlayerCubit.playNext:1436`, `addToQueue:1479`, `clearQueue:1517`, `reorderQueue:1541`, `removeQueueItem:1581` | handler `:4173-4324`; max 500 | song tiles, queue view | Full |
| Three slots | `_queueSlots` `player_cubit.dart:118`, `switchQueueSlot:1668`, `_persistQueueSlots:283` | prefs `queue_slots`; 15 s position save `:944` | `now_playing_queue_view.dart:53` | Full |
| Gapless auto-advance | `_onGaplessIndexChanged` `audio_handler.dart:3390` | model/notification/history/ReplayGain reconcile + circuit breaker | — | Full |
| Prefetch | `TripleBufferPipeline` used `:3637`; `SmartPreloadScheduler` `_smartPrefetch:2348`; `StreamPreResolver` | — | — | Full |
| `PlaybackQueueManager` | `data/audio/collaborators/playback_queue_manager.dart` constructed `:1015` | all methods unused | — | Dead |

### Gaps / bugs

- **F-21 (P2):** `PlaybackQueueManager`, `SeamlessQueueTransition` (`:1057`),
  `PlaybackStateCoordinator` (`:1020`), and `PlaybackPreloadOrchestrator` (`:1023`) are constructed
  but never invoked in `audio_handler.dart`. Remove or wire; currently confusing dead surface.
- **F-22 (P2):** `StreamResolutionPipeline.resolveStreamUrl` is bypassed by the handler's own
  `_resolveStreamUrl` (`audio_handler.dart:1931`); only `invalidateCache` is used.

---

## 11. Playback Transport & Advanced Playback

**What it is.** Play/pause, next/prev, seek, shuffle, repeat, speed/pitch, A-B loop, per-track
delay, bookmarks, BPM override, ReplayGain, per-song volume, silence skip, SponsorBlock, and the
adaptive/network-aware engine.

**Best behavior.** Rock-solid transport with optimistic UI + rollback; all advanced tools exposed
in **every** player theme; user controls for every automatic behavior.

### Functions & wiring

| Function | Implementation | Wiring | UI entry | Status |
|---|---|---|---|---|
| Play/pause | `PlayerCubit.togglePlayPause:1784`; handler `play:3725`, `pause:3749` | state `isPlaying` | all themes, mini-player | Full |
| Next/prev | `PlayerCubit.next:1853`, `previous:1863`; handler `skipToNext:3823`, `skipToPrevious:3874` | repeat/shuffle history | all themes | Full |
| Seek | `PlayerCubit.seek:1805`; handler `seek:3759`, `_performSeek:3802` | 100 ms throttle + 60 ms debounce | seek bars, lyrics tap | Full |
| Shuffle | `toggleShuffle:1884`; `setShuffleMode:3945` | pref `playback_shuffle` | controls | Full |
| Repeat | `toggleRepeat:1896`; `setRepeatMode:3965` | pref `playback_repeat_mode` | controls | Full |
| Speed | `setPlaybackSpeed:2766`; handler `setSpeed:4077`, `setAdvancedSpeedEnabled:4034` | pref `playback_speed` | `speed_picker_sheet.dart` | Full (range UI) |
| Pitch | `setPlaybackPitch:2793`; handler `setPitch:4090` | pref `playback_pitch` | `speed_picker_sheet.dart:170` | Full |
| A-B loop | `AbLoopManager` `data/audio/ab_loop_manager.dart`; handler `:4813-4827` | `state.abLoop*`; pref `ab_loops_v1` | `advanced_playback_bar.dart:62` | Partial (UI) |
| Per-track delay | `TrackDelayManager`; handler `setCurrentTrackDelay:4844` | `state.trackDelayMs` | `advanced_playback_bar.dart:96` | Partial (UI) |
| Bookmarks | `PlaybackBookmarkStore`; handler `recallBookmarkFor:4997` | `state.bookmarkPosition` | `advanced_playback_bar.dart:32` | Partial (UI) |
| BPM override | `BpmOverrideStore`; handler `setTrackBpm:2217` | feeds crossfade | `song_info_sheet.dart:607` | Full |
| ReplayGain | `replay_gain_math.dart`; handler `_calculateReplayGainVolume:545` | prefs `replay_gain_*`; `PlaybackVolumeController` | `audio_sound_section.dart:247` | Full (Dart) |
| Per-song volume | `PerSongVolumeStore`; cubit `setSongVolumeOverride:2824` | `state.currentSongVolumeOverrideDb` | `song_info_sheet.dart:554` | Full |
| Volume boost | `EqualizerManager.setVolumeBoost:1111` | `state.volumeBoost` | `equalizer_sheet.dart:1660` | Full |
| Silence skip | `SilenceSkipController`; handler `setSkipSilenceEnabled:2162`, `setSilenceSkipSensitivity:4984` | `state.silenceSkipSensitivity` | `playback_section.dart:136` | Partial (advisory) |
| SponsorBlock | `SponsorBlockService` `core/services/sponsorblock_service.dart`; cubit `_checkSponsorBlockSkip:1012` | enabled unless offline | — | Partial (no UI) |
| Adaptive quality | `AdaptiveQualityManager`; handler `_maybeAdaptiveStepDown:4870` | `playback_section.dart:126` | Settings | Full |
| Audio normalization | `handler.setAudioNormalizationEnabled:2255` | pref `audio_normalization_enabled` | — | Dead (UI) |
| Save DSP snapshot | `PlayerCubit.saveDspSnapshot:2997` | no caller | — | Dead |

### Gaps / bugs

- **F-23 (P1):** `AdvancedPlaybackBar` (A-B loop / delay / bookmarks) only renders in the Classic
  theme (`classic_player_theme.dart:613`); the other 8 themes omit it. Render it from the shared
  `NowPlayingScreen` chrome or all themes.
- **F-67 (P1):** SponsorBlock is always-on with **no** enable/disable or category UI
  (`sponsorblock_service.dart`; grep shows no settings key). Add toggles + category selection and
  a skip indicator.
- **F-25 (P1):** Sleep timer `SleepTimerMode.endOfQueue` is unreachable —
  `SleepTimerManager.startEndOfQueueTimer`/`onQueueCompleted` (`sleep_timer_manager.dart:174,197`)
  are never called. Wire to queue-completion.
- **F-26 (P2):** Advanced speed range (0.1–8.0 via `setAdvancedSpeedEnabled:4034`) has no UI toggle.
- **F-27 (P2):** Manual audio normalization (`setAudioNormalizationEnabled:2255`) has no settings UI.
- **F-28 (P2):** Manual `saveDspSnapshot:2997` is never called; add a "save for this album" action.
- **F-29 (P2):** Native ReplayGain stage is deliberately dormant —
  `_pushNativeReplayGain` always calls `setReplayGainEnabled(false)` (`audio_handler.dart:601`).
  Document or remove the native path.

---

## 12. Now Playing Themes & Mini Player

**What it is.** Eight selectable Now Playing themes + a custom theme builder, shared transport
chrome, and a gesture-rich mini player.

**Best behavior.** Consistent feature parity across themes; no dead karaoke/lyrics-editor screens;
custom theme import/export.

### Functions & wiring

| Function | Implementation | Wiring | UI entry | Status |
|---|---|---|---|---|
| Theme switch | `NowPlayingScreen` `features/player/presentation/now_playing_screen.dart:72` | `PlayerThemeMode` (8) | `/now-playing` | Full |
| Themes | `classic/card/circle/minimal/vinyl/cassette/waveform/lyricsFocus` `features/player/presentation/themes/*` | `PlayerThemeProps` `player_theme.dart:6` | Settings picker `settings_screen.dart:703` | Full |
| Theme studio | `CustomThemeBuilderScreen` `themes/custom_theme_builder_screen.dart:13` | export/import `:36,61` | `/theme-studio` | Full |
| View switcher | each theme e.g. `classic_player_theme.dart:759` | `toggleLyricsVisibility:2857`, `toggleQueueVisibility:2864` | themes | Full |
| Mini player | `MiniPlayer` `features/player/presentation/mini_player.dart` | swipe actions, drag-seek, `rawPositionStream` `player_cubit.dart:82` | shell | Full |
| Karaoke mode | `KaraokeModeScreen` `widgets/karaoke_mode_screen.dart` | reads `PlayerCubit`; fake score `:92` | none | Dead |
| Lyrics editor | `LyricsEditorSheet` `widgets/lyrics_editor_sheet.dart` | `onSave` | none | Dead |

### Gaps / bugs

- **F-30 (P1):** `KaraokeModeScreen` is never instantiated (grep confirms definition only) and
  shows a hardcoded "VOCAL SCORE: 96%" (`karaoke_mode_screen.dart:92`). Wire it (e.g. from the
  lyrics view) and remove/implement the fake score.
- **F-31 (P1):** `LyricsEditorSheet` is never instantiated; wire an "Edit lyrics" affordance in the
  lyrics view.
- **F-23 (P1):** Advanced playback bar only in Classic (see §11).

---

## 13. DSP / Equalizer / Effects Engine

**What it is.** The full audio DSP chain: 10-band / 32-band EQ, AutoEQ headphone profiles, bass
boost, virtualizer/spatializer, dynamics/compressor/limiter, crossfeed, reverb + custom IR,
stereo balance/mono, saturation, stereo width, loudness contour, sub crossover, dynamic EQ, sinc
resampler, dither, and a master kill-switch, surfaced in `EqualizerSheet`.

**Best behavior.** Every authored stage reachable from the UI; honest conflict/degradation
status; no dead API; manual control where useful.

### Functions & wiring

Central classes: `EqualizerManager` (`lib/data/audio/equalizer_manager.dart`),
`AudioEffectsChannel` (`lib/data/audio/audio_effects_channel.dart`), `EqPreset`,
`AudioEffectsConfig`, `OptimizedDspPipeline`, and the conflict registry
`lib/core/constants/audio_feature_info.dart`.

| Function | Implementation | Wiring | UI entry | Status |
|---|---|---|---|---|
| Master EQ (10-band) | `setEnabled:766`, `setPreset:794`, `setBandGain:808`, `applyCurrentPreset:884`, `resetToFlat:1005` | `state.isEqEnabled`, `state.eqPreset`; `setNativeEqBandsBulk` | `equalizer_sheet.dart` tab 1 | Full |
| 32-band / custom freqs | `set32BandMode:716`, `setCustomFrequencies:1080` | persisted/restored | — | Partial (no UI) |
| Built-in presets | `EqPreset.defaultPresets` `domain/models/eq_preset.dart:218` | `interpolateGains:168` | EQ sheet carousel | Full |
| AutoEQ profiles | `HeadphoneProfilesRepository`; `setHeadphoneProfile:1126`; `AutoEqService` | bundled `assets/eq_profiles/headphone_profiles.json`; per-song by name `player_cubit.dart:680` | EQ "AutoEq" tab `:1840`; `autoeq_search_sheet.dart` | Full |
| Preamp | `setPreamp:876` | applied only via headphone profile `:1160` | — | Partial (no UI) |
| Bass boost | `setBassBoost:989` | `state.eqPreset.bassBoost`, `isBassBoostSupported` | `equalizer_sheet.dart:1500` | Full |
| Virtualizer / spatializer | `:1178,1203,1276,1300` | `state.isVirtualizerEnabled`, `isSpatializerEnabled` | `equalizer_sheet.dart:1800` | Full |
| Dynamics / multiband | `setDynamicsPreset:1212`, `toggleDynamicsBypass:1234` | `state.dynamicsPreset` | `equalizer_sheet.dart:2500` | Full |
| Limiter / compressor | `setLookaheadLimiter:1333`, `setCompressorParams:1355` | `state.isLimiterEnabled`, `limiter*` | `equalizer_sheet.dart:2840`; `compressor_limiter_sheet.dart` | Full |
| Crossfeed | `setCrossfeed:1314` | `state.isCrossfeedEnabled`, `crossfeed*` | `equalizer_sheet.dart:2660` | Full |
| Reverb + custom IR | `setReverb:1385`, `loadCustomImpulseResponse:1401`; `IrFileParser` | prefs `custom_reverb_ir_path` | `equalizer_sheet.dart:3165` | Full |
| Stereo balance / mono | `setStereoBalance:1434`, `setMonoMix:1443` | `state.stereoBalance`, `monoMix` | `equalizer_sheet.dart:3001` | Full |
| Sinc resampler | `setSincResampler:1452`; handler `setSincResamplerQuality:2184` | `state.isSincResamplerEnabled` | EQ sheet + `audio_sound_section.dart:814` | Full |
| Dither (TPDF) | `setDither:1686` | `state.isDitherEnabled`, auto-skip on BT | `equalizer_sheet.dart:4067` | Full |
| Saturation / exciter | `setSaturation:1524` | `state.isSaturation*` | `equalizer_sheet.dart:3454` | Full |
| Stereo width | `setStereoWidth:1546` | `state.isStereoWidthEnabled` | `equalizer_sheet.dart:3578` | Full |
| Loudness contour | `setLoudnessContour:1560`, `updateLoudnessVolume:1577` | `state.isLoudnessContourEnabled` | `equalizer_sheet.dart:3968`, `audio_sound_section.dart:398` | Full |
| Sub crossover | `setSubCrossover:1587` | `state.isSubCrossover*` | `equalizer_sheet.dart:3679` | Full |
| Dynamic EQ | `setDynamicEq:1611`, `setDynamicEqBand:1621` | `state.isDynamicEqEnabled`, `dynamicEqBands` | `equalizer_sheet.dart:3795` | Full |
| Master kill-switch | `PlayerCubit.setDspEffectsEnabled:2170` | `_dspSnapshot` | `equalizer_sheet.dart:794` | Full |
| A/B flat + 4 slots | `startAbComparison:1017`, `switchComparisonSlot:959`, `saveCurrentToSlot:955` | `PlayerCubit:2068,2101` | `equalizer_sheet.dart:1069,1146` | Full |
| Preset import/export | `exportPresetToJson:967`, `importPresetFromJson:972` | cubit `:2108` | `equalizer_sheet.dart:302` | Full |
| Conflict/degrade/inspector | `AudioFeatureRegistry`/`AudioConflicts`; `effectStatusNotifier`; `DspInspectorSheet` | auto-degrade `audio_effects_channel.dart:1422` | EQ info dialogs; Settings `:573` | Full |
| Genre-based EQ | `applyGenreBasedEq:1791` | none | — | Dead |
| Band solo/mute | `setBandSolo:1429`, `setBandMute:1431` | none | — | Dead |
| Pipeline latency estimate | `OptimizedDspPipeline.calculateTotalEstimatedLatencyMs:100` | none | — | Dead |
| Room correction | `RoomCorrectionService`; `room_correction_sheet.dart:48` | channels `room_correction(_pcm)` | `audio_sound_section.dart:504` | Full |
| Room correction merge/IR export | `mergeWithHeadphoneCurve:227`, `exportCorrectionImpulseResponse:250` | none | — | Dead |
| Device profile apply | `PlayerCubit.applyProfile:2662` | `HiResAudioService.outputDeviceStream` watcher `:2608` | `device_profiles_section.dart` (dead UI) | Partial |

### Gaps / bugs

- **F-32 (P1):** 32-band mode and custom band frequencies have full engine + persistence but **no
  UI** (`EqualizerManager.set32BandMode:716`, `setCustomFrequencies:1080`). Add a band-count toggle
  and frequency editor to the EQ sheet.
- **F-33 (P1):** Manual preamp has no slider; it is only applied from a headphone profile
  (`setHeadphoneProfile:1160`). Add a preamp control with a clip warning.
- **F-34 (P2):** `applyGenreBasedEq:1791` is never called. Wire genre presets or remove.
- **F-35 (P2):** Band solo/mute API (`:1429,1431`) has no UI. Expose per-band mute in the EQ.
- **F-36 (P2):** `OptimizedDspPipeline.calculateTotalEstimatedLatencyMs:100` unused; use it in the
  DSP inspector or remove.
- **F-37 (P1):** Room correction `mergeWithHeadphoneCurve`/`exportCorrectionImpulseResponse` are
  never called (`room_correction_service.dart:227,250`), so headphone+room stacking and FIR export
  are unavailable. Wire both.
- **F-38 (P2):** Device Profiles service is live but its UI (`DeviceProfilesSection`) is dead
  (`widgets/device_profiles_section.dart:17`), so users cannot create/manage profiles. Re-mount it.
- **F-39 (P2):** `EqualizerManager.setPreamp` is push-to-native only; ensure restore path covers it
  after process death (documented in §11/F-29 for ReplayGain).

---

## 14. Hi-Res / Bit-Perfect / Formats

**What it is.** Audio output introspection and control: quality badge/sheet, output device
selection, target sample-rate/bit-depth, bit-perfect, float/AAudio paths, Bluetooth codecs, and
DSD/MQA handling.

**Best behavior.** Honest reporting of the active signal chain; real format negotiation; DSD and
MQA either fully supported or clearly marked unsupported.

### Functions & wiring

| Function | Implementation | Wiring | UI entry | Status |
|---|---|---|---|---|
| Quality badge/sheet | `AudioQualityInfo`; `audio_quality_badge.dart`, `audio_quality_sheet.dart` | `PlayerCubit.enrichAudioQuality:1059`; `SettingsCubit.streamingQuality`, `currentOutputDevice` | badge tap | Full |
| Output info / negotiation | `HiResAudioService` `domain/services/hires_audio_service.dart`; `output_format_negotiation.dart`; handler `_maybeNegotiateOutputFormat:1587` | `hires_dac` channel; prefs `output_format_negotiation_enabled`, `bit_perfect_output`, `bypass_dsp_on_bit_perfect` | `audio_quality_sheet.dart:497` | Full |
| Bit-perfect | `SettingsCubit.setBitPerfectOutput:1236`, `setBypassDspOnBitPerfect:1287` | conflict-blocked with ReplayGain | quality sheet / Settings | Full |
| Target rate/depth + device select | `setTargetOutputSampleRate:1323`, `setTargetOutputBitDepth:1343`, `selectOutputDevice:1307`, `openOutputSwitcher:1316` | `HiResAudioService` | quality sheet | Full |
| Float DSP path | `float_output_controller.dart`; handler `setFloatOutputEnabled:2176` | Settings toggle `audio_sound_section.dart:770` | Full |
| AAudio Direct | `aaudio_output_controller.dart`; handler `setAaudioOutputEnabled:2227` | Settings `:786` + buffer `:799` | Full |
| BT codec control | `HiResAudioService.setBluetoothCodec/SampleRate/BitDepth/LdacQuality:341-409` | `AudioOutputInfo.bt*` | `audio_quality_sheet.dart:1440` | Full |
| DSD | `DsdDecoderHelper`; `decodeDsd` channel | handler `_resolveAudioSource:1861` routes dsf/dff; PCM decode | quality sheet note `:303` | Full (PCM) |
| DoP | `DopEncoder` `data/audio/dop_encoder.dart` | only reachable via `forceDop:true`, no caller | — | Dead |
| MQA | `MqaDecoderHelper`; `FormatAwareDecoder.decodeForFormat:36` | `FormatAwareDecoder` constructed `audio_handler.dart:972` but never called | — | Dead |

### Gaps / bugs

- **F-40 (P1):** MQA unfold is disconnected — `FormatAwareDecoder.decodeForFormat`
  (`format_aware_decoder.dart:36`) is never invoked from the playback path, so `MqaDecoderHelper`
  never runs. Either wire it in `_resolveAudioSource` or mark MQA unsupported in the quality sheet.
- **F-41 (P2):** DoP/native DSD output is not exposed (`DopEncoder` has no caller); `AudioFeatureRegistry.dsdNative`
  (`audio_feature_info.dart:142`) correctly says "not implemented". Document or implement.
- **F-42 (P2):** `FormatAwareDecoder` and `AudioPlayerBackend`/`JustAudioPlayerBackend`
  (`data/audio/audio_player_backend.dart`) are unused in `lib`; remove or reinstate.

---

## 15. Lyrics & Karaoke

**What it is.** Millisecond-synced lyrics from embedded tags, sidecar `.lrc`, LRCLIB, or YTM, with
tap-to-seek, offset calibration, plain-text fallback, and a karaoke experience.

**Best behavior.** Multi-source fallback, precise active-line tracking, user offset persisted
per-track, and a working editor + karaoke screen.

### Functions & wiring

| Function | Implementation | Wiring | UI entry | Status |
|---|---|---|---|---|
| Load lyrics | `PlayerCubit._loadLyricsForSong:1087`, `refreshLyrics:1216` | `LrcParser` `core/utils/lrc_parser.dart`; `LrclibService`; `YtmAccountService.fetchYtmLyrics:1684` | player lyrics view | Full |
| Sync + tap-to-seek | `lyrics_view.dart` (`flutter_lyric`) | `state.lyrics`, `lyricsSource`, `isLyricsVisible`; `audibleLatencyOffset` | every theme | Full |
| Source badge / search | `lyrics_view.dart` | `LyricsSource` enum `domain/models/lyrics_line.dart:3` | lyrics view | Full |
| Lyrics editor | `lyrics_editor_sheet.dart` | `onSave` | none | Dead |
| Karaoke | `karaoke_mode_screen.dart` | reads `PlayerCubit`; fake score `:92` | none | Dead |

### Gaps / bugs

- **F-30 (P1)** and **F-31 (P1)** as in §12.

---

## 16. Visualizer

**What it is.** Audio-reactive spectrum with multiple styles and an honest simulated fallback.

**Best behavior.** Native FFT when available, deterministic fallback otherwise, style persisted,
and every authored style reachable.

### Functions & wiring

| Function | Implementation | Wiring | UI entry | Status |
|---|---|---|---|---|
| Visualizer widget | `AudioVisualizer` `features/player/presentation/widgets/audio_visualizer.dart` | channels `visualizer`/`visualizer_stream`; mic permission `:132`; simulated fallback `:192` | theme slots (`classic:442`, `card:254`, `minimal:195`) | Full |
| Style picker | `SettingsCubit.setVisualizerStyle:747` | `state.visualizerStyle`; `VisualizerStyle` (8) | Settings appearance | Full |
| Track seed | `trackSeed` param `audio_visualizer.dart` | no caller passes it | — | Dead param |

### Gaps / bugs

- **F-43 (P2):** `trackSeed` is never passed, so deterministic per-track visual variation is
  dormant. Pass the current song id from theme slots.
- **F-30 (P1):** the karaoke visualizer usage is dead (same screen).

---

## 17. Audio Session, Interruption, Ducking & Outputs

**What it is.** `audio_session` configuration, call/navigation interruption handling, volume
ducking, multi-output routing, OEM/system effects policy, and adaptive/battery-aware playback.

**Best behavior.** Correct focus/duck/resume per Android audio policy; truthful multi-output
support; system-effect conflict warnings.

### Functions & wiring

| Function | Implementation | Wiring | UI entry | Status |
|---|---|---|---|---|
| Session config | `audio_session` + handler interruption `:1290-1444` | `resume_after_interruption` pref | Settings | Full |
| Ducking | `DuckingController` `data/audio/ducking_controller.dart`; `_volumeController.setDucked:1386` | `setDuckingMode/Level` `settings_cubit.dart:1684,1690` | `playback_section.dart:149` | Full |
| Multi-output | `MultiOutputRouter`; handler `setMultiOutputMode:4943` | native best-effort | `playback_section.dart:169` | Full |
| System/OEM effects | `AudioEffectsChannel.detectSystemEffects:193`, `setSystemEffectsPolicy:519` | `setSystemEffectsPolicy:1519` | `audio_sound_section.dart:626` | Full |
| Battery-aware | `BatteryAwarePlayback`; handler `:993` | `battery_optimization_card.dart` | Settings | Full |
| Audio memory | `AudioMemoryManager`; handler `:891,942` | — | — | Full |
| Adaptive buffer | `AdaptiveBufferEngine`; handler `_evaluateBufferBucket:1543` | `calculateStartBuffer:123`/`calculateOptimalBuffer:141` uncalled | — | Partial |
| Playback analytics | `PlaybackAnalytics`; only `recordBufferUnderrun` wired `:1085` | error counters unused | — | Partial |
| Latency optimizer | `LatencyOptimizer.getOptimalBufferFrames:433` | no internal caller | — | Dead |
| Playback latency telemetry | `PlaybackLatencyTracker` `core/telemetry/playback_latency_tracker.dart` | used in cubit/handler | session logs | Full |
| Session logs | `core/telemetry/audio_session_log.dart` | export in `audio_sound_section.dart:860` | Settings | Full |

### Gaps / bugs

- **F-44 (P2):** `AdaptiveBufferEngine.calculateStartBuffer`/`calculateOptimalBuffer` uncalled
  (`adaptive_buffer_engine.dart:123,141`); buckets are driven ad-hoc. Consolidate or remove.
- **F-45 (P2):** `PlaybackAnalytics.recordStreamFailure`/`recordDecodeError`/`resetErrorCounters`
  unused (`playback_analytics.dart:63,71,79`); error telemetry is effectively absent.
- **F-46 (P2):** `LatencyOptimizer.getOptimalBufferFrames` has no caller
  (`latency_optimizer.dart:433`); use it in buffer selection or remove.

---

## 18. Sleep Timer

**What it is.** Sleep Timer with duration, end-of-track, after-N-tracks, and end-of-queue modes,
with native fade-out.

**Best behavior.** All four modes reachable from the sheet; countdown survives backgrounding.

### Functions & wiring

| Function | Implementation | Wiring | UI entry | Status |
|---|---|---|---|---|
| Timer engine | `SleepTimerManager` `data/audio/sleep_timer_manager.dart` | streams `:274`; handler wrappers `:803-844` | `features/sheets/sleep_timer_sheet.dart` | Full |
| Remaining UI | `state.sleepTimerRemaining`; cubit `:2716` | — | sheet, classic dock | Full |
| End-of-queue | `startEndOfQueueTimer:174`, `onQueueCompleted:197` | no caller | — | Dead |

### Gaps / bugs

- **F-25 (P1):** see §11.

---

## 19. Theming (Aura, Dynamic Color, Player Themes)

**What it is.** Theme modes (system/light/dark/AMOLED), accent sources (Material You / artwork /
custom), the Aura palette extension, dynamic album-art color extraction, player themes, the theme
studio, and edge-to-edge system UI.

**Best behavior.** Instant, consistent theming; correct accent resolution per brightness; scheduled
day/night theming; no dead theme services.

### Functions & wiring

| Function | Implementation | Wiring | UI entry | Status |
|---|---|---|---|---|
| Theme builder | `AuraTheme` `core/theme/aura_theme.dart:126`; `PulsrPalette:8` | `customTheme:205`, presets `:495` | `main.dart:447` | Full |
| Modes | `AppThemeMode` `settings_state.dart:13` | `SettingsCubit.setThemeMode:699` | Settings segmented | Full |
| Accent sources | `ThemeColorSource` `settings_state.dart:20` | `main.dart:431`; `setCustomAccentColor:729` | Settings | Full |
| Dynamic palette | `DynamicThemeCubit` `core/theme/dynamic_theme_cubit.dart:76` | `updateFromSong:89`, `_extractPalette:133` (LRU 50, 500 ms debounce) | automatic | Full |
| Player theme picker | `SettingsCubit.setPlayerThemeMode` | `state.playerThemeMode` | `settings_screen.dart:703` | Full |
| Theme studio | `CustomThemeBuilderScreen:13` | export/import | `/theme-studio` | Full |
| System UI overlay | `SettingsCubit._syncSystemUiOverlay:708` | `main.dart:71` | automatic | Full |
| Theme scheduler | `ThemeSchedulerService` `core/services/theme_scheduler_service.dart:5` | none | — | Dead |

### Gaps / bugs

- **F-47 (P1):** `ThemeSchedulerService` (auto day/night) is never started/consumed
  (`theme_scheduler_service.dart:5`). Start it from `main.dart` or `SettingsCubit` and add a toggle.
- **F-48 (P2):** High-contrast theme `AuraTheme.highContrastTheme:135` exists but no setting
  exposes it. Add an accessibility toggle.

---

## 20. Settings

**What it is.** The settings hub: audio & sound, playback, theme/appearance, gestures, library &
scanning, YTM/online, network & proxy, storage & cache, privacy & data + backup, scrobbling,
cloud, and about; plus sub-screens.

**Best behavior.** Every visible tile works; sections are single-sourced (no dead duplicates);
destructive actions confirm; prefs round-trip reliably.

### Functions & wiring

| Function | Implementation | Wiring | UI entry | Status |
|---|---|---|---|---|
| Settings cubit | `SettingsCubit` `features/settings/cubit/settings_cubit.dart:27` | `_loadPreferences:182` (~50 prefs + secure storage + live EqualizerManager), ~90 setters | root provider | Full |
| State | `SettingsState` `settings_state.dart:43` | ~70 fields; derived `customAccentColor`, `audibleLatencyOffset`, `proxyConfig` | — | Full |
| Screen | `SettingsScreen` `presentation/settings_screen.dart:29` | sections inlined; `_section:515`, `_navTile:560`, `_switchTile:576` | `/settings` | Full |
| Audio & sound | `AudioSoundSection` `widgets/audio_sound_section.dart:29` | DSP engine, output, ReplayGain, loudness, room correction, inspector, system effects, BT latency, negotiation, float, AAudio, resampler, BPM, logs, battery | Settings | Full |
| Playback section | `PlaybackSection` `widgets/playback_section.dart:16` | sleep, gapless, resume, waveform, crossfade, hedged, adaptive, silence, ducking, multi-output, snapshot | Settings | Full |
| Proxy | `ProxySettingsScreen` `presentation/proxy_settings_screen.dart:16` | pool, import, test, presets; `setProxySettings:852` | `/proxy-settings` | Full |
| Hidden folders | `HiddenFoldersScreen` `presentation/hidden_folders_screen.dart:15` | `FolderUseCases`, `SettingsCubit` min-size/duration, rescan | `/hidden-folders` | Full |
| Scrobble stats | `presentation/scrobble_stats_screen.dart:12` | prefs written by `scrobbler_service.dart:640` | `/scrobble-stats` | Full |
| Cloud backup dashboard | `presentation/cloud_backup_dashboard_screen.dart:8` | `CloudSyncService.syncAll:126` | `/cloud-backup-dashboard` | Partial |
| Preset bundles | `applyMaximumQualityPreset:1760`, `applySmoothPlaybackPreset:1769`, `applyPoorNetworkPreset:1777` | — | Settings | Full |
| Dead duplicate widgets | `appearance_section.dart`, `gestures_section.dart`, `library_section.dart`, `privacy_data_section.dart`, `cloud_sync_card.dart`, `online_section.dart`, `cache_section.dart`, `device_profiles_section.dart` | none import them | — | Dead |
| Empty tiles | `settings_screen.dart:493` (privacy), `:500` (about); `privacy_data_section.dart:55` | `onTap: () {}` | Settings | Partial |

### Gaps / bugs

- **F-49 (P0):** `CloudBackupDashboardScreen` exposes selective toggles
  (`cloud_backup_dashboard_screen.dart:22-26,143`) but `_performSync:34` calls `syncAll()` with no
  arguments, ignoring them; history/EQ/settings toggles have no backing in `CloudSyncService`
  (`cloud_sync_service.dart:126`). Fix selection→sync or remove the toggles.
- **F-50 (P2):** Eight settings section widgets are dead duplicates of inline UI. Remove them (or
  refactor the screen to use them) to prevent divergent behavior.
- **F-51 (P2):** Privacy guarantee and About tiles are no-ops (`settings_screen.dart:493,500`);
  wire to a privacy policy / about dialog.
- **F-52 (P2):** Many settings strings are hardcoded English (cache/scrobbler/YTM web sheets,
  duration dialog `settings_screen.dart:611`, etc.) despite 455 localized keys. Route through ARB.

---

## 21. YouTube Music (Online) — GATED

**What it is.** YTM account auth, search, browse, stream resolution, downloads, and proxy support,
enabled only with `ENABLE_YTM=true` and excluded from Pure builds at the native level.

**Best behavior.** Real browse data (no fake moods), robust stream resolution with circuit
breakers, resumable downloads, and honest account/session handling.

### Functions & wiring

| Function | Implementation | Wiring | UI entry | Status |
|---|---|---|---|---|
| YTM service | `YtmService` `core/services/ytm_service.dart:119` | `ytm` channel; `YtmUrlCache`, `YtmCircuitBreaker`, `YtmRateLimiter` | — | Gated |
| Browse | `YtmBrowseService` `core/services/ytm_browse_service.dart:48` | 6 h cache | `/ytm-explore` `ytm_browse_screen.dart:12` | Gated |
| Account | `YtmAccountService` `core/services/ytm_account_service.dart:85` | secure-storage cookies; `fetchLikedSongs:1034`, `fetchHomeRecommendations:1611`, `fetchYtmLyrics:1684` | `YtmWebLoginSheet`, settings | Gated |
| Search | `YtmSearchCubit` `features/ytm_search/cubit/ytm_search_cubit.dart:13` | `YtmService.search:424`, continuation `:440` | `/ytm-search` | Gated |
| Stream resolution | handler `_resolveStreamUrl:1931`; `HedgedStreamResolver`; `YtmResolvingSource` | `YtmUrlCache` | playback | Gated |
| Downloads | `DownloadsCubit`; `YtDownloadService`; `DownloadRepositoryImpl` | `yt_download` channel; `DownloadsScreen` | `/downloads`, settings | Gated |
| YTM download UI | `YtmDownloadCubit` `features/ytm_search/cubit/ytm_download_cubit.dart:50` | pref `ytm_download_states` | song tiles | Gated |
| Proxy | `ProxySettingsScreen`; `ProxyPlugin.kt` | `setProxySettings`, `proxy` channel | `/proxy-settings` | Full |
| Cache manager | `YtmCacheManager` `core/services/ytm_cache_manager.dart:12` | handler `:1896`; settings cache section | Settings | Gated |
| XDM remote backend | `XdmBackendService:49` | class disabled `:45,151`; settings force on-device | — | Decommissioned |

### Gaps / bugs

- **F-53 (P1):** `YtmBrowseService.getMoodsAndGenres` returns hardcoded moods with fake IDs and
  Unsplash art (`ytm_browse_service.dart:166`); `startRadio` just searches "related to $videoId"
  (`:204`). Wire real moods/radio or label as experimental.
- **F-54 (P2):** `MetadataSearchService` documents "iTunes and MusicBrainz" but only iTunes is
  implemented (`metadata_search_service.dart:38` vs `:51`). Fix docs or add MusicBrainz.
- **F-55 (P2):** `YtmCacheManager.clearCache`/`pruneIfExceedsLimit` are surfaced in settings but the
  cache section has no size display; ensure size refresh after clearing.

---

## 22. Auth & Cloud Sync

**What it is.** Firebase Auth + Google Sign-In and Firestore-backed favorites/playlists sync,
available in non-Pure builds.

**Best behavior.** Graceful degradation when Firebase/network is absent; selective, observable
sync; no silent no-ops.

### Functions & wiring

| Function | Implementation | Wiring | UI entry | Status |
|---|---|---|---|---|
| Auth service | `AuthService` `core/services/auth_service.dart:10` | lazy Firebase init `:23`, Google/email sign-in `:46,86,106`, reset `:126`, signOut `:137` | `AuthSheet.show` | Full |
| Auth cubit | `AuthCubit` `features/auth/cubit/auth_cubit.dart:10` | `syncNow:167` (2 s dedupe), `signOut:207` | Settings cloud card | Full |
| Cloud sync | `CloudSyncService` `core/services/cloud_sync_service.dart:31` | `syncAll:126`; Firestore `users/{uid}`; gated by `isCloudSyncAllowed:130` + `offline_only_mode:134` | cloud dashboard | Partial |
| Cloud dashboard | `CloudBackupDashboardScreen:8` | calls `syncAll()` | `/cloud-backup-dashboard` | Partial |

### Gaps / bugs

- **F-49 (P0):** selective toggles ignored (see §20).
- **F-56 (P2):** The active cloud card (`settings_screen.dart:_buildCloudSyncCard:1697`) is not
  hidden in Pure builds, where sync is a no-op. Hide or explain.

---

## 23. Scrobbling

**What it is.** Last.fm / Libre.fm / ListenBrainz / webhook scrobbling with offline queue and
stats.

**Best behavior.** Correct now-playing + scrobble thresholds per service, offline buffering with
retry, and per-service validation.

### Functions & wiring

| Function | Implementation | Wiring | UI entry | Status |
|---|---|---|---|---|
| Scrobbler | `ScrobblerService` `core/services/scrobbler_service.dart:12` | secure keys; offline queue `:395,674`; stats `:640`; `scrobbler` channel | settings modal `settings_screen.dart:2273` | Full |
| Player hooks | `PlayerCubit:427,449` | now-playing/scrobble | automatic | Full |
| Stats screen | `ScrobbleStatsScreen:12` | reads daily log | `/scrobble-stats` | Full |

### Gaps / bugs

- None critical. (P2: strings partly hardcoded, see F-52.)

---

## 24. Tag Editor & Metadata

**What it is.** In-place ID3/container tag editing, artwork injection, batch editing, and online
metadata matching.

**Best behavior.** Atomic writes with rollback, format-aware fields, gallery/camera artwork, batch
support, and online lookup that respects offline mode.

### Functions & wiring

| Function | Implementation | Wiring | UI entry | Status |
|---|---|---|---|---|
| Tag cubit | `TagEditorCubit` `features/tag_editor/tag_editor_cubit.dart:12` | `loadTags:77`, field updates `:139`, `pickArtwork:201`, `saveTags:332`; `tag_editor` channel; `rescanSingleFile` | `/tag-editor` | Full |
| Screen | `TagEditorScreen`, `TagFieldWidget`, `ArtworkPicker` | — | song info → Edit tags | Full |
| Online metadata | `MetadataSearchService` `core/services/metadata_search_service.dart:32` | `searchOnlineMatches:251`, `applyMetadataResult:263`, offline gate `:47` | tag editor | Partial |
| Song info | `SongInfoSheet` `features/sheets/song_info_sheet.dart:30` | rating, per-song EQ/volume, BPM, share, ringtone, quality | long-press / menu | Full |

### Gaps / bugs

- **F-54 (P2):** MusicBrainz claim vs iTunes-only implementation (see §21).
- **F-57 (P2):** `SongInfoSheet` has no bookmark controls; bookmarks are reachable only from the
  Classic advanced bar (see F-23).

---

## 25. Library Tools (Duplicates, Missing Artwork, Stats, Artwork Grid)

**What it is.** Duplicate detection, missing-artwork backfill, library statistics, and an artwork
wall.

**Best behavior.** Full-scope analysis, actionable results (resolve/delete), DI-consistent
services, and accurate totals.

### Functions & wiring

| Function | Implementation | Wiring | UI entry | Status |
|---|---|---|---|---|
| Duplicate detection | `DuplicateFinderService` `core/services/duplicate_finder_service.dart:20` | metadata + duration/size + SHA-256 `:101` | `/duplicate-finder` | Partial |
| Duplicate UI | `DuplicateFinderScreen` `library/presentation/duplicate_finder_screen.dart:12` | reads `LibraryCubit.state.songs` `:32`; read-only tiles `:132` | Home chip | Partial |
| Missing artwork | `MissingArtworkService` `core/services/missing_artwork_service.dart:35` | iTunes lookup, offline gate `:60`; **no consumer** | — | Dead |
| Library stats | `LibraryStatsScreen` `library/presentation/library_stats_screen.dart:18` | `state.songs` totals, top played/artists | Home chip | Partial |
| Artwork grid | `ArtworkGridScreen` `library/presentation/artwork_grid_screen.dart:14` | `state.albums`, zoom/pinch | `/artwork-grid` | Full |

### Gaps / bugs

- **F-24 (P1):** Duplicate Finder has **no remediation** (no delete/merge), scans only the loaded
  window (`duplicate_finder_screen.dart:32`), and bypasses DI by instantiating
  `DuplicateFinderService()` directly (`:20`). Fix: use `getIt`, query the full library, and add
  keep/delete resolution with undo.
- **F-58 (P1):** `MissingArtworkService.batchFetchArtwork`/`findMissingArtworkAlbums` are unused
  (`missing_artwork_service.dart:47,104`) and fetched URLs are not persisted to `albums`. Wire a
  "Fetch missing artwork" action that writes back and refreshes.
- **F-59 (P2):** `LibraryStatsScreen` derives all metrics from the paginated window
  (`state.songs`), so totals are wrong for libraries >1,000 tracks (depends on F-07).
- **F-60 (P2):** `DuplicateFinderService.findDuplicatesSync:78` is dead.

---

## 26. Platform Integration (Widget, Notification, Intents, Android Auto, Ringtone)

**What it is.** Android home-screen widget, MediaStyle notification, hardware/headset buttons,
Android Auto media tree, external file/YouTube intents, ringtone setting, and share.

**Best behavior.** Live widget + notification with correct controls, token-protected broadcasts,
correct intent routing across flavors, and platform-gated features that hide when unsupported.

### Functions & wiring

| Function | Implementation | Wiring | UI entry | Status |
|---|---|---|---|---|
| Home widget | `WidgetService` `features/widgets/widget_service.dart:16` | keys title/artist/album/isPlaying/isFavorite/isShuffle/repeat/position/duration/next0-2/artwork; `NowPlayingWidget.kt` actions `:200`; token `:210` | launcher widget | Full |
| Widget clicks | `PlayerCubit._listenToWidgetClicks:464`, `_updateWidgetThrottled:522` | `WidgetService.listenToWidgetClicks:340` | widget | Full |
| Media notification | `PulsrAudioHandler extends BaseAudioHandler:75`; `_broadcastState:2880` | `AudioService.init:81`; `AudioService` manifest `:134` | notification/lockscreen | Full |
| Headset buttons | `click():3993` | 1 play/pause, 2 next, 3 prev | hardware | Full |
| Android Auto | `getChildren/getMediaItem/playFromMediaId/playFromSearch/search:4387-4810` | `MediaBrowserService`; YTM nodes `:4554` | Auto/car | Full |
| File/YouTube intents | `FileIntentHandler` `core/services/file_intent_handler.dart:22` | `file_opener` channel; `extractYouTubeVideoId:63`, `handleAudioUri:134` | external open | Full |
| Ringtone | `RingtonePlugin.kt`; `song_info_sheet.dart:49` | `ringtone` channel; `PlatformCapabilities.hasRingtoneManager` | song info | Full |
| Share | `SharePlus` in `backup_section.dart:59`, `audio_sound_section.dart:884`, `song_info_sheet.dart:40` | — | multiple | Full |

### Gaps / bugs

- **F-61 (P2):** `PlatformCapabilities.hasDownloads`/`hasYtm` are declared but unused
  (`core/utils/platform_capabilities.dart:74`); capability UI uses per-feature getters. Consume or
  remove for consistency.
- **F-62 (P2):** `WidgetService.listenToWidgetClicks` default-case handling should be audited to
  ensure unknown widget actions are ignored (token already protects broadcasts).

---

## 27. Profiles & Automation

**What it is.** Device profiles (apply settings per output device), settings profiles, automation
rules (triggers), and Bluetooth latency calibration.

**Best behavior.** Profiles are user-manageable, automation triggers actually fire, and calibration
is reachable.

### Functions & wiring

| Function | Implementation | Wiring | UI entry | Status |
|---|---|---|---|---|
| Device profiles | `DeviceProfileService` `domain/services/device_profile_service.dart:52` | prefs `setting_device_profile_links`, `setting_auto_device_profiles_enabled`, `setting_device_registry`; `PlayerCubit` watcher `:2608`, `applyProfile:2662` | `device_profiles_section.dart` (dead) | Partial |
| Settings profiles | `SettingsProfilesService` `domain/services/settings_profiles_service.dart:141` | prefs `setting_custom_profiles`; `applyProfile` | dead UI | Partial |
| Automation rules | `AutomationRulesService` `core/services/automation_rules_service.dart:47` | pref `setting_automation_rules`; **no trigger wiring** | — | Dead |
| BT latency calibrator | `BluetoothLatencyCalibrator` `core/services/bluetooth_latency_calibrator.dart:47` | no consumer (manual offset only) | Settings slider | Dead |
| Subsonic | `SubsonicService` `core/services/subsonic_service.dart:38` | no consumer | — | Dead |

### Gaps / bugs

- **F-38 (P2):** device profiles UI is dead (see §13).
- **F-63 (P1):** `AutomationRulesService` has persistence + backup but **no runtime triggers**
  (Bluetooth/headphone/charging observers never invoke it). Wire triggers + a rules editor.
- **F-64 (P2):** `BluetoothLatencyCalibrator` is unintegrated; expose an "auto-calibrate" action
  (a manual offset already exists at `settings_cubit.dart:1549`).
- **F-65 (P2):** `SubsonicService` is a fully authored dead feature (`subsonic_service.dart:38`);
  either build its UI or remove.

---

## 28. Localization

**What it is.** English, Spanish, and Arabic (RTL) with 455 ARB keys and runtime language
switching.

**Best behavior.** 100% of user-visible strings localized (including native/platform messages),
RTL-correct layouts, and no hardcoded English in widgets.

### Functions & wiring

| Function | Implementation | Wiring | UI entry | Status |
|---|---|---|---|---|
| ARB catalogs | `lib/l10n/app_en.arb`, `app_es.arb`, `app_ar.arb` | 455 keys, in sync | — | Full |
| Locale wiring | `main.dart:493-502` | `AppLocalizations.delegate`, `supportedLocales` | — | Full |
| Language picker | `_showLanguagePickerSheet` `settings_screen.dart:887` | `setLanguage:723`; pref `language_code` | Settings | Full |
| RTL | Flutter + `l10n_extensions.dart` | — | — | Full |
| Hardcoded strings | e.g. `settings_screen.dart:611,767`, cache/scrobbler/YTM sheets, `app_router.dart:61` | — | — | Partial |

### Gaps / bugs

- **F-52 (P2)** and **F-04 (P2):** localize remaining hardcoded strings; add an ARB lint check.

---

## 29. Privacy, Flavors & Build Gating

**What it is.** Pulsr Pure (offline, no INTERNET), YTM-enabled builds, telemetry gating, and native
compile-time exclusion of GPL YouTube code from the Play-Store flavor.

**Best behavior.** Pure builds are provably offline; gating is centralized and consistently
applied; no YouTube references in the prod artifact.

### Functions & wiring

| Function | Implementation | Wiring | UI entry | Status |
|---|---|---|---|---|
| Env config | `AppConfig` `core/config/app_config.dart:6` | `ytmEnabled:22`, `isPure:47`, `isCloudSyncAllowed:55`, `isTelemetryAllowed:51` | — | Full |
| Validation | `validateConfiguration:69` | throws on prod+YTM / prod+env=dev | startup | Full |
| Native exclusion | `android/app/build.gradle.kts:48` | `ytmEnabled`/`ytmDisabled` source sets | Gradle | Full |
| Prod isolation check | `validateProdIsolation` `build.gradle.kts:300` | scans for YouTube/NewPipe/po_token strings | CI/Gradle | Full |
| Prod manifest strip | `android/app/src/prod/AndroidManifest.xml:6` | removes INTERNET, FGS_DATA_SYNC, network perms, DownloadService | — | Full |
| Telemetry gating | `main.dart:129` | DSN only | — | Partial |
| Dead config helpers | `isPure`, `isDev`, `isTelemetryAllowed` | no external references | — | Dead |

### Gaps / bugs

- **F-02 (P2):** config helpers unused; telemetry gated on DSN only (see §2).
- **F-66 (P2):** DI registers YTM/cloud services unconditionally
  (`injection.config.dart:136-144,210-235`); Pure privacy relies on native stubs + runtime guards.
  Consider gating the graph or documenting the guarantee (comment already at `app_config.dart:19`).

---

## 30. Consolidated Gap Register

Ordered by priority. "Evidence" points at the current code; "Fix" is the recommended change.

### P0 — Correctness / user-visible breakage

| ID | Feature | Issue | Evidence | Fix |
|---|---|---|---|---|
| F-07 | Library/Scanning | `GetSongsUseCase` clamps limit to 1000, breaking pagination; Stats/Duplicates undercount | `domain/usecases/get_songs_usecase.dart:21`; `library_cubit.dart:194` | Remove/raise clamp or offset-paginate; make stats/duplicates query full library |
| F-49 | Cloud Backup | Dashboard selective toggles are ignored; history/EQ/settings toggles have no backing | `cloud_backup_dashboard_screen.dart:22-26,34`; `cloud_sync_service.dart:126` | Pass selections to `syncAll`; implement or remove unsupported toggles |

### P1 — Present but unusable / unreachable / high value

| ID | Feature | Issue | Evidence | Fix |
|---|---|---|---|---|
| F-14 | Genre browse | `GenreHierarchyView` never mounted | `genre_hierarchy_view.dart:15` | Add hierarchy toggle to Genres tab |
| F-15 | Folder browse | `FolderTreeBrowserTab` never mounted | `folder_tree_browser_tab.dart:10` | Add tree/flat toggle for deep folders |
| F-16 | Search | Fuzzy fallback bounded to 300 songs | `search_cubit.dart:134` | SQL-prefilter + fuzzy-rank over full library |
| F-11 | Library | Select-all only loads window | `library_cubit.dart:448` | Select by IDs/query |
| F-17 | Smart playlists | BPM rule stub, hidden from builder | `smart_playlist_engine.dart:313`; `smart_playlist_builder_screen.dart:543` | Add BPM column, persist, re-enable rule |
| F-18 | Playlists | `PlaylistShareService` unused | `playlist_share_service.dart:63` | Wire share buttons |
| F-24 | Library tools | Duplicate Finder read-only, window-limited, bypasses DI | `duplicate_finder_screen.dart:12,20,32` | DI + full-query + keep/delete with undo |
| F-58 | Library tools | Missing-artwork service unused | `missing_artwork_service.dart:47,104` | Add "fetch missing artwork" + persist URLs |
| F-30 | Player | Karaoke screen dead + fake score | `karaoke_mode_screen.dart:92` | Wire entry point; remove/implement score |
| F-31 | Player | Lyrics editor dead | `lyrics_editor_sheet.dart` | Add "Edit lyrics" action |
| F-23 | Player | Advanced playback bar (A-B/delay/bookmark) only Classic theme | `classic_player_theme.dart:613` | Render in shared chrome/all themes |
| F-25 | Sleep timer | `endOfQueue` mode unreachable | `sleep_timer_manager.dart:174,197` | Wire to queue completion |
| F-67 | Player | SponsorBlock has no enable/category UI | `sponsorblock_service.dart` | Add toggles + skip indicator |
| F-32 | DSP | 32-band / custom frequencies have no UI | `equalizer_manager.dart:716,1080` | Add band-count toggle + freq editor |
| F-33 | DSP | Manual preamp has no slider | `equalizer_manager.dart:876` | Add preamp control |
| F-37 | DSP | Room correction merge/IR export unused | `room_correction_service.dart:227,250` | Wire headphone stacking + FIR export |
| F-40 | Hi-Res | MQA unfold disconnected | `format_aware_decoder.dart:36` | Wire or mark unsupported |
| F-47 | Theming | Theme scheduler dead | `theme_scheduler_service.dart:5` | Start service + add toggle |
| F-53 | YTM | Browse moods hardcoded / naive radio | `ytm_browse_service.dart:166,204` | Real data or label experimental |
| F-63 | Automation | Automation rules have no triggers | `automation_rules_service.dart:47` | Wire system triggers + editor |

### P2 — Polish, consistency, dead code

| ID | Feature | Issue | Evidence |
|---|---|---|---|
| F-01 | Onboarding | "5-Band EQ" copy vs 10-band | `onboarding_screen.dart:363,385` |
| F-02 | Config | `isPure`/`isDev`/`isTelemetryAllowed` unused; Sentry DSN-only | `app_config.dart:47,51,41`; `main.dart:129` |
| F-03 | Scanning | `scanProgress`/`scanErrors` unconsumed | `media_scanner_service.dart:32` |
| F-04 | Router | English-only error page | `app_router.dart:61` |
| F-05 | Home | Discovery chip to read-only duplicate tool | `home_screen.dart:363` |
| F-06 | Home | Chips surface partial tools | `home_screen.dart:340` |
| F-08 | Scanning | `enrichAudioQualityBatch`/`computeTruePeak`/`computeLoudnessRange` dead | `media_scanner_service.dart:384,412,444` |
| F-09 | Scanning | `clearNomediaCache` never called | `media_scanner_service.dart:183` |
| F-10 | Scanning | `hardDeleteMissingSongs` no caller | `music_repository.dart:1325` |
| F-12 | Library | Favorites implemented twice | `favorites_screen.dart`; `library_screen.dart:1140` |
| F-13 | Library | Folder aggregation loads all songs in Dart | `folder_usecases.dart:42,90` |
| F-19 | Playlists | Suggestions service unused | `playlist_suggestions_service.dart:33` |
| F-20 | Playlists | `createPlaybackSnapshot` unused | `smart_playlist_engine.dart:566` |
| F-21 | Queue | Dead collaborators constructed but unused | `audio_handler.dart:1015-1057` |
| F-22 | Queue | `StreamResolutionPipeline.resolveStreamUrl` bypassed | `audio_handler.dart:1931` |
| F-26 | Player | Advanced speed range no UI | `audio_handler.dart:4034` |
| F-27 | Player | Audio normalization no UI | `audio_handler.dart:2255` |
| F-28 | Player | `saveDspSnapshot` no caller | `player_cubit.dart:2997` |
| F-29 | Player | Native ReplayGain stage dormant | `audio_handler.dart:601` |
| F-34 | DSP | `applyGenreBasedEq` dead | `equalizer_manager.dart:1791` |
| F-35 | DSP | Band solo/mute no UI | `equalizer_manager.dart:1429,1431` |
| F-36 | DSP | Latency estimate unused | `optimized_dsp_pipeline.dart:100` |
| F-38 | Profiles | Device Profiles UI dead | `device_profiles_section.dart:17` |
| F-39 | DSP | Preamp push-to-native only; verify restore after process death | `equalizer_manager.dart:876,1160` |
| F-41 | Hi-Res | DoP/native DSD not exposed | `dop_encoder.dart` |
| F-42 | Audio | `FormatAwareDecoder`/`AudioPlayerBackend` unused | `format_aware_decoder.dart`; `audio_player_backend.dart` |
| F-43 | Visualizer | `trackSeed` never passed | `audio_visualizer.dart` |
| F-44 | Audio | Adaptive buffer helpers unused | `adaptive_buffer_engine.dart:123,141` |
| F-45 | Audio | Analytics error counters unused | `playback_analytics.dart:63,71,79` |
| F-46 | Audio | `LatencyOptimizer.getOptimalBufferFrames` unused | `latency_optimizer.dart:433` |
| F-48 | Theming | High-contrast theme not exposed | `aura_theme.dart:135` |
| F-50 | Settings | Eight dead duplicate section widgets | `widgets/*_section.dart` |
| F-51 | Settings | Privacy/About no-op taps | `settings_screen.dart:493,500` |
| F-52 | i18n | Hardcoded English strings | multiple |
| F-54 | Metadata | MusicBrainz claim vs iTunes-only | `metadata_search_service.dart:38` |
| F-55 | YTM | Cache size display/refresh | `settings_screen.dart` cache section |
| F-56 | Auth | Cloud card not hidden in Pure | `settings_screen.dart:1697` |
| F-57 | Player | No bookmark controls in song info | `song_info_sheet.dart` |
| F-59 | Stats | Window-limited totals | `library_stats_screen.dart:101` |
| F-60 | Tools | `findDuplicatesSync` dead | `duplicate_finder_service.dart:78` |
| F-61 | Platform | Unused capability getters | `platform_capabilities.dart:74` |
| F-62 | Platform | Audit widget default action handling | `widget_service.dart:340` |
| F-64 | Profiles | BT calibrator unintegrated | `bluetooth_latency_calibrator.dart:47` |
| F-65 | Online | Subsonic dead feature | `subsonic_service.dart:38` |
| F-66 | Gating | DI registers YTM/cloud unconditionally | `injection.config.dart:136,210` |

---

## 31. Phased Implementation Roadmap

For the later coding pass (this document changes no code).

### Phase 1 — Data correctness (P0)
1. F-07: fix pagination/limit clamp; make Stats/Duplicates query the full library.
2. F-49: fix cloud dashboard selection or remove unsupported toggles.
3. Add regression tests for pagination and stats totals.

### Phase 2 — Dead-feature revival (P1)
4. F-24: Duplicate Finder resolve actions + DI + full query.
5. F-58: Missing artwork fetch + persist.
6. F-30/F-31: wire Karaoke + Lyrics editor.
7. F-23/F-57: advanced playback bar in all themes + song-info bookmarks.
8. F-67: SponsorBlock UI.
9. F-25: sleep timer end-of-queue.
10. F-32/F-33/F-37: 32-band EQ, preamp, room-correction merge/export.
11. F-14/F-15: genre hierarchy + folder tree views.
12. F-47/F-63: theme scheduler + automation triggers.
13. F-17/F-18/F-53: BPM smart rule, playlist share, YTM browse realism.

### Phase 3 — Reach & consistency (P1/P2)
14. F-11/F-16: select-all by query; full-library fuzzy search.
15. F-40/F-41: MQA/DSD honesty or implementation.
16. F-26/F-27/F-28: expose advanced speed, normalization, DSP snapshot save.
17. F-38/F-64/F-65: profiles UI, BT calibrator, Subsonic decision.

### Phase 4 — Cleanup & polish (P2)
18. F-21/F-22/F-42/F-44/F-45/F-46/F-60: remove or wire dead audio/service code.
19. F-50: delete dead settings widgets; F-51: wire privacy/about.
20. F-52/F-04/F-54: localization + docs accuracy.
21. F-01/F-02/F-03/F-05/F-06/F-08/F-09/F-10/F-12/F-13/F-19/F-20/F-29/F-34/F-35/F-36/F-43/F-48/F-55/F-56/F-59/F-61/F-62/F-66: remaining polish.

### Cross-cutting acceptance criteria
- Every visible control performs a real action (no `onTap: () {}` placeholders).
- Every user-facing string is in `app_en/ar/es.arb`.
- No DI-registered service without a consumer (or explicitly documented as reserved).
- Any "window-limited" computation (stats, duplicates, folders, search) is replaced with a
  full-library query or clearly labeled.
