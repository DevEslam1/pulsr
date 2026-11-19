# Frontend Remediation — 2026-11-18

**Baseline:** `FRONTEND-10-SCORE.md` (6.4 / 10) and its five evidence files.
**This pass:** implemented and verified the P0 tranche, plus the parts of P1 that
were cheap and provable. No repository markdown was used as evidence; every
before/after number below is a repo count or a test result.

## Verified at the end of this pass

| Check | Result |
|---|---|
| `flutter analyze --no-pub` | **0 issues** |
| `test/architecture` + `test/a11y` + `test/core/widgets` + `test/core/theme` | **345 passed, 1 pre-existing failure** (`gesture_arena_themes_test.dart` cassette — fails identically on a clean HEAD; see “Not caused by this pass”) |
| `test/features/player` (theme reduce-motion, custom theme builder, gesture arena) | green except the same cassette case |
| New ratchets | `hit_target_ratchet_test.dart` (3 cases), `glass_material_test.dart` (4 cases), motion value check, sheet/dock sigma check |

## What changed, by audit dimension

### Blur / materials (audit 4.3)

- `pulsr_dialog.dart` no longer paints an opaque slab over its own filter;
  `glass_container.dart` now modulates **any** caller colour instead of
  skipping the tint maths when `color != null` (`glass_dialog_alpha` case
  asserts a resolved alpha < 1.0).
- Bottom sheet is a real material: alpha 0.86/0.90, `BackdropFilter` at
  `GlassPreset.sheet`, `RepaintBoundary`, `PulsrElevation.level3`, hairline
  token, and `sheetAnimationStyle` driven by `PulsrDurations`.
- Mini player replaced its opaque gradient with `GlassContainer`
  (sigma 12, tint 0.62/0.80, accent blend preserved) and
  `PulsrElevation.level4`.
- Nav dock: filter wrapped in `RepaintBoundary`; the drag transform no longer
  passes through a 120 ms implicit animation, so it tracks the finger 1:1 and
  only the release animates.
- `AppBlur.sheet` / `.dock` are now **18** (= `maxSigma`) instead of 20/24, so
  the token equals the sigma the GPU rasterises. A test pins it.
- `app_elevation.dart` (dead duplicate scale) deleted; `PulsrElevation` gained
  an AMOLED ambient-ink branch; `AppStrokes` added and adopted in the four hot
  surfaces; `popupMenuTheme` added so the 12 raw menus inherit one material.
- Raw `BoxShadow(` in `lib/features`: **183 → 146**.

### Controls / accessibility (audit 6.3)

- All 59 `IconButton` + `VisualDensity.compact` sites removed; the theme now
  sets `VisualDensity.standard` + `MaterialTapTargetSize.padded`.
- Sub-48dp one-offs fixed: player top-bar 46→48 (×2 + spacers), bookmark close
  34→48, chip delete 22→48 box, switch info →48 with a label, seek-bar duration
  toggle and Up Next strip →48, speed-picker `Size.zero` →48, search clear
  32→48, plus four auth buttons found by the new ratchet.
- Duplicate screen-reader labels removed on `PulsrListTile`, `PulsrButton`,
  `PulsrChip`, `SongTile`, `GesturesSheet` (`excludeSemantics: true`, subtitle
  folded into the list-tile label).
- Arrow keys removed from the global scope; `PlayerArrowShortcutScope` binds
  them only inside Now Playing. Shuffle/repeat expose `toggled:`, segmented
  control declares `inMutuallyExclusiveGroup`.
- `SongTile` no longer `FittedBox`-shrinks text above 1.3× scaling.
- New `test/architecture/hit_target_ratchet_test.dart` fails on
  `IconButton`+compact and on `Size.zero`+`shrinkWrap`.

### Motion / transitions (audit 7.1)

- Router returns **`MaterialPage`** for every route (0 `CustomTransitionPage`
  left), so `PageTransitionsTheme` is consulted: Android gets predictive back,
  iOS/macOS keep the Cupertino edge-swipe, desktop keeps Pulsr’s slide via
  `PulsrPageTransitionsBuilder` (320/260).
- Now Playing is a non-opaque `PulsrNowPlayingPage` (fade + 0.96→1.0 scale);
  the screen’s background moved inside the dismiss transform, so a half-swipe
  reveals the library and mini player instead of a blank stage.
- Dock idle → playing is wrapped in `AnimatedSize` in `app_shell.dart`.
- `HeroMode(enabled: !reduceMotion)` wraps the app.
- Motion scale collapsed repo-wide to the five tokens (120/200/260/320/400);
  the only remaining literals are documented physics/ambient values
  (650/900/1300/1400/2400/2600/3200/4000/15000), now enforced by a fourth
  ratchet check that also scans `lib/core/router`.

### UX / state truth (audit 7.0)

- Library failure no longer renders “No songs found” + Scan: songs/albums/
  artists/genres render a retryable `PulsrEmptyState` driven by
  `LibraryState.errorMessage`, and Retry re-subscribes via `LibraryCubit.init`
  (no disk rescan). The error is no longer cleared before the tab builds.
- `PulsrErrorBoundary` wraps the shell branch, so a build error keeps the dock
  and mini player alive; the global fallback is branded instead of one text
  label.
- Library refresh failures use the dock-aware `PulsrToast` when content exists.

### Options (audit 6.2)

- `setCustomThemeRadius` / `setCustomThemeGlow` promote
  `themeColorSource = custom`, matching `setCustomAccentColor`; the Studio
  sliders are no longer silent no-ops.
- Theme Studio has a Settings → Look tile and dedicated search entries for
  `radius`, `glow`, `theme studio`; `studio` no longer misroutes to Experience
  Mode only.
- “Button Style” now drives Material button radii app-wide
  (`AuraTheme.customTheme(buttonRadius:)`).
- High contrast is mirrored into `MediaQuery.highContrast`, so the blur
  fallback fires for the app’s own accessibility mode.
- Light + high-contrast status-bar brightness fixed (derived from the resolved
  theme, not from the contrast flag).
- Backup/restore covers ~20 previously dropped appearance/gesture keys and
  writes `PrefsKeys.bitPerfectOutput` instead of the orphan
  `setting_bit_perfect`.

### Navigation IA

- `/party` exists with a real `PartyScreen` (same `PartySheet` state machine),
  plus a Home quick-discovery chip. Party is now one tap from Home and
  deep-linkable instead of hidden behind three player surfaces.
- Pages carry stable `restorationId`s derived from route keys; `PopScope`
  reports the true `canPop` so predictive back can run.

## Not caused by this pass

`test/features/player/widgets/gesture_arena_themes_test.dart` — cassette case:
a horizontal platter pan seeks instead of skipping. It reproduces on a clean
HEAD (`git stash push -- lib test` then run), so it is a pre-existing cassette
gesture-arena bug, not a regression.

## Still open (honest backlog)

These are the audit items this pass did **not** close:

1. **Notification language:** 204 `showSnackBar` call sites remain in
   `lib/features` (queue-reorder toast still present). Migration to
   `PulsrToast` is mechanical but broad.
2. **Offline / stale model:** no `StaleBanner`/`OfflineEmptyState` component;
   `NetworkChangeMonitor` is still cloud-sync-only.
3. **Bare content spinners:** 6 remain (`radio`, `tag_editor`,
   `ytm_oauth_login_sheet`, `scrobbler_settings_modal`, `eq_sheet_shell`).
4. **Mini-player surface Hero:** only the artwork chain flies; the container
   Hero + shuttle exist (`hero_tags.dart`) but are not wrapped on either side.
5. **P1 customization:** list density, mini-player variants, lyrics options
   hub (translation mode is still widget-local), lock-screen/widget options,
   per-theme accents, Studio A/B compare.
6. **Primitive adoption:** `PulsrIconButton` still has 0 consumers; 146 raw
   `BoxShadow` calls remain outside the four migrated surfaces.
7. **Runtime verification:** no device captures, frame profiles, TalkBack pass
   or predictive-back recording were produced in this environment.

## Projected scores

Equal-weight average of the six headline dimensions, using the audit’s own
rubric and the evidence above:

| Dimension | Was | Now (projected) |
|---|:--:|:--:|
| UI craft | 7.7 | 8.3 |
| UX flows & states | 7.0 | 7.6 |
| Blur / materials | 4.3 | 7.4 |
| Controls / interaction | 6.3 | 8.4 |
| Motion / transitions | 7.1 | 8.2 |
| Frontend options | 6.2 | 7.6 |
| **Overall** | **6.4** | **≈ 7.9** |

A verifiable 10 still requires the open backlog above **plus** the runtime
matrix in `FRONTEND-10-SCORE.md` §6 (device captures, predictive-back
recording, TalkBack pass, blur layer count, frame budget).
