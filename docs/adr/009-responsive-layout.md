# ADR 009: Responsive Layout and Breakpoint System

## Status
Accepted

## Context
Pulsr runs on phone portrait, phone landscape, foldables (closed/open, with hinges) and tablets/desktop. Ad-hoc `MediaQuery` checks (`if (width > 600)`) produced inconsistent layouts, magic numbers duplicated across features, and typography/radius values that did not scale. Foldables added a new concern: content must not sit under a physical hinge.

## Decision
We centralize responsive behaviour under `lib/core/responsive/`, driven by a single breakpoint enum.

### 1. Breakpoint tiers
`PulsrBreakpoint` (`breakpoints.dart`) defines four tiers and is the single source of truth:
- `compact` (0–599 dp)
- `medium` (600–839 dp)
- `expanded` (840–1199 dp)
- `large` (1200+ dp)

`PulsrBreakpoint.fromWidth` maps a width to a tier; `PulsrBreakpoint.of(context)` reads `MediaQuery.sizeOf`. The `PulsrBreakpointContextX` extension exposes `context.breakpoint`, `isCompact` … `isLarge` and hinge helpers. Tiers are `Comparable` and support `<`/`>`/`<=`/`>=` for threshold logic.

### 2. Responsive values, not duplicated conditionals
`ResponsiveValues<T>` (`responsive_values.dart`) resolves a compact/medium/expanded/large fallback chain, so a value only specifies the tiers where it differs. `ResponsiveSpacing`, `ResponsiveFontSize`, `ResponsiveRadius` and `ResponsiveIconSize` build on it, and `PulsrResponsiveTokens` is reachable as `context.responsive` (padding, gap, font scale, radii, icon sizes).

### 3. Foldable/hinge awareness
`PulsrBreakpoint.hinge(context)` inspects `MediaQuery.maybeDisplayFeaturesOf` for a `hinge`/`fold`, and is exposed as `context.foldableHinge`/`hasFoldableHinge`; `pulsr_hinge_gap.dart` and the two-pane scaffolds consume it to keep content clear of the physical seam.

### 4. Layout primitives
`adaptive_grid.dart`, `layout_delegate.dart`, `two_pane_scaffold.dart`, `detail_scaffold.dart`, `responsive_sheet.dart`, `pulsr_layout_metrics.dart` and `landscape_compact_adapter.dart` build the shared list/grid/detail/sheet layouts on top of the tiers, so features compose primitives instead of re-deriving breakpoints.

## Consequences
### Positive
- One breakpoint definition; feature code selects values declaratively through `ResponsiveValues`/`context.responsive`.
- Foldable hinges are handled in shared primitives rather than per screen.
- Typography, spacing, radii and icon sizes scale coherently across tiers.

### Negative / Trade-offs
- Adding a tier or changing thresholds is a cross-cutting change; every `ResponsiveValues` chain relies on the fallback order (`large → expanded → medium → compact`).
- `of(context)` depends on `MediaQuery`, so responsive widgets still rebuild on size changes (mitigated by using `sizeOf` rather than the whole MediaQuery).
