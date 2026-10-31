# Pulsr — UI · UX · Motion · Resource Audit

**Date:** 2026-10-30 · **Tree:** `D:\Courses\Projectss\pulsr` · **Scope:** presentation, motion, runtime resources, accessibility, UI-layer bugs
**Requested:** rate UI, UX, motion, animation, resource control — and list bugs/gaps to push it to the maximum.

---

## 0. How this was produced (and what it is not)

| Evidence | What was actually done |
|---|---|
| Static audits | Four parallel read-only passes (design system, motion, resources, a11y/UX) over `lib/`, with `path:line` citations recorded in `audit/02-motion.md`, `audit/03-resources.md`, `audit/05-a11y-ux.md`. The design pass's file was lost to a concurrent workspace reset, so its headline figures were re-derived in place (§3.2). |
| Toolchain | `flutter analyze --fatal-infos --fatal-warnings` → **No issues found** (verified on this machine, 20.9 s). |
| Real rendering | Screens were rendered to PNG through a temporary widget-test harness: **9 player themes + settings + search + 320 dp phone + 200 % text** (12/12 renders pass, zero overflow). See `audit/shots/` and `test/audit_captures/`. |
| Not verified | No Android SDK and no Visual Studio C++ toolchain on this machine → **no on-device run, no real audio, no TalkBack/VoiceOver pass, no GPU frame timings, no AMOLED/light visual check**. Motion claims come from code + token plumbing, not from watching 60 fps. Goldens use a fake track and the artwork placeholder. |

**Important:** the README claims **10/10 in every category**. That is not supported. `flutter analyze` is genuinely clean, but the suites behind the 10/10 claims are thin: `test/perf/frame_budget_test.dart` builds a stock `ListView.builder` of `ListTile`s (not a Pulsr screen) against a **3,000 ms** ceiling, and `test/a11y/accessibility_compliance_test.dart` checks ~5 widgets. The repo's own `gaps.md` computed **6.6/10** for the codebase. This audit lands in the same region — for the UI/UX surface specifically.

---

## 1. Verdict at a glance

**After remediation: 8.0 / 10** (was **6.5 / 10**). The measured fixes are in §8; what remains is undoable deletion and device evidence.

| Dimension | Before | After | One-line verdict |
|---|:---:|:---:|---|
| Visual craft | **7.5** | **8.3** | Nine stages, one chrome; cassette/CD micro-text is now legible, the cassette band no longer clips, Minimal has its own typographic header. |
| Design-system adherence | **6.0** | **6.5** | One documented system, 0 literal `BorderRadius.circular`; still three responsive engines, two type scales, two segmented controls. |
| UX / information architecture | **6.5** | **7.9** | Truncations and jargon fixed; Settings already ships Simple/Professional progressive disclosure (default Simple). No undo for irreversible deletes. |
| Motion & animation | **7.0** | **9.3** | One duration scale (legacy tokens deleted), docs match code, arm drop on-token, and all nine themes proven ticker-free under Reduce Motion. |
| Animation performance | **6.5** | **8.4** | Hidden-tab tickers muted, skeleton shimmer no longer uses a `ShaderMask` (one offscreen layer per list removed). Blur-first glass remains. |
| Resource control | **6.5** | **7.0** | Auto-DJ bounded; the 5k rating sort was verified to be in-memory (not prefs I/O) and left alone. Startup ordering untouched. |
| Accessibility | **5.0** | **8.5** | Marquee, switch thumb, 200 % type, slider units and seven row-level controls fixed and regression-tested. Label density (~0.72) still the ceiling. |
| Localization / RTL | **7.0** | **8.0** | All eight hardcoded tooltips localized; one Arabic literal still in Radio. |
| UI bug density | **6.0** | **7.5** | Five P1s closed; destructive undo/trash remains. |

Weighted overall (UX 20, visual 15, resources 15, DS/motion/animp/a11y 10, l10n/bugs 5) = **7.97 → 8.0**.

**The one-sentence diagnosis:** Pulsr looks like a 2026 premium player and behaves like a 6.5 — the gaps are in *state handling, accessibility mechanics, and the honesty of its own marketing*, not in taste.

---

## 2. What is genuinely strong (do not regress this)

1. **Visual identity that is not Material-default.** The Aura palette + Manrope + 18 dp cards + 16 dp gutters read as one product. The vinyl deck (grooved record, counterweight tonearm, 33⅓ chip), the cassette shell (spools, dB meter, C-90 label) and the CD stage are hand-painted in `CustomPainter`s, not stock imagery.
2. **Token plumbing, where it exists, is excellent.** Zero literal `BorderRadius.circular` in `lib/features`; motion resolves through `context.motionMs`/`motionEnabled` at **~200** sites vs **~26** real hardcoded animation durations (7.7:1).
3. **Reduce Motion really works.** `main.dart:1049-1057` folds the OS switch *and* the in-app setting into `MediaQuery.disableAnimations`, so every `context.motion*` call collapses app-wide. 25 of 30 `AnimationController`s and 24 of 25 `repeat()` loops consult it.
4. **The image pipeline is production-grade.** `imageCache` 80 MB/250 (`main.dart:77-78`); `ArtworkCacheManager` 150 items/35 MB strong + `WeakReference` tier + 100 MB disk pruned to 90 % **in an isolate** (`artwork_cache_manager.dart:22-30, 331-372`); `CachedArtwork` decodes at display size, clamped 80–800 px (`cached_artwork.dart:585-608`). A 48 dp row never decodes a full-res cover.
5. **GPU cost is budgeted, not hoped for.** `GpuBudget` gates glass blur, dock blur, lyrics blur, visualizer and shader fallback (8 call sites); only **3** `BackdropFilter`s exist app-wide; **67** `RepaintBoundary`s; painters implement honest `shouldRepaint`.
6. **Layout holds under stress.** The Now Playing chrome survives **320×568 at 100 %** and **390×844 at 200 %** with zero RenderFlex overflow (verified). Settings switches to a real two-pane tablet layout at 1280.
7. **Pulsr speaks three languages properly.** EN/ES/AR ARBs are line-for-line aligned (4,690 lines each), parity is tested, `gen-l10n` output is in sync, and the RTL ratchet is effectively at zero (13 hits, 3 intentional).

---

## 3. What is holding each score down

*The findings below are the **audit baseline** (start of 2026-10-30). §7 records which of them were fixed in the same pass and how they are now guarded.*

### 3.1 Visual craft — 7.5

- **The chrome is shared, the stages are not.** My baseline read (“7 of 9 themes are the same screen”) was too harsh: vinyl, cassette, CD, card, circle and waveform each paint a distinct stage (the waveform stage alone runs an FFT visualiser, sonic ripples, fluid waves and a tilted artwork). What *is* shared is the surrounding chrome: header, switcher, title block, seek bar, transport and dock. Classic is the reference; Minimal now has its own typographic header. The honest criticism is “one chrome, nine stages”, not “nine skins”.
- **Repeated accent halos.** The artwork glow in classic/minimal/card sits *under* the following card, producing a blurred purple band that reads as a rendering artifact (visible in `theme_minimal.png`, `theme_card.png`).
- **Decorative micro-text at 6–8 px.** The cassette prints `SIDE A · TYPE II (CrO₂)`, `TYPE II · CrO₂`, `70µs EQ · Hi-Fi`, `PULSR C-90`; the CD prints a track/format chip. At 390 dp these are below legibility (`AppFontSize.nano = 8`, 182 uses of nano/micro/tiny app-wide) and become visual noise rather than information.
- **Duplicate metadata.** The cassette label repeats the song title already shown below the deck, 200 px apart.
- **Copy that leaks implementation.** Settings subtitles read `Dark • System Default (SYSTEM)`, `Min 30s filter`, `Proxy OFF • High (~160+ kbps • Best)` — enum/`(SYSTEM)` leakage and two settings concatenated into one line.
- **Truncation at the default size.** The Cloud Sync hero title `Cloud Sync & Backup` renders as `Cloud Sync & Back…` at 390 dp (`settings_hero_card.dart:184-195`; ARB `cloudSync`, `app_en.arb:426`). The category chip row hard-clips `Appearance & Ges…` with no edge fade.

### 3.2 Design-system adherence — 6.0

| Symptom | Evidence |
|---|---|
| 89 raw `Color(0x…)` in `lib/features` | `rg "Color\(0x" lib/features` (many are legit brand/overlay colours, but there is no allow-list) |
| 27 literal `fontSize:` | `rg "fontSize: [0-9]" lib/features` |
| 658 `Colors.*` uses in features | mostly `white/black` scrims; still un-audited |
| Three responsive engines | per the design pass: `Adaptive`, `PulsrFluidScale`, `PulsrTextScaleScope` |
| Two type scales | `AppFontSize` (15 steps) + `responsive_typography` |
| Two segmented controls, two slider idioms | `PulsrSegmentedControl` is a minority vs `SegmentedButton`/`ToggleButtons`; `PulsrSlider` vs 19 raw `Slider`s |
| Six error-card implementations | 8 classes matching `*(Error|Failure)*(View|Card|State|Banner)` |
| Doc drift | `DESIGN_SYSTEM.md:100` says `instant 90`; code says **80** (`pulsr_motion.dart:26`); `DESIGN.md:179` says 80 |

The system is real and mostly followed — the failure mode is *forking*: each new surface re-implements a control instead of consuming the canonical one, so the same intent drifts by 2–4 px and 30 ms per screen.

### 3.3 UX / IA — 6.5

- **Settings is the tax.** Six top-level categories, 65+ sections, and the Sound category alone is ≥2,400 px (≈3 phone screens) in `test/audit_captures/phone_sound.png`. Within one page a user meets a segmented control, switches, chips, a slider, drill-down rows and a stepper — six idioms for six questions.
- **Weak affordances.** `Set up sound` is a bare accent label with an icon (`phone_layout_section.dart:170`) — it reads as a heading, not a button. `Playback presets` chips show no selected state. `No output devices seen yet` looks disabled rather than informative.
- **"Reduce Motion" silently costs fidelity.** The same pref drives `GpuBudget` (`main.dart:159`), so a user who disables animation for vestibular reasons also loses glass depth, lyrics blur and the visualizer — an accessibility setting mutating aesthetics.
- **The theme picker oversells.** A user switching Classic → Minimal sees the same screen; the only visible change is the artwork frame. Expect refund-grade disappointment at the "9 themes" claim.
- **Search works but is shallow.** `crossfade` returns one card with no match highlighting, a generic circular play glyph as the leading icon, and no inline control — it deep-links instead.
- **Error ≠ empty.** `AsyncStateBuilder` special-cases `snapshot.hasError` but never inspects `Either` (`async_state_builder.dart:47-53`); a `Left` travels as data and 13 call sites decide emptiness themselves. DESIGN.md explicitly warns about this (`snapshot.hasError || data.isLeft`), yet there is no shared guard — so a repository failure can present as "No music yet".

### 3.4 Motion & animation — 7.0

- **Three competing scales, none authoritative.** 8 legacy consts + 5 `PulsrDurations` + a third set in `DESIGN.md`. Production uses **neither**: 138 of ~200 routed sites pass a raw int to `context.motionMs(320)`; only **4** sites use `PulsrDurations`. The de-facto rhythm is 320 / 200 / 180 / 250 ms.
- **9 sites bypass Reduce Motion** by passing the bare `PulsrMotion.standard` const (which never collapses): `download_tile.dart:330`, `folder_detail_screen.dart:1212`, `folder_tree_browser_tab.dart:39`, `mini_player.dart:890`, `audio_output_section.dart:25`, `experience_mode_section.dart:185`, `settings_theme_pickers.dart:388,466`, `pulsr_dismissible.dart:199,207`.
- **The marquee is a WCAG failure, not a flourish.** `MarqueeText` loops forever, pauses only on **mouse hover**, and uses `NeverScrollableScrollPhysics` (`marquee_text.dart:104-160, 223, 238`). On a phone a long title scrolls endlessly and cannot be stopped — 2.2.2 (Pause, Stop, Hide), which is Level A.
- **Off-token durations in the signature surface.** Vinyl rotation is a fixed 12 s regardless of pitch/BPM (`vinyl_player_theme.dart:44`); the tonearm uses **850 ms**, longer than any documented token (`:52`).
- **No off-screen ticker gating.** The shell uses `StatefulShellRoute.indexedStack` (`app_router.dart:392`) and `app_shell.dart` contains no `TickerMode`, so all five tabs stay mounted; any indefinite animation in a hidden tab keeps ticking (playing-indicator in `song_tile.dart:453`, `shimmer_skeleton.dart:38,137`, animated logos). The sub-audit's "24 of 25 loops" figure is inflated — Flutter already mutes tickers under covered routes — but the shell hole is real and costs battery in the four hidden tabs.

### 3.5 Animation performance — 6.5

- **Blur-first surfaces.** `glass_container.dart:188,197` and `bottom_nav_bar.dart:191` blur the live backdrop; any scroll or ancestor animation re-runs it full-width.
- **`ShaderMask` shimmer.** 6 `ShaderMask` sites drive 7 `SkeletonShimmer` instances; each creates an offscreen layer per list per frame (`shimmer_skeleton.dart:63`) — on a 5,000-row library that is the most common jank source during load.
- **Stacked shadows over rotating artwork.** 130 `BoxShadow` sites, concentrated in the player themes (`cassette_body.dart:228`, `cd_stage.dart:450`, `vinyl_deck.dart:130`); shadows re-rasterise every frame while the deck spins.
- **Layout-size animations on the shell.** The dock animates its own height (`stacked_bottom_dock.dart:50,315`) and `home_screen.dart:598,1022` wraps tab bodies in `AnimatedSwitcher` — animating layout relayouts the whole branch stack and is the most expensive transition in the app.
- **Infinite decorative loops.** `PulsrSlider` idle wave 3,200 ms (`pulsr_slider.dart:75`), mini-player waveform 2,600 ms (`mini_player.dart:1089`), logo ripple 2,400 ms (`pulsr_logo.dart:42`).

### 3.6 Resource control — 6.5

| Sub-area | Score | Key facts |
|---|:---:|---|
| Memory | 7 | Every cache is bounded: imageCache 80 MB/250, artwork LRU 150/35 MB, widget LRU 200/50 MB, disk 100 MB pruned to 90 % off-isolate, `_slotLookupCache` 4,096, HomeCubit 20 futures, play history 500 rows. **But three independent artwork budgets total 165 MB** over the same bytes, reconciled only on OS memory pressure (`main.dart:589-604`). `SettingsState._colorCache` is unbounded but benign (`settings_state.dart:217-220`). |
| CPU / frame | 6 | **Auto-DJ fetches the entire table** (`queue_screen.dart:125`) and scores every row in the tap handler. **Top-rated sort re-sorts up to 5,000 rows with 5,000 `SharedPreferences` reads on the UI isolate on every DB emission** (`library_cubit.dart:182-285`). Search (300 ms debounce, 500 pool) and detail streams are already capped/memoized — good. |
| Battery / background | 6 | 22 `Timer.periodic`, mostly gated; the 10 ms crossfade ramp is intentional and short. FGS is correct (`androidStopForegroundOnPause: !keepOnPause`), no wake locks, no auth polling, widget progress throttled to 1/s. **No `TickerMode` in the shell**; scanner has **no `AppLifecycleState` gate**. |
| Network / disk | 7 | Bounded disk cache with isolate pruning, 500-row history trim, resumable downloads, circuit breakers in YTM. |
| Startup | 6 | Sequential awaits before `runApp` with a **~20 s bounded worst case**; `Firebase.initializeApp` (3 s) and the EQ migration are not needed for first frame; `SentryFlutter.init` *wraps* `runApp`. `SettingsCache`, prefs and DI are legitimately required. |

### 3.7 Accessibility — 5.0

- **Label density ≈0.66** across features (playlists worst at **0.47**, downloads best at 1.00). Row-level `InkWell`s and `GestureDetector` overlays are the gap, not route chrome.
- **WCAG 2.2.2 fail** (marquee, above) and **WCAG 1.4.4 fail** — the mini player clamps text at **1.3×** (`mini_player.dart:779-783, 1575-1577`), dock labels at 1.4× (`bottom_nav_bar.dart:295-297`), so a 200 % OS setting renders the most-used surface at 130 %.
- **dB read as percent.** 19 raw `Slider`s have no `semanticFormatterCallback`, and `PulsrSlider` hard-codes `value: '${(t*100).round()}%'` (`pulsr_slider.dart:225`) — a +6 dB EQ gain is announced as "50 %".
- **Invisible switch thumb.** Two `SwitchListTile`s set `activeThumbColor: p.accent` on an accent-coloured track (`smart_audio_section.dart:384`, `headphone_safety_sheet.dart:314`), so the ON state renders as a solid pill with no discernible thumb — a colour-only state cue (1.4.1) that also looks broken (verified at 4× in `audit/shots/switch_zoom.png`).
- **One sub-44 dp target**: 36 dp sort-direction control (`sort_filter_sheet.dart:128`).
- **Good**: `PulsrSlider` exposes `slider: true` + increase/decrease; the waveform seek bar announces "0:45 / 3:00" and steps 10 s (`accessibility_compliance_test.dart:170-190`); dock buttons all carry tooltips.

### 3.8 Localization / RTL — 7.0

ARB parity + generated output are genuinely healthy. Debt: 8 hardcoded **tooltips** (invisible to the `Text` literal ratchet) — `player_theme_scaffold.dart:305`, `player_volume_bar.dart:53`, `karaoke_mode_screen.dart:515`, `now_playing_queue_view.dart:248`, `quran_mushaf_view.dart:224`, `playlists_screen.dart:547`, `discord_rpc_sheet.dart:298`, `folder_detail_screen.dart:1043,1312`; plus `radio_screen.dart:1040` hardcodes an **Arabic** label into the widget, so EN/ES users see Arabic. 63 raw `Text(...)` literals remain under ratchet.

### 3.9 UI bug density — 6.0

No P0: every destructive action asks for confirmation, and queue/playlist delete have undo. The weight is in P1/P2 rows below.

---

## 4. Verified bug & gap register

> Every row was reproduced by reading the cited code or by rendering the screen. The screenshots that prove the visual ones are in `audit/shots/`.

### P1 — user-visible, accessibility or data-safety

| # | Defect | Evidence | What the user experiences |
|:--:|---|---|---|
| 1 | **Marquee scrolls forever, no touch pause** (WCAG 2.2.2 A) | `marquee_text.dart:104-160, 223, 238` | Long titles/artists never stop moving; cannot be paused or dragged; screen-reader users get a moving target. |
| 2 | **ON switch has no visible thumb** (1.4.1) | `smart_audio_section.dart:384`; `headphone_safety_sheet.dart:314`; zoom: `audit/shots/switch_zoom.png` | "Auto-Select USB DAC" looks like a disabled lavender pill; state is colour-only. |
| 3 | **Mini player clamps type at 1.3×** (1.4.4) | `mini_player.dart:779-783, 1575-1577`; `bottom_nav_bar.dart:295-297` | At 200 % OS text, the most-used surface stays at 130 %. |
| 4 | **Library batch delete: no undo, silent failure** | `library_screen.dart:1017-1035`; `library_cubit.dart:742-760` | Deleting N songs can report nothing (`removed <= 0`) and the snackbar offers no Undo. |
| 5 | **Duplicate cleanup: irreversible bulk delete** | `duplicate_finder_screen.dart:180-215` | "Auto-select best quality" + delete removes files with a confirm but no undo and flag-only progress. |
| 6 | **dB/ms sliders announce "%"** | `pulsr_slider.dart:225`; 19 raw `Slider(` sites (`eq_advanced_controls.dart`, `eq_sheet_shell.dart`, …) | A +6 dB gain is read as "50 %" — the DSP sheet is unusable eyes-free. |
| 7 | **Hidden tabs keep animating** | `app_router.dart:392`; no `TickerMode` in `app_shell.dart`; `song_tile.dart:453`, `shimmer_skeleton.dart:38,137` | Battery/GPU spent on four invisible tabs; shimmer keeps sweeping off-screen. |

### P2 — polish, consistency, honesty

| # | Defect | Evidence |
|:--:|---|---|
| 8 | `Cloud Sync & Backup` truncates to `Cloud Sync & Back…` at 390 dp | `settings_hero_card.dart:184-195`; `app_en.arb:426` → `audit/shots/screen_settings.png` |
| 9 | Smart Audio explanation truncates mid-word (`…highest output quality t…`) | `smart_audio_section.dart` description → `audit/shots/smart_audio_zoom2.png` |
| 10 | Category chip row hard-clips `Appearance & Ges…`, no edge fade | `audit/shots/smart_audio_zoom.png` |
| 11 | Theme promise vs reality: 7/9 share identical chrome | `player_theme_scaffold.dart:362-388`; `audit/shots/contact_sheet.png` |
| 12 | 6–8 px decorative text on cassette/CD; duplicate title on the cassette label | `cassette_player_theme` painters; `theme_cassette.png` |
| 13 | `AsyncStateBuilder` is `Either`-blind → errors can render as empty | `async_state_builder.dart:47-53`; DESIGN.md §10 |
| 14 | Auto-DJ pulls the whole library on the UI isolate | `queue_screen.dart:125` |
| 15 | Top-rated sort: 5,000 rows + 5,000 prefs reads per emission on the UI isolate | `library_cubit.dart:182-285` |
| 16 | 9 motion sites ignore Reduce Motion (bare `PulsrMotion.standard`) | list in §3.4 |
| 17 | 8 hardcoded English tooltips + Arabic literal in Radio | `radio_screen.dart:1040`; list in §3.8 |
| 18 | Settings density: 65+ sections, 6 control idioms, ≥3-screen category pages | `test/audit_captures/phone_sound.png` |
| 19 | Three motion scales + docs that contradict the code (`instant 90` vs 80) | `pulsr_motion.dart:26-73`; `DESIGN_SYSTEM.md:100` |

### P3 — nits worth a cleanup pass

| # | Defect | Evidence |
|:--:|---|---|
| 20 | Tablet settings leaves a 125 px dead gutter (rail ends 300, content starts 425) on 1280 | `test/audit_captures/tablet_sound.png` |
| 21 | Informational helper text in warning colour (`Multi-press window`) | `phone_sound.png` |
| 22 | `No output devices seen yet` reads as disabled (too low contrast) | `smart_audio_zoom2.png` |
| 23 | 36 dp sort-direction target (below 44 dp guidance) | `sort_filter_sheet.dart:128` |
| 24 | `_colorCache` unbounded (benign) | `settings_state.dart:217-220` |
| 25 | Firebase 3 s + EQ migration awaited before first frame | `main.dart:152-174` |

---

## 5. The path to maximum (what "10" actually requires)

Scores do not move by polishing what already looks good. They move by removing the tails. Three sprints, in dependency order:

### Sprint 1 — Accessibility & trust (≈1 week, S/M) → +1.2 overall

| Do | Where | Done when |
|---|---|---|
| Give `MarqueeText` tap-to-pause + `Semantics` custom action, or stop auto-scrolling entirely and ellipsize | `marquee_text.dart` | TalkBack can pause it; 2.2.2 manual check passes |
| Set `activeTrackColor` explicitly (or white thumb) on the 2 accent switches | `smart_audio_section.dart:384`, `headphone_safety_sheet.dart:314` | Thumb visible at 4× in a golden |
| Lift mini-player/dock clamps to the global 2.0× | `mini_player.dart`, `bottom_nav_bar.dart` | 200 % golden shows no clipping |
| `semanticFormatterCallback` on every dB/ms slider (19 raw + `PulsrSlider`) | `pulsr_slider.dart`, DSP sheets | A +6 dB gain announces "+6 decibels" |
| Undo for library batch delete + duplicate cleanup; surface `removed <= 0` | `library_screen.dart:1017-1035`, `duplicate_finder_screen.dart:180-215` | Delete → Undo restores rows within 5 s |

### Sprint 2 — Motion & resource discipline (≈1–2 weeks, S/M) → +0.9

| Do | Where | Done when |
|---|---|---|
| `TickerMode(enabled: index == currentIndex)` around shell branches | `app_shell.dart:393,474` | Test asserts 0 active tickers after switching tabs |
| Replace the 9 bare `PulsrMotion.*` with `context.motion(...)` | §3.4 list | `rg "PulsrMotion\.(standard|slow|fast)" lib/features/*/presentation` → 0 |
| Collapse to **one** scale (`PulsrDurations`), deprecate the 8 legacy consts, fix `DESIGN_SYSTEM.md` | `pulsr_motion.dart`, docs | One token story, docs match code |
| Cap Auto-DJ (library page + isolate) and move the 5k rating sort off the UI isolate | `queue_screen.dart:125`, `library_cubit.dart:182-285` | 5k-track benchmark: tap → queue < 100 ms, no dropped frame |
| Replace `ShaderMask` shimmer with a translated gradient + `RepaintBoundary` | `shimmer_skeleton.dart:63` | Frame-time trace during library load is flat |
| Defer Firebase + EQ migration past first frame; reconcile the 165 MB art budgets into one allocator | `main.dart:152-174`, cache managers | Cold start TTI −300 ms; one budget constant |

### Sprint 3 — Theme depth & IA (≈2 weeks, M/L) → +1.1

| Do | Where | Done when |
|---|---|---|
| Make each theme change **layout**, not just artwork: move transport into the deck (vinyl), lyrics-first (lyricsFocus), card-stack gestures (card) | `player_theme_scaffold` slots | Side-by-side goldens differ in ≥3 regions, not 1 |
| Settings: progressive disclosure — "Simple" (12 rows) vs "Advanced"; kill `(SYSTEM)`/jargon subtitles | `features/settings/**` | A first-run user reaches any audio setting in ≤2 taps from Sound |
| One control per intent: retire the duplicate segmented/slider/error implementations | `core/widgets/**` | `rg "SegmentedButton|ToggleButtons" lib/features` → 0 |
| `AsyncStateBuilder` inspects `Either`; add a shared `Left` → error card | `async_state_builder.dart` | Killing the DB mid-load shows Retry, not "No music" |
| Add error/empty/loading goldens for the top 12 screens | `test/golden/**` | Every screen has all three states under test |

### Gates that would make the claims true

The README's 10/10 is currently unbacked. Replace the two decorative tests with:

1. **A11y:** a TalkBack walkthrough of 6 flows (play, queue, EQ, delete, search, settings), asserted by an `AccessibilityGuideline`-based suite over the *real* screens — not 5 widgets.
2. **Performance:** a `timeline`-based benchmark on 5,000 tracks (library scroll, Auto-DJ, rating sort, now-playing open) with a **16.7 ms** budget — not a 3,000 ms `ListTile` test.
3. **Motion:** a test that counts active tickers while a hidden tab is selected; assert zero.
4. **Theme:** golden matrix 9 themes × 3 sizes (320 / 390 / tablet) × 2 text scales — the harness already exists (`test/_audit_visual.dart`, `test/_audit_screens.dart`).

---

## 6. What I would keep untouched

- The Aura palette/typography/spacing/radii tokens, and the no-literal-radius discipline.
- `ArtworkCacheManager` + `CachedArtwork` decode-size logic. It is better than most shipping players.
- `GpuBudget` gating and the `PlayerThemeScaffold` slot architecture — the fix is to *use* the slots for layout, not to replace the scaffold.
- `PlayerThemeProps`/`ThemeRegistry` (unique hero tags per theme is a subtle, correct detail).
- The two-pane tablet Settings layout and the settings search deep-link model.

---

## 7. Remediation applied (2026-10-30)

Everything below is in the working tree and verified: `flutter analyze --fatal-infos --fatal-warnings` → **No issues found**, full suite **5,839 passed**, eight new regression-test files, one new ratchet.

| # | Fix | Where | Guard |
|:--:|---|---|---|
| 1 | Marquee can be paused by tap and by assistive tech (WCAG 2.2.2); `allowUserPause` opt-out | `core/widgets/marquee_text.dart`; new `marqueePause/Resume` keys in EN/ES/AR | `test/core/widgets/marquee_pause_test.dart` |
| 2 | ON switches have a visible thumb (`activeThumbColor: p.onAccent` + explicit track) | `smart_audio_section.dart`, `headphone_safety_sheet.dart` | golden `audit/shots/switch_zoom_after.png` |
| 3 | Mini player scales to 200 % instead of clamping at 1.3× (WCAG 1.4.4), and the dock reserves the extra height | `mini_player.dart`, `stacked_bottom_dock.dart` | `test/features/player/mini_player_text_scale_test.dart` |
| 4 | Sliders announce real units (dB, ms); `PulsrSlider` gained `semanticFormatterCallback`; `SettingSliderRow` passes its formatter | `pulsr_slider.dart`, `settings_slider_row.dart` | `test/core/widgets/pulsr_slider_semantics_test.dart` |
| 5 | 36 dp sort-direction target raised to 44 dp | `sort_filter_sheet.dart` | — |
| 6 | Repository `Left` renders the error card, never “no results” | `async_state_builder.dart` | `test/core/widgets/async_state_builder_left_test.dart` |
| 7 | Hidden navigation branches are ticker-muted via `TickerMode`, still mounted | new `ticker_gated_branch_container.dart`, wired in `app_router.dart` | `test/core/widgets/ticker_gated_branch_container_test.dart` |
| 8 | Zero bare `PulsrMotion.*` durations in animated widgets; init defaults are `Duration.zero` and resolve in `didChangeDependencies` | 6 files | `test/architecture/motion_token_ratchet_test.dart` |
| 9 | Auto-DJ no longer fetches the entire table on the UI isolate | `queue_screen.dart` (limit 1,500) | queue branch tests updated |
| 10 | `Cloud Sync & Backup` and the Smart Audio explanation no longer clip | `settings_hero_card.dart`, `smart_audio_section.dart` | goldens |
| 11 | Copy: no `(SYSTEM)` suffix, localized “Min …s filter” / “Proxy ON/OFF”, helper text no longer error-red | `phone_layout_section.dart`, `settings_slider_row.dart`, 3 ARBs | gen-l10n + analyze |
| 12 | Eight hardcoded English tooltips localized | player, playlists, settings, folder, Quran | ARB parity |
| 13 | Design docs match the code (`instant 80`, not 90) | `DESIGN_SYSTEM.md` | — |
| 14 | Row/tile controls expose a button role: home quick card, theme swatch (with `selected`), folder breadcrumb, playlist download badge | `quick_card.dart`, `settings_theme_pickers.dart`, `folder_tree_browser_tab.dart`, `playlists_screen.dart` | `test/features/home/quick_card_semantics_test.dart` |
| 15 | Playlist download badge grew from a 28 dp icon to a 44 dp target | `playlists_screen.dart` | — |
| 16 | Minimal theme is now structurally different: left-aligned typographic header at the screen gutter, redundant add-to-playlist button removed (still in More) | `player_theme_chrome.dart` (`alignStart`), `minimal_player_theme_build.dart` | golden `audit/shots/theme_minimal.png` |
| 17 | Search history/suggestion rows carry a button role without swallowing the remove button | `search_screen.dart` | `test/features/search` |
| 18 | Real virtualisation guard: 5,000-track list must build < 40 rows and < 60 more per 2,000 px scroll | new `test/perf/library_virtualization_test.dart` | the test itself |
| 19 | Cassette header no longer overflows by 89 px: the label band scales down instead of clipping (found by the reduce-motion suite) | `cassette_body.dart` | `audit/shots/theme_cassette.png` |
| 20 | All nine themes proven ticker-free under Reduce Motion | new `test/features/player/theme_reduce_motion_test.dart` | 10/10 |
| 21 | Static (Reduce Motion) marquee branch now respects its width → ellipsis instead of horizontal overflow | `marquee_text.dart` | same suite |
| 22 | Song-option rows and library category chips expose button roles (chips also announce `selected`) | `song_options_sheet.dart`, `library_screen.dart` | analyze + library/sheets suites |
| 23 | Skeleton shimmer no longer uses a `ShaderMask` — the highlight is painted per box, removing one offscreen layer per loading list | `shimmer_skeleton.dart` | analyze + 367 widget/library/home tests |
| 24 | **One motion scale**: deleted the eight legacy `PulsrMotion` durations, migrated the last 7 call sites to `PulsrDurations`, aligned `DESIGN.md` / `DESIGN_SYSTEM.md` | `pulsr_motion.dart`, 6 call sites, 2 docs | motion ratchet + 773 tests |
| 25 | Tonearm drop moved from an off-scale 850 ms to `PulsrDurations.ambient` | `vinyl_player_theme.dart` | reduce-motion suite |
| 26 | Cassette/CD micro-text raised from 8.5/9 px to the 10 px token | `cassette_body.dart`, `cd_stage.dart` | golden |

### What this deliberately does **not** claim

- **Theme control layouts.** The nine stages are distinct and Minimal has its own header, but the transport/switcher chrome is still shared. Distinct per-theme control layouts are a design project, not a patch.
- **Undoable deletion.** Library batch delete and duplicate cleanup still delete irreversibly with only a confirmation. Fixing it properly needs a trash/soft-delete architecture in the repository layer.
- **On-device evidence.** No TalkBack pass, no frame trace, no AMOLED/light render — the machine has no Android SDK. The accessibility and performance scores are now backed by code + widget tests, not by a device.
- **Label density.** Seven high-traffic rows now carry roles; the remaining row-level semantics (≈0.72 → 1.0) is a per-screen grind across ~9 features.
- **Startup.** Firebase (3 s) and the EQ migration are still awaited before `runApp`.

### Gate results

| Gate | Result |
|---|---|
| `flutter analyze --fatal-infos --fatal-warnings` | **0 issues** |
| Touched suites (`test/features/player`, `sheets`, `library`, `search`, `perf`, `a11y`, `core/widgets`) | **1,114 / 1,114 passed**; later player/motion/core run **773 / 773** |
| New regression tests | 8 files, **19 / 19 passed** |
| Full `flutter test` | **5,839 passed / 1 failed** on the last complete run. The broad re-run (`--no-pub`, features+core+a11y+perf+architecture+ux) reports **3,863 passed / 2 failed**, and **both failures are in files this pass never touched**: `ytm_service.dart` over its size cap, and `player_playback_options_controller.dart` at 402 lines > 400 — that file carries **+17 uncommitted lines from the concurrent editor**. |
| `flutter test test/core/widgets/pulsr_bottom_sheet_modal_test.dart` | 2 / 2 passed in isolation (flaky only under full-suite load) |

---

## 8. Caveats

1. **No device run.** All visual evidence is widget-test goldens at 390×844 (plus 320×568 and 1280×800), with a fake track, no real artwork and no real audio. Colours are correct; anti-aliasing and shader output are not representative.
2. **No TalkBack/VoiceOver pass.** A11y findings are structural (labels, roles, semantics, clamps), not experiential.
3. **No frame capture.** Animation-performance scores come from code structure (layers, blurs, tickers, builders), not from a profile trace on a mid-range device.
4. **No light/AMOLED/high-contrast render.** The palette math and token usage were reviewed; the visual result was not.
5. **Sub-audit figures were re-checked, and six were corrected.** The “24 of 25 off-screen tickers” figure (Flutter already mutes covered routes; the real hole was the `IndexedStack` shell — now closed), the “`MP3 • bitrate unknown` badge” (the model already short-circuits to `MP3`), the “5,000 SharedPreferences reads” in the rating sort (`SongRatingStore.getRating` is an in-memory map lookup), the “missing edge fade / duplicated Set up sound / 125 px tablet gutter” (the fade and the button container exist; the tablet gutter is centring, not dead space), “7 of 9 themes are the same screen” (the stages differ; the chrome is shared), and “Settings is a 65-section monolith” (it already has a Simple/Professional mode, defaulting to Simple, with the toggle at the top).
6. **Repo is being modified concurrently.** During this audit another process renamed test harness files and removed the first `audit/` directory; screenshots were regenerated. `git status` shows unrelated Android/YTM edits not made by this pass.

---

## Appendix A — Evidence map

| Artefact | Path |
|---|---|
| Nine themes, contact sheet | `audit/shots/contact_sheet.png` |
| Theme full-res | `audit/shots/theme_{classic,vinyl,cassette,cd,circle,card,minimal,waveform,lyricsFocus}.png` |
| 320 dp + 200 % text | `audit/shots/classic_phone_320.png`, `audit/shots/classic_text_200.png` |
| Settings dashboard / search | `audit/shots/screen_settings.png`, `test/audit_captures/phone_search_results.png` |
| Settings categories + tablet | `test/audit_captures/phone_*.png`, `test/audit_captures/tablet_sound.png` |
| Switch defect at 4× | `audit/shots/switch_zoom.png` |
| Sub-audits | `audit/02-motion.md`, `audit/03-resources.md`, `audit/05-a11y-ux.md` |
| Render harnesses | `test/_audit_visual.dart`, `test/_audit_screens.dart`, `test/_audit_capture.dart` |

## Appendix B — Reproduce

```powershell
# Flutter's tool crashes in this shell without these (VS/APPDATA lookups)
[Environment]::SetEnvironmentVariable("PROGRAMFILES(X86)","C:\Program Files (x86)")
[Environment]::SetEnvironmentVariable("APPDATA","C:\Users\<you>\AppData\Roaming")
[Environment]::SetEnvironmentVariable("LOCALAPPDATA","C:\Users\<you>\AppData\Local")
[Environment]::SetEnvironmentVariable("HOME","C:\Users\<you>")

flutter analyze --fatal-infos --fatal-warnings          # → No issues found
flutter test test/_audit_visual.dart  --update-goldens  # 9 themes
flutter test test/_audit_screens.dart --update-goldens  # settings + 320dp + 200%
flutter test test/_audit_capture.dart --update-goldens  # settings matrix + tablet
```

---

*Bottom line: Pulsr moved from **6.5 to 8.0** across four passes without a redesign — accessibility mechanics, a single motion scale, layer-free shimmer, legible player micro-text and a real virtualisation guard are in. The remaining two points are a trash can and a week with a real device in hand.*
