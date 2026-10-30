# Player feature audit — Pulsr

- **Date:** 2026-10-30
- **Scope:** `lib/features/player/**` (cubit + controllers + managers + presentation/widgets + themes), read-only
- **Method:** source reading with `file:line` anchors cross-checked against DI wiring (`lib/core/di/injection.config.dart`) and the existing test corpus. `flutter analyze` / `flutter test` were **not** run (out of scope for this task), so all statements below are static-reading conclusions.
- **Baseline:** `gaps.md` (2026-10-02 body, 2026-10-04 remediation header).
- **No source file was modified.** This is the only file created.

Verdict legend: **FIXED** = current code no longer contains the defect; **STILL-OPEN** = defect still present, evidence given; **PARTIAL** = fixed on the main path but still reachable on a secondary path.

---

## STILL-OPEN

### Baseline claims that are now FIXED (verified, listed so they are not re-litigated)

| # | 2026-10-02 claim | Verdict | Current evidence |
|---|---|---|---|
| 1 | Quran Mode never persisted/restored; `QuranModeService` injected but unused; `PlayerQuranManager` dead | **FIXED** | `player_cubit.dart:245` `unawaited(playbackOptionsController.restoreQuranMode());`; manager is constructed and passed at `player_cubit.dart:162-164`; persistence in `quran_mode_service.dart:83-84` (`loadActiveProfile` → `if (!await isEnabled()) return null;`); DI passes the real service at `injection.config.dart:291` `quranModeService: gh<_i322.QuranModeService>()`. Caveat: still **no test** covers enable→relaunch→restore (only `test/features/player/player_playback_options_quran_race_test.dart`, 61 lines, covers toggling races). |
| 2 | "Reset Profile" undoes Quran Mode (`reapplyQuranProfile` restored the pre-Quran snapshot) | **FIXED** | Button now calls `resetQuranProfile` — `quran_mode_sheet.dart:529` `cubit.resetQuranProfile(),`; that method clears the style tuning then re-applies the curated profile: `player_playback_options_quran.dart:674-700` `final cleared = await _quranManager.setStyleTuning(... const QuranStyleTuning()); ... await _applyQuranProfile(QuranModeProfile.forStyle(...))`. The retry button (`quran_mode_sheet.dart:298`, `reapplyQuranProfile`) also re-applies the Quran profile while enabled (`:657-672`). |
| 3 | Quran `preampDb` captured but never applied | **FIXED** | `player_playback_options_quran.dart:640` `await _audioHandler.setPreamp(tunedProfile.preampDb);` inside `_applyQuranProfile`'s transition, and `:600` `preampDb: tunedProfile.preampDb,` in the emitted state. |
| 4 | `_resolveMediaItemId` is O(n²) via `Map.containsValue` in a loop | **FIXED** | Reverse index `Set<int> _negativeIdValues` — `player_cubit.dart:400-402` (declaration) and `:421` `if (!_negativeIdValues.contains(h))`; the collision walk at `:441-442` is only over assigned fallback ids. No `containsValue` remains in the file. |
| 5 | `_slotLookupCache` grows monotonically, never pruned | **FIXED** | `player_queue_slots.dart:7` `const int _maxSlotLookupCacheEntries = 4096;` + `_cacheSlotSongs` re-inserts and evicts the oldest beyond the cap (`:12-29`), called from `setQueueSlot` (`player_queue_radio.dart:71`). Residual: `player_transport_controller.dart:338` writes the map directly (`_slotLookupCache![songId] = ...`) bypassing eviction, so the bound is only enforced on queue mutation. |
| 6 | Three injected deps accepted then ignored | **FIXED** | `settingsProfilesService`, `deviceProfileService`, `hiResAudioService`, `smartAudioService` are all consumed (`player_dsp_profiles.dart:14-29`, `player_dsp_follow_rate.dart:13,140`, `player_playback_options_lyrics.dart:212-214`). |
| 7 | Per-song rating writes bypass the DI singleton (`SongRatingStore()` per call) | **FIXED (main path)** | `player_playback_options_controller.dart:105` is now a fallback only (`_songRatingStore = songRatingStore ?? SongRatingStore()`), and the cubit always passes the injected store (`player_cubit.dart:157`); DI hands over the `@singleton` at `injection.config.dart:289`. Residual: a `PlayerCubit` built with `const PlayerDependencies()` still forks the store silently. |
| 8 | Queue add/reorder/remove compute from a pre-`await` snapshot; `_queueMutex` used in one method | **PARTIAL** — see S1 below | `addToQueue`/`playNext`/`addAllToQueue` now re-read state after the await (`player_queue_slots.dart:679`, `:750`, `:832`) and all of `playSong`, `addToQueue`, `playNext`, `addAllToQueue`, `removeQueueItem`, `reorderQueue`, `clearQueue`, `restoreQueue`, `switchQueueSlot`, `restoreQueueSlots` are wrapped in `_queueMutex.protect`. |
| 9 | `setQuranAmbience` unclamped/uncatch, no generation guard on rapid on→off | **FIXED** | `player_playback_options_quran.dart:378-382` `if (!value.isFinite || ...) return; final gen = ++_quranAmbienceGen; final clamped = value.clamp(0.0, 0.6);`, try/catch with full DSP rollback at `:405-422`. Toggle guard `_quranToggleGen` at `:191-198`. |

### Claims that are still open

**S1 — Autoplay/radio queue append is the one mutation path with no mutex (lost update).**
`player_queue_radio.dart:189` `Future<void> fetchAndEnqueueAutoplay(String seedVideoId,` … appends to the engine at `:245-252` and emits the new queue at `:279-284` without ever taking `_queueMutex`. Why it is wrong: `_removeQueueItemLocked` reads `state.queue` before `await _audioHandler.removeQueueItemAt(index)` and emits that pre-await snapshot after the await (`player_queue_slots.dart:361,446`); the mutex is the only thing that makes that snapshot safe. A 15-track autoplay fetch (network, seconds) that lands inside a user remove/reorder window overwrites the user's change in state while the engine keeps both. Secondary: `room` is computed from the pre-await state at `:243` `final room = PlayerQueueController.maxQueueSize - s.queue.length;`, so the 500-item cap can be overshot. Consequence: removed tracks reappear, or queued tracks vanish and desync from the engine until the next mutation.

**S2 — Mute state lives outside `PlayerState` and the UI reads it during build.**
`playback_volume_mute.dart:13` `bool _muted = false;` with the only reader `player_playback_options_controller.dart:308` `bool get isMuted => _volumeControl.isMuted;`, consumed by `tablet_player_bar.dart:1026` `final isMuted = cubit.isMuted ||`. Why it is wrong: `toggleMute()`/`setVolume()` emit no state (`playback_volume_mute.dart:45-79` only emits on error), and a `BlocBuilder` rebuilds only on state change, so the getter is sampled at an arbitrary earlier build. Consequence: after muting from the tablet bar the icon/tooltip keep showing "Mute" until playback emits something unrelated.

**S3 — `QuranPanel` tuning sliders are unlabelled to accessibility services.**
`quran_mode_sheet.dart:962` `Slider(` with `onChanged`, `onChangeEnd`, `activeColor`, `inactiveColor` only — no `semanticFormatterCallback`, no wrapping `Semantics(label: widget.title)`. The `Text(widget.title)`/`subtitle` are visual siblings. Consequence: TalkBack announces "50 percent, adjustable" with no indication whether it is mosque ambience or vocal warmth.

**S4 — Controller size budget still evaded via `part` files.**
`player_queue_slots.dart` 851 lines, `player_dsp_effects.dart` 985, `player_playback_options_quran.dart` 714 — all `part of` their controller, so the ≤400-line rule is measured on the parent only. (Baseline cited 629/722; both have grown.)

**S5 — Empty catches remain in the player feature.**
`player_queue_warming.dart:24` and `:51` `catch (_) {}` (stream warm failures leave no trace); `player_queue_slots.dart:557` `catch (_) {}` (slot-switch speed rollback); `player_playback_options_quran.dart:73` `catch (_) {}` in `_clearQuranSnapshot`. Baseline listed the first two; all three are still present.

---

## NEW FINDINGS

**9 new findings** (N1–N9). The mute-item defect is *not* counted here: it is a re-verification of the baseline claim and lives in STILL-OPEN as S2.

### N1 (High) — Quran Mode silently flips itself on every track change; `isAutoTriggered` is dead

- `player_playback_options_track_state.dart:59` — `await handleTrackChangeQuranMode(song);` runs from `onCurrentSongChanged`, which the cubit fires on every real track change (`player_cubit.dart:533`, `:664`, both `unawaited`).
- `player_playback_options_quran.dart:189` — `{bool isAutoTriggered = false}) async {` … the parameter is **never referenced** anywhere in the 60-line body (no branch distinguishes a user toggle from an automatic one), and `handleTrackChangeQuranMode` always passes `isAutoTriggered: true` (`:742`, `:746`).
- `player_playback_options_quran.dart:736-747` — `if (isQuran) { if (!isCurrentlyEnabled) { await setQuranModeEnabled(true, isAutoTriggered: true); } } else { if (isCurrentlyEnabled) { await setQuranModeEnabled(false, isAutoTriggered: true); } }`

Why it is wrong: the user's explicit on/off is overwritten by a metadata heuristic on every track. `isQuranTrack` (`core/utils/song_classification.dart:36-174`) is a `norm.contains(kw)` scan for `'quran'`, `'surah'`, `'recitation'`, `'tilawat'`, `'koran'`, plus 60 reciter names — a lecture titled "Why the Quran matters", an artist called "Quranic Beats", or any album tag containing "recitation" all match, and the whole DSP chain is rewritten by `_applyQuranProfile` (EQ preset replaced, `applyHeadphoneProfile(null)` at `:619`, preamp, saturation, reverb, and `setSpeed(tunedProfile.playbackSpeed)` — 0.75× for `memorization`).

Consequence: (a) playing such a track mid-album audibly changes EQ, room, warmth and playback speed with no user action; (b) a manually enabled Quran Mode is switched off — and persisted as off — the moment a non-matching track starts, so "on" cannot be pinned; (c) the automatic enable is persisted through `_quranManager.setEnabled(true)` (`:224`), so the app relaunches in Quran Mode for a user who never enabled it. This also makes the baseline's "persistence" fix behave as "persist whatever the heuristic last decided".

### N2 (High) — `fetchAndEnqueueAutoplay` mutates the queue outside `_queueMutex`
See S1. Anchor: `player_queue_radio.dart:189` (no `protect`), `:243` stale `room`, `:279-284` emit. Distinct from the fixed add/remove paths.

### N3 (Medium) — Seek bar exposes two nested slider semantics nodes with conflicting values

- `player_seek_bar.dart:436-441` — `Semantics(value: valueLabel, increasedValue: increasedLabel, decreasedValue: decreasedLabel, onIncrease: …, onDecrease: …, child: AnimatedContainer(… PulsrSlider(…)))` — no `excludeSemantics: true`.
- `pulsr_slider.dart:222-225` — `child: Semantics(label: widget.semanticLabel, slider: true, value: '${(t * 100).round()}%', …)`.

Why it is wrong: the inner widget already publishes itself as a slider with a percentage value; the outer node adds a second, differently-formatted value ("1:42 / 3:58") plus increase/decrease actions. The two nodes are siblings in the semantics tree, so a screen reader announces a *percentage* for a time control and can focus the same control twice, and both `onIncrease` handlers seek by 10 s.

Consequence: the primary scrub control is ambiguous and double-actionable for TalkBack/VoiceOver users.

### N4 (Medium) — Transport buttons are 28–42 dp because the theme-supplied `sideButtonSize` has no 48 dp floor

- `player_theme_scaffold.dart:187-191` — `final double sideButtonSize = isTablet ? 48.0 : (isLandscape ? 36.0 : (isShortHeight ? 38.0 : (isCompactHeight ? 42.0 : 48.0)));` → **36 dp in landscape**, 38 dp on short screens, 42 dp compact, passed straight through as `sideButtonSize: metrics.sideButtonSize` (`:533`).
- `player_controls.dart:128-129` — `final resolvedSideSize = widget.sideButtonSize ?? (widget.mainButtonSize * 0.72).clamp(38.0, 52.0);` — the explicit value wins verbatim; the `clamp(38.0, 52.0)` floor only applies to the fallback, so nothing enforces ≥48 dp.
- `player_controls.dart:135` — `final abButtonSize = (resolvedSideSize * 0.78).clamp(32.0, 42.0);` → A/B loop buttons 28–37 dp in landscape/short layouts.
- `player_controls.dart:143` — the row also sits in `FittedBox(fit: BoxFit.scaleDown, …)`, shrinking every hit area further on narrow widths.

Consequence: previous/next are 36 dp in the landscape player and the A/B loop buttons ≈28 dp — far below the 48 dp Material/Apple minimum, on the two most-used controls of the screen. (The scrub strip is similarly 32 dp tall: `player_seek_bar.dart:451` `height: isDragging ? 38.0 : 32.0`.)

### N5 (Medium) — Quran badge is a ~20 dp unlabelled tap target

- `quran_mode_badge.dart:28-35` — `child: InkWell(onTap: … child: Ink(padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12, vertical: compact ? 3 : 6), …` around a 12 px `Text('Quran Mode')`.
- No `Semantics(label: …, button: true)` anywhere in the file; the visible string is a hardcoded English `'Quran Mode'` (`:68`) in an otherwise localized sheet (`context.l10n.quranMode` exists and is used at `quran_mode_sheet.dart:205`).

Consequence: compact badge is ≈20 dp tall (≈34 dp with the 6 px non-compact padding), fails the 48 dp target, and is announced as plain text rather than a button; the label is untranslated.

### N6 (Medium) — Two async guards are write-only; one flag can never observe a race

- `player_queue_controller.dart:69-75` — `final AsyncGuard _mediaItemGuard = AsyncGuard();` / `final AsyncGuard _lyricsGuard = AsyncGuard();` with public getters `mediaItemGuard` / `lyricsGuard`.
- Only uses: `player_queue_playback.dart:97` `_mediaItemGuard.next();` (return value discarded, no later `isValid`), `player_queue_playback.dart:232` `_lyricsGuard.invalidate();`, `player_queue_controller.dart:128-129` invalidate in `dispose`.
- No `isValid(...)` call exists for either guard anywhere in `lib/` (grep for `mediaItemGuard`/`lyricsGuard` returns only those lines).
- `player_queue_slots.dart:473-474` — `if (_isSwitchingSlot || _isClosed()) return; _isSwitchingSlot = true;` is inside `_queueMutex.protect`, so a second caller cannot be inside the critical section to observe it.

Why it is wrong: these read as concurrency protection but guard nothing; the getters make them look load-bearing to future readers.

Consequence: no user-visible failure today, but the lyric-load and media-item code paths that the comments promise are protected (see the rollback comment at `player_queue_playback.dart:229-234`) are not; a regression there will not be caught.

### N7 (Low–Medium) — Index-arithmetic helpers are test-only; production re-implements them inline

- `queue_slot_data.dart:33` `int calculateReorderedIndex(int oldIndex, int newIndex, int currentIndex)` and `:45` `int calculateRemovedIndex(int removedIndex, int currentIndex, int newQueueLength)` are referenced **only** by `test/architecture/code_hygiene_test.dart:130-160`.
- The live implementations are duplicated inline: `player_queue_slots.dart:325-337` (reorder) and `:400-408` (remove).

Why it is wrong: the code the hygiene test certifies is not the code that runs, so the test can stay green while the real index math drifts.

### N8 (Low) — Media-item id cache eviction can change an id between two resolutions of the same item

- `player_cubit.dart:413-415` — `if (_remoteIdToNegativeId.length >= _maxNegativeIdEntries) { final evictedKey = _remoteIdToNegativeId.keys.first; final evictedValue = _remoteIdToNegativeId.remove(evictedKey);`
- The queue-restore listener resolves every id once at `player_cubit.dart:~604` (`final ids = mediaItems.map((m) => _resolveMediaItemId(m.id)).toList();`) and then resolves each item **again** inside the loop (`final mid = _resolveMediaItemId(m.id);`), where `songsMap.containsKey(mid)` decides between a DB row and a fabricated `SongsTableData`.

Why it is wrong: once 1000 distinct non-numeric ids have been seen, an evicted id is re-assigned a fresh negative id, so the second resolution can disagree with the first; the item then misses its DB row and a synthetic duplicate (`id` never in the DB) is appended to the queue.

Consequence: duplicate/ghost queue rows and lost per-song overrides after a long session with >1000 remote ids (a queue itself is capped at 500, so this needs several restores/slots in one process).

### N9 (Low) — Quran metadata load swallows every failure and bypasses DI

- `quran_mode_sheet.dart:120-129` — `} catch (_) { if (mounted) { setState(() { _metadata = null; _bookmark = null; }); } }` — a DB failure is indistinguishable from "this track has no Quran metadata", and the sheet then renders as if the track were not a recitation.
- `quran_mode_sheet.dart:97-99` — `final repo = getIt.isRegistered<QuranRepository>() ? getIt<QuranRepository>() : QuranRepositoryImpl();` — the fallback constructs a repository directly, although `QuranRepository` **is** registered (`injection.config.dart:219`), so the branch is dead and hides a misconfigured locator.

Consequence: silent blank metadata card; no error surface, no log.

---

## RANKED FIX LIST

Ordered by user-visible blast radius per unit of change.

| Rank | Item | Anchor | Fix direction |
|---|---|---|---|
| 1 | Quran Mode auto-flips on every track change; user intent discarded | `player_playback_options_track_state.dart:59`, `player_playback_options_quran.dart:189,736-747` | Honour `isAutoTriggered`: only auto-enable when the user has never made an explicit choice (persist a `quranModeUserOverride` tri-state), and never auto-disable a manually enabled mode. Tighten `isQuranTrack` to genre/station signals before trusting the keyword list for DSP changes. |
| 2 | Autoplay append bypasses `_queueMutex` → lost queue updates and cap overshoot | `player_queue_radio.dart:189,243,279-284` | Wrap the whole append in `_queueMutex.protect`, recompute `room` from the post-await state, and add an in-flight latch so overlapping `checkAndTriggerAutoplay` calls cannot double-fetch. |
| 3 | Mute icon/tooltip stale | `playback_volume_mute.dart:13`, `player_playback_options_controller.dart:308`, `tablet_player_bar.dart:1026` | Move `_muted` into `PlaybackSlice` (e.g. `isMuted` + `volumeBeforeMute`) and emit on every mute/volume change; keep the engine as the single writer. |
| 4 | Duplicate/conflicting slider semantics on the main scrubber | `player_seek_bar.dart:436-441` + `pulsr_slider.dart:222-225` | Add `excludeSemantics: true` to the outer `Semantics` (or drop the inner node when a `semanticLabel` is supplied) so exactly one slider node announces time, not percent. |
| 5 | Sub-48 dp transport and Quran badge targets | `player_theme_scaffold.dart:187-191`, `player_controls.dart:128-135,143`, `quran_mode_badge.dart:28-35` | Clamp the resolved side size to ≥48 dp inside `PlayerControls` (so no theme can undercut it), raise the A/B floor to 48, replace `FittedBox` scaling with adaptive spacing, and give the badge `ConstrainedBox(minHeight: 48)` + `Semantics(button: true, label: l10n.quranMode)`. |
| 6 | Quran tuning sliders unlabelled | `quran_mode_sheet.dart:962-981` | Wrap in `Semantics(label: widget.title, value: widget.valueLabel)` and/or add `semanticFormatterCallback: (v) => '${(v * 100).round()}%'` plus `divisions`. |
| 7 | Write-only guards mislead future concurrency work | `player_queue_controller.dart:69-75,77`, `player_queue_playback.dart:97,232` | Either consume them (`if (!guard.isValid(gen)) return;` on the lyric/media-item continuations) or delete the fields, getters and the `_isSwitchingSlot` flag. |
| 8 | Test-only index helpers while production duplicates the math | `queue_slot_data.dart:33,45` vs `player_queue_slots.dart:325-337,400-408` | Call the helpers from the controller and delete the inline copies, so `code_hygiene_test.dart` covers the shipped path. |
| 9 | Id-cache eviction can re-identify a media item mid-restore | `player_cubit.dart:413-415`, queue listener double resolution | Resolve each id once and pass the resolved ints into the loop; raise/derive the cache bound from `maxQueueSize` (≤3 slots) and never evict an id that is present in the engine queue. |
| 10 | Quran metadata errors swallowed; dead DI fallback | `quran_mode_sheet.dart:97-99,120-129` | Log through `ErrorLogger`, surface a retry in `QuranErrorCard`, and delete the `QuranRepositoryImpl()` fallback. |

### Test gaps worth closing with the fixes

- No test asserts that a Quran Mode enable survives a relaunch, or that an explicit "off" is not overridden by a track change (N1) — `test/features/player/` has no restore/persistence test.
- No test drives `fetchAndEnqueueAutoplay` concurrently with `removeQueueItem` (N2).
- No a11y test covers `PlayerControls`, `PlayerSeekBar` or `QuranPanel` (the a11y suite only touches chrome/waveform), which is why N3–N5 are invisible to CI.
