# 02 — Motion & Animation

Scope: `lib/` only, read-only. Counts are `rg`-equivalent line counts over `lib/features/*/presentation` + `lib/core/widgets`.

**Verdict:** the reduce-motion *architecture* is genuinely good (one MediaQuery override, `main.dart:1049-1057`); the *discipline* is not. Two token scales plus a third set in docs, 80 raw durations, and a 9-site hole where `PulsrMotion.standard` is passed raw and therefore ignores Reduce Motion entirely.

---

## 1. TOKEN DISCIPLINE

| Metric | Count |
|---|---|
| `Duration(milliseconds:` (features/presentation) | **60** |
| `Duration(milliseconds:` (core/widgets) | **20** |
| **Total hardcoded** | **80** |
| `motionMs(` / `PulsrMotion.` / `context.motion(` (features/presentation, union) | **155** |
| same (core/widgets, union) | **46** |
| **Total token-routed** | **201** |

Ratio **2.5 : 1** for tokens. But only **~26 of the 80 are animation durations** (11 in `core/widgets`, ~15 in features); the other ~54 are `Timer`/debounce/poll and `Duration`-arithmetic (e.g. `player_seek_bar.dart:391` drag maths, `dsp_inspector_sheet.dart:75` 1500 ms poll). True animation split is **~26 vs 201 → 7.7 : 1**, which is healthy. The problem is not volume, it is *which* API is used.

### Three scales, none authoritative

- `lib/core/motion/pulsr_motion.dart:26-48` — **8 legacy consts**: 80 / 150 / 220 / 250 / 300 / 400 / 500 / 600.
- `lib/core/motion/pulsr_motion.dart:60-73` — **5 semantic** `PulsrDurations` (120 / 200 / 260 / 320 / 400, defined `motion_durations.dart:24-36`), re-exported as `tap/state/layout/page/ambient`.
- `DESIGN.md:179-183` — a **third** set: instant 80 / fast 150 / standard 250 / slow 400 / expressive 600. `DESIGN_SYSTEM.md:100` claims **`instant 90`** — wrong on both counts; code says 80 (`pulsr_motion.dart:26`) and `DESIGN.md:179` says 80.

**What production actually uses:** none of them. **138 of the 201** routed sites are `context.motionMs(<raw int>)`, and only **4** sites use `PulsrDurations` (`dock_style_picker_sheet.dart:164,222`, `stacked_bottom_dock.dart:50`, plus `context.motion(PulsrDurations.layout)` pass-through). The de-facto rhythm is ad-hoc literals: **320** dominates the player theme builders (`card_player_theme_build.dart:166,232`, `cd_player_theme_build.dart:77`, …17 sites), then 200 (24 sites), 180 and 250. The semantic scale is documentation, not production.

### 10 largest hardcoded values

| ms | Site | Animates | Kind |
|---|---|---|---|
| 3500 | `pulsr_dismissible.dart:62` | undo-confirm window | timer |
| 3200 | `pulsr_slider.dart:75` | idle wavy track loop | animation |
| 3200 | `pulsr_toast.dart:69` | toast dwell | timer |
| 2600 | `mini_player.dart:1089` | mini waveform loop | animation |
| 2400 | `pulsr_logo.dart:42` | logo ripple loop (40+ draws/frame) | animation |
| 1400 | `shimmer_skeleton.dart:30` | list shimmer sweep | animation |
| 1400 | `player_shortcut_scope.dart:77` | shortcut toast dwell | timer |
| 1400 | `marquee_text.dart:24` | scroll pause between cycles | animation |
| 1300 | `shimmer_skeleton.dart:120` | grid shimmer sweep | animation |
| 1200 | `player_controls.dart:199` (also 460, 507) | AB-loop toast dwell | timer |

### The bare-const trap (9 sites)

`PulsrMotion.standard` is a plain `const Duration`. It does **not** collapse under Reduce Motion — only `context.motion(...)`, `context.motionMs(...)` and `PulsrMotion.resolve(...)` do (`pulsr_motion.dart:91-97`). These pass the raw const straight into an implicit animation, so they animate at full length with Reduce Motion ON:

`download_tile.dart:330` · `folder_detail_screen.dart:1212` · `folder_tree_browser_tab.dart:39` · `mini_player.dart:890` · `audio_output_section.dart:25` · `experience_mode_section.dart:185` · `settings_theme_pickers.dart:388,466` · `pulsr_dismissible.dart:199,207`

Fix is mechanical: wrap in `context.motion(...)`.

---

## 2. REDUCE MOTION

**Global mechanism works.** `main.dart:1049-1057` computes `reduceMotion = settingsConfig.reduceMotion || media.disableAnimations` and rewrites `MediaQuery.disableAnimations`, so every `context.motion*` call site app-wide collapses — including the OS switch, with no per-widget settings reads. That is the right design and most code honours it.

Coverage of the two instrumented surfaces:

- **30 `AnimationController` sites** (14 features, 16 `core/widgets`). 25 check `motionEnabled` directly; 3 more are safe because their duration resolves to `Duration.zero` (`pulsr_dismissible.dart:219-220`, `now_playing_screen.dart:293`); **2 are genuinely unguarded** — `audio_output_section.dart:23` and `experience_mode_section.dart:183` (raw const duration, no check).
- **25 `repeat()` sites.** 24 are gated by `context.motionEnabled`; the exception is `pulsr_logo.dart:43` (`..repeat()` in `initState`), which starts for one frame before `didChangeDependencies` stops it (`pulsr_logo.dart:76-83`). Cost is negligible, but it is the only loop that is not declaratively gated.

So reduce-motion is **~92 % correct**. The residual defects are the 9 bare-const sites above, not the loops.

### GpuBudget double-use — coherent in mechanism, overloaded in meaning

Same pref drives both: `main.dart:159` (`GpuBudget.setEnabled(prefs.getBool('setting_reduce_motion'))`), `settings_accessibility_ext.dart:20` (setter) and `:30` (restore). Effect: Reduce Motion ⇒ `BackdropFilter` skipped at `glass_container.dart:169`, nav-bar blur dropped at `bottom_nav_bar.dart:188`, lyric blur zeroed at `advanced_lyrics_view.dart:252-255`, shader fallback at `milkdrop_renderer.dart:29`.

**Coherent** in that it is one flag, one direction, no oscillation, and restoring before first frame (`main.dart:159`) avoids a blur flash. **Not coherent** in three ways:

1. **It is a proxy, not a requirement.** A user disabling motion for vestibular reasons silently loses glass depth and shader visuals — an accessibility setting mutating aesthetics.
2. **The two halves do not cover each other.** Reduce Motion kills *durations* but leaves *static* blur to GpuBudget; the 9 bare-const sites animate at full length *while* blur is already off — i.e. the user who asked for less motion gets less fidelity and still gets the motion.
3. **No path back for battery-only users.** Someone who wants to save power must turn off all animation. A separate `gpuSaver` pref (defaulting from `reduceMotion || lowRam`) would separate the intents; `GpuBudget.enabled` is already a `ValueNotifier` (`gpu_budget.dart:9`) so the plumbing exists.

---

## 3. TICKER LIFECYCLE

25 `repeat()` sites. (a) stops on playback pause · (b) stops off-screen/inactive route · (c) stops on background · (d) stops under reduce motion.

| # | Site | (a) | (b) | (c) | (d) |
|---|---|---|---|---|---|
| 1-2 | `pulsr_empty_state.dart:83,99` | n/a | ✗ | ✗* | ✓ `:48` |
| 3-5 | `pulsr_logo.dart:43,59,81` | n/a | ✗ | ✗* | ✓ `:77` (1 frame late) |
| 6 | `pulsr_slider.dart:98` | n/a | ✗ | ✗* | ✓ `:92` |
| 7-8 | `shimmer_skeleton.dart:38,137` | n/a | ✗ | ✗* | ✓ `:37,136` |
| 9-11 | `song_tile.dart:453,463,472` | ✓ | ✗ | ✗* | ✓ `:460,471` |
| 12 | `spinning_vinyl_disc.dart:51` | ✓ | ✗ | ✗* | ✓ `:49` |
| 13-15 | `waveform_logo.dart:38,54,73` | **✗** | ✗ | ✗* | ✓ `:53,69` |
| 16 | `mini_player.dart:1125` | ✓ | ✗ | ✓ `:1099` | ✓ `:1122` |
| 17-18 | `cassette_player_theme.dart:63,79` | ✓ | ✗ | ✗* | ✓ `:60` |
| 19 | `cd_player_theme.dart:79` | ✓ | ✗ | ✗* | ✓ `:76` |
| 20 | `circle_player_theme.dart:57` | ✓ | ✗ | ✗* | ✓ `:54` |
| 21 | `cassette_body.dart:593` | ✓ | ✗ | ✗* | ✓ `:590` |
| 22 | `vinyl_player_theme.dart:77` | ✓ | ✗ | ✗* | ✓ `:74` |
| 23 | `waveform_player_theme.dart:62` | ✓ | ✗ | ✗* | ✓ `:59` |
| 24 | `audio_visualizer.dart:240` | ✓ | **✓** `:166` (TickerMode) | **✓** `:251-259` | ✓ `:235` |
| 25 | `karaoke_pitch_highway.dart:117` | n/a | ✗ | ✗* | ✓ `:114` |

\* Engines stop producing vsync while backgrounded, so a bare ticker costs ~nothing in background; `isAnimating` simply resumes. Treat (c) as an audit-trail gap, not a battery finding — only 2 of 25 do it deliberately.

**(b) is the real hole: 24 of 25 loops have no visibility gate.** Flutter only mutes tickers for routes *covered by an opaque route*; it does not mute `IndexedStack` branches. This app keeps all five tabs mounted — `StatefulShellRoute.indexedStack` at `app_router.dart:392` — and the shell adds no `TickerMode` wrapper (`rg TickerMode lib/features/shell` → 0 hits). **So yes: repeating tickers run in screens that stay mounted under the tab shell.** Home's loops keep ticking while you browse Library, and `mini_player.dart:1125` (rendered in the dock outside the branch stack, `app_shell.dart:393`) ticks under every tab.

**Worst 5 for battery/GPU:**

1. `audio_visualizer.dart:240` — 60 fps FFT + CustomPaint, largest continuous GPU spend. Best-in-class gating, but it is the cost centre.
2. `cd_player_theme.dart:79` / `circle_player_theme.dart:57` / `vinyl_player_theme.dart:77` — full-artwork rotation; each frame re-rasterises a large transformed image under a blur/shadow stack.
3. `shimmer_skeleton.dart:38,137` — `ShaderMask` (saveLayer) at ~35 call sites; survives tab switches while a list is still loading.
4. `waveform_logo.dart:38,54,73` — three controllers looping *independently of playback*; pure decoration with no pause and no visibility gate.
5. `pulsr_logo.dart:43` — 2400 ms infinite loop over a painter that draws ~40 circles + a clipped mesh per frame.

---

## 4. FRAME RISK

| # | Risk | Site | Why it costs | Triggers | Cheap fix |
|---|---|---|---|---|---|
| 1 | BackdropFilter | `glass_container.dart:188,197` (sigma ≤18), `bottom_nav_bar.dart:191` (14) | blur reads the backdrop and re-runs every frame the backdrop changes; full-width layer | any scroll under glass, any ancestor animation | pre-blur a downscaled snapshot (pattern already in `canvas_backdrop.dart:266-272`, /6); fall back to opaque while scrolling |
| 2 | Blur + Opacity over video | `canvas_backdrop.dart:256-269` | 400 ms `AnimatedOpacity` over `ImageFiltered` video forces layer re-composite each frame; `LayoutBuilder` re-derives size on every metrics change | now-playing open, artwork/video swap, rotation | `RepaintBoundary` + static blurred texture, cross-fade opacity only |
| 3 | saveLayer via ShaderMask | `shimmer_skeleton.dart:63`, `pulsr_scroll_edge_fade.dart:33` | one offscreen layer per shimmer list per frame; 35+ call sites | list first paint / reload | move the gradient instead of the mask, or paint it in one `CustomPainter` |
| 4 | saveLayer via BoxShadow stacks | `cassette_body.dart:228`, `cd_stage.dart:450`, `vinyl_deck.dart:130`, `waveform_stage.dart:461` (~100 `BoxShadow` sites, concentrated in player themes) | each shadow is a layer; stacked over a *rotating* child ⇒ re-rasterise per frame | playback (themes spin) | bake static shadows into one pre-rendered layer, animate only the top sprite |
| 5 | Implicit animation over a big subtree | `stacked_bottom_dock.dart:50,315` (dock height), `home_screen.dart:598,1022` (`AnimatedSwitcher` over tab body), `player_theme_scaffold.dart:415` | animating *layout* size relayouts the whole branch stack every frame — the most expensive animation in the app | tab switch, player open/close | animate a `Transform`/`SlideTransition` instead of height; or `AnimatedSize` with a `RepaintBoundary` child |
| — | per-build layout in painters | **not found** — `rg 'TextPainter\|\.layout\('` over `player/presentation/themes/painters` → 0 hits | — | — | — |

`shouldRepaint` discipline is good: ~15 painters, mostly correct field comparisons (`vinyl_painters.dart:483`, `cd_painters.dart:480`), several hard `=> false` (`cassette_body.dart:801,820,846`, `circle_stage.dart:471`).

---

## Scores

- **Motion & Animation: 4/10** — excellent global reduce-motion plumbing, but three competing scales, a doc that contradicts the code, and 9 sites that quietly ignore the switch.
- **Animation Performance: 5/10** — solid painter/`RepaintBoundary` hygiene undermined by blur-first surfaces and no off-screen ticker gating.

## 5 fixes

| Effort | Fix |
|---|---|
| **S** | Wrap the 9 bare `PulsrMotion.*` durations in `context.motion(...)` (§1 list). |
| **S** | Reconcile docs: `DESIGN_SYSTEM.md:100` `instant 90` → 80; mark the 8 legacy consts `@Deprecated` pointing at `PulsrDurations`. |
| **M** | Wrap inactive shell branches in `TickerMode(enabled: index == currentIndex)` at `app_shell.dart:393,474` — kills 24-of-25 off-screen loops in one file. |
| **M** | Replace `ShaderMask` shimmer with a translated gradient + `RepaintBoundary` per list (`shimmer_skeleton.dart:63`). |
| **L** | Blur budget: cache the backdrop blur as a downscaled snapshot, and drop glass to opaque during scroll and while any route transition runs. |
