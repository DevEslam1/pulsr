# Data-layer audit — pulsr (Flutter + Drift/SQLite)

Scope: `lib/data/db/**`, `lib/data/repositories/**`, `lib/data/scanner/**`, `lib/data/usecases/**`,
`lib/data/models/**`, plus the two data-layer collaborators they delegate to
(`lib/data/services/library_maintenance_service.dart`, `lib/core/widgets/entity_by_id_loader.dart`).
Baseline compared: `gaps.md` (2026-10-02, with the 2026-10-04 remediation header).
Read-only: no source file was modified. No `flutter analyze` / `flutter test` was run.

Method: every baseline claim below was re-read in the current tree; line numbers are from the
working copy at audit time. Evidence tiers used: **code** (implementation), **test**, **doc**.
Claims that could not be tied to a concrete line are listed under 待证 at the end of this file,
not in the findings.

---

## STILL-OPEN

Baseline gaps that still reproduce on the current tree.

### S1 — Database is unencrypted at rest (baseline db gap #1) — STILL-OPEN
`lib/data/db/app_database.dart:133`
```dart
AppDatabase() : super(driftDatabase(name: 'pulsr_music_db'));
```
No SQLCipher dependency (`pubspec.yaml:20-24` has `drift`, `drift_flutter`, plain
`sqlite3_flutter_libs`), no `PRAGMA key`, no `encryptedDatabase`. The file therefore holds every
local path, play history, favorite flag and queue row in plaintext in the app sandbox. The
remediation header itself still lists "DB-at-rest encryption" as open, so code and doc agree.

### S2 — `reconcileDownloadedSong` metadata fallback is an unindexed full scan (baseline repositories perf gap) — STILL-OPEN
`lib/data/repositories/music_repository.dart:3084-3090`
```dart
t.title.lower().equals(matchMetadata.title.toLowerCase()) &
t.artist.lower().equals(matchMetadata.artist.toLowerCase()) &
t.durationMs.isBetweenValues(...)
```
`lower(title)` / `lower(artist)` cannot use `idx_songs_title_nocase` / `idx_songs_artist_nocase`
(those index `title COLLATE NOCASE`, not `lower(title)`). This runs on every completed download
whose exact-path lookup misses, i.e. once per download, over the whole `songs` table. On a 10k-row
library that is a 10k-row scan plus 10k string lowerings per download.

### S3 — Whole library is copied as `List<Map<String,dynamic>>` into `compute` (baseline scanner perf #1) — STILL-OPEN
`lib/data/scanner/media_scanner_service.dart:472-476`
```dart
rawSongs: songsToProcess.map((s) => Map<String, dynamic>.from(s.getMap)).toList(),
```
Every scan (incremental included) deep-copies the full `SongModel` map list and ships it across the
isolate boundary; the parsed `SongsTableCompanion` list is then shipped back. Peak memory is roughly
two to three copies of the catalog.

### S4 — Per-genre `queryAudiosFrom` N+1 is still present (baseline scanner perf #2) — PARTIAL
`lib/data/scanner/media_scanner_service.dart:405-415`
```dart
final audios = await _audioQuery.queryAudiosFrom(AudiosFromType.GENRE_ID, g.id);
```
The inline `genre` fast path now covers Android 11+ rows, so only songs without an inline genre hit
the loop — the N+1 shape survives (one MediaStore query per genre, over the whole genre table) but
its blast radius is smaller. Not fixed, only narrowed.

### S5 — Sequential per-song quality enrichment (baseline scanner perf #3) — STILL-OPEN, worsened
`lib/data/scanner/media_scanner_service.dart:689` then `:721`
```dart
final res = await _repository.getAllSongs();
...
await channel.invokeMapMethod<dynamic, dynamic>('readTags', {'path': song.path, ...});
```
The pass first materialises the **entire** library (`getAllSongs()`, no limit), filters it in Dart,
then performs one platform-channel `readTags` round trip per song, strictly sequentially, on the
main isolate. 10k tracks ⇒ 10k JNI tag reads plus 10k full row objects held in memory; the scan
already knows which rows need enrichment, so the full read is avoidable.

### S6 — Static mutable caches shared across instances (baseline db state gap + scanner state gap) — STILL-OPEN (partially fixed)
`lib/data/db/app_database.dart:35-36` (`ftsRebuildFailed`, `ftsTrigramSupported`) and
`lib/data/scanner/media_scanner_service.dart:241` (`static final Map<String, bool>
_nomediaDirCache`) remain process-global. The FTS *attempt* counters did move to instance fields
(`_ftsRepairAttempts`, `app_database.dart:49`), so this is now "two static flags + one static capped
cache" rather than four fields.

### S7 — Denormalized `song_count` maintained by hand-rolled SQL that can drift (baseline db architecture gap) — STILL-OPEN
`lib/data/repositories/music_repository.dart:2663`, `:2866-2878`, `:2991-3001`
```dart
await _db.customStatement(
  "UPDATE albums SET song_count = (SELECT COUNT(*) FROM songs WHERE ...);",
);
```
Same pattern as the baseline (`:1680-1686`, `:1937-1948` in the old numbering), now duplicated in
four places with four slightly different WHERE clauses (`:2844` and `:2996` count
`is_missing = 0` only; `:2663` also filters source and cue state). Any read path that trusts
`song_count` (e.g. `getAlbums()` at `:1287` filters `songCount > 0`) inherits whichever variant ran
last.

### S8 — `music_repository.dart` is still a god object, and larger (baseline repositories architecture gap) — STILL-OPEN
3768 lines now (baseline recorded 2508), 100+ repository methods plus static caches and cue-sheet
parsing helpers. No extraction happened; the file grew by ~50 %.

### S9 — Scanner delta epoch is not durable (derived from the baseline `markScanComplete`/incremental gaps) — STILL-OPEN
`lib/data/scanner/media_scanner_service.dart:110-114`
```dart
void markScanComplete({int? epochSec}) {
  _lastScanAt = DateTime.now();
  _lastScanEpochSec = epochSec ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
```
Both fields live only in memory and are never persisted, so after every cold start `_lastScanEpochSec`
is null and `scanDeviceLibrary(incremental: true)` (guard at `:357`) degrades to a full scan. The
baseline's "epoch missing on some paths" is fixed; "the epoch does not survive a restart" is not.

### Verified FIXED (baseline claims that no longer reproduce)
| Baseline claim | Verdict | Evidence |
|---|---|---|
| `deleteSongs` calls `File(path).delete()` with no containment (arbitrary file deletion) | **FIXED** in `music_repository` | `music_repository.dart:2916-2960` `SafeFilePath.validate(...)` + `p.isWithin(canonicalRoot, canonicalFile)`; but see N1/N2 for two surviving holes |
| v11 migration failure sets the *FTS* flag (`app_database.dart:268`) | **FIXED** | `app_database.dart:330` `db?.migrationFailed = true;`, flag declared separately at `:43`; see N10 for the new problem |
| Empty catch around the v11 rollback | **FIXED** | `app_database.dart:322-330` logs rollback failure via `ErrorLogger` |
| `PrefsRepository._writeToDisk` silently drops unsupported types | **FIXED** | `prefs_repository.dart:168-179` constructs `ArgumentError`, logs, and rethrows |
| `PrefsRepository.dispose()` fires `unawaited(flush())` | **FIXED** | `prefs_repository.dart:91-96` `await flush();` |
| Download persistence swallows all errors (`download_repository_impl.dart:680-686`) | **FIXED** | `download_repository_impl.dart:1054-1064` logs encode/persist failures and checks `prefs.setString` |
| Watch queries swallow DB errors via `Stream.handleError` | **FIXED except one** | `onResultError` extension at `music_repository.dart:27-75`, used by every watch but `watchSongsInFolder` (N3) |
| `DatabaseHealthCheck` has zero tests | **FIXED** | `test/data/db/database_health_check_test.dart` (6 test bodies) |
| Scanner bulk enrichment re-entrancy | **FIXED** (bulk path) | `_isEnrichingQuality` guarded at `media_scanner_service.dart:684-686` |
| `markScanComplete()` overwrites `_lastScanAt` without epoch | **FIXED** | `media_scanner_service.dart:112-116` always sets `_lastScanEpochSec` |
| Scanner has no scan re-entrancy guard | **FIXED** | `media_scanner_service.dart:308-313` `_isScanning` early return |

---

## NEW FINDINGS

14 defects not covered by the baseline. Ordered by impact; confidence noted per item.

### N1 — Unvalidated `File.delete()` in `LibraryMaintenanceService` (arbitrary file deletion) — high, code
`lib/data/services/library_maintenance_service.dart:79-80`
```dart
final f = File(path);
if (await f.exists()) await f.delete();
```
`path` is `filePath` from a persisted `DownloadTask` JSON blob (`download_repository_impl.dart:510-514`)
or `song.path` read back at `:39-43`. There is **no** `SafeFilePath.validate`, no extension check, no
canonical-root containment — the exact control that was added to `music_repository.dart:2916-2960`.
The method then also deletes `$path.part`, `.parts`, `.part.stamp` (`:82-86`).
Consequence: `deleteDownload()` on a task whose `filePath` is stale, restored from a backup, or points
at a shared/public directory removes that file with no policy check; the remediation claim "deletes
validated through SafeFilePath" holds for only one of the two delete paths.

### N2 — Allowed delete roots exclude the real library location, so `deleteSongs` never deletes files — high, code
`lib/data/repositories/music_repository.dart:2903-2908`
```dart
await add(getApplicationDocumentsDirectory);
await add(getApplicationSupportDirectory);
await add(getTemporaryDirectory);
if (Platform.isAndroid) await add(getExternalStorageDirectory);
```
`getExternalStorageDirectory()` is the **app-specific** external dir
(`/storage/emulated/0/Android/data/<pkg>/files`), not the public `Music/` tree the scanner indexes
(`media_scanner_service.dart:342` queries MediaStore `EXTERNAL`) and not the default download
destination (`download_settings.dart:11` — "SAF uri or null for default Music/"). So
`_isSafeLocalDeletePath` returns false for essentially every library row, and
`deleteSongsWithReport` silently skips the file:
`music_repository.dart:3011`
```dart
if (!await _isSafeLocalDeletePath(path)) continue;
```
Consequence: "delete song" removes the DB row but leaves the audio file; the next full scan
re-indexes it (MediaStore id still valid), so the track **reappears** with zero play count and no
favorites/ratings. It also means the app has two contradictory delete policies: N1 deletes
anything, `deleteSongs` deletes almost nothing.

### N3 — `watchSongsInFolder` reintroduces the swallowed-error pattern its own file documents — medium-high, code
`lib/data/repositories/music_repository.dart:552-553`
```dart
}).handleError((Object e) => Left<AppFailure, List<SongsTableData>>(
    DatabaseFailure('Failed to watch folder songs', e)));
```
`Stream.handleError` discards the callback's return value — exactly what the extension doc at
`music_repository.dart:29-33` says ("`Stream.handleError` discards its callback's return value, which
silently swallowed every database failure in these watch queries"). Every other watch in the file uses
`.onResultError(...)`. Consequence: a DB failure in the folder browser produces a completed stream with
no `Left`, so the UI shows an empty folder (or keeps the previous frame) with no error/retry state.

### N4 — Multi-step deletes/count updates are not atomic — medium, code
`lib/data/repositories/music_repository.dart:2858-2867`
```dart
final deletedCount = await (_db.delete(_db.songsTable)
      ..where((t) => t.isMissing.equals(true) & t.source.equals(SongSource.local))).go();

// Reconcile and cleanup orphaned albums and artists in single SQL queries
await _db.customStatement('DELETE FROM albums WHERE NOT EXISTS (...)');
```
No `_db.transaction`. Four separate statements (album prune, artist prune, album count, artist count)
follow the delete. `expandCueSheets` has the same shape: the insert/update/delete block is inside a
transaction (`:2615-2659`) but the album/artist count fixes at `:2663` and `:2666` run **after** it
commits. `cleanupOrphanedSongs` likewise marks rows missing in one batch (`:2757-2775`) and rewrites
counts in later, separate batches (`:2817-2838`) plus two more statements (`:2844`, `:2847`).
Consequence: a kill/SQLITE_BUSY between steps leaves `song_count` and album/artist rows permanently
inconsistent — an album page can show "12 tracks" over an empty list, and orphaned albums survive
until the next full cleanup. Only `deleteSongsWithReport` (`:2971`) does this correctly.

### N5 — Excluding a folder converts its tracks into "missing files", which a later cleanup hard-deletes — medium-high, code
`lib/data/scanner/media_scanner_service.dart:880-887`
```dart
if (input.excludedFolders.any((folder) {
  ... return normPath.startsWith(prefix) || normPath == normFolder;
})) { continue; }
```
Excluded rows are dropped from the parse, so their ids never reach `validSongIds` (`:918`), and the
post-scan cleanup uses exactly that set (`:512`):
```dart
await _repository.cleanupOrphanedSongs(parseResult.validSongIds);
```
which marks every absent id `is_missing = 1` (`music_repository.dart:2768`). `hardDeleteMissingSongs`
(`:2858-2863`) then deletes those rows for real. Consequence: "hide this folder" + later "remove
missing files" deletes the user's hidden library rows (favorites, play counts, ratings keyed by song
id in `SongRatingStore`), and un-excluding the folder only restores metadata after a full rescan, with
stats lost. Same mechanism applies to `minDurationSec` changes (short tracks become "missing").

### N6 — `artists.album_count` is dead schema — medium-low, code
`lib/data/db/tables.dart:127`
```dart
IntColumn get albumCount => integer().withDefault(const Constant(0))();
```
No application code ever writes it: the only `ArtistsTableCompanion` constructions are
`media_scanner_service.dart:958` (`id`, `name`) plus `songCount` via `copyWith`, and
`music_repository.dart:2834` (`songCount` only). No read either (`t.albumCount` appears nowhere).
Every artist row therefore carries a permanent 0 that any future reader would present as fact.

### N7 — `songs.pending_download_path` is dead schema plus a dead index — low-medium, code
`lib/data/db/tables.dart:80-81`
```dart
/// Destination a download is writing to, used to match the row MediaStore
/// creates once the file lands.
TextColumn get pendingDownloadPath => text().nullable()();
```
Every write in the tree sets it to `null` (`music_repository.dart:3158`, `:3294`, `:3413`); nothing
ever assigns a destination and nothing ever reads it, yet `app_database.dart:308-309` creates
`idx_songs_pending_dl` on it. The documented matching flow does not exist.

### N8 — FTS health check cannot detect a broken index; migration validator ignores v12 — medium-low, code
`lib/data/db/database_health_check.dart:125`
```dart
final ftsCheck = await _db.customSelect('SELECT COUNT(*) AS c FROM songs_fts;')
```
`songs_fts` is an external-content FTS5 table (`content='songs'`, `app_database.dart:139`), so
`COUNT(*)` is answered from the content table and returns the song count even when the index is empty
or corrupt. The check that would actually fail is `INSERT INTO songs_fts(songs_fts)
VALUES('integrity-check')`. Separately, `requiredTables` (`:289-298`) omits the v12
`online_playlists` / `online_playlist_entries`, so `validateSchema()` reports `isValid: true` for a
database missing the two newest tables.

### N9 — Migration degradation is recorded but never surfaced — medium-low, code
`lib/data/db/app_database.dart:43`
```dart
bool migrationFailed = false;
```
Set at `:330` when the v11 constraint migration rolls back, but the only readers are tests
(`test/data/db/drift_migration_smoke_test.dart:20,138`, `test/db/migration_resilience_test.dart:24`). No health
report, settings screen or log line consumes it. A device whose upgrade silently lost the UNIQUE
indexes and the dedupe pass looks identical to a healthy one; the baseline defect "wrong failure flag"
was replaced by "correct flag, no consumer".

### N10 — Unbounded static CUE hash cache — low, code
`lib/data/repositories/music_repository.dart:2414`
```dart
static final Map<String, int> _cueContentHashCache = {};
```
Never evicted in production (only `resetEmbeddedCueProbeState()` clears it, `:2416-2421`), unlike the
sibling `_embeddedCueMisses` which is capped at 20 000 (`:2406-2407,2423-2428`). Growth is bounded by
the number of CUE-backed containers, so impact is small, but it is lifetime-of-process state.

### N11 — `expandCueSheets` stats and parses the whole library on the main isolate after every scan — medium, code
`lib/data/repositories/music_repository.dart:2490-2498` then `:2528`
```dart
final containers = await (_db.select(_db.songsTable)
      ..where((t) => t.id.isBiggerThanValue(0) & t.source.equals(SongSource.local) ...))
    .get();
...
} else if (!_embeddedCueMisses.contains(container.path)) {
  final embedded = await CueParser.extractEmbeddedCueSheet(container.path);
```
The query has no path filter (all local rows, not just `.cue`-adjacent files), and for every row
without a sibling `.cue` it performs a file read/probe to look for an embedded sheet. On a 10k-track
library that is 10k row objects plus up to 10k file opens on the platform thread after each scan —
the same work the scanner just did, repeated because the container set is not narrowed.

### N12 — Routing an album/artist deep link re-subscribes on every router rebuild — low-medium, code
`lib/core/widgets/entity_by_id_loader.dart:55-66`
```dart
final resubscribe = oldWidget.fetchSingle != widget.fetchSingle ||
    oldWidget.watch != widget.watch || oldWidget.match != widget.match;
```
The route builders create fresh closures on every call
(`lib/core/router/app_router.dart:216` `watch: () => repo.watchAlbums(),`), and Dart closures are never
`==` across evaluations, so `didUpdateWidget` always resubscribes: `_entity = null` (skeleton flash)
then `repo.watchAlbums()` — a full albums-table query — for a page that already had its entity.

### N13 — `PrefsRepository.flush()` drops writes that fail — medium-low, code
`lib/data/repositories/prefs_repository.dart:106-116`
```dart
final writes = Map<String, dynamic>.from(_pendingWrites);
_pendingWrites.clear();
...
try { await _writeToDisk(entry.key, entry.value); } catch (e, st) { firstError ??= e; }
```
The pending map is cleared **before** the writes land, and a failed entry is only re-thrown to
`_flushSafely()` (`:141-147`), which logs and drops it. The value survives only in `_memoryCache`, so
it reads back correctly for the rest of the session and silently disappears after a restart — the
class of silent-loss the prefs rewrite was meant to remove.

### N14 — Playlist import creates the playlist outside the add-songs transaction — low, code
`lib/data/usecases/playlist_io_usecases.dart:368-374`
```dart
final createRes = await _repository.createPlaylist(playlistName);
...
if (matchedSongIds.isNotEmpty) {
  await _repository.addSongsToPlaylist(playlistId, matchedSongIds);
}
```
`addSongsToPlaylist` is its own transaction (`music_repository.dart:1631`); the create is not part of
it. If the insert fails (constraint, disk full, app killed) the user is left with an empty playlist
named after the file and no error, since the failing call's `Left` is ignored here.

---

## RANKED FIX LIST

Ordered by (user harm × likelihood) / effort. "Guard" = the existing helper to reuse.

1. **N2 — make `deleteSongs` actually delete, or stop promising it.** Add the public library roots
   (`getExternalStorageDirectories(type: StorageDirectory.music)`, the configured `downloadLocation`,
   SAF URIs) to `_allowedDeleteRoots`, and treat "no matching root" as a reported failure
   (`deleteSongsWithReport` already returns a report). Today the user deletes a track and it returns
   on the next scan. Guard: `_isSafeLocalDeletePath` + `SafeFilePath`.
2. **N1 — route `LibraryMaintenanceService.removeDownloadedArtifacts` through the same guard.**
   Validate `path` with `SafeFilePath.validate` (audio extensions, absolute, exists) and require
   containment in an allowed root before `File.delete()`; keep the `contentUri` branch as is. This is
   the one remaining arbitrary-delete surface and it sits directly behind a user-visible "delete
   download" button.
3. **N5 — separate "excluded/hidden" from "missing".** Either add `excludedFolders` to the cleanup
   input (do not mark ids that were skipped by an exclusion) or add an `is_hidden` column; do not let
   `hardDeleteMissingSongs` reach rows the user only hid. This is the only chain that silently
   destroys library rows plus ratings.
4. **N4 — wrap each multi-step write in one `_db.transaction`:** `hardDeleteMissingSongs`, the
   `expandCueSheets` count block (move `:2663/:2666` inside the enclosing transaction), and
   `cleanupOrphanedSongs` count recalculation. Then delete the duplicated hand-written count SQL
   (S7) in favour of one helper with a single WHERE clause.
5. **N3 — replace `.handleError(...)` with `.onResultError(...)`** in `watchSongsInFolder`; it is a
   one-line change and restores the error contract every other watch already honours.
6. **S2 — index the download-reconcile lookup.** Add `idx_songs_title_artist_lower` or store a
   normalized `title_key`/`artist_key`, then reuse it in `_rematch`/`reconcileDownloadedSong`; this is
   the baseline's still-open unindexed scan and it runs per download.
7. **S5/S3 — stop loading and shipping the whole library.** Have the scanner pass only ids needing
   enrichment (a `SELECT id, path WHERE codec IS NULL` projection), bound the platform-channel
   concurrency, and stream parse input in pages instead of one `List<Map>`.
8. **N9/N8 — make degradation observable.** Surface `migrationFailed` in `DatabaseHealthCheck`/
   settings, switch the FTS probe to `integrity-check`, and add the v12 tables to `requiredTables`.
9. **N6/N7 — drop or implement the dead schema.** `artists.album_count` and
   `songs.pending_download_path` (+ `idx_songs_pending_dl`) should be removed in the next schema
   version, or wired up if the flows they document are still planned.
10. **N11 — narrow `expandCueSheets`.** Query only containers that have a sibling `.cue`, an
    `embedded://` marker or an existing virtual row; move the probe loop to `compute`.
11. **N12 — compare stable keys, not closures,** in `EntityByIdLoader` (pass an `id` and compare it),
    so a router rebuild does not refetch and flash the skeleton.
12. **N13 — keep failed entries in `_pendingWrites`** (re-queue on error) so a transient prefs
    failure is retried instead of being logged away.
13. **N14 — create + populate the imported playlist in one transaction** (or delete the empty
    playlist when the add fails).
14. **N10 — cap `_cueContentHashCache`** the same way `_embeddedCueMisses` is capped.

---

## 待证 (not counted above)

- **`cacheOnlinePlaylist` partial snapshots.** `music_repository.dart:1829-1870` deletes and rewrites
  `online_playlist_entries` wholesale even when `fullSnapshot: false`, while leaving `cachedAt`
  untouched (`:1818-1822`). If a caller seeds with a page-sized list
  (`online_playlist_detail_screen.dart:622` passes `_tracks`, `playlist_cubit.dart:1207` passes
  `entry.tracks`), the cached track list shrinks but still looks fresh to the sync. Needs the caller's
  pagination contract to confirm — not proven here.
- **`songs.date_added` unit mixing.** `tables.dart:33` allows seconds *or* milliseconds; the scanner
  normalises to ms (`media_scanner_service.dart:933`) and `smart_playlist_engine.dart:339-342` splits
  on `10000000000`, but no migration rewrites legacy seconds rows (`app_database.dart:455-467`
  backfills only playlist timestamps). Every current writer uses ms, and `git log -S` shows no
  seconds-era writer in this history, so the mixed-unit ordering bug is **unproven** for databases
  created by this code — only reachable from a pre-history database.
- **`queue_items` vs `is_missing`.** `getSavedQueue` (`music_repository.dart:2070`) returns queue rows
  without joining `songs`, so a saved queue can reference rows later marked missing by N5. Whether the
  player filters them before enqueue was not traced.
- **`ArtistsTable`/`AlbumsTable` artwork columns** are read in many places but written only by
  `updateAlbumArtwork` (`:1335`) and the scanner; artist artwork appears never to be populated
  (`media_scanner_service.dart:958` sets only id/name). Not counted: no confirmed user-visible
  promise.
