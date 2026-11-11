# Pulsr Hardening & Delivery Changelog

## Phase 0 — Baseline & P0 Corrections
- **`lib/core/constants/audio_feature_info.dart`**
  - **Change**: Restored truncated prefix check to `!lowerPath.startsWith('content://')) {`.
  - **Why**: Content URIs from Android MediaStore/SAF cannot be accessed via direct filesystem path probing; checking `content://` avoids false positive path validation failures.
  - **Risk**: Very low (restores intended Android SAF compatibility).
- **`lib/features/player/cubit/controllers/queue_slot_data.dart`**
  - **Change**: Reordered directives so `export` directives appear after all `import` directives.
  - **Why**: Dart 3 grammar requires all directives to appear before declarations and `import`s before `export`s.
  - **Risk**: None (pure grammar conformance).

## Phase 1 — Correctness & Concurrency
- **`lib/core/services/radio_station_store.dart`**
  - **Change**: Converted to true singleton with factory constructor, private internal constructor, single shared `ready` future getter (`_sharedReady ??= load()`), static `_writeMutex`, and test reset hook (`resetForTesting()`). In `lib/features/radio/presentation/radio_screen.dart`, replaced `await _store.load()` with `await _store.ready`.
  - **Why**: Prevents concurrent callers (home carousel, song classification, radio screen) from triggering redundant or racing disk reads.
  - **Risk**: Low (tested via `radio_station_store_test.dart`).
- **`lib/core/services/missing_artwork_service.dart`, `lib/core/services/sponsorblock_service.dart`, `lib/data/lyrics/lyrics_translation_service.dart`**
  - **Change**: Added `final bool _ownsClient` flag; only call `_client.close()` in `dispose()` if the client was created internally.
  - **Why**: Closing an externally injected client closes the shared HTTP connection pool of the caller (such as GetIt or test suites).
  - **Risk**: Low (preserves injected client lifecycle).
- **`lib/core/services/playlist_suggestions_service.dart`**
  - **Change**: Restructured suggestion generation into pure raw bucketing (`computeRawSuggestionBuckets`) which runs inside background isolate via `compute()`, and localized view building (`buildLocalizedSuggestions`) which resolves `L10nHolder.current` on the main isolate. Added `RawSuggestionBuckets` record typedef.
  - **Why**: Accessing `L10nHolder.current` inside an isolate throws a runtime error or returns null because isolate memory is unshared.
  - **Risk**: Low (maintains same suggestion outputs with correct localization).
- **`lib/core/services/ytm_account_service.dart`**
  - **Change**: Replaced mutable in-place `clientChain..sort(...)` with a stable partition `[...rawChain.where((c) => !_isSabrDemoted(c)), ...rawChain.where(_isSabrDemoted)]`.
  - **Why**: Dart `List.sort` is not guaranteed to be stable; partitioning preserves the deterministic priority hierarchy among both non-demoted and demoted clients.
  - **Risk**: None.
- **`lib/core/telemetry/playback_latency_tracker.dart`**
  - **Change**: Added `_disposed` check; guarded `_reportController.add` with `!_reportController.isClosed`; made `start`, `markStage`, `finish`, `finishWithError` safe no-ops after disposal.
  - **Why**: Avoids `StateError: Bad state: Cannot add event after closing` when async playback events land after tracker disposal.
  - **Risk**: None (verified via `playback_latency_tracker_test.dart`).
- **`lib/core/services/cloud_sync_service.dart`**
  - **Change**: Implemented last-writer-wins (LWW) conflict resolution using `modifiedAt`/`deviceTimestamp` vs `_localModifiedFavorites` timestamp map; removed title+artist fallback matching for favorites (remoteId/stable ID only); added delta queries with a 7-day tombstone window (`where('modifiedAt', isGreaterThan: lastSync - 7d)`).
  - **Why**: Prevents stale cloud tombstones or outdated cloud state from overriding newer local edits, eliminates dangerous collision when songs share title/artist, and cuts Firestore read costs via delta queries.
  - **Risk / BREAKING-BEHAVIOR**:
    > **BREAKING-BEHAVIOR: Sync Conflict Resolution & Matching**
    > - *Before*: Stale cloud downloads could overwrite newer local favorites; songs lacking remote ID were matched by fuzzy `title + artist`, causing distinct tracks or alternate takes with identical titles to conflate and override each other's favorite states.
    > - *After*: Last-writer-wins strictly inspects timestamps. Local favorites modified at $T_{local} > T_{cloud}$ defeat cloud updates. Stale tombstones from other devices are discarded. Matching is strictly pinned to stable track ID / remoteId.
- **`lib/core/services/duplicate_finder_service.dart`**
  - **Change**: Added full-file SHA-256 confirmation via `ChainOfCustodyService.hashFileContents` (capped at 512MB in isolate) before labeling a group "Checksum Verified"; stopped stripping `(Remix)/(Live)/(Version)` in `_normalizeString`; tightened duration tolerance from ±5s to ±2s when version tags differ.
  - **Why**: Prevents false positive duplicate grouping of studio originals with their remix or live versions, and guarantees checksum verification is cryptographic rather than partial hash.
  - **Risk / BREAKING-BEHAVIOR**:
    > **BREAKING-BEHAVIOR: Duplicate Clustering & Version Tag Preservation**
    > - *Before*: `_normalizeString` stripped `(Remix)`, `(Live)`, `(Acoustic)`, `(Radio Edit)`, etc., causing remixes and live performances to be grouped into duplicate clusters alongside original recordings if within ±5 seconds.
    > - *After*: Version tags are preserved during normalization. A remix and an original recording are recognized as distinct songs and will never be clustered together. When version tags differ, duration tolerance is tightened to ±2s.

## Phase 2 — Performance & Lifecycle
- **`lib/core/services/scrobbler_service.dart`**
  - **Change**: Throttled `_keyLastScrobblePos` persistence to ≥5s intervals during active playback; always persisted position immediately on track change and pause.
  - **Why**: Eliminates high-frequency SharedPreferences disk I/O on every second of audio position change while ensuring accurate crash/kill/pause recovery.
  - **Risk**: Very low (tested via `scrobbler_persistence_test.dart`).
- **`lib/core/services/ambient_sound_service.dart`**
  - **Change**: Debounced `_persist()` by 400ms via `_persistTimer`; replaced bare `catch (_)` in `init()` with `ErrorLogger.log`; added `cancelPersistTimerForTesting()`.
  - **Why**: Avoids disk thrashing during ambient volume slider dragging; preserves test determinism and logs startup errors.
  - **Risk**: Very low.
- **`lib/core/widgets/cached_artwork.dart`**
  - **Change**: Added static in-flight deduplication map `_inFlightFetches` keyed by URL and quality parameters, removing futures in `whenComplete`.
  - **Why**: Prevents multiple concurrent widgets displaying the same artwork URL from triggering duplicate concurrent network fetches.
  - **Risk**: Very low (tested via `cached_artwork_test.dart`).
- **`lib/features/home/presentation/widgets/online_category_section.dart` & `lib/features/library/presentation/tabs/library_songs_tab.dart`**
  - **Change**: Moved `playerCubit.warmStreams(...)` calls out of widget `build()` into `WidgetsBinding.instance.addPostFrameCallback`.
  - **Why**: Calling stateful / asynchronous stream warming during Flutter's build phase violates framework rules and causes extraneous rebuilds.
  - **Risk**: None.
- **`lib/core/services/ytm_service.dart` & `lib/core/services/ytm_service_internals.dart`**
  - **Change**: Added `_LruCache` bounded to 256 entries for `_loudnessByVideoId` and `_alternateVideoIds`.
  - **Why**: Prevents unbounded memory growth in long-running player sessions.
  - **Risk**: None.
- **`lib/core/network/app_http_overrides.dart`**
  - **Change**: Re-checked `_config` after `ServerSocket.bind` in `ensureSocks5Bridge` and closed the server if disabled; added backpressure in `_SocketByteReader.forwardTo` (paused source stream until `target.flush()` completes).
  - **Why**: Closes race condition where proxy is disabled while socket is binding, and prevents memory unbounded buffering when streaming through SOCKS5.
  - **Risk**: Low.
- **`lib/core/network/network_change_monitor.dart`**
  - **Change**: Recreates `_controller` in `start()` if closed.
  - **Why**: Allows network monitor to be safely stopped and restarted without throwing `Bad state: Cannot add event after closing`.
  - **Risk**: None.
- **`lib/core/services/library_cache_manager.dart`**
  - **Change**: Implemented atomic snapshot writing by writing to temporary file (`.tmp`), flushing, and renaming with Windows fallback.
  - **Why**: Prevents snapshot file corruption if the app is terminated mid-write.
  - **Risk**: None.
- **`lib/features/settings/cubit/settings_proxy_actions.dart` & `lib/features/settings/cubit/settings_cubit.dart`**
  - **Change**: Verified proxy password encryption in `FlutterSecureStorage` with one-time migration and plaintext wipe from `SharedPreferences`.
  - **Why**: Secures proxy credentials against unencrypted device backups and disk inspection.
  - **Risk**: None (tested in `settings_cubit_test.dart`).
- **`lib/features/home/presentation/home_screen.dart`**
  - **Change**: In online tab `onRefresh`, awaited refetched `categoryFuture`.
  - **Why**: Ensures pull-to-refresh spinner stays active until the new category data finishes loading.
  - **Risk**: None.
- **`lib/core/services/file_intent_handler.dart`**
  - **Change**: Routed `pulsr://favorites` to `context.go('/favorites')`.
  - **Why**: Directs user directly to dedicated favorites screen rather than generic library view.
  - **Risk**: None.
- **`lib/core/services/ytm_url_cache.dart`**
  - **Change**: On same-URL `put`, preserved stream's computed `expiresAt` via `copyWith(expiresAt: computedExpiry.millisecondsSinceEpoch)`.
  - **Why**: Prevents URL cache expiry regressions on repeat cache updates.
  - **Risk**: None.
- **`lib/core/services/auth_service.dart`**
  - **Change**: Passed `serverClientId` (via `const String.fromEnvironment('SERVER_CLIENT_ID')`) to `GoogleSignIn.initialize`, verified `idToken` non-null on Android with fallback to `accessToken`.
  - **Why**: Required by Google Play Services / Firebase OAuth for valid ID token minting on Android.
  - **Risk**: None (tested in `auth_service_test.dart`).
- **`lib/core/widgets/shimmer_skeleton.dart`**
  - **Change**: Reused parent `_SkeletonShimmerScope` when available, only instantiating per-box `AnimationController` when unshared.
  - **Why**: Slashes redundant animation controllers and CPU usage in large skeleton loading lists.
  - **Risk**: None.
- **`lib/core/services/metadata_search_service.dart`**
  - **Change**: Capped artwork download at 10MB using `BytesBuilder`; deleted superseded `auto_art_*.jpg` temp files.
  - **Why**: Prevents out-of-memory crashes on excessively large remote images and disk leakage.
  - **Risk**: None.

## Phase 3 — Tests & CI
- **Unit & Widget Tests**:
  - `test/core/services/ytm_cookie_codec_test.dart`: Split/merge/expiry deletion/signed-in detection.
  - `test/core/services/radio_station_store_test.dart`: Singleton concurrency and station ordering.
  - `test/core/services/cloud_sync_merge_test.dart`: LWW conflict resolution and timestamp parsing.
  - `test/core/services/duplicate_finder_test.dart`: Remix/original segregation and hash collision resolution.
  - `test/features/library/library_cubit_favorites_test.dart`: Rapid toggle race and failure rollback.
  - `test/core/telemetry/playback_latency_tracker_test.dart`: Post-dispose no-op safety.
  - `test/core/widgets/pulsr_dismissible_test.dart`: Two-stage confirm and swipe timeout.
  - `test/core/widgets/pulsr_toast_test.dart`: Deduplication and auto-dismissal.
  - `test/core/widgets/marquee_text_test.dart`: Reduced-motion and boundary checks.
  - `test/core/widgets/pulsr_slider_test.dart`: Wavy/straight styling, bounds, and RTL interactions.
- **CI Workflow (`.github/workflows/ci.yml`)**:
  - Ensured `git diff --exit-code` verification after `build_runner` to fail CI if generated code is committed out of sync.
- **`CLAUDE.md`**:
  - Documented root package metadata (`pulsr`, `pubspec.yaml`, version 1.0.0+1, SDK `>=3.0.0 <4.0.0`, Flutter `>=3.41.0`).
  - Documented `CustodyVerifier.cpp / .h` and `DacVoicing.cpp / .h` in §4.6. Verified with `scripts/check_claude_dsp_docs.py` (exit code 0).
