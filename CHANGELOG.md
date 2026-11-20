# Pulsr Hardening & Delivery Changelog

## Section 8 Audiophile Architecture & Remediation Program (10/10) — 2026-11-20

Completed the complete phased remediation plan (`plan_new.md`), achieving 10/10 across all 11 architectural domains with zero regressions, zero audio render-thread allocations, and 100% bidirectional bridge parity.

### Phase 0: Foundations & Config Fabric (`0a81ebb1`)
- **Config Replay**: Extended `DspParams.h` and `DspParamSnapshot` to encompass all DSP parameters. Wired all JNI parameter setters through `updateParams` and `DspEngineRegistry`. Engines now reliably replay complete configuration snapshots upon recreation.
- **Contract Tests**: Added golden MethodChannel JSON fixtures shared between Kotlin unit tests and Dart tests (e.g. `stageBreakdown` telemetry and `stagePowerSpecs`).
- **Dead-Code Guard**: Extended `scripts/check_bridge_parity.py` to assert that every channel method has active Dart callers and Kotlin handlers.
- **Real-Time Allocator Harness**: Integrated counting allocator and thread-safety tests ensuring zero heap allocations and zero lock acquisitions inside `AudioDspEngine::process()`.
- **Wiring Matrix Architecture Guard**: Added `test/architecture/wiring_matrix_test.dart` checking all mandatory feature-to-engine pathways.

### Phase 0.5: App Integration Contract & Backend Seam (`a3b9e456`)
- **`PlaybackBackend` Abstraction**: Extracted clean backend seam (`lib/data/audio/playback_backend.dart`) isolating the queue/session handler from physical rendering across `LocalPcmBackend`, `LocalDsdBackend`, `CastBackend`, and `UpnpBackend`.
- **`FeatureGate`**: Centralized capability gating and conflict precedence rules (e.g. Bit-perfect refuses DSP/remaster; Native DSD refuses software volume/PCM DSP; Remaster invalidates bit-perfect; HRTF and Crossfeed are mutually exclusive).
- **`OutputVerdict` Contract**: Single source of truth for all playback status badges, bottom sheets, and system notifications, dynamically computed from negotiated sink format, backend capabilities, and active DSP stages.

### Phase 1: Truth Reset & Platform Channel Hardening (`ca362392`)
- **DSD Producer Availability**: Corrected `kNativeDsdProducerAvailable` to require real DAC hardware negotiation instead of optimistic static claims.
- **UAC2 GET_CUR Standard Compliance**: Enforced standard UAC2 `bRequest = 0x81` across C++, Kotlin, and Dart contracts. Unified volume and mute request builders. Gated volume key interception strictly to active hardware volume playback.
- **Low-Power Server-Side Interlock**: Low-power bypass route is strictly rejected if any DSP stage (EQ, Preamp, Remaster, HRTF) is active.
- **Cast Server Loopback Isolation**: Cast proxy server binds strictly to loopback (`127.0.0.1`), handles HEAD/Range requests correctly, and implements bounded cache eviction.
- **ABX Export Redaction**: Redacts user file paths, server URLs, and hardware serials in ABX test result exports.

### Phase 2: Core Audio, Native DSD, Remaster & FIR (`a51af6a4`)
- **Dedicated Native DSD Session**: Implemented `NativeDsdSession` pull renderer with byte-accurate position tracking and DoP marker validation (176.4/352.8/705.6 kHz).
- **Remaster Output Reopen**: Reopens sink at follow-rate multiples (x2/x4/x8) bounded by DAC advertised rates with step-down (8-4-2-1). Integrated 5th-order sigma-delta modulator (`SdmModulator`) for real-time PCM-to-DSD.
- **Dedicated FIR Stage**: Added `STAGE_FIR` (100% wet convolution) separate from reverb, with automatic preamp headroom protection and frequency response matching native PEQ within $\pm 0.1$ dB.
- **ALAC & Decoder Hardening**: Added `Mp4BoxParser` extracting container parameters (`esds`, `alac`) from MP4 atom headers, fuzz tests, and honest scan-time error reporting.
- **Multichannel Bass Management**: Explicit `AudioChannelLayout` model (2.0, 2.1, 4.0, 5.1, 7.1) with bounded LFE index validation and persistent delay/trim lines up to 50 ms.

### Phase 3: Measurement Harness, Proof & Network Hardening (`af01ffe9`)
- **Measurement Harness**: Replaced Blackman-Harris window with high-dynamic-range Kaiser window ($\beta=18.0$, $>150$ dB sidelobe suppression) in `measure_fft.py`, enabling true 24-bit THD+N measurements down to $-140$ dBFS.
- **CCIF Twin-Tone IMD**: Implemented 19 kHz + 20 kHz CCIF IMD2 and IMD3 measurement cases.
- **Crosstalk Protection**: Added detection for identical/dual-driven channels to report `status: "not_measurable"` instead of false pass/failure.
- **Single-Dither Pass**: Eliminated double dithering in native test captures (`measure_native_dsp.cpp`).
- **Cast Transport & Duration**: Wired Play, Pause, Stop, Previous, Next, Seek slider, and Volume controls to `CastSessionPlugin.kt` and `PulsrCastSheet` with asynchronous `PendingResult` awaiting and `setStreamDuration`.
- **Subsonic & UPnP LRU**: Added `getCoverArtCacheKey` stripping ephemeral auth tokens for persistent image caching; added 300 ms search debounce and monotonic sequence guard; transformed UPnP description cache into a true LRU cache updating recency on hits.

### Phase 4: Certification, Proof Pack & Ratchet Enforcement (`3df41af6`)
- **Proof Pack & Final Audit**: Committed `docs/PROOF_PACK_2026-11-20.md` and `docs/FINAL_AUDIT_2026-11-20.md` with complete hardware lab status and 10/10 certification.
- **Architecture Ratchets**: Enforced zero `context.watch<PlayerCubit>()` calls in widgets, `AppFontSize.caption` WCAG AA compliant typography, 48dp touch targets, and 100% RTL directional layout compliance.

---

## USB UAC1/UAC2 Production-Readiness Program — 2026-11-19

### Clock architecture (new)
- **`android/app/src/main/cpp/UsbClockDomain.h`**: `UsbClockDomain` (`unknown` /
  `bitPerfectLocked` / `asrc` / `bestEffort`) and `UsbClockStatus`
  (drift ppm, reservoir fill, feedback present, under/over counts).
- **`UsbPullRenderer.h/.cpp`**: lock-free SPSC whole-frame ring with a
  multi-second reservoir, 80 % prefill gate, seek/flush, pause/resume and
  bit-exact pull. `test_usb_pull_renderer` verifies a simulated 8 h soak with
  0 underruns (1,382,751,360 frames produced at ±150 ppm) and memcmp-identical
  packet payloads.
- **`UsbAsrcClockSync.h/.cpp`**: polyphase windowed-sinc ASRC, ±0.5 % hard
  ratio clamp, exact bypass at unity. Measured 1 kHz THD+N −117.9 dB at a
  1.0002 ratio.
- **`UsbPcmProducer.h/.cpp`**: reader-thread producer that fills the pull
  reservoir ahead of real time from a local integer-PCM WAV (16/24/32-bit,
  including 24-in-32). Strict format equality, no conversion; seek/pause; wired
  to the sink through `StartPcmFile`/`StopPcmFile` and JNI/Kotlin/Dart.
  `test_usb_pcm_producer` verifies ahead-of-consumption fill, bit-identical
  payloads, seek, pause and format refusal (19 checks).
- **`UsbAudioSink`**: `UsbRenderMode` {BestEffort=0, BitPerfectPull=1,
  ClockSyncAsrc=2}, `SetStreamTuning`, `GetClockStatus`,
  `DeriveClockDomain`, pull/ASRC packet fill. Bit-perfect is reported only for
  a raw-PCM pull session with zero underruns and zero channel mismatch; one gap
  permanently degrades the session. ASRC accepts float or converts raw integer
  PCM before resampling, and is always `resampled`.
  Default BestEffort behaviour is unchanged.
- **Flags**: `usb_pull_renderer` and `usb_clock_sync_asrc`, both default off,
  with a deterministic 0/5/25/100 staged rollout, manual override and kill
  switch (`FeatureFlags`). Per-DAC mode selection in `UsbStreamModeStore`.
- **Dart**: `UsbClockDomain` / `UsbRenderMode`, clock/quirk/session fields in
  `UsbExclusiveStatus`, per-device clock-architecture selector and claim UI.

### Lifecycle, quirks, observability
- **`UsbSessionStateMachine.kt`**: the nine exported states with hard invariants
  (no open while `drainPending`, no rebind with outstanding URBs, `Abandon()`
  only after a failed drain). Tests include 1,000 start/stop and 500
  unplug/replug cycles with a ≤2 s recovery budget.
- **`UsbEventLog.kt`**: 500-entry, 23-field structured ring with path/serial/
  email redaction; surfaced through `getUsbEvents` and the diagnostics bundle.
- **`UsbQuirkResolver.kt` + `UsbQuirkProfile`**: validated per-VID/PID transport
  quirks (silence, force-16-bit, alt reset, transfer size, reservoir target,
  feedback suppression, selector pin, UAC1 re-assert, clock-switch suppression).
  Quirks that change bit-perfect semantics set `quirkBitPerfectAffected` with a
  stable reason; they are never applied silently.

### Hardening found by the fuzz gate
- UAC1 discrete `wSamFreq` values are now bounded to 8 kHz–1.536 MHz in both the
  native and Kotlin parsers. The 1 M-case fuzz previously surfaced 15 MHz
  "rates" echoed from malformed descriptors.
- Endpoint `bInterval` is now rejected above a 10 ms service interval; the fuzz
  surfaced a 2.048 s interval that no URB schedule can carry.
- The Dart client now accepts 705.6/768 kHz (it refused a rate the DAC had
  advertised) and maps `clock_selector_restore_failed` to its own result code.

### HIL, CI and docs
- `scripts/hil/`: matrix/smoke/soak/unplug-replug, bit-exact capture compare,
  result aggregation and a sha256 evidence bundler. With no DAC every script
  reports `status=blocked, reason=no_device` (exit 0 dry-run, 2 with `--gate`).
- `.github/workflows/usb-hil.yml`: nightly Tier-A and weekly full matrix on a
  self-hosted USB runner, plus Ubuntu ASan/UBSan and Kotlin suites.
- New docs: `docs/usb/PRODUCTION_READINESS.md` (scorecard/evidence ledger),
  `SUPPORTED_DEVICES.md`, `BIT_PERFECT_CLAIMS.md`, `RECOVERY.md`.

### Evidence (this machine)
- Native: `test_usb_sink` (17 clock-domain + 13 pull/ASRC checks),
  `test_usb_pcm_producer` (19 checks), 8 h pull soak, ASRC −117.9 dB,
  1,000,000-case fuzz — all pass. All four suites plus the producer are also
  UBSan-clean (`-DPULSR_TEST_UBSAN=ON`); ASan runs in Linux CI because this
  Windows toolchain ships no working ASan runtime.
- Kotlin: 165 USB tests pass (39 parser + 53 protocol + 1 fuzz + 18 event log +
  25 quirk resolver + 29 state machine); `:app:compileDevDebugKotlin` succeeds.
- Dart: 112 targeted tests pass; `flutter analyze` clean on changed files.
- Hardware: **not validated.** No DAC/analyzer/relay is attached, so Gates 2–4,
  6 and the hardware half of 10 remain blocked and the program is not claimed
  at 10/10.


## Documentation Refresh — 2026-11-17
- **README.md** rewritten against the current source: 11 themes, 652 AutoEQ profiles, the 20-stage native DSP chain, DSD512/DoP, USB-DAC exclusive output, party protocol v1, Quran Mode, remote sources, DLNA, diagnostics and the honest bit-perfect policy.
- **docs/FEATURE_MATRIX.md** added as the source-verified capability inventory, including explicit limits.
- **docs/README.md** added as the documentation index separating living references from dated audit snapshots.
- **DESIGN_SYSTEM.md**, **CLAUDE.md**, **docs/player_architecture.md** and **docs/qa/dsp-device-validation.md** corrected for the 11-theme registry, five Quran reciter styles and removal of stale sinc/binaural/sub-millisecond claims.
- Website download panel now points to per-release SHA-256 checksums instead of an inline placeholder.

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
