# Pulsr — Controls, Gestures & Accessibility Audit

**Scope:** every tappable control, hit target, semantics node, gesture recognizer, keyboard binding, focus treatment, press/haptic feedback path, and text-scale/RTL behaviour in the Flutter UI layer (`lib/`, 827 Dart files / 341k LOC), with emphasis on the design-system primitives and the player surfaces named in the brief.
**Method:** static reading of the named modules plus whole-repo counts (`Select-String` over `lib/`), cross-checked against the vendored Material fork source (`material_ui 1.11.0`) for widget-level sizing math, and against the repo's own enforcement tests. I also **ran** the accessibility suite.
**Runtime:** `flutter test test/a11y test/core/widgets/pulsr_slider_semantics_test.dart test/architecture/icon_button_a11y_ratchet_test.dart` → **130 tests passed**; `test/architecture/rtl_ratchet_test.dart` → **passed** (needed `LOCALAPPDATA` / `PUB_CACHE` / `ProgramFiles(x86)` env repair; the note in `audit/frontend/motion.md:4` that tests cannot run does not hold in this run). No Android device or desktop build was driven, so anything that depends on TalkBack/VoiceOver speech output, pointer hit-testing under a finger, or OS-level key routing is marked **unverified**.
**Date:** 2026-11-18

---

## 0. The headline

The **primitives are better than the app that uses them.** `PulsrButton`, `PulsrIconButton`, `PulsrChip`, `PulsrSlider` and `PulsrSwitch` all expand to a 48dp target by construction, `PulsrPressable` publishes one merged semantics node with an activation action, the seek bars deliberately de-duplicate their nested slider node, and there is a live-region announcer plus `CustomSemanticsAction`s for gestures that have no visible affordance. The RTL and icon-tooltip ratchets pass, and 130 accessibility assertions guard the result.

The failures are all **call-site and governance failures**, not primitive failures:

1. `visualDensity: VisualDensity.compact` silently subtracts 8dp from *every* icon button it touches — including the mini player, where the author wrote `constraints: minWidth: 48, minHeight: 48` believing it protected the target. 59 sites resolve to **40×40**. The design system never shipped a rule against it, and the only hit-target ratchet checks exactly two widgets.
2. The gesture map is a **documentation registry with one consumer** (`gestures_sheet.dart`). Nothing binds an implemented recognizer to a map entry, so "one documented gesture map enforced" is currently "one documented gesture map, displayed".
3. The five most-used components set `Semantics(label: …)` **and** keep the visible `Text` as a child without `excludeSemantics` — while the seek bar two files away carries a comment explaining precisely why that duplicates a node. The knowledge exists; it was not generalized.

---

## 1. Score table

| Dimension | Score | One-line verdict |
| :--- | :---: | :--- |
| **Hit targets** | **6/10** | Primitives are exemplary (a 48dp floor in all six core widgets) but ~59 compact-density icon buttons render at 40dp, plus a long tail of 20–46dp one-offs in the player chrome. |
| **Semantics** | **7/10** | 250 `Semantics` nodes, 305 tooltips, a real live-region announcer and custom gesture actions — undercut by duplicate labels on the 5 core components and almost no toggle-state exposure. |
| **Gesture coherence** | **6/10** | A canonical 11-entry gesture map exists and conflicts are handled *deliberately* where they were hit, but the map is display-only and no test pins any arena outcome. |
| **Keyboard & desktop** | **6/10** | One `CallbackShortcuts` scope with 13 bindings, focus rings on every custom pressable, ordered traversal in the shell — but global arrow keys shadow focus traversal and `FocusTokens` is dead code. |
| **Feedback & states** | **7/10** | 436 haptic call sites behind one gated switch, loading-in-button, real disabled states, scale+ripple press — three competing press idioms and no error shake anywhere. |
| **Dynamic type & RTL** | **6/10** | App-level scale clamp honours the full 200% OS range and the RTL ratchet is at a hard zero — but `FittedBox.scaleDown` in the most-used row widget cancels the user's text size. |

**Total: 38 / 60.**

---

## 2. Findings

### 2.1 Hit targets — 6/10

**What is genuinely right.** Every design-system primitive enforces a 48dp floor even when the visual is smaller:

| Primitive | Visual size | Enforced target | Evidence |
| :--- | :--- | :--- | :--- |
| `PulsrButton` | 36 / 44 / 52 (sm/md/lg) | 48 (`ConstrainedBox minHeight`) | `lib/core/widgets/pulsr_button.dart:300` |
| `PulsrIconButton` | 44 default | 48 | `lib/core/widgets/pulsr_icon_button.dart:105-108` |
| `PulsrChip` | 36 pill | 48 | `lib/core/widgets/pulsr_chip.dart:109` |
| `PulsrSlider` | caller height 32–44 | `max(48, height)` | `lib/core/widgets/pulsr_slider.dart:266` |
| `PulsrSwitch` | 48×28 / 38×22 | 48 box | `lib/core/widgets/pulsr_switch.dart:180-181` |
| `PulsrSegmentedControl` | 28 content | 28 + 2×10 padding = 48 | `lib/core/widgets/pulsr_segmented_control.dart:153`, `:298` |

The transport strip is also correctly defensive: `mainHitSize = mainButtonSize < 48 ? 48 : mainButtonSize` (`player_controls.dart:139`), side buttons clamp to `>= 48` (`:132`), and `_ControlButton`/`_AbPointButton` carry `BoxConstraints(minWidth: 48, minHeight: 48)` (`:677`, `:782`). A test locks this in at 360dp for five icons (`test/a11y/player_transport_a11y_test.dart:61-96`).

**The systemic defect: compact density costs 8dp, and nobody noticed.** Material resolves `VisualDensity.compact` as `(-2,-2)` and multiplies by the 4dp interval (`material_ui-1.11.0/lib/src/theme_data.dart:3429-3436`). Both button code paths subtract it from the *tap target*, not just the visual:

- M2 path: `adjustedConstraints = effectiveVisualDensity.effectiveConstraints(constraints ?? BoxConstraints(minWidth: 48, minHeight: 48))` — `icon_button.dart:852-856`.
- M3 path: `_InputPadding(minSize: Size(kMinInteractiveDimension + densityAdjustment.dx, …))` → `48 + (-8) = 40` — `button_style_button.dart:606-617`.

So `VisualDensity.compact` yields a **40×40 hit target on both paths**, and an explicit `constraints: 48` does not rescue it. The clearest example is the mini player:

```dart
// lib/features/player/presentation/mini_player.dart:2032-2039
IconButton(
  tooltip: state.isPlaying ? context.l10n.pause : context.l10n.play,
  iconSize: 26,
  visualDensity: VisualDensity.compact,
  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
```

Effective target: 40×40. Same pattern at `:2060-2065` (next). A heuristic scan for the nearest preceding constructor finds **59 `IconButton(` sites under `visualDensity: VisualDensity.compact`** out of 236 `IconButton(` occurrences in `lib/` — roughly a quarter of all icon buttons, concentrated in `eq_sheet_shell.dart`, `eq_advanced_controls.dart`, `lyrics_view.dart`, `settings/*`, `mini_player.dart`. (`visualDensity` never appears in the theme's `iconButtonTheme`, so there is no global override either way.)

Compounding it: **`PulsrIconButton` — the one primitive that guarantees the 48dp target plus the scale-press and haptic behaviour — has zero call sites.** All 236 icon buttons in `lib/` are raw Material `IconButton`s (`pulsr_icon_button.dart` is referenced only by its own declaration), so the design system's answer to this problem was written and never adopted.

**Explicit shrink-wrap removes the padding entirely.** `MaterialTapTargetSize.shrinkWrap` sets `minSize = Size.zero` (`button_style_button.dart:615-616`), so the target collapses to the glyph:

- `lib/features/player/presentation/widgets/speed_picker_sheet.dart:157-167` — `minimumSize: Size.zero` + `padding: EdgeInsets.zero` + `shrinkWrap` on the "Reset" label. Target ≈ 13dp tall.
- `lib/features/player/presentation/widgets/speed_picker_sheet.dart:229-235` — same for pitch reset.
- `lib/features/search/presentation/search_screen.dart:2193-2197` — `minimumSize: Size(48, 32)` + `shrinkWrap` = 48×32.
- `lib/features/player/presentation/themes/player_theme_chrome.dart:1701-1706` — resume banner action, `Size(48, 34)` + `shrinkWrap`.
- 12 `tapTargetSize: MaterialTapTargetSize.shrinkWrap` declarations total; 7 `minimumSize: Size.zero` declarations.

**Fixed-size one-offs inside the player chrome** (the surface users touch most):

| Control | Size | File:line |
| :--- | ---: | :--- |
| Dismiss (`chevron`) + overflow (`…`) in `PlayerTopBar` | 46×46 | `player_theme_chrome.dart:1179-1181` (both buttons, plus 46×46 spacers at `:1231`, `:1329`) |
| Bookmark-prompt close | 34×34 | `player_theme_chrome.dart:1718-1733` (`SizedBox(34,34)` + `padding: EdgeInsets.zero`) |
| `PulsrChip` delete affordance | 22×22 | `pulsr_chip.dart:223-231` |
| `PulsrSwitchListTile` info affordance | ≈20.5×20.5 | `pulsr_switch.dart:343-364` (3.5 padding + 13.5 icon) |
| Seek bar elapsed/remaining toggle | text height | `player_seek_bar.dart:706-711` |
| "Up Next" strip (opens queue) | ≈22–26px tall | `player_seek_bar.dart:312-320` |

**Counts.** Of the surfaces I sampled, compliant: transport (5 controls), queue rows (`now_playing_queue_view.dart:381`, `:394`), song-tile overflow (48, and asserted by test), search-field clear (48 + localized tooltip, `pulsr_search_field.dart:286-315`), bottom-nav items (≈56 inside a 64 bar), `PlayerSwitcherItem`/`PlayerDockIconButton`/`PlayerAnimatedFavoriteButton` (48, `player_theme_chrome.dart:210, 317, 528`). Non-compliant by construction: 59 compact icon buttons, ≥12 shrink-wrap/shape-declared sites, 2×46dp top-bar buttons per theme, and the 4 one-offs above.

**Why this scores 6 and not 7.** A 40dp target clears WCAG 2.5.8's 24dp floor and is exactly Material's default icon-button footprint — but it is 8dp below the app's own declared floor (`AppSpacing.minTouchTarget = 48`, `app_spacing.dart:56`) and it is applied *unconsciously*, including where the code asserts the opposite. The enforcement net catches exactly one IconButton (`test/architecture/icon_button_a11y_ratchet_test.dart:66-109`).

### 2.2 Semantics — 7/10

**Coverage.** 250 `Semantics(` widgets, 305 `tooltip:` arguments, 49 explicit `semanticLabel`, 77 `excludeSemantics`, 11 `liveRegion`, 24 `onIncrease`. Every `IconButton` in `lib/` carries a tooltip, and a ratchet fails the build otherwise (`icon_button_a11y_ratchet_test.dart:32-63`). That is a genuinely high floor — it is the main reason this dimension is 7 and not 5.

**Slider semantics are reference-grade.** `PulsrSlider` publishes a single `Semantics(slider: true, value, increasedValue, decreasedValue, onIncrease, onDecrease)` with a caller-supplied `semanticFormatterCallback` (`pulsr_slider.dart:247-258`), plus arrow/page key stepping (`:227-239`). The player seek bar then wraps it with `excludeSemantics: true` and *its own* time-formatted values, with the reason spelled out in a comment:

```dart
// lib/features/player/presentation/widgets/player_seek_bar.dart:478-482
// The child PulsrSlider publishes its own slider node
// with a percentage value; without this exclusion the
// same control appeared twice (time and percent) and
// both increase handlers seeked 10s.
excludeSemantics: true,
```

Verified by test: `test/a11y/accessibility_compliance_test.dart:177-215` asserts `value == '0:45 / 3:00'`, `increasedValue == '0:55 / 3:00'`, and that `onIncrease` seeks exactly 10s. 8 call-site occurrences of `semanticFormatterCallback` (5 call sites plus the primitive's own declaration) — `player_seek_bar.dart:505`, `player_volume_bar.dart:81`, `settings_slider_row.dart:145`, `speed_picker_sheet.dart:259`, `ambient_sound_panel.dart:594`, so dB/ms/speed values are announced with units.

**Live announcements are real.** `A11yLiveAnnouncer` listens to `PlayerCubit` and announces track change, play/pause, queue add/remove/reorder/clear, both via `SemanticsService.sendAnnouncement(assertiveness: polite)` and via a resident `liveRegion: true` node (`a11y_live_announcer.dart:42-60`, `:63-140`, `:150-165`). It is mounted once, above the shell (`app_shell.dart:337`). Toasts are also `liveRegion: true` (`pulsr_toast.dart:499`), so errors reach a screen reader without focus.

Gaps in the announcer: nothing is announced for repeat/shuffle/volume/playback-speed changes even though the transport shows a toast for repeat (`player_controls.dart:572`) — the toast's live region covers it only when the toast is shown; nothing announces library-scan completion or download progress; and the announcement is a single overwritten string, so two rapid changes collapse (acceptable, but undocumented).

**Duplicate labels on the five most-used components.** Each of these sets an explicit label *and* leaves the visible text in the subtree, with no `excludeSemantics`. Flutter merges a `Semantics` label with descendant text into one node, so the announcement repeats the visible strings:

```dart
// lib/core/widgets/pulsr_list_tile.dart:166-170
child: Semantics(
  button: onTap != null,
  enabled: enabled,
  selected: selected,
  label: title,            // …and `Text(title)` is inside `content`
```

Same shape at `pulsr_button.dart:309-312` (`label: widget.label` over `Text(widget.label)`), `pulsr_chip.dart:99-102`, `song_tile.dart:382-383` (`label: songByArtist(title, artist)` over both `Text`s — so a track announces *title, title, artist*), and `gestures_sheet.dart:83-84` (`label: '$title. $desc'` over both `Text`s). Confidence: **high, code-derived** (Flutter's `SemanticsConfiguration.absorb` concatenates labels of non-boundary children); **not device-verified** — a TalkBack node dump is the confirming step. It matters because these five components render most of the app's rows.

**Toggle state is barely exposed.** `toggled:` appears 4 times, `checked:` once, in a 827-file app. `PulsrSwitch` does it correctly (`pulsr_switch.dart:162`), but:

- Shuffle and repeat are plain `Semantics(button: true, label: …)` with an *action-verb* label ("Enable shuffle" / "Disable shuffle", `player_controls.dart:167`, `:547`) — a screen reader user cannot query current state, only infer it from the verb, and the label changing under focus is disorienting.
- `PulsrSegmentedControl` sets `selected:` but not `inMutuallyExclusiveGroup: true` (`pulsr_segmented_control.dart:123`), so TalkBack announces "selected" without "1 of 3".
- `PulsrSwitchListTile` makes the whole row tappable *and* nests a live `PulsrSwitch` (`pulsr_switch.dart:307-309` → `:412`), producing two adjacent tap targets that do the same thing; there is no `MergeSemantics`.

**Unlabeled tap targets.** The `IconButton` ratchet does not cover bare `GestureDetector`+`Icon` compositions. `pulsr_switch.dart:343-364` (info affordance) is a `GestureDetector` around an `Icon` with no `semanticLabel` and no `Tooltip` — TalkBack reads an unnamed clickable node. `player_seek_bar.dart:312-320` ("Up Next" row) gets a tap action from `GestureDetector` but no role label or value.

**The a11y test suite is partly self-referential.** `test/a11y/talkback_eyes_free_flow_test.dart:292-340` is titled "Eyes-free E2E journey validation" but builds a synthetic tree of `Semantics(button: true, label: 'Play')` + disabled `IconButton`s and asserts those literal labels exist. It proves Flutter merges semantics; it does not traverse one Pulsr screen. Likewise `:190-240` re-tests a hand-built `Semantics(excludeSemantics: true)` wrapper rather than `PulsrSlider` — the real widget is only covered by `accessibility_compliance_test.dart`. This is the difference between "we have a11y tests" and "a11y is regression-proof".

### 2.3 Gesture coherence — 6/10

**A canonical map exists — and is inert.** `PulsrGestureMap` declares 11 entries across 6 surfaces with ids, icons and localized copy (`lib/core/motion/gesture_map.dart:103-190`). Its only consumer in the entire codebase is the sheet that renders it:

```
lib/core/motion/gesture_map.dart:26,47          (declaration)
lib/core/widgets/gestures_sheet.dart:6,11,43,60 (rendering)
```

Nothing in `mini_player.dart`, `now_playing_screen.dart`, `waveform_seek_bar.dart` or the theme platters references a map id. So the map cannot detect drift: delete the platter-scrub recognizer and the guide still promises it. There is no id on any recognizer, no `const Key('gesture:mini_swipe_horizontal')`, and no test asserting that a documented gesture is implemented (or that an implemented drag is documented).

**Where conflicts were met, they were handled deliberately — this is the strongest part of the dimension.**

- Mini player: horizontal swipe means *skip*, but when the carousel is live the same surface must page. The code nulls the drag handlers and hands the axis to the `PageView` instead of fighting: `onHorizontalDragStart: carouselEnabled ? null : …` (`mini_player.dart:524`), with `_carouselDragDelta` driven from `ScrollNotification` (`:681-720`). Axes are cleanly split: vertical = expand/dismiss (`:484-522`), horizontal = skip (`:524-568`).
- Now Playing: vertical-only dismiss on a translucent ancestor (`now_playing_screen.dart:429-437`), with an explicit comment that only the vertical recognizer owns the drag flag after a bug where child taps disabled dismissal (`:310-314`, "BUG-01").
- Queue: `ReorderableListView` (long-press/drag-handle vertical) + `Dismissible` (horizontal end-to-start) — orthogonal axes, plus an explicit 48dp `ReorderableDragStartListener` handle so desktop users don't have to long-press (`now_playing_queue_view.dart:388-397`, `:422-440`).
- Lists: `PulsrDismissible` keeps a global "one open row" registry (`pulsr_dismissible.dart:200`, `:303-310`) and a 60% threshold (`:26-31`) so a horizontal swipe doesn't fire on a micro-drag.

**Actual conflict surface (unresolved or unverified):**

1. **Dock vs mini player, both vertical.** `PulsrBottomNavBar` installs a vertical drag over the whole dock (`bottom_nav_bar.dart:125-145`) and the mini player installs its own vertical drag (`mini_player.dart:484-522`). They are nested, so the inner wins by arena order — but the dock's drag still fires when the finger starts on nav items, and there is no test for either outcome. Two different thresholds (dock 20px / velocity 80; mini 25px / velocity 120) also mean the *same* flick does different things depending on where it starts.
2. **Vertical dismiss cannot start over the lyrics or queue surfaces** in Now Playing, because those are scrollables that claim vertical drags first. That is defensible, but it means the documented "swipe down to dismiss" silently fails on the two screens users are most likely to be on — and nothing in the gesture map says so.
3. **Pinch-to-zoom vs scrub on the waveform.** One `GestureDetector` carries `onScaleStart/Update`, `onHorizontalDragStart/Update/End`, `onTapUp` and `onDoubleTap` (`waveform_seek_bar.dart:231-395`). `ScaleGestureRecognizer` is a pan superset, and which one wins a one-finger horizontal drag is arena-order dependent; the code compensates by re-freezing the window around `_dragValue` during scale (`:256-300`) rather than by resolving the conflict. **Unverified without a device**; a `tester.startGesture` + `moveBy` test would settle it.
4. **Sheet drag vs sheet scroll.** `showModalBottomSheet(enableDrag: true)` (`pulsr_bottom_sheet.dart:162-168`) is used for the EQ, queue and lyrics surfaces; the framework's scroll-to-dismiss handshake only works when the inner list reaches its top edge. No test pins it.

**Verdict.** The map is the right idea executed as content instead of contract. 6/10: deliberate where it was hard, unenforced where it is easy.

### 2.4 Keyboard & desktop — 6/10

**Exactly one shortcut scope exists in the whole app.** `Shortcuts(` occurs zero times; `CallbackShortcuts(` once — `player_shortcut_scope.dart:190`, mounted at `app_shell.dart:321`. It binds 13 actions: Space, ←/→ (seek ±10s), ↑/↓ (volume ±5%), N/P, M, L, Q, Shift+/? (help), Ctrl/Cmd+K (palette), F (favorite). It correctly suppresses itself while an `EditableText` has focus (`:62-67`) and gives a toast confirming every action (`:69-84`) — good desktop citizenship.

Local key handling exists where it must: `PulsrPressable` binds Enter/Space to `ActivateIntent` (`pulsr_pressable.dart:186-201`), `PulsrSlider` binds arrows/page (`pulsr_slider.dart:227-239`), `PulsrSwitch` binds Enter/Space (`pulsr_switch.dart:149-150`), and the command palette owns Arrow/Enter/Escape while open (`command_palette_sheet.dart:409-440`).

**The arrow bindings break standard focus traversal.** Flutter's `WidgetsApp` maps arrows to `DirectionalFocusIntent`. `PlayerShortcutScope` sits *below* that root `Shortcuts` and *above* every screen, and its autofocus `Focus` (`player_shortcut_scope.dart:194`) guarantees a focused descendant. Shortcut resolution walks up from the primary focus, so this scope wins: on the library grid, **↓ changes the volume instead of moving focus**, and ← / → seek instead of moving between controls. Keyboard-only navigation is therefore reduced to Tab/Shift-Tab. This is the single biggest desktop defect in the audit, and it is structural, not a bug in one screen.

**Escape is unbound outside the palette.** No `DismissIntent` anywhere in `lib/`. Sheets/dialogs dismiss on Escape via framework defaults (barrier + `DismissIntent`), but the full-screen Now Playing route is not a dialog: it only reacts through `PopScope` (`app_shell.dart:315`, `now_playing_screen.dart:187-191`), which is driven by Android back, not by Escape. On a desktop build, Escape in Now Playing is likely a no-op — **unverified**, but there is no code path that would handle it.

**Focus rings exist three times, and the token file is dead.**

- `PulsrPressable` draws a 2dp accent `Border` in `DecorationPosition.foreground` plus a glow, gated on `onShowFocusHighlight` (`pulsr_pressable.dart:167-181`). Good instinct: focus-only, no ring on tap.
- `PulsrSlider` draws its own 1.5dp accent border (`pulsr_slider.dart:256-262`).
- `PulsrSwitch` swaps its hairline for a 2dp accent border (`pulsr_switch.dart:217-221`).

`FocusTokens` — which documents WCAG 2.4.7 / 1.4.11 and provides a **contrast halo** so the ring survives accent-on-accent surfaces (`focus_tokens.dart:7-15`, `ring()` at `:26-45`) — is referenced by **nothing in `lib/`**; its only callers are its own unit test (`test/core/theme/phase1_design_tokens_test.dart:60-66`). So no shipped focus indicator has the contrast halo, and the three implementations disagree on width (2.0 / 1.5 / 2.0) and on whether a glow is added.

**Hover and cursors are thin outside Material widgets.** `MouseRegion` appears in 8 files, `SystemMouseCursors` in 7. `PulsrButton`/`PulsrIconButton` do it properly (`pulsr_button.dart:294-299`, `pulsr_icon_button.dart:96-101`), and Material `InkWell`/`IconButton` supply hover + click cursor everywhere else — but the many bare `GestureDetector` controls (seek-bar duration toggle, up-next strip, widget-grid tiles) get neither a hover state nor a pointer cursor.

**Traversal order is handled.** `FocusTraversalGroup` + `FocusTraversalOrder` appear in 19 places including the shell (`app_shell.dart:439-530`), every sheet container (`pulsr_bottom_sheet.dart:325-345`, `:433-475` — asserted in `talkback_eyes_free_flow_test.dart:254-285`), settings and auth. Bottom-nav items carry `OrdinalSortKey(index)` (`bottom_nav_bar.dart:380`) so the dock traverses left-to-right. That is better than most Flutter apps.

**No desktop menu bar.** `MenuBar`/`PlatformMenu`/`MenuItemButton`: zero occurrences. Shortcut discoverability depends on `?` → `ShortcutHelpSheet` and the command palette.

### 2.5 Feedback & states — 7/10

**Haptics are centralized, gated and actually wired.** 436 `PulsrHaptics.*` call sites across the UI. Every call routes through a `ValueNotifier<bool>` gate (`pulsr_haptics.dart:14-20`), and the gate is set from persisted prefs at startup (`main.dart:210`), from the settings cubit on load (`settings_cubit.dart:1135`) and on toggle (`settings_accessibility_ext.dart:32`). No widget calls `HapticFeedback` directly — zero bypasses. Semantic variants exist for destructive (`heavyImpact`) and success (double-pulse, `:63-70`). Auditory feedback is a separate opt-in with its own gate (`sound_feedback_service.dart:38-84`), used 46 times.

`PulsrPressable` is the default press idiom: scale 0.96 with `easeOutBack` release, motion-gated (`pulsr_pressable.dart:43`, `:79`, `:103`), with a careful fix so long-press-only pressables don't stick at the pressed scale (`:112-118`). Row-level components use 0.985 (`pulsr_list_tile.dart`, `song_tile.dart`, `pulsr_switch.dart:309`) and the play button uses 0.92 (`player_controls.dart:327`).

**Three competing press languages.** `PulsrPressable` 36 sites (scale), `InkWell` 141 sites (ripple), bare `GestureDetector` 86 sites (nothing but the handler). Consequences: a `PulsrButton` compresses while the `IconButton` next to it ripples; the queue row ripples inside a `PulsrListTile` that also compresses; the seek-bar duration toggle gives no feedback at all. Not wrong individually — inconsistent as a system.

**Loading states are real, not spinners-of-last-resort.** `PulsrButton.loading` swaps the leading icon through `AnimatedSwitcher` and disables the tap (`pulsr_button.dart:252-275`, `:315`); transport shows a buffering spinner inside the play button while keeping it tappable (`player_controls.dart:391-401`); mini player mirrors it (`mini_player.dart:2040-2048`). Disabled states are consistent in intent: accent at 32% alpha + tertiary text (`pulsr_button.dart:137`), switch content at 45% opacity (`pulsr_switch.dart:187`), prev/next dimmed to 30% with a null `onTap` (`player_controls.dart:296`, `:483`).

**No error-shake primitive.** Nothing in `lib/` animates a field on validation failure; errors surface as `errorText` on `PulsrTextField` (`pulsr_text_field.dart:257`) or as a toast. For a music app this is tolerable, but the brief asks and the answer is "absent", not "different".

**Long-press is used 55 times** (queue row actions, nav command palette, A/B loop clear) with no discoverability affordance beyond the gesture sheet and haptics. On desktop, long-press is a poor affordance (`ReorderableDragStartListener` is the only place that acknowledges this).

### 2.6 Dynamic type & RTL — 6/10

**Text scaling is not suppressed at the app boundary.** The root builder clamps only to the OS range, `minScaleFactor: 0.8, maxScaleFactor: 2.0` (`main.dart:1392-1398`) with a comment stating the 200% intent. There is no 1.3 cap anywhere in the app shell — the common way Flutter apps cheat WCAG 1.4.4 and this app does not do it. `PulsrTextScaleScope` (which *would* cap at 1.5) exists but has zero call sites (`responsive_typography.dart:94-106`), so it is a trap waiting for the next developer rather than a live defect.

35 `textScaler` reads size layout to the user's setting (mini player height `52 * clamp(1.0,1.5)`, `mini_player.dart:674-677`; segmented-control label measurement, `pulsr_segmented_control.dart:237-268`; dock scale, `stacked_bottom_dock.dart:153-156`). 2.0× is asserted for `SongTile` + a dock button (`accessibility_compliance_test.dart:217-268`) and for the transport at 360dp (`player_transport_a11y_test.dart:141-160`).

**But the most-used row cancels the setting.** `SongTile` wraps its title/artist column in `FittedBox(fit: BoxFit.scaleDown)` with a fixed `SizedBox(width: textConstraints.maxWidth)` (`song_tile.dart:274-300`). At 200% the text does not grow — it is measured at 200%, found too wide, and scaled *back down* to fit the same row height. The user's accessibility setting is visually neutralized in the exact component that lists every song. `PulsrSegmentedControl` does the same by design (`_fitContent`, `:290-330`) and at least documents the trade-off ("scaled uniformly down only when the available width is still too small", `:36-38`).

**RTL is enforced, not aspirational — the strongest sub-result in this audit.** `test/architecture/rtl_ratchet_test.dart:8-41` fails the build if `Positioned(left|right:)`, `EdgeInsets.only(left|right:)` or `EdgeInsets.fromLTRB` appear outside generated code, with **baseline 0**; I ran it and it passes. 343 `EdgeInsetsDirectional` vs 187 `EdgeInsets.only` (the latter mostly `top/bottom`-only, which is direction-neutral). Arabic is a shipped locale (`app_localizations.dart:97-100`: ar, en, es), so the RTL path is a real product path. Custom painters mirror explicitly (`pulsr_slider.dart:322`, `:377-435`), switches use `AlignmentDirectional` + a signed slide (`pulsr_switch.dart:142`), and badges use `PositionedDirectional` (`pulsr_icon_button.dart:87`).

Deliberate non-mirroring, which should be documented rather than left implicit: the whole transport strip is forced LTR (`player_controls.dart:142-143`), so in Arabic shuffle stays left and repeat stays right while every surrounding row mirrors. Defensible (hardware-style transport), invisible to the ratchet (it only catches insets/positions), and unexplained in code.

**Localization of control labels is essentially complete**: 305 tooltips, and the ones I sampled resolve through `context.l10n` (`pulsr_search_field.dart:314`, `song_tile.dart:368`, `player_controls.dart:122`, `now_playing_screen.dart:426`). The leak is outside the control layer: 30+ hardcoded English user-facing strings in `ytm_error_classifier.dart` (e.g. `:442` "No connection. Check your network.", `:620` "This track is restricted in your region.") and `app_error.dart:113-232` — these reach toasts and therefore the screen reader.

---

## 3. Top gaps

1. **59 icon buttons render at 40×40 because of `visualDensity: VisualDensity.compact`** — including `mini_player.dart:2032-2039`, where an explicit 48dp constraint is defeated by the density adjustment. The design system declares 48 (`app_spacing.dart:56`) and the enforcement test covers exactly one widget.
2. **Duplicate screen-reader labels on the 5 core components** (`pulsr_list_tile.dart:166-170`, `pulsr_button.dart:309-312`, `pulsr_chip.dart:99-102`, `song_tile.dart:382-383`, `gestures_sheet.dart:83-84`): label + visible `Text` with no `excludeSemantics`, so rows are read twice. The seek bar proves the team knows the fix.
3. **Global arrow-key shortcuts shadow `DirectionalFocusIntent`** (`player_shortcut_scope.dart:88-190`): on desktop, arrows change volume/seek instead of moving focus, so keyboard navigation is Tab-only.
4. **The gesture map is documentation with no contract** (`gesture_map.dart` → only `gestures_sheet.dart`): no recognizer carries a map id, no test asserts a documented gesture exists, so the guide can lie.
5. **`FocusTokens` is dead code** (`focus_tokens.dart:9-49`, zero `lib/` callers): no focus ring in the app has the contrast halo, and three widgets implement three different rings.
6. **A 20–46dp tail in the player chrome**: 46×46 top-bar buttons (`player_theme_chrome.dart:1179-1181`), 34×34 bookmark close (`:1718-1733`), 22×22 chip delete (`pulsr_chip.dart:223`), ~20×20 switch info (`pulsr_switch.dart:343-364`), and 7 `minimumSize: Size.zero` / 12 `shrinkWrap` buttons.
7. **`FittedBox.scaleDown` in `SongTile`** (`song_tile.dart:274-300`) visually cancels 200% text scaling in the app's most common row; and the a11y suite's "eyes-free journey" test exercises a synthetic tree, not a Pulsr screen (`talkback_eyes_free_flow_test.dart:292-340`).

---

## 4. Path to 10/10

### P0 — fix before the next release

**P0-1 · Kill the 40dp cluster (root cause, not 59 patches).**
Add to the theme in `lib/core/theme/aura_theme.dart` (alongside `segmentedButtonTheme`): `iconButtonTheme: IconButtonThemeData(style: ButtonStyle(visualDensity: WidgetStatePropertyAll(VisualDensity.standard), tapTargetSize: WidgetStatePropertyAll(MaterialTapTargetSize.padded)))`. Then remove `visualDensity: VisualDensity.compact` from every `IconButton` in `lib/` (59 sites; `eq_sheet_shell.dart`, `eq_advanced_controls.dart`, `lyrics_view.dart`, `mini_player.dart:2037`/`:2063`, `settings/widgets/*`) — keep it on `TextButton`/`Checkbox` only where the surrounding row already provides a ≥48 box.
*Acceptance:* a new `test/architecture/hit_target_ratchet_test.dart` pumps the mini player, the queue view, the EQ sheet and the settings root, collects every `IconButton`/`PulsrIconButton`/`PulsrChip` descendant with a tap handler, and asserts `tester.getSize(...)` ≥ 48×48 (skipping those inside a `SizedBox.shrink`). Zero offenders. Manual: enable Android "Show tap target" in developer options and confirm no circle is smaller than the 48dp guide.

**P0-2 · De-duplicate semantics on the 5 core components.**
Add `excludeSemantics: true` to the `Semantics` at `pulsr_list_tile.dart:166`, `pulsr_button.dart:309`, `pulsr_chip.dart:99`, `song_tile.dart:382`, `gestures_sheet.dart:83` — the explicit label already carries everything the child text says (and for `pulsr_list_tile` include the subtitle in the label: `'$title, $subtitle'`).
*Acceptance:* extend `test/a11y/accessibility_compliance_test.dart` with `tester.getSemantics(find.byType(SongTile))` and assert `RegExp(title).allMatches(node.label).length == 1`; same for `PulsrListTile` and `PulsrButton`. Manual TalkBack pass on the library list: each row speaks once.

**P0-3 · Scope the arrow shortcuts to the player surface.**
In `lib/features/shell/presentation/widgets/player_shortcut_scope.dart`, split the binding map: keep Space/N/P/M/L/Q/F/`?`/Ctrl+K global, and move ←/→/↑/↓ into a `CallbackShortcuts` mounted inside `NowPlayingScreen`'s body (or gate them with `FocusManager.instance.primaryFocus?.context` being a descendant of the player route). Update `shortcut_help_sheet.dart` to say arrows work "in the player".
*Acceptance:* widget test — on a library screen, focus a `SongTile`, send `ArrowDown`, assert the next tile's `FocusNode.hasFocus` and that `PlayerCubit.adjustVolume` was **not** called; on Now Playing, `ArrowRight` seeks +10s and does not move focus.

**P0-4 · Fix the sub-48 one-offs in the player chrome.**
`player_theme_chrome.dart:1179-1181` (46→48), `:1718-1733` (34→48, keep the 34 visual via a centred `Icon`), `pulsr_chip.dart:223-231` (wrap the 22dp disc in a 48dp `SizedBox`+`Center`, move the `GestureDetector` outside), `pulsr_switch.dart:343-364` (48dp box + `Semantics(button: true, label: …)`), `player_seek_bar.dart:706-711` (min height 48) and `:312-320` (min height 48 + `Semantics(button: true)`), `speed_picker_sheet.dart:157-167`/`:229-235` (drop `Size.zero` + `shrinkWrap`), `search_screen.dart:2193-2197` (32→48).
*Acceptance:* same ratchet as P0-1 extended to these four screens.

### P1 — next design-system pass

**P1-1 · Make the gesture map a contract.** Add `String gestureId` to each recognizer's wrapper (a `PulsrGesture` widget that owns the `GestureDetector` and takes the map id), and derive `PulsrGestureMap.entries` coverage from it. New `test/architecture/gesture_map_coverage_test.dart`: every `PulsrGesture` id must exist in the map and vice versa; the sheet renders from the map (unchanged).
*Acceptance:* deleting a handler breaks compilation or the test; adding an undocumented drag fails the test.

**P1-2 · Adopt `FocusTokens` and unify the ring.** Replace the three hand-rolled rings (`pulsr_pressable.dart:167-181`, `pulsr_slider.dart:256-262`, `pulsr_switch.dart:217-221`) with `FocusTokens.ring(accent, isDark: …, radius: …)`, which already draws the contrast halo.
*Acceptance:* golden test of a focused button on an accent-tinted surface shows the halo; `FocusTokens.` has ≥3 non-test callers.

**P1-3 · Expose toggle state.** `toggled:` on shuffle/repeat (`player_controls.dart:167`, `:547`), `inMutuallyExclusiveGroup: true` on `PulsrSegmentedControl` (`:123`), and `MergeSemantics` on `PulsrSwitchListTile` so the row and the switch are one node.
*Acceptance:* `tester.getSemantics(...).flagsCollection.isToggled` / `hasCheckedState` asserted for shuffle, repeat, switch.

**P1-4 · Stop cancelling text scaling in `SongTile`.** Replace `FittedBox(scaleDown)` (`song_tile.dart:274-300`) with a single-line `Text` that ellipsizes plus a 2-line allowance when `MediaQuery.textScalerOf(context).scale(1) > 1.3`; drop the fixed row `minHeight` at large scale.
*Acceptance:* at 2.0× the title renders at ≥1.9× its nominal font size (measure `Text` size in a test), no overflow.

**P1-5 · Replace the synthetic a11y tests.** Rewrite `talkback_eyes_free_flow_test.dart:292-340` to pump the real `LibraryScreen`/`NowPlayingScreen` harness and walk `SemanticsNode`s (label + role + action), so a regression in any real row breaks the build.

### P2 — craft polish

**P2-1 · One press language.** Decide scale-vs-ripple per surface class and encode it in `PulsrPressable` (`ripple: bool`), then migrate the 86 bare `GestureDetector` tap targets to it — which also gives them hover + cursor (`MouseRegion` currently in 8 files).
**P2-2 · Error feedback primitive.** A `PulsrShake`/`PulsrInlineError` with `PulsrHaptics.error()` (already implemented, `pulsr_haptics.dart:71-79`) for validation failures, so `PulsrTextField`'s `errorText` is not the only signal.
**P2-3 · Desktop affordances.** `PlatformMenuBar` on macOS/Windows built from `PulsrGestureMap` + `PlayerShortcutScope` bindings, Escape → pop on the Now Playing route, and hover labels on the bare-`GestureDetector` controls.
**P2-4 · Document the intentional LTR transport.** Add a comment at `player_controls.dart:142` and an entry in `gesture_map`/docs so the next RTL pass doesn't "fix" it.

---

## 5. Already best-in-class — do not regress

- **48dp by construction** in all six primitives (`pulsr_button.dart:300`, `pulsr_icon_button.dart:105`, `pulsr_chip.dart:109`, `pulsr_slider.dart:266`, `pulsr_switch.dart:180`, `pulsr_segmented_control.dart:153`).
- **Single-node slider semantics with a `semanticFormatterCallback`** and a documented `excludeSemantics` reason (`player_seek_bar.dart:475-482`), asserted by test.
- **Live-region announcer** for track change / play state / queue mutations (`a11y_live_announcer.dart:63-140`), plus `liveRegion: true` toasts (`pulsr_toast.dart:499`).
- **`CustomSemanticsAction`s for invisible gestures** — swipe up/down/left/right on the mini player (`mini_player.dart:459-480`), dismiss on Now Playing (`now_playing_screen.dart:429-433`). This is the correct way to make a gesture-only affordance reachable, and it is rare.
- **RTL ratchet at a hard zero** (`rtl_ratchet_test.dart:8-41`, verified passing) with 343 directional insets.
- **Haptics behind one switch, wired to settings** (`pulsr_haptics.dart:14-20`, `main.dart:210`, `settings_cubit.dart:1135`) — 436 sites, zero bypasses.
- **Ordered focus traversal in every sheet and in the shell** (`pulsr_bottom_sheet.dart:325-345`, `app_shell.dart:439-530`), asserted by test.
- **Transport hit targets locked by test at 360dp** (`player_transport_a11y_test.dart:61-96`).

---

## 6. Unverified / out of scope

| Item | Status | How to settle |
| :--- | :--- | :--- |
| Merged-node duplication in TalkBack/VoiceOver speech | **High-confidence inference** from Flutter's `SemanticsConfiguration.absorb`; not device-dumped | `flutter run` + TalkBack focus on a `SongTile`; or `tester.getSemantics(...).label` (P0-2 acceptance) |
| `ScaleGestureRecognizer` vs `HorizontalDragGestureRecognizer` on the waveform | **Unverified** | `tester.startGesture` + `moveBy(Offset(-80,0))`, assert seek delta ≠ 0 and zoom unchanged |
| Escape behaviour on the Now Playing route | **Unverified** (no `DismissIntent` binding exists) | Desktop build, press Escape on `/now-playing` |
| Which of the 59 compact sites are M2 vs M3 button paths | Both paths subtract 8dp, so the conclusion holds either way | n/a |
| Pointer-cursor / hover coverage on touch-first surfaces | **Not exhaustively counted** (8 `MouseRegion` files, 7 cursor files) | static scan per screen |
| Contrast ratios of the three focus rings against accent-tinted surfaces | **Out of scope** (color audit); `FocusTokens`' halo is the intended fix and unused | run `test/a11y/contrast_matrix_test.dart` + add ring-on-surface cases |
| Web (CanvasKit) keyboard routing | **Out of scope** — desktop/web engine differences not exercised | browser run |
