# Open defect register (parsed from DELIVERY/feature-audit/remediation/ledger.json)

## Area 1
### 01-01 [P2] defect status=partial ws=WS2
LOC: Repo-wide: **442** inline empty `catch` bodies in `lib/` (counted with a multiline-aware regex over all 343 files)
SYMPTOM: Failures vanish without a trace. The user sees a feature silently do nothing, and crash reporting never sees it either Ã¢â‚¬â€ a class of bugs that can only surface as "sometimes it doesn't work".
CAUSE: Empty catch blocks used as a blanket "don't crash" idiom. Representative example: `equalizer_manager.dart:1189`.
FIX: Ban empty catches via a lint/CI check; require at least `ErrorLogger.log` in the block.

### 01-02 [P3] defect status=open ws=WS2
LOC: `analysis_options.yaml` (only `package:flutter_lints/flutter.yaml`, no additional rules) together with **501** `// ignore:` suppressions in `lib/`
SYMPTOM: The static-analysis bar is the default Flutter set, and suppressions are pervasive, so `flutter analyze` clean does not imply much. Several findings in this audit (dead code, unwired controls) are exactly the class such rules would catch.
CAUSE: Default lint configuration.
FIX: Enable a stricter rule set and add a CI budget that fails on new `ignore` comments.

### 01-03 [P2] defect status=open ws=WS2
LOC: `lib/core/errors/failures.dart` (1,606 B) vs `lib/core/errors/ytm_error_classifier.dart` (22,227 B)
SYMPTOM: Error taxonomy is lopsided: the online path has a thorough 22 KB classifier while the shared failure model is ~1.6 KB, so local failures are mostly untyped and unactionable.
CAUSE: The shared failure model was never grown to match the online one.
FIX: Extend the shared failure taxonomy and migrate the 442 swallowing sites onto it.

## Area 2
### 02-01 [P2] defect status=open ws=WS2
LOC: `media_scanner_service.dart:69Ã¢â‚¬â€œ70` (`if (storageCurrent.isPermanentlyDenied) return false;` / `if (audioStatus.isPermanentlyDenied) return false;`) vs `onboarding_screen.dart:55` (`openAppSettings()` offered only for the notification permission)
SYMPTOM: A user who permanently denies the audio/storage permission gets a non-functional library with no in-app route to Settings, while the notification denial does get one. The app can look broken rather than blocked.
CAUSE: The denial fallback exists in the permission layer but the recovery affordance was only built for notifications.
FIX: On any permanently-denied media permission, show an explanatory state with an `openAppSettings()` action.

### 02-02 [P3] defect status=open ws=WS2
LOC: `onboarding_screen.dart:44` (notification request) and `player_cubit.dart:855` (notification status check)
SYMPTOM: A user can be asked about notifications twice on the same session.
CAUSE: Two independent call sites own the same permission.
FIX: Centralise notification permission ownership.

### 02-03 [P2] defect status=open ws=WS2
LOC: `main.dart:104Ã¢â‚¬â€œ120` (`SharedPreferences` then `Future.wait([...])`, `AuthService().initialize()Ã¢â‚¬Â¦timeout(8s)Ã¢â‚¬Â¦catchError`)
SYMPTOM: The claim that Pure builds perform **zero** network work at startup is asserted in comments but was not verified against the actual gating in the initialiser list; if any initialiser is not flag-gated, a Pure build would still do online work.
CAUSE: Verification requires following each initialiser's own flag check, which was not done for all of them in this audit.
FIX: Add a startup test that asserts no network initialiser runs in the Pure configuration.

### 02-04 [P3] defect status=open ws=WS2
LOC: `main.dart:164` and `main.dart:169` (two `runApp` call sites)
SYMPTOM: Two launch paths exist (Sentry-initialised vs not). They are almost certainly mutually exclusive, but the duplication is a drift hazard: a change applied to one is easy to miss in the other.
CAUSE: Branching duplicated the whole app construction.
FIX: Extract the common construction into a helper.

## Area 3
### 03-01 [P3] defect status=open ws=WS4
LOC: `lib/core/router/app_router.dart` (3 hardcoded literal hits), including the error page area claimed fixed as F-04
SYMPTOM: Some router strings bypass l10n even though the spec records the router error page as localised; ES/AR users may still see English on router-generated surfaces.
CAUSE: Inline literals alongside localised ones in the same file.
FIX: Move the remaining literals to ARB keys.

### 03-02 [P2] defect status=open ws=WS4
LOC: `app_router.dart` Ã¢â‚¬â€ route `/cloud-backup-dashboard` exists while `docs/PULSR_FEATURES_SPEC.md` records cloud backup as **SKIPPED** (F-49)
SYMPTOM: A user could navigate to a route whose feature was intentionally not implemented, or the route is dead code.
CAUSE: Route retained after the feature was scoped out.
FIX: Either remove the route or implement/clearly label the destination.

### 03-03 [P2] defect status=open ws=WS4
LOC: `app_router.dart` (34 flat top-level routes) + `lib/features/shell/**`
SYMPTOM: Back-stack and deep-link behaviour across 34 flat routes was not exercised; flat route tables of this size commonly produce inconsistent back behaviour (a deep link landing mid-stack).
CAUSE: No visible nesting/redirect strategy in the inspected route list.
FIX: Add redirect/back-stack assertions and a route-level test per deep link.

## Area 4
### 04-01 [P2] defect status=open ws=WS4
LOC: `home_screen.dart` (57,134 B, single widget) with independently streamed sections at `:471Ã¢â‚¬â€œ600` and `:669Ã¢â‚¬â€œ700`
SYMPTOM: A single emission from any one source (settings, songs, YTM) rebuilds the entire dashboard tree. On a large library with several active sections this is a plausible source of jank on low-end hardware.
CAUSE: All sections are built inline in one widget instead of isolated `BlocBuilder`/`StreamBuilder` subtrees.
FIX: Extract each section into its own widget with a narrow builder.

### 04-02 [P3] defect status=open ws=WS4
LOC: `lib/features/home/presentation/home_screen.dart` (3 hardcoded literal hits)
SYMPTOM: Some home strings are English-only in an app claiming full EN/ES/AR support, while adjacent headers are localised (e.g. `:549` uses `context.l10n.recentlyAdded`).
CAUSE: Mixed authoring.
FIX: Move remaining literals to ARB keys.

### 04-03 [P3] defect status=open ws=WS4
LOC: `home_screen.dart:501Ã¢â‚¬â€œ520` (quick actions build `shuffled` / `top` lists before playing)
SYMPTOM: "Shuffle all" and "Top played" materialise their list on the UI thread before playback starts; on a 10k-track library the tap can take a visible moment.
CAUSE: The lists are built in the button handler.
FIX: Precompute lazily or move the shuffle to the queue layer.

## Area 5
### 05-01 [P2] defect status=partial ws=WS2
LOC: `app_database.dart:253Ã¢â‚¬â€œ258` (`INSERT INTO songs_fts(songs_fts) VALUES('rebuild')` wrapped in a try that only `print`s)
SYMPTOM: If the FTS rebuild fails, search silently returns incomplete results: the library looks intact but tracks become unfindable, with no error shown and nothing in telemetry.
CAUSE: Failure is written to stdout only.
FIX: Route through the error logger, set a user-visible "search index needs rebuild" state, and offer a retry action.

### 05-02 [P3] defect status=open ws=WS2
LOC: `media_scanner_service.dart:158Ã¢â‚¬â€œ159` (`if (_nomediaDirCache.length >= _nomediaCacheMax) { _nomediaDirCache.clear(); }`)
SYMPTOM: When the `.nomedia` cache exceeds 2,000 directories it is flushed wholesale rather than evicted by recency, so previously resolved directories are re-`stat`ed, causing avoidable I/O on very large trees.
CAUSE: Coarse cache eviction.
FIX: Use LRU eviction (the codebase already uses an LRU pattern in `SearchCubit`).

### 05-03 [P2] defect status=open ws=WS2
LOC: `README.md` claim: "*scanning and indexing 10,000+ local tracks in under 2 seconds*"
SYMPTOM: Users/reviewers are promised a specific performance figure that no evidence in the repository supports. If it is wrong, the feature is judged harshly; if it is right, it is not defended.
CAUSE: Marketing claim without a benchmark or test that asserts it.
FIX: Add a benchmark test on a synthetic 10k library, or soften the claim.

### 05-04 [P3] defect status=open ws=WS2
LOC: `media_scanner_service.dart:69Ã¢â‚¬â€œ70` (permanent denial Ã¢â€ â€™ `return false`)
SYMPTOM: Same root cause as 02-01: the scanner reports a bare `false` with no reason, so the caller cannot distinguish "denied" from "no files".
CAUSE: Boolean-returning API.
FIX: Return a typed result (denied / no-permission / empty / scanned).

## Area 6
### 06-01 [P2] defect status=open ws=WS4
LOC: `library_cubit.dart:449Ã¢â‚¬â€œ467` (`selectAllSongs` Ã¢â€ â€™ `watchAllSongs(limit: null, Ã¢â‚¬Â¦)`)
SYMPTOM: "Select all" resolves the entire library into memory and into the selection set. On a 10k+ track library this is a large allocation and a long selection operation, with no progress feedback.
CAUSE: The fix for the historical cap replaced a bounded window with an unbounded fetch.
FIX: Use an "everything" selection token instead of materialising ids, or batch the selection with progress.

### 06-02 [P2] defect status=open ws=WS4
LOC: `library_screen.dart` (89,598 B, one file, six tabs)
SYMPTOM: All six tabs live in one widget file; an emission that concerns one tab can rebuild others, and the file is beyond practical review size.
CAUSE: No splitting into per-tab widgets/blocs.
FIX: Split per tab; isolate rebuild scope.

### 06-03 [P3] defect status=open ws=WS4
LOC: `library_screen.dart` (4 literal hits), `recents_screen.dart` (5 literal hits)
SYMPTOM: Library strings remain English-only in places.
CAUSE: Inline literals.
FIX: Move to ARB keys.

## Area 7
### 07-01 [P3] defect status=open ws=WS3
LOC: `album_detail_screen.dart:201,209,217`; `artist_detail_screen.dart:300,306`; `genre_detail_screen.dart:64,72,80,184`; `year_detail_screen.dart:63,71,79,151,168,184`; `folder_detail_screen.dart:64,77,78,100,109,117,249`
SYMPTOM: Spanish and Arabic users see English text on error and empty states ("Could not load album songs", "Retry", "No tracks found in this genre.").
CAUSE: Strings are inline literals instead of `context.l10n.*`, while sibling strings in the same files *are* localised (e.g. `album_detail_screen.dart` uses `context.l10n.playAll` at line 133).
FIX: Move all 22 literals into `app_en/es/ar.arb` and reference via `context.l10n`.

### 07-02 [P2] defect status=open ws=WS3
LOC: `music_repository.dart:797Ã¢â‚¬â€œ800` orders by `discNumber`; `album_detail_screen.dart:160Ã¢â‚¬â€œ175` and `:178` render one flat list
SYMPTOM: Multi-disc albums show a single flat track list with a continuous index; the disc structure is invisible although the query already sorts by disc.
CAUSE: The ordering exists in the data layer but the presentation layer never groups by `discNumber`.
FIX: Insert disc header slivers when `discNumber` changes between adjacent rows.

### 07-03 [P2] defect status=open ws=WS3
LOC: `album_detail_screen.dart:120Ã¢â‚¬â€œ156` (header actions), `artist_detail_screen.dart:251Ã¢â‚¬â€œ253`, `genre_detail_screen.dart:147Ã¢â‚¬â€œ197`, `year_detail_screen.dart:147Ã¢â‚¬â€œ195`
SYMPTOM: There is no album/artist/genre/year-level "Add to queue", "Play next" or "Add to playlist"; those actions exist only perSong through `SongInfoSheet`.
CAUSE: Header exposes only Play All + Shuffle; no overflow menu was built.
FIX: Add an overflow `PopupMenuButton` to the header with queue/playlist targets.

### 07-04 [P2] defect status=open ws=WS3
LOC: `.openclaw/tmp/audit_flutter_test.log` (perf harness block); `genre_detail_screen.dart:51` stream-per-build
SYMPTOM: Genre detail rebuild/scroll cost is the highest in the repo's own harness (`first_build 212,252 Ã‚Âµs`, scroll avg `235,536 Ã‚Âµs`, p95 `294,645 Ã‚Âµs`). Users on low-end devices may see janky scrolling in large genres.
CAUSE: `watchGenreSongs` copies the whole list on every emit; the screen rebuilds a full `ListView` each time. Not reproduced on a device.
FIX: Profile on a real device; consider `ListView.builder` with `const` header extraction + `ValueListenableBuilder` for the playing row only.

### 07-05 [P3] defect status=open ws=WS3
LOC: `year_detail_screen.dart:151,168` vs `album_detail_screen.dart:133,142`
SYMPTOM: The same two controls are localised in the album screen and hardcoded in the year screen.
CAUSE: Inconsistent authoring across sibling screens.
FIX: Normalise on `context.l10n.playAll` / `context.l10n.shuffle`.

## Area 8
### 08-03 [P3] defect status=open ws=WS1
LOC: `search_cubit.dart:159` (`errorMessage: 'Search failed'`)
SYMPTOM: The search failure message is English-only in an app claiming full EN/ES/AR localisation.
CAUSE: Inline literal instead of `context.l10n` (the cubit has no context; needs a code/state key translated in the UI).
FIX: Emit an error code in state and translate at render time.

### 08-05 [P2] defect status=open ws=WS1
LOC: `search_cubit.dart:116Ã¢â‚¬â€œ138` (fallback calls `searchSongs('')` then `_filterWithFuzzy(allSongs, Ã¢â‚¬Â¦)`)
SYMPTOM: On a 10k+ track library, a query that strictly matches nothing triggers a full-library materialisation plus Levenshtein over every row **on the UI isolate**; typing a typo in a large library can visibly stall.
CAUSE: The fallback deliberately removed the previous 300-row window ("fuzzy matching must not miss valid typo/variant matches") without moving the work off the UI isolate.
FIX: Move the fallback into a `compute`/isolate, or keep a cheap first-pass filter (e.g. first-letter or trigram) before Levenshtein.

### 08-06 [P3] defect status=open ws=WS1
LOC: `search_cubit.dart:60Ã¢â‚¬â€œ63` (`void clearHistory() async`)
SYMPTOM: `async void` on a public API: an exception inside the `try` is caught, but the method cannot be awaited by callers, and the state emit happens after an unawaited gap.
CAUSE: Dart idiom slip.
FIX: Return `Future<void>`.

## Area 9
### 09-01 [P3] defect status=open ws=WS4
LOC: `lib/features/playlists/presentation/playlists_screen.dart` (22 literal hits), `playlist_detail_screen.dart` (11 hits)
SYMPTOM: The playlists surface is largely English-only for ES/AR users, including action labels.
CAUSE: Inline literals in the two largest playlist files.
FIX: Extract to ARB keys.

### 09-02 [P2] defect status=open ws=WS4
LOC: `playlist_share_service.dart:65,84` (export Ã¢â€ â€™ import round-trip) and `playlist_detail_screen.dart:134Ã¢â‚¬â€œ145`
SYMPTOM: A shared playlist bundle is validated by re-importing it in-process before sharing (`:139`). If the import path is stricter than the export path (e.g. differing JSON key casing or version handling), sharing can silently refuse to share without explaining why.
CAUSE: Self-validation gate without distinct failure messaging.
FIX: Surface the specific validation failure to the user.

### 09-03 [P2] defect status=open ws=WS4
LOC: `playlist_io_usecases.dart:100Ã¢â‚¬â€œ103,223` (single-format export via `PlaylistFormat.m3u`)
SYMPTOM: `.m3u` round-trip fidelity (absolute vs relative paths, extended `#EXTINF`, non-ASCII filenames, `.m3u8` encoding) is not verified; a lossy round trip silently reorders or drops tracks.
CAUSE: Export format handling was read but not executed.
FIX: Add round-trip tests with non-ASCII paths and relative/absolute mixes.

### 09-04 [P2] defect status=open ws=WS4
LOC: `smart_playlist_engine.dart` (24,491 B; `case '` sites indicate ~7 rule families)
SYMPTOM: The smart-rule engine's behaviour on missing metadata (null BPM, null year, null rating) is not verified; rules may silently exclude rows the user expects to match.
CAUSE: Rule evaluation for null operands was not traced.
FIX: Define and test null semantics per rule type.

## Area 10
### 10-01 [P2] defect status=open ws=WS4
LOC: `music_repository.dart:1230Ã¢â‚¬â€œ1253` (`saveQueue` Ã¢â€ â€™ `queue_items`) **and** `player_cubit.dart:275Ã¢â‚¬â€œ281, 547Ã¢â‚¬â€œ580, 590Ã¢â‚¬â€œ671` (`queue_slots_v1` in SharedPreferences)
SYMPTOM: Two systems persist "the queue". If they diverge (e.g. one is written on pause and the other on slot switch), the queue the user sees after a restart may not be the queue they left, and the stale copy silently wins on one path.
CAUSE: Independent persistence introduced at different times without a single owner.
FIX: Make one store authoritative; derive the other, or delete the unused one.

### 10-02 [P2] defect status=open ws=WS4
LOC: `music_repository.dart:1234Ã¢â‚¬â€œ1247`
SYMPTOM: On a long queue (thousands of items), every save deletes and re-inserts the whole table inside a transaction, so each queue change rewrites everything Ã¢â‚¬â€ a latency and battery cost while playing.
CAUSE: Full-table rewrite instead of incremental diffing.
FIX: Diff against the previous state and apply inserts/deletes/moves only.

### 10-03 [P3] defect status=open ws=WS4
LOC: `queue_screen.dart:79,87,97,98,100`
SYMPTOM: Five queue strings are English-only: "Failed to save playlist: Ã¢â‚¬Â¦", "Saved "Ã¢â‚¬Â¦" with N tracks", "Shuffle queue", "Save as playlist", "Clear queue".
CAUSE: Inline literals next to localised headers (`:30,45,119Ã¢â‚¬â€œ121`).
FIX: Move to ARB keys.

### 10-04 [P3] defect status=open ws=WS4
LOC: `queue_screen.dart:141` (`// ignore: deprecated_member_use` on the reorder callback)
SYMPTOM: The screen keeps the deprecated `onReorder` API with a suppression comment, so it will break on a future Flutter upgrade and it adds to the repo-wide suppression debt.
CAUSE: Compatibility trade-off for the stable channel.
FIX: Migrate to `onReorderItem` once the minimum Flutter version allows it.

### 10-05 [P3] defect status=open ws=WS4
LOC: `queue_screen.dart:110Ã¢â‚¬â€œ160`
SYMPTOM: Clearing the queue and removing items are destructive with no undo, and the clear action is a single tap in the overflow menu.
CAUSE: No undo affordance.
FIX: Add an undo snackbar for clear/remove.

## Area 11
### 11-01 [P2] defect status=open ws=WS1
LOC: `audio_handler.dart:168Ã¢â‚¬â€œ170` (`_lastGaplessChangeTime`, `_rapidGaplessChangeCount`), `:246Ã¢â‚¬â€œ255` (`_gaplessLoaded`, `_lastGaplessIndex`, `_gaplessTargetIndex`, `_gaplessTargetReached`)
SYMPTOM: Gapless transitions may occasionally play the wrong track, skip a track, or stutter, because the code defensively filters transient ExoPlayer index emissions with timers and counters rather than relying on a single source of truth for "which index is really playing".
CAUSE: Multiple overlapping guards around the same signal indicate the underlying race was worked around rather than removed.
FIX: Introduce one authoritative "current index" derived from the player plus an explicit state machine, and delete the counters.

### 11-02 [P2] defect status=open ws=WS1
LOC: `audio_handler.dart:579Ã¢â‚¬â€œ611` (`_calculateReplayGainVolume`) and `:656Ã¢â‚¬â€œ660` (`_pushNativeReplayGain`)
SYMPTOM: ReplayGain is applied in the player-side mixer **and** pushed to a native pre-gain stage (commented as "single-stage mode"). If any configuration reaches both paths, loudness would be applied twice (tracks quieter/louder than intended) Ã¢â‚¬â€ the same class of defect as 13-01.
CAUSE: Two application sites for one gain stage.
FIX: Assert single-stage application with a test and remove the redundant path.

### 11-03 [P2] defect status=open ws=WS1
LOC: `audio_handler.dart:591`
SYMPTOM: ReplayGain is intentionally bypassed under strict bit-perfect Ã¢â‚¬â€ correct behaviour, but it changes loudness with no visible indication on the transport.
CAUSE: Exclusivity rule enforced in code only.
FIX: Surface the active exclusivity (a badge in the quality sheet/DSP inspector).

### 11-04 [P3] defect status=open ws=WS1
LOC: `audio_handler.dart` (spans 223 KB / ~5,000+ lines)
SYMPTOM: The single largest file in the app owns transport, gapless, crossfade, ReplayGain, queues, media session and more; the bug surface for transport changes is very wide.
CAUSE: God-object growth.
FIX: Extract the transport/gapless and ReplayGain concerns into collaborators.

## Area 12
### 12-01 [P2] defect status=open ws=WS3
LOC: The eight theme files (29.6Ã¢â‚¬â€œ52.0 KB each; five declare their own `State` with animation controllers)
SYMPTOM: Behavioural fixes and accessibility improvements must be applied eight times. A fix landed in one theme silently does not reach the others, so themes drift apart in behaviour even when they look consistent.
CAUSE: Shared chrome exists, but control/animation logic is duplicated per theme.
FIX: Extract the common control/animation surface into `player_theme_chrome.dart` so a theme only supplies visuals.

### 12-02 [P3] defect status=open ws=WS3
LOC: `custom_theme_builder_screen.dart` (4 literal hits)
SYMPTOM: The custom theme studio is partially English-only; a user building a theme in ES/AR sees mixed language.
CAUSE: Inline literals.
FIX: Move to ARB keys.

### 12-03 [P2] defect status=open ws=WS3
LOC: `prefs_keys.dart:28` (`playerThemeMode`) Ã¢â‚¬â€ the selection plumbing to the theme widgets was not traced
SYMPTOM: If theme selection is persisted but a theme's own state is not restored/rebuilt on switch, switching themes mid-playback can produce a stale or duplicated control state.
CAUSE: Not verified.
FIX: Add a widget test that switches all 8 themes while playing.

## Area 13
### 13-03 [P3] defect status=open ws=WS1
LOC: `lib/features/player/presentation/widgets/equalizer_sheet.dart` (77 literals)
SYMPTOM: The EQ sheet is entirely English regardless of the selected EN/ES/AR locale.
CAUSE: Inline literals instead of ARB keys.
FIX: Extract to `app_en/es/ar.arb`.

### 13-04 [P3] defect status=open ws=WS1
LOC: `lib/features/player/presentation/widgets/dsp_inspector_sheet.dart:612` (`'ACTIVE'` / `'OFF'`)
SYMPTOM: The inspector Ã¢â‚¬â€ the surface whose purpose is honest reporting Ã¢â‚¬â€ reports its own status in English only.
CAUSE: Inline literal.
FIX: Localise the status labels along with the stage names.

## Area 14
### 14-01 [P2] defect status=open ws=WS1
LOC: `audio_handler.dart:2076Ã¢â‚¬â€œ2079` (`DsdDecoderHelper.probeDopCapabilities()` / `decodeDsdFile`), `dsd_decoder_helper.dart:187,206` (`DopEncoder.dopPcmSampleRate` / `encodeToDopPcm24`) vs `docs/PULSR_FEATURES_SPEC.md` row **F-41** ("encoder left dormant")
SYMPTOM: Documentation and code disagree about whether DSD/DoP is live. A reviewer trusting the spec will believe the capability is disabled; the code calls it. Any user-facing copy derived from the spec is therefore inaccurate.
CAUSE: The remediation pass recorded DoP as "HONEST / dormant" while a later commit wired `DsdDecoderHelper` into the audio handler.
FIX: Re-audit the DoP path and correct the spec + any UI copy to the real state.

### 14-02 [P2] defect status=open ws=WS1
LOC: `mqa_decoder_helper.dart:15` (`mqaSyncWord = 0xbe0498c4`), `:84` (13-tap spline interpolation described as unfold), wired at `format_aware_decoder.dart:47Ã¢â‚¬â€œ51`
SYMPTOM: The UI can report an MQA track as detected/unfolded based on a Dart-layer synchronisation-word sniff plus interpolation, which is not equivalent to an MQA-licensed renderer and cannot authenticate the stream. Users may believe they are hearing a certified MQA decode.
CAUSE: The capability is implemented as a best-effort heuristic but described in docs/UI terms reserved for the licensed pipeline.
FIX: Either label the result explicitly as "MQA detected (approximate)", or remove the reporting until the real path exists.

### 14-03 [P2] defect status=open ws=WS1
LOC: `audio_handler.dart:1752Ã¢â‚¬â€œ1753` (`unawaited(MqaDecoderHelper.isMqaFile(song.path).then(...))`)
SYMPTOM: If the file read fails or the path disappears, the future's error is unobserved; no user feedback and no telemetry Ã¢â‚¬â€ the track simply plays without the expected badge.
CAUSE: Fire-and-forget async call on a file I/O path.
FIX: Attach `.catchError` and log; or route through the existing error pipeline.

### 14-04 [P3] defect status=open ws=WS1
LOC: `lib/features/settings/presentation/widgets/audio_sound_section.dart` (7 literals), `lib/features/player/presentation/widgets/audio_quality_sheet.dart`
SYMPTOM: The hi-res/bit-perfect settings surface carries hardcoded English literals while sibling strings are localised.
CAUSE: Inline literals.
FIX: Move to ARB keys.

## Area 15
### 15-01 [P3] defect status=open ws=WS2
LOC: `lyrics_view.dart:231,232,260,262,388,411,424`
SYMPTOM: The lyrics surface is English-only: "Lyrics saved", "Lyrics updated for this session only", "Edit lyrics", "Karaoke mode", "No lyrics found", the `.lrc` guidance text and "Search Lyrics".
CAUSE: Inline literals in a UI layer that otherwise uses `context.l10n`.
FIX: Move all seven to ARB keys (en/es/ar).

### 15-02 [P2] defect status=open ws=WS2
LOC: `player_cubit.dart:1473` (comment) and `:1521Ã¢â‚¬â€œ1560` (LRCLIB fetch)
SYMPTOM: If the LRCLIB lookup runs on the play path, starting a track on a slow network can delay lyric display by up to the fetch timeout, with no visual progress state.
CAUSE: The comment records that the pipeline avoids an "embedded reads plus a 5 s LRCLIB round-trip on every play", implying the round-trip exists on that path; the timeout value was not confirmed.
FIX: Ensure the network lookup is strictly post-playback and surface a "fetching lyrics" state.

### 15-03 [P3] defect status=open ws=WS2
LOC: `player_cubit.dart:1663Ã¢â‚¬â€œ1672`
SYMPTOM: Editing lyrics on a track whose folder is not app-writable fails silently: the user sees a success path while nothing is persisted.
CAUSE: The sidecar write failure is only passed to `ErrorLogger`; no failure state reaches the UI (`'Lyrics saved'` vs the session-only branch is decided before the write result is known at `lyrics_view.dart:231`).
FIX: Return a success/failure result from the persist call and branch the toast on it.

## Area 16
### 16-01 [P2] defect status=open ws=WS2
LOC: `audio_visualizer.dart:86,104,163,343` (`ui.FragmentProgram.fromAsset('shaders/milkdrop.frag')`, `_milkShader != null` branch)
SYMPTOM: If the shader fails to compile (e.g. an Impeller/GPU difference on a specific device), the MilkDrop style silently degrades to a `CustomPainter` fallback; the user believes they are seeing MilkDrop.
CAUSE: Load failure is caught and the code branches on `_milkShader != null` without surfacing the degradation.
FIX: Surface a visible "GPU visualiser unavailable" state, and log the compile failure.

### 16-02 [P2] defect status=open ws=WS2
LOC: `audio_visualizer.dart:196Ã¢â‚¬â€œ198` (`Permission.microphone.status` / `.request()`), README claim of a "synthetic waveform" denial fallback
SYMPTOM: When microphone access is denied, what the user actually sees is not confirmed in code review; the README's denial-fallback claim is unverified.
CAUSE: The permission is requested but the concrete denial branch was not traced to a data source.
FIX: Confirm and document the denial path; ensure visuals remain animated (or explain the degraded state).

### 16-03 [P2] defect status=open ws=WS2
LOC: `audio_visualizer.dart:367Ã¢â‚¬â€œ680` (six `CustomPainter`s) and `:841` (`_MilkdropGpuPainter`)
SYMPTOM: Continuous per-frame repaint of full-screen painters alongside audio playback is a plausible source of battery drain and dropped frames on low-end devices.
CAUSE: No frame-budget gate or adaptive quality reduction is visible in this file.
FIX: Add an adaptive quality/frame-rate cap and measure with the repo's existing perf harness.

### 16-04 [P3] defect status=open ws=WS2
LOC: `audio_visualizer.dart:258` (`widget.trackSeed ?? widget.audioSessionId ?? 0`)
SYMPTOM: Falling back to `audioSessionId` means two different tracks can share a seed (the audio session id is stable across tracks), producing visuals that do not change as intended between songs.
CAUSE: The seed is only distinct when a caller supplies `trackSeed`.
FIX: Derive the fallback seed from the track identity rather than the session id.

## Area 17
### 17-01 [P2] defect status=open ws=WS2
LOC: `docs/AUDIO_INTERRUPT_MATRIX.md` (declared matrix) vs `interruption_state_machine.dart` (pure, testable logic)
SYMPTOM: The project documents an interruption matrix but the matrix was not executed in this audit and no evidence of an automated version was found; the area's real-world correctness therefore rests on untested claims.
CAUSE: Documentation-first verification.
FIX: Encode the matrix as executable tests against the pure state machine (it is already pure and trivially testable).

### 17-02 [P3] defect status=open ws=WS2
LOC: `audio_session_id_router.dart:50,64,81,84,102,105,122,125` (eight log calls on the session-change path)
SYMPTOM: Every session/route emission writes log lines. On a route-flapping device (BT renegotiation) this is log churn in a hot path.
CAUSE: Verbose debug-level logging in production code.
FIX: Gate on debug builds or use a sampled logger.

### 17-03 [P3] defect status=open ws=WS2
LOC: `ducking_controller.dart` (1,728 B) and `multi_output_router.dart` (1,902 B)
SYMPTOM: Both collaborators are extremely thin for the behaviour they imply; the substantive logic likely lives in `audio_handler.dart`, which contradicts the separation this area appears to have.
CAUSE: Partial extraction.
FIX: Move the remaining logic into these collaborators so the boundary is real.

## Area 18
### 18-01 [P3] defect status=open ws=WS4
LOC: `sleep_timer_manager.dart:28,31` (`_isFadeOutEnabled = true`, `_preFadeVolume`)
SYMPTOM: Fade-out defaults to on and tracks a pre-fade volume. If the process is killed mid-fade, the "restore" value lives only in memory; on restart the volume comes from the player's own state, so this is benign Ã¢â‚¬â€ but the intent is worth an explicit comment/test.
CAUSE: Volatile state for a user-visible audio property.
FIX: Add a regression test for interruption-during-fade.

### 18-02 [P2] defect status=open ws=WS4
LOC: `sleep_timer_manager.dart` (ticker + one-shot timer) and `audio_handler.dart:170` (track-completion reporting for the timer)
SYMPTOM: Because gapless playback complicates track-completion detection (see 11-01), `endOfTrack` / `afterNTracks` modes depend on that same signal and may fire one track early or late during seamless transitions.
CAUSE: Dependency on the gapless completion signal.
FIX: Drive the count from the same authoritative index source recommended in 11-01.

## Area 19
### 19-01 [P3] defect status=open ws=WS3
LOC: `app_colors.dart:38Ã¢â‚¬â€œ44` (`// AMOLED (legacy)` constants: `amoledBackground`, `amoledSurface`, `amoledCard`, `amoledTextPrimary`, `amoledTextSecondary`, `amoledOutline`)
SYMPTOM: Two competing sources of truth for AMOLED colours; a change applied to the new theme factory will not reach the legacy constants, and vice versa.
CAUSE: Legacy constants retained after the AMOLED theme was moved into `aura_theme.dart:133`.
FIX: Delete the legacy constants once no call site remains.

### 19-02 [P2] defect status=open ws=WS3
LOC: `theme_scheduler_service.dart` + `injection.config.dart:141Ã¢â‚¬â€œ142`
SYMPTOM: The scheduler exists and is registered, but whether it is actually started and consumed on the appearance toggle (the spec's F-47 claim) was not verified. If it is registered but never started, the "automatic light/dark by time of day" feature is inert.
CAUSE: Registration and wiring are different things.
FIX: Trace start/consume; add a test that the theme changes at the scheduled boundary.

### 19-03 [P3] defect status=open ws=WS3
LOC: `aura_theme.dart:133Ã¢â‚¬â€œ136` (`amoledTheme`, `highContrastTheme`)
SYMPTOM: The high-contrast theme reuses the AMOLED background (`isAmoled: true`) with a cyan accent; contrast of the secondary text (`#A0A0A0`) on `#000000` meets the usual ratio, but the accessibility variant is not distinguished by more than accent + AMOLED background, which may not be a meaningful accessibility improvement.
CAUSE: High-contrast implemented as a variant rather than a distinct token set.
FIX: Validate against WCAG AA/AAA for every token pair and adjust.

## Area 20
### 20-01 [P2] defect status=open ws=WS2
LOC: `settings_cubit.dart` (81,061 B) + `settings_state.freezed.dart` (122,308 B) + **175** preference keys in `prefs_keys.dart`
SYMPTOM: With this many keys behind one state object, some toggles are very likely inert or only partially wired (persisted but not read on the path they claim to affect). A user flips a switch, it stays flipped, and nothing changes Ã¢â‚¬â€ the worst kind of settings bug because it looks like it worked.
CAUSE: Unbounded growth of a single settings state without per-key wiring tests.
FIX: Add a wiring test per preference key: flip it, assert the consuming subsystem observed the change.

### 20-02 [P3] defect status=open ws=WS2
LOC: `proxy_settings_screen.dart` (15 literals), `backup_section.dart` (9), `audio_sound_section.dart` (7), `cast_section.dart` (4), `settings_picker_sheets.dart` (3)
SYMPTOM: 38 hardcoded English literals across the settings surface Ã¢â‚¬â€ the largest concentration outside the EQ sheet.
CAUSE: Inline literals.
FIX: Move to ARB keys.

### 20-03 [P2] defect status=open ws=WS2
LOC: `cloud_backup_dashboard_screen.dart` (6,020 B) exists, reachable via `/cloud-backup-dashboard`, while `docs/PULSR_FEATURES_SPEC.md` records cloud backup as **SKIPPED** (F-49, F-56)
SYMPTOM: A user can reach a cloud-backup dashboard for a feature that is declared out of scope, producing an inconsistent product story between code and documentation.
CAUSE: Route + screen retained after the feature was descoped.
FIX: Decide: remove, or make the screen explicitly say the feature is unavailable in this build.

### 20-04 [P3] defect status=open ws=WS2
LOC: `experience_mode_section.dart` (1,920 B)
SYMPTOM: A 1.9 KB file carries a mode that claims to switch the whole settings surface between "curated" and "professional". A section that changes this much is implausibly small, suggesting the flag drives gates elsewhere and the section is a thin toggle.
CAUSE: Likely intentional, but the coupling is hidden.
FIX: Document and test which controls each mode gates.

## Area 21
### 21-01 [P2] defect status=open ws=WS3
LOC: `ytm_web_login_sheet.dart` (101,601 B Ã¢â‚¬â€ the largest non-generated UI file in the app)
SYMPTOM: A single 100 KB login sheet is effectively unreviewable and a maintenance sink; regressions hide easily.
CAUSE: Web-login flow built as one widget.
FIX: Split into steps/widgets; add integration tests for the login state machine.

### 21-02 [P2] defect status=open ws=WS3
LOC: `app_config.dart:77Ã¢â‚¬â€œ82` (mismatch messaging)
SYMPTOM: The flavour/define mismatch guard produces its message through a debug-oriented path, so a release build configured with the native bridge but without the Dart gate (or vice versa) can ship a build with a dead bridge or broken YTM UI rather than failing loudly.
CAUSE: Validation expressed as a development assertion rather than a user-visible build state.
FIX: Surface the mismatch in-app and fail the release build.

### 21-03 [P3] defect status=open ws=WS3
LOC: `ytm_web_login_sheet.dart` (13 literals), `settings/.../ytm_account_disconnect_dialog.dart`
SYMPTOM: The online surfaces remain English-only, including account disconnection.
CAUSE: Inline literals.
FIX: Move to ARB keys.

### 21-04 [P2] defect status=open ws=WS3
LOC: `ytm_oauth_login_sheet.dart` (11,201 B) **and** `ytm_web_login_sheet.dart` (101,601 B)
SYMPTOM: Two parallel login implementations double the failure surface (token storage, refresh, disconnection) for the same account.
CAUSE: Two flows retained.
FIX: Consolidate on one, or clearly separate their scopes.

## Area 22
### 22-01 [P2] defect status=open ws=WS4
LOC: `lib/features/settings/presentation/cloud_backup_dashboard_screen.dart` + the `/cloud-backup-dashboard` route, vs spec rows F-49/F-56 ("SKIPPED Ã¢â‚¬â€ Firebase/cloud out of scope")
SYMPTOM: Code and documentation tell different stories: a dashboard screen and route ship for a feature the audit document says was deliberately not implemented. Whichever is true, one of them is wrong and users/reviewers will be misled.
CAUSE: Feature descoped in documentation but its surface retained in code.
FIX: Remove the surface, or implement and update the docs.

### 22-02 [P2] defect status=open ws=WS4
LOC: `main.dart:104Ã¢â‚¬â€œ120` (auth init with 8 s timeout and `catchError`) plus the Pure-mode skip claim
SYMPTOM: If the Pure-mode gate for auth/cloud initialisation is not airtight, a "100% offline, no account" build could still construct Firebase/cloud objects at startup. This is the same open question as 02-03 and is the most consequential item in this area because it touches the app's central privacy promise.
CAUSE: Claim verified in comments, not by test.
FIX: Add an automated assertion that no cloud initialiser runs in the Pure configuration.

### 22-04 [P3] defect status=open ws=WS4
LOC: `auth_sheet.dart` (16,586 B)
SYMPTOM: Sign-in messaging quality was not verifiable statically; note that this surface is a trust boundary where copy matters and where the app should be explicit about what is uploaded.
CAUSE: Ã¢â‚¬â€
FIX: Review copy against actual sync behaviour.

## Area 23
### 23-01 [P2] defect status=open ws=WS2
LOC: `scrobbler_service.dart:30Ã¢â‚¬â€œ33` (`keyLastFmApiKey`, `keyLastFmSecret`, `keyLastFmSessionKey` in `SharedPreferences`) **and** `:45Ã¢â‚¬â€œ47` (`lastfm_api_key_secure`, `lastfm_secret_secure`, `lastfm_session_key_secure` in secure storage)
SYMPTOM: Two credential stores exist for the same secrets. If the legacy `SharedPreferences` keys are still written anywhere, the API secret and session key sit in an unencrypted, device-readable store Ã¢â‚¬â€ a real privacy defect for an app whose headline promise is privacy.
CAUSE: Secure-storage migration appears to have been added without removing the legacy plaintext keys.
FIX: Remove the plaintext keys, migrate once, and add a test asserting the secret is never written to prefs.

### 23-02 [P2] defect status=open ws=WS2
LOC: `scrobbler_service.dart:81` (`_keyOfflineQueue`), `:395Ã¢â‚¬â€œ430` (queue read/write as JSON in prefs)
SYMPTOM: The offline queue is an unbounded JSON blob in `SharedPreferences`. A long offline period (or a permanently failing endpoint) grows it without limit, and a single malformed write can invalidate the whole queue.
CAUSE: Queue stored as one blob with no cap or per-entry durability.
FIX: Cap the queue (drop-oldest with a counter) and store it in the database.

### 23-03 [P3] defect status=open ws=WS2
LOC: `scrobbler_service.dart` (whole file is 30.7 KB in one class)
SYMPTOM: Credentials, queue, HTTP, stats and service rules live in one class, so a scrobbling bug has a wide blast radius.
CAUSE: God-service growth.
FIX: Split transport, queue and credential concerns.

### 23-04 [P3] defect status=open ws=WS2
LOC: `scrobbler_settings_modal.dart`, `scrobble_stats_screen.dart`
SYMPTOM: The scrobbling surfaces were not audited for l10n; several settings-side literals were already found in area 20.
CAUSE: Ã¢â‚¬â€
FIX: Include in the l10n sweep.

## Area 24
### 24-01 [P1] defect status=open-evidence-upgraded ws=WS1
LOC: `lib/features/tag_editor/tag_editor_cubit.dart:419,467` (channel call) and `android/app/src/main/kotlin/com/pulsr/music/TagEditorPlugin.kt:320` (`AudioFileIO.write`)
SYMPTOM: Tag edits rewrite the user's own audio file **in place** through the native `writeTags` channel. For path-based files there is no temp-file-and-rename swap, no backup and no post-write verification; only `content:` URIs are copied into a cache temp file first. An interrupted or failed write can leave metadata truncated on a file the app is the only copy of the edit for.
CAUSE: `AudioFileIO.write(audioFile)` mutates the original path and jaudiotagger offers no transactional guarantee.
FIX: Write to a sibling temp file and rename into place atomically; re-read the tag before reporting success. Impact not reproduced (no device write was performed).

### 24-02 [P2] defect status=open ws=WS1
LOC: `artwork_picker.dart` (4,936 B) and the claim of embedding art into **MP3, FLAC, M4A, OGG and WAV**
SYMPTOM: WAV has no standard tag/cover-art container. Claiming artwork embedding for WAV risks producing files whose "cover" other players cannot read, or appending data that some tools treat as corruption.
CAUSE: Format claim broader than the format supports.
FIX: Restrict the claim per container and tell the user when artwork cannot be embedded.

### 24-03 [P2] defect status=open ws=WS1
LOC: `tag_editor_cubit.dart` (write path)
SYMPTOM: On Android 11+ scoped storage, writes outside app-owned directories commonly fail. If the failure is not surfaced distinctly from a successful edit, the user believes tags were saved when they were not (the same failure shape as 15-03 in the lyrics editor).
CAUSE: Write-result handling not verified.
FIX: Return a typed write result and branch the UI on it.

### 24-04 [P3] defect status=open ws=WS1
LOC: `lib/features/sheets/song_info_sheet.dart` (12 literals)
SYMPTOM: The song-info surface adjacent to tag editing is partly English-only.
CAUSE: Inline literals.
FIX: Add to the l10n sweep.

## Area 25
### 25-01 [P2] defect status=open ws=WS2
LOC: `duplicate_finder_service.dart` (5,043 B) + `duplicate_finder_screen.dart` (14,176 B)
SYMPTOM: Duplicate resolution deletes files. No trash/undo/confirmation journal was found in the inspected surface. A mis-tap in a 200-item duplicate list is unrecoverable.
CAUSE: Destructive action without a safety net.
FIX: Move deletions to an app trash with restore, or require an explicit review list with counts.

### 25-02 [P2] defect status=open ws=WS2
LOC: `missing_artwork_service.dart` (5,874 B)
SYMPTOM: Backfilled artwork is referenced by remote URL (persisted per the spec's F-58). If a host changes or goes offline, albums lose artwork with no local fallback detectable at read time.
CAUSE: Remote-URL dependence.
FIX: Cache fetched artwork locally and fall back to a placeholder on failure.

### 25-03 [P2] defect status=open ws=WS2
LOC: `library_stats_screen.dart` (23,956 B)
SYMPTOM: Library statistics over a very large library can require full aggregation; the spec records an explicit fix (F-59) to load the full library for accurate totals Ã¢â‚¬â€ which is precisely the pattern that makes the stats screen expensive.
CAUSE: Correctness fix traded for a full-library load.
FIX: Precompute and persist aggregates, or compute in SQL.

### 25-04 [P3] defect status=open ws=WS2
LOC: `artwork_grid_screen.dart` (7,388 B)
SYMPTOM: The artwork wall is a small screen; whether it virtualises large libraries was not verified.
CAUSE: Ã¢â‚¬â€
FIX: Verify with a large library.

## Area 26
### 26-01 [P2] defect status=open ws=WS2
LOC: `player_cubit.dart:796,822` (throttled widget updates) and `widget_service.dart`
SYMPTOM: Because widget updates are throttled, a widget can show the previous track or a stale position until the next throttled tick Ã¢â‚¬â€ and if the process is killed while backgrounded, the widget can keep showing a stale track indefinitely with no reconciliation on next launch.
CAUSE: Throttle without a reset-on-launch refresh.
FIX: Force one widget refresh on launch/restore (the code already forces on specific events at `:415,999,1083,1254`, so this is a completeness check).

### 26-02 [P2] defect status=open ws=WS2
LOC: `cast_section.dart` (8,105 B) and the most recent commit (`feat(audio): implement DVC, USB exclusive streaming, and Cast support`)
SYMPTOM: Cast/Android Auto are claimed. A settings section and a commit message are not evidence that a media-browser/Auto service is registered; if only a settings surface exists, the capability is advertised beyond what ships.
CAUSE: Claim density exceeding verifiable integration.
FIX: Confirm Android Auto's `MediaBrowserService` registration and Cast receiver; otherwise adjust the claim.

### 26-03 [P3] defect status=open ws=WS2
LOC: `lib/core/services/file_intent_handler.dart` (4 literal hits)
SYMPTOM: Intent-handling strings are English-only, so a user opening a file from a file manager may see an English error.
CAUSE: Inline literals.
FIX: Add to the l10n sweep.

### 26-04 [P3] defect status=open ws=WS2
LOC: Home-widget and notification behaviour
SYMPTOM: Notification/widget interaction with queue changes, sleep timer and interruption states was not verified end to end; this is where most "widget shows the wrong thing" reports originate.
CAUSE: Not exercised.
FIX: Add a widget/notification state test against a scripted playback session.

## Area 27
### 27-01 [P3] defect status=open ws=WS2
LOC: `lib/core/services/device_profile_service.dart`, `hires_audio_service.dart`, `room_correction_service.dart` Ã¢â‚¬â€ each **64 B, a single `export` line**
SYMPTOM: These look like dead placeholder files but are actually deliberate re-export shims to `lib/domain/services/`. Recorded so the finding is not mis-read as dead code: **no defect**. The pattern is worth documenting in-repo, since it reads as dead code to anyone scanning file sizes.
CAUSE: Compatibility shim.
FIX: Add a comment or consolidate imports.

### 27-02 [P2] defect status=open ws=WS2
LOC: `automation_trigger_service.dart` (5,071 B)
SYMPTOM: Automation triggers exist, but whether the service actually subscribes to Bluetooth/headset connect events (rather than exposing an API nobody calls) was not verified. An unwired trigger service would make the whole automation section inert Ã¢â‚¬â€ the same failure pattern the project's own gap register recorded for other features (F-63).
CAUSE: Trigger subscription not traced.
FIX: Trace subscription to the platform event source and add a test.

### 27-03 [P2] defect status=open ws=WS2
LOC: `bluetooth_latency_calibrator.dart` (2,989 B), `earbud_optimization_service.dart` (5,636 B); spec row F-64 describes a "codec-derived estimate"
SYMPTOM: A codec-derived estimate is presented as calibration/optimisation. If the UI implies a measurement, users will trust a number that is only a lookup-table guess.
CAUSE: Estimate presented with measurement-grade framing.
FIX: Label it explicitly as an estimate, or measure via the mic path (which already exists for room correction).

## Area 28
### 28-01 [P2] defect status=open ws=WS3
LOC: **289** hardcoded user-facing literals across `lib/`, concentrated in: `player/presentation/widgets/equalizer_sheet.dart` (77), `playlists/presentation/playlists_screen.dart` (22), `settings/presentation/proxy_settings_screen.dart` (15), `auth/presentation/ytm_web_login_sheet.dart` (13), `smart_playlist_builder_screen.dart` (12), `sheets/song_info_sheet.dart` (12), `playlist_detail_screen.dart` (11), `settings/widgets/backup_section.dart` (9), `online_playlist_detail_screen.dart` (8), `settings/widgets/audio_sound_section.dart` (7), Ã¢â‚¬Â¦ and 22 in the five library detail screens (see 07-01)
SYMPTOM: A Spanish or Arabic user sees English text throughout the EQ sheet, the playlists screen, parts of Settings, the player's error states and several empty states. The most-used screen (the EQ sheet) is the worst affected.
CAUSE: Strings written inline in Dart instead of via `context.l10n`. The ARB files are complete, so this is purely a code-side wiring gap Ã¢â‚¬â€ the translations exist but are never reached.
FIX: Add a lint/CI gate that fails on new hardcoded UI literals, then sweep the 289 sites in priority order (EQ sheet Ã¢â€ â€™ playlists Ã¢â€ â€™ settings Ã¢â€ â€™ detail screens).

### 28-02 [P2] defect status=open ws=WS3
LOC: All 8 player themes + layout system
SYMPTOM: RTL correctness for Arabic was not verified across the eight now-playing themes, the mini player, or the EQ sheet's horizontal band scroller Ã¢â‚¬â€ the areas most likely to break under mirroring.
CAUSE: Not exercised.
FIX: Add RTL golden-image tests per theme.

### 28-03 [P3] defect status=open ws=WS3
LOC: `lib/l10n/app_en.arb` vs `app_es.arb` byte sizes (44,490 B vs 35,155 B)
SYMPTOM: **Corrected finding.** The byte-size gap is *not* missing translations: it is explained by Spanish having fewer/shorter `@`-metadata description blocks and shorter strings. The baseline hypothesis in `00-baseline.md` is refuted by the key-level diff, and `00-baseline.md` has been updated accordingly.
CAUSE: Ã¢â‚¬â€
FIX: Ã¢â‚¬â€

## Area 29
### 29-01 [P2] defect status=open ws=WS4
LOC: `android/app/src/main/AndroidManifest.xml:4` declares `INTERNET`; `android/app/src/prod/AndroidManifest.xml:6` removes it; `debug/` and `profile/` manifests re-add it
SYMPTOM: **The privacy guarantee is a build-configuration property, not an inherent one.** Any release built without the `prod` flavour (e.g. a plain `flutter build apk --release`) ships *with* `INTERNET`, Firebase, Sentry and the YTM bridge available Ã¢â‚¬â€ while presenting itself as the private offline player. Nothing in the manifest set prevents this.
CAUSE: Flavour-scoped manifest override rather than a single locked-down default.
FIX: Make the private configuration the default and the online one the opt-in flavour; and/or add a release-build check that fails when `INTERNET` is present in a prod artifact.

### 29-02 [P3] defect status=open ws=WS4
LOC: `app_config.dart:77Ã¢â‚¬â€œ82` (prod-must-not-enable-YTM assertion)
SYMPTOM: The prod/YTM consistency rule is expressed as a development assertion, so it protects developers but not a mis-configured release.
CAUSE: Assertion-based validation.
FIX: Promote to a build-time failure (see also 21-02).

### 29-04 [P2] defect status=open ws=WS4
LOC: `docs/PLAY_CONSOLE_READINESS.md` (claimed data-safety audit)
SYMPTOM: The Play Console data-safety claims were not reconciled against the actual permissions in each flavour during this audit; a mismatch between the declared data-safety form and the shipped manifest is a policy-review risk, not a code bug, but it is the highest-consequence documentation claim in the repo.
CAUSE: Not verified here.
FIX: Reconcile doc against both flavour manifests before each release.

