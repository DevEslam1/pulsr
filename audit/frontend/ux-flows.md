# UX Flows & State Coverage Audit — Pulsr (Flutter)

**Date:** 2026-11-18
**Repo:** `D:\Courses\Projectss\pulsr` (827 Dart files under `lib/`, 44 `*_screen.dart`)
**Mode:** static, read-only audit. No app was run; every claim below is traceable to a `file:line` in this repo.
**Feature folders found:** 37 under `lib/features` (brief says 38 — see Appendix A1).

---

## 0. Scope, method, and what this audit cannot see

**Read in full before touching features:** `lib/core/widgets/async_state_builder.dart`, `pulsr_empty_state.dart`, `shimmer_skeleton.dart`, `pulsr_toast.dart`, `pulsr_error_boundary.dart`, `pulsr_dialog.dart`, `pulsr_page_pop_scope.dart`, `lib/core/router/app_router.dart`, `lib/features/shell/presentation/app_shell.dart`, `nav_destinations.dart`, `bottom_nav_bar.dart`.

**Method.**
1. Counted the design-system primitives with `rg` per feature (`AsyncStateBuilder`, `Skeleton*`, `PulsrEmptyState`, `RefreshIndicator`, `showSnackBar`, `PulsrToast.show`, `showConfirmDialog`).
2. Read the ten in-scope screens end-to-end (player, home, library, search, queue, settings, downloads, onboarding, party, ytm_browse) plus eleven detail/adjacent screens (album, artist, playlist_detail, playlists, genre, folder, year, radio, tag_editor, quran_mode, ytm_search).
3. Every score row carries at least one `file:line`. Anything not read is marked **unverified**, not inferred.

**Deliberately out of scope:** visual/RTL quality, animation timing correctness, a11y screen-reader output, performance, l10n copy quality beyond structure. These need a running build and were not verified.

---

## 1. Score table

| # | Dimension | Score | Why (key evidence) |
| :- | :--- | :---: | :--- |
| 1 | **State coverage** (loading / empty / error / refresh / partial) | **7 / 10** | The contract is explicit and mostly honored for lists: `AsyncStateBuilder` renders waiting/error/empty/data in one place and even treats a `Left` failure payload as an error (`async_state_builder.dart:45-59`), and `DESIGN.md:290-296` forbids bare spinners for content. But only **9 of 53** files that use `StreamBuilder`/`BlocBuilder`/`FutureBuilder` adopt it, the library collapses failures into "no songs", and no screen outside `ytm_browse` has a partial/offline state. |
| 2 | **First-run & permissions** | **6 / 10** | Real work exists: splash timeout + Retry (`splash_screen.dart:43-56`, `:121`), 5-page onboarding with skip-to-last, `1 / 5` pill and tappable dots (`onboarding_screen.dart:312-318`, `:404-440`), a storage-denial dialog with *Continue limited access* / *Open settings* (`:214-245`). Missing: no resume of onboarding position, no scan progress (scanner exposes one — `empty_library.dart:117-122`), no battery-optimization step, no way to replay onboarding. |
| 3 | **Navigation IA** | **7 / 10** | 5 shell tabs + 41 `GoRoute` declarations; Queue/Downloads/Radio/Favorites are **1 tap** from the Home chip row (`quick_discovery_header.dart:44-82`); settings has 7 categories, its own search and section deep links (`category_metadata.dart:3-11`, `app_router.dart:487-505`); ~27-action command palette with full keyboard nav (`command_palette_sheet.dart:418-434`). Against that: **Party has no route and no Settings/palette entry** (only player `⋮` → `player_more_sheet.dart:103-108`), and route restoration is declared but inert (`app_router.dart:333` vs **0** `restorationId` in `lib/`). |
| 4 | **Destructive safety** | **8 / 10** | 27 `showConfirmDialog` sites; the three highest-blast-radius actions have confirm **and** undo (clear queue `queue_screen.dart:76-105`; delete playlist `playlists_screen.dart:360-410`; remove-from-playlist `song_options_sheet.dart:199-235`). File deletion always confirms with a count (`library_screen.dart:1335-1375`, `downloads_screen.dart:721-745`, `duplicate_finder_screen.dart:347-366`). Deductions are copy-level: cache clears confirm with the literal string "Confirm" (`storage_cache_section.dart:299`, `:355`), and playlist delete says "cannot be undone" while offering Undo (`playlists_screen.dart:358` vs `:403`). |
| 5 | **Feedback & toasts** | **6 / 10** | `PulsrToast` is genuinely well-built — dedupe of identical messages (`pulsr_toast.dart:88-96`), dock/keyboard/modal-aware offset (`:328-380`), a11y live region (`:500`), action button with extended dwell. But it is the **minority** channel: 106 `PulsrToast.show` calls vs **205** raw `ScaffoldMessenger…showSnackBar` calls in `lib/features`, and the queue emits a toast+Undo on every reorder (`queue_screen.dart:466-487`). |
| 6 | **Search UX** | **8 / 10** | 300 ms query debounce (`search_cubit.dart:58`), 180 ms suggestion debounce with stale-response guard (`search_screen.dart:207-221`), persisted recents with dedupe/cap and per-item delete (`search_cubit.dart:439-465`), no-results with a *Clear search* CTA (`:1399-1405`), keyboard dismissal on drag (`:1426`), persisted Local/Online scope (`source_scope_switcher.dart:52-88`), and stale results kept while refining (`:1389`). Missing: no typo tolerance, suggestions are prefix-only over history+local entities, clear-history has no confirm (`:995-999`). |
| 7 | **Consistency of chrome** | **7 / 10** | Strong navigation discipline: 76 `PulsrSheetHelper` vs 3 raw `showModalBottomSheet`, and only 2 raw `MaterialPageRoute` in `lib/features`. Dialogs all route through `PulsrDialogHelper`, which also registers modal state for the dock (`pulsr_dialog.dart:62-92`). Deductions: the dual notification chrome above, two refresh implementations (31 raw `RefreshIndicator` vs 6 `PulsrRefreshIndicator`), and five content surfaces that break the "never a bare spinner" rule (see F3). |

**Composite: 49 / 70.** Median quality is high; the gaps cluster in *failure and offline paths*, not in the happy path.

---

## 2. Per-feature state coverage

Legend: **✓** implemented · **~** partial/weak · **—** absent · **n/a** no async surface · **?** not read (spot-check only).

### 2.1 Fully audited

| Feature | Load | Empty | Error + retry | Refresh / partial | Offline | Evidence |
| :--- | :---: | :---: | :---: | :---: | :---: | :--- |
| `player` | ✓ | n/a | ✓ | n/a | ~ | Mini player has a full-width error state with throttled retry (`mini_player.dart:1716-1770`, `:95`). The full-screen themes read `state.currentSong` with no explicit no-track branch (`player_theme_scaffold.dart:392-394`); now-playing is normally only reachable with a track, so a deep link into an empty queue is **unverified**. |
| `home` | ✓ | ✓ | ~ | ✓ | ~ | Per-section `StreamBuilder` + skeleton + `SectionError` + empty (`recently_played_section.dart:143-219`); page-level `RefreshIndicator` rescans on local tab (`home_screen.dart:334-352`). Error copy is generic "library load failed" even for online sections (`section_error.dart:40`). Quick-action failures are toasts, not states (`home_screen.dart:163-190`). |
| `library` | ✓ | ✓ | **—** | ✓ | ~ | Skeleton list + load-more (`library_songs_tab.dart:66-95`), empty with scan CTA (`library_screen.dart:1756-1795`). **A query failure renders as the empty state after a 4 s toast** (`library_screen.dart:640-669`). Refresh = full rescan (`library_songs_tab.dart:448-452`). |
| `search` | ✓ | ✓ | ✓ | ✓ | ~ | Skeleton (`search_screen.dart:1389`), error with retry (`:1394-1400`), no-results with clear CTA (`:1399-1405`), results retained while loading; online tab has a dedicated offline-only empty (`:2229-2232`). |
| `queue` | **—** | ✓ | **—** | n/a | n/a | Empty state (`queue_screen.dart:314-320`), reorder + undo, clear confirm + undo. No loading skeleton and no surfacing of a failed queue restore (`restoreQueueSlots` swallows decode failures — `player_queue_slots.dart:61-79`). |
| `settings` | n/a | n/a | ✓ | n/a | n/a | Settings hydrate from prefs before the first frame; errors surface as a floating SnackBar (`settings_screen.dart:213-235`), not the design-system toast. |
| `downloads` | ✓ | ✓ | ✓ | ✓ | **—** | Skeleton (`downloads_screen.dart:318-322`), filter-aware empty with CTA (`:462-486`), error toast + retry surfaces, pull-to-refresh (`:604-640`). No WiFi/offline gate state despite `wifiOnlyMode`. |
| `onboarding` | ~ | n/a | ~ | n/a | n/a | CTA shows an inline spinner while granting (`onboarding_screen.dart:561-580`); scan failure is a SnackBar only (`:209-220`); no scan progress. |
| `party` | ~ | **—** | ~ | n/a | ~ | `LinearProgressIndicator` while connecting and an inline error string (`party_sheet.dart:202-214`); join/create buttons carry busy state (`:389`). No skeleton, no retry action, no "room is empty" state. |
| `ytm_browse` | ✓ | ✓ | ✓ | ✓ | ~ | The best screen in the app for state work: skeleton, full error with retry, empty, **and a non-blocking "stale feed" strip when a refresh fails** (`ytm_browse_screen.dart:191-215`, `:877-930`). |
| `ytm_search` | ✓ | ✓ | ✓ | ✓ | ✓ | Skeleton (`ytm_search_screen.dart:415-417`), error with retry (`:419-430`), no-results, load-more failure slot, and an offline-only empty state. |

### 2.2 Detail & adjacent screens (read)

| Feature | Load | Empty | Error + retry | Refresh | Offline | Evidence |
| :--- | :---: | :---: | :---: | :---: | :---: | :--- |
| `album_detail` | ✓ | ✓ | ✓ | ✓ | — | Structured skeleton (`album_detail_screen.dart:1084-1110`), `_AlbumErrorView` with retry (`:466-477`, `:1122-1148`), empty (`:1019`). |
| `artist_detail` | ✓ | ✓ | ✓ | — | — | 3× `AsyncStateBuilder` (biography, albums, songs) with skeletons and retries (`artist_detail_screen.dart:155-166`, `:289-297`, `:384-392`). |
| `playlist_detail` | ✓ | ✓ | ✓ | ✓ | ~ | 3 skeletons, 7 empty variants, error with retry; offline badge copy exists but no offline data state. |
| `playlists` | ✓ | ✓ | ✓ | ✓ | ~ | `SkeletonGrid` (`playlists_screen.dart:852-860`), error empty (`:863-870`), 19 toasts. |
| `genre_detail` | ✓ | ✓ | ✓ | — | — | `AsyncStateBuilder` + skeleton in the loading widget + explicit `errorView` (`genre_detail_screen.dart:204-261`). |
| `folder_detail` | ✓ | ✓ | ✓ | — | — | `AsyncStateBuilder` with `errorView` and empty content (`folder_detail_screen.dart:1671-1682`). |
| `year_detail` | ✓ | ✓ | ✓ | — | — | Same shape (`year_detail_screen.dart:229-253`). |
| `radio` | ~ | ✓ | ✓ | ✓ | — | **Bare centered spinner** while loading (`radio_screen.dart:1066`), then error empty with pull-to-refresh (`:1072-1100`) and empty (`:1136`). |
| `tag_editor` | ~ | — | ~ | — | — | **Bare centered spinner** (`tag_editor_screen.dart:285-286`); save/load errors are error-colored SnackBars (`:171-183`, `:254-266`). |
| `quran_mode` | n/a | — | ~ | n/a | n/a | The screen is a 38-line wrapper around `QuranModePanel` (`quran_mode_screen.dart:15-33`); errors come from `QuranErrorCard` with retry (`quran_error_card.dart:12-46`). |
| `playlist_detail` (online) | ✓ | ✓ | ✓ | ✓ | ~ | Skeleton + error empty + 7 toasts (`online_playlist_detail_screen.dart`). |

### 2.3 Spot-checked (grep-level only)

| Feature | Verdict | Note |
| :--- | :--- | :--- |
| `audio_profiles` | solid | Branded indeterminate `PulsrProgressBar` (`audio_profiles_screen.dart:377-382`), error empty with retry (`:384-392`), empty (`:393+`). |
| `diagnostics` | solid | `PulsrProgressBar` then error empty with retry (`diagnostics_screen.dart:277-292`). |
| `remote_sources` | adequate | `PulsrProgressBar` (`remote_sources_screen.dart:383-387`); failures are SnackBars (`:108`), no persistent error state. |
| `usb_tools` | adequate | 2 px progress bar + "no device" empty with refresh (`usb_ergonomics_screen.dart:208-220`). |
| `dlna` | adequate | Own state machine with an error banner + retry copy (`dlna_strings.dart:64-68`); not verified on device. |
| `smart_playlist_builder` | adequate | Static rule editor; save errors only (`smart_playlist_builder_screen.dart`, 3 error sites), no loading/empty needed. |
| `auth` | **weak** | No skeleton; a bare spinner while the login sheet loads (`ytm_oauth_login_sheet.dart:259`); errors handled in-cubit with copy (`auth_cubit.dart:274`). |
| `splash` | adequate | Branded splash, 8 s timeout, Retry (`splash_screen.dart:43-56`, `:121`). No progress semantics. |
| `shell` | adequate | Global player-error listener → toast (`app_shell.dart:300-316`); download effects forced to `isError: true` (`:84-92`) — currently correct because both emitters are failures (`ytm_download_cubit.dart:273`, `:286`). |
| `command_palette` | solid | Empty-query and no-match states, keyboard nav (`command_palette_sheet.dart:459-520`). |
| `sheets` | mixed | `add_to_playlist_sheet` uses `AsyncStateBuilder` for its playlist list; feedback is SnackBar after `Navigator.pop` (`add_to_playlist_sheet.dart:125-141`). |
| `extras`, `announcements`, `system_behavior` | n/a | Static navigation/content screens; no async surface. |
| `assistant` | n/a | Non-UI intent surface (`assistant_intent_bootstrap.dart`) — no screens. |
| `widgets` | n/a | Home-screen widget plumbing, not a UI surface. |

---

## 3. Findings

### 3.1 State coverage

**F1 — The four-state contract is written down and implemented, but adopted by 9 of 53 async files.**
`DESIGN.md:290-296` requires skeleton loading, `PulsrEmptyState` empty, `PulsrEmptyState` + Retry error, and staged content. `AsyncStateBuilder` implements exactly that, including the non-obvious case where a repository failure arrives as a `Left` *value*:

```dart
// async_state_builder.dart:56-59
final leftFailure = _leftFailureOf(data);
if (leftFailure != null) {
  return onError?.call(leftFailure) ?? _AsyncErrorCard(error: leftFailure, onRetry: onRetry);
}
```

`rg -l AsyncStateBuilder lib/features` → 9 files: album/artist/folder/genre/year detail, playlist_detail, recents, `add_to_playlist_sheet`, `online_category_section`. Everything else hand-rolls its branches. That is why quality is uneven rather than uniformly high.

**F2 — Library converts a failure into "No songs found" + a Scan CTA.**
`library_screen.dart:640-669` shows the failure as a 4 s SnackBar and calls `clearError()`; the tab then falls through to the empty branch:

```dart
// library_songs_tab.dart:64-78 (abridged)
if (songs.isEmpty) {
  if (state.isLoading) { return SkeletonList(...); }
  return _buildEmpty(context, title: context.l10n.noSongsFound, ...);
}
```

`_buildEmpty` (`library_screen.dart:1756-1795`) defaults its primary action to **Scan storage**. So a failed DB stream produces a screen that tells the user their library is empty and offers to rescan — the single most misleading state in the app, and the one users are most likely to see after a storage/permission problem.

**F3 — Five content surfaces still use a bare centered spinner.**
`radio_screen.dart:1066`, `tag_editor_screen.dart:285-286`, `ytm_oauth_login_sheet.dart:259`, `scrobbler_settings_modal.dart:165-169`, `eq_sheet_shell.dart:3216`. This is a direct violation of `DESIGN.md:290-292` ("Never a bare `CircularProgressIndicator` for *content* loading"). Note the counter-pattern that already exists and should be the default: `diagnostics`, `audio_profiles`, `remote_sources`, `usb_tools` all use the branded `PulsrProgressBar` for non-list surfaces.

**F4 — Offline is a mode toggle, not a state.**
`NetworkChangeMonitor` is constructed only for cloud sync (`main.dart:521`, `:988-992`). Connectivity failures are mapped to copy at render time (`error_message_resolver.dart:115-116`), never to a persistent offline state with retry-on-reconnect. Only three surfaces acknowledge offline structurally: Home's `offlineOnlyMode` notice (`home_screen.dart:406-420`, `:545-560`), search's online-tab empty (`search_screen.dart:2229-2232`), and party's connection state (`party_sheet.dart:216-229`). Downloads, YTM browse, and every detail screen have no offline concept.

**F5 — Partial-refresh is essentially a single-screen feature.**
Only `ytm_browse` renders stale content with a failure strip (`ytm_browse_screen.dart:877-930`). Search approximates it by only showing the skeleton when results are empty (`search_screen.dart:1389`), but it has no indication that the visible results are stale.

**F6 — The design-system error boundary is dead code.**
`PulsrErrorBoundary` (`pulsr_error_boundary.dart`) has **zero** references in `lib/` — only in `test/` (`p3_bug_fixes_test.dart:25`, `phase_1_components_test.dart:97`, `pulsr_error_boundary_test.dart:38`). The production fallback in `main.dart:151-169` is a bare centered `Text`:

```dart
// main.dart:158-167
return Builder(builder: (context) => Material(
  color: AppColors.card,
  child: Center(child: Text(AppLocalizations.of(context)?.somethingWentWrong ?? 'Error', ...
```

A build error in any subtree therefore yields a white-on-dark "Something went wrong" with no retry, no navigation escape, and no telemetry-visible retry path — even though a fully-featured boundary with retry exists one import away.

**F7 — Queue has no failure path.**
`queue_screen.dart` renders from in-memory `PlayerState`; the persisted queue restore silently returns on a corrupt payload (`player_queue_slots.dart:64-79`). The user sees an empty queue with no explanation and no retry.

### 3.2 First run: splash → onboarding → ready

**F8 — Splash is patient but opaque.** 8 s wait on `initializationReady` (`splash_screen.dart:43-44`), then a Retry button only if `!getIt.allReadySync()` (`:55-58`, `:121-140`). Nothing is shown while waiting: no progress text, no "still starting" hint before the timeout.

**F9 — Onboarding has skip and progress but no resume.**
5 pages, `1 / 5` pill, tappable dots, and *Skip* that animates to the last page (`onboarding_screen.dart:312-318`, `:404-440`, `:421`). But `_currentPage` is never persisted; `onboarding_completed` is written only at the very end (`:266-270`). Killing the app on page 3 restarts at page 1. There is also no entry point to replay onboarding (no `onboarding` reference anywhere in `lib/features/settings`).

**F10 — The onboarding scan has no progress, though the scanner already emits one.**
`_scanLibrary` just awaits the scan (`onboarding_screen.dart:206-209`). `EmptyLibrary` demonstrates the available API and the correct UI:

```dart
// empty_library.dart:121-122
_progressSub = scanner.scanProgress.listen((p) {
  if (mounted) setState(() => _scanProgress = p);
});
```

and renders percent + determinate bar at `:166-190`. Onboarding blocks on the same call with only a 22 px button spinner. On a 5k-track library this is the longest silent wait in the product.

**F11 — Battery optimization is never requested at first run.**
`BatteryOptimizationService` is surfaced only by the settings card (`battery_optimization_card.dart:54`). For an app whose headline feature is background downloads and a foreground playback service, omitting this from onboarding is a functional gap, not a polish one.

**F12 — Denial path is not a dead end.** Storage denial opens a dialog with *Continue limited access* and *Open settings* (`onboarding_screen.dart:220-245`); barrier dismissal keeps the page usable. Notification denial persists a flag and shows a dismissible Home banner with a Settings deep link (`home_screen.dart:469-520`). The one rough edge: after *Open settings* the app does not re-check the OS status on return (only the notification path does, `:170-185`).

**Dead ends found:** none that trap the user. The bad paths are *silent* (F8, F10) rather than blocking.

### 3.3 Navigation IA

**Tabs and reachability** (`nav_destinations.dart:96-128` → Home, Library, Search, Playlists, Settings):

| Destination | Taps from a cold tab | Path | Deep-linkable |
| :--- | :---: | :--- | :--- |
| Queue | **1** (Home chip) / 2 (mini player → Now Playing → queue) | `quick_discovery_header.dart:77-80`; `now_playing_queue_view.dart:21` | yes, `/queue` |
| Downloads | **1** (Home chip, YTM builds) / 3 (Settings → online → Downloads) | `quick_discovery_header.dart:51-56`, `online_section.dart:136` | yes, `/downloads` |
| Radio | **1** | `quick_discovery_header.dart:72-75` | yes, `/radio` |
| Favorites | 1 (Home quick card) / 2 | `home_screen.dart:742-746` | yes, `/favorites` |
| **Party** | **3** (song long-press → Info → Listen Together, or mini player → ⋮ → Party) | `song_info_sheet.dart:558`; `player_more_sheet.dart:103-108` | **no route at all** |
| **Quran Mode** | **2–3** (Settings → Sound → Quran section) or 3 via player ⋮ | `settings_category_widgets_section.dart:115-131`; `player_more_sheet.dart:114-121` | yes, `/quran-mode` |
| Settings | 1 | tab 5 | `/settings?category=&section=` |
| Smart playlist builder | 2 (Playlists → create) | `app_router.dart:613-624` | yes |

**F13 — Party is the one truly buried feature.** `rg -i party lib/features/settings` → **0 hits**; `rg -i party lib/features/command_palette` → **0 hits**; `rg "'/party'"` → **0 hits**. It exists only as a bottom sheet launched from three player/song surfaces. It is also the feature with the most complex state (host/member, sync, reconnect) and therefore the one that most needs a stable, linkable surface.

**F14 — The command palette is excellent and hidden.** ~27 actions (`CommandPaletteItem(` ×28 minus its declaration), arrow/enter/escape handling (`command_palette_sheet.dart:418-434`), opened by long-pressing the **Search** tab (`bottom_nav_bar.dart:91-94`) or Ctrl/Cmd-K on desktop (`player_shortcut_scope.dart:174-177`). No first-run hint mentions either gesture; the only discovery path is the desktop shortcut help sheet. Quran radio is in the palette (`command_palette_sheet.dart:171`); Party is not.

**F15 — Restoration is declared but inert.** Both scopes are set (`app_router.dart:333` `restorationScopeId: 'pulsr-router'`; `main.dart:1372` `restorationScopeId: 'pulsr'`), yet `rg -o restorationId lib` → **0**. All pages are `CustomTransitionPage` with no `restorationId`, so the navigator stack cannot be restored; only 7 `PageStorageKey`s preserve in-session scroll offsets. Playback/queue *data* does persist (`player_queue_slots.dart:61+`), which makes the gap less visible but doesn't restore the route the user was on.

**F16 — Predictive back is suppressed.** `android:enableOnBackInvokedCallback="true"` (`AndroidManifest.xml:49`, `:72`) but 34 `PopScope` wrappers and `PulsrPagePopScope` hard-code `canPop: false` (`pulsr_page_pop_scope.dart:21`), so Android 14+ never plays the back-preview animation. Back still *works* — the shell has a careful tab-history implementation with a 50-entry cap and double-back-to-exit (`app_shell.dart:190-270`) — but the gesture feels non-native on modern Android.

**F17 — Settings is dense, not a junk drawer — with one caveat.** 58 files / ~29.6k LOC (`lib/features/settings`), but organized into 7 categories with live subtitles (`category_metadata.dart:3-11`, `:34-86`), a phone filter bar, tablet master-detail, and its own search. The caveat: the search index is a **hand-curated list of 50 `_SearchItem`s** (`search_results_section.dart`), not derived from the widget tree, so a toggle absent from that list is unfindable by search. Coverage completeness is **unverified** without enumerating all ~100 controls.

### 3.4 Destructive actions: confirm vs immediate

| Action | Confirm | Undo | Evidence |
| :--- | :---: | :---: | :--- |
| Clear queue | ✓ | ✓ | `queue_screen.dart:76-105` |
| Delete playlist (list) | ✓ | ✓ | `playlists_screen.dart:360-410` |
| Delete playlist (detail) | ✓ | — | `playlist_detail_screen.dart:1199-1210` |
| Remove song from playlist | — | ✓ | `song_options_sheet.dart:199-235` |
| Delete song(s) from library (multi-select) | ✓ | — | `library_screen.dart:1335-1375` |
| Delete downloaded file (single) | ✓ | — | `download_tile.dart:274-283` |
| Delete selected downloads | ✓ | — | `downloads_screen.dart:721-745` |
| Clear completed downloads | ✓ | — | `downloads_screen.dart:860-878` |
| Delete duplicate songs | ✓ | — | `duplicate_finder_screen.dart:347-366` |
| Clear play history | ✓ | — | `recents_screen.dart:118-126`; `library_stats_screen.dart:205-213` |
| Clear caches | ✓ (weak copy) | — | `storage_cache_section.dart:296-304`, `:352-359` |
| Clear search history | **—** | — | `search_screen.dart:995-999` |
| Restore backup (overwrites) | ✓ + description | — | `backup_section.dart:155-196` |

**Count: 13 destructive surfaces; 11 confirm, 2 rely on undo or nothing; 3 offer undo.** There is **no** library-wipe/factory-reset affordance anywhere (`rg "resetAll|clearDatabase|wipe"` in settings/extras → no UI hits), which is the right call.

**F18 — Cache-clear confirmations carry no information.** Both dialogs pass the generic confirm string as body:

```dart
// storage_cache_section.dart:296-302
final confirmed = await PulsrDialogHelper.showConfirmDialog(
  context,
  title: context.l10n.clear,
  message: context.l10n.confirm,   // <- renders "Confirm"
  confirmLabel: context.l10n.clear,
  isDestructive: true,
);
```

No size, no item count, no "covers/artwork only". Spotify/Plexamp-tier dialogs name the object and the consequence.

**F19 — Contradictory copy around undo.** `playlists_screen.dart:358` sets `deleteMessage = context.l10n.browseCannotBeUndone`, then the success toast at `:400-410` offers **Undo**. Same string at `:1133` for custom online playlists. One of the two is wrong; users who read "cannot be undone" won't look for the undo.

**F20 — Clear search history is the only unconfirmed destructive action** (`search_screen.dart:995-999`), while the structurally identical "clear listening history" two tabs away does confirm (`recents_screen.dart:118-126`).

### 3.5 Feedback loops

**F21 — Two notification chromes compete, and the raw one is twice as common.**
Measured in `lib/features`: `PulsrToast.show` = **106**, `ScaffoldMessenger…showSnackBar` = **205**. `PulsrToast` exists precisely to solve a layout problem the SnackBar ignores — it computes an offset above the mini player/dock, keyboard, and modals:

```dart
// pulsr_toast.dart:328-341
double _calculateBottomOffset(BuildContext context) {
  if (widget.customBottomOffset != null) return widget.customBottomOffset!;
  ...
  if (keyboardInset > 0) return keyboardInset + 14.0;
```

Because `AppShell` renders the dock and mini player as a `Stack` overlay inside the body (`app_shell.dart:380-410`), a `SnackBar` sits at the Scaffold's bottom edge — the same band the floating dock occupies — instead of floating above it the way `PulsrToast` is designed to (layout read, not device-verified; see A3). Users therefore see two different notification designs depending on which screen triggered them (`tag_editor`, `settings`, `library`, `home`, `onboarding`, `eq_preset_carousel`, `lyrics_view` all use SnackBar).

**F22 — Queue reorder toasts on every drag.** `queue_screen.dart:466-487` shows `queueReordered` + Undo after each `onReorderItem`. Reordering is continuous and self-evident; this is the clearest case of feedback spam in the app.

**F23 — "Empty" delivered as a transient toast.** Focus Flow with no play history fires a SnackBar (`home_screen.dart:177-190`) instead of an inline empty state, so the explanation disappears after a few seconds and leaves the user on a blank card.

**F24 — Success toasts fired from a popped context.** `add_to_playlist_sheet.dart:125-141` and `scrobbler_settings_modal.dart:151-156` call `Navigator.pop(context)` and then `ScaffoldMessenger.of(context)` on the same context. It currently resolves (the element is still active during the pop animation), but it is one refactor away from throwing or attaching to a deactivated route; both should capture the messenger before popping (the pattern the queue screen already uses at `queue_screen.dart:468-470`).

**Confirmed-good loops:** download cancel offers Retry (`download_tile.dart:237-242`); delete reports "Song deleted" (`:285-290`); playlist add names the playlist and count (`add_to_playlist_sheet.dart:136-139`); party join flips the sheet into the in-party view (`party_sheet.dart:236-238`, `:407`) and copy-share confirms with a success toast (`:132`); scrobble save confirms (`scrobbler_settings_modal.dart:151-156`).

### 3.6 Search UX

**F25 — Strong core.** 300 ms query debounce with `isDebouncing` surfaced to the UI (`search_cubit.dart:58`, `:89-91`), 180 ms suggestion timer that discards stale responses by re-checking the controller text (`search_screen.dart:207-221`), recents that record only committed queries (dedupe, cap, min length 2 — `search_cubit.dart:439-465`), per-item removal and clear-all (`search_screen.dart:982-1003`), keyboard dismissal on drag (`:1426`), scope switch persisted per surface (`source_scope_switcher.dart:52-88`), and scope-aware suggestions that respect hidden folders (`search_cubit.dart:408-412`).

**F26 — Gaps.** Suggestions are prefix-only (`startsWith`, `search_cubit.dart:405`) over history + local entities; no online suggestions even in the Online scope; no typo tolerance ("beatls" → nothing). Clear-history has no confirm/undo (F20). Scope semantics are per-tab rather than per-query, so switching scope re-runs the query immediately (`search_screen.dart:296-305`) — good — but the tab label "All" vs "Local" vs "Online" is the only signal of where results come from.

### 3.7 Chrome consistency

**F27 — Navigation chrome is disciplined.** 76 `PulsrSheetHelper` vs 3 raw `showModalBottomSheet`; 2 raw `MaterialPageRoute` (`extras_screen.dart:444`, `settings_category_widgets_section.dart:245`); one dialog helper that also feeds the modal tracker (`pulsr_dialog.dart:62-92`); a single page-transition builder (`app_router.dart:60-128`).

**F28 — Two refresh implementations.** 31 raw `RefreshIndicator` vs 6 `PulsrRefreshIndicator`; they differ in color/background handling and pull physics, so the same gesture looks different between Library and Search.

**F29 — Two progress idioms.** Branded `PulsrProgressBar`/skeletons coexist with 5 bare `CircularProgressIndicator` content states (F3), which reads as unfinished rather than stylistically varied.

---

## 4. Top gaps (max 8)

1. **Error states collapse into empty states.** Library (F2) is the worst case; `SectionError`'s "library load failed" copy on online sections (`section_error.dart:40`) is the same class of bug. No persistent, retryable failure surface for the app's primary data.
2. **No offline or stale state.** Only `ytm_browse` distinguishes "refresh failed but here's what I have" (F5); nothing retries on reconnect (F4).
3. **Two notification chromes.** 205 raw SnackBars bypass the dock-aware toast (F21), and the queue toasts on every reorder (F22).
4. **Party is undiscoverable.** No route, no Settings entry, no palette action, no deep link (F13) — for the app's flagship social feature.
5. **Route-level restoration is declared but inert** (F15), and predictive back is suppressed (F16).
6. **First-run quality:** no onboarding resume, no scan progress, no battery-optimization step (F9–F11).
7. **Crash fallback is a bare text label** and the rich error boundary is unused (F6), while 5 screens still show bare spinners (F3).
8. **Weak/contradictory destructive confirmation copy** — contentless cache confirms, "cannot be undone" + Undo, unconfirmed search-history clear (F18–F20).

---

## 5. Path to 10 / 10

### P0 — Do first (small diffs, user-visible correctness)

**P0-1 · Persistent library error state**
- Files: `lib/features/library/presentation/tabs/library_songs_tab.dart:64-80`, `lib/features/library/presentation/library_screen.dart:640-669`, `:1756-1795`.
- Change: before the empty branch, test `state.errorMessage != null && songs.isEmpty` and return `PulsrEmptyState(icon: error_outline, title: somethingWentWrong, subtitle: resolveUiErrorMessage(...), primaryActionLabel: retry, onPrimaryAction: () => cubit.init())`. Use `LibraryCubit.init()` (re-subscribe, `library_cubit.dart:95`) rather than the existing `_handleRefresh`, which runs a full storage rescan (`library_screen.dart:1739-1745`). Keep the toast for non-fatal refreshes only, and add the same error variant to the albums/artists/folders tabs.
- Acceptance: forcing the songs stream to fail shows the error card, **not** "No songs found"; tapping Retry re-subscribes and repopulates without an app restart and **without** a disk rescan; no "Scan storage" CTA on a failure.

**P0-2 · Wire the error boundary + a recoverable global fallback**
- Files: `lib/core/widgets/pulsr_error_boundary.dart`, `lib/main.dart:151-169`, `lib/features/shell/presentation/app_shell.dart` (wrap `widget.navigationShell`), `lib/features/player/presentation/now_playing_screen.dart` (wrap the theme widget).
- Change: wrap each shell branch and Now Playing in `PulsrErrorBoundary(category: ..., onRetry: ...)`; replace the global `ErrorWidget.builder` body with the same boundary-styled fallback (a `Builder` that offers Retry by bumping a key).
- Acceptance: a widget that throws inside Home/Library/Player renders the branded retry card; Retry re-renders that subtree; the rest of the shell (dock, mini player) stays alive; a widget test asserts the boundary is in the tree.

**P0-3 · Truthful destructive copy**
- Files: `lib/features/settings/presentation/widgets/storage_cache_section.dart:296-304`, `:352-359`; `lib/features/playlists/presentation/playlists_screen.dart:358`, `:1133`.
- Change: pass real bodies — cache size and scope ("Clears 412 MB of artwork and stream cache. Playlists and downloads are kept.") — and pick one policy for playlist delete: either remove the Undo, or change `browseCannotBeUndone` to "You can undo this for a few seconds."
- Acceptance: no confirm dialog body is a bare "Confirm"; the playlist dialog and its toast never disagree about undo.

**P0-4 · Give Party a home**
- Files: new `lib/features/party/presentation/party_screen.dart` (reuse `PartySheet`'s body), `lib/core/router/app_router.dart` (add `/party`), `lib/features/home/presentation/widgets/quick_discovery_header.dart` (chip, gated the same way the existing `AppConfig.ytmEnabled` chips are), `lib/features/settings/presentation/sections/search_results_section.dart` (search entry), `lib/features/command_palette/presentation/command_palette_sheet.dart` (action).
- Acceptance: Party reachable in ≤2 taps from any tab, deep-linkable via `pulsr://party` and `/party`, back returns to the previous tab, and the sheet entry points keep working.

### P1 — Next (state model + platform behavior)

**P1-1 · Offline/partial state component and reconnect retry**
- Files: new `lib/core/widgets/connectivity_state.dart`; use `NetworkChangeMonitor` (currently cloud-only, `main.dart:988-992`); apply in `search`, `ytm_browse`, `downloads`, `ytm_search`.
- Change: a `StaleBanner` (generalize `ytm_browse_screen.dart:877-930`) + `OfflineEmptyState`; on reconnect, auto-retry the last failed query once.
- Acceptance: airplane mode on Search/Online shows the offline empty state, and turning the network back on repopulates without a manual pull; a failed refresh over existing results shows the stale banner, not a full-page error.

**P1-2 · One toast, one refresh**
- Files: `tag_editor_screen.dart` (10 SnackBars), `settings_screen.dart:213-235`, `library_screen.dart:640-703`, `home_screen.dart:163-190`, `onboarding_screen.dart` (4), `eq_preset_carousel.dart` (6), `lyrics_view.dart` (5); then `RefreshIndicator` → `PulsrRefreshIndicator`.
- Change: migrate success/error notifications to `PulsrToast.show`; drop the queue-reorder toast entirely (`queue_screen.dart:466-487`); capture the messenger before `Navigator.pop` where a SnackBar must remain.
- Acceptance: `rg -c "showSnackBar" lib/features` trends to 0 outside platform/share code; a test asserts no `ScaffoldMessenger.of(context).showSnackBar` in `lib/features` (allow-list with reasons); reordering the queue shows no banner.

**P1-3 · Onboarding: resume, progress, battery**
- Files: `lib/features/onboarding/presentation/onboarding_screen.dart:205-215`, `:266-318`; reuse `empty_library.dart:117-190` and `battery_optimization_card.dart`.
- Change: persist `_currentPage` on change and restore in `initState`; subscribe to `scanner.scanProgress` and render the determinate bar + percent during the final CTA; add a 6th step or a post-scan card for battery optimization with *Allow* / *Later*.
- Acceptance: kill the app on page 3 → relaunch lands on page 3; scanning a 1k-track library shows monotonic percent; declining battery optimization is persisted and never re-nagged in onboarding.

**P1-4 · Real restoration + predictive back**
- Files: `app_router.dart:60-128` (add `restorationId` per page key), `pulsr_page_pop_scope.dart:21` (`canPop: canPop` with a callback), `app_shell.dart` branches.
- Change: give every page a stable `restorationId`; let `PopScope` report `canPop: true` when the router can pop, and handle the gesture result instead of forcing the callback path.
- Acceptance: process death on `/album/42` restores the same route; Android 14 back gesture shows the preview animation while still honoring the double-back-to-exit rule at Home.

**P1-5 · Search polish**
- Files: `search_screen.dart:995-999`, `search_cubit.dart:387-412`.
- Change: confirm-or-undo on clear history (mirror `recents_screen.dart:118-126`); add a source label to suggestions ("From your library" / "Recent"); consider online suggestions in the Online scope.
- Acceptance: clearing history asks once or offers Undo; suggestions state their source; no regression in debounce (query still fires once per pause).

### P2 — Craft (after P0/P1)

- **P2-1** Replace the five bare spinners (F3) with `SkeletonList`/`PulsrProgressBar`; add a golden/lint test that fails on `Center(child: CircularProgressIndicator()` inside `lib/features/**/presentation`.
- **P2-2** Generate the settings search index from the widget tree (or extend it to every tile) and add Party/Downloads entries; acceptance: every settings toggle is findable by its label.
- **P2-3** Undo for irreversible downloads: keep the file for N seconds (trash) or show a confirm that names file count + total size.
- **P2-4** Empty-state copy pass: replace generic `SectionError` text with cause-specific copy (`network` vs `storage` vs `permission`), reusing `resolveUiErrorMessage`.

---

## Appendix A — Measurements, commands, and limits

### A1 — Counts (verified this run)

| Metric | Value | Command |
| :--- | :--- | :--- |
| Dart files under `lib/` | 827 | `Get-ChildItem lib -Recurse -Filter *.dart` |
| `*_screen.dart` files | 44 | `Get-ChildItem lib/features -Recurse -Filter *_screen.dart` |
| Feature folders | **37** (brief said 38) | `Get-ChildItem lib/features -Directory` |
| `AsyncStateBuilder` files | 9 | `rg -l AsyncStateBuilder lib/features` |
| Files with `StreamBuilder`/`BlocBuilder`/`FutureBuilder` | 53 | `rg -l ... lib/features` |
| `PulsrEmptyState` usages | 54 across 26 files | `rg -o PulsrEmptyState lib/features` |
| `PulsrToast.show` | 106 | `rg -o "PulsrToast.show" lib` |
| `showSnackBar` in features | 205 | `rg -o showSnackBar lib/features` |
| `showConfirmDialog` sites | 27 | `rg -o showConfirmDialog lib/features` |
| `GoRoute` declarations | 41 | `rg -o "GoRoute\(" lib/core/router/app_router.dart` |
| `restorationId` in `lib/` | **0** | `rg -o restorationId lib` |
| `PulsrErrorBoundary` refs in `lib/` | **0** (tests only) | `rg -l PulsrErrorBoundary lib` |
| `PulsrSheetHelper` vs raw `showModalBottomSheet` | 76 vs 3 | `rg -o ...` |
| Raw `RefreshIndicator` vs `PulsrRefreshIndicator` | 31 vs 6 | `rg -o ...` |
| Command palette actions | ~27 | `CommandPaletteItem(` ×28 − declaration |
| Settings search entries | 50 `_SearchItem(` sites | `rg -o "_SearchItem\(" lib/features/settings` |

### A2 — Design-intent documents consulted
- `DESIGN.md:275-296` — component map + the four required async states; explicitly bans bare spinners for content.
- `DESIGN_SYSTEM.md:123-156` — declares `AsyncStateBuilder`/`PulsrEmptyState` the standard and requires new async UI to use them.
- `CLAUDE.md` §5 — "Never instantiate screens with `Navigator.push(MaterialPageRoute(...))`" (honored: 2 exceptions), "prefer reactive Drift streams".

### A3 — Marked unverified
- Whether a raw SnackBar is *visually* occluded by the dock (layout read suggests collision; not observed on device).
- The five bare-spinner screens' behavior while the spinner is up (no runtime trace).
- Completeness of the 50-entry settings search index vs all available toggles.
- DLNA / remote-sources / USB / diagnostics behavior against real hardware.
- Predictive-back animation behavior on Android 14+ hardware.
- Screen-reader semantics of `PulsrEmptyState` and the toast live region.
- Whether `Navigator.pop` + `ScaffoldMessenger.of` currently throws on any route (F24 is a latent risk, not an observed crash).

### A4 — Brief vs repo discrepancies
- **38 vs 37 feature folders.** Disk has 37 (`assistant` and `widgets` are non-UI/support: `assistant` is an intent bootstrap with no screens; `widgets` is home-widget plumbing). This audit covers all 37.
- `CLAUDE.md` says "11 player themes"; `theme_registry.dart:29-41` registers exactly 11 (`custom_theme_builder_screen.dart` is the studio, not a theme). No discrepancy.

### A5 — Working tree state (not caused by this audit)
`git status --porcelain` at the end of this run showed pre-existing modifications to `android/app/src/main/kotlin/com/pulsr/music/AudioEffectsPlugin.kt`, `lib/data/audio/audio_handler.dart`, `lib/data/audio/equalizer_manager.dart`, plus an untracked `android/.kotlin/`. This audit only created `audit/frontend/ux-flows.md`; no file under `lib/`, `test/`, or `android/` was written or edited by it.
