# 03 — Resources: Memory, UI-Isolate Cost, Battery, Startup

Repo: `D:\Courses\Projectss\pulsr` · 2026-10-30 · read-only (no run, no profile, no `flutter test`).
**[V]** = verified by reading the cited line · **[I]** = inferred (arithmetic, ordering, or absence-of-grep).
Library size assumed for all cost math: **5,000 tracks**.

---

## 1. MEMORY

| Cache | Bound | Where | Verdict |
|---|---|---|---|
| Flutter `imageCache` | **80 MB / 250 images** | `lib/main.dart:77-78` **[V]** | Bounded, hard |
| `ArtworkCacheManager` strong LRU | **150 items / 35 MB** (dual bound, evicts from `keys.first`) | `artwork_cache_manager.dart:28-29`, `:202-203` **[V]** | Bounded |
| `ArtworkCacheManager` weak tier | one `WeakReference` per payload **> 512 KB**; key map has **no count bound**, dead refs swept only every 20 puts (`_pruneDeadWeakReferences`) | `artwork_cache_manager.dart:30`, `:184-195` **[V]** | Bytes bounded, **keys lazily bounded** |
| Disk artwork cache | default **100 MB**, user clamp **10–2048 MB**, pruned to **90 %** of cap, `Isolate.run` (off-isolate), triggered every **20 puts** | `artwork_cache_manager.dart:22`, `:55`, `:139`, `:331-372` **[V]** | Bounded, correctly off-thread |
| `ArtworkLruCache` (widget tier) | **200 items / 50 MB** strong + 200 weak large keys, swept on each large put | `cached_artwork.dart:22-26`, `:83-104` **[V]** | Bounded |
| `CachedArtwork` decode size | `cacheWidth/Height = (size·dpr).clamp(80,800)`, HQ `.clamp(300,1440)` | `cached_artwork.dart:585-589`, used `:607-608` **[V]** | Bounded — a 48 dp row decodes ≤96–144 px, never full-res |

**Unbounded growth still present**

- `_colorCache` — `static final Map<int, Color>` on `SettingsState`, **no eviction, process lifetime** (`settings_state.dart:217-220` **[V]**). Key domain is ARGB ints so real growth is a few dozen entries: a leak in principle, benign in practice **[I]**.
- `_slotLookupCache` — capped at **4096** entries with LRU-ish eviction on write (`player_queue_slots.dart:8-18` **[V]**). Bounded.
- HomeCubit category cache — **20 futures**, TTL + prune (`home_cubit.dart:116`, `:242-269` **[V]**). Bounded; cleared on login change (`:108`).
- Play history — one row per play, then `DELETE … ORDER BY played_at DESC LIMIT 500` on every insert (`music_repository.dart:1214`, `:1221-1223` **[V]**). Bounded at 500 rows.
- Queue slots / `queue_items` — unbounded by design (user-owned queue) **[V]**.

**Real risk is the sum, not any one cache [I]:** 80 MB (imageCache) + 50 MB (`ArtworkLruCache`) + 35 MB (`ArtworkCacheManager`) = **165 MB ceiling** of artwork bitmaps, three independent budgets over the same bytes, on top of a 5,000-row `SongsTableData` list. `didHaveMemoryPressure` does trim two of them (`main.dart:589-604`), but nothing reconciles the ceilings.

---

## 2. UI-ISOLATE COST (5,000-track library)

| Site | Cap / debounce | Off-isolate? | Cost at 5k |
|---|---|---|---|
| Library rating sort `library_cubit.dart:182-280` | rows capped **5000** (`:187`), pagination off in this mode (`:224`) | **No** — Dart `List.sort` + **5,000** `store.getRating()` calls on the UI isolate (`:267-285`) | ≈61 k comparisons → tens of ms per emission **[I]**; every DB re-emission re-sorts |
| Search fuzzy `search_cubit.dart:540-620` | **300 ms** debounce (`:53`), pool **500** (`:51`), results **200** raising to **500** (`:48`, `:620`) | No (≤500 rows) | negligible **[I]** — properly capped |
| Library stats sort `library_stats_screen.dart:95-135` | **none** — `getAllSongs()` unbounded (`:185`), 3 full sorts (`:112`, `:128`, `:133`) | No | memoized by list identity (`:96-100`), so once per open/range change; 5k → tens of ms **[I]**, acceptable but unbounded |
| Auto-DJ `queue_screen.dart:125` | **no limit** — `getAllSongs()` with no args → whole table | No; `buildAutoDjQueue` scores every row inside the tap handler | worst single offender **[V]**; 5k row decode + O(n) scoring on tap |
| Nested `shrinkWrap` grids | album/artist detail use `CustomScrollView` + `SliverList.builder` (`album_detail_screen.dart:184`, `:272`); remaining `shrinkWrap` are sheets over short lists (`sort_filter_sheet.dart:169`, `add_to_playlist_sheet.dart:348`) | n/a | **no nested shrinkWrap grid found** in the detail screens **[V]** |
| Per-build stream creation | **fixed** — both screens memoize `.distinct()` streams (`album_detail_screen.dart:64`; `artist_detail_screen.dart:47-49`, `:68`, `:72`) | n/a | not a defect anymore **[V]** |

Net: the two genuine frame risks are the **Auto-DJ unbounded fetch** and the **rating re-sort on every emission**; search and detail screens are already capped/memoized.

---

## 3. BATTERY / BACKGROUND

`Timer.periodic` call sites found in `lib`: **22** (brief said 24 — no 23rd/24th exists as a `Timer.periodic`; `ytm_service.dart:134` only *mentions* a removed one in a comment **[V]**). Top 5 by cost:

| # | Site | Interval | Work | Gating |
|---|---|---|---|---|
| 1 | `crossfade_manager.dart:471`, `:614` | **10 ms** | per-tick volume ramp on both players | only during an active fade; cancels on `_fadeId` change **[V]** — 100 Hz for the fade duration |
| 2 | `room_correction_sheet.dart:279` | **100 ms** | reads `player.position`, drives sweep UI | `mounted` + phase check, measurement only **[V]** |
| 3 | `headphone_safety_sheet.dart:47` | **500 ms** | `_pollTelemetry()` while the sheet is open | `mounted` only — **no visibility gate** **[V]** |
| 4 | `lyrics_editor_sheet.dart:92` | **250 ms** | position fallback when no position stream | only when `_positionSub == null` **[V]** |
| 5 | `listen_together_service.dart:651` (+`:424` 10 s ping) | **1 s** | member drift check for non-hosts | only `inParty && !_isHost` **[V]** |

Also: `audio_handler.dart:1702` 2 s DB position save (dirty-flag gated, coalesced `:1576-1578`), `dsp_telemetry_cubit.dart:73`, `download_repository_impl.dart:1120` 5 s policy watchdog (**only while a download is busy** `:1114-1120`), `downloads_cubit.dart:104` 30 s tombstone prune.

- **Foreground service:** real `audio_service` integration, `androidStopForegroundOnPause: !keepOnPause` (`audio_handler.dart:141-149`) **[V]** — so the FGS survives pause only if the user asked for it. Init has a 10 s timeout and degrades to no-notification playback (`:167-172`).
- **Wake locks:** no `wakelock`/`WakelockPlus` dependency or call anywhere in `lib` **[V, absence]** — audio focus is the only keep-alive.
- **Auth polling:** none — `auth_service.dart` has **zero** `Timer`/`periodic` matches **[V]**; auth is event/stream driven.
- **Widget progress:** throttled to **1/s** (`player_widget_coordinator.dart:126-129`; doc `widget_service.dart:285`) **[V]**.
- **Scanning in background:** tag parse runs in an isolate via `compute` (`media_scanner_service.dart:485`) **[V]**, but the scanner has **no `AppLifecycleState` gate** (no match in that file) **[V, absence]** — a scan started before backgrounding keeps competing with playback; resume path has a 15-min delta gate (`main.dart:559-577`).

---

## 4. STARTUP

`await`s before `runApp`, in order:

| # | Await | Timeout | Needed for first frame? |
|---|---|---|---|
| 1 | `AppConfig.loadInstalledVersion()` `main.dart:134` | **2 s** (`:135`) | No — version is read by Settings/About & updater; deferrable |
| 2 | `SettingsCache().init()` `:142` | **none** | **Yes** — theme/settings seed the first painted shell |
| 3 | `SharedPreferences.getInstance()` + `EqLegacyMigration.run(prefs)` `:152-154` | **none** | Prefs: needed by `GpuBudget`; migration: **no** — deferrable |
| 4 | `Firebase.initializeApp()` `:171` | **3 s** (`:174`) | No — Auth inits post-frame (`:230`) |
| 5 | `configureDependencies(warmUpAsync: false)` `:193` | **15 s** (`:194`) | **Yes** — router needs `MediaScannerService` |
| 6 | `SentryFlutter.init(..., appRunner:)` `:363` | **none** | No — but it *wraps* `runApp` (`:401-404`) |

Unawaited (correct): `ArtworkCacheManager().init()` `:144`, `SoundFeedbackService.init()` `:148`, `PlatformCapabilities.ensureLoaded()` 5 s `:162`.

**Sequential worst case:** 2 + 3 + 15 = **20 s** bounded, **plus** two unbounded awaits (`SettingsCache.init`, prefs+EQ migration) and unbounded `SentryFlutter.init` → no hard upper bound **[I]**. Typical ~0.5–1.5 s **[I, not measured]**.

**DI eager work:** `getIt.init()` constructs **~40 `gh.singleton<…>` instances synchronously** before first frame (`injection.config.dart:124-362`) **[V]** — use cases are cheap, but `AppDatabase` (`:151`) and `SettingsCubit` (`:323`) are not free: the DB opener itself is lazy (`driftDatabase(name:)`, `app_database.dart:133`) **[V]**, while `SettingsCubit`'s constructor fires `_loadPreferences()` (`settings_cubit.dart:233`) — a second, unserialized prefs read racing `SettingsCache.init()` [`I`, from ordering]. `configureDependencies(warmUpAsync:false)` correctly skips the 12 s audio warm-up (`injection.dart:56-63`) and the shell shows a bootstrap screen until `appDependenciesReady` (`injection.dart:187-200`).

---

## Scores

| Axis | Score | One-line basis |
|---|---|---|
| Memory | **7/10** | Every cache capped; 165 MB aggregate art ceiling + unbounded weak-key map |
| CPU-Frame | **6/10** | Search/detail clean; Auto-DJ unbounded + rating re-sort on UI isolate |
| Battery | **6/10** | No wakelocks, no auth poll, FGS correct; 100 Hz fade ticks, 500 ms sheet poll |
| Network-Disk | **7/10** | Artwork disk LRU off-isolate, 90 % target, 20-put cadence; HQ fetch up to 10 MB, no per-host budget |
| **Resource Control** | **6.5/10** | Discipline is real and documented; the gaps are specific, not systemic |

## 6 fixes

1. **S** — Drop `ArtworkCacheManager._maxMemoryBytes` 35 MB → 20 MB and delete the duplicate `ArtworkLruCache` strong tier (`cached_artwork.dart:22`): one byte budget, not three.
2. **S** — Move `_sortByRating` (`library_cubit.dart:267`) to `compute()` (or add a `rating` column so SQL sorts): removes the 5k-comparison re-sort per emission.
3. **M** — `queue_screen.dart:125`: pass `limit: 1500` to `getAllSongs()` and score candidates in an isolate; cap Auto-DJ input instead of materializing the library on tap.
4. **S** — `main.dart`: move `Firebase.initializeApp` (3 s) and `EqLegacyMigration.run` behind `firePostStartupTasks()`, and give `SettingsCache().init()` a 1.5 s timeout — removes ~3 s + one unbounded await from the pre-frame path.
5. **M** — Gate `MediaScannerService` on `AppLifecycleState`: pause between chunks when `paused`/`hidden`, resume on `resumed` (today the isolate parse has no lifecycle awareness, `media_scanner_service.dart:485`).
6. **M** — `headphone_safety_sheet.dart:47`: 500 ms → 1 s and stop polling when `WidgetsBinding.instance.lifecycleState != resumed`; the same lifecycle gate applied to `exclusive_usb_chip.dart:59` and `dsp_inspector_sheet.dart:75`.
