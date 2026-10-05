# Pulsr — Feature Audit & Gap Register

> ## Remediation status — 2026-10-04 (supersedes the baseline below)
>
> Since this register was written, the listed defects were triaged and the
> verifiable gates now pass on the current tree:
>
> | Gate | Result |
> |---|---|
> | `flutter analyze --fatal-infos --fatal-warnings` | **0 issues** |
> | `dart format --set-exit-if-changed lib test` | **0 files changed** |
> | `flutter test` | **2,318 / 2,318 passed** |
> | `flutter test --coverage` | **39.1 %** lines, floor raised **3 % → 35 %** |
> | CI guard suites (hygiene, ratchets, a11y, security, fuzz, property, perf) | **green** |
>
> Closed criticals and gaps:
> - **Security:** deletes validated through `SafeFilePath` (`music_repository.dart`),
>   radio hosts reject loopback/RFC1918/link-local (`radio_station.dart`), WebView
>   navigation uses exact-domain allowlisting (`ytm_web_login_sheet.dart`).
> - **Quran Mode:** persistence/restore wired through `PlayerQuranManager` +
>   `QuranModeService`; `reapplyQuranProfile` restores the reciter profile; vocal
>   warmth setter validated and applied on release.
> - **ADR-002:** `ErrorLogger` now classifies every failure through
>   `resolveAppError` and tags crash reports with the sealed `AppError` type.
> - **Hygiene ratchets:** Player controllers all ≤ 400 lines; empty-catch ceiling
>   397 → **367**; fat-file ratchet extended to `ytm_account_service`,
>   `yt_download_service`, `ytm_service`, `playlists_screen`; raw `Text` literal
>   ratchet 24 → **17**; RTL positioning ratchet stays **0**; 245 MB of committed
>   test audio and debug logs removed from tracking.
> - **Bug fixes:** DoP byte order corrected to the v1.1 little-endian layout,
>   duplicate detection refined to same-recording (album + duration tolerance),
>   player badge row no longer overflows portrait widths, dock style sheet is
>   scrollable, unknown output rates fall back to 44.1 kHz/16-bit labels.
>
> Still open (structural, multi-sprint): DB-at-rest encryption, the remaining
> god-files (`ytm_account_service` ≈3.1k lines, `playlists_screen` ≈2.2k,
> `yt_download_service` ≈1.7k), ~367 empty catches, and coverage above ~39 %.
> The per-module scores below are the **pre-remediation baseline**.

Consolidated rating of **every module** under `lib/features`, `lib/core`, `lib/data`, and `lib/domain`.
Each module is scored on **11 dimensions, each out of 10 (the maximum possible rate)**. The
**Overall** score is the holistic module rating out of 10.

- **Date:** 2026-10-02
- **Method:** `flutter analyze --fatal-infos --fatal-warnings` → *clean (0 issues)*; eight parallel,
  evidence-based code audits (source + tests + CI + ADRs). Every gap cites `file:line`.
- **Scope:** 26 feature modules + 15 core modules + 6 data modules + 5 domain modules = **52 modules**.

> **Headline:** the README claims a verifiable **10/10 across all 11 dimensions**. At the module
> level this audit computes an aggregate of **≈ 6.6/10**. The architecture scaffolding is genuinely
> strong (clean analyze, ratchets, ADRs, fuzz/property tests), but there are concrete functional
> defects, silent-failure surfaces, security issues, and large untested presentation surfaces.

## Scoring rubric

| Dimension | A 10/10 module would have… |
|---|---|
| **1. Architecture** | Clear layering, small cohesive units, dependency inversion, no god files/objects |
| **2. Bug Density** | No known functional defects; edge cases covered |
| **3. State Management** | Single source of truth, immutable state, no state duplicated outside the store |
| **4. Error Handling** | Typed errors (ADR-002 `AppError`), no silent/swallowed failures, user-visible recovery |
| **5. Performance** | No UI-isolate heavy work, bounded work per frame, no O(n²)/N+1 regressions |
| **6. Memory Safety** | Bounded caches, deterministic disposal, no leaks / unbounded growth |
| **7. Concurrency** | Mutex/generation guards on shared mutable state; no lost updates or races |
| **8. Code Hygiene** | No dead code, no `dynamic` where avoidable, no oversized files, l10n coverage |
| **9. Security** | Input/path/URL validation, no credential leakage, no SSRF/arbitrary file ops |
| **10. Accessibility** | Semantics on every control, ≥48 dp targets, dynamic-type/RTL safe |
| **11. CI / DX / ADR** | Enforced by CI, dedicated tests, documented decisions, real coverage floor |

Dimensions marked **N/A** mean the concern does not apply to a headless/pure module; they are scored
at the module's baseline and excluded from the "weakest" callouts.

**Bands:** 9–10 excellent · 7–8 strong · 5–6 functional with real gaps · 3–4 weak/high-risk · 0–2 broken.

---

## Executive summary

### Aggregate

| Layer | Modules | Mean overall | Weakest module |
|---|:---:|:---:|---|
| `lib/features` | 26 | **6.0 / 10** | `quran_mode` (4.5) |
| `lib/core` | 15 | **7.6 / 10** | `services` (6.5) |
| `lib/data` | 6 | **6.7 / 10** | `repositories` (5.0) |
| `lib/domain` | 5 | **6.6 / 10** | `services` (5.5) |
| **Whole codebase** | **52** | **6.6 / 10** | `ytm_browse` (4.0) |

### Features

| Module | Overall | Weakest dimension(s) |
|---|:---:|---|
| `features/player` | 5.5 | Concurrency 4, Bug/Perf/Hygiene 5 |
| `features/queue` | 5.0 | Architecture/CI 4 |
| `features/quran_mode` | 4.5 | Bug/Concurrency 3 |
| `features/library` | 7.0 | Error Handling 6, A11y 6 |
| `features/home` | 6.0 | Architecture/Error/Hygiene/A11y 5 |
| `features/search` | 7.0 | Performance 5 |
| `features/smart_playlist_builder` | 7.0 | A11y 4 |
| `features/settings` | 5.7 | Bug/State/Error/Perf/Hygiene 5 |
| `features/shell` | 7.2 | Bug 6, A11y 7 |
| `features/sheets` | 6.0 | Bug 5, A11y 5 |
| `features/widgets` | 6.5 | Bug/CI 5 |
| `features/auth` | 5.5 | Error/Hygiene 4, Security 5 |
| `features/downloads` | 7.0 | Error/CI 6 |
| `features/ytm_search` | 6.5 | A11y 5 |
| `features/ytm_browse` | 4.0 | Arch/State/Error 3, CI 2 |
| `features/radio` | 5.0 | Arch/State/Concurrency 4 |
| `features/playlists` | 6.0 | A11y 4.5, CI 4 |
| `features/playlist_detail` | 6.0 | CI 4 |
| `features/tag_editor` | 5.5 | Bug 4.5, CI 3.5 |
| `features/album_detail` | 6.0 | CI 3.5 |
| `features/artist_detail` | 5.8 | CI 3.5 |
| `features/folder_detail` | 6.0 | CI 3.5 |
| `features/genre_detail` | 6.3 | CI 3.5 |
| `features/year_detail` | 6.3 | CI 3.5 |
| `features/onboarding` | 5.5 | Architecture/A11y 4 |
| `features/splash` | 7.5 | Concurrency/Error 7 |

### Core

| Module | Overall |
|---|:---:|
| `core/theme` | 8.5 |
| `core/bloc` | 9.0 |
| `core/motion` | 9.0 |
| `core/config` | 8.0 |
| `core/responsive` | 8.0 |
| `core/constants` | 7.5 |
| `core/errors` | 7.5 |
| `core/telemetry` | 7.5 |
| `core/di` | 7.0 |
| `core/network` | 7.0 |
| `core/performance` | 7.0 |
| `core/router` | 7.0 |
| `core/utils` | 7.0 |
| `core/widgets` | 7.0 |
| `core/services` | 6.5 |

### Data & Domain

| Module | Overall |
|---|:---:|
| `data/visualizer` | 8.0 |
| `data/lyrics` | 8.0 |
| `data/db` | 7.0 |
| `data/audio` | 6.0 |
| `data/scanner` | 6.0 |
| `data/repositories` | 5.0 |
| `domain/repositories` | 7.5 |
| `domain/interfaces` | 7.5 |
| `domain/usecases` | 6.5 |
| `domain/models` | 6.0 |
| `domain/services` | 5.5 |

---

## Cross-cutting (systemic) gaps

These recur across modules and are the highest-leverage fixes.

1. **ADR-002 `AppError` is essentially unadopted.** `sealed AppError` exists and is tested
   (`lib/core/errors/app_error.dart`, `test/errors/app_error_taxonomy_test.dart`) but there are
   **zero production references** in `lib/features` and `lib/core/services`. Modules use raw
   `Exception` (auth), `Either<AppFailure>` (downloads), or string classifiers (YTM search).
   `AppFailure` (`core/errors/failures.dart:4`) and the sealed `Result` (`core/utils/result.dart:10`)
   are two unrelated types with the same name.
2. **Silent-failure surface is systemic.** Empty-catch ratchets allow **435** (`test/architecture/code_hygiene_test.dart:19`)
   vs **397** (`test/architecture/empty_catch_ratchet_test.dart:15`) empty `catch {}` blocks; ~155 sit in
   `lib/data/audio`, 63 in `lib/core`, 38 in `features/settings`.
3. **Coverage floor is 3.0 %** (`scripts/check_coverage.py:12`) — CI "coverage" is effectively
   unenforced, which is why large presentation surfaces (settings 1747-line screen, playlists 2211,
   home 2073, onboarding 1021) and whole features (queue, ytm_browse, all detail screens) ship untested.
4. **Fat-file ratchet covers only 5 files** (`test/architecture/fat_file_ratchet_test.dart:20-26`). The largest
   files are excluded: `ytm_account_service.dart` (3384), `yt_download_service.dart` (1879),
   `ytm_service.dart` (1735), `playlists_screen.dart` (2211), `home_screen.dart` (2073),
   `settings_screen.dart` (1747), `equalizer_sheet.dart` (8050).
5. **Security-critical: arbitrary file deletion.** `MusicRepository.deleteSongs`
   (`lib/data/repositories/music_repository.dart:1951-1965`) calls `File(song.path).delete()` with
   no `SafeFilePath` containment, so any DB-persisted path (sync import, corrupted/edited backup) can
   delete arbitrary files.
6. **Security-critical: WebView host allowlist bypass.** `_isTrustedHost`
   (`lib/features/auth/presentation/ytm_web_login_sheet.dart:247-248`) uses
   `host.contains('.google.')` / `host.contains('.youtube.')`, so `evil.google.com.attacker.com` and
   `x.youtube.evil.com` pass inside the credential WebView.
7. **Security: radio URL SSRF.** `RadioStation.isHttpUrl` accepts any `http(s)` host including
   `localhost`, RFC1918 and `169.254.169.254`; the player can be pointed at internal endpoints.
8. **DB is unencrypted** (`lib/data/db/app_database.dart:106`), storing full library paths and play
   history in plaintext despite the README privacy positioning.
9. **Player feature has real functional defects** (see player/quran below): Quran Mode is never
   persisted/restored, the "Reset Profile" button is inverted, preamp compensation is dead, and queue
   read-modify-write ops are not serialized by the advertised mutex.
10. **ADR coverage has expanded.** Fifteen ADRs now cover player/DSP/queue/errors/cache plus DI, UI
    sound design, router, responsive, network/proxy, telemetry, settings, playlists and domain
    layering (ADR-003 corrected); there is still none for library.

---

## Features

### lib/features/player — **5.5 / 10**

| Dimension | Score | Key gap (evidence) |
|---|:---:|---|
| Architecture | 6 | Strong controller/manager split + 15 ADRs, but `equalizer_sheet.dart` is an 8050-line God-widget and `PlayerQuranManager` is dead code (`player_quran_manager.dart:10`). |
| Bug Density | 5 | `reapplyQuranProfile` restores the pre-Quran snapshot instead of the reciter profile (`player_playback_options_quran.dart:264-273`); Quran snapshot is a library-scoped global (`:10`); `preampDb` dead (`quran_mode_profile.dart:93`). |
| State Management | 6 | Mute state lives outside state (`player_playback_options_controller.dart:279-311`); global Pre-Quran snapshot shared across instances. |
| Error Handling | 6 | Silent swallows: `player_queue_slots.dart:424-426`, `player_cubit.dart:644`, `player_queue_warming.dart:24,51`; unguarded native `setQuranAmbience`. |
| Performance | 5 | `_resolveMediaItemId` does `Map.containsValue` in a loop over up to 1000 entries → O(n²) (`player_cubit.dart:339-352`); sequential native inserts (`player_queue_slots.dart:569-578`). |
| Memory Safety | 6 | `_slotLookupCache` grows monotonically, never pruned (`player_queue_controller.dart:35,110`); global snapshot retained. |
| Concurrency | 4 | `_queueMutex` used in exactly one method (`player_queue_slots.dart:396`); add/reorder/remove compute from pre-`await` snapshot → lost updates (`:467,531,580`); no generation guard on Quran toggle (`..._quran.dart:71`). |
| Code Hygiene | 5 | 400-line controller rule evaded via `part` files (`player_queue_slots.dart` 629, `player_dsp_effects.dart` 722); 3 injected deps accepted then ignored (`player_cubit.dart:113,118,119`); heavy `dynamic`. |
| Security | 7 | Positive: 25 MB IR cap + `SafeFilePath.validate` (`player_dsp_effects.dart:427-434`). Gap: arbitrary-EQ/LiveProg strings sent to native with no length/shape validation (`arbitrary_eq_sheet.dart:52-61`). |
| Accessibility | 7 | Good Semantics on chrome/seek bar; `QuranPanel` slider lacks `semanticFormatterCallback`; a11y suite only covers chrome/waveform. |
| CI / DX / ADR | 7 | Strong CI + 15 ADRs; `pubspec` declares Flutter `>=3.41.0`, matching the post-3.41 `onReorderItem` usage; ADR-003 corrected. |

**Top gaps**
1. **Quran Mode is never persisted or restored** — `QuranModeService` injected but never called (`player_cubit.dart:118`), `PlayerQuranManager` dead, enable/style methods never call `setEnabled`/`setStyle` (`player_playback_options_quran.dart:71-109`). *Impact:* mode resets every launch.
2. **"Reset Profile" undoes Quran Mode** — `reapplyQuranProfile` restores the pre-Quran snapshot whenever one exists (`player_playback_options_quran.dart:264-269`), which is always while enabled.
3. **Quran `preampDb` is dead** — captured/declared but never applied (`quran_mode_profile.dart:78,93`), so boosted bands can clip.
4. **Concurrent queue mutations lose tracks** — read-modify-write from a stale snapshot; `_queueMutex` not used (`player_queue_slots.dart:467-548`).
5. **Per-song rating writes bypass the DI singleton** — `SongRatingStore()` constructed per call (`player_playback_options_controller.dart:188`) vs `@singleton` in DI; lost updates.
6. **O(n²) track-id resolution** — `containsValue` over a 1000-entry map (`player_cubit.dart:339-352`).

**Test coverage:** deep cubit/controller tests (`player_cubit_test.dart` 1365 lines, decomposition, queue soak, wiring). Missing: any Quran enable/disable/persist test; concurrent `addToQueue` lost-update test.

---

### lib/features/queue — **5.0 / 10**

| Dimension | Score | Key gap (evidence) |
|---|:---:|---|
| Architecture | 4 | Single 475-line `StatelessWidget`, no cubit; Auto-DJ/save/clear live in `PopupMenuButton.onSelected` and call `getIt` directly (`queue_screen.dart:45-183,103,123,158,171`). |
| Bug Density | 6 | `isCurrent` compares only `song.id` (`:309`); reorder undo replays stale raw indices (`:288-306`). |
| State Management | 5 | Handlers snapshot `cubit.state` before `await` then mutate it (`:46-47`). |
| Error Handling | 6 | Undo/failure snackbars present; success branch awaits `addSongsToPlaylist` unguarded (`:170-179`) → partial saves report success. |
| Performance | 5 | Auto-DJ calls `getAllSongs()` on the UI isolate (`:102-103`); per-build O(n) `slotKeys`/`occurrences` (`:244-251`). |
| Memory Safety | 7 | No controllers/timers; snackbars cleared. |
| Concurrency | 5 | No guard against overlapping menu actions; queue not re-checked after the `getAllSongs` await. |
| Code Hygiene | 5 | Business logic in UI; magic menu strings; raw `toIso8601String().substring(0,10)`. |
| Security | 7 | No path/URL handling; playlist name passed to use case. |
| Accessibility | 6 | Tile + drag-handle semantics and ≥48 dp targets; reorder list itself not annotated reorderable. |
| CI / DX / ADR | 4 | **Zero tests** reference `QueueScreen` anywhere in `test/`. |

**Top gaps**
1. **No test coverage at all** — clear/shuffle/Auto-DJ/save/undo are untested.
2. **Business logic in the presentation layer** — reaches the service locator directly (`queue_screen.dart:103,123,158,171`).
3. **Stale-state menu operations** — "save" sends the pre-`await` `songIds` while playback may have advanced (`:156-157`).
4. **Partial playlist save reports success** (`:170-179`).
5. **Whole-library load on the UI isolate** for Auto-DJ (`:102-103`).

**Test coverage:** none. Queue persistence only covered at cubit/codec level (`queue_slot_codec_test.dart`, ADR-006).

---

### lib/features/quran_mode — **4.5 / 10**

| Dimension | Score | Key gap (evidence) |
|---|:---:|---|
| Architecture | 4 | 35-line screen delegating to a player-owned panel; `QuranModeService` and `PlayerQuranManager` are dead, so ownership is split and partly unused. |
| Bug Density | 3 | Persistence never happens; reset inverted; `preampDb` unused; `setQuranAmbience` unclamped/uncatch (`player_playback_options_quran.dart:111-120`). |
| State Management | 4 | `isQuranModeEnabled`/`quranReciterStyle` in `DspSlice` are not persisted; global restore snapshot (`..._quran.dart:10`). |
| Error Handling | 4 | Apply/restore only log on failure with no user-visible state (`:171-176,256-261`); toggle can show "on" while partially applied. |
| Performance | 6 | Small surface; slider calls `setReverb` per drag with no debounce (`:111-120`). |
| Memory Safety | 6 | Global snapshot retained (cleared on disable). |
| Concurrency | 3 | No generation guard on rapid on→off (`:71-100`); `unawaited(_applyQuranProfile(...))` races style changes (`:102-108`). |
| Code Hygiene | 5 | Dead manager + unused field + global mutable state. |
| Security | 8 | Enum-only input; no secrets/paths. |
| Accessibility | 5 | Dock button labelled; `_QuranSliderTile` raw `Slider` with no `semanticFormatterCallback` / label (`quran_mode_sheet.dart:504-510`); style chips lack selection semantics. |
| CI / DX / ADR | 3 | No dedicated tests; no ADR; absent from CI suites. |

**Top gaps:** (1) state lost on every restart; (2) reset button undoes Quran Mode; (3) preamp headroom never applied; (4) no concurrency guard / error surface on enable; (5) `setQuranAmbience` uncaught/unclamped; (6) zero feature-level tests.

---

### lib/features/library — **7.0 / 10**

| Dimension | Score | Key gap (evidence) |
|---|:---:|---|
| Architecture | 7 | `library_screen.dart` 1510 lines mixes tab management, persistence and 8 tab builders (`:168-173`); rating sort leaks into cubit (`library_cubit.dart:221-249`). |
| Bug Density | 7 | Stale `_activeTabs` race in `_rebuildTabController` (`library_screen.dart:313-316`); duplicate key ignores duration/album (`duplicate_finder_sheet.dart:61-63`). |
| State Management | 8 | Freezed + optimistic favorites reconciliation + per-song mutex (`library_cubit.dart:308-536`); minor uncleared `infoMessage`/`errorMessage`. |
| Error Handling | 6 | 5 empty catches incl. snapshot load (`library_cubit.dart:114-125`) and YTM sync (`library_favorites_tab.dart:445,654`); cap reported as `errorMessage` (`:596-598`). |
| Performance | 7 | Rating sort awaits per-song prefs lookup over 5000 rows (`library_cubit.dart:231-238`); stats re-sorts full list on UI isolate (`library_stats_screen.dart:186-215`). |
| Memory Safety | 7 | Full-library snapshot retained (`library_stats_screen.dart:39`); snapshot + 5000-rating window coexist. |
| Concurrency | 8 | Ref-counted per-song mutex + generation token (`library_cubit.dart:408-536,143,169`). |
| Code Hygiene | 7 | 1510-line screen; duplicated dismissible blocks. |
| Security | 9 | No secrets; clipboard import sanitized (`library_favorites_tab.dart:564-569`). |
| Accessibility | 6 | Some widgets annotated; tabs/grid song tiles and grid alphabet rail lack semantics (`library_songs_tab.dart:76-160`). |
| CI / DX / ADR | 8 | CI ratchets apply; only 3 feature tests for 19 files; no ADR. |

**Top gaps:** (1) UI-isolate rating sort with per-song I/O (`library_cubit.dart:231-238`); (2) silent corrupt-snapshot catch (`:114-125`); (3) duplicate key collision → destructive delete of distinct files (`duplicate_finder_sheet.dart:61-63`); (4) full list retained + re-sorted per rebuild (`library_stats_screen.dart:39,186-215`); (5) 1510-line screen; (6) grid tiles lack semantics.

**Test coverage:** `library_cubit_test` (view mode/selection/favorites/pagination) + grid/alphabet/duplicate/widget tests. Missing: 14 presentation screens/tabs, favorite rollback/mutex, deleteSelectedSongs, tab persistence.

---

### lib/features/home — **6.0 / 10**

| Dimension | Score | Key gap (evidence) |
|---|:---:|---|
| Architecture | 5 | `home_screen.dart` is 2073 lines / ~83 KB holding 8+ private widgets and scan/permission logic (`:113-2193`). |
| Bug Density | 6 | Category-cache prune runs before insert and can evict/overshoot (`home_cubit.dart:117-131`); notification-denied flag cleared globally (`home_screen.dart:428-451`). |
| State Management | 6 | Hand-rolled `HomeState` (no `==`/`hashCode`) → extra rebuilds (`home_cubit.dart:14-24`). |
| Error Handling | 5 | 6 empty catches incl. permission check/request (`home_screen.dart:2052-2084`) and recommendation/trending fallbacks (`home_cubit.dart:150,155`). |
| Performance | 6 | Stream rebuilt per `_currentLimit` change (`home_screen.dart:1566-1569`); `_scaledCarouselHeight` recomputed per build. |
| Memory Safety | 6 | Up to 20 cached category futures holding full track lists (`home_cubit.dart:74,97`). |
| Concurrency | 7 | Per-category fetch tokens + identical-future guard (`home_cubit.dart:81,172,183`). |
| Code Hygiene | 5 | 2073-line file; inline literal styling. |
| Security | 9 | No secrets; standard permission handling. |
| Accessibility | 5 | Only 2 Semantics sites (`home_screen.dart:354,1178`); carousel/chips/recent tiles unlabeled. |
| CI / DX / ADR | 6 | Only `home_quick_cards_test` (3 overflow tests); no HomeCubit unit test; no ADR. |

**Top gaps:** (1) 2073-line screen; (2) permission failures swallowed (`:2052-2084`); (3) HomeCubit has zero tests; (4) cache eviction correctness (`home_cubit.dart:117-128`); (5) hand-rolled state without equality; (6) recently-played stream re-created per limit change.

**Test coverage:** `home_quick_cards_test` only. Missing: HomeCubit TTL/eviction/token, permission/scan flow, pagination sections, offline toggle.

---

### lib/features/search — **7.0 / 10**

| Dimension | Score | Key gap (evidence) |
|---|:---:|---|
| Architecture | 7 | Cubit delegates matching to pure `SearchAlgorithmUtils`; screen 1520 lines mixing 3 tab bodies (`search_screen.dart:894-1487`). |
| Bug Density | 7 | `_filterWithFuzzy` runs twice with re-sort (`search_cubit.dart:356-378`); `_generation` bumped twice (`:71,313`). |
| State Management | 8 | Freezed + generation guard + debounce + exclusion cache (`search_cubit.dart:83-85,312-350`); `savedSearches` is a separate `ValueNotifier` (`:122`). |
| Error Handling | 6 | Empty catches on legacy decode/history/derived lookups (`search_cubit.dart:214,281,290`); generic `'Search failed'` (`:408`). |
| Performance | 5 | Levenshtein fuzzy filter over up to 500 results on the UI isolate; 2-char fallback doubles work (`search_cubit.dart:346-378`, `search_algorithm_utils.dart:173-244`). |
| Memory Safety | 7 | `_normCache` LRU 1000; results capped 200/500. |
| Concurrency | 8 | Generation counter + cancellation prevents stale emissions. |
| Code Hygiene | 6 | 1520-line screen; raw literal category lists/strings. |
| Security | 9 | Query bounded to 64 chars; no secrets. |
| Accessibility | 6 | Tooltips only; no `Semantics` in the module. |
| CI / DX / ADR | 8 | Strong cubit suite; large-library perf test is a static harness only; no ADR. |

**Top gaps:** (1) synchronous fuzzy matching on the UI isolate; (2) double pipeline pass; (3) generic error message; (4) silent history persistence failures; (5) `savedSearches` outside Freezed state; (6) single whole-screen `BlocBuilder` (`search_screen.dart:255`).

**Test coverage:** excellent cubit-level. Missing: `search_screen` widget tests, 2-char fallback branch, exclusion-folder caching, isolate perf assertion.

---

### lib/features/smart_playlist_builder — **7.0 / 10**

| Dimension | Score | Key gap (evidence) |
|---|:---:|---|
| Architecture | 7 | Clean cubit/state/screen split; builder runs a preview on construction (`smart_playlist_builder_cubit.dart:29-34`). |
| Bug Density | 7 | `close()` cancels preview without await (`:231`); `initWithPlaylist` called during `create:` (`screen:32`). |
| State Management | 8 | Freezed + `_previewGen` + 150 ms debounce + cap 100 (`:20,111-143`). |
| Error Handling | 8 | Validation + exception handling + logged preview failure; no empty catches. |
| Performance | 7 | Preview capped; debounced; cap boundary untested. |
| Memory Safety | 8 | `previewSub` replaced/cancelled; list bounded. |
| Concurrency | 7 | Generation guard; `savePlaylist` has no in-flight guard (UI mitigates). |
| Code Hygiene | 7 | 764-line screen; unlocalized hints (`screen:199,768-796`). |
| Security | 9 | Criteria serialized; name/value validated. |
| Accessibility | 4 | **Zero `Semantics`**; 5+ identical dropdowns per rule unlabelled (`screen:634-734`). |
| CI / DX / ADR | 6 | Covered indirectly by audit tests; no dedicated test file; no ADR. |

**Top gaps:** (1) zero accessibility affordances; (2) `initWithPlaylist` during provider creation; (3) constructor side-effect preview; (4) `close()` doesn't await preview cancel; (5) no dedicated cubit test; (6) unlocalized hints.

**Test coverage:** preview debounce/truncation + validation via `p1_bug_fixes_test`/`audit_bug_fixes_test`. Missing: cap boundary, edit/save round-trip, `initWithPlaylist`, screen widget test. (`SmartPlaylistRuleBuilder` is dead production code kept alive only by an old-API test.)

### lib/features/settings — **5.7 / 10**

| Dimension | Score | Key gap (evidence) |
|---|:---:|---|
| Architecture | 6 | God-object cubit (1376 lines, ~80 fields); `part` mixins need mirror stubs (`settings_cubit.dart:38-40`, `settings_proxy_actions.dart:339-366`); `settings_screen.dart` 1747 lines. |
| Bug Density | 5 | `unawaited()` inside `try` never catches persistence errors (`settings_cubit.dart:436-444`); ~20 audio setters omit dirty tracking (`settings_audio_actions.dart:628-631,736-790`). |
| State Management | 5 | Dirty-field reconciliation omits `floatOutputEnabled`, `ducking*`, `hedgedResolutionEnabled`, `adaptiveQualityEnabled`, `aaudio*`, DSP fields → in-flight reload silently reverts them (`settings_cubit.dart:788-947`). |
| Error Handling | 5 | Unguarded `prefs.set*` (`settings_cubit.dart:1076-1084`); secure-storage write failure swallowed while state claims a password is set (`settings_proxy_actions.dart:114-123`); 38 empty catches; unguarded platform poll (`headphone_safety_sheet.dart:54-77`). |
| Performance | 5 | Single unselective `BlocBuilder` wraps the whole screen (`settings_screen.dart:183-229`); unbounded static accent `_colorCache` (`settings_state.dart:193-196`). |
| Memory Safety | 7 | Controllers/timers disposed in most screens. |
| Concurrency | 6 | Load/migration mutex+generation guarded (`settings_cubit.dart:118-120,698-700`); `set*` writes unserialized + incomplete reconciliation. |
| Code Hygiene | 5 | 38 empty catches; `as dynamic` double-cast (`settings_cubit.dart:1217-1224`); `debugPrint` instead of `ErrorLogger` (`settings_proxy_actions.dart:15`); 1747-line screen. |
| Security | 7 | Proxy password in secure storage + migration + plaintext purge (`settings_cubit.dart:583-610`), IPv6-aware validator, `SafeFilePath` on backup; swallowed secure-write is the weak spot. |
| Accessibility | 6 | Good Semantics on pills/sliders; accent swatches are bare `GestureDetector` with no label/selected (`settings_category_sections_a.dart:111-147`). |
| CI / DX / ADR | 6 | Wiring + fat-file ratchets; coverage floor 3 %; no ADR. |

**Top gaps:** (1) incomplete dirty-field reconciliation → toggles revert (`settings_cubit.dart:788-947`); (2) whole-screen rebuild (`settings_screen.dart:183-229`); (3) `unawaited` in `try` (`:436-444`); (4) silent secure-storage failure (`settings_proxy_actions.dart:114-123`); (5) unguarded 500 ms platform poll (`headphone_safety_sheet.dart:54-77`); (6) accent swatches inaccessible.

**Test coverage:** good cubit/proxy/UI tests. Missing: backup import/export, theme-schedule, cast/headphone-safety/widgets, and any settings a11y test.

---

### lib/features/shell — **7.2 / 10**

| Dimension | Score | Key gap (evidence) |
|---|:---:|---|
| Architecture | 7 | Clear separation (`nav_destinations.dart:24-72`); `app_shell.dart` still mixes back-nav/tab-history/system-UI/layout. |
| Bug Density | 6 | `_restoreLastShellTab` hardcodes index `< 5` (`app_shell.dart:110`); static locale cache never evicted (`nav_destinations.dart:30`). |
| State Management | 7 | `ValueNotifier` dock mode + `BlocSelector`/`BlocListener` for player. |
| Error Handling | 7 | Navigation try/catch with fallback; dock persistence errors swallowed (`dock_style_controller.dart:30,41`); 5 empty catches. |
| Performance | 8 | GpuBudget gates `BackdropFilter`, RepaintBoundary, memoized destinations, debounced sync. |
| Memory Safety | 8 | All timers/subs/notifiers disposed. |
| Concurrency | 7 | 200 ms nav throttle + 50 ms dock debounce + post-frame coalescing. |
| Code Hygiene | 7 | 5 empty catches; 864-line sidebar not under any ratchet. |
| Security | 8 | No sensitive state; shortcuts suppressed while editing. |
| Accessibility | 7 | Nav items have semantics; inspector tabs/drag handle and logo expand are bare `GestureDetector` (`tablet_side_inspector.dart:145-243`, `landscape_sidebar.dart:411-423`). |
| CI / DX / ADR | 6 | 8 focused tests; no ADR; fat-file ratchet excludes two large files; 3 % floor. |

**Top gaps:** (1) inspector tabs not accessible (`tablet_side_inspector.dart:145-243`); (2) static unbounded locale cache; (3) hardcoded `< 5` tab bound; (4) unlabeled logo-expand/peek gestures; (5) silent dock-preference I/O; (6) 864/669-line files unratcheted.

---

### lib/features/sheets — **6.0 / 10**

| Dimension | Score | Key gap (evidence) |
|---|:---:|---|
| Architecture | 6 | `song_info_sheet.dart` is a 1108-line monolith with 5 private widgets. |
| Bug Density | 5 | `AppLifecycleListener` only disposed on resume → leak if never resumed (`song_info_sheet.dart:140-170`); `HeadphoneProfilesRepository()` re-instantiated (`:805,815`); un-awaited `openWriteSettings` (`:169`). |
| State Management | 6 | Local `setState`/`StatefulBuilder`; process-global static mutation lock (`add_to_playlist_sheet.dart:50`). |
| Error Handling | 6 | `_shareSong` has no try/catch (`song_info_sheet.dart:51-64`); add-to-playlist well handled. |
| Performance | 7 | `sleep_timer_sheet.dart:34` `BlocBuilder` with no `buildWhen` rebuilds on every player tick. |
| Memory Safety | 6 | Lifecycle-listener leak above is the main defect. |
| Concurrency | 6 | Static lock prevents duplicate adds but is never reset on dispose. |
| Code Hygiene | 6 | 1108-line sheet; large inline UI. |
| Security | 7 | Share path existence-checked; ringtone uses constrained channel. |
| Accessibility | 5 | 5-star rating is bare `GestureDetector`+`Icon` with no semantics (`song_info_sheet.dart:961-983`); sort options expose no selected/direction semantics (`sort_filter_sheet.dart:74-91`). |
| CI / DX / ADR | 6 | 3 dedicated tests; no sheets a11y or ringtone/share tests; no ADR. |

**Top gaps:** (1) inaccessible rating stars; (2) lifecycle-listener leak / unhandled retry; (3) unguarded `_shareSong`; (4) no sort semantics; (5) unselective sleep-timer `BlocBuilder`; (6) global mutable lock set.

---

### lib/features/widgets — **6.5 / 10**

| Dimension | Score | Key gap (evidence) |
|---|:---:|---|
| Architecture | 7 | Well-scoped `@lazySingleton` with layered caches and progressive API. |
| Bug Density | 5 | `_ensureAppGroup` marks configured even when `setAppGroupId` threw (`widget_service.dart:29-42`); stale-artwork dead end if cached file evicted (`:170-182`). |
| State Management | 7 | Service-owned caches + `_contentVersion`; appropriate. |
| Error Handling | 7 | Pervasive try/catch + `ErrorLogger`, timeouts, client closed. |
| Performance | 7 | Caches + queue cap 3 + progress-only path; `updateNowPlaying` ~15 sequential writes (`:132-203`). |
| Memory Safety | 7 | In-memory LRUs capped 50; disk pruned; raw-byte cache holds up to 50 images. |
| Concurrency | 7 | Single-flight artwork resolver + pending queue + generation check. |
| Code Hygiene | 7 | 525 lines; triplicated `updateWidget` blocks (`:198-253`). |
| Security | 6 | Click URI allowlisted, but remote artwork fetch accepts arbitrary `http(s)` metadata URLs with no scheme restriction (`:362-384`). |
| Accessibility | 6 | Home-widget strings hardcoded English, never localized (`:134-140`). |
| CI / DX / ADR | 5 | No dedicated `widget_service_test.dart`; incidental coverage only; no ADR. |

**Top gaps:** (1) app-group flag set on failure; (2) stale-artwork dead end; (3) hardcoded widget strings; (4) no scheme restriction on fetched artwork URLs; (5) triplicated widget push; (6) no dedicated tests.

---

### lib/features/auth — **5.5 / 10**

| Dimension | Score | Key gap (evidence) |
|---|:---:|---|
| Architecture | 6 | Cubit/service split clean, but `ytm_web_login_sheet.dart` is 2591 lines mixing network/session/persistence/UI. |
| Bug Density | 5 | Latent host-policy bypass; `cookieManager.setCookie` not awaited inside `try` (`:529-538`). |
| State Management | 6 | `AuthCubit` uses `PulsrCubit`/`safeEmit` well; web login is ~20 ad-hoc bools/timers. |
| Error Handling | 4 | `AuthService` throws raw `Exception` (`auth_service.dart:50,90,110`); `_mapAuthError` only handles `FirebaseAuthException`/`PlatformException` (`auth_cubit.dart:154-197`); `syncNow` swallows (`:256`); no `AppError`. |
| Performance | 6 | 2–10 s auth poll + JS scan; cookie read across 7 domains per check. |
| Memory Safety | 7 | Timers/notifier/controllers disposed; in-flight flag cleared. |
| Concurrency | 7 | Poll generation counter + in-flight dedupe + static `_isShowing`. |
| Code Hygiene | 4 | Hardcoded English in recovery card/banners (`:996,1021,2183-2189`); `debugPrint` instead of `ErrorLogger`. |
| Security | 5 | Secure cookies + hardened WebView are good, but `_isTrustedHost` uses `host.contains('.google.')`/`host.contains('.youtube.')` (`:247-248`) → phishing/open-redirect. |
| Accessibility | 6 | Semantics on progress; many status banners unlabeled. |
| CI / DX / ADR | 5 | Only `google_login_recovery_test` + webview settings in security tests; no `AuthCubit`/sheet test. |

**Top gaps:** (1) host allowlist bypass (`:247-248`); (2) raw `Exception` not mapped to user copy (`auth_service.dart:50,90,110`); (3) `syncNow` silent catch (`auth_cubit.dart:256`); (4) `errorMessage` is `String?` not `AppError?` (`auth_state.dart:24`); (5) un-awaited `setCookie` (`:529-538`); (6) hardcoded recovery strings.

---

### lib/features/downloads — **7.0 / 10**

| Dimension | Score | Key gap (evidence) |
|---|:---:|---|
| Architecture | 8 | Cubit → use cases → repository interface; widgets split cleanly. |
| Bug Density | 7 | `_selectedVideoIds` never pruned when tasks disappear/filter changes (`downloads_screen.dart:42,390`); `filteredTasks[index - 2]` assumes list didn't shrink. |
| State Management | 8 | Immutable state with equality + precomputed sorted list; `BlocSelector` narrows rebuilds. |
| Error Handling | 6 | Uses `Either<AppFailure>` not the sealed `AppError`; UI string-matches errors; `RefreshIndicator` ignores load failures (`:459-468`). |
| Performance | 8 | 100 ms progress throttle, 300 ms stats debounce, trailing coalescing. |
| Memory Safety | 8 | Timers cancelled, mutex awaited in `close()`, maps pruned. |
| Concurrency | 8 | `Mutex` single-writer tombstones, resubscribe backoff, single-flight stats. |
| Code Hygiene | 6 | Hardcoded English: `'selected'`, `'Select all'`, `'Downloading …'`, remove-confirm (`:133,150-152,314,659`). |
| Security | 8 | Filename/extension sanitization tested; no credentials. |
| Accessibility | 6 | Overflow menu semantic; progress indicators lack `Semantics(value:)` (`download_tile.dart:326`). |
| CI / DX / ADR | 6 | Widget + chaos tests; no `DownloadsCubit` unit test / `DownloadsScreen` test. |

**Top gaps:** (1) selection not pruned → wrong-item deletion (`:42,390`); (2) untranslated strings; (3) error-taxonomy divergence; (4) progress semantics; (5) no cubit unit test; (6) silent refresh failures.

---

### lib/features/ytm_search — **6.5 / 10**

| Dimension | Score | Key gap (evidence) |
|---|:---:|---|
| Architecture | 7 | Search + download cubits; ownership correctly delegated to `DownloadsCubit` (`ytm_download_cubit.dart:61-69`). |
| Bug Density | 6 | Comment says cap 500, loop evicts above 250 (`ytm_download_cubit.dart:146-148`); swallowed duration backfill (`:199`). |
| State Management | 7 | `YtmSearchState` freezed with derived `phase`; `YtmDownloadState` hand-rolled. |
| Error Handling | 6 | `YtmErrorClassifier` consistent, but no `AppError`; `catch (_) {}` on download completion (`:199`). |
| Performance | 8 | 300 ms debounce, generation guard, capped speculative warm, throttled emits. |
| Memory Safety | 7 | Timers/notifier disposed; generation bumped on close. |
| Concurrency | 7 | `_botRetryInFlight` latch + generation guards. |
| Code Hygiene | 6 | Hardcoded English status strings (`ytm_search_cubit.dart:126,134`; `ytm_download_cubit.dart:216`). |
| Security | 7 | No credential handling; plaintext search history (low sensitivity). |
| Accessibility | 5 | Progress ring has no semantics (`ytm_download_button.dart:73-89`). |
| CI / DX / ADR | 7 | Cubit tests exist; no screen widget test. |

**Top gaps:** (1) cap comment/code mismatch; (2) swallowed backfill error; (3) hardcoded English; (4) progress-ring semantics; (5) speculative warm lacks true cancellation; (6) no screen widget test.

---

### lib/features/ytm_browse — **4.0 / 10**

| Dimension | Score | Key gap (evidence) |
|---|:---:|---|
| Architecture | 3 | No cubit/state; screen calls `getIt<YtmBrowseService>()` and holds all state (`ytm_browse_screen.dart:27-70`). |
| Bug Density | 4 | `clearCache()` nulls `_pendingFeed` without completing it → in-flight awaiter hangs (`ytm_browse_service.dart:60-64`). |
| State Management | 3 | Raw `setState`; no immutable state; no testable seam. |
| Error Handling | 3 | `catch (e)` discards the error and logs nothing (`ytm_browse_screen.dart:61-69`). |
| Performance | 4 | 3 network fetches run sequentially (`ytm_browse_service.dart:77-79`); empty feeds never cached; `queueSongs` rebuilt per card in `itemBuilder` → O(n²) (`:194-197`). |
| Memory Safety | 6 | No timers/controllers; `Image.network` without explicit cache manager. |
| Concurrency | 4 | No generation guard; overlapping load + refresh = last-writer-wins (`:41-70`). |
| Code Hygiene | 5 | No logging, no cubit. |
| Security | 7 | No credentials; remote image URLs. |
| Accessibility | 4 | Cards are bare `InkWell` with no semantics (`:227`). |
| CI / DX / ADR | 2 | **Zero tests** reference `YtmBrowseScreen`/`YtmBrowseService`. |

**Top gaps:** (1) `clearCache` hangs in-flight awaiters; (2) swallowed exceptions; (3) O(n²) card rebuild; (4) sequential fetches; (5) no card semantics; (6) no tests.

---

### lib/features/radio — **5.0 / 10**

| Dimension | Score | Key gap (evidence) |
|---|:---:|---|
| Architecture | 4 | Single 893-line screen; `RadioStationStore` constructed directly with a process-static backing list (`radio_station.dart:22`). |
| Bug Density | 5 | Static mutable store + unserialized writes; `ready.then` can overwrite a list already mutated (`radio_screen.dart:44-46`). |
| State Management | 4 | `setState` + manual `_refresh`; no cubit/notifier. |
| Error Handling | 5 | Store logs failures; screen add/import paths don't guard store throws. |
| Performance | 6 | Filter cache good; `_availableGenres` recomputed per build (`:59-69`); import persists per URL (`:163-165`). |
| Memory Safety | 6 | Controller disposed; static list lives for process lifetime. |
| Concurrency | 4 | No mutex around static `_stations` → interleaved writes (`radio_station.dart:37-45,88-99`). |
| Code Hygiene | 6 | Dialogs co-located; no l10n gaps noted. |
| Security | 5 | `isHttpUrl` accepts any host incl. `localhost`/private/metadata (`radio_station.dart:103-108`, `radio_screen.dart:644-654`) → SSRF. |
| Accessibility | 7 | Tooltips + semantic `ListTile`s. |
| CI / DX / ADR | 6 | Model/store + 4 screen tests; no concurrency/persistence-race test. |

**Top gaps:** (1) mutable static store without synchronization; (2) SSRF-permitting URL validation; (3) per-URL persistence on import; (4) `ready.then` overwrite race; (5) per-build genre recompute; (6) no concurrency test.

### lib/features/playlists — **6.0 / 10**

| Dimension | Score | Key gap (evidence) |
|---|:---:|---|
| Architecture | 5.5 | 2211-line screen mixes local/online/suggestions/import/export/share + 6 card widgets. |
| Bug Density | 5.5 | Undo after delete loses all songs for non-smart playlists (`playlists_screen.dart:333-345`); long-press silently deletes an online playlist (`:1746`). |
| State Management | 7 | Dual source of truth: freezed state + separate `ValueNotifier<YtmOnlineState>` (`playlist_cubit.dart:61-147`). |
| Error Handling | 6 | `_setOnlineState`/`_setOnlineStateDirect` swallow everything (`:150-162`); suggestions failure swallowed (`playlists_screen.dart:81-83`). |
| Performance | 5.5 | Nested `shrinkWrap` grids in a `ListView` (`:694-754,844-902,1249-1361`); suggestions call `getAllSongs()` (`:75`). |
| Memory Safety | 8 | Cache caps + bounded save queue (`cubit:258-280,327-357`); `close()` disposes all. |
| Concurrency | 6.5 | Serialized cache writes good; `fetchLikedSongsPlaylist`/`fetchAccountPlaylists` have no in-flight dedupe (`:625-722`). |
| Code Hygiene | 6 | 2211-line file; many `catch (_) {}`. |
| Security | 8.5 | `SafeFilePath.validate` on import; temp filename sanitized; share JSON depth ≤5. |
| Accessibility | 4.5 | Hero/liked cards lack semantics; download/remove `GestureDetector`s ~28 px unlabeled (`:1501-1517,1776-1808`). |
| CI / DX / ADR | 4 | 5 cubit tests; no screen/golden tests; 2.2k-line file unratcheted; no ADR. |

**Top gaps:** (1) undo delete loses contents (`:333-345`); (2) silent online-playlist delete on long-press (`:1746`); (3) overlapping YTM fetches (`cubit:625-722`); (4) swallowed notifier writes (`:150-162`); (5) sub-48 dp unlabeled targets; (6) nested shrink-wrapped grids.

---

### lib/features/playlist_detail — **6.0 / 10**

| Dimension | Score | Key gap (evidence) |
|---|:---:|---|
| Architecture | 6 | Three `StatefulWidget`s call `getIt` directly (`manage_playlist_screen.dart:50-52`, `online_playlist_detail_screen.dart:108-134`). |
| Bug Density | 5.5 | Manage apply is non-transactional; partial remove failure leaves half-edited playlist (`manage_playlist_screen.dart:548-595`); silent no-op when `createdId == null` (`online:254-268`). |
| State Management | 6.5 | Detail screen memoizes its stream (`:64-100`); online/manage use raw `setState`. |
| Error Handling | 7 | Load/apply errors surfaced with retry; online maps timeouts; several `catch (_)`. |
| Performance | 5.5 | Manage loads the whole library and filters in memory (`manage:52-55,105-124`); online recomputes duration each build. |
| Memory Safety | 8 | `_disposed` flags + dispose + stream memoization + temp cleanup. |
| Concurrency | 6.5 | No cancellation for `_applyChanges`; background refresh vs pull-to-refresh can interleave. |
| Code Hygiene | 6.5 | 537–741-line files; no TODOs. |
| Security | 8 | Temp names sanitized; user URL only fetched via `YtmService`. |
| Accessibility | 6 | Manage checkboxes accessible; some online `GestureDetector`s lack labels. |
| CI / DX / ADR | 4 | **Zero tests** for all three screens; no ADR. |

**Top gaps:** (1) non-atomic manage apply (`manage:548-595`); (2) silent no-op on save-to-local (`online:254-268`); (3) invalid smart criteria renders empty with no error (`playlist_detail_screen.dart:71-86`); (4) whole-library load in memory; (5) `Navigator.pop` before toast (`:588-594`); (6) no tests.

---

### lib/features/tag_editor — **5.5 / 10**

| Dimension | Score | Key gap (evidence) |
|---|:---:|---|
| Architecture | 6 | Screen well-factored; cubit holds native-channel IO/metadata/save/history with no tag-write abstraction (`tag_editor_cubit.dart:15-20,457-735`). |
| Bug Density | 4.5 | **Text fields never update on state change** — `initialValue` + `didUpdateWidget` does not sync it (`tag_field_widget.dart:46-47`), breaking undo and auto-fetch. |
| State Management | 6 | Hand-rolled `copyWith`; `_batchArtistEdited…` flags live outside state (`cubit:24-30`). |
| Error Handling | 8.5 | Distinct native outcomes + validation + per-file batch failure capture + scoped-storage hint. |
| Performance | 6.5 | 100 ms flush + `rescanSingleFile` per file (`:559-562,679-682`); 300 ms inter-request delay. |
| Memory Safety | 7.5 | 15-entry diff cap; 15 MB artwork guard; caches cleared on success. |
| Concurrency | 6.5 | `isClosed` guards; batch sequential; `autoFetchOnlineTags` not self-guarded (`screen:389`). |
| Code Hygiene | 6 | 838-line cubit; hardcoded English error strings (`cubit:258,663,716,725`). |
| Security | 7.5 | No path sanitization on `newArtworkPath` passed to native (`cubit:647`); size-capped. |
| Accessibility | 5 | Fields show a `Text` label but no `Semantics` (`tag_field_widget.dart:37-47`); `_SavingOverlay` has no semantics. |
| CI / DX / ADR | 3.5 | A single incidental test (`test/perf/rebuild_audit_test.dart:103`); no tag-write/undo/batch tests; no ADR. |

**Top gaps:** (1) `initialValue` bug breaks undo + auto-fill; (2) undo per-keystroke capped at 15; (3) batch checkpoint never resumes (`screen:59-81`); (4) batch flags not reset on partial failure (`cubit:597-625`); (5) no `TagWriter` abstraction; (6) inaccessible saving overlay.

---

### lib/features/album_detail — **6.0 / 10**

| Dimension | Score | Key gap (evidence) |
|---|:---:|---|
| Architecture | 5 | One 541-line file: presentation + stream access + sort persistence + multi-select + queue ops; no cubit. |
| Bug Density | 6.5 | Sort cache correctly hashes fields; `playNext` loop reversal suspicious (`:349-351`). |
| State Management | 6 | Local `_sort`/`_selectedIds` + `StreamBuilder`; prefs writes inside the widget. |
| Error Handling | 7.5 | Failure → `_AlbumErrorView` with retry; prefs errors logged. |
| Performance | 5 | Stream created inline in `build` (`:139-140`) → DB re-query per selection/sort; eager split-pane list (`:478-491`). |
| Memory Safety | 8 | No controllers; memoized sort cache. |
| Concurrency | 7.5 | Local selection; fire-and-forget prefs write. |
| Code Hygiene | 6.5 | 541 lines; private widgets. |
| Security | 9 | No sensitive operations. |
| Accessibility | 6.5 | `SongTile` semantics inherited; hero artwork unlabeled (`:199-208`). |
| CI / DX / ADR | 3.5 | Zero tests; not ratcheted. |

**Top gaps:** (1) inline `watchAlbumSongs` in build (`:139-140`); (2) eager non-virtualized list (`:478-491`); (3) prefs/sort/session logic in widget; (4) no hero semantics; (5) no tests.

---

### lib/features/artist_detail — **5.8 / 10**

| Dimension | Score | Key gap (evidence) |
|---|:---:|---|
| Architecture | 5.5 | 410-line file with two inline streams + bio future + error widgets; no cubit. |
| Bug Density | 6 | Refresh does not refetch bio (`:74-76`); hardcoded `'Bio unavailable'` (`:38,162`). |
| State Management | 6.5 | `_bioFuture` memoized once per artist (`:41-53`). |
| Error Handling | 7.5 | Independent error sections with retry. |
| Performance | 5 | Two streams recreated every build (`:227,311`); eager top-tracks list (`:339-349`). |
| Memory Safety | 8 | Future/list enabled. |
| Concurrency | 7.5 | No significant races. |
| Code Hygiene | 6 | Hardcoded English; 410 lines. |
| Security | 9 | No sensitive operations. |
| Accessibility | 6 | Album tiles are `InkWell` without explicit label (`:270-298`). |
| CI / DX / ADR | 3.5 | Zero tests; not ratcheted. |

**Top gaps:** (1) two inline streams per build; (2) refresh doesn't refresh bio; (3) eager top-tracks; (4) hardcoded string; (5) no tests.

---

### lib/features/folder_detail — **6.0 / 10**

| Dimension | Score | Key gap (evidence) |
|---|:---:|---|
| Architecture | 5.5 | 377-line file bundling breadcrumbs, exclusion toggle, songs, error view. |
| Bug Density | 6 | Breadcrumb `subPath` rebuilt as `'/'+parts`, dropping the original root/drive (`:356`). |
| State Management | 7 | Local `_isExcluded` syncs with `LibraryCubit`; clean. |
| Error Handling | 7.5 | Failure snackbar + rollback + retry view. |
| Performance | 5 | Inline stream in build (`:142`); eager `for` list (`:301-312`). |
| Memory Safety | 8 | No controllers. |
| Concurrency | 7.5 | Await + rollback; guarded undo. |
| Code Hygiene | 6.5 | 377 lines; no TODOs. |
| Security | 9 | Paths displayed/exported only. |
| Accessibility | 6 | Tooltip on toggle; breadcrumb taps text-only. |
| CI / DX / ADR | 3.5 | Zero tests. |

**Top gaps:** (1) inline stream per build; (2) eager song list; (3) breadcrumb loses root (`:356`); (4) no tests.

---

### lib/features/genre_detail — **6.3 / 10**

| Dimension | Score | Key gap (evidence) |
|---|:---:|---|
| Architecture | 6 | 248-line single-purpose file. |
| Bug Density | 7 | No functional defect found. |
| State Management | 6.5 | Stateless beyond `_useCase`. |
| Error Handling | 7.5 | Dedicated loading/error views with retry. |
| Performance | 5 | Inline `watchGenreSongs` per build (`:51-52`); eager `for` list (`:230-241`). |
| Memory Safety | 8 | No resources held. |
| Concurrency | 7.5 | None. |
| Code Hygiene | 7 | 248 lines; consistent. |
| Security | 9 | None. |
| Accessibility | 6 | `SongTile` semantics; hero/unlabeled. |
| CI / DX / ADR | 3.5 | Zero tests. |

**Top gaps:** inline stream (`:51-52`); eager list; duplicated loading/error scaffold vs year/artist detail (DRY); no tests.

---

### lib/features/year_detail — **6.3 / 10**

| Dimension | Score | Key gap (evidence) |
|---|:---:|---|
| Architecture | 6 | 231-line file, near-duplicate of `genre_detail_screen.dart`. |
| Bug Density | 7 | No defect found. |
| State Management | 6.5 | Read-only. |
| Error Handling | 7.5 | Retry present. |
| Performance | 5 | Inline stream (`:51-52`); eager list (`:213-224`). |
| Memory Safety | 8 | None held. |
| Concurrency | 7.5 | None. |
| Code Hygiene | 7 | 231 lines. |
| Security | 9 | None. |
| Accessibility | 6 | Same as genre. |
| CI / DX / ADR | 3.5 | Zero tests. |

**Top gaps:** inline stream; eager list; copy-paste of genre screen (extract shared `DetailTracksScreen`); no tests.

---

### lib/features/onboarding — **5.5 / 10**

| Dimension | Score | Key gap (evidence) |
|---|:---:|---|
| Architecture | 4 | 1021-line file with 5 page-builder methods; no page widgets extracted; not ratcheted. |
| Bug Density | 5.5 | Grant flow has no `catch` (`:48-68`); `SharedPreferences` awaited unguarded inside the notification catch (`:114-118`); hardcoded English snackbar (`:104`). |
| State Management | 6.5 | Local `_currentPage`/`_isLoading`; reads `SettingsCubit` for accent. |
| Error Handling | 5.5 | Scan errors handled; permission/complete path unguarded; unlogged `catch (_)`. |
| Performance | 7.5 | `PageView` lazy; reduce-motion honored. |
| Memory Safety | 8.5 | `PageController` disposed. |
| Concurrency | 7 | `_isLoading` gates the button; no re-entrancy guard inside the method. |
| Code Hygiene | 4.5 | 1021 lines + hardcoded `'PULSR'`/notification/`'OK'` (`:104,106,228`). |
| Security | 8 | Scoped permission; no exfiltration. |
| Accessibility | 4 | Accent swatches are unlabeled `GestureDetector`s (`:856-887`); page dots have no progress semantics (`:287-302`); logo unlabeled. |
| CI / DX / ADR | 3.5 | No onboarding test; no ADR. |

**Top gaps:** (1) unhandled grant-flow exceptions (`:48-68`); (2) unguarded prefs await inside catch (`:114-118`); (3) inaccessible swatches; (4) no page-progress semantics; (5) 1021-line monolith; (6) hardcoded strings.

---

### lib/features/splash — **7.5 / 10**

| Dimension | Score | Key gap (evidence) |
|---|:---:|---|
| Architecture | 8.5 | Single-purpose 147-line gate. |
| Bug Density | 7.5 | Retry can start a second `_checkNextScreen` while one is in flight (`:134-136`). |
| State Management | 8 | Minimal `_timedOut`. |
| Error Handling | 7 | Timeout + DI-ready gate + retry; `SharedPreferences.getInstance()` unguarded (`:52`). |
| Performance | 9 | 800 ms hold + 8 s safety net. |
| Memory Safety | 9 | No controllers/subscriptions. |
| Concurrency | 7 | No re-entrancy guard on retry → duplicate `context.go`. |
| Code Hygiene | 8 | Short, clean, uses l10n. |
| Security | 9 | None. |
| Accessibility | 6.5 | Logo `Image.asset` lacks `semanticLabel` (`:88-93`). |
| CI / DX / ADR | 6.5 | Indirect smoke coverage. |

**Top gaps:** (1) unguarded `SharedPreferences` (`:52`); (2) retry re-entrancy (`:134-136`); (3) logo has no semantic label.

---

## Core

### lib/core/bloc — **9.0 / 10**

| Dimension | Score | Key gap (evidence) |
|---|:---:|---|
| Architecture | 9 | Strong base cubit (`base_cubit.dart:17-63`); no ADR for the cubit contract. |
| Bug Density | 9 | `safeEmit`/close guards well tested. |
| State Management | 9 | Effects separated from state. |
| Error Handling | 8 | Close failures routed to `addError` after `_closed` (`:189-207`). |
| Performance | 9 | Minimal allocation; `autoTimer` prunes (`:159-163`). |
| Memory Safety | 9 | LeakDetector + composite disposal (`:166-209`). |
| Concurrency | 8.5 | Double-guarded `isClosed`; close futures intentionally unawaited. |
| Code Hygiene | 9 | Clear docs; documented `_NoopSubscription`. |
| Security | N/A | No sensitive data. |
| Accessibility | N/A | No UI. |
| CI / DX / ADR | 8 | Covered indirectly; no dedicated base-cubit suite. |

**Top gaps:** (1) `close()` never awaits effect-controller/sub disposal (`:189-208`); (2) no direct `base_cubit_test.dart`; (3) `_NoopSubscription.asFuture()` throws when no value (`:237-244`).

---

### lib/core/config — **8.0 / 10**

| Dimension | Score | Key gap (evidence) |
|---|:---:|---|
| Architecture | 8 | Static const config; not injectable/overridable in tests. |
| Bug Density | 9 | `app_config_test.dart` covers gating. |
| Error Handling | 8 | `validateConfiguration` throws + logs (`:98-115`). |
| Performance | 9 | `const` enables tree-shaking. |
| Memory/Concurrency | N/A | Immutable. |
| Code Hygiene | 9 | Well-commented. |
| Security | 9 | Flavor isolation + runtime purity probe (`:54-76`). |
| Accessibility | N/A | No UI. |
| CI / DX / ADR | 9 | `check_prod_flavor.py` + manifest guard in CI. |

**Top gaps:** (1) `environment` blends `flavor`/`envName` heuristics → missing flag silently defaults dev (`:35-49`); (2) tree-shaking not guaranteed because DI imports all services (`:21-24`); (3) no ADR for the flavor gate.

---

### lib/core/constants — **7.5 / 10**

| Dimension | Score | Key gap (evidence) |
|---|:---:|---|
| Architecture | 8 | Token files split by concern; two 600+-line data blobs (`audio_feature_info.dart` 669, `embedded_browser_ua.dart` 610). |
| Bug Density | 8 | Dead keys removed with notes (`prefs_keys.dart:26-48`). |
| Error/State/Mem/Conc | N/A | Constants only. |
| Performance | 9 | Const. |
| Code Hygiene | 7 | Raw pref strings duplicated in `scrobbler_service.dart:116-126` instead of `PrefsKeys`. |
| Security | 8 | No secrets. |
| Accessibility | 8 | `minTouchTarget ≥48`, ordered type scale (`tokens_lock_test.dart:65-115`). |
| CI / DX / ADR | 9 | `tokens_lock_test` in CI. |

**Top gaps:** (1) `PrefsKeys` not the single source of truth (raw literals in scrobbler); (2) two 600+-line pure-data files inflate the module.

---

### lib/core/di — **7.0 / 10**

| Dimension | Score | Key gap (evidence) |
|---|:---:|---|
| Architecture | 8 | GetIt + injectable modules + dispose hooks; service locator leaks into business code (`ytm_account_service.dart:525,837`, `app_router.dart:334`). |
| Bug Density | 7 | Runtime graph only validated by asserts. |
| Error Handling | 6 | Five silent `catch (_) {}` in bootstrap (`injection.dart:38,49,54,65,68`). |
| Performance | 8 | Pre-warm + timeouts. |
| Memory Safety | 8 | Clients/cubits disposed. |
| Concurrency | 8 | `_initializationReady` Completer gates splash. |
| Code Hygiene | 7.5 | Generated config 368 lines; global mutable `getIt`. |
| Security | 8 | Secure-storage options. |
| CI / DX / ADR | 8 | Generated-graph text guard only. |

**Top gaps:** (1) `validateDependencies` assert-only → stripped in release (`:75-86`); (2) silent audio-handler warm-up catch (`:38`); (3) service-locator leakage; (4) no runtime resolution test; (5) no ADR.

---

### lib/core/errors — **7.5 / 10**

| Dimension | Score | Key gap (evidence) |
|---|:---:|---|
| Architecture | 7 | Sealed `AppError` (ADR-002) but parallel `AppFailure` + two `Result` types (`failures.dart:4`, `utils/result.dart:10`). |
| Bug Density | 8 | Taxonomy tests pass. |
| Error Handling | 8 | Typed classification + resolver. |
| Performance/Mem/Conc | N/A | Pure. |
| Code Hygiene | 7 | Resolver matched by English literal prefixes (`error_message_resolver.dart:54-199`). |
| Security | 8 | Bot/auth classification; redaction in utils. |
| CI / DX / ADR | 8 | ADR-002 + taxonomy test. |

**Top gaps:** (1) two unrelated `Result` types collide; (2) `resolveAppError` misses typed `TimeoutException`, `FormatException`, Drift/SQLite, TLS → all generic (`:104-182`); (3) UI coupled to exact English strings (`error_message_resolver.dart:15-49`).

---

### lib/core/motion — **9.0 / 10**

| Dimension | Score | Key gap (evidence) |
|---|:---:|---|
| Architecture | 9 | Reduce-motion-aware tokens + context extension. |
| Bug Density | 9 | `reduce_motion_test` verifies collapse. |
| Error/State/Mem/Conc | N/A | Pure. |
| Performance | 9 | Zero-cost. |
| Code Hygiene | 8.5 | Two overlapping duration systems (`motion_durations.dart:21-37` vs `pulsr_motion.dart:25-38`). |
| Security | N/A | — |
| Accessibility | 9 | Honors `disableAnimations`/`accessibleNavigation`. |
| CI / DX / ADR | 8 | Tested; no ADR. |

**Top gaps:** (1) duplicate duration systems; (2) router bypasses tokens with hard-coded 320/280/240 ms (`app_router.dart:67,135,472`); (3) `PulsrMotion.scale(factor: 0.0)` defaults to full collapse (`:75-77`).

---

### lib/core/network — **7.0 / 10**

| Dimension | Score | Key gap (evidence) |
|---|:---:|---|
| Architecture | 8 | Value-object `ProxyConfig`; global override singleton. |
| Bug Density | 8 | Robust IPv6/bracket proxy parser. |
| State Management | 7 | Global mutable `_config` (`app_http_overrides.dart:14`). |
| Error Handling | 6 | Fail-open `catch (_) return true` (`connectivity_guard.dart:21-23`); empty catches. |
| Performance | 8 | Timeouts/keep-alive/drain. |
| Memory Safety | 8 | Test client force-closed. |
| Concurrency | 8 | Debounced path-change. |
| Code Hygiene | 8 | Clear SOCKS-limitation comments. |
| Security | 7.5 | Proxy host logged (`:23-26`); SOCKS silent DIRECT fallback. |
| CI / DX / ADR | 8 | `proxy_config_test`, security tests. |

**Top gaps:** (1) `hasConnection()` returns `true` on any exception (`connectivity_guard.dart:21-23`); (2) proxy host:port logged; (3) SOCKS silently returns `DIRECT` while UI may claim proxy active (`proxy_config.dart:89-92`).

---

### lib/core/performance — **7.0 / 10**

| Dimension | Score | Key gap (evidence) |
|---|:---:|---|
| Architecture | 7 | Static global `ValueNotifier`, not injected (`gpu_budget.dart:8`). |
| Bug Density | 9 | 17 lines. |
| State Management | 7 | Global mutable singleton. |
| Error/Conc/Mem | 8-9 | Single notifier; single-isolate write. |
| Performance | 8 | Central flag is right. |
| Code Hygiene | 8 | Clear docs. |
| CI / DX / ADR | 6 | No dedicated test; no ADR. |

**Top gaps:** (1) no test asserts `GpuBudget.isEnabled` actually downgrades expensive passes; (2) static singleton not injectable.

---

### lib/core/responsive — **8.0 / 10**

| Dimension | Score | Key gap (evidence) |
|---|:---:|---|
| Architecture | 8.5 | Breakpoints, viewport tokens, delegate, metrics, hinged two-pane. |
| Bug Density | 8 | Device-matrix + breakpoint tests. |
| Error Handling | 9 | Zero catches; safe defaults. |
| Performance | 9 | `InheritedWidget` O(1). |
| Memory Safety | 9 | Stateless. |
| Code Hygiene | 6 | `contentMaxWidth` defined three times with different numbers (`pulsr_responsive_tokens.dart:120-128`, `pulsr_layout_metrics.dart:26-32`, `layout_delegate.dart:134-146`). |
| Security | N/A | — |
| Accessibility | 8 | `textScaler` carried; field height clamps scale. |
| CI / DX / ADR | 7 | 8 responsive tests; none for delegate mode matrix; no ADR. |

**Top gaps:** (1) three `contentMaxWidth` sources → width discontinuities; (2) duplicated device classification; (3) `isShortHeight` threshold collides with delegate rule.

---

### lib/core/router — **7.0 / 10**

| Dimension | Score | Key gap (evidence) |
|---|:---:|---|
| Architecture | 7 | One 731-line function; `state.extra is Map` duck-typing (`:199-208`); service-locator fallback (`:334`). |
| Bug Density | 8 | Orphan/dead-push guards tested. |
| Error Handling | 8 | `errorBuilder` + not-found screens. |
| Performance | 8 | Per-route transitions; no lazy page caching. |
| Memory/Conc | N/A | Stateless. |
| Code Hygiene | 6 | Hardcoded durations bypass motion tokens; scattered deep-link parsing. |
| Security | 8 | YTM/cloud routes hard-gated. |
| Accessibility | 8 | Transitions honor `motionEnabled`. |
| CI / DX / ADR | 7 | Text-scan guard; **0 test files import `core/router`**; no ADR. |

**Top gaps:** (1) no behavioral deep-link/redirect/error tests; (2) `getIt<IMusicRepository>()` routing fallback untestable; (3) untyped `extra` payloads.

---

### lib/core/services — **6.5 / 10**

| Dimension | Score | Key gap (evidence) |
|---|:---:|---|
| Architecture | 6 | God files: `ytm_account_service.dart` 3384, `yt_download_service.dart` 1879, `ytm_service.dart` 1735 — all excluded from the fat-file ratchet. |
| Bug Density | 7 | 61 test files reference services, but `auth_service`, `ytm_oauth_service`, `earbud_optimization_service`, `quran_mode_service`, `waveform_service`, `ytm_browse_service` are untested. |
| State Management | 7 | Mixed `ValueNotifier` + cubits. |
| Error Handling | 6 | **30 empty catch blocks**; e.g. `ytm_url_cache` restore. |
| Performance | 8 | Isolates, LRU, parallelism, circuit breaker. |
| Memory Safety | 7 | `YtmService.dispose()` doesn't cancel `_botCooldownTimer`/dispose notifier (`ytm_service.dart:327-335`); `_downloadedFilePaths` never pruned (`yt_download_service.dart:93`). |
| Concurrency | 8 | Hand-rolled `AsyncMutex` despite the `mutex` package; generation tokens; dedup. |
| Code Hygiene | 5 | 30 empty catches; oversized files. |
| Security | 8 | Cookies in Keystore/Keychain, WebView sandbox, OAuth device flow, PII redaction. |
| CI / DX / ADR | 8 | Security/audio/cache suites in CI. |

**Top gaps:** (1) `YtmService.dispose()` leaks timer/notifier (`:327-335`); (2) 30 empty catches; (3) 3384-line God object; (4) hand-rolled `AsyncMutex` vs declared `mutex` package; (5) zero direct tests for OAuth/auth services.

---

### lib/core/telemetry — **7.5 / 10**

| Dimension | Score | Key gap (evidence) |
|---|:---:|---|
| Architecture | 8 | Injectable `Clock`; tracker + session log. |
| Bug Density | 8 | Latency regression gate tests. |
| State Management | 8 | Broadcast reports, capped history. |
| Error Handling | 7 | 3 empty catches; nested fallback. |
| Performance | 7 | Every report does both `debugPrint` and `ErrorLogger.log` (`playback_latency_tracker.dart:390-410`). |
| Memory Safety | 8 | History capped 100; controller closed. |
| Concurrency | 8 | `_active` supersede handling. |
| Code Hygiene | 7.5 | `_enableDebugPrint=true` on prod path (`:118-119`). |
| Security | 7.5 | Emits `videoId` to Sentry (`:166,350-359`). |
| CI / DX / ADR | 8 | Regression-gate test. |

**Top gaps:** (1) double emission (print + log) on the playback path; (2) `videoId` leaves the device; (3) `AudioSessionLog` retention/pruning undocumented.

---

### lib/core/theme — **8.5 / 10**

| Dimension | Score | Key gap (evidence) |
|---|:---:|---|
| Architecture | 9 | `ThemeExtension` palette, presets, dynamic cubit. |
| Bug Density | 8 | Design-token + widget tests. |
| State Management | 9 | Monotonic TTL + single-slot queue (`dynamic_theme_cubit.dart:141-173`). |
| Error Handling | 8 | Palette fallback chain preserved. |
| Performance | 8 | Debounce 500 ms, timeout, 128 px decode. |
| Memory Safety | 9 | Palette LRU capped 50. |
| Concurrency | 9 | Token invalidation + pending-extraction guard. |
| Code Hygiene | 8.5 | Clear. |
| Security | N/A | — |
| Accessibility | 8 | High-contrast theme + `onAccent` guarantee; contrast test covers only 3 pairs (`accessibility_compliance_test.dart:66-87`). |
| CI / DX / ADR | 8 | Token tests in CI. |

**Top gaps:** (1) contrast test validates only 3 color pairs (secondary/tertiary + light theme untested); (2) static `Stopwatch` weakens test isolation (`:61`); (3) no ADR.

---

### lib/core/utils — **7.0 / 10**

| Dimension | Score | Key gap (evidence) |
|---|:---:|---|
| Architecture | 6 | Two `Result` types; **duplicate `PulsrToast`** (`utils/pulsr_toast.dart:9` vs `widgets/pulsr_toast.dart:39`). |
| Bug Density | 8 | Parsers fuzzed. |
| Error Handling | 7 | `RetryUtil` solid; **10 empty catches**. |
| Performance | 8 | Token-bucket limiter, parsers. |
| Memory Safety | 8 | `LeakDetector`; bounded cache manager. |
| Concurrency | 8 | `AsyncMutex`, `AsyncGuard`, in-flight dedup. |
| Code Hygiene | 6 | Name collisions (`PulsrToast`, `Result`); `AsyncMutex` supersedes `mutex`. |
| Security | 8 | `InputSanitizer`, `SafeFilePath`, PII redaction. |
| Accessibility | 7 | `l10n_extensions` only. |
| CI / DX / ADR | 8 | Fuzz + security tests. |

**Top gaps:** (1) two `PulsrToast` classes with unrelated APIs; (2) `Result` type collision; (3) 10 empty catches.

---

### lib/core/widgets — **7.0 / 10**

| Dimension | Score | Key gap (evidence) |
|---|:---:|---|
| Architecture | 6 | Duplicate `PulsrToast`; large files (toast 562, dismissible 546). |
| Bug Density | 7 | Golden + safety suites; `gesture_hint_overlay`, `pulsr_adaptive_sheet`, `pulsr_logo`, `pulsr_modal_tracker`, `shimmer_skeleton` untested. |
| State Management | 8 | Controllers disposed. |
| Error Handling | 7 | `PulsrErrorBoundary` present; **10 empty catches**. |
| Performance | 8 | Weak-ref artwork cache, RepaintBoundary, shimmer. |
| Memory Safety | 7 | `_weakLargeCache` keys never pruned when target GC'd (`cached_artwork.dart:25,46-55`). |
| Concurrency | 7 | Singleton caches; no explicit sync. |
| Code Hygiene | 6 | Duplicate `PulsrToast`; deprecated aliases still shipped. |
| Security | N/A | — |
| Accessibility | 7 | Only 13 of 37 widgets reference semantics; a11y suite covers 4 widgets. |
| CI / DX / ADR | 8 | Golden + RTL + a11y suites in CI. |

**Top gaps:** (1) `_weakLargeCache` accumulates dead `WeakReference` entries (`cached_artwork.dart:25,46-55,102-108`); (2) thin a11y coverage; (3) duplicate `PulsrToast`; (4) `PulsrErrorBoundary` only catches synchronous build errors (`:107-115`).

---

## Data

### lib/data/audio — **6.0 / 10**

| Dimension | Score | Key gap (evidence) |
|---|:---:|---|
| Architecture | 7 | Handler split into 7 `part` mixins + collaborators, but core files remain god-objects: `audio_handler.dart` 2773/90 methods, `equalizer_manager.dart` 2556, `audio_effects_channel.dart` 2140, `audio_handler_queue_engine.dart` 1862. |
| Bug Density | 6 | Unclamped range `sublist` (`dsd_decoder_helper.dart:108`, `mqa_decoder_helper.dart:240`); `onTrackCompleted(Object trackId)` ignores its argument (`audio_memory_manager.dart:193-195`); `PreconnectedSocketPool.preconnect` opens no socket (`stream_pre_resolver.dart:20-26`). |
| State Management | 6 | `PlaybackQueueStateMachine.songs` returns the internal mutable list (`playback_queue_state_machine.dart:42`); dozens of mutable fields mutated from async callbacks. |
| Error Handling | 5 | **155 empty `catch {}`**; MQA throws raw `UnsupportedError` while DSD throws a typed exception (`mqa_decoder_helper.dart:150` vs `dsd_decoder_helper.dart:176`). |
| Performance | 5 | Whole 10k queue materialized to MediaItems/AudioSources on every mutation (`audio_handler_queue_engine.dart:1002-1004,1140`); unbounded bulk-enqueue resolves (`stream_pre_resolver.dart:142-159`). |
| Memory Safety | 5 | 300 MB in-memory DSD decode with boxed `List<int>` then copy (`dsd_decoder_helper.dart:180,323-349`); unbounded static `_headerTrimCache` (`gapless_trim_handler.dart:46`); process-wide static preload budget (`audio_memory_manager.dart:23`). |
| Concurrency | 7 | Good primitives (`AsyncLock`, `Mutex`, monotonic generations); weakness: `releaseInactive` outside the claim mutex (`triple_buffer_pipeline.dart:82-86`), wall-clock underrun (`adaptive_buffer_engine.dart:209`), 100+ unawaited calls. |
| Code Hygiene | 5 | 155 empty catches; 133 `dynamic`; `// ignore_for_file: unused_field` on the main handler; 8 ignore directives. |
| Security | 7 | Cookie leak to CDN fixed and tested (`ytm_resolving_source.dart:490-510`); DSD/MQA read `song.path` with no containment check. |
| Accessibility | N/A | Headless DSP/playback engine. |
| CI / DX / ADR | 9 | ADR-003 + DSP/Bluetooth suites in CI. |

**Top gaps:** (1) 10k-queue full rebuild per mutation (`audio_handler_queue_engine.dart:999-1140`); (2) unclamped `sublist` on range requests; (3) 300 MB in-memory DSD decode; (4) 155 empty catches; (5) static mutable audio state; (6) unbounded `_headerTrimCache`; (7) MQA raw-throw + no signature gating; (8) `PreconnectedSocketPool` is a no-op.

**Test coverage:** 239 tests/30 files, strong on pure logic. Missing: real handler concurrency races (`concurrency_hardening_test` only tests the generic `Mutex`), 10k-queue perf, DSD range bounds, `GaplessTrimHandler` cache growth, `AudioEffectsChannel.dispose`.

---

### lib/data/db — **7.0 / 10**

| Dimension | Score | Key gap (evidence) |
|---|:---:|---|
| Architecture | 7 | Clean table defs + health checker; denormalized `songCount`/`albumCount` maintained by hand-rolled SQL that can drift (`music_repository.dart:1680-1686,1937-1948`). |
| Bug Density | 6 | `_createV11Constraints` failure sets `ftsRebuildFailed = true` even though it is not FTS (`app_database.dart:268`). |
| State Management | 5 | Four process-static mutable FTS-repair fields shared across all instances (`app_database.dart:30-41`). |
| Error Handling | 7 | Repair retries with backoff + bounded attempts; some empty rollback catches (`:267`). |
| Performance | 8 | Extensive indexes incl. `lower(path)`/NOCASE + FTS5 external content. |
| Memory Safety | 8 | Bounded by SQLite. |
| Concurrency | 7 | `_ftsRepairInProgress` Completer gate; WAL + SAVEPOINT; static attempt counters not per-connection. |
| Code Hygiene | 7 | Well-commented; heavy raw-SQL migrations + static globals. |
| Security | 5 | **DB is unencrypted** (no SQLCipher/`PRAGMA key`); paths + history plaintext. |
| Accessibility | N/A | — |
| CI / DX / ADR | 8 | Migration test + legacy fixture; no schema-policy ADR. |

**Top gaps:** (1) no encryption at rest (`app_database.dart:106`); (2) static repair state; (3) wrong failure flag on migration (`:268`); (4) denormalized counts drift; (5) migration rollback/repair untested; (6) `DatabaseHealthCheck` has zero tests.

---

### lib/data/lyrics — **8.0 / 10**

| Dimension | Score | Key gap (evidence) |
|---|:---:|---|
| Architecture | 8 | Single-responsibility 110-line store; hash+owner collision guard; legacy migration. |
| Bug Density | 8 | Owner marker prevents collisions; `owner == null` returns whatever sits at the hashed key (`:57-58`). |
| State Management | 8 | Stateless, prefs-backed. |
| Error Handling | 8 | Logs + defaults; one intentional empty catch (`:93`). |
| Performance | 7 | Re-reads prefs per call; index list rewritten every set. |
| Memory Safety | 9 | Hard 500-entry bound with eviction. |
| Concurrency | 6 | Index read-modify-write not atomic (`:83-92`) → dropped entries / orphaned values. |
| Code Hygiene | 8 | Small, documented, typed. |
| Security | 7 | Raw path stored as owner marker (PII in prefs). |
| Accessibility | N/A | — |
| CI / DX / ADR | 5 | Only `max_rate_remediation_test` references it; no dedicated test. |

**Top gaps:** (1) non-atomic index update; (2) owner-null fallback can return a foreign value; (3) no dedicated tests; (4) PII marker in prefs.

---

### lib/data/repositories — **5.0 / 10**

| Dimension | Score | Key gap (evidence) |
|---|:---:|---|
| Architecture | 5 | `music_repository.dart` is a 2508-line / 137-method god object. |
| Bug Density | 5 | `PrefsRepository._writeToDisk` silently drops any type other than the 5 supported (`prefs_repository.dart:108-120`); download persistence swallows all errors (`download_repository_impl.dart:680-686`). |
| State Management | 6 | Prefs caches every key + batches; download repo tracks task maps. |
| Error Handling | 6 | `Either`/`Result` used; 18 empty catches + silent drops. |
| Performance | 6 | FTS parameterized/indexed; `reconcileDownloadedSong` metadata fallback does unindexed `lower()` scans (`music_repository.dart:2004-2016`). |
| Memory Safety | 7 | Bounded task map; prefs cache can hold all keys. |
| Concurrency | 5 | `PrefsRepository.dispose()` fires `unawaited(flush())` (`:77-81`) → lost writes on shutdown; batched flush unguarded. |
| Code Hygiene | 5 | God file; dead duplicated `_likeEscape`; many `dynamic`. |
| Security | 4 | **`deleteSongs` calls `File(path).delete()` with no containment check** (`music_repository.dart:1951-1965`) → arbitrary file deletion; DB unencrypted. |
| Accessibility | N/A | — |
| CI / DX / ADR | 7 | Repository/smart-playlist tests (19+); no repository ADR. |

**Top gaps:** (1) **arbitrary file deletion** (`:1951-1965`); (2) `PrefsRepository` silently drops unsupported types; (3) `dispose()` fire-and-forget flush; (4) god object; (5) silent download persistence failures; (6) unindexed metadata fallback.

---

### lib/data/scanner — **6.0 / 10**

| Dimension | Score | Key gap (evidence) |
|---|:---:|---|
| Architecture | 7 | Focused service with isolate parsing, progress/error streams, clean DTOs. |
| Bug Density | 6 | Incremental scan keyed on store timestamps can miss edited files (`:321-327`); `markScanComplete()` overwrites `_lastScanAt` without epoch on some paths (`:335`). |
| State Management | 5 | Static mutable `_nomediaDirCache` (`:222`) + `_isEnrichingQuality` (`:89`); no reentrancy guard. |
| Error Handling | 7 | `ErrorLogger` + `ScanError` stream; two empty catches (`:264,363`). |
| Performance | 5 | `compute` copies the entire library as `List<Map<String,dynamic>>` across the isolate boundary (`:391-404`); N+1 `queryAudiosFrom` per genre (`:349-364`); sequential enrichment at 20 ms each (`:565-580`). |
| Memory Safety | 6 | Full raw map list + isolate copy; nomedia cache capped 2000. |
| Concurrency | 5 | `_isEnrichingQuality` check-and-set not atomic; no scan reentrancy lock; static cache shared. |
| Code Hygiene | 6 | 796 lines; `avoid_dynamic_calls` ignores; hand-rolled cache eviction. |
| Security | 7 | Paths normalized + `.nomedia`/exclusion filtered; read-only. |
| Accessibility | N/A | — |
| CI / DX / ADR | 5 | 2-test file (static predicates only); no dedicated CI job. |

**Top gaps:** (1) whole-library isolate copy (`:391-404`); (2) N+1 genre queries (`:349-364`); (3) sequential enrichment (`:562-588`); (4) non-atomic guards; (5) static nomedia cache not instance-scoped; (6) thin tests.

---

### lib/data/visualizer — **8.0 / 10**

| Dimension | Score | Key gap (evidence) |
|---|:---:|---|
| Architecture | 8 | Two tiny single-purpose stores. |
| Bug Density | 8 | Clean parse/save; `load` falls back to defaults. |
| State Management | 8 | Stateless, prefs-backed. |
| Error Handling | 7 | Import paths log; `save()` does not catch prefs failures (`milkdrop_preset_store.dart:29-33`, `visualizer_preset_store.dart:26-29`). |
| Performance | 9 | Trivial. |
| Memory Safety | 9 | Single string/JSON preset. |
| Concurrency | 8 | Standard prefs semantics. |
| Code Hygiene | 9 | Small, documented, typed. |
| Security | 7 | Extension allowlist + null-byte check, but `SafeFilePath` enforces no directory containment (`safe_file_path.dart:36-70`). |
| Accessibility | N/A | — |
| CI / DX / ADR | 4 | No test imports either store. |

**Top gaps:** (1) stores untested; (2) `save()` unguarded; (3) no path containment; (4) no size cap on imported preset text.

---

## Domain

### lib/domain/models — **6.0 / 10**

| Dimension | Score | Key gap (evidence) |
|---|:---:|---|
| Architecture | 5 | `audio_quality_info.dart:2-7` imports Flutter `material` + `data/db` + `data/audio`; `download_settings.dart:3,23-57` does prefs I/O in a model; `ytm_track.dart:2` depends on drift. |
| Bug Density | 5 | Partial equality (below); unsafe JSON casts throw. |
| State Management | N/A | `audio_quality_info.dart:22` exposes mutable static `dsdDopActive` global. |
| Error Handling | 5.5 | `fromJson`/`fromMap` throw raw `TypeError` on malformed input (`headphone_profile.dart:107-110`, `smart_playlist_criteria.dart:123,129`). |
| Performance | 7 | `audio_quality_info.dart:190-218` recompiles regexes per `fromSong`. |
| Memory Safety | 7.5 | Mostly immutable; some lists not `unmodifiable`. |
| Concurrency | 7 | Static `dsdDopActive` + prefs in `save()`. |
| Code Hygiene | 6 | Duplicate `encode`/`toJsonString` (`eq_preset.dart:174-175`); 420/606-line models. |
| Security | 7 | `smart_playlist_criteria.dart:144-149` logs the full raw JSON payload. |
| Accessibility | N/A | — |
| CI / DX / ADR | 6.5 | Model tests live largely outside `test/domain/models`; no purity ADR. |

**Top gaps:** (1) `AudioOutputInfo ==`/`hashCode` ignore ~12 fields → settings/device state won't rebuild (`audio_output_info.dart:374-397`); (2) `HeadphoneProfile ==` uses only `id` (`:275-283`); (3) `LyricsLine ==` ignores `words` (`lyrics_line.dart:76-92`); (4) `HeadphoneProfile.fromJson` throws despite "must not throw" comment (`:107-110`); (5) unchecked casts in criteria/download/dsp (`smart_playlist_criteria.dart:123,129`); (6) `dsp_debug_report.dart:128` discards parsed timestamp.

---

### lib/domain/services — **5.5 / 10**

| Dimension | Score | Key gap (evidence) |
|---|:---:|---|
| Architecture | 4.5 | Infrastructure in domain: `cast_service.dart:3-6`, `hires_audio_service.dart:4,10` (`permission_handler`), `usb_exclusive_service.dart:3`, `room_correction_service.dart:7-9`; 1-line `lib/core/services/*.dart` shims duplicate public paths. |
| Bug Density | 5 | Re-entrancy + dedup defects below. |
| State Management | 6 | Singleton caches with manual `dispose()`; no lifecycle ownership. |
| Error Handling | 6 | Good try/catch + `ErrorLogger`; raw throws in prefs writers; silent `catch (_)` in cast. |
| Performance | 7 | FIR offloaded to isolate; timeouts guard hangs. |
| Memory Safety | 5 | `dispose()` defined but **never called in `lib/`** (`cast_service.dart:473`, `hires_audio_service.dart:502`, `usb_exclusive_service.dart:364`); `_pcmBuffer` unbounded until `stopCapture`. |
| Concurrency | 5 | Read-modify-write prefs without locks; capture re-entry (`room_correction_service.dart:431-463`). |
| Code Hygiene | 5.5 | 480/507-line services; stale shim headers; empty catches. |
| Security | 7 | Mic permission handled; USB labelled experimental. |
| Accessibility | N/A | — |
| CI / DX / ADR | 6 | Strong core tests but no `test/domain/services/`. |

**Top gaps:** (1) layer violation (platform code in `domain/services` + duplicate `core/services` shims); (2) singleton `dispose()` never called; (3) concurrency lost-update races in `device_profile_service.dart:118-140` and `settings_profiles_service.dart:162-183`; (4) `startCapture` re-entrancy (`:431-463`); (5) raw-throw write methods; (6) `getAudioOutputInfo` dedups on only 3 fields vs the 17-field listener (`hires_audio_service.dart:194-197`).

---

### lib/domain/usecases — **6.5 / 10**

| Dimension | Score | Key gap (evidence) |
|---|:---:|---|
| Architecture | 5 | `backup_usecases.dart` imports `drift`/`shared_preferences`/`AppDatabase` (962-line god class); `playlist_io_usecases.dart:2,7` imports `dart:io`/`path_provider`. |
| Bug Density | 6 | Cross-platform folder-name bug; PLS escaping; N+1 queries. |
| State Management | 8 | Stateless delegates. |
| Error Handling | 6.5 | Most use `Result`/`Either`; `backup_usecases.dart:309-326,899-961` throws raw `FormatException`. |
| Performance | 5.5 | N+1 playlist queries (`:56-66`); ~30 sequential unbatched prefs writes (`:534-657`); full-library export in memory. |
| Memory Safety | 7 | Import capped 10 MB; export data-driven. |
| Concurrency | 6 | Import/export merge prefs via unlocked read-modify-write (`:801-820`). |
| Code Hygiene | 6 | 962-line file not in the fat-file ratchet; redundant `_validateSchema`. |
| Security | 7 | Import size cap + schema validation + binary detection; path traversal not exploitable. |
| Accessibility | N/A | — |
| CI / DX / ADR | 7 | Backed by 6+ test files. |

**Top gaps:** (1) 962-line god class; (2) raw `FormatException`; (3) `folder_usecases.dart:67-71` splits by `Platform.pathSeparator` on `/`-normalized paths (Windows bug); (4) N+1 + unbatched I/O; (5) PLS export does not escape `=`/newlines and `parseM3uContent` accepts URLs as local paths (`playlist_io_usecases.dart:61-78,140-153`); (6) unlocked prefs merge.

---

### lib/domain/repositories — **7.5 / 10**

| Dimension | Score | Key gap (evidence) |
|---|:---:|---|
| Architecture | 7 | Mostly pure abstracts, but default methods implement filtering using `data/db` types (`music_repository_interface.dart:1-5,28-47,98-101,204-212`). |
| Bug Density | 7.5 | No throwing logic; defaults can diverge from overrides. |
| Error Handling | 8 | Consistent `Result`/`Either`, no raw throws. |
| Performance | 6.5 | Default `watchAllSongs().map(filter)` is a full-table watch if overridden wrongly (`:40-47`). |
| Memory Safety | 8 | Stateless. |
| Concurrency | 8 | No shared mutable state. |
| Code Hygiene | 8 | Well-documented. |
| Security | 8 | Contract level; destructive cascade documented. |
| Accessibility | N/A | — |
| CI / DX / ADR | 6.5 | Covered indirectly; no contract test. |

**Top gaps:** (1) default implementations in an interface using `data/db` types; (2) `watchSongsInFolder` default watches the whole table; (3) `validateRules` default returns `const []` (silently "valid") (`smart_playlist_engine_interface.dart:15`); (4) no shared contract test matrix; (5) `deleteSongs` cascade is documentation-only.

---

### lib/domain/interfaces — **7.5 / 10**

| Dimension | Score | Key gap (evidence) |
|---|:---:|---|
| Architecture | 8.5 | Pure dependency-inversion contracts, minimal deps. |
| Bug Density | 9 | No logic. |
| Error Handling | 6.5 | No documented failure semantics (null vs throw vs empty). |
| Performance | 7.5 | `putCachedArtwork` permits unbounded cache growth. |
| Memory Safety | 8.5 | Contracts only. |
| Concurrency | 7 | No thread-safety/lifetime guarantees on cache/pusher contracts. |
| Code Hygiene | 9 | Concise, documented. |
| Security | 6.5 | `proxy_applier_interface.dart:9-15` passes plaintext `password`. |
| Accessibility | N/A | — |
| CI / DX / ADR | 6 | No tests reference the 5 files. |

**Top gaps:** (1) undocumented failure contracts (`artwork_resolver_interface.dart:9-13`, `lyrics_provider_interface.dart:8-14`, `proxy_applier_interface.dart:10-15`); (2) plaintext password parameter (`proxy_applier_interface.dart:14`); (3) fire-and-forget `scrobble_sink_interface.dart:9-18`; (4) cache contract has no eviction/thread-safety statement; (5) no interface tests.

---

## Prioritized remediation roadmap

Status legend: `[ ]` open · `[~]` in progress · `[x]` implemented & verified.

### P0 — security & data-loss (fix first)
- [x] 1. **Arbitrary file deletion** — `MusicRepository.deleteSongs` now gates on `_isSafeLocalDeletePath` (absolute + audio-extension allowlist + symlink/root containment via `SafeFilePath`; fails safe) (`lib/data/repositories/music_repository.dart`).
- [x] 2. **WebView host allowlist bypass** — `_isTrustedGoogleNavigation` now uses exact/dotted-suffix matching (`lib/features/auth/presentation/ytm_web_login_sheet.dart`).
- [x] 3. **Radio SSRF** — `RadioStation.isHttpUrl` rejects loopback/private/link-local/unique-local hosts (`lib/domain/models/radio_station.dart`, reused by `radio_screen.dart`).
- [x] 4. **Playlists undo deletes songs / silent online delete** — undo restores captured `songIds` via `PlaylistCubit.restorePlaylist`; online delete now confirms (`lib/features/playlists/**`).
- [x] 5. **Tag editor state sync** — `tag_field_widget.dart` is stateful with a `TextEditingController` synced in `didUpdateWidget`.
- [x] 6. **Queue lost updates** — queue mutations serialized under `_queueMutex` and recomputed from fresh state (`player_queue_slots.dart`).

### P1 — correctness, silent failures, leaks
- [~] 7. **Adopt `AppError`** — `resolveAppError` now handles timeout/TLS/format/drift; **not** yet adopted across features and the two `Result` types remain (partial).
- [x] 8. **Persist/restore Quran Mode; fix inverted reset; apply preamp** — service wired via `PlayerQuranManager`, reset reapplies the profile, preamp applied/restored.
- [x] 9. **Fix `YtmBrowseService.clearCache` hang + O(n²) card rebuild** — pending feed completed, fetches parallelized, `queueSongs` hoisted.
- [~] 10. **Dispose leaks** — `YtmService` timer/notifier, `_weakLargeCache` sweep and sheets `AppLifecycleListener` fixed; singleton domain-service `dispose()` still not wired (partial).
- [~] 11. **Bound caches** — `_slotLookupCache` and `_headerTrimCache` bounded; static shell locale cache not yet bounded (partial).
- [x] 12. **Settings dirty-field reconciliation + secure-write failure surfacing** — done.
- [ ] 13. **DB encryption decision** + `DatabaseHealthCheck` tests + migration rollback tests (not started).

### P2 — performance, tests, A11y, DX
- [ ] 14. **Move heavy work off the UI isolate** — not started (scanner genre N+1 reduced, but no isolate moves).
- [ ] 15. **Decompose god files** and add them to the fat-file ratchet (not started).
- [~] 16. **Raise the coverage floor** — new focused tests added (Quran, queue mutex, settings dirty, domain equality, data hardening, etc.); floor unchanged (partial).
- [~] 17. **Accessibility sweep** — Semantics added to accent swatches, rating stars, rule cards, inspector tabs, sort options, progress rings, hero artwork, splash logo, library grid tiles, onboarding; a11y matrix not yet extended (partial).
- [~] 18. **l10n sweep** — `folder_detail` "Top Songs" localized; downloads/auth/widget/smart-playlist/tag-editor/onboarding strings still raw (partial).
- [~] 19. **Unify duplicated primitives** — responsive `contentMaxWidth`/`isShortHeight` unified and router now uses motion tokens; `PulsrToast`/`Result`/`AsyncMutex` still duplicated (partial).
- [x] 20. **Add ADRs** for DI, router, responsive, network/proxy, telemetry, settings, playlists, domain layering; ADR-003 corrected (`docs/adr/007`–`014`). Note: `007-ui-sound-design.md` pre-existed with the same number (owned by separate uncommitted work).

---

## Implementation log

> Appended by the remediation run (2026-10-02). Full project analysis must stay green
> (`flutter analyze --fatal-infos --fatal-warnings`) and tests must pass before an item is ticked.

### Verification gate (final)
- `flutter analyze --fatal-infos --fatal-warnings` → **No issues found**.
- `flutter test` → **+1730 passed, 0 failed**.
- Ratchets green: `l10n_literal_ratchet_test`, `rtl_ratchet_test`, `code_hygiene_test`, `empty_catch_ratchet_test`, `fat_file_ratchet_test`.

### Work packages executed (parallel subagents, file-disjoint)
| Package | Scope | Status |
|---|---|---|
| PKG1 | Security P0 (delete path guard, host allowlist, radio SSRF, widget URL) | done |
| PKG2 | Player / Quran / Queue (persistence, reset, preamp, mutex, singleton, cache, O(n²)) | done |
| PKG3 | Tag editor + playlists + playlist detail | done |
| PKG4 | Settings (dirty reconcile, `unawaited`, secure-write, poll guard, a11y) | done (resumed after interrupt) |
| PKG5 | Data layer (sublist clamp, MQA, caches, DB state, lyrics lock, prefs, scanner) | done (resumed after interrupt) |
| PKG6 | Core services / network / DI / errors (`YtmService` dispose, `resolveAppError`) | done |
| PKG7 | Core UI (weak-cache sweep, `contentMaxWidth`, motion tokens, telemetry sink) | done |
| PKG8 | Features A: library / home / search / smart-playlist | done |
| PKG9 | Features B: downloads / ytm* / onboarding / splash / sheets / shell / details / queue | done |
| PKG10 | Domain equality/contracts + ADRs 007–014 | done |

### Notable new/updated tests
- `test/features/quran_mode/quran_mode_persistence_test.dart`, `test/features/queue/queue_mutex_test.dart`
- `test/features/tag_editor/tag_field_widget_test.dart`, `test/features/playlists/playlist_undo_restore_test.dart`
- `test/features/settings/settings_dirty_reconciliation_test.dart`
- `test/data/audio/audio_decoder_hardening_test.dart`, `test/data/repositories/prefs_repository_hardening_test.dart`, `test/data/lyrics/lyrics_offset_store_atomic_test.dart`
- `test/features/home/home_cubit_test.dart`, `test/features/downloads/downloads_selection_pruning_test.dart`
- `test/domain/models/value_equality_test.dart`, `test/domain/usecases/folder_usecases_test.dart`
- `test/responsive/content_max_width_unification_test.dart`, `test/core/widgets/gpu_budget_consumer_test.dart`
- Updated: `test/errors/app_error_taxonomy_test.dart`, `test/core/services/ytm_service_test.dart`, `test/features/library/duplicate_finder_test.dart`.

### Deferred (open) work
- **P1-7**: full `AppError` adoption + unify `Result`/`AppFailure`.
- **P1-10**: wire `dispose()` for singleton domain services (`cast`, `hires`, `usb_exclusive`).
- **P1-11**: bound the static shell locale cache (`nav_destinations.dart`).
- **P1-13**: DB encryption decision, `DatabaseHealthCheck` + migration-rollback tests.
- **P2-14**: move search fuzzy ranking / library rating sort / scanner enrichment / 10k-queue materialization off the UI isolate.
- **P2-15**: decompose the god files and extend the fat-file ratchet.
- **P2-16**: raise the coverage floor above 3 %.
- **P2-17**: complete the accessibility matrix and extend `accessibility_compliance_test.dart`.
- **P2-18**: finish the l10n sweep for downloads/auth/widgets/smart-playlist/tag-editor/onboarding.
- **P2-19**: merge duplicate `PulsrToast`, duration tokens, device classification, and `AsyncMutex` vs `mutex`.

### Notes
- The working tree already contained unrelated uncommitted work (a "sound" feature: `sound_feedback_service.dart`, `pulsr_toast.dart`, `pulsr_switch.dart`, `prefs_keys.dart`, `auth_cubit.dart`, `library_screen.dart`, `downloads_cubit.dart`, `sounds.md`, ADR `007-ui-sound-design.md`). It was left intact.
- `test/features/playlists/playlist_cubit_test.dart` now calls `TestWidgetsFlutterBinding.ensureInitialized()` because the pre-existing sound feature triggers haptics from `PlaylistCubit`.
- `ftsRebuildFailed` remains static in `AppDatabase` because off-limits static readers in `music_repository.dart` still use it; the repair budget and `migrationFailed` are now per-instance.

