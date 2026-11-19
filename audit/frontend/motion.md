# Pulsr — Motion & Transitions Audit

**Scope:** every animation token, route transition, implicit animation, repeating ticker, and drag-driven transform in the Flutter UI layer.
**Method:** static measurement over 827 Dart files (`rg` counts, exact line refs) plus reading of the named modules. **No app was run**: `flutter test` fails in this environment (`Could not find the pub cache. No LOCALAPPDATA`), so no runtime frame timing was captured. Everything below is code-level evidence; claims that depend on runtime appearance are marked **unverified**.
**Date:** 2026-11-18

---

## 0. The headline

This codebase does not have a *casual* motion problem — it has a **discipline problem at the scale layer** and a **continuity problem at the surface layer**.

The mechanism is unusually good: there is a single token file, a central `PulsrMotion.resolve`, an in-app Reduce Motion toggle that overrides `MediaQuery.disableAnimations` app-wide, a **ratchet test** that fails the build if an `Animated*` widget receives a raw duration, and a per-theme test that proves all 11 player themes stop ticking under Reduce Motion. That is better than most production Flutter apps.

What it does **not** have: a coherent *route family* (predictive back is declared but dead), a *continuous* Now Playing surface (artwork flies, the container does not), and a *real* duration scale (33 distinct millisecond values in circulation; the untokenized `180ms` is the second most-used duration in the app).

---

## 1. Score table

| Dimension | Score | One-line verdict |
| :--- | :---: | :--- |
| **Token discipline** | **7/10** | Mechanism is ratchet-enforced and ~80% of animations resolve through `context.motion*`, but the 5-token scale is nominal — 33 distinct durations in use and only 34% of token calls land on a real token. |
| **Reduce Motion** | **8/10** | Genuinely best-in-class at the token and decorative-loop level (in-app toggle + 11-theme test), but `Hero` flights and route durations are bare consts and never collapse. |
| **Route transitions** | **6/10** | Push/pop is one coherent, well-tuned family (320 in / 260 out, slide+fade+parallax) — but every one of the 41 routes is a `CustomTransitionPage`, which kills the predictive-back builder the theme configures. |
| **Surface continuity** | **6/10** | Artwork has a real shared-element chain from mini player → all 11 themes; the *player surface* is still a plain full-height slide and the mini player hard-swaps into existence with no animation. |
| **Micro-interactions** | **8/10** | Play/pause, seek, chip, segmented control and favorite are individually hand-crafted to a high standard; press feedback is three different physical constants with no single primitive. |
| **Choreography & stagger** | **7/10** | Staggered entrance is performance-aware (16-item cap, `RepaintBoundary`, `groupKey` re-sort replay) but exists three times with three different timings, and there is no screen-level timeline. |
| **Interruption & performance** | **8/10** | Ticker gating, app-lifecycle stops, drag re-grab, GPU budget and blur caps are all real and rare; one drag gesture is still animated by `AnimatedContainer`, which fights the finger. |

**Total: 50 / 70.**

---

## 2. Findings

Ordered by strength of support for the scores above.

### 2.1 Token discipline — 7/10

**The mechanism is enforced, not aspirational.** `test/architecture/motion_token_ratchet_test.dart` runs three checks over `lib/features` + `lib/core/widgets` (`dirs` at `:13-16`):
- no bare `PulsrMotion.*` in a `duration:` position (`:20-23`),
- no raw `Duration(...)` in an `Animated*`/`TweenAnimationBuilder` window (`:51-53, 68-71`),
- every file calling `.repeat()` must mention `motionEnabled` (`:90-97`).

I reproduced all three checks statically against the working tree: **all pass** (zero offenders). Evidence tier: first-party test + my own `rg` re-run.

**Measured adoption.** In `lib/features`, 68 raw `Duration(milliseconds: N)` occurrences vs 240 `context.motionMs(N)` + 36 `context.motion(...)`/`PulsrMotion.*` occurrences — roughly **80% of animation call sites resolve through the token API**. Calling that "81% token adoption" would be the flattering reading and it is technically true at the *mechanism* level.

**But the scale is nominal.** A histogram of every `motionMs(N)` value in `lib` yields **33 distinct durations**:

| ms | uses | is a token? |
| ---: | ---: | :--- |
| 200 | 53 | ✅ `state` |
| **180** | **33** | ❌ |
| 220 | 17 | ❌ |
| 260 | 13 | ✅ `layout` |
| 150 | 13 | ❌ |
| 300 | 10 | ❌ |
| 650 | 9 | ❌ (theme physics) |
| 240 / 250 / 320 | 8 / 8 / 8 | 320 ✅, others ❌ |
| 350 / 420 / 500 | 7 / 7 / 7 | ❌ |
| 160 / 400 | 6 / 5 | 400 ✅ |
| 450 / 600 / 380 / 800 | 4 / 4 / 4 / 3 | ❌ |

Of 240 token calls, only **81 (34%)** land on one of the five declared tokens (`120/200/260/320/400`). The single most common off-scale value, **180 ms, is used 33 times — more than `layout` (260 ms, 13 uses)**. A user cannot perceive the difference between 180 and 200 ms, which is precisely why the scale has failed: nobody had a reason to pick one.

So `motion_durations.dart:1-16` promises "one motion rhythm" and "never a raw millisecond literal", while the codebase freely passes arbitrary literals *through* the sanitized API. The ratchet guards the wrapper, not the value.

**The router escapes the ratchet entirely.** The ratchet's `dirs` list is `lib/features` and `lib/core/widgets` (`motion_token_ratchet_test.dart:13-16`); `lib/core/router` is not scanned. `app_router.dart:69-70` therefore passes bare consts straight into `transitionDuration`:

```dart
transitionDuration: PulsrMotion.page,        // 320ms, never resolved
reverseTransitionDuration: PulsrMotion.layout, // 260ms, never resolved
```

`PulsrMotion.page` is `PulsrDurations.page` (`pulsr_motion.dart:50`), a `const Duration`. It cannot collapse. Only the `transitionsBuilder` body checks `context.motionEnabled` (`app_router.dart:71-73`), which is a *different* fix: it suppresses the visuals, not the duration.

**Off-scale values in chrome the user sees constantly:** `now_playing_screen.dart:196` (`420ms` background colour tween on every track change), `:247` (`380ms` theme switch), `bottom_nav_bar.dart:159` (`120`), `:268` (`160`), `:400`/`:442`/`:478` (`220`).

### 2.2 Reduce Motion — 8/10

**This is the strongest dimension of the codebase and should not be regressed.**

- **Central override.** `main.dart:1386-1393` merges the in-app `settingsConfig.reduceMotion` with the OS flag and rewrites `MediaQueryData.disableAnimations` once, so every downstream `context.motionEnabled` sees one truth. The in-app toggle is real, not vapour.
- **`PulsrMotion` is a clean primitive.** `pulsr_motion.dart:62-84` — `isEnabled` checks both `disableAnimationsOf` and `accessibleNavigationOf`; `resolve` → `Duration.zero`; `resolveCurve` → `Curves.linear`. Correct on both counts (accessible-navigation is the one people forget).
- **Decorative loops are gated, not merely shortened.** Every spinning theme resolves through the same shape: `initState` controller → `didChangeDependencies` resolves duration → `_syncX()` checks `context.motionEnabled`.

  | Theme | Gate | Evidence |
  | :--- | :--- | :--- |
  | Vinyl | `isPlaying && context.motionEnabled` | `vinyl_player_theme.dart:82-93` |
  | CD | same + gloss parked at `1.0` under reduce motion | `cd_player_theme.dart:98-115, 151-156` |
  | Cassette | same | `cassette_player_theme.dart:79-91` |
  | Circle | same | `circle_player_theme.dart:55-63` |
  | Waveform | same | `waveform_player_theme.dart:56-65` |
  | Shared disc | same | `spinning_vinyl_disc.dart:50-57` |

- **Covered by a test, across all 11 modes.** `test/features/player/theme_reduce_motion_test.dart:85-100` asserts `'${mode.name}: no ticker under Reduce Motion'` for each mode, with a control asserting vinyl *does* animate when motion is allowed. A negative test plus a positive control is the correct shape.
- **The visualizer is exemplary.** `audio_visualizer.dart:173-175` checks `TickerMode.valuesOf(context).enabled` *and* `motionEnabled` *and* visibility; `:454-467` additionally throttles to ~30 fps and re-checks both flags inside the listener; `:568` degrades style under `GpuBudget`.
- **Blur is accessibility-aware.** `app_blur.dart:52-58` disables blur on GPU-saver *and* `MediaQuery.highContrast`, with a WCAG-safe solid fallback alpha (`:46`). Very few apps do this.

**Two real holes.**

1. **`Hero` flights ignore Reduce Motion.** The artwork shared-element chain (§2.4) has no `HeroMode`, no `flightShuttleBuilder` and no `motionEnabled` check anywhere in the app (`rg flightShuttleBuilder|HeroMode` → **zero hits**). Because the route's `transitionDuration` is a bare const (§2.1), a reduce-motion user still gets a 320 ms full-screen artwork flight — the single largest movement in the product. *Runtime appearance unverified; the absence of any gate is certain.*
2. **`PulsrTransitions` is dead code.** `pulsr_transitions.dart:7` declares the class and **nothing anywhere in `lib` references it** (`rg 'PulsrTransitions'` → only its own declaration). It has no context, so `:11-17` picks `_enter`/`_exit` from animation status alone and can never resolve curves — a latent trap rather than an active bug, but it means the file named "transitions" is not what drives any transition in the app.

**Framework hazard, documented locally.** `pulsr_chip.dart:182-188` conditionally omits `AnimatedSize` entirely under reduce motion with a comment explaining that a zero-duration `AnimatedSize` re-dirties itself inside its own layout pass and trips the framework mutation assertion. Correct fix, but it is applied at *one* call site. Any other `AnimatedSize`/`AnimatedContainer` that receives `Duration.zero` is exposed to the same assertion. `rg` shows this pattern is otherwise unguarded.

### 2.3 Route transitions — 6/10

**The push/pop family is good and internally coherent.** `app_router.dart:62-107` (`_buildPulsrPageRoute`):
- 320 ms in / 260 ms out — asymmetric in the right direction (exits should be faster than entrances);
- primary slide `Offset(0.12, 0)` + fade with `Interval(0, 0.75)`;
- secondary parallax: the outgoing page recedes to `Offset(-0.04)` and dims to `0.92` opacity — an Apple-style depth cue, not a flat crossfade;
- `animation.drive(CurveTween)` rather than `CurvedAnimation`, avoiding listener leaks on re-build (a real trap, correctly avoided).

**Tab switching is its own, calmer family.** `app_router.dart:125-146` (`_buildTabPage`): 200 ms, `Offset(0, 0.012)` lift + fade. Distinguishing "lateral" from "descend" is the right call.

**Dock mode changes share the page rhythm.** `stacked_bottom_dock.dart:111, 356-357` resolves `PulsrDurations.page` **once** through `context.motion()` and threads the same `animDuration`/`animCurve` into four different animated widgets (`:649-655, 697-703, 741`). This is the cleanest token plumbing in the repo and the model the router should copy.

**Where it breaks: predictive back is dead code.**

```dart
// aura_theme.dart:731-735
pageTransitionsTheme: const PageTransitionsTheme(
  builders: { TargetPlatform.android: PredictiveBackPageTransitionsBuilder() },
),
```

```xml
<!-- android/app/src/main/AndroidManifest.xml:49, 72 -->
android:enableOnBackInvokedCallback="true"
```

Both halves of the Android 14 predictive-back contract are configured. But `PageTransitionsTheme` is only consulted by routes that delegate to it. `rg 'MaterialPage\(|CupertinoPage\(|NoTransitionPage\('` over `lib` returns **zero hits**; all **41** `GoRoute`s use `CustomTransitionPage`, whose `transitionsBuilder` replaces `buildTransitions` wholesale (`_buildPulsrPageRoute` is referenced 37 times, plus the inline Now Playing page and the tab builder). **Result: no predictive-back preview exists anywhere in the app**, despite the theme and manifest both asserting it. Users on Android 14 get a system back gesture with no route preview — the exact regression the builder was added to prevent.

**Sheets and dialogs are a third and fourth family, on framework defaults.**
- `PulsrBottomSheet`/`PulsrAdaptiveSheet` animate *content* with `ctx.motion(PulsrMotion.state)` (`pulsr_bottom_sheet.dart:121-122, 508-514`; `pulsr_adaptive_sheet.dart:122-123, 415-421`) but never pass `sheetAnimationStyle`. The sheet *route* itself therefore runs Material's default enter duration, outside the 200/260/320 rhythm and outside the token system. `rg sheetAnimationStyle|AnimationStyle` → zero hits.
- Dialogs go through `DialogRoute` (`pulsr_dialog.dart:63-64`) — framework default ~150 ms fade, again outside the family.

So the real transition inventory is: **routes 320/260**, **tabs 200**, **dock 320**, **sheets ~250 framework**, **dialogs ~150 framework**. Four rhythms, two of them untokenized.

**No platform branching at all.** `rg 'kIsWeb|Platform\.is|defaultTargetPlatform'` across `lib/core/router`, `pulsr_transitions.dart`, `lib/core/motion` → **zero hits**. Consequences:
- **iOS loses the interactive back-swipe.** `CupertinoPageRoute` is what provides the edge-swipe pop gesture; `CustomTransitionPage` does not. An iOS user must reach for the back button on every screen. This is a HIG-level omission and it is invisible on Android, which is likely why it survived.
- Web/desktop get a 12%-width horizontal slide at 320 ms — playable, but not the desktop-native near-instant transition, and the horizontal slide fights browser back/forward semantics.

### 2.4 Surface continuity — 6/10

**The artwork chain is genuinely excellent and better than the score implies.** One tag function is the single source of truth:

```dart
// player_theme.dart:11-12
String nowPlayingArtHeroTag(PlayerThemeMode mode) => 'now_playing_art_${mode.name}';
```

`ThemeRegistry.build` **forces** the tag onto the props (`theme_registry.dart:41-43`), so a theme cannot forget it. All 11 themes wrap their artwork in `Hero` with `props.heroTag` (`classic:112`, `card:269`, `circle:36`, `clean:123`, `minimal:67`, `lyrics:123`, `vinyl:34`, `cd:34`, `cassette:54`, `waveform_stage:130`, `milkdrop:222`). The mini player uses the *same* function (`mini_player.dart:100-101, 817-820`), and so does the tablet bar (`tablet_player_bar.dart:283-285`). Because the tag embeds `mode.name`, the flight stays correct when the user switches themes. That is careful, correct work.

**But the surface around the artwork is a plain route.** `app_router.dart:496-521` builds Now Playing as a full-height slide:

```dart
Tween<Offset>(begin: const Offset(0.0, 1.0), end: Offset.zero)
```

There is no scale, no fade, no corner-radius interpolation, and **no `Hero` on the mini-player container** — only its artwork. The result is the hybrid that feels slightly wrong: a small square flies to centre-screen *while* an unrelated full page slides up from off-screen. In the Apple Music / Spotify pattern the *card itself* expands (`Hero` on the container, artwork riding along), so the user reads one continuous object. Here they read two.

**Drag-to-dismiss reveals a flat backdrop, not the app.** `now_playing_screen.dart:194-198` wraps the dismissible subtree in a **static, non-transformed** `AnimatedContainer(color: bgColor)`; the transform is applied *inside* it (`:457-478`). So pulling the player down exposes a solid colour panel — not the library, not the mini player. The interaction physics themselves are excellent (§2.7), but the reveal is a blank stage rather than a return journey. Compounding this, the route is opaque (default `CustomTransitionPage`), so the shell behind it is not even painted.

**No flight shuttle.** `rg flightShuttleBuilder` → zero. Flutter's default shuttle renders the *destination* child at an interpolated rect, so the artwork snaps between the 46 px / `borderRadius: 12` mini-player version (`mini_player.dart:823-833`) and the large themed version, and any radius/decoration difference pops at the endpoints instead of tweening.

**The highest-frequency state change has no transition at all.**

```dart
// stacked_bottom_dock.dart:484-491
if (!hasSong) {
  return PulsrBottomNavBar(currentIndex: ..., onTap: ..., includeSafeArea: true);
}
```

Idle → first song playing swaps the entire dock subtree instantly: the mini player does not slide, fade, or grow in; the nav bar jumps. Every subsequent track change is beautifully animated; the very first one — the moment a new user forms their impression of the app — is a hard cut. Fixing this is a few lines (`AnimatedSize`/`AnimatedSwitcher` around the two branches) for disproportionate perceived gain.

### 2.5 Micro-interactions — 8/10

**Play/pause is the best-crafted control in the app.** `player_controls.dart:326-406`:
- asymmetric press: `motionMs(_isPlayPressed ? 90 : 280)` with `easeOutCubic` down and `easeOutBack` up — down is snappy, release overshoots gently;
- press scale `0.92`;
- `AnimatedSwitcher` 260 ms with fade + scale `0.80 → 1.0` + rotation `-0.06 → 0` turns under `easeOutBack`, so the pause bars appear to rotate into place rather than crossfade;
- the button's glow tracks state: `blurRadius: isPlaying ? 18 : 10`, alpha `0.36 / 0.18` (`:357-362`);
- `abLoopActive` swaps border width `1.0 → 2.0` (`:366-370`).

That is a real morph-plus-glow, not a two-icon crossfade. It is Apple-tier for a single control.

**Seek feedback is thorough.** `player_seek_bar.dart`: drag delta pill rendering `+0:12` relative to drag start (`:463-469`), dual-tone timestamp pill above the thumb (`:591`), thumb `AnimatedScale` (`:603`), and haptics at drag start (`:110`), tick (`:315`), threshold crossing and tap (`:521, 546`). This is the correct feedback triad: visual delta + absolute position + tactile confirm.

**Favorite is a cross-pop, and that is a deliberate ceiling.** `player_theme_chrome.dart:292-353` — `AnimatedSwitcher` 280 ms, `ScaleTransition` driven through `context.motionCurve(Curves.easeOutBack)` for the filled heart, `easeOutCubic` for the outline, plus `PulsrHaptics.confirm()` and `SoundFeedbackService.playClick()`. Good; but note the `transitionBuilder` decides its curve by reading `child.key as ValueKey<bool>` (`:329-332`), which is fragile, and both hearts scale through the same window, so mid-transition you see two overlapping hearts shrinking/growing — a dissolve, not a burst. No particle rays, no container overshoot. Acceptable, not distinctive.

**Chip selection uses the right token.** `pulsr_chip.dart:113-114` — `context.motion(PulsrDurations.tap)` (120 ms) for the fill/border/glow change. Selecting a filter chip should be faster than a layout change, and it is.

**Segmented control has a real sliding thumb.** `player_theme_chrome.dart:606-650` — `AnimatedAlign` 260 ms moving a `FractionallySizedBox(widthFactor: 1/3)` gradient thumb, with the label/icon/badge changing simultaneously (`:225-260`). That is the correct construction (indicator travels, content crossfades) rather than three independent colour tweens.

**The consistency defect: three press scales, no single primitive.**

| Surface | Scale | Down / up | Evidence |
| :--- | :---: | :--- | :--- |
| `PulsrPressable` (design-system default) | **0.96** | 100 / 165 ms | `pulsr_pressable.dart:43-44, 67, 79` |
| Main play button | **0.92** | 90 / 280 ms | `player_controls.dart:326-329` |
| `PlayerDockIconButton` | **0.88** | 120 ms | `player_theme_chrome.dart:485-488` |

These are three different physical fictions for the same gesture. Worse, adoption is partial: **141 raw `InkWell(` call sites vs 28 files importing `PulsrPressable`** (`rg` counts). So the design-system pressable is the minority path, and most feature screens respond with ink only — no scale. On a touch device, ink-only is the single most common way an app feels "cheap".

### 2.6 Choreography & stagger — 7/10

**`StaggeredReveal` is the good implementation and is performance-aware.** `staggered_reveal.dart:24-66`:
- caps the entrance at `index >= 16` (`:36`) — only the first screenful animates, so a fling doesn't mount 300 simultaneous tweens;
- only the first 8 items get a delay (`index < 8 ? index * 30 : 0`, `:37`), so rows 9-15 animate immediately rather than queuing a 270 ms tail;
- `RepaintBoundary` around each row (`:66`);
- `groupKey` in the `ValueKey` (`:42-44`) so re-sorting the library replays the cascade instead of hard-jumping — a genuinely nice touch that most apps miss.

**But there are three stagger systems with three timings:**

| Implementation | Delay | Duration | Cap | Uses |
| :--- | ---: | ---: | ---: | ---: |
| `StaggeredReveal` | 30 ms ×8 | `motionMs(250)` | 16 | **18** |
| `StaggeredListItem` | 30 ms | 320 ms | 15 | **3** |
| `shimmer_skeleton._cascade` | 45 ms | `300.ms` | — | skeletons only (`:271-291`) |

`staggered_list_item.dart:20-21` declares `itemDelay = 30ms` / `animDuration = 320ms` as **defaults on a public widget**, bypassing both the token scale and `context.motion` at the declaration site (it resolves later in `didChangeDependencies:70`, so Reduce Motion still works). With 3 usages against `StaggeredReveal`'s 18, it is effectively legacy. Two independent 30 ms/300 ms+ staggers will drift the moment either is tuned.

**And there is no screen-level choreography.** No timeline orchestrates header → hero card → section → rows; each widget staggers from its own `index` starting at 0. On Home, the hero card and the first row of "recently played" both begin at delay 0, so the screen assembles as several independent cascades rather than one composition.

### 2.7 Interruption & performance — 8/10

**This is where the codebase is quietly excellent.**

- **Hidden tabs stop ticking.** `ticker_gated_branch_container.dart:29-45` wraps every shell branch in `TickerMode(enabled: i == active)` + `ExcludeFocus` + `RepaintBoundary`. The comment (`:10-16`) correctly identifies that `StatefulShellRoute.indexedStack` leaves every hidden branch animating. This is the fix most apps never write.
- **Ambient loops stop in background.** `mini_player.dart:1385-1398` — `didChangeAppLifecycleState` sets `_isAppActive = false` and calls `_waveController.stop()`, restarting via `_syncWave()` on resume. `_syncWave` (`:1405-1419`) also gates on `isBuffering` and `FLUTTER_TEST`. Battery-correct.
- **Drag gestures are properly interruptible.** `now_playing_screen.dart:356-367` handles mid-flight re-grab: if the snap-back controller is animating, `_dragOffset = _anim.value` continues from the painted position, then the tween endpoints are neutralised (`_tween.begin = _tween.end = _dragOffset`). There is a regression comment (`BUG-12`) and a status listener resetting resting state on completion (`:331-338`). Most sheets get this wrong (visible jump on re-grab).
- **Per-frame `setState` avoided.** `:439-441` drives the dismiss transform through `AnimatedBuilder` over a `RepaintBoundary`-wrapped child, so only the transform layer rebuilds — not the whole theme tree.
- **Blur is scarce and capped.** Only **3** `BackdropFilter` sites in the entire app (`glass_container.dart` ×2, `bottom_nav_bar.dart` ×1) and 6 `ImageFilter.blur`; `AppBlur.maxSigma = 18` is a hard clamp (`app_blur.dart:31, 60-64`).
- **Skeletons share one ticker.** `shimmer_skeleton.dart:30-45` — one `AnimationController` for all boxes via an `InheritedWidget` scope, and each box paints its own gradient instead of a `ShaderMask`, with the rationale spelled out (`:57-60`: a `ShaderMask` forces one offscreen layer per frame). That is a measured, correct trade.

**One gesture is animated against the finger.** `bottom_nav_bar.dart:153-159`:

```dart
child: ValueListenableBuilder<double>(
  valueListenable: _visualDyNotifier,
  builder: (context, visualDy, child) {
    return AnimatedContainer(
      duration: context.motionMs(120),
      transform: Matrix4.translationValues(0, visualDy, 0),
```

The `ValueNotifier` is written on every drag update (`:135-140`, throttled to ~16 ms), and each write feeds an `AnimatedContainer` with a 120 ms duration. The implicit animation is therefore restarted roughly 60×/s and **can never catch up** — the bar trails the finger with a constant ~120 ms lag instead of tracking 1:1. Direct manipulation should be un-`tween`ed; only the *release* should animate. This one is worth fixing because the dock is the most-touched surface in the app.

It compounds: the `BackdropFilter` (`:325`) sits *inside* that `AnimatedContainer`, so the blur is re-rasterised while the transform changes on every drag frame.

**Sheets don't declare their route animation**, so the framework's default sheet transition runs with no opportunity to downgrade or retime it for desktop (`pulsr_adaptive_sheet.dart` switches to a centred dialog on tablet/desktop at `:100-105`, but the dialog entry is also framework default via `DialogRoute`).

---

## 3. Top gaps

Max 7, ordered by impact.

1. **Predictive back is configured and dead.**
   `aura_theme.dart:731-735` installs `PredictiveBackPageTransitionsBuilder` for Android; `AndroidManifest.xml:49,72` sets `enableOnBackInvokedCallback="true"`; but all 41 routes are `CustomTransitionPage` (`app_router.dart:62-70, 496-521`), whose builder bypasses `PageTransitionsTheme` entirely. *Impact:* Android 14 users get no back-gesture preview — the gesture feels disconnected from the app on every single navigation. Two sources of truth disagree and the runtime ignores both.

2. **The dock hard-cuts on the first song.**
   `stacked_bottom_dock.dart:484-491` returns a plain `PulsrBottomNavBar` when `!hasSong` and the full stacked dock otherwise — no `AnimatedSize`/`AnimatedSwitcher`. *Impact:* the most emotionally loaded transition in a music player (silence → music) is the only un-animated one; the nav bar also jumps height without a size transition.

3. **Now Playing is a plain surface, not an expanding one.**
   `app_router.dart:496-521` (full-height slide, no scale/fade/radius) + no `Hero` on the mini-player container (`mini_player.dart:817` wraps only the artwork) + no `flightShuttleBuilder` anywhere. *Impact:* the artwork flies while the page slides — two unrelated motions where Apple Music/Spotify present one object. The signature interaction of the product reads as assembled rather than designed.

4. **Dismissing the player reveals a blank stage.**
   `now_playing_screen.dart:194-198` keeps an opaque, non-transformed background outside the drag transform (`:457-478`), and the route is opaque. *Impact:* pulling the player down exposes a flat colour instead of the library the user is returning to; the gesture loses its spatial meaning at exactly the moment it should feel continuous.

5. **The duration scale is nominal, not enforced.**
   33 distinct `motionMs` values; `180 ms` used 33× though untokenized (`pulsr_pressable`, `bottom_nav_bar:268`, `build` parts); only 34% of token calls on a real token; `pulsr_transitions.dart` has zero call sites; router excluded from the ratchet (`motion_token_ratchet_test.dart:16-19`) so `app_router.dart:69-70` passes bare consts. *Impact:* the codebase has a motion *vocabulary* but no motion *rhythm*; near-duplicate values (180/200, 220/240/250, 380/400) are perceptually identical, so the design system buys cost without buying consistency.

6. **Drag-driven `AnimatedContainer` + `BackdropFilter` in the nav bar.**
   `bottom_nav_bar.dart:135-159` writes a notifier per drag frame into a 120 ms implicit animation, with `BackdropFilter` at `:325` inside it. *Impact:* permanent lag behind the finger on the most-used surface, plus repeated blur re-rasterisation while dragging — the one place where the app's otherwise-excellent perf discipline lapses.

7. **iOS has no interactive back-swipe.**
   Zero `CupertinoPage`/platform branching in `lib/core/router`; every route is `CustomTransitionPage`. *Impact:* on iPhone the standard edge-swipe pop is absent on every screen — a HIG violation that Android-only testing will never surface.

---

## 4. Path to 10/10

### P0 — fix before the next release (breaks platform contract or signature UX)

**P0.1 — Restore predictive back.**
*Files:* `lib/core/router/app_router.dart:62-107, 496-521`.
*Change:* stop overriding the transition for *every* route. Either (a) delete `pageTransitionsTheme` from `aura_theme.dart:731-735` and make `_buildPulsrPageRoute` return a `MaterialPage` (letting the theme drive Android predictive back, with `PulsrMotion` applied via a custom `PageTransitionsBuilder` registered in the theme), or (b) keep `CustomTransitionPage` and gate the android branch on `PageTransitionsTheme` compatibility — (a) is the honest fix.
*Acceptance:* on an Android 14 device, a slow back-gesture from `/album/:id` shows the library behind the receding page and the library is visible before commit; a widget test asserts the route class used for `TargetPlatform.android` is not `CustomTransitionPage`.

**P0.2 — Animate the first song into the dock.**
*Files:* `lib/features/shell/presentation/widgets/stacked_bottom_dock.dart:484-491`.
*Change:* replace the early-return branch with an `AnimatedSize` (or `AnimatedSwitcher` with a `SizeTransition`+`FadeTransition`) that owns both the `hasSong: false` and `hasSong: true` trees, using the already-threaded `animDuration`/`animCurve` from `:356-357`.
*Acceptance:* starting playback from the library makes the mini player slide/grow in over `PulsrDurations.page`; pausing to end-of-queue reverses it; `MediaQuery(disableAnimations: true)` makes both instant; an existing golden for the dock still matches.

**P0.3 — Give the dock drag 1:1 tracking.**
*Files:* `lib/features/shell/presentation/bottom_nav_bar.dart:135-159`.
*Change:* drop `AnimatedContainer` from the drag path — apply `Transform.translate` directly from the notifier inside the `ValueListenableBuilder` (no duration), and animate only the reset-to-zero on `onVerticalDragEnd` via a short `AnimationController`.
*Acceptance:* with the drag slowed by hand, the bar's offset equals the finger's delta each frame (instrumented via a widget test asserting the transform after a synthetic drag update); no `BackdropFilter` re-layout during drag.

### P1 — next design-system pass (coherence)

**P1.1 — Make Now Playing an expanding surface.**
*Files:* `lib/features/player/presentation/mini_player.dart:817`, `lib/core/router/app_router.dart:496-521`, all `themes/parts/*_build.dart` Hero sites.
*Change:* wrap the mini-player *container* (not just artwork) in `Hero(tag: 'np_surface')` matching a same-tag container in the player; add a shared `flightShuttleBuilder` that interpolates `borderRadius` and `BoxDecoration` between 12 px and the theme's radius; soften the route to a fade + slight scale so the Hero dominates.
*Acceptance:* a screen recording shows the mini-player card's corners and background morphing continuously into the full player; no visible artwork pop at either endpoint; reduce-motion path shows no flight (see P1.2).

**P1.2 — Gate Hero flights behind Reduce Motion.**
*Files:* `lib/main.dart` (root), or a new `PulsrHeroScope` in `lib/core/widgets/`.
*Change:* wrap the app subtree in `HeroMode(enabled: !reduceMotion)` using the same merged flag as `main.dart:1386`.
*Acceptance:* with the in-app Reduce Motion toggle on, opening Now Playing performs no shared-element flight (widget test: `find.byType(Hero)` flights never start / `tester.pumpAndSettle` with zero intermediate frames containing a `Hero` flight overlay).

**P1.3 — Collapse the duration scale to 5 values and enforce it.**
*Files:* `lib/core/motion/motion_durations.dart`, plus the off-scale call sites (`bottom_nav_bar.dart:159,268,400`, `now_playing_screen.dart:196,247`, `staggered_reveal.dart:38`, `staggered_list_item.dart:20-21`, `player_theme_chrome.dart:325,402`).
*Change:* (a) map `150/160/180 → tap|state`, `220/240/250 → layout|state`, `280/300 → layout`, `380/420/450 → page`; (b) extend `motion_token_ratchet_test.dart` with a fourth check: every `motionMs(N)`/`motion(...)` **literal** must equal one of the five token values, with an explicit allowlist for documented physics durations (`650/850/900` motor inertia, `2600` waveform) — and add `lib/core/router` to `dirs` (`:13-16`).
*Acceptance:* the new ratchet check passes; `rg -o 'motionMs\(\d+\)' | sort -u` yields ≤ 5 values plus the allowlist; no visual regression in motion goldens.

**P1.4 — One press primitive.**
*Files:* `lib/core/widgets/pulsr_pressable.dart:43-44`, `lib/features/player/presentation/themes/player_theme_chrome.dart:485-488`, `lib/features/player/presentation/widgets/player_controls.dart:326-329`.
*Change:* adopt a single `pressedScale` (0.96) and a single down/up pair (`PulsrDurations.tap` down, `state` up); migrate `PlayerDockIconButton` onto `PulsrPressable`; migrate the 141 `InkWell` sites by surface priority (list rows, tiles, nav items first).
*Acceptance:* `rg 'pressedScale: 0\.8[0-9]'` returns zero; a widget test drags a finger onto three different controls and asserts identical scale at hold.

**P1.5 — Put sheets and dialogs inside the family.**
*Files:* `lib/core/widgets/pulsr_bottom_sheet.dart:162`, `lib/core/widgets/pulsr_adaptive_sheet.dart`, `lib/core/widgets/pulsr_dialog.dart:63`.
*Change:* pass `sheetAnimationStyle: AnimationStyle(duration: ctx.motion(PulsrDurations.page), reverseDuration: ctx.motion(PulsrDurations.layout))` at the four `showModalBottomSheet` sites; for dialogs, use a `PageRouteBuilder`/`showGeneralDialog` with the same `PulsrTransitions.fadeScale` already written at `pulsr_transitions.dart:48` — which would finally give that dead file a call site.
*Acceptance:* instrumented test asserts sheet route enter duration equals 320 ms (or 0 under reduce motion); dialogs and sheets dismiss in ≤ 260 ms.

### P2 — craft polish

**P2.1 — Restore iOS interactive pop.**
*Files:* `lib/core/router/app_router.dart`.
*Change:* branch on `Theme.of(context).platform`: on iOS/macOS return `CupertinoPage`-equivalent (or a `CustomTransitionPage` whose route mixes in `CupertinoRouteTransitionMixin`).
*Acceptance:* an iOS simulator edge-swipe from `/album/:id` pops interactively and can be cancelled mid-gesture.

**P2.2 — Make dismissal return to the library.**
*Files:* `lib/features/player/presentation/now_playing_screen.dart:194-198, 457-478`.
*Change:* set `opaque: false` on the Now Playing `CustomTransitionPage` so the shell paints behind, and scrub the *background* opacity with the drag progress instead of translating an opaque panel.
*Acceptance:* a half-completed swipe shows the library and mini player behind the receding player; releasing below threshold restores it with no flash.

**P2.3 — Collapse the three staggers into one.**
*Files:* `lib/core/widgets/staggered_list_item.dart`, `lib/core/widgets/staggered_reveal.dart`, `lib/core/widgets/shimmer_skeleton.dart:271-291`.
*Change:* delete `StaggeredListItem` (3 uses → `StaggeredReveal`), and have `_cascade` delegate to `StaggeredReveal` so skeletons and content share one timing.
*Acceptance:* `rg 'StaggeredListItem'` returns zero in `lib`; the skeleton cascade and the list cascade have identical delay/duration constants.

**P2.4 — Coordinate at the screen level.**
*Files:* `lib/features/home/presentation/home_screen.dart`, section widgets.
*Change:* introduce an optional `baseDelay` on `StaggeredReveal` and pass increasing bases per section (hero 0, recents 60 ms, recently added 120 ms) so Home assembles as one cascade.
*Acceptance:* a slow-motion capture shows sections arriving in a single sweep rather than three simultaneous ones.

**P2.5 — A real favorite burst.**
*Files:* `lib/features/player/presentation/themes/player_theme_chrome.dart:292-353`.
*Change:* replace the key-sniffing `transitionBuilder` (`:329-332`) with two explicit children keyed by state, and add a one-shot scale overshoot (`1.0 → 1.18 → 1.0`) on the filled heart plus a brief radial glow, skipped under Reduce Motion.
*Acceptance:* tapping the heart produces a distinct overshoot on the incoming heart only; the outgoing outline does not visibly scale.

---

## 5. Already best-in-class — do not regress

These are the parts that are better than most shipping apps. They are also the parts a refactor is most likely to quietly break.

1. **The single-tag Hero chain.** `player_theme.dart:11-12` + `theme_registry.dart:41-43` force one tag across mini player, tablet bar and all 11 themes. Any change to the registry must keep the tag derivation.
2. **`TickerGatedBranchContainer`** (`ticker_gated_branch_container.dart:29-45`) — `TickerMode` + `ExcludeFocus` + `RepaintBoundary` per hidden shell branch. Removing this silently resumes five always-running tab animations.
3. **Theme physics.** Vinyl/CD/cassette motor inertia (`velocityController` spin-down over `motionMs(650)` with `Curves.decelerate`, `vinyl_player_theme.dart:88-108`, `cd_player_theme.dart:104-124`), tonearm/pickup engagement, gloss parked at `1.0` under reduce motion (`cd_player_theme.dart:151-156`). This is genuine skeuomorphic craft.
4. **`theme_reduce_motion_test.dart:85-100`** — a per-mode "no ticker" assertion plus a positive control. Keep both halves; the control is what stops the suite passing vacuously.
5. **`audio_visualizer.dart`** (`:173-175, 454-467, 568`) — `TickerMode` + `motionEnabled` + visibility + 30 fps throttle + GPU-budget style downgrade, checked again inside the listener.
6. **`AppBlur`** (`app_blur.dart:31, 46, 52-64`) — GPU-saver and high-contrast gating with a WCAG-safe solid fallback and a hard sigma ceiling. Only 3 `BackdropFilter`s exist because of this policy.
7. **`stacked_bottom_dock.dart:111, 356-357`** — resolve the token **once**, thread it into all six animated widgets. The model the router should follow.
8. **`_SwipeDownToDismiss`** (`now_playing_screen.dart:356-367, 439-441`) — mid-animation re-grab with endpoint neutralisation, `AnimatedBuilder` over a `RepaintBoundary` child, threshold haptic (`:382`), weighted resistance (`:376`).
9. **Play button** (`player_controls.dart:326-406`) — asymmetric 90/280 press, rotate+scale+glow morph. Best single control in the app.
10. **Seek feedback** (`player_seek_bar.dart:463-469, 591-606`) — relative delta pill + dual-tone timestamp + thumb scale + four haptic moments.
11. **`SkeletonShimmer`** (`shimmer_skeleton.dart:30-45, 57-60`) — one ticker, per-box gradient instead of `ShaderMask`, with the layer-cost rationale recorded.
12. **The motion ratchet itself** (`motion_token_ratchet_test.dart`) — a build-breaking guard is worth more than a style guide. Strengthen it (P1.3), never remove it.
13. **In-app Reduce Motion** (`main.dart:1386-1393`) — one merge point that rewrites `disableAnimations`, so no widget needs to read settings. This is the correct architecture.
14. **`PulsrModalTracker`** (`pulsr_modal_tracker.dart`, `stacked_bottom_dock.dart:52-62`) — the dock hides whenever a modal or keyboard appears, via `AnimatedSlide` on `PulsrDurations.layout`. Prevents the classic "floating bar over the sheet" defect.

---

## 6. Unverified / out of scope

- **No runtime measurement.** `flutter test` cannot run here (`Could not find the pub cache. No LOCALAPPDATA`), so the ratchet's pass state was verified by re-implementing its three regex checks over the tree, not by execution. Frame timings, jank on real devices, and the *appearance* of the Hero flight, the drag-dismiss reveal and the predictive-back gesture are **unverified**.
- **`Hero` under `disableAnimations`**: I assert the flight is *not* suppressed because no gate exists anywhere and `transitionDuration` is a bare const; the exact framework behaviour was not observed.
- **Custom theme builder** (`custom_theme_builder_screen.dart`, 593 lines) was not audited in depth — its live preview motion may add further off-scale durations.
- **`quran_radio_hero_carousel.dart:2142, 2212`** carries two off-scale controllers (1000/1100 ms) with `repeat()`; it is guarded by `motionEnabled` (2 occurrences) but its auto-advance timing deserves a separate look.
- Only **8 of 11** themes were read in full (vinyl, cd, cassette, circle, waveform, card, minimal, classic, lyrics) plus the shared chrome they all render through; `clean`, `milkdrop` and the `parts/*_build.dart` bodies were sampled via `rg` rather than read end-to-end.
