# Audit — Blur, Materials & Depth

**Repo:** `D:\Courses\Projectss\pulsr` · Flutter UI via vendored `package:material_ui/material_ui.dart`
**Scope:** backdrop blur coverage, blur correctness/perf, fallbacks, elevation system, light/dark/AMOLED parity, "liquid glass" identity
**Method:** static read of the design-system primitives + every surface named in the brief; call-site counts by repo-wide grep. No runtime/profile capture was performed — perf claims are structural (raster/layer reasoning), not measured frame timings.
**Date:** 2026-11-18

---

## 0. Correction to the given premise

The brief states: *"the whole repo has only 3 `BackdropFilter` call sites (`glass_container.dart`, `app_blur.dart`, `bottom_nav_bar.dart`) while tokens define 6 blur presets."*

The count of 3 is right, the file attribution is not:

| Claim | Reality |
|---|---|
| 3 `BackdropFilter` call sites | **3 confirmed** — but in **2 files**, not 3 |
| `app_blur.dart` contains a call site | **False.** `app_blur.dart` is a pure token/gating file; it imports `dart:math` and `gpu_budget`, and never constructs a `BackdropFilter` (`lib/core/constants/app_blur.dart:1-59`) |
| — | `glass_container.dart` holds **2** (`:233`, `:242`); `bottom_nav_bar.dart` holds **1** (`:325`) |
| 6 blur presets | **Confirmed** — `chip 8 / standard 12 / nav 14 / dialog 16 / sheet 20 / dock 24` (`app_blur.dart:24-43`) |

Two further blur sites use `ImageFilter.blur` (not `BackdropFilter`) and are routinely missed by a `BackdropFilter` grep:
`lib/features/player/presentation/widgets/canvas_backdrop.dart:321` and `lib/features/player/presentation/widgets/lyrics/advanced_lyrics_view.dart:354`.

**Total blur sites = 5 across 4 files.** A repo-wide ratchet test already enforces that every `ImageFilter.blur` file mentions `AppBlur` (`test/architecture/ui_ux_10_ratchet_test.dart:64-79`).

---

## 1. Score table

| Dimension | Score | One-line verdict |
|---|:--:|---|
| Blur coverage | **2 / 10** | Glass is declared, not shipped: 2 surfaces in the entire app render a visible backdrop blur. |
| Blur correctness & perf | **6 / 10** | The primitive is genuinely well-engineered; the two call sites that use it each carry a defect. |
| Fallbacks & contrast | **8 / 10** | Best-in-class solid fallback ladder — but it is gated on a signal the app's own setting never sets. |
| Elevation system | **3 / 10** | An excellent dual-shadow scale exists and is out-adopted 8:1 by hand-rolled shadows; a second scale is dead code. |
| Light / dark / AMOLED parity | **5 / 10** | Light mode is handled properly; AMOLED makes blur optically meaningless and nothing compensates. |
| Material identity ("liquid glass") | **2 / 10** | The liquid tier is unreachable dead API; nothing in the product reads as a distinct material. |

**Overall: 4.3 / 10** — a design system with a strong skeleton and almost no muscle. The tokens, gating, tests and elevation math are better than most production apps; the adoption is at prototype level.

---

## 2. Findings

Ordered by strength of support for the summary.

### F1 — The glass primitive is essentially unreachable: 4 constructions in 4 files, 0 indirect consumers · *verified*
Repo-wide `GlassContainer` constructions, excluding its own definition and its single import line in `pulsr_surface.dart`:

| File | Sites |
|---|---|
| `lib/core/widgets/pulsr_dialog.dart` | 1 (`:425`) |
| `lib/core/responsive/responsive_sheet.dart` | 1 (`:99`) |
| `lib/features/player/presentation/widgets/usb_rate_switch_dialog.dart` | 1 |

`PulsrSurface` — the documented "unified interactive surface combining glass/solid materials" that would have distributed glass across cards and tiles — has **4 references, all inside its own file**: zero consumers (`lib/core/widgets/pulsr_surface.dart`). Its own `GlassContainer` construction is therefore dead too, leaving 3 reachable constructions.

Consequence: of those three, `responsive_sheet.dart:99` uses `GlassContainer.solid` (blur deliberately off by constructor, `glass_container.dart:87-104`), and `pulsr_dialog` passes an opaque colour (see F2). **Only `usb_rate_switch_dialog` — a niche USB sample-rate confirmation dialog — renders true, visible glass**, via `color: p.surface.withValues(alpha: 0.85)` + `blur: 24` (clamped to 18).

The one high-traffic glass surface is not `GlassContainer` at all: the nav dock hand-rolls its own `BackdropFilter` (`bottom_nav_bar.dart:325-331`).

### F2 — The dialog runs a full BackdropFilter and then paints over it: blur is a pure GPU cost · *verified*
`pulsr_dialog.dart:425-429`:
```dart
child: GlassContainer.fromPreset(
  preset: GlassPreset.dialog,
  ...
  color: p.surfaceContainerHigh,
```
`GlassContainer` only applies the translucency maths when `color` is null (`glass_container.dart:159-161`):
```dart
final base = color ?? (p.isDark ? p.surfaceContainer : p.surface);
final baseColor =
    color == null ? base.withValues(alpha: base.a * tintAlpha) : base;
```
`p.surfaceContainerHigh` is fully opaque in every scheme — `0xFFE4E4E4` light (`aura_theme.dart:422`), `0xFF17171D` AMOLED (`:554`), `0xFF212635` dark (`:592`). With `specularHighlight: true`, the gradient path also uses this opaque base (`glass_container.dart:181-197`).

So every `PulsrDialog` pays an 18σ backdrop blur over the barrier scrim and composites an opaque slab on top of it. **The app's only `GlassPreset` consumer is a no-op visual with a real per-frame price.** This is the single most damaging defect in the audit: it is simultaneously evidence that glass is wired up and that it does not work.

### F3 — The most-seen surfaces are opaque by construction, and two of them advertise glass · *verified*
| Surface | Treatment | Evidence |
|---|---|---|
| Bottom sheet (all sheets, app-wide) | Opaque gradient; **no BackdropFilter**. Docstring: *"A responsive, frosted-glass container wrapper for all bottom sheets"* | `pulsr_bottom_sheet.dart:206` (claim) vs `:355-359` (`alpha: 0.96` dark / `0.98` light) |
| Mini player | Opaque gradient over `surfaceContainerHigh`→`surfaceContainer`; no blur | `mini_player.dart:606-624` |
| Toast | Opaque `surfaceContainerHigh` lerp; docstring: *"styled in Pulsr's signature glass aesthetic"* | `pulsr_toast.dart:37` (claim) vs `:508-521` |
| Now-playing queue overlay | `surfaceContainer.withValues(alpha: 0.85)` + `surfaceContainerHigh`; no blur | `now_playing_queue_view.dart:192`, `:264` |
| Context menus | No `popupMenuTheme` in the theme at all; 12 raw `PopupMenuButton` | `aura_theme.dart` (0 hits) |
| Nav dock | **Glass** — `BackdropFilter`, 0.88/0.84 gradient | `bottom_nav_bar.dart:207-224`, `:325-331` |

Three separate surface docstrings promise frost that the code does not deliver. On a player whose Now Playing screen is full-bleed artwork, the mini player is the surface most obviously *entitled* to backdrop blur — it floats over cover art all day — and it is a solid slab.

### F4 — Elevation: a strong scale, out-adopted 8:1, plus a dead duplicate · *verified*
`PulsrElevation` is genuinely well-designed: every level pairs a tight directional key shadow with a wide ambient one, and light mode globally halves the ink (`pulsr_elevation.dart:31-49`, `scale = isDark ? 1.0 : 0.45` at `:88`). The docstring even states the rationale — *"Single-shadow elevation reads as a grey sticker"*.

Adoption:
- **22** `PulsrElevation` references across **5** files (mostly `pulsr_card.dart`: 10).
- **183** raw `BoxShadow(` constructor calls across **87** files. Ratio ≈ **8:1 ad-hoc**.
- **20 distinct `blurRadius` values** in those raw shadows: `0, 2.5, 4, 4.5, 5, 6(19×), 8(27×), 10(21×), 12(14×), 14(11×), 16(15×), 18(13×), 20, 22, 24(8×), 28(11×), 30, 32, 34, 36(7×)`. There is no scale in use — there is a continuum.
- `AppElevation` (`lib/core/constants/app_elevation.dart`, e0–e3) is a **second, incompatible scale with zero consumers** — 1 reference, its own definition. Dead code that will confuse the next engineer into picking the wrong one.
- Theme-level elevation is inconsistent with both tokens: `bottomSheetTheme.elevation: 24`, `dialogTheme.elevation: 24` (`aura_theme.dart:923`, `:931`) alongside `PulsrElevation.level3` blur 10/24.

Concrete ad-hoc examples superseding the scale: `pulsr_bottom_sheet.dart:387` (blur 20, offset `(0,-4)`), `pulsr_toast.dart:484` (blur 18, offset `(0,6)`), `mini_player.dart:586-601` (blur 22 + accent glow), `bottom_nav_bar.dart:165-185` (blur 18 + accent glow).

### F5 — The one working glass has the perf bug: nav blur is not isolated, inside a transforming ancestor · *verified*
`bottom_nav_bar.dart`: **0** `RepaintBoundary` occurrences in the file. The `BackdropFilter` at `:325` sits inside `AnimatedContainer(transform: Matrix4.translationValues(0, visualDy, 0))` (`:158-161`) driven by a drag `ValueListenableBuilder` (`:153-155`). During a dock drag the backdrop filter is re-rasterised against a moving transform every frame — the exact case `RepaintBoundary` exists to bound.

By contrast the primitive does this correctly: `return RepaintBoundary(child: blurred);` (`glass_container.dart:250`). The well-isolated implementation is the one nobody calls; the unisolated one is the one on screen permanently.

### F6 — Blur gating is excellent, but keyed to the wrong high-contrast signal · *verified*
`AppBlur.canBlur` refuses blur on GPU-saver and on `MediaQuery.highContrast` (`app_blur.dart:47-53`), and `GlassContainer` then forces alpha to `solidFallbackMinAlpha = 0.94` (`app_blur.dart:41`, applied `glass_container.dart:156-158`). Unit tests pin this behaviour, including `clampSigma(24) == maxSigma` and negative→0 (`test/architecture/ui_ux_10_ratchet_test.dart:123-179`; `test/core/widgets/glass_container_live_test.dart:72-83`). This is the strongest part of the system.

The defect: the app ships its **own** high-contrast mode as a *theme*, not as `MediaQuery.highContrast`. `main.dart:1309-1310` reads `settingsConfig.highContrast || MediaQuery.highContrastOf(context)` to pick the theme, but `app_blur.dart:50` consults **only** `media.highContrast`. A user who turns on Pulsr's High Contrast setting gets `AuraTheme.highContrastTheme` (which additionally forces `isAmoled: true`, `aura_theme.dart:305-306`) while `canBlur` still returns true — so the contrast fallback never engages for the app's own accessibility path. Two high-contrast signals, one of which is invisible to the blur layer.

### F7 — Token names that lie: `sheet` and `dock` presets exceed the ceiling by design · *verified*
`maxSigma = 18.0` is documented as a "hard ceiling … to prevent GPU frame spikes" (`app_blur.dart:33-34`), yet `sheet = 20.0` (`:37`) and `dock = 24.0` (`:40`) are defined above it and silently clamped at raster time by `clampSigma` (`:55-58`, applied `glass_container.dart:227`). `GlassPreset.dock` therefore declares 24 and renders 18 (`glass_container.dart:23`). A designer reading the token file gets a different number than the GPU does.

Related: `GlassContainer.liquid`, `GlassPreset.dock`, `GlassPreset.sheet`, `GlassPreset.chip` are **never called** anywhere in `lib/`. Only `GlassPreset.dialog` is (`pulsr_dialog.dart:426`) — and it is the one broken by F2.

### F8 — `bottom_nav_bar` bypasses the clamp and the `GlassPreset` contract · *verified*
`bottom_nav_bar.dart:326-329` passes `AppBlur.nav` straight into `ImageFilter.blur` with no `clampSigma`. It is safe today only because 14 < 18; the invariant is unenforced at the site, so a later token bump silently escapes the ceiling the ratchet test guards elsewhere. It also duplicates the preset maths (`GlassPreset.dock` opacity 0.72 vs the dock's local 0.88/0.84) rather than consuming it.

### F9 — AMOLED: blur over black is optically null, and nothing compensates · *verified + inference*
AMOLED sets `bg: Colors.black`, `surface: 0xFF0A0A0D`, `surfaceContainer: 0xFF111116` (`aura_theme.dart:551-554`). A backdrop blur under an 84–88% opaque tint over a near-black field produces almost no perceivable change — the material reads as a flat grey veil, and the only remaining depth cues are the hairline border and shadow. Dark container alpha differs by just `0.16` (AMOLED) vs `0.14` (dark) (`:497`), which is not enough to re-tune the material for a field where shadow and translucency both lose their signal. `PulsrElevation` likewise applies a single `isDark` branch with no AMOLED case (`pulsr_elevation.dart:88`).
*Inference, not measurement:* the visual consequence is reasoned from the colour values; no on-device AMOLED capture was taken.

### F10 — Radii and colour are disciplined; hairlines are the weak link in coherence · *verified*
Radii are genuinely tokenised: semantic (`tile 14 / card 18 / artwork 20 / miniPlayer 24 / dialog 26 / bottomSheet 28`, `app_radii.dart:5-13`) plus a full numeric scale (`:19-36`). Colour spill is contained: **285 raw `Color(0x…)` literals live in 3 files, all under `core/theme` (158) and `core/constants` (127)** — features contain effectively none. That is unusually good hygiene and it means the depth problem is *not* a colour problem.

Hairlines are where coherence breaks: border-width literals cluster at `1.0` (75×), `2` (63×), `1` (38×), **`0.8` (38×)**, `1.5` (37×), `1.2` (27×), `3`, `2.5`, `2.2`, **`0.7` (6×)**. Four values (`0.7/0.8/1/1.0/1.2/1.5`) are visually near-identical at 1× DPR but are independently authored — a hairline token (`AppStrokes.hairline`) is the missing piece, not a redesign.

### F11 — Contextual menus are outside the material system entirely · *verified*
`aura_theme.dart` defines **no** `popupMenuTheme`, while the app opens **12** raw `PopupMenuButton` instances. Menus therefore inherit the Material default surface, elevation and radius — the one surface class in the app that is neither Pulsr-glass nor Pulsr-elevation, sitting directly on top of artwork in library and queue contexts.

### F12 — The full-screen blur path is the best-engineered one in the repo · *verified*
`canvas_backdrop.dart:300-317` rasterises video at 1/6 resolution, blurs that, and scales back up — *"cutting the per-frame blur cost by ~36x"* — with sigma divided by the same factor (`AppBlur.clampSigma(widget.blurSigma / downscale)`) so the visual radius is preserved. It is gated by `AppBlur.canBlur`. This is exactly the technique the dock should have used for its own layer isolation, and it shows the team knows how to do this correctly.

---

## 3. Top gaps (max 7)

1. **Glass is API, not product.** 3 reachable call sites; `PulsrSurface` has 0 consumers; the bottom sheet — the app's most-used container — is opaque while its docstring claims frost. (F1, F3)
2. **The only `GlassPreset` consumer renders an invisible blur at full cost.** `pulsr_dialog.dart:429` passes an opaque colour, which short-circuits the alpha maths at `glass_container.dart:160`. (F2)
3. **The mini player — the surface with artwork permanently behind it — is an opaque slab,** and it is the surface most obviously entitled to material treatment. (F3)
4. **No usable depth scale.** 183 raw shadows vs 22 token uses, 20 distinct blur values, and a second dead scale (`AppElevation`) inviting the wrong choice. (F4)
5. **The one shipping glass has a raster-isolation bug:** nav `BackdropFilter` inside a drag-transformed `AnimatedContainer` with 0 `RepaintBoundary`. (F5)
6. **Accessibility fallback does not fire for the app's own high-contrast mode** — `canBlur` reads only `MediaQuery.highContrast`. (F6)
7. **AMOLED and contextual menus are unhandled material cases:** blur is optically null over `#0A0A0D`, and 12 popup menus escape the system with no theme. (F9, F11)

---

## 4. Path to 10/10

### P0 — make the material real (do first; ~2–3 days)

**P0.1 Fix the dialog so its blur is visible**
`lib/core/widgets/pulsr_dialog.dart:429` — remove `color: p.surfaceContainerHigh,` and let `GlassContainer` derive the tint from the palette (or pass `p.surfaceContainerHigh.withValues(alpha: 0.88)`).
Also harden the primitive: `glass_container.dart:160` should apply `tintAlpha` to a caller-supplied colour too, rather than treating `color != null` as "fully opaque, skip the maths". Guard with an assertion that a `GlassTier.standard/liquid` container never receives an opaque colour.
*Acceptance:* a widget test asserts the resolved `BoxDecoration` colour of `PulsrDialog` has alpha < 1.0; manual check — artwork and barrier visibly shimmer through the dialog at sigma 18.

**P0.2 Isolate the nav blur**
Wrap the `BackdropFilter` at `bottom_nav_bar.dart:325` in a `RepaintBoundary`, and move the drag transform to a parent `Transform.translate` outside that boundary so the filter layer is not rebuilt per drag frame.
*Acceptance:* `RepaintBoundary` directly wraps the `BackdropFilter`; drag-and-hold on the dock shows no filter re-raster in a `--profile` DevTools timeline (layer count stable).

**P0.3 Make the mini player glass over artwork**
`lib/features/player/presentation/mini_player.dart:606-624` — swap the opaque gradient for `GlassContainer` with `blur: AppBlur.standard (12)`, tint alpha ≈ 0.62 dark / 0.80 light, keeping the existing hairline and accent `alphaBlend` so the accent identity survives.
*Acceptance:* with bright artwork behind, the mini player's cover edges are perceptibly diffused; text contrast over the now-translucent surface still ≥ 4.5:1 (sample 5 artwork brightnesses).

**P0.4 Bind the app's high-contrast setting to blur gating**
`lib/core/constants/app_blur.dart:47-53` — accept the app's own flag, e.g. `bool canBlur(BuildContext, {bool enableBlur = true, bool forceSolid = false})`, and pass `SettingsCubit`'s `highContrast` from `GlassContainer` the way it already reads `liquidGlassTint` at `glass_container.dart:126-134`.
*Acceptance:* test mirroring `glass_container_live_test.dart:72` but toggling the *app* setting (no `MediaQuery` override) — expects `findsNothing` for `BackdropFilter`.

### P1 — one depth system (next; ~3–4 days)

**P1.1 Delete the duplicate scale, then migrate the hot surfaces**
Delete `lib/core/constants/app_elevation.dart` (0 consumers, so removal is free). Migrate the four highest-traffic raw-shadow sites to `PulsrElevation`: `pulsr_bottom_sheet.dart:387` → `level3`, `pulsr_toast.dart:484` → `level3`, `mini_player.dart:586` → `level4`, `bottom_nav_bar.dart:165` → `level4`.
*Acceptance:* those four files contain no raw `BoxShadow(`; visual diff shows the key+ambient pairing; `PulsrElevation` references rise from 22 to ≥ 40.

**P1.2 Add the missing hairline token**
`lib/core/constants/app_strokes.dart` (new): `hairline = 1.0`, `hairlineSubtle = 0.75`, and a `Divider`-width constant. Replace the `0.7 / 0.8 / 1 / 1.0 / 1.2 / 1.5` literals in `glass_container.dart:170-176`, `mini_player.dart:625-627`, `pulsr_bottom_sheet.dart:381`.
*Acceptance:* a ratchet test fails on any new `width:` literal inside a `Border.all` in `lib/features`.

**P1.3 Give contextual menus a material**
Add `popupMenuTheme` to `aura_theme.dart` (near `:920`): `surfaceContainerHigh` background, `AppRadii.cardRadius`, `PulsrElevation.level3`, hairline border. For the queue/library overflow menus over artwork, route through a `GlassContainer` popover.
*Acceptance:* all 12 `PopupMenuButton` sites inherit the same radius/shadow; screenshot parity across library, queue, and player.

**P1.4 Reconcile the blur scale with its own ceiling**
`app_blur.dart:37-43` — either raise `maxSigma` to 24 (and justify the cost) or re-declare `sheet = 18`, `dock = 18` so token == raster. Prefer the latter: it keeps the ceiling honest and makes the presets truthful. Then delete the unused `GlassPreset.sheet/dock/chip` entries or wire them to real call sites.
*Acceptance:* a test asserts every `AppBlur` constant ≤ `maxSigma`; `GlassPreset` values equal `clampSigma` of their own declared blur.

### P2 — parity and identity (after P0/P1)

**P2.1 AMOLED-specific material tuning** — `pulsr_elevation.dart:88` add an AMOLED branch that raises ambient alpha (blur over `#0A0A0D` needs more ink to read) and lowers container tint so the surface does not sit as flat grey; `aura_theme.dart:497` widen the AMOLED/dark delta beyond 0.16/0.14.
*Acceptance:* side-by-side AMOLED vs dark captures show distinguishable depth; no surface reads as an unmodulated grey rectangle.

**P2.2 Give "liquid" a definition or delete it** — `GlassContainer.liquid` (`glass_container.dart:68-85`) currently exists with a specular sheen and radius but zero callers. Either ship it on exactly one hero surface (the now-playing transport dock) or remove `GlassTier.liquid` and `GlassPreset.dock` so the tier list stops advertising an unused material.
*Acceptance:* `GlassTier.liquid` either has ≥ 1 production call site or does not exist.

**P2.3 Text-over-artwork contrast contract** — where chrome floats on artwork, standardise on `ScrimTokens.topLegibility` / `artworkDissolve` (`scrim_tokens.dart:26-44`) beneath text rather than relying on surface tint alone.
*Acceptance:* a golden test samples chrome text against 3 bright and 3 dark artworks; all ≥ 4.5:1.

---

## 5. Surfaces to leave opaque on purpose

Explicitly **not** gaps — blur here would cost frames and buy nothing, or would actively harm legibility:

- **Library, album, artist, folder and playlist lists.** Dense scrolling text; a moving backdrop behind text is a legibility tax. Keep `surface`/`surfaceContainer`.
- **Queue screen rows** (`queue_screen.dart:506`) — same reason; the queue is a reading surface.
- **Settings rows** (~65 screens) — utility surfaces; glass would read as decoration, not hierarchy.
- **Tag editor** (`tag_editor_screen.dart`) — form input over arbitrary art; opacity is correct.
- **Full-screen lyrics** — text legibility is the entire product; `advanced_lyrics_view` already blurs the *artwork* (correct) rather than relying on a translucent panel over it.
- **Now Playing hero artwork itself** — the cover should be pristine pixels, never behind a filter.
- **Milkdrop / GPU visualizer surface** — the shader owns the frame; a second filter pass is pure waste.
- **Modal barrier scrims** — a blur here (`ImageFilter` on the whole route below) is the classic Android jank source; the existing `ScrimTokens.barrierScrim` approach is right.

The distinguishing rule the repo currently lacks: *blur belongs to chrome that floats over artwork and carries little text* (dock, mini player, now-playing transport, sheets over artwork, toasts, dialogs). *Opaque belongs to surfaces that are read* (lists, forms, settings, lyrics).

---

## 6. Unverified / not checked

- **Actual GPU frame cost** of the dialog's wasted blur — reasoned structurally (18σ full-card backdrop filter + opaque composite), not profiled. Recommend a `--profile` timeline on a mid-tier device before/after P0.1.
- **On-device AMOLED appearance** (F9) — derived from palette hex values, no physical capture.
- **Whether `pulsr_bottom_sheet`'s opaque surface is a deliberate performance decision** — no commit message or ADR found asserting intent; the docstring says otherwise, so I treat it as drift rather than design.
- **iOS/macOS platform surfaces** — audit covered `lib/` only; no `ios/` material review.
- **`glass_container_live_test.dart` pass/fail status at HEAD** — tests were read for intent, not executed (read-only audit).
