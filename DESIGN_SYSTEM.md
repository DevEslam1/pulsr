# Pulsr Design System

Single source of truth for colour, spacing, radii, typography, motion and the
shared component inventory. Everything below lives under `lib/core/` and is
guarded by `test/core/constants/tokens_lock_test.dart`; prefer these tokens
over raw literals so Light / Dark / AMOLED and reduce-motion stay consistent.

## 1. Colour

### Semantic palette — use first

Widgets read surfaces and text from the active theme via
`context.palette` (`PulsrPalette` in `lib/core/theme/aura_theme.dart`):

| Token | Role |
|---|---|
| `accent` / `onAccent` / `accentContainer` | Primary action fill, text on it, soft tinted container |
| `glow` | Shadows and halos derived from the accent |
| `bg` / `surface` / `surfaceContainer` / `surfaceContainerHigh` | Page, card, raised and overlay surfaces |
| `hairline` | 1 px borders and dividers |
| `textPrimary` / `textSecondary` / `textTertiary` | Text hierarchy |
| `favorite` / `success` / `error` / `warning` / `info` | Status roles |
| `playerCard` / `deepShade` / `isDark` | Player-specific surfaces and brightness flag |

The palette is built by `AuraTheme` from an accent colour (dynamic colour aware)
in Light, Dark and AMOLED variants.

### Raw values — only for identity and overlays

`AppColors` (`lib/core/constants/app_colors.dart`) holds fixed values that are
intentionally *not* theme-driven:

- **Brand / feature accents** — `primary`, `secondary`, `accentCyan`, `dacGold`,
  `ytRed`, `spotifyGreen`, `studioGreen`, `ldacViolet`, …
- **Category identity tints** — `tab*`, `cat*`, `qualityBadge*`, `roomPoint*`.
- **Physical materials** — `disc*`, `surfaceGrey*`, `vinyl*` for the
  skeuomorphic player themes.
- **Overlay tokens** — the replacement for ad-hoc `Colors.black/white.withValues`:

| Token | Value | Use |
|---|---|---|
| `scrim` | 65 % black | Modal / player scrims |
| `scrimLight` | 45 % black | Light scrims on elevated surfaces |
| `scrimStrong` | 85 % black | Heavy media overlays |
| `specular` | 7 % white | Hairline highlights |
| `specularStrong` | 14 % white | Stronger sheen |
| `highlightSoft` | 4 % white | Softest wash |
| `scrimAt(alpha)` / `specularAt(alpha)` | black / white at a custom alpha | Theme-dependent opacities |

`ScrimTokens` (`lib/core/theme/scrim_tokens.dart`) wraps these for barriers,
player surfaces and the dock gradient.

## 2. Spacing — 4 px base

`AppSpacing` (`lib/core/constants/app_spacing.dart`):

| Semantic | `xxs` | `xs` | `sm` | `md` | `lg` | `xl` | `xxl` |
|---|--:|--:|--:|--:|--:|--:|--:|
| dp | 4 | 8 | 12 | 16 | 24 | 32 | 48 |

Half-steps `s2 … s64` preserve legacy chrome (badges, dense rows).
`minTouchTarget = 48` is the WCAG/Material minimum hit area and
`scrollBottom = 160` clears the mini-player + nav dock.

## 3. Radii

`AppRadii` (`lib/core/constants/app_radii.dart`):

| Semantic | tile | card | button | artwork | bottomSheet | chip | miniPlayer | dialog | full |
|---|--:|--:|--:|--:|--:|--:|--:|--:|--:|
| dp | 14 | 18 | 14 | 20 | 28 | 10 | 24 | 26 | 999 |

Numeric tokens `r1_5, r2, r4, r6, r8, r10, r12, r14, r16, r18, r20, r22, r24,
r26, r28, r32` cover one-off geometry. Squircle variants
(`squircleTile/Card/Artwork/MiniPlayer/Dialog/BottomSheet/Pill`, multiplier
`2.2`) follow the iOS continuous-curvature look.

## 4. Typography

`AppFontSize` / `AppTracking` (`lib/core/constants/app_typography.dart`):

| Token | nano | micro | tiny | caption | label | bodySmall | body | callout | bodyLarge | title | titleLarge | headline | display | displayLarge |
|---|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|
| sp | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 | 16 | 18 | 20 | 24 | 28 | 32 |

Tracking: `display −0.8`, `heading −0.4`, `title −0.2`, `none 0`,
`label 0.3`, `medium 0.5`, `overline 0.8`, `wide 1.2`, `widest 2.0`.
The app font is **Manrope**; responsive scaling helpers live in
`lib/core/responsive/`.

## 5. Motion

`PulsrDurations` (`lib/core/motion/motion_durations.dart`) — canonical rhythm:

| Token | tap | state | layout | page | ambient |
|---|--:|--:|--:|--:|--:|
| ms | 120 | 200 | 260 | 320 | 400 |

`PulsrMotion` (`lib/core/motion/pulsr_motion.dart`) adds
`instant 90`, `fast/snappy 150`, `standard 250`, `slow 400`,
`expressive 600`, the aliases above, and the reduce-motion API:

```dart
context.motion(PulsrMotion.state); // Duration.zero when reduce motion is on
context.motionMs(250);
context.motionCurve(Curves.easeOut);
```

Infinite/decorative animations should check `context.motionEnabled` first.

## 6. Component inventory

### Foundation widgets (`lib/core/widgets/`)

| Component | Purpose |
|---|---|
| `PulsrCard`, `PulsrSurface`, `GlassContainer` | Elevated / glass surfaces |
| `PulsrDialog`, `PulsrBottomSheet`, `PulsrAdaptiveSheet` | Dialog and sheet scaffolding |
| `PulsrPressable`, `PulsrSegmentedControl`, `PulsrSwitch`, `PulsrSlider`, `PulsrDismissible` | Controls |
| `PulsrSearchField`, `PulsrRefreshIndicator`, `PulsrBackButton`, `PulsrPagePopScope` | Input / navigation chrome |
| `SongTile`, `CachedArtwork`, `ArtworkPlaceholder`, `SpinningVinylDisc`, `WaveformLogo` | Music-specific media |
| `PulsrEmptyState`, `PulsrErrorBoundary`, `AsyncStateBuilder`, `ShimmerSkeleton` / `SkeletonList` / `SkeletonGrid` | Async & empty/error states |
| `PulsrSectionHeader`, `SectionHeader`, `PulsrStaticGrid`, `StaggeredList`, `StaggeredReveal` | Layout / structure |
| `PulsrToast`, `PulsrSnackBar`, `MarqueeText`, `HighlightedText`, `PulsrLogo`, `GestureHintOverlay` | Feedback & text |
| `PulsrDockTracker`, `PulsrModalTracker` | Dock/modal visibility coordination |

`AsyncStateBuilder<T>` renders the four `AsyncSnapshot` states in one place:
loading defaults to `SkeletonList`, error to a retry card, empty to
`PulsrEmptyState`, and everything is overridable via
`loadingWidget` / `onError` / `emptyWidget` / `isEmpty` / `onRetry`.

### Player chrome (`lib/features/player/presentation/themes/`)

`PlayerThemeChrome` provides the shared top bar, symmetrical track header,
controls column, view switcher, dock icons and favourite button used by all
eight themes; `PlayerThemeScaffold` composes them for new themes.
Player-only painters live under `themes/painters/`.

### Async / feedback

`PulsrErrorBoundary` catches render errors, `PulsrEmptyState` is the standard
empty illustration, and `AsyncStateBuilder` is the standard data-state renderer.

## 7. Rules of thumb

1. Read surfaces/text from `context.palette`; use `AppColors` only for fixed
   identity colours and overlays.
2. Never hard-code radii, spacing, font sizes or animation durations — use the
   token scales above (`AppRadii.rN`, `AppSpacing.*`, `AppFontSize.*`,
   `PulsrDurations.*` / `context.motion*`).
3. Icon-only controls need a tooltip, a semantic label and a ≥48 dp hit area.
4. Route animation timing through `context.motion*` so Reduce Motion is honoured.
5. New async UI goes through `AsyncStateBuilder`; new empty states use
   `PulsrEmptyState`.
