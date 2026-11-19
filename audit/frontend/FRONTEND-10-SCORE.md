# Pulsr Frontend — Rating & Gaps to 10/10

> **Post-remediation status (2026-11-18, same day):** the P0 tranche plus several
> P1 items have been implemented and verified. See `REMEDIATION.md` for the
> file-level evidence, the measured before/after counts, and the remaining
> backlog. Projected equal-weight score after this pass: **≈ 7.9 / 10** (was
> 6.4). The sections below are the **original baseline audit** and are kept as
> the reference evidence; where they say “0 `restorationId`”, “41
> `CustomTransitionPage`”, “106 compact declarations” or “glass is API, not
> product”, those describe the pre-remediation tree.

**Date:** 2026-11-18
**Scope:** `lib/` presentation layer (37 feature folders, 818 Dart files, ~322,900 LOC), 9 rendered captures, 36 golden images, design/a11y ratchet tests.
**Method:** code-level evidence (`file:line`), call-site counts, and rendered captures. No repository markdown was used as evidence. Runtime profiling was not performed; items that depend on device appearance are marked **unverified**.
**Verification run:** `flutter test` on the UI/UX ratchet, motion ratchet, and contrast matrix → **122 cases passed**.

---

## 1. Headline

**Overall: 6.4 / 10.**

Pulsr has a **9/10 design-system skeleton and a 5–6/10 adoption layer**. Tokens, contrast tests, reduce-motion plumbing, RTL enforcement, timer gating and GPU budgets are better than most production Flutter apps. The product does not yet *look* like that skeleton: glass is declared but barely shipped, the best primitives have zero call sites, several settings lie about what they change, and a few signature interactions (Now Playing open/close, first song into the dock) are assembled rather than designed.

| Requested dimension | Score | Verdict |
|---|:--:|---|
| **UI (visual craft)** | **7.7** | Coherent dark system, strong settings/tablet screens, 11 player themes. Held back by ad-hoc depth, missing glass, and no light-mode capture evidence. |
| **UX (flows & states)** | **7.0** | Good IA and destructive safety; errors collapse into empty states, no offline/stale model, Party is undiscoverable. |
| **Blur / materials** | **4.3** | Glass is API, not product. 5 blur sites in the whole app; the only `GlassPreset` consumer paints an opaque slab over its own blur. |
| **Controls / interaction** | **6.3** | Excellent primitives, but 104 compact-density declarations shrink targets; `PulsrIconButton` has zero call sites; duplicate screen-reader labels. |
| **Motion / transitions** | **7.1** | Real token + reduce-motion architecture; predictive back is configured but dead, Now Playing is a plain route, and the duration scale is nominal. |
| **Frontend options** | **6.2** | 87 options (66 applied, 12 caveated, 9 absent). Breadth is impressive; wiring honesty and discoverability are not. |

**Equal-weight average = (7.7 + 7.0 + 4.3 + 6.3 + 7.1 + 6.2) / 6 = 6.43.**

Supporting dimensions (not in the headline average): Accessibility **6.8**, Responsive/adaptive **8.0**, Design-system consistency **6.5**, Perceived performance **7.5**.

**Projected:** P0 ≈ **7.9**, P0+P1 ≈ **8.8**, P0+P1+P2 ≈ **9.3–9.5**. A verifiable 10 requires the runtime matrix in §6, not more features.

---

## 2. What is already 9–10 — do not regress

1. **Reduce-motion architecture.** One merge point rewrites `MediaQuery.disableAnimations` for the whole app (`lib/main.dart:1386-1393`); `PulsrMotion.isEnabled` also checks accessible navigation (`lib/core/motion/pulsr_motion.dart:62-84`).
2. **Per-theme motion gating.** All 11 player themes stop their tickers under reduce motion; a negative test plus a positive control exists (`test/features/player/theme_reduce_motion_test.dart:85-100`).
3. **Blur fallback ladder.** `AppBlur.canBlur` disables blur on GPU saver and high contrast, with a WCAG-safe solid alpha and a hard sigma ceiling (`lib/core/constants/app_blur.dart:41-58`).
4. **RTL at hard zero.** `test/architecture/rtl_ratchet_test.dart` enforces zero non-directional sites; 343 directional insets in use.
5. **Slider semantics.** Single node, `semanticFormatterCallback`, documented `excludeSemantics` (`player_seek_bar.dart:475-482`), asserted by test.
6. **Haptics behind one switch.** 436 sites, zero bypasses (`lib/core/utils/pulsr_haptics.dart:14-20`).
7. **Ticker gating + GPU budget.** `TickerGatedBranchContainer`, visualizer `TickerMode` + 30 fps throttle + GPU style downgrade (`audio_visualizer.dart:173-175, 454-467, 568`).
8. **Theme physics.** Vinyl/CD/cassette motor inertia, tonearm engagement, gloss parked under reduce motion (`vinyl_player_theme.dart:82-108`, `cd_player_theme.dart:98-156`).
9. **Responsive shell.** Real tablet two-pane (captured at 1280×800), not a stretched phone UI; `Adaptive.pagePadding` used 161×.
10. **Guardrail tests.** 122 cases cover colour literals, blur routing, route builders, spinner ceiling, font sizes, sub-11sp allowances and WCAG contrast across light/dark/AMOLED/calm/high-contrast.
11. **Dock modal awareness.** `PulsrModalTracker` hides the dock for sheets and the keyboard (`stacked_bottom_dock.dart:52-62`).
12. **The artwork Hero chain.** One tag across mini player, tablet bar and all 11 themes (`player_theme.dart:11-12`, `theme_registry.dart:41-43`).

---

## 3. Hard evidence behind the scores

| # | Fact | Evidence | Consequence |
|---|---|---|---|
| 1 | **5 blur sites in 4 files**, 3 of them `BackdropFilter` | `glass_container.dart:233,242`; `bottom_nav_bar.dart:325`; `canvas_backdrop.dart:321`; `advanced_lyrics_view.dart:354` | Glass is not a product material |
| 2 | **The only `GlassPreset` consumer renders invisible blur** | `pulsr_dialog.dart:425-429` passes opaque `p.surfaceContainerHigh`; `glass_container.dart:159-161` skips alpha maths when `color != null` | Full 18σ backdrop pass for zero visual effect |
| 3 | **Bottom sheet is opaque, no filter** | `pulsr_bottom_sheet.dart:355-359` (alpha 0.96 dark / 0.98 light) | The most-used container has no material |
| 4 | **Mini player is an opaque gradient** | `mini_player.dart:606-624` | The surface permanently over artwork gets no diffusion |
| 5 | **Best primitives are unused** | `PulsrSurface` 0 consumers; `PulsrIconButton` 0; `PulsrErrorBoundary` 0; `PulsrTransitions` 0 | System exists, product bypasses it |
| 6 | **Depth is hand-rolled** | 183 raw `BoxShadow(` vs 22 `PulsrElevation` refs; 20 distinct blur radii; second dead scale `app_elevation.dart` | No usable elevation rhythm |
| 7 | **104 compact-density declarations** | `rg 'visualDensity: VisualDensity.compact'` → 104; 229 `IconButton` in features | 48dp targets shrink to 40dp; `mini_player.dart:2032-2039` shows an explicit 48 constraint defeated |
| 8 | **No route restoration** | `restorationId` occurrences in `lib/`: **0** | Process-death restore is inert |
| 9 | **Library error shown as “No songs found”** | `library_songs_tab.dart:73-88` checks `isLoading` then empty; `LibraryState.errorMessage` exists (`library_state.dart:41`) | Users are told their library is empty when loading failed |
| 10 | **440 `SnackBar(` vs 106 `PulsrToast.`** | repo counts | Two notification languages; dock-aware toast bypassed |
| 11 | **Theme Studio is hidden and half-inert** | Only entry `home_screen.dart:625`; radius/glow gated on `themeColorSource == custom` (`player_shape.dart:13-32`) | Best customization feature is 2 taps deep and its controls silently no-op |
| 12 | **Predictive back configured but bypassed** | `aura_theme.dart:733` installs the builder; 41 `GoRoute`s use custom page builders (`app_router.dart:62-107, 496-521`) | Android 14 back preview never appears |
| 13 | **In-app High Contrast never reaches blur** | `main.dart:1309` computes it for theming only; `app_blur.dart:50` reads only `MediaQuery.highContrast` | The contrast fallback does not fire for Pulsr's own accessibility mode |
| 14 | **Motion scale is nominal** | 33 distinct `motionMs` values; only 34% land on a token; 180 ms used 33× (untokenized) | Consistency bought at the API layer, lost at the value layer |
| 15 | **Party has no route** | `/party` absent from `app_router.dart` | Flagship social feature is undiscoverable |

---

## 4. Gaps to 10/10

### P0 — correctness & honesty (≈2 weeks, brings the score to ~7.9)

**P0-1 · Make glass real (blur 4.3 → ~7.0)**
- Fix `pulsr_dialog.dart:429`: drop the opaque `color`, or apply tint alpha to caller colours in `glass_container.dart:159-161`.
- Convert the mini player (`mini_player.dart:606-624`) to `GlassContainer` (sigma 12, tint ≈0.62 dark / 0.80 light) keeping the accent blend and hairline.
- Give the bottom sheet a real material (`pulsr_bottom_sheet.dart:355-359`): sigma 20 clamped to 18, alpha 0.82–0.88, `RepaintBoundary` around the filter.
- Wrap the dock filter in `RepaintBoundary` and move the drag transform outside it (`bottom_nav_bar.dart:158-161, 325-331`).
- Pass the app's `highContrast` flag into `AppBlur.canBlur` (mirror how `GlassContainer` already reads `liquidGlassTint`).
- **Done when:** widget test asserts `PulsrDialog`'s resolved colour has alpha < 1.0; a 5-artwork contrast sweep keeps chrome text ≥ 4.5:1; drag-and-hold on the dock shows no filter re-raster in a `--profile` timeline.

**P0-2 · Restore 48dp targets (controls 6.3 → ~8.0)**
- Add `iconButtonTheme` with `VisualDensity.standard` + `MaterialTapTargetSize.padded` (`aura_theme.dart`, near `segmentedButtonTheme`).
- Remove `visualDensity.compact` from `IconButton` sites (start with `mini_player.dart:2032-2039`, EQ sheets, lyrics, settings widgets).
- Fix the sub-48 one-offs: 46×46 player top bar (`player_theme_chrome.dart:1179-1181`), 34×34 bookmark close (`:1718-1733`), 22×22 chip delete (`pulsr_chip.dart:223`), ~20×20 switch info (`pulsr_switch.dart:343-364`), `Size.zero` speed-picker buttons (`speed_picker_sheet.dart:157-167, 229-235`).
- Add `test/architecture/hit_target_ratchet_test.dart` that pumps mini player, queue, EQ sheet and settings root and asserts ≥48×48 for every tappable descendant.
- **Done when:** ratchet is green; Android “show tap targets” shows no undersized circle.

**P0-3 · Make states truthful (UX 7.0 → ~8.0)**
- Library: before the empty branch, render a retryable `PulsrEmptyState` when `errorMessage != null` (`library_songs_tab.dart:73-88`; same for albums/artists/folders). Retry via `LibraryCubit.init()`, not a disk rescan.
- Adopt `PulsrErrorBoundary` per shell branch and around Now Playing; replace the bare global `ErrorWidget.builder` fallback.
- Replace the five remaining content spinners with `SkeletonList`/`SkeletonGrid`.
- **Done when:** forcing the songs stream to fail shows the error card with Retry, never “No songs found”; throwing inside Home keeps the dock and mini player alive.

**P0-4 · Add offline / stale / reconnect (UX)**
- New `StaleBanner` + `OfflineEmptyState` using `NetworkChangeMonitor`; auto-retry the last failed query once on reconnect.
- Apply in search, YTM browse/search, downloads, online playlist detail.
- **Done when:** airplane mode produces an offline state (not a generic error), and toggling the network back repopulates without a pull.

**P0-5 · Make Theme Studio honest and findable (options 6.2 → ~7.2)**
- `setCustomThemeRadius` / `setCustomThemeGlow` must promote `themeColorSource` to `custom` (matching `setCustomAccentColor`), or disable the controls with an inline hint when source ≠ custom.
- Add a Theme Studio tile to Settings → Appearance and a search index entry (`radius`, `glow`, `theme studio`); disambiguate the existing `studio` keyword.
- **Done when:** dragging radius to 40 changes Now Playing chrome within a frame and survives restart; searching “radius” returns Theme Studio first.

**P0-6 · Make “Button Style” mean something (options)**
- Either feed `appButtonStyle` into `ThemeData` button themes (`aura_theme.dart` currently hardcodes 14/20dp radii) or rename the option to what it actually styles (Pulsr chips/section actions).
- **Done when:** switching the option changes a dialog’s primary button radius app-wide, or the label no longer claims “buttons”.

**P0-7 · Restore platform navigation contracts (motion 7.1 → ~8.0)**
- Stop forcing `CustomTransitionPage` on every route: register a `PulsrPageTransitionsBuilder` in `pageTransitionsTheme` and return `MaterialPage` for Android, so predictive back works (`app_router.dart:62-107`).
- Branch on platform for iOS/macOS to recover the interactive edge-swipe pop.
- **Done when:** Android 14 slow back-gesture shows the receding page; iOS simulator edge-swipe pops and can be cancelled mid-gesture.

**P0-8 · Fix the two signature transitions (motion)**
- Animate idle → playing in the dock (`stacked_bottom_dock.dart:484-491`) with `AnimatedSize`/`SizeTransition` reusing the already-threaded duration/curve.
- Make Now Playing an expanding surface: wrap the mini-player *container* in a Hero matching a container in the player, add a shared `flightShuttleBuilder`, soften the route to fade + slight scale; set the route `opaque: false` and scrub background opacity during drag-dismiss.
- Wrap the app in `HeroMode(enabled: !reduceMotion)`.
- **Done when:** starting a song grows the mini player over 320 ms; opening/closing the player morphs corners and background continuously; reduce motion produces no flight.

**P0-9 · Enforce the motion scale (motion)**
- Collapse 150/160/180 → tap|state, 220/240/250 → state|layout, 280/300 → layout, 380/420/450 → page; keep documented physics values (650/850/900, 2600) on an allowlist.
- Extend the motion ratchet to assert every `motionMs(N)` literal is a token value, and add `lib/core/router` to its scan dirs.
- **Done when:** `rg -o 'motionMs\(\d+\)'` yields ≤5 values plus allowlist; ratchet green.

**P0-10 · One notification language + truthful destructive copy (UX)**
- Migrate success/error SnackBars to `PulsrToast` (start: tag editor 10, settings, library, home, onboarding, EQ carousel, lyrics); delete the queue-reorder toast.
- Replace contentless confirm bodies with size/scope (“Clears 412 MB of artwork and stream cache. Playlists and downloads are kept.”); make playlist delete copy and toast agree on Undo.
- **Done when:** `showSnackBar` outside platform/share code is zero (allow-listed); no confirm body is a bare “Confirm”.

**P0-11 · One depth system (blur/UI)**
- Delete the dead `app_elevation.dart`; migrate the four hottest surfaces to `PulsrElevation` (bottom sheet, toast, mini player, dock); add `AppStrokes.hairline` and replace 0.7/0.8/1/1.2/1.5 border literals.
- Add `popupMenuTheme` (surface, radius, elevation, hairline) for the 12 raw `PopupMenuButton`s.
- **Done when:** those four files contain no raw `BoxShadow`; all popup menus share radius/shadow.

**P0-12 · Remove a11y regressions (controls 6.3 → 8.0)**
- Add `excludeSemantics: true` to the five duplicated labels (`pulsr_list_tile.dart:166`, `pulsr_button.dart:309`, `pulsr_chip.dart:99`, `song_tile.dart:382`, `gestures_sheet.dart:83`).
- Scope arrow-key shortcuts to the player route so desktop focus traversal works (`player_shortcut_scope.dart:118-136`).
- Replace `FittedBox.scaleDown` in `SongTile` (`song_tile.dart:274-300`) with an ellipsizing single line + 2-line allowance above 1.3× scaling.
- **Done when:** a SongTile row is announced once; ArrowDown moves focus on Library and changes volume only on Now Playing; 2.0× text renders at ≥1.9× nominal.

---

### P1 — coherence & customization (≈2–3 weeks, → ~8.8)

1. **Party gets a home:** `/party` route, Settings entry, quick-discovery chip, command-palette action, deep link (≤2 taps from any tab).
2. **Route restoration:** stable `restorationId` per page + `PopScope` integration; process death on `/album/42` restores it.
3. **Onboarding:** persist current page, show determinate scan progress, add battery-optimization step with persisted decline.
4. **Lyrics options hub:** font size, alignment, translation default, offset; persist translation choice across rebuilds.
5. **List density:** compact/comfortable for library, queue and playlists (currently hard-coded per tab).
6. **Mini-player variants:** at minimum a compact bar vs current card, plus theme reactions beyond vinyl.
7. **Lock-screen & home-widget options:** artwork on/off, action set, widget size/queue; both subsystems exist with zero configuration.
8. **AMOLED material tuning:** stronger ambient ink and lower container tint over `#0A0A0D`; distinguish AMOLED from dark in elevation.
9. **Per-theme accent/geometry:** each of the 11 themes owns its palette/radius rather than one global accent gate.
10. **Settings integrity:** backup/restore must include the ~20 dropped appearance keys and stop writing the orphan `setting_bit_perfect` key.
11. **Studio depth:** truthful live preview (reflect applied radius), A/B hold-to-compare, named theme slots, export/import.
12. **Settings UI consistency:** localize the remaining hard-coded English rows; unify the five persistence channels; stop maintaining the search index by hand.

---

### P2 — delight & platform polish (→ 9.3–9.5)

1. Favorite burst with one-shot overshoot + radial glow, skipped under reduce motion.
2. Screen-level stagger choreography on Home (hero 0 ms, recents 60 ms, recently added 120 ms).
3. Crossfade visualization on the seek bar (blend region + remaining time).
4. Visualizer preview in Settings (currently icon-only) and mini-player preview in theme pickers.
5. Desktop menu bar + Escape-to-pop + hover labels on bare `GestureDetector` controls.
6. In-app text scale and lyric font choice (Manrope-only today).
7. Gesture map as a contract: `PulsrGesture` carries map ids; a test enforces coverage.
8. Adopt `FocusTokens` (currently zero callers) as the single focus ring.

---

## 5. Sequenced implementation plan

| Batch | Contents | Effort | Score after |
|---|---|---:|---:|
| **A — Honesty** | P0-1, P0-5, P0-6, P0-11 | 2–3 days | 7.0 |
| **B — Targets & semantics** | P0-2, P0-12 | 2 days | 7.4 |
| **C — State truth** | P0-3, P0-4, P0-10 | 3–4 days | 7.8 |
| **D — Signature motion** | P0-7, P0-8, P0-9 | 3–4 days | 8.1 |
| **E — Coherence** | P1 1–6 | 1.5 weeks | 8.6 |
| **F — Customization** | P1 7–12 | 1 week | 8.8 |
| **G — Delight** | P2 1–8 | 1–2 weeks | 9.3–9.5 |

Ship A+B first: they are low-risk, high-visibility, and every one is individually testable.

---

## 6. Verification & definition of done

**Automated (must stay green):**
- `flutter test test/architecture/ui_ux_10_ratchet_test.dart test/architecture/motion_token_ratchet_test.dart test/a11y/contrast_matrix_test.dart` (122 cases, currently passing).
- Add: hit-target ratchet, motion-value ratchet, library error-state test, studio-promotion test, dialog-alpha test.

**Runtime matrix (currently missing):**
- Screens: Home, Library, Now Playing (3 themes: clean, vinyl, cassette), Queue, Album, Search, Settings root, Theme Studio.
- Variants: light / dark / AMOLED / high-contrast × phone 390×844 + tablet 1280×800.
- Motion: 60 fps capture of mini player → Now Playing → dismiss; dock idle → playing; predictive back.
- Accessibility: TalkBack pass on library rows and the transport; 200% text on the mini player and SongTile.

**Performance budget:**
- No frame over 16 ms during dock drag or Now Playing open on a mid-tier device.
- Blur layer count ≤3 simultaneously; no full-screen blur under animation.
- One ticker per visible surface; zero tickers when the player is paused.

**Definition of 10:** the runtime matrix passes on device, every option changes what it claims to change, and the scorecard above reads ≥9 on all six requested dimensions with no P0/P1 open.

---

## 7. Evidence files

- `audit/frontend/blur-depth.md` — blur, materials, elevation (228 lines).
- `audit/frontend/motion.md` — tokens, routes, continuity (389 lines).
- `audit/frontend/controls-a11y.md` — targets, semantics, input parity (302 lines).
- `audit/frontend/ux-flows.md` — state coverage, IA, first-run (393 lines).
- `audit/frontend/options.md` — 87-option inventory, wiring flags, benchmark (361 lines).
- `audit/frontend/ratchet_tests.log` — 122 passing cases.

**Caveats:** the 9 captures are all dark mode and none show Now Playing, so player visuals are rated from code and 36 goldens (test-font boxes preserve layout, not typography). AMOLED/HC appearance and Hero/predictive-back behaviour are structural findings, not device captures.
