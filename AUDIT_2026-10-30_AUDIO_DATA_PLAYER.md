# Audio, data and player — audit and remediation (2026-10-30)

Scope requested: **check the audio, data and player subsystems and push them to the maximum.**
"Maximum" is read against this repository's own quality model (`gaps.md`, 11 dimensions) and against
what is verifiable on this machine — not as a claim of 10/10 or of listening-test certification.

- **Tree:** `D:\Courses\Projectss\pulsr` @ `34f9a347` (working tree: 1 pre-existing change,
  `android/gradle.properties`, untouched by this pass)
- **Method:** three read-only subsystem audits with `file:line` evidence, then targeted fixes with
  regression tests, then the project gates.
- **Baseline before changes:** `flutter analyze --fatal-infos --fatal-warnings` → **0 issues**;
  `flutter test test/features/player test/data` → **2,021 / 2,021 passed**.

---

## 1. Verdict at a glance

| Area | Register (2026-10-02) | Verified today | What changed in this pass |
|---|---|---|---|
| `lib/features/player` | 5.5 / 10 | Baseline defects in the register were already fixed; **2 new high-severity defects** found | 4 fixes (Quran intent, autoplay queue race, seek semantics, media-id resolution) |
| `lib/data` (db, repositories, scanner) | 6.7 / 10 | Most register items fixed; **1 security + 1 data-loss + 1 "delete does nothing" defect** found | 7 fixes |
| `lib/data/audio` + native DSP | 6.0 / 10 | Register items addressed by earlier hardening; remaining gaps are native-contract and hardware-evidence issues, not Dart bugs | 0 code fixes, status verified |
| Gates | — | analyze 0 issues; player+data suites green | 12 new/updated tests |

The 2026-10-04 remediation header in `gaps.md` is accurate for the player and data items it names
(Quran persistence/restore, reset inversion, dead preamp, O(n²) id resolution, rating-store
singleton, slot-cache growth, SafeFilePath on `deleteSongs`, FTS flag, download persistence).
Re-litigating those would be wasted work; what follows is what is still wrong.

---

## 2. New defects found (and their status)

### 2.1 Data layer — 14 findings, 3 high

| # | Severity | Defect | Status |
|---|---|---|---|
| N1 | **High (security)** | `LibraryMaintenanceService.removeDownloadedArtifacts` called `File(path).delete()` on a persisted download path with **no containment check** — the second arbitrary-delete surface, behind the visible "delete download" button (`library_maintenance_service.dart:79-86`) | **Fixed** |
| N2 | **High (data loss)** | Hiding a folder removed its rows from `validSongIds`, so post-scan cleanup marked them `is_missing`, and "remove missing files" hard-deleted favourites/ratings/play counts (`media_scanner_service.dart:880` → `music_repository.dart:2768` → `:2858`) | **Fixed** |
| N3 | **High (correctness)** | `deleteSongs` refused every file outside app-private roots, so "delete song" removed the row and the next scan re-indexed the track with no stats (`music_repository.dart:2903-2908,3011`) | **Fixed (MediaStore path + explicit log)** |
| N4 | Medium | `watchSongsInFolder` used `Stream.handleError`, whose return value is discarded — folder DB failures completed silently, contradicting the file's own `onResultError` contract (`music_repository.dart:552`) | **Fixed** |
| N5 | Medium | `DatabaseHealthCheck` used `COUNT(*)` on an external-content FTS5 table (answered from the content table), so a stale/empty index always looked healthy (`database_health_check.dart:125`) | **Fixed** (`integrity-check`, rank 1) |
| N6 | Medium | `requiredTables` omitted the v12 `online_playlists` / `online_playlist_entries`, so a database missing them validated as complete | **Fixed** |
| N7 | Medium | `PrefsRepository.flush()` cleared the pending map before writing and dropped failures — the value survived only in memory and vanished on restart (`prefs_repository.dart:106-116`) | **Fixed (re-queue transient failures)** |
| N8 | Low–Med | Multi-step deletes/count rewrites outside a transaction (album/artist `song_count` drift) | Open |
| N9 | Low–Med | `artists.album_count` and `songs.pending_download_path` (+ its index) are dead schema | Open |
| N10 | Low | Unbounded static `_cueContentHashCache` | **Fixed (capped)** |
| N11 | Medium | `expandCueSheets` scans the whole local library and probes each container for embedded CUE after every scan | Open |
| N12 | Low–Med | `EntityByIdLoader` compares closures, so every router rebuild re-subscribes and flashes a skeleton | Open |
| N13 | Low | Playlist import creates the playlist outside the add-songs transaction | Open |
| N14 | Low | `migrationFailed` is recorded but never surfaced in health/settings | Open |

### 2.2 Player — 9 findings, 2 high

| # | Severity | Defect | Status |
|---|---|---|---|
| P1 | **High** | Quran Mode flipped itself on **every track change**: `isAutoTriggered` was never read, so a keyword heuristic (`"quran"`, `"surah"`, reciter names, any album containing "recitation") rewrote the DSP chain, overrode a manual on/off, and persisted the heuristic's decision (`player_playback_options_track_state.dart:59`, `..._quran.dart:189,736-747`) | **Fixed** |
| P2 | **High** | `fetchAndEnqueueAutoplay` appended to the queue outside `_queueMutex` with a pre-fetch `room` value → lost user remove/reorder, cap overshoot, duplicated batches (`player_queue_radio.dart:189-284`) | **Fixed (mutex + single-flight)** |
| P3 | Medium | Seek bar exposed two nested slider semantics nodes with conflicting values and duplicate 10 s actions (`player_seek_bar.dart:436`, `pulsr_slider.dart:222`) | **Fixed** |
| P4 | Medium | Transport buttons 28–42 dp because the theme's `sideButtonSize` has no 48 dp floor (`player_theme_scaffold.dart:187`, `player_controls.dart:128-143`) | Open |
| P5 | Medium | Quran badge is ~20 dp and unlabelled to a11y services (`quran_mode_badge.dart:28-35`) | Open |
| P6 | Medium | Quran tuning sliders have no label/`semanticFormatterCallback` (`quran_mode_sheet.dart:962`) | Open |
| P7 | Medium | Mute state lives outside `PlayerState`, so the tablet bar's mute icon is sampled at an arbitrary build (`playback_volume_mute.dart:13`) | Open |
| P8 | Low | Media-item ids were resolved twice (batch + loop); after 1,000 remote ids a cache eviction could disagree and append a ghost row (`player_cubit.dart:711,726`) | **Fixed** |
| P9 | Low | Two `AsyncGuard`s are write-only; index helpers used by tests are not the production math; Quran metadata errors swallowed | Open |

### 2.3 Audio

The register's audio defects were closed by the 2026-10-03/04 hardening (documented in
`docs/AUDIO_DSP_HARDENING_2026-10-03.md`, verified in code). What remains is **not a Dart defect**:

- The in-place playback path of `SincResampler` is a documented **passthrough**: a fixed-frame
  contract cannot express rate conversion (`SincResampler.h:47-52`). Real conversion exists only in
  the reverb wet path (`processPlanar`). The UI must keep surfacing this truthfully; implementing a
  streaming converter is a native design change, not a tuning knob.
- Bit-perfect/USB-DAC claims need **device measurements**; emulator and unit tests cannot certify them.
- 296 empty `catch` blocks remain across `lib/data/audio` (296), `lib/features/player` (94) — the
  global ratchet allows them, so they are a systemic hygiene item, not a per-file bug.

---

## 3. Fixes landed in this pass

1. **Shared deletion policy** — new `lib/core/utils/local_delete_guard.dart`
   (`allowedAppDeleteRoots`, `resolveDeletableAudioFile`) with canonical-path containment, symlink
   resolution and an extension allowlist. `MusicRepository` and `LibraryMaintenanceService` now use
   the same guard, so the two delete surfaces cannot drift apart again.
2. **Download artifacts guarded** — `library_maintenance_service.dart` validates the persisted path
   before any `File.delete()` (audio and `.part*` files); MediaStore request still runs first.
3. **`deleteSongs` actually deletes** — for paths outside app roots, the platform MediaStore delete
   is attempted (`deleteFromMusic`); if it removes nothing, the outcome is logged with the path
   instead of being silently skipped.
4. **Hidden ≠ missing** — `cleanupOrphanedSongs` takes `excludedFolderPrefixes` and never marks rows
   under a user-excluded folder as missing; the scanner passes the same list it filters with.
   Matching accepts both `/` and `\`, and a sibling with a shared prefix (`hidden2` vs `hidden`) is
   not treated as excluded.
5. **Folder watch errors surfaced** — `.handleError` → `.onResultError` in `watchSongsInFolder`.
6. **FTS probe that can fail** — `integrity-check` with `rank 1` (verified: `rank 0` and `COUNT(*)`
   both pass on a deliberately drifted index; `rank 1` raises `SQLITE_CORRUPT`).
7. **v12 schema validation** — online-playlist tables added to `requiredTables`.
8. **Prefs retry** — transient write failures are re-queued; deterministic `ArgumentError`s are not.
9. **CUE hash cache capped** (20k, evicting 25%).
10. **Quran Mode respects the user** — new persisted tri-state
    (`QuranModeService.getUserOverride` / `setUserOverride`, surfaced through `PlayerQuranManager`).
    Manual toggles record the decision; automatic activation is skipped whenever it would contradict
    an explicit choice, and never records itself as user intent.
11. **Autoplay append is serialized** — the network fetch stays outside the lock; eligibility,
    capacity (`room`), engine append and emit happen inside `_queueMutex`, with a single-flight latch.
12. **Seek semantics de-duplicated** — `excludeSemantics: true` on the time-based node, so the
    control announces once (time) instead of twice (time + percent).
13. **Media ids resolved once** — batch and per-item loops use the same resolution.

### Tests added/updated

| Test file | Coverage |
|---|---|
| `test/features/player/quran_mode_user_override_test.dart` (new) | manual off survives a Quran-looking track; manual on survives a normal track; never-chosen users still get auto activation; manual toggles persist |
| `test/data/services/library_maintenance_service_test.dart` | containment allows in-root audio + `.part`; refuses outside roots; fails closed with no roots; refuses non-audio |
| `test/data/db/music_repository_test.dart` | excluded folder rows stay visible; prefix sibling is not excluded; `watchSongsInFolder` surfaces DB failure |
| `test/data/db/database_health_check_test.dart` | drifted FTS index detected (row count still looks fine); v12 tables required |
| `test/data/repositories/download_repository_impl_extended_test.dart` | artifact delete still works inside an app root (path_provider mocked) |
| `test/data/scanner/media_scanner_service_test.dart`, `..._more_test.dart` | updated stubs for the new `excludedFolderPrefixes` argument |

### Developer experience

The exec sandbox inherits an empty `LOCALAPPDATA`/`ProgramFiles(x86)`, which makes `flutter` fail with
"Could not find the pub cache" and `%PROGRAMFILES(X86)% environment variable not found`. Added
`scratch/dev-env.ps1` (dot-source before `flutter`), which reconstructs the variables.

---

## 4. What is still open, in priority order

1. **Database encryption at rest** (register item, acknowledged structural): `AppDatabase` still opens
   a plain `driftDatabase`. Needs SQLCipher + key management + migration; not a one-pass change.
2. **Transport/Quran tap targets and labels** (P4–P6) — 28–42 dp buttons, 20 dp badge, unlabelled
   sliders. Requires layout review against the player goldens, hence not bundled with the logic fixes.
3. **Scanner scale** — the whole library is copied into `compute` (`media_scanner_service.dart:472`)
   and quality enrichment is a strictly sequential per-song channel call. On 10k tracks this is the
   largest remaining performance item.
4. **Transaction atomicity** for `hardDeleteMissingSongs` / `expandCueSheets` count rewrites (N8) and
   the duplicated hand-written `song_count` SQL.
5. **Observability** — `migrationFailed` is never surfaced (N14); dead schema (N9) should be removed
   in the next schema version.
6. **God files / empty catches** — `music_repository.dart` 3.7k lines, `audio_handler.dart` 3.1k;
   reducing empty catches is a ratchet-driven programme, not a spot fix.

---

## 5. Verification

| Gate | Before | After |
|---|---|---|
| `flutter analyze --fatal-infos --fatal-warnings` | 0 issues | **0 issues** |
| `flutter test test/features/player test/data` | 2,021 passed | **see run log: 2,033 passed** |
| `dart format` on all touched files | — | clean |
