# Pulsr Design System

The single source of truth for every screen, sheet, and widget. Follow this when
building anything new so Pulsr keeps one visual language and stays at parity with
the best-in-class players (Apple Music, Spotify, Plexamp, Poweramp).

> Golden rule: **never hardcode a colour, size, radius, tracking, duration, or
> padding.** Consume a token. If a token is missing, add it to the token file
> first, then use it.

---

## 0. Principles

1. **One rhythm.** Everything sits on a 4-pt base grid (Apple HIG + Material 3).
2. **Symmetry first.** Content, titles and actions share one leading/trailing
   edge (`Adaptive.pagePadding`).
3. **Calm motion.** Short, eased, purposeful; respects Reduce Motion.
4. **Theme-safe.** Every surface reads `context.palette`; it must look right in
   Dark, Light, AMOLED, and High-Contrast.
5. **Accessible by default.** ≥48 dp targets, semantics on every control,
   dynamic type clamped, RTL-correct (`Directional` APIs only).
6. **Reuse over rebuild.** Reach for `core/widgets/*` before writing a new one.

---

## 1. Colour

### 1.1 Semantic palette (always use this in UI)

```dart
final p = context.palette; // PulsrPalette via ThemeExtension
```

| Token | Role |
|---|---|
| `p.accent` / `p.primary` | brand accent for the active theme |
| `p.onAccent` | foreground on top of `accent` |
| `p.accentContainer` | soft accent fill (~12–16% alpha) |
| `p.glow` | shadow / halo colour |
| `p.bg` / `p.background` | scaffold background |
| `p.surface` | card / sheet surface |
| `p.surfaceContainer` / `p.surfaceCard` | elevated surface |
| `p.surfaceContainerHigh` / `p.surfaceVariant` | highest surface |
| `p.hairline` | 1 px borders / dividers |
| `p.textPrimary` / `textSecondary` / `textTertiary` | text hierarchy |
| `p.favorite`, `p.success`, `p.error`, `p.warning`, `p.info` | status |
| `p.isDark` | branch for the rare dark/light-only tweak |

Source: `lib/core/theme/aura_theme.dart` (`PulsrPalette`, `AuraTheme`).

**Do**: `color: p.textSecondary`
**Don't**: `color: Colors.grey`, `color: Color(0xFF98A0B3)`

### 1.2 Fixed brand / feature colours

These identify a *source* (not a surface) and intentionally do not change with
the theme. Use the `AppColors` constants — never a raw hex.

`AppColors.dacGold, ytRed, ytRedDeep, netflixRed, studioGreen, ldacViolet,
accentCyan, skyBlue, emeraldDeep, roseDeep, amberDeep, slate, darkSurface,
mint, azure` — source: `lib/core/constants/app_colors.dart`.

```dart
color: AppColors.dacGold   // Hi-Res / USB-DAC tier
color: AppColors.ytRed     // YouTube family
```

`Colors.white` / `Colors.black` are acceptable only for pure overlays/scrims and
shadows on top of media (album art), never as text or surface colours.

---

## 2. Typography

Sizes come from `AppFontSize`; tracking from `AppTracking`
(`lib/core/constants/app_typography.dart`).

| `AppFontSize` | px | Role |
|---|---|---|
| `micro` | 9 | badges, counters |
| `tiny` | 10 | dense micro-labels |
| `caption` | 11 | captions, timer readouts |
| `label` | 12 | chips, meta, overlines |
| `bodySmall` | 13 | secondary rows |
| `body` | 14 | default body |
| `callout` | 15 | emphasised body |
| `bodyLarge` | 16 | song titles, list primary |
| `title` | 18 | section / card titles |
| `titleLarge` | 20 | screen titles |
| `headline` | 24 | large headings |
| `display` | 28 | hero headings |
| `displayLarge` | 32 | numeric hero values |

| `AppTracking` | value | Role |
|---|---|---|
| `display` | −0.8 | large display / hero numerals |
| `heading` | −0.4 | headings |
| `title` | −0.2 | titles |
| `none` | 0.0 | body copy |
| `label` | 0.3 | labels |
| `medium` | 0.5 | medium-emphasis labels |
| `overline` | 0.8 | overlines / small caps |
| `wide` | 1.2 | wide overlines |
| `widest` | 2.0 | extra-wide branding |

**Weights:** only `w400 w500 w600 w700 w800 w900`. Never `FontWeight.bold`
(use `w700`). Display/headings use `w800/w900`, titles `w700`, body `w400/w500`.

```dart
Text('Recently added',
    style: TextStyle(
      color: p.textPrimary,
      fontSize: AppFontSize.bodyLarge,
      fontWeight: FontWeight.w700,
      letterSpacing: AppTracking.title,
    ));
```

Prefer the theme's `textTheme` for standard copy
(`Theme.of(context).textTheme.headlineMedium`) and `AppFontSize` for anything
bespoke. Line height: keep default for body; use a tight `height: 1.1–1.3` only
inside fixed-height chrome.

---

## 3. Spacing

4-pt scale — `AppSpacing` (`lib/core/constants/app_spacing.dart`).

`xxs=4 · xs=8 · sm=12 · md=16 · lg=24 · xl=32 · xxl=48`
Half-steps: `s2=2 · s6=6 · s10=10 · s14=14 · s18=18 · s20=20 · s28=28 · s40=40 · s64=64`
`AppSpacing.scrollBottom = 160` — bottom padding so content clears the dock.

- **Screen gutters:** always `Adaptive.pagePadding(context)` (12/16/24/32 by
  width). Never a literal.
- **Gaps between top-level sections:** `AppSpacing.md` (16); use `lg` (24)
  between grouped cards in Settings.
- **Card internal padding:** `AppSpacing.md` horizontal, `sm`/`xs` vertical.
- **Scrollable list bottom inset:** `AppSpacing.scrollBottom`.

```dart
Padding(
  padding: EdgeInsetsDirectional.fromSTEB(
      Adaptive.pagePadding(context), AppSpacing.md, Adaptive.pagePadding(context), 0),
  child: ...,
)
```

---

## 4. Shape & radii

`AppRadii` (`lib/core/constants/app_radii.dart`).

Semantic: `tile=14 · card=18 · button=14 · artwork=20 · bottomSheet=28 ·
chip=10 · miniPlayer=24 · dialog=26 · full=999`
Numeric (`r2 … r32`) for everything else.

- Buttons/tiles → `AppRadii.buttonRadius` / `tileRadius`
- Cards → `AppRadii.cardRadius`
- Sheets → `AppRadii.bottomSheetRadius`
- Artwork → `AppRadii.artworkRadius` (or `resolveCustomRadius(context, fallback)`
  for the Now Playing artwork so the Custom Theme Studio applies)
- iOS-style continuous curvature → `AppRadii.squircle(radius)` /
  `squircleCard` / `squircleArtwork`

Never call `BorderRadius.circular(<literal>)`.

---

## 5. Motion

`PulsrMotion` (`lib/core/motion/pulsr_motion.dart`).

| Token | ms | Use |
|---|---|---|
| `instant` | 90 | icon tint / selection feedback |
| `fast` | 150 | press states, small fades |
| `standard` | 250 | standard transitions |
| `slow` | 400 | sheets, hero, artwork |
| `expressive` | 600 | entrance choreography |

**Always resolve through context** so Reduce Motion is honoured:

```dart
AnimatedContainer(
  duration: context.motionMs(250),          // collapses to 0 when reduced
  curve: context.motionCurve(Curves.easeOutCubic),
  ...
)
```

- For a one-shot controller, create it in `initState` then set
  `controller.duration = context.motionMs(N)` in `didChangeDependencies`.
- Gate infinite/decorative loops with `context.motionEnabled`.
- Repeated widgets in tests cause `pumpAndSettle` timeouts — guard
  `controller.repeat()` with
  `!WidgetsBinding.instance.runtimeType.toString().contains('Test')`
  (see `PulsrSlider`).

---

## 6. Elevation & surfaces

- Cards: `elevation: 0`, a `p.hairline` border, radius `cardRadius`, and a soft
  shadow — never a heavy drop shadow.
- Glass surfaces: `GlassContainer` (blur + tint) or the hand-rolled recipe used
  by the dock (gradient `p.surface`→`p.surfaceContainer`, blur 25, hairline
  border). Keep the dock (mini player + nav bar) visually identical.
- Overlay charts (Now Playing) sit on album art: use a scrim
  (`Colors.black.withValues(alpha: 0.4)` dark, `0.72` light) to keep contrast.

---

## 7. Layout & adaptive

`Adaptive` (`lib/core/utils/adaptive.dart`).

| Breakpoint | Value | Layout |
|---|---|---|
| `compactBreakpoint` | 600 | phone |
| `tabletBreakpoint` | 700 | tablet (rail on tablets, both orientations) |
| `railExtendedBreakpoint` | 1000 | sidebar expands |
| `maxContentWidth` | 1160 | centre-rail clamp |
| `maxSheetWidth` | 620 | sheet/dialog clamp |

```dart
Center(child: ConstrainedBox(
  constraints: Adaptive.contentConstraints(context),
  child: ...,
));
```

- `Adaptive.pagePadding(context)` for gutters.
- `Adaptive.gridColumns(context, minItemWidth: 150)` for responsive grids.
- `context.trackGridColumns` for song grids (1/2/3).
- Tablets use the landscape rail in both orientations; phones use the bottom
  dock portrait and landscape.

---

## 8. Navigation / information architecture

- **Primary dock — 5 destinations:** Home · Library · Search · Playlists ·
  Settings (`pulsrDestinations`). Single source of truth — the dock and rail
  both consume it.
- **Settings** is a primary destination (`settingsDestinationIndex`) and is also
  still reachable from the Home header gear.
- **Library tabs — 5:** Songs · Downloaded · Albums · Artists · Favorites.
  Folders · Genres · Years live behind the "Jump to Category" sheet.
- **Deep links:** album/artist/playlist resolve from `?id=` via
  `EntityByIdLoader<T>` — never require a typed `extra` for a shareable page.
- Tabs cross-fade (`_buildTabPage`); detail pushes slide + fade
  (`_buildPulsrPageRoute`). Both are motion-aware.

---

## 9. Components (reuse these)

| Component | Path | Notes |
|---|---|---|
| `PulsrSegmentedControl` | `core/widgets/pulsr_segmented_control.dart` | the only segmented control |
| `SectionHeader` | `core/widgets/section_header.dart` | aligns to content gutter |
| `SongTile` | `core/widgets/song_tile.dart` | list rows |
| `CachedArtwork` | `core/widgets/cached_artwork.dart` | all artwork |
| `PulsrSlider` | `core/widgets/pulsr_slider.dart` | wavy slider |
| `PulsrSwitch`, `PulsrPressable`, `PulsrDismissible` | `core/widgets/` | interactions |
| `PulsrBottomSheetContainer` / `PulsrSheetHelper` | `core/widgets/pulsr_bottom_sheet.dart` | every sheet |
| `PulsrDialogHelper` / `PulsrDialog` | `core/widgets/pulsr_dialog.dart` | every dialog |
| `EmptyStateWidget` | `core/widgets/empty_state_widget.dart` | empty **and** error states |
| `SkeletonBox/Line/List/Grid`, `SkeletonShimmer` | `core/widgets/shimmer_skeleton.dart` | loading |
| `StaggeredReveal` | `core/widgets/staggered_reveal.dart` | sort/re-flow entrance |
| `EntityByIdLoader<T>` | `core/widgets/entity_by_id_loader.dart` | id-based deep links |
| `SettingSliderRow` | `features/settings/.../settings_slider_row.dart` | labelled slider |

---

## 10. States — every async surface needs all four

1. **Loading** → a skeleton that matches the final layout, wrapped in
   `SkeletonShimmer` (one ticker, synchronized sweep). Use `SkeletonList` for
   rows, `SkeletonGrid` for grids. Never a bare `CircularProgressIndicator` for
   *content* loading (spinners are for button/inline progress only).
2. **Empty** → `EmptyStateWidget` with a clear CTA.
3. **Error** → `EmptyStateWidget` with the error icon, the failure message, and
   a Retry action. A repository `AppFailure` arrives as a `Left` **value**, not a
   stream error — check both (`snapshot.hasError || data.isLeft`).
4. **Content** → animated in via `StaggeredReveal`, keyed by the sort/group
   signature so re-sorting replays the cascade.

---

## 11. Accessibility (non-negotiable)

- **Targets** ≥ 48 dp (44 dp absolute minimum on dense chrome).
- **Semantics** on every non-text control: icon buttons get `tooltip:`, sliders
  get `semanticLabel` + `increasedValue`/`decreasedValue`, custom toggles get
  `Semantics(toggled:/selected:)`.
- **Haptics:** `HapticFeedback.selectionClick()` (nav/selection),
  `lightImpact()` (press), `mediumImpact()` (commit/success).
- **Dynamic type:** the app clamps to 0.8–2.0 at the root. In fixed-height
  chrome (nav bar, mini player) wrap with
  `MediaQuery.withClampedTextScaling(maxScaleFactor: 1.15)`.
- **Reduce Motion:** never animate without `context.motionMs`/`motionEnabled`.
- **Contrast:** verify text/icons against `p.surface` in Light and
  High-Contrast, not just Dark.

---

## 12. Localization & RTL

- All user-facing strings go through `context.l10n.<key>` (EN/ES/AR in
  `lib/l10n/app_*.arb`). Add keys to all three ARBs and run `flutter gen-l10n`.
- **Directional APIs only:** `PositionedDirectional`, `EdgeInsetsDirectional`,
  `AlignmentDirectional`, `BorderRadiusDirectional`. Never `Positioned(left:)`,
  `EdgeInsets.only(left:)`, `Alignment.centerLeft`, or `TextAlign.left`.
  (Exception: gradients inside `CustomPainter`s use plain `Alignment` — they have
  no `TextDirection`.)
- The `rtl_ratchet_test` enforces a **zero** non-directional-site count.

---

## 13. New-screen recipe

```dart
class MyScreen extends StatelessWidget {
  const MyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(title: Text(context.l10n.myTitle), leading: const PulsrBackButton()),
      body: Center(
        child: ConstrainedBox(
          constraints: Adaptive.contentConstraints(context),
          child: ListView(
            padding: EdgeInsetsDirectional.fromSTEB(
                Adaptive.pagePadding(context), AppSpacing.md,
                Adaptive.pagePadding(context), AppSpacing.scrollBottom),
            children: [ /* ... */ ],
          ),
        ),
      ),
    );
  }
}
```

---

## 14. Pre-merge checklist

- [ ] No raw hex colours, `Colors.*` surfaces, or literal font sizes/radii.
- [ ] Gutters use `Adaptive.pagePadding`; gaps use `AppSpacing`.
- [ ] All animations use `context.motionMs` / `context.motionCurve`.
- [ ] Loading, empty, and error states all handled (Left-aware).
- [ ] Controls ≥48 dp with semantics/tooltips; haptics on meaningful actions.
- [ ] Only `Directional` positioning/insets; verified for RTL.
- [ ] New strings added to EN/ES/AR and `flutter gen-l10n` run.
- [ ] `flutter analyze` clean and `flutter test` green.
- [ ] Sanity-checked in Dark, Light, AMOLED, and 200% font scale.

---

*Reference files: `lib/core/constants/app_{colors,spacing,radii,typography}.dart`,
`lib/core/theme/aura_theme.dart`, `lib/core/motion/pulsr_motion.dart`,
`lib/core/utils/adaptive.dart`, `lib/core/widgets/`.*
