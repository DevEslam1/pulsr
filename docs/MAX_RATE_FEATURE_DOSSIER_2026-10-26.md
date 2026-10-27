# Pulsr — Maximum-Rate Feature Dossier

**Every feature scored where it stands today, the 10/10 engineering ceiling, and the full function set it could reach.**

- **Date:** 2026-10-26
- **Scope:** 37 user-facing and platform features across 7 domains
- **Baseline:** `gaps.md` (2026-10-02, evidence-cited) + the 2026-10-04 remediation table + fresh checks on the current working tree
- **Companion:** `docs/pulsr_max_rate_scorecard_2026-10-26.xlsx` (sortable scores, effort, wave)

> **Snapshot caveat.** At the 2026-10-26 baseline, the working tree had uncommitted edits and an untracked repro test: `flutter analyze --fatal-infos --fatal-warnings` reported **2 warnings** and the local `coverage/lcov.info` artifact reported **73.4%** hand-written line coverage against a **77.0%** CI floor. Those were the findings that seeded this dossier; the 2026-10-27 execution addendum below records the current, green state.

> **Execution status — 2026-10-27.** The first max-rate tranche is landed:
> - `flutter analyze --fatal-infos --fatal-warnings` → **0 issues** (scratch/ is now excluded as an experiment area).
> - **YTM Browse** replaced its ad-hoc `setState` with `YtmBrowseCubit` + immutable state + generation guard + stale-while-error banner; **7 new cubit tests**, feature suite **13/13 green**. Estimated feature score **5.4 → 6.7**.
> - **Downloads** suite **68/68 green** after 16 mocks were updated for the `title`/`artist` arguments on `resolveStream` (the production API was already correct).
> - **Router guard**, **RTL ratchet**, and **schema-audit** tests fixed (dead `?id=` push, one non-directional padding, stale schema version 11→12).
> - **Full suite: 5,589 passed / 18 skipped / 0 failed.** All 61 baseline failures are cleared. `flutter analyze --fatal-infos --fatal-warnings` and `dart format --set-exit-if-changed lib test` are green; the fat-file ratchet passes after extracting `YtmException` and the playlist suggestion card.
> - Also fixed: tablet-player 167px overflow at narrow widths (11 tests), mini-player goldens refreshed (4), audio-handler `resolveStream` mocks (7), YTM `/next` list-shape crash + embed fallback (3), generated real-audio fixture (1), and the player cold-start guard that swallowed an intentional queue clear (1).
> - **Radio** gained a live radio-browser.info search/add sheet with URL validation and 7 tests; estimated score **6.0 → 7.0**.
> - **Native audio:** DSD512 decodes natively to 768 kHz (host test: 38,400 frames / 0.05 s), and a new 2–8 channel `ChannelManager` (per-channel trim/delay, scratch-buffer RT-safe) passes its host suite. Native matrix: **13/14**; the legacy composite still fails a dither deviation assertion (>2 LSB), which needs a separate audit. UAC2 hardware volume remains pending a USB-DAC test rig — see `docs/NATIVE_AUDIO_MATRIX.md`.
> - Coverage: **77.66%** hand-written (73,168/94,220), above the **77.0%** floor. All gates are green: analyze 0, format 0, full suite 5,589 passed / 18 skipped / 0 failed. Not yet started: SQLCipher DB encryption, app lock, multichannel/DSD512, desktop/iOS DSP, 100k-track benchmark.
>
> **Domain C tranche — 2026-10-27 (this pass).** The Online & accounts surface moved on four fronts; downloads is unchanged.
> - **YTM search.** A bounded offline result cache (30 queries, 14-day TTL) serves the last good answer for a repeated query, with a neutral "saved results" strip. The cache is consulted after the live empty/error state is already painted, so a slow preferences read never holds the spinner. Search text/track round-trip and TTL/bounds/eviction are covered by new tests.
> - **YTM browse.** Failures now carry a reason (`offline`, `geoBlocked`, `botBlocked`, `unavailable`, `unknown`) that selects distinct copy; the app bar shows when the feed was fetched; each section has its own refresh with a local spinner and inline retry. A full reload still wins over a stale section response (generation-guarded).
> - **Auth.** `AuthFailure` gives every failure a kind and a recovery action (`editCredentials`, `resetPassword`, `useEmailSignIn`, `continueOffline`, `retry`). Firebase/Google init and every sign-in/sign-up/reset call are bounded at 30 s, so a hung provider cannot leave the sheet spinning. The legacy message mapping is retained for UI compatibility.
> - **Radio.** Every station mutation and the constructor's disk load are serialised through one mutex, closing the load-vs-add overwrite and lost-update races. The live directory now probes a stream with a ranged GET before adding it and refuses dead URLs with a localized message.
> - **Gates.** `flutter analyze --fatal-infos --fatal-warnings` → **0 issues**; `dart format --set-exit-if-changed lib test` → **0 changed**; full suite **5,626 passed / 18 skipped / 0 failed** (37 new tests).
> - **Estimated movement (not a re-audit).** YTM search 7.1 → ~7.5, YTM browse 6.7 → ~7.3, auth 6.4 → ~7.0, radio 7.0 → ~7.4; domain C mean **6.9 → ~7.3**. Downloads stays ~7.3.
>
> **YTM error hardening — 2026-10-27.** Four error families were audited end-to-end:
> - **Source errors.** The vendored just_audio bridge used to forward ExoPlayer's literal `Source error` and discard the underlying cause, so Dart could neither classify nor recover. It now forwards `Source error: <cause>`; the Dart classifier maps a source 401/403/404/410 to an expired link, a transport cause to `networkUnavailable`, and a bare source failure to an actionable retry message. URL-burn logic treats a bare source failure as burned (re-resolve) but a reset/timeout as a transport retry.
> - **Bad connections.** `bad connection`, `connection reset/closed/aborted`, `broken pipe`, `unexpected end of stream`, TLS handshake failures, DNS failures, `timed out` and the common `ECONNRESET`/`ETIMEDOUT` forms now collapse into one `networkUnavailable` verdict on both the Dart and Kotlin sides.
> - **+18 detection.** A new `AGE_RESTRICTED` signal (Dart and Kotlin) runs before bot and sign-in checks. Age-restricted tracks are now `isUnavailable` (so the alternate-version resolver still runs) but not `isAuth`, so the UI no longer claims the YouTube session expired. The copy is localized in English, Arabic and Spanish.
> - **Bot detection.** Removed the bare `robot` and `verification required` substrings that made track titles like "Robot Rock" and age walls look like bot challenges; bot detection now requires explicit interstitial wording (`not a bot`, `not a robot`, `unusual traffic`, `recaptcha`, `botguard`, `LOGIN_REQUIRED_BOT_CHECK`, …).
>
> **Bit-perfect verification tranche — 2026-10-27.** The output path now proves what it can prove and warns when it cannot.
> - A pure `assessBitPerfectChain` compares the source rate/depth with the format the output actually opened. The audio-quality sheet shows **verified**, **resampled**, **depth-truncated** or **armed-but-inactive** with the source and output numbers; DoP is treated as a carrier, not a resample. The static "not measured by this app" line is replaced with the live verdict.
> - When `USB DAC Hardware Volume` is enabled on a USB route, the software volume is forced to unity in Bit-Perfect mode so attenuation is not applied twice; otherwise the user volume remains explicit. DoP still wins at unity gain.
> - `HiResDacPlugin` now coalesces route callbacks for 200 ms before publishing a topology, so USB attach + A2DP connect bursts cannot briefly arm Bit-Perfect on the wrong sink.
> - The signal chain reports the ALSA/AAudio buffer estimate (`nativeFramesPerBuffer / nativeSampleRate`) next to the app-stream format; native underrun counts remain visible in the exclusive USB chip.
> - Estimated feature movement: Q 8.4 → ~8.6, F 8.0 → ~8.2, X 7.6 → ~8.1; composite **8.1 → ~8.4**. Hardware validation on a physical DAC is still required for the final 10/10 claim.

---

## 0. Verdict

**Current composite: 7.2 / 10.** Quality 7.2, function coverage 7.1, experience 7.1.

The centre of the app is genuinely strong: the native DSP engine (8.9), EQ and room correction (8.3), bit-perfect output (8.1), themes (8.3), and the design system (8.3) are closer to maximum than most commercial players. The drag is at the edges: desktop/web parity (4.7), radio (6.0), Party (6.1), cloud sync (6.1), onboarding (6.4), auth (6.4), accessibility/i18n (6.4), and — before the 2026-10-27 cubit — YouTube Music browse (5.4, now ~6.7). The app is **excellent at playing audio and uneven at being a complete product around it**.

A credible 10/10 is not one heroic sprint. It is seven workstreams over roughly 9–12 months for a 2–3 engineer team:

1. **Scale proof.** 100k tracks, sub-50 ms search, sub-1% jank, 100k-track scroll at 120 Hz. Today the architecture is sound but scale is asserted, not measured.
2. **Silent-failure elimination.** 427 empty `catch` blocks remain. Every one is a place where the app can lie to the user. This is the single largest quality multiplier.
3. **Privacy floor.** The library database is still plaintext (ADR-015 is *Proposed*, not implemented), and there is no app lock. A privacy-first player cannot ship either gap at 10/10.
4. **Edge parity.** YTM Browse, Party, Cloud Sync and Radio must meet the same standard as the player: cubit, typed errors, tests, accessibility, no swallowed exceptions.
5. **Audio moat, made undeniable.** Multichannel, DSD512, UAC2 hardware volume, a measurement-driven room-correction wizard, and an exportable bit-perfect certificate. The DSP is already the best part; make it the reason to choose Pulsr.
6. **Platform reach without lying.** Desktop needs a real exclusive-output path; iOS needs a CoreAudio port of the C++ engine. Web should be explicitly Tier 3, not a degraded clone.
7. **Product finish.** Settings search, onboarding to first sound in under 60 seconds, 10 languages, 100% labelled controls, and a home screen that loads in under 300 ms.

**What "maximum" means here.** Each feature is scored on three axes, each capped at 10:

| Axis | Question | Weight |
|---|---|---:|
| **Q — Quality** | Is it engineered to the 11-dimension 10/10 bar (architecture, bugs, state, errors, performance, memory, concurrency, hygiene, security, accessibility, CI)? | 50% |
| **F — Function** | How much of the category's credible maximum feature set is present? | 30% |
| **X — Experience** | Does it feel instant, legible, accessible, and polished in daily use? | 20% |

**Composite = 0.5 Q + 0.3 F + 0.2 X.** A 10/10 requires all three at 10. Where a platform makes 10 physically or legally impossible, the row states the hard cap and why.

---

## 1. Scoreboard

### 1.1 By domain

| Domain | Features | Q | F | X | Composite | Verdict |
|---|---:|---:|---:|---:|---:|---|
| **A. Playback & DSP** | 7 | 8.3 | 8.2 | 7.8 | **8.1** | The moat. Closest to maximum. |
| **B. Library & discovery** | 7 | 7.0 | 7.1 | 7.0 | **7.0** | Good bones; scale and polish missing. |
| **C. Online & accounts** | 5 | 6.9 | 7.0 | 6.7 | **6.9** | YTM browse lifted by the cubit; live radio directory added. |
| **D. Social & sync** | 5 | 6.8 | 6.2 | 6.6 | **6.6** | Infrastructure ahead of product. |
| **E. Personalization & care** | 6 | 7.2 | 7.1 | 7.3 | **7.2** | Strong identity; settings and onboarding lag. |
| **F. Platform & experience** | 4 | 6.5 | 6.1 | 6.5 | **6.4** | Android good, everywhere else thin. |
| **G. Foundation** | 3 | 7.9 | 7.5 | 7.5 | **7.7** | Strong CI, weak privacy floor. |
| **Whole app** | **37** | **7.2** | **7.1** | **7.1** | **7.2** | Excellent player, incomplete product. |

### 1.2 Every feature

| # | Feature | Q | F | X | Composite | Gap to 10 | Effort | Wave |
|---:|---|---:|---:|---:|---:|---:|---|---|
| 1 | Playback core | 7.6 | 8.6 | 7.4 | **7.9** | 2.1 | L | 1 |
| 2 | Native DSP engine | 9.2 | 8.8 | 8.2 | **8.9** | 1.1 | L | 2 |
| 3 | EQ & room correction | 8.5 | 8.3 | 8.0 | **8.3** | 1.7 | M | 2 |
| 4 | Bit-perfect output & DAC | 8.4 | 8.0 | 7.6 | **8.1** | 1.9 | L | 2 |
| 5 | Playback intelligence | 7.8 | 8.4 | 7.6 | **7.9** | 2.1 | M | 2 |
| 6 | Lyrics & karaoke | 8.0 | 7.6 | 7.6 | **7.8** | 2.2 | M | 2 |
| 7 | Themes & visualizers | 8.3 | 7.4 | 8.4 | **8.1** | 1.9 | M | 2 |
| 8 | Library core | 7.6 | 7.6 | 7.2 | **7.5** | 2.5 | L | 1 |
| 9 | Search | 7.4 | 7.0 | 7.4 | **7.3** | 2.7 | M | 1 |
| 10 | Playlists | 6.9 | 7.4 | 6.8 | **7.0** | 3.0 | M | 1 |
| 11 | Home & discovery | 6.7 | 6.6 | 7.0 | **6.7** | 3.3 | M | 1 |
| 12 | Detail screens | 6.9 | 7.0 | 7.0 | **7.0** | 3.0 | S | 1 |
| 13 | Tag editor | 6.6 | 7.2 | 6.4 | **6.7** | 3.3 | M | 1 |
| 14 | Duplicate finder & stats | 7.1 | 6.9 | 7.0 | **7.0** | 3.0 | M | 3 |
| 15 | YouTube Music search | 7.0 | 7.2 | 7.0 | **7.1** | 2.9 | M | 1 |
| 16 | YouTube Music browse | 7.0 | 6.5 | 6.2 | **6.7** | 3.3 | M | 0 |
| 17 | Downloads | 7.4 | 7.4 | 7.0 | **7.3** | 2.7 | M | 1 |
| 18 | Auth & account | 6.4 | 6.6 | 6.2 | **6.4** | 3.6 | M | 1 |
| 19 | Radio | 6.8 | 7.2 | 7.0 | **7.0** | 3.0 | M | 1 |
| 20 | Pulsr Party | 6.4 | 5.8 | 6.0 | **6.1** | 3.9 | L | 1 |
| 21 | Cloud sync & backup | 6.3 | 5.8 | 6.0 | **6.1** | 3.9 | L | 1 |
| 22 | Scrobbling & stats | 7.2 | 7.0 | 7.0 | **7.1** | 2.9 | S | 3 |
| 23 | Discord Rich Presence | 7.0 | 6.2 | 7.0 | **6.8** | 3.2 | S | 3 |
| 24 | Sharing & deep links | 6.9 | 6.4 | 7.0 | **6.8** | 3.2 | M | 2 |
| 25 | Theme system & design | 8.5 | 7.8 | 8.6 | **8.3** | 1.7 | M | 2 |
| 26 | Settings & profiles | 6.4 | 7.6 | 6.6 | **6.8** | 3.2 | M | 1 |
| 27 | Automation & device profiles | 6.7 | 6.8 | 6.8 | **6.8** | 3.2 | M | 3 |
| 28 | Smart audio & hearing safety | 8.0 | 7.8 | 7.6 | **7.9** | 2.1 | M | 2 |
| 29 | Quran mode | 7.0 | 6.4 | 7.0 | **6.8** | 3.2 | M | 3 |
| 30 | Onboarding | 6.4 | 6.0 | 7.0 | **6.4** | 3.6 | S | 1 |
| 31 | Android integration | 7.4 | 7.0 | 7.6 | **7.3** | 2.7 | M | 3 |
| 32 | Desktop & web parity | 4.8 | 4.2 | 5.2 | **4.7** | 4.3 (cap 9.0) | XL | 3 |
| 33 | Accessibility & i18n | 6.5 | 6.2 | 6.4 | **6.4** | 3.4 (cap 9.8) | L | 1 |
| 34 | App-wide performance | 7.4 | 7.0 | 6.8 | **7.2** | 2.8 | L | 1 |
| 35 | Security & privacy | 7.4 | 6.8 | 7.0 | **7.1** | 2.9 | L | 1 |
| 36 | Data layer & reliability | 7.5 | 7.4 | 7.4 | **7.5** | 2.5 | L | 1 |
| 37 | CI / DX / test | 8.8 | 8.2 | 8.0 | **8.5** | 1.5 | M | 0 |

**Reading the table.** Q and F are capped at 10; X is capped at 10. "Gap to 10" is `cap − composite`; rows 32–33 carry a hard cap below 10 (desktop/web sandbox, platform semantics), so their gap is cap-adjusted. Row 16 and domain C were updated on 2026-10-27 after the YTM Browse cubit; row 19 was updated after the live radio directory; row 37 and domain G were updated after the suite/coverage gates went green. All other rows are the 2026-10-26 baseline. Effort: **S** ≤ 1 week, **M** 2–6 weeks, **L** 2–4 months, **XL** 4+ months. Wave 0 is immediate hygiene, Wave 1 is scale and trust, Wave 2 is the audio moat, Wave 3 is reach.

---

## 2. Domain dossiers

### A. Playback & DSP — mean 8.1

The strongest domain. The C++ engine is not a marketing claim: 18 real-time stages, a lock-free parameter snapshot, an RTF governor, 19 host tests, and fuzzers for the parsers. The remaining distance is mostly product surface and platform reach, not DSP correctness.

---

#### 1. Playback core — **7.9 / 10**
`Q 7.6 · F 8.6 · X 7.4`

**Now.** Dual pipeline (Media3 + AAudio/USB), gapless, crossfade, A-B loop, sleep fade, silence skip, bookmarks, per-song volume/EQ, three queue slots with persistence, and Auto-DJ. The feature set is already near the category ceiling; the engineering is not.

**Max optimisation.**
- **Queue as a single-writer actor.** Every mutation (add, reorder, remove, slot swap) goes through one serialized command queue with an immutable version and an undo log. Today several read-modify-write paths still compute from a pre-`await` snapshot. Target: 0 lost updates across 10k randomized concurrent operations; property test it.
- **Frame-true position.** Derive position from frames rendered and the output clock, not wall time. Target: <10 ms seek error, <5 ms drift over one hour, no position jump on route change.
- **One transport state machine.** Local, YTM, radio and Party currently reach playback through different paths. Collapse them into one state machine with explicit states (`idle → resolving → buffering → playing → draining → completed → failed`). Kill duplicate timers and ad-hoc booleans.
- **Preload budget.** Next-track resolution <150 ms p95 on LTE; zero-gap on 100% of album transitions; preload cancelled cleanly on queue edit.

**Max function.**
- **[Parity]** Variable skip intervals (5/10/30/60 s), per-genre defaults, and a scrub-preview waveform on the seek bar.
- **[Parity]** Queue lanes: "Up next", "Play next", and history, with drag between lanes and a visible version history.
- **[Moat]** Perfect-transition automix 2.0: beat grid + key + energy curve, 0–12 s configurable, fully offline, with a "no-train-wreck" guard.
- **[Moat]** Listening sessions: resume exact queue + DSP chain + position on another device, via cloud sync.
- **[Experimental]** Assistant intents: "play my 90s playlist in the car", "skip the slow one".

**The 10/10 bar.** It never loses a queue edit, never gaps, its position is frame-true, and its transitions are musically planned rather than crossfaded by timer.

---

#### 2. Native DSP engine — **8.9 / 10**
`Q 9.2 · F 8.8 · X 8.2`

**Now.** 18 stages: EQ, crossfeed, reverb, panner, limiter, resampler, saturation, width, loudness, crossover, dynamic EQ, dither, multiband compressor, dynamic bass, ViPER DDC, arbitrary EQ, LiveProg, headphone safety. Lock-free snapshot handoff, retire pool, hazard pointer, RTF auto-degrade, `-O3` + thin LTO, and a native host suite.

**Max optimisation.**
- **Multi-rate graph.** Run the chain at the source rate and resample once at the output, not per stage. Target: one SRC per playback path, THD+N < −110 dB, passband ripple <0.1 dB.
- **SIMD biquads and convolution.** NEON intrinsics for the hot loops, scalar fallback verified bit-identical to within 1 LSB. Target: 2–4× headroom on mid-tier SoCs.
- **Cost model per stage.** Publish a measured CPU table (48 kHz/24-bit, 6 active stages) for three SoC classes; make the governor pick stages from measured cost, not a static mask. Target: <12% of one core on Snapdragon 7-series, zero xruns in a 24-hour soak.
- **Multichannel correctness.** The graph is stereo-centric: crossfeed, width, reverb, multiband and bass management assume channels 0/1, and there is no multichannel layout, per-channel trim or bass-management policy. Extend every stage to 4/6/8 channels with per-channel state, trims and delays; keep stereo paths allocation-free.

**Max function.**
- **[Parity]** 4/6/8-channel output with bass management, per-channel distance/level, and downmix presets.
- **[Moat]** DSD512 and PCM 768 kHz; native DSD over USB where the DAC exposes an alternate mode (DoP stays the safe default).
- **[Moat]** Linear-phase and minimum-phase modes; 32-band FIR per channel for room correction.
- **[Moat]** Head-tracked binaural (phone IMU + HRTF) for Bluetooth headphones.
- **[Experimental]** A user-facing DSP graph editor: series/parallel stages, per-stage meters, saveable as a preset.

**The 10/10 bar.** Reference-grade transparency, no clipping at any gain, no xruns at any supported rate, and any file can reach any DAC without an unexpected conversion.

---

#### 3. EQ & room correction — **8.4 / 10**
`Q 8.5 · F 8.6 · X 8.0`

**Now.** 10-band graphic, 64-band parametric (native `MAX_BANDS = 64`; the codebase docs claim 128), arbitrary-response EQ, 652 bundled AutoEq/target profiles (the docs claim 4,000+), ViPER DDC, convolution room correction, per-song EQ, and A/B comparison. Functionally this is best-in-class on Android.

**Max optimisation.**
- **One engine, three front-ends.** Graphic, parametric and arbitrary modes currently carry separate state and gain staging. Unify on one biquad/FIR graph with a single preamp calculation; make mode switching lossless.
- **Measured overlay.** A 1/3-octave RTA with peak-hold and target-curve overlay at 60 fps, computed off the UI isolate.
- **Import pipeline.** AutoEq from URL, squig.link, CSV and clipboard; dedupe by model + source; version and rollback. Target: <2 s from paste to audible.
- **Room wizard.** Guided sweep, 8 positions, target curve, IR export, A/B against bypass. Target: <5 minutes end-to-end, with a confidence score.

**Max function.**
- **[Parity]** Target-curve library: Harman, diffuse-field, flat, custom, and per-genre.
- **[Moat]** Hearing-profile EQ from an audiogram or a 6-tone self-test, applied with automatic headroom.
- **[Moat]** Per-output-device + per-headphone profiles with hotplug recall (the device profile service already exists; finish the UX).
- **[Moat]** Dynamic EQ tied to measured loudness, not volume-step approximation.
- **[Experimental]** Shareable tuning packs with clipping and hearing-safety validation.

**The 10/10 bar.** Measure, correct, verify — without clipping, guessing, or a spreadsheet.

---

#### 4. Bit-perfect output & DAC — **8.1 / 10**
`Q 8.4 · F 8.0 · X 7.6`

**Now.** AAudio low-latency sink, USB UAC2 exclusive mode, DoP, float output, chain-of-custody reporting, sample-rate negotiation, USB diagnostics, and a HiRes DAC plugin.

**Max optimisation.**
- **Sample-rate follow.** In exclusive mode, reopen the stream per track when the rate changes; show source vs actual rate/depth continuously. Target: zero silent resamples, and a visible warning when the OS forces one.
- **Hardware volume.** UAC2 volume/mute where supported; bypass software attenuation in bit-perfect mode. Target: no digital attenuation below 0 dBFS unless the user asks.
- **Hotplug state machine.** 200 ms debounce, per-device DSP recall, safe fallback that never routes to the speaker by accident. Test unplug/replug 1,000 times.
- **Latency proof.** Expose measured output latency and xrun count; use AAudio MMAP where available. Target: <10 ms on supported devices, <25 ms otherwise.

**Max function.**
- **[Parity]** DSD512 / PCM 768 kHz; native DSD alternate mode with automatic DoP fallback.
- **[Parity]** Bluetooth codec control and a quality badge (LDAC 990, aptX Adaptive, AAC), with a "why is it transcoding?" explainer.
- **[Moat]** A bit-perfect test-track suite and an exportable chain-of-custody certificate (PDF/JSON) per album.
- **[Moat]** Multichannel USB with bass management and per-channel trims.
- **[Experimental]** A DAC compatibility database with quirks, firmware notes, and community reports.

**The 10/10 bar.** Whatever the file, the DAC receives exactly it — and the app can prove it on that device, at that moment.

---

#### 5. Playback intelligence — **7.9 / 10**
`Q 7.8 · F 8.4 · X 7.6`

**Now.** Crossfade, gapless trim, silence skip, ReplayGain, sleep fade, speed/pitch, BPM/key automix, adaptive buffer, battery-aware playback, and SponsorBlock segment skipping for online tracks.

**Max optimisation.**
- **Loudness.** EBU R128 with true-peak limiting, album and track modes, isolate-based fallback analysis. Target: <2 s per track, <0.5 LU error against reference.
- **Crossfade.** Equal-power, phase-safe, configurable curve; no click at the boundary. Test 10k transitions across formats and rates.
- **Automix confidence.** Beat-grid confidence >0.9 and key accuracy >85% on a 500-track test set; refuse to automix when confidence is low rather than guess.
- **Silence detection.** <20 ms decision, no false positives on quiet intros or ambient tracks.

**Max function.**
- **[Parity]** Loudness targets per context (local −18 LUFS, streaming −14 LUFS) and a "late-night" dynamics mode.
- **[Moat]** Auto-DJ 2.0 with an energy arc and party-aware pacing.
- **[Moat]** "Radio from track": harmonic mixing within a tempo range, seeded by the current track.
- **[Experimental]** Mood/energy shuffle learned from skip behavior, on-device only.

**The 10/10 bar.** Transitions and loudness are invisible. Nothing jars, ever, on any output.

---

#### 6. Lyrics & karaoke — **7.8 / 10**
`Q 8.0 · F 7.6 · X 7.6`

**Now.** LRC parser, LRCLIB client, millisecond offset editor, translations, karaoke screen with YIN pitch detection, lyric cards, and a Mushaf-style view for Quran.

**Max optimisation.**
- **Parser hardening.** Multi-timestamp lines, enhanced LRC word tags, malformed input, BOM/encoding variants. Fuzz 10k documents; never throw.
- **Sync accuracy.** Offset per track persisted; drift corrected against the frame clock. Target: ±20 ms against a reference master.
- **Rendering budget.** Active-line animation at 60/120 fps with pre-laid-out text; no layout thrash when lines change.
- **Pitch latency.** <30 ms from mic to note display, with a noise gate and calibration screen.

**Max function.**
- **[Parity]** Word-by-word timing (enhanced LRC + forced alignment) and tap-to-seek per word.
- **[Parity]** Offline lyric packs and a community cache with attribution.
- **[Moat]** Duet mode, pitch scoring, and a record/share path with the instrumental mix.
- **[Moat]** Translation auto-detect with a dual-language layout and per-language typography.
- **[Experimental]** Studio mode: record a cover, apply DSP, export video with synced lyrics.

**The 10/10 bar.** Lyrics feel native to the recording — at the word, in any language, with no visible lag.

---

#### 7. Themes & visualizers — **8.1 / 10**
`Q 8.3 · F 7.4 · X 8.4`

**Now.** Nine skeuomorphic Now Playing themes (vinyl, cassette, CD, circle, classic, minimal, card, waveform, lyrics), a theme studio, dynamic color, OLED black, a Milkdrop fragment shader, a GPU budget, and Canvas motion artwork (Apple Music / TIDAL / community) in the backdrop.

**Max optimisation.**
- **One theme contract.** A layout spec + design tokens; no per-theme logic duplication. Golden tests for 9 themes × 3 sizes × light/dark.
- **Shader discipline.** Warmup/compile cache, 120 Hz cap, graceful fallback, <8 ms GPU per frame on mid-tier. Zero dropped frames in a 10-minute soak.
- **Motion parity.** Every theme has a reduce-motion variant; no theme depends on animation to be usable.

**Max function.**
- **[Parity]** Theme import/export (validated JSON) and a community gallery.
- **[Parity]** More visualizer presets: spectrum, oscilloscope, particles, album-tinted flow.
- **[Moat]** Milkdrop `.milk` preset compatibility layer.
- **[Moat]** Per-track / per-genre visualizer rules.
- **[Moat]** Canvas provider expansion with a legal, cached, offline-first fallback.
- **[Experimental]** Seasonal and time-of-day themes that change without a restart.

**The 10/10 bar.** The player looks like a piece of hardware worth buying, and it never drops a frame doing it.

---

### B. Library & discovery — mean 7.0

The library is competent and reactive, but it has not been proven at scale. The difference between 7 and 10 here is not new screens; it is 100k tracks, sub-50 ms queries, and a library that heals itself.

---

#### 8. Library core — **7.5 / 10**
`Q 7.6 · F 7.6 · X 7.2`

**Now.** MediaStore + filesystem scanner, metadata enrichment, six tabs, folder tree, exclusions, reactive Drift streams, and per-song favorite mutexes. The 2026-10 remediation fixed the destructive delete path.

**Max optimisation.**
- **Incremental scan.** mtime/size index, resumable, cancelable. Target: 50k tracks cold <60 s, warm <6 s, battery <2% per 10-minute scan.
- **Virtualize everything.** No full-list copies in memory; 100k-track scroll at 120 Hz; section indices built in SQL.
- **Query budgets.** Album/artist/genre counts in SQL, not Dart. p95 <30 ms for every library screen on 100k tracks, proven by a benchmark test.
- **Scanner isolation.** Scan, tag enrichment and artwork extraction on background isolates with backpressure; the UI isolate never parses a file.

**Max function.**
- **[Parity]** Multi-library: internal storage, SD card, SMB/WebDAV, with a unified index and per-source policies.
- **[Parity]** MusicBrainz/AcoustID enrichment and fingerprint-based dedupe.
- **[Moat]** Smart collections (rule-based, auto-updating) and saved views.
- **[Moat]** A library health dashboard: missing art, bad tags, duplicates, corrupt files, dead queue entries.
- **[Experimental]** Watch folders on desktop/NAS with near-real-time indexing.

**The 10/10 bar.** 100k tracks feel like 100, and the library repairs itself without a wizard.

---

#### 9. Search — **7.3 / 10**
`Q 7.4 · F 7.0 · X 7.4`

**Now.** Local fuzzy search + YTM search, 300 ms debounce, generation guard, LRU normalization cache, capped results, saved searches.

**Max optimisation.**
- **Indexed search.** SQLite FTS5 trigram index + top-k Levenshtein; no full scan on the UI isolate. Target: p95 <50 ms at 100k tracks, <10 ms for prefix hits.
- **One query pipeline.** Current fuzzy filtering runs twice with a re-sort in some paths. Collapse to a single scored pass with deterministic tie-breaks.
- **Search everything.** Lyrics, tags, folders, playlists, queue, downloads, and settings — grouped, keyboard-navigable, with recent queries.
- **Incremental index.** Update on scan/tag edit without a rebuild; verify with a 10k-edit soak.

**Max function.**
- **[Parity]** Semantic search ("rainy Sunday jazz") via a <30 MB on-device embedding model.
- **[Parity]** Voice search and assistant intents.
- **[Moat]** Natural-language filters: "FLAC over 24-bit before 2005", "duets I haven't played in a year".
- **[Moat]** "More like this" from audio features (tempo, key, energy, timbre).
- **[Experimental]** Visual search: photograph a cover and jump to the album.

**The 10/10 bar.** Type three letters, get the song before the keyboard settles — even with 100k tracks.

---

#### 10. Playlists — **7.0 / 10**
`Q 6.9 · F 7.4 · X 6.8`

**Now.** Local, smart and online playlists; Spotify import; JSON share; suggestions; cached covers; bounded save queue.

**Max optimisation.**
- **Atomic apply.** Diff + transaction + rollback for manage/reorder/remove. Target: no partial saves, even on process death mid-write.
- **One model.** Local, online and smart playlists share one domain model and one editor; no dual source of truth in a `ValueNotifier`.
- **Virtualized grids.** Remove nested `shrinkWrap` grids; 60 fps at 500 playlists and 10k entries.
- **Undo stack.** 20 steps, persisted per session, covering delete/remove/reorder/rename.

**Max function.**
- **[Parity]** Folder nesting and multi-select drag between playlists.
- **[Parity]** Import/export M3U, CSV, and platform links where legally permitted.
- **[Moat]** Collaborative playlists: Party members can add, with host approval.
- **[Moat]** Version history and one-tap restore.
- **[Experimental]** AI playlist generator constrained by mood, energy, tempo and explicit-content rules.

**The 10/10 bar.** Playlists are as reliable as the filesystem and as flexible as a spreadsheet.

---

#### 11. Home & discovery — **6.7 / 10**
`Q 6.7 · F 6.6 · X 7.0`

**Now.** Hero mix, recently played, recently added, category carousels, online recommendations, scan/permission flow.

**Max optimisation.**
- **Immutable HomeCubit.** Hand-rolled state without `==` causes rebuild storms; move to Freezed with selectors and `buildWhen`.
- **Cache correctness.** Fix the prune-before-insert eviction bug; add TTL + explicit invalidation on scan/tag change.
- **Skeleton-first.** First paint <300 ms, meaningful content <800 ms, even on a cold start with 100k tracks.
- **Recovery.** Permission and scan failures become actionable cards, not swallowed exceptions.

**Max function.**
- **[Parity]** Time-of-day/mood mixes, "on this day", and rediscovery rows.
- **[Parity]** Cross-device "continue listening".
- **[Moat]** A weekly/monthly recap ("Pulsr Wrapped") with share cards.
- **[Moat]** Smart downloads for the commute, pre-cached before you leave.
- **[Experimental]** Generative mix covers from the tracks' own palettes.

**The 10/10 bar.** The home screen knows what you want before you do — and loads before you blink.

---

#### 12. Detail screens — **7.0 / 10**
`Q 6.9 · F 7.0 · X 7.0`

**Now.** Album, artist, genre, year and folder detail; sort persistence; multi-select; queue operations; error views with retry.

**Max optimisation.**
- **Streams created once.** Several screens recreate Drift streams inside `build`, causing a DB re-query on every selection or sort. Memoize and dispose correctly.
- **One scaffold.** A shared detail scaffold + selection/sort/queue controller; delete the duplicated `StatefulWidget` logic.
- **Virtualized lists.** Sticky headers, 120 Hz scrolling, no eager child lists.
- **State coverage.** Loading, empty, error and partial states for every section, with retry and offline explanations.

**Max function.**
- **[Parity]** Credits, release versions, similar artists, and discography grouping.
- **[Parity]** Genre hierarchy and a year timeline.
- **[Moat]** Album completeness: missing tracks, alternate editions, and "complete this album" downloads.
- **[Moat]** Breadcrumb history and "go to artist/album" from anywhere.
- **[Experimental]** Liner notes and an artwork gallery with pinch-zoom.

**The 10/10 bar.** Every detail page is a doorway, not a dead end.

---

#### 13. Tag editor — **6.7 / 10**
`Q 6.6 · F 7.2 · X 6.4`

**Now.** ID3 editing, batch edits, artwork replacement, online auto-fetch, a 15-step undo history, and native jaudiotagger writes.

**Max optimisation.**
- **Field state correctness.** `TextEditingController`s keyed by field, not `initialValue`; the 2026-10 audit found undo/auto-fill could fail to update the visible text. Verify and regression-test all field types.
- **Undo 100 steps.** Coalesce by field, persist per session, and make undo survive a screen rebuild.
- **Batch as a resumable transaction.** Per-file checkpoint, partial-failure report, and resume from the last good file.
- **Write abstraction.** A `TagWriter` interface with a format matrix (FLAC/MP3/M4A/OGG/WAV/DSF) and golden files for each.

**Max function.**
- **[Parity]** Tag-from-filename templates and batch rename.
- **[Parity]** Multi-value tags, sort tags, and ReplayGain write-back.
- **[Moat]** Fingerprint lookup + MusicBrainz matching with confidence.
- **[Moat]** Artwork crop/compress and palette extraction.
- **[Experimental]** Duplicate-aware merge that preserves play counts and playlist membership.

**The 10/10 bar.** Metadata is a joy to fix, and undo always works — even after a batch of 500 files.

---

#### 14. Duplicate finder & stats — **7.0 / 10**
`Q 7.1 · F 6.9 · X 7.0`

**Now.** Duration/title/album matching, batch cleanup, library statistics, and format breakdown.

**Max optimisation.**
- **Acoustic fingerprinting.** Chromaprint-based matching with a local cache; <1 s per track, resumable. This turns "same title" into "same recording".
- **Keep-best policy.** Rank by bit depth, sample rate, bitrate, DR and tag completeness; preview storage saved before deleting.
- **SQL + isolate stats.** No full-list sorts on the UI isolate; <200 ms for 100k tracks.

**Max function.**
- **[Parity]** Merge duplicates (tags, art, play counts, playlist references) rather than only delete.
- **[Parity]** Storage treemap by artist/album/format.
- **[Moat]** Listening recap with share cards and yearly trends.
- **[Moat]** Library health score with one-tap fixes.
- **[Experimental]** Predict missing album tracks and offer to complete them.

**The 10/10 bar.** One press, and the library is clean — without losing a play.

---

### C. Online & accounts — mean 6.4

This was the weakest domain. The 2026-10-27 tranche added an offline search cache, typed browse failures with per-section retry, a typed auth failure taxonomy with bounded operations, and serialised radio writes with a stream health probe. Downloads remains serviceable but unchanged.

---

#### 15. YouTube Music search — **7.1 / 10**
`Q 7.0 · F 7.2 · X 7.0`

**Now.** InnerTube catalog search, stream pre-resolution, chunked download, rate limiting, circuit breaker, proxy pool, DoH resolver, cellular failover, OAuth/WebView login, and geo-block recovery.

**Max optimisation.**
- **Typed failures.** Replace string classification with `AppError` variants (`YtmGeoBlocked`, `YtmRateLimited`, `YtmBotCheck`, `YtmUnavailable`) and user-actionable recovery.
- **Cache discipline.** Search + stream URL TTLs, negative caching, and a single-flight resolver per video ID. p95 <400 ms on a warm cache.
- **Hedged resolution.** Pre-resolve the next two tracks; cancel speculation on queue change; never block play.
- **Quality transparency.** Show codec, bitrate and source before playback; warn when a "lossless" request will transcode.

**Max function.**
- **[Parity]** Filters (duration, upload type, quality) and artist radio.
- **[Parity]** One-tap album/playlist queueing and related tracks.
- **[Moat]** Offline search cache with downloads-first ranking.
- **[Moat]** Import a playlist/album by URL, with duplicate detection against the local library.
- **[Experimental]** "Find this local song online" matching for missing tracks.

**The 10/10 bar.** Online feels local: instant, predictable, and never a dead end.

---

#### 16. YouTube Music browse — **6.7 / 10**
`Q 7.0 · F 6.5 · X 6.2`

**Now.** The 2026-10-27 tranche replaced the 349-line `StatefulWidget` with `YtmBrowseCubit` + immutable state + a generation guard. The service already fetches the three feeds concurrently, filters empty sections, completes in-flight awaiters on `clearCache`, and degrades per section; the screen now shows a stale-while-error banner instead of throwing the feed away. **13/13 feature tests green.**

**Max optimisation.**
- **Screen depth.** Pagination/load-more, section-level retry, and a cold-cache first paint <400 ms.
- **Typed errors.** Map `YtmErrorClassifier` signals to distinct UI copy (offline, geo, bot) instead of one generic failure.
- **Test matrix.** Widget tests for cache-hit and empty-section combinations; a golden test for card density at phone/tablet widths.
- **Cache UX.** Show last-updated time and allow a per-section force refresh.

**Max function.**
- **[Parity]** Charts by country, new releases, moods/genres, and personalized rows.
- **[Parity]** Editorial collections and "because you listened to…".
- **[Moat]** Wi-Fi prefetch of the next browse page.
- **[Moat]** Daily mixes generated from local + online history.
- **[Experimental]** A "crate digging" mode that surfaces deep cuts by label/year.

**The 10/10 bar.** A browse tab worth visiting on its own, not a demo of the API.

---

#### 17. Downloads — **7.3 / 10**
`Q 7.4 · F 7.4 · X 7.0`

**Now.** Chunked, resumable downloads; progress; pause/resume; storage stats; notifications; tombstone-based queue; throttled UI updates.

**Max optimisation.**
- **Selection integrity.** Prune `_selectedVideoIds` when tasks disappear or filters change; deletion must never target the wrong row.
- **Verification.** Size + hash check, automatic retry with backoff, and a "repair" action for truncated files.
- **Storage guard.** Quota, low-space preflight, and a clear "what will this cost" estimate before queueing.
- **Scheduling.** WorkManager with Wi-Fi/charging constraints; pause on metered networks unless overridden.

**Max function.**
- **[Parity]** Scheduled/auto-download of new releases from followed artists.
- **[Parity]** Export/import the download library; SD-card migration.
- **[Moat]** Smart downloads for commute/liked/party, pre-cached on Wi-Fi.
- **[Moat]** Per-item priority and queue reordering.
- **[Experimental]** Download from a shared playlist link, deduped against local files.

**The 10/10 bar.** Downloads finish, resume, verify themselves, and never surprise you.

---

#### 18. Auth & account — **6.4 / 10**
`Q 6.4 · F 6.6 · X 6.2`

**Now.** Firebase Auth + Google Sign-In + YTM WebView login; secure cookies; session sync; recovery UI. The WebView allowlist is now exact-domain, which closes the 2026 audit's phishing gap.

**Max optimisation.**
- **Error taxonomy.** `AuthService` still throws raw `Exception` in places; map every failure to an actionable `AppError` with a recovery path.
- **Token refresh.** Single-flight refresh, offline-first account state, no spinner that never ends.
- **Multi-account state machine.** Explicit states for "signed out", "local only", "YTM session expired", "Firebase offline".
- **Privacy.** No tokens in logs; cookie encryption at rest; clear "what is stored where" copy.

**Max function.**
- **[Parity]** Account switcher and "continue offline" without re-auth.
- **[Parity]** In-place re-auth banner instead of a blocking modal.
- **[Moat]** Passkeys for the Pulsr account.
- **[Moat]** Device/session management with revoke.
- **[Experimental]** Family/child profiles with separate libraries and limits.

**The 10/10 bar.** Sign-in is invisible, recoverable, and never costs you your library.

---

#### 19. Radio — **7.0 / 10**
`Q 6.8 · F 7.2 · X 7.0`

**Now.** Curated station store, add/import URL, genre filter, player integration, SSRF validation (rejects loopback/private/link-local/CGNAT), and a live radio-browser.info search/add sheet with name/country/tag queries, URL validation and dedupe (**7 tests**).

**Max optimisation.**
- **Facets + health.** Surface country/language/genre chips, hide broken stations by default, and health-check before adding.
- **Metadata.** ICY now-playing polling, artwork fallback, and a "track ID" action.
- **Buffer policy.** Fast start (<2 s), adaptive rebuffer, and a visible "unstable stream" state.
- **Store concurrency.** The process-static station list still needs a single-writer/mutex discipline; eliminate `ready.then` overwrite races.

**Max function.**
- **[Parity]** Favorites sync and recents across devices.
- **[Parity]** Sleep timer and car mode with large targets.
- **[Moat]** Recording + track identification + "listen later".
- **[Moat]** Recommendations by genre/country and listening history.
- **[Experimental]** Community station packs with moderation.

**The 10/10 bar.** Radio is a first-class source, not a URL list with a play button.

---

### D. Social & sync — mean 6.6

The infrastructure here is better than the product. The Go Party server has clock sync, hubs, presence and load tests; the client is a 601-line sheet. Cloud sync exists but lacks conflict UX. This domain has the largest "product gap per line of code" in the app.

---

#### 20. Pulsr Party — **6.1 / 10**
`Q 6.4 · F 5.8 · X 6.0`

**Now.** Go server with rooms, codes, WebSocket protocol, NTP-style clock sync, host/democratic queue, presence, and a load-test harness. Client: join/host sheet and sync status.

**Max optimisation.**
- **Client state machine.** Explicit `idle → connecting → synced → degraded → reconnecting → closed`; exponential backoff; <1 s recovery after a tunnel.
- **Drift compensation.** Apply clock offset on every sync and on seek; target p95 skew <40 ms across 10 devices on mixed networks.
- **Queue versioning.** Server-issued version + client optimistic updates + rollback; no lost edits when two members add simultaneously.
- **Load proof.** 100 rooms × 10 members, p95 broadcast <100 ms, no goroutine leaks after 1k join/leave cycles.

**Max function.**
- **[Parity]** QR/deep-link join and optional room password.
- **[Parity]** Chat/reactions and a synchronized "everyone play" countdown.
- **[Moat]** Host migration and an offline LAN relay mode.
- **[Moat]** Per-member volume/headphone profiles so everyone hears their own correction.
- **[Experimental]** Cross-network TURN + end-to-end encrypted room metadata.

**The 10/10 bar.** Ten phones, one song, no drift, no dropped edits, and a join that takes one scan.

---

#### 21. Cloud sync & backup — **6.1 / 10**
`Q 6.3 · F 5.8 · X 6.0`

**Now.** Firebase-backed backup/sync of playlists, favorites and settings; a dashboard for export/import.

**Max optimisation.**
- **Incremental sync.** Vector clocks or per-collection revisions; explicit conflict resolution UI (keep local / keep remote / merge).
- **Encrypted backups.** Client-side key (XChaCha20/age), restore preview, and schema-versioned payloads.
- **Failure discipline.** No data loss on logout; background retry; visible last-synced timestamp.
- **Scale.** 100k-track library metadata sync <30 s on Wi-Fi; delta payload <500 KB for a typical edit.

**Max function.**
- **[Parity]** Scheduled backups and multi-provider support (Drive, WebDAV, local NAS).
- **[Parity]** Cross-device queue/position handoff.
- **[Moat]** Selective sync (playlists and settings only, no history).
- **[Moat]** 30-day version history with restore.
- **[Experimental]** End-to-end encrypted device-to-device sync without a server.

**The 10/10 bar.** Your library follows you, and you can always roll back.

---

#### 22. Scrobbling & stats — **7.1 / 10**
`Q 7.2 · F 7.0 · X 7.0`

**Now.** Last.fm and ListenBrainz auth, scrobble queue, now-playing, and a stats screen.

**Max optimisation.**
- **Offline queue.** Durable, deduped, exponential retry; target 100% delivery after a week offline.
- **Two-way sync.** Loved/favorite state both ways, with conflict rules.
- **Edit/delete.** Fix a bad scrobble; batch import history with progress.
- **Privacy.** Per-service toggles, scrub private tracks, and a clear "what leaves the device" view.

**Max function.**
- **[Parity]** Stats v2: streaks, genres, decades, artist discovery timeline.
- **[Parity]** Import from Spotify/Last.fm with dedupe.
- **[Moat]** Recommendations from the scrobble graph, on-device where possible.
- **[Moat]** Shared listening stats with friends (opt-in).
- **[Experimental]** An open export format for your full listening history.

**The 10/10 bar.** Your listening history is complete, portable, and private.

---

#### 23. Discord Rich Presence — **6.8 / 10**
`Q 7.0 · F 6.2 · X 7.0`

**Now.** Presence toggle, track/artist/album, elapsed time, reconnect handling.

**Max optimisation.**
- **Resilience.** No crash or log spam when Discord is absent; backoff and a clear disabled state.
- **Privacy.** Hide private/explicit tracks; idle and paused states; per-server profiles.
- **Assets.** Album art caching with fallbacks and no rate-limit bursts.

**Max function.**
- **[Parity]** Buttons ("listen along", "open Pulsr").
- **[Parity]** Progress bar and pause state.
- **[Moat]** "Listening party" invite link that opens the Party join flow.
- **[Moat]** Per-server privacy profiles.
- **[Experimental]** Host-mode presence showing the party queue.

**The 10/10 bar.** Presence is accurate, private, and one tap from joining in.

---

#### 24. Sharing & deep links — **6.8 / 10**
`Q 6.9 · F 6.4 · X 7.0`

**Now.** Playlist JSON share, lyric cards, song share, Spotify import, and safe temp-file handling.

**Max optimisation.**
- **Deep links.** Signed links with a web fallback that previews the playlist; no dead links when the app is absent.
- **Export quality.** Three card sizes, contrast-checked text, alt text, and no clipped artwork.
- **Latency and cleanup.** Share sheet <300 ms; temp files cleaned on failure and on next launch.

**Max function.**
- **[Parity]** QR codes for playlists and Party rooms.
- **[Parity]** Story-format cards with theme selection.
- **[Moat]** Smart links with a web preview and "open in Pulsr".
- **[Moat]** Collaborative import: several people add to one playlist.
- **[Experimental]** An embeddable web player for shared playlists.

**The 10/10 bar.** Sharing makes the recipient want the app — and the link always works.

---

### E. Personalization & care — mean 7.2

This is Pulsr's identity domain: themes, hearing safety, Quran mode, automation. It is strong where it is distinctive and weak where it is infrastructural (settings, onboarding).

---

#### 25. Theme system & design — **8.3 / 10**
`Q 8.5 · F 7.8 · X 8.6`

**Now.** Nine player themes, a theme studio, dynamic color, OLED black, theme scheduling, responsive layouts, Manrope typography, and a documented design system.

**Max optimisation.**
- **Token-only theming.** No hardcoded colors outside tokens; automated contrast tests for all 9 themes in light/dark.
- **Golden coverage.** 9 themes × 3 sizes × 2 brightness modes; block visual regressions in CI.
- **Motion budget.** Every animation has a reduce-motion variant and a measured frame cost.

**Max function.**
- **[Parity]** Theme import/export and a curated gallery.
- **[Parity]** Full light-mode parity for every theme.
- **[Moat]** Per-screen accent rules and album-art adaptive palettes.
- **[Moat]** Custom fonts and density settings.
- **[Experimental]** Seasonal/live themes driven by time, weather or listening context.

**The 10/10 bar.** Every theme looks intentional at every size, and you can make your own without breaking it.

---

#### 26. Settings & profiles — **6.8 / 10**
`Q 6.4 · F 7.6 · X 6.6`

**Now.** 57 settings files and 65+ sections covering audio, DSP, output, gain, appearance, scrobbling, Discord, cloud backup, proxy, automation, device profiles and more. Functionally enormous; structurally a god-cubit with incomplete dirty-field reconciliation.

**Max optimisation.**
- **Settings search.** Index every tile, deep-link to it, and highlight the match. This is the single highest-value settings improvement.
- **Split the god-cubit.** Per-domain controllers (audio, appearance, network, privacy) with a shared persistence layer; no 1,376-line cubit.
- **Dirty-field correctness.** Track every field or derive state from prefs; no silent revert during an in-flight reload.
- **Dependency-aware UI.** Hide irrelevant toggles, explain consequences, and offer "reset this section".

**Max function.**
- **[Parity]** "Recommended for this device" preset (DAC, headphones, SoC).
- **[Parity]** Change history with undo.
- **[Moat]** Expert mode exposing raw DSP values and telemetry.
- **[Moat]** Per-profile settings (car, home, headphones, party).
- **[Experimental]** Shareable "tuning packs" with validation.

**The 10/10 bar.** You can find any switch in five seconds and understand exactly what it does.

---

#### 27. Automation & device profiles — **6.8 / 10**
`Q 6.7 · F 6.8 · X 6.8`

**Now.** Triggers for headphone connect, time of day and charging; playback rules; per-device EQ/volume profiles.

**Max optimisation.**
- **Rule engine.** Priority, conflict detection, dry-run preview, and an audit log of what fired.
- **Reliable triggers.** Broadcast receivers for BT/USB/headset, optional geofence, and battery-safe scheduling.
- **Device recall.** Hotplug profile application in <300 ms with a visible "applied" confirmation.

**Max function.**
- **[Parity]** Visual rule builder with AND/OR conditions.
- **[Parity]** More triggers: specific BT device, app launch, location, battery level, wired headset.
- **[Moat]** Per-device auto EQ/volume/codec rules.
- **[Moat]** Car mode automation (large UI, screen-on, auto-play).
- **[Experimental]** Natural-language rules: "when I plug in my HD 600s, use the warm preset".

**The 10/10 bar.** The app adapts to your life without you opening settings.

---

#### 28. Smart audio & hearing safety — **7.9 / 10**
`Q 8.0 · F 7.8 · X 7.6`

**Now.** AutoEq headphone matching, Bluetooth latency calibration, WHO-style sound-dose tracking, headphone safety limiting, and earbud optimization.

**Max optimisation.**
- **Matching confidence.** Model/alias matching with a confidence score and manual override; never silently apply the wrong correction.
- **Dose accuracy.** Calibrate per output/headphone; show real-time dB and a weekly report; make the limiter transparent.
- **Hearing test.** A 6-tone self-test with a safe level ceiling, stored as a profile and applied with automatic headroom.
- **Safety UX.** Lock-screen/widget dose meter; child/age profiles; a clear "this will be loud" warning.

**Max function.**
- **[Parity]** Audiogram import (manual or photo) and age-based profiles.
- **[Parity]** Real-time dose meter on lock screen and widget.
- **[Moat]** Personalized loudness contour from the hearing profile.
- **[Moat]** Automatic ducking in loud environments using the mic (opt-in).
- **[Experimental]** A "hearing age" estimate with a trend over months.

**The 10/10 bar.** The app protects your ears better than you do, without nagging.

---

#### 29. Quran mode — **6.8 / 10**
`Q 7.0 · F 6.4 · X 7.0`

**Now.** Mode toggle, reciter styles, per-style tuning, persistence (fixed in the 2026-10 remediation), restore snapshot, Mushaf view, surah selector, bookmarks, and a dedicated screen.

**Max optimisation.**
- **State restore.** Prove on/off/restart/force-kill with a widget test matrix; ensure the pre-Quran snapshot always restores the *music* profile, not the Quran one.
- **Headroom.** Apply the stored `preampDb` so boosted bands cannot clip.
- **Timing.** Ayah tracking accuracy against real recitations; background/lock-screen behavior.
- **RTL/a11y.** Full Arabic typography, TalkBack labels, and dynamic type.

**Max function.**
- **[Parity]** Word-by-word text + translation audio.
- **[Parity]** Memorization loop: repeat range, hide text, reveal on tap.
- **[Moat]** Reciter library + offline packs.
- **[Moat]** Prayer times and Qibla.
- **[Experimental]** Teacher mode with recitation scoring.

**The 10/10 bar.** A complete, respectful Quran companion — not a skin over the music player.

---

#### 30. Onboarding — **6.4 / 10**
`Q 6.4 · F 6.0 · X 7.0`

**Now.** Multi-step onboarding, permissions, library scan, theme choice.

**Max optimisation.**
- **Just-in-time permissions.** Explain each permission at the moment it is needed; no dead-end denial.
- **First value <60 s.** Detect headphones/DAC, pick a sensible default, scan a folder, play a demo track.
- **Skip/resume.** Persist progress; never trap a user in a flow.
- **Accessibility-first.** Screen-reader labels, large targets, and a reduced-motion path from step one.

**Max function.**
- **[Parity]** Personalization quiz (genres, quality, usage) that seeds home and EQ.
- **[Parity]** Scan preview with progress, cancel and estimated time.
- **[Moat]** "Bring your library" wizard: SD, NAS, backup import, playlist import.
- **[Moat]** A demo library for users with no local files.
- **[Experimental]** Guided first listen that explains DSP changes in real time.

**The 10/10 bar.** Sixty seconds from install to "wow", with no permission dead ends.

---

### F. Platform & experience — mean 6.4

Android is the only tier that gets the full engine. Desktop and web are thin, and accessibility is mid-pack. This domain decides whether Pulsr is an Android audiophile app or a platform.

---

#### 31. Android integration — **7.3 / 10**
`Q 7.4 · F 7.0 · X 7.6`

**Now.** Four widget sizes, media notification, media session, Android Automotive manifest, Cast (dev/ytm flavors only), ringtone support, an in-app APK updater, file-intent open, a battery-optimization prompt, and a media browser service.

**Max optimisation.**
- **Widget budget.** <100 ms update, no stale artwork, localized strings, and a reliable fallback when art is missing.
- **Media session completeness.** Queue, seek, speed, art, and Android 13+ media controls; no duplicate notification.
- **Android Auto / Car App Library.** A proper browse tree (artists/albums/playlists) and voice search.
- **Cast handoff.** Session transfer, volume, and a clear "casting" state.

**Max function.**
- **[Parity]** Wear OS app + tile (play/pause, volume, queue).
- **[Parity]** Quick Settings tile and assistant intents.
- **[Moat]** Lock-screen lyrics.
- **[Moat]** Resizable widgets and Material You colors.
- **[Moat]** Signed delta updates with signature verification and staged rollout.
- **[Experimental]** Android XR/glasses companion (watch the platform, don't bet on it).

**The 10/10 bar.** Pulsr feels like part of the OS, not an app you have to open.

---

#### 32. Desktop & web parity — **4.7 / 10** — *hard cap 9.0*
`Q 4.8 · F 4.2 · X 5.2`

**Now.** Flutter desktop shells (Windows/macOS/Linux) with `just_audio` and `audio_service`; a web build; a marketing site. None of them run the C++ DSP engine, and there is no exclusive-output path.

**Max optimisation.**
- **Declare tiers.** Tier 1 Android (full DSP), Tier 2 desktop (playback + EQ/limiter/crossfeed), Tier 3 web (preview/party join). Stop implying parity.
- **Desktop exclusive output.** WASAPI exclusive (Windows), CoreAudio hog mode (macOS), PipeWire/PulseAudio (Linux), with sample-rate follow.
- **Desktop library.** Local scan, keyboard shortcuts, tray controls, and a proper window layout.
- **Web honesty.** OPFS library, WASM DSP for EQ, and a visible "browser limits" notice; no background-audio promises.

**Max function.**
- **[Parity]** Desktop DSP parity (at least EQ, limiter, crossfeed, gain).
- **[Parity]** NAS/SMB library and watch folders.
- **[Moat]** Desktop Party host.
- **[Moat]** Web party join + shared queue.
- **[Experimental]** A plugin SDK for third-party DSP stages.

**The 10/10 bar (cap 9.0).** The same library and sound signature on every screen you own — with honest limits where the platform imposes them.

---

#### 33. Accessibility & i18n — **6.4 / 10** — *cap 9.8*
`Q 6.5 · F 6.2 · X 6.4`

**Now.** Three languages (en/ar/es), ~3,976 ARB keys, accessibility tests, RTL ratchet, dynamic type support, and semantic labels on many controls.

**Max optimisation.**
- **100% labelled controls.** Every interactive element has a label, role, and state; 48 dp minimum; logical focus order; keyboard navigation on desktop.
- **Screen-reader pass.** TalkBack and VoiceOver audits on the ten most-used flows; fix every "unlabeled button".
- **Contrast.** WCAG AA for all 9 themes in light/dark; a high-contrast mode.
- **Localization debt.** Remove the remaining raw `Text` literals and hardcoded widget strings; add plural/format checks.

**Max function.**
- **[Parity]** 10 languages: hi, id, tr, ru, pt-BR, fr, de, fa, ur, zh.
- **[Parity]** Per-app language selection and a full RTL audit.
- **[Moat]** Dyslexia-friendly font and a high-contrast theme.
- **[Moat]** Haptic/audio parity for every visual cue.
- **[Experimental]** Sign-language video for onboarding (only if user research supports it).

**The 10/10 bar (cap 9.8).** Nobody needs to ask how to use it, in any language, on any input device.

---

#### 34. App-wide performance — **7.2 / 10**
`Q 7.4 · F 7.0 · X 6.8`

**Now.** 80 MB image cache cap, GPU budget, frame-budget tests, rebuild audits, and a large test suite. The app is responsive, but scale and startup are not yet proven.

**Max optimisation.**
- **Startup.** <900 ms p50 to first frame, <1.5 s p95; defer DI, prefs and network; no blocking platform calls.
- **Memory.** <250 MB p95 with a 100k-track library; bounded artwork cache; no full-library snapshots.
- **Jank.** <0.5% frames over 16 ms on Pixel 6, <1% on a mid-tier device; measure with macrobenchmarks, not vibes.
- **Isolates.** Scan, search, tag write, stats and artwork decode never touch the UI isolate.

**Max function.**
- **[Parity]** A dev performance dashboard + CI regression gate.
- **[Parity]** Baseline profiles and R8 full mode.
- **[Moat]** 120 Hz animation polish with variable refresh.
- **[Moat]** Low-RAM mode for <2 GB devices.
- **[Experimental]** Predictive preloading of the next screen and track.

**The 10/10 bar.** It feels native on a $200 phone and a flagship, with numbers to prove it.

---

### G. Foundation — mean 7.4

The foundation is the quiet success: 211k hand-written Dart LOC, 116k test LOC, 5,238 test declarations, a 77% coverage floor, native host tests, fuzzers, goldens and ratchets. The failures are concentrated: plaintext DB, 427 empty catches, and a red analyze gate caused by temporary test debris.

---

#### 35. Security & privacy — **7.1 / 10**
`Q 7.4 · F 6.8 · X 7.0`

**Now.** `SafeFilePath` containment on deletes, exact-domain WebView allowlist, SSRF-hardened radio URLs, secure storage for proxy credentials, encrypted token storage, a SOCKS5/HTTP proxy with DoH resolution, a "Pure" build with no INTERNET permission, and Sentry crash reporting.

**Max optimisation.**
- **Encrypt the database.** Implement ADR-015 with SQLCipher, a resumable migration, backup-before-migrate, and a key in Keystore/Keychain. This is the largest single privacy gap.
- **App lock.** Biometric/PIN gate, privacy screen in the recents switcher, and a configurable timeout.
- **Log hygiene.** No tokens, paths or queries in logs; structured redaction; opt-in diagnostics.
- **Data controls.** Export and delete all user data; a permission dashboard; a "what left the device" network log.

**Max function.**
- **[Parity]** Encrypted backups (XChaCha20/age) with restore preview.
- **[Parity]** Tracker-free Pure build (already exists) and a reproducible-build attestation.
- **[Moat]** A privacy dashboard showing every network destination and why.
- **[Moat]** Per-feature telemetry opt-in.
- **[Experimental]** Reproducible builds + signed release verification.

**The 10/10 bar.** A privacy-first player you can verify, not just trust.

---

#### 36. Data layer & reliability — **7.5 / 10**
`Q 7.5 · F 7.4 · X 7.4`

**Now.** Drift/SQLite with reactive streams, schema migrations, queue slot persistence, migration resilience tests, and a 73–78% coverage band depending on the artifact.

**Max optimisation.**
- **Scale indexes.** Audit every query with `EXPLAIN QUERY PLAN`; add FTS5 for search; p95 <30 ms for all library queries at 100k tracks.
- **Migration proof.** Test every historical schema version → current, with a corrupted-DB recovery path.
- **Encryption.** SQLCipher + key rotation + backup/restore (shared with security).
- **Integrity.** Startup integrity check, automatic rebuild from filesystem if the DB is corrupt, and a visible recovery state.

**Max function.**
- **[Parity]** Multi-library schema with per-source policies.
- **[Parity]** Sync metadata (revisions/vector clocks) for cloud.
- **[Moat]** An event log for analytics and undo.
- **[Moat]** Corruption detection + one-tap rebuild.
- **[Experimental]** CRDT-backed collaborative playlists.

**The 10/10 bar.** Data is never lost, never slow, and never plaintext.

---

#### 37. CI / DX / test — **8.5 / 10**
`Q 8.8 · F 8.2 · X 8.0`

**Now.** 5,589 tests passed (18 skipped, 0 failed), 116k test LOC, 77.66% hand-written coverage against a 77% floor, native DSP host tests, fuzz/property/golden/a11y/security suites, and ratchets for fat files, empty catches and RTL. `flutter analyze --fatal-infos --fatal-warnings` and `dart format --set-exit-if-changed lib test` are both clean. Remaining debt: four tracked temporary probe tests, goldens that are local-only (the masters directory is gitignored), no device farm, and a thin coverage margin.

**Max optimisation.**
- **Keep the gate green.** Remove the four tracked `_probe_*` / `_audit_capture_*` files (their coverage is incidental), and fail any PR that adds new temporary diagnostics under `test/`.
- **Coverage truth.** Commit the golden masters or generate them in CI; add a diff-coverage gate (new lines ≥85%) on top of the 77% floor.
- **Device farm.** Firebase Test Lab / physical devices for playback, USB, Bluetooth and AAudio; macrobenchmarks for startup, scroll and search.
- **Mutation testing.** At least the DSP math, gain staging and queue codec; a surviving mutant is a missing assertion.

**Max function.**
- **[Parity]** Golden tests for 9 themes × 3 sizes × 2 brightness modes.
- **[Parity]** Performance regression gates (startup, search, scroll, scan).
- **[Moat]** Nightly 24-hour playback soak + 10k queue-operation fuzz.
- **[Moat]** Automated release checklist and signed artifacts.
- **[Experimental]** A public benchmark dashboard (DSP CPU, latency, battery).

**The 10/10 bar.** `main` is always releasable, and the numbers prove it.

---

## 3. Cross-cutting ceilings

### 3.1 Audio quality matrix (target state)

| Capability | Today | 10/10 target | Hard limit |
|---|---|---|---|
| PCM | Up to 384 kHz / 32-bit (path-dependent) | 768 kHz / 32-bit, one SRC | DAC/HAL |
| DSD | DSD64–256 via DoP/decoder | DSD512, native USB alternate mode | DAC firmware |
| Channels | Stereo (engine ignores >2) | 4/6/8 ch + bass management | USB/HDMI |
| Bit-perfect | USB exclusive + AAudio | Per-track rate follow + certificate | OEM HAL |
| Latency | Low-latency AAudio | <10 ms MMAP where available | Device |
| DSP stages | 18, stereo | 18+, multichannel, SIMD | CPU budget |
| Room correction | Convolution IR | Guided sweep + target curves | Mic quality |
| Spatial | Panner/width | Head-tracked binaural | IMU/HRTF |

**Licensing note.** Do not chase MQA full decoding (the format is in retreat and the helper is enough) or Dolby Atmos/DTS:X decoding (licensing cost, not a core differentiator). Put the effort into multichannel PCM, DSD, and measurement-driven correction instead.

### 3.2 Scale and latency budgets

| Metric | Current evidence | 10/10 target |
|---|---|---|
| Library size | Architecture supports it; not proven | 100k tracks, all screens <30 ms p95 |
| Cold scan | Not benchmarked here | 50k tracks <60 s; <2% battery per 10 min |
| Incremental scan | mtime-based paths exist | <6 s warm; resumable |
| Search | Fuzzy over up to 500 results | <50 ms p95 at 100k; FTS5 |
| Cold start | Not measured | <900 ms p50 / <1.5 s p95 |
| Jank | Frame tests exist | <0.5% frames >16 ms (Pixel 6) |
| Memory | 80 MB image cache | <250 MB p95 at 100k tracks |
| Queue integrity | Mutex in one path | 0 lost updates / 10k ops |
| Party skew | Clock sync implemented | <40 ms p95, 10 devices |
| DSP xruns | RTF governor | <0.1/hour, 24 h soak |

### 3.3 Platform tiers

| Tier | Platforms | Promise | Cap |
|---|---|---|---|
| **Tier 1** | Android (dev/ytm/prod) | Full DSP, USB/AAudio, widgets, Cast (flavors), Automotive | 10.0 |
| **Tier 2** | Windows, macOS, Linux | Playback + EQ/limiter/crossfeed, exclusive output, local library | 9.5 |
| **Tier 3** | Web | Preview, party join, shared queue; WASM EQ | 8.0 |
| **Tier 2 (future)** | iOS | CoreAudio port of the C++ engine; background audio entitlement | 9.0 until port |

**The honesty rule.** Every surface must state which tier it is. A Tier 3 web build that claims "bit-perfect" destroys trust in the Tier 1 claim.

### 3.4 Intelligence layer (on-device, privacy-preserving)

The credible 2026 ceiling is not a chatbot. It is small, local models that make the library feel smart:

- **Semantic search** via a <30 MB embedding model, indexed in SQLite; no audio leaves the device.
- **Acoustic fingerprinting** (Chromaprint) for dedupe and missing-metadata lookup.
- **Auto-tagging** from audio features + text metadata, with confidence and undo.
- **Mood/energy/tempo features** for smart shuffle, radio-from-track and Auto-DJ.
- **Skip-behavior personalization** stored locally, exportable and resettable.

Avoid: cloud LLM chat in the player, generative audio, social feeds, and any feature that requires uploading the library. They are off-brand and dilute the privacy promise.

---

## 4. The road to maximum

### Wave 0 — Stop the leaks (0–2 weeks)

**Exit criteria:** `flutter analyze` = 0; no temporary probe/repro tests in `test/`; coverage artifact regenerated and above the floor; download selection cannot delete the wrong item; every empty catch either logs or is explicitly justified.

| Item | Why | Effort |
|---|---|---|
| Delete/move `_probe_*`, `_audit_capture_*`, `_repro_*` | Current analyze is red because of one untracked repro; four more temporary probes are committed | S |
| Regenerate coverage and reconcile 73.4% vs 77% floor | The headline CI claim is currently unverifiable | S |
| Fix download selection pruning | Wrong-item deletion is a data-loss bug | S |
| Empty-catch burn-down: 427 → <250 | Silent failures are the largest quality multiplier | M |
| Settings search (first slice) | 65+ sections with no search is a usability tax | S |

### Wave 1 — Scale and trust (2–8 weeks)

**Exit criteria:** 100k-track benchmark green; search p95 <50 ms; queue 0 lost updates; DB encryption migration tested on 10 devices; Party reconnect p95 <1 s; cloud conflict UI shipped.

| Item | Why | Effort |
|---|---|---|
| 100k-track benchmark + SQL index audit + FTS5 search | Proves the library architecture; unlocks every downstream screen | L |
| Queue single-writer actor + property test | Eliminates the last class of playback data loss | M |
| SQLCipher migration (ADR-015) + app lock | Closes the largest privacy gap | L |
| YTM Browse cubit rewrite | Weakest feature; 349 lines, no tests, hanging cache | M |
| Party client state machine + QR join + queue versioning | Turns good infrastructure into a product | L |
| Cloud sync conflict UI + encrypted backups | Prevents silent data loss | L |
| A11y sweep: labels, 48 dp, focus order | 100% labelled controls is achievable in one pass | M |

### Wave 2 — The audio moat (6–16 weeks)

**Exit criteria:** multichannel and DSD512 verified on 3 DACs; UAC2 hardware volume; room wizard <5 min; word-level lyrics; theme gallery; 9 themes golden-tested.

| Item | Why | Effort |
|---|---|---|
| Multichannel DSP + bass management | The biggest missing audiophile capability | L |
| DSD512 + PCM 768 + native DSD fallback | Category leadership; DoP remains the safe default | M |
| UAC2 hardware volume + per-track rate follow | Removes the last hidden attenuation | M |
| Room correction wizard + target curves | Turns a hidden feature into a headline | M |
| Word-level lyrics + duet/pitch scoring | Lyrics are a daily surface; word timing is the bar | M |
| Theme gallery + Milkdrop preset compatibility | Design moat; community leverage | M |

### Wave 3 — Everywhere (3–9 months)

**Exit criteria:** desktop exclusive output + DSP parity; iOS CoreAudio port (beta); Android Auto/Wear; semantic search; 10 languages.

| Item | Why | Effort |
|---|---|---|
| Desktop WASAPI/CoreAudio/PipeWire exclusive output | Tier 2 credibility | L |
| iOS CoreAudio port of the DSP engine | Unlocks the second-largest market | XL |
| Android Auto / Car App Library + Wear OS | Platform presence where listening happens | M |
| Semantic search + mood/energy features | Makes 100k libraries navigable | L |
| 10 languages + per-app language | Reach without a redesign | M |
| Party/cloud E2E + host migration | Trust for social features | L |

### 4.1 What buys the most points

| Move | Features lifted | Est. composite gain | Confidence |
|---|---|---:|---|
| Scale proof (100k, FTS5, virtualize) | Library, Search, Home, Detail, Settings | +0.6 to +0.9 | High |
| Silent-failure elimination | All 37 (quality floor) | +0.3 to +0.5 | High |
| DB encryption + app lock | Security, Data, Trust | +0.4 | High |
| YTM Browse rewrite | Online domain | +0.2 | High |
| Party + Cloud productization | Social domain | +0.5 | Medium |
| Multichannel/DSD/UAC2 | Playback, DSP, DAC | +0.3 | Medium |
| Desktop/iOS reach | Platform domain | +0.5 (strategic) | Medium |
| Settings search + split | Settings, first-run | +0.3 | High |
| A11y + 10 languages | A11y, every screen | +0.4 | High |

### 4.2 Anti-roadmap (do not build)

- **MQA full decoder.** The format is in retreat; keep the helper, don't license the decoder.
- **Atmos/DTS:X decoding.** Licensing and hardware complexity for a feature the core user does not need.
- **A social network / follower feed.** Party is the social feature; a feed is a different product.
- **Cloud music locker / streaming service.** Legal exposure, infrastructure cost, and it fights the offline-first promise.
- **An in-player LLM chatbot.** Off-brand, privacy-hostile, and not a music problem.
- **A plugin SDK before the DSP API is stable.** You will freeze a bad API.
- **Desktop/iOS before the Android scale proof.** Reaching more platforms with the same 7/10 library would multiply the debt.

---

## 5. What a 10/10 Pulsr actually feels like

1. **Cold start to sound in under two seconds**, with the last queue and DSP chain exactly where you left them.
2. **A 100k-track library that scrolls like a 100-track one**, and a search box that answers before you finish typing.
3. **A DAC that receives the file untouched**, and a screen that proves it with source rate, output rate, and a chain-of-custody certificate.
4. **A room-correction wizard that takes five minutes**, then gets out of the way.
5. **Lyrics at the word**, in your language, with a karaoke mode that actually scores you.
6. **A party where ten phones stay within 40 ms**, and nobody loses a queue edit.
7. **A library database that is encrypted**, an app that locks, and a privacy dashboard that shows exactly what left the device.
8. **Nine themes that look intentional at every size**, and a theme you made yourself.
9. **Settings you can search**, onboarding that respects your time, and a screen reader that never says "button".
10. **A green build**, 80%+ coverage, 0 empty catches, and performance numbers that are measured, not claimed.

That is the maximum. It is reachable, but not by adding more features to the current surface. It is reached by making the existing surface provable, then extending the moat.

---

## Appendix A — Evidence and confidence

**Current scores** are expert estimates on a 10-point scale, anchored to:

- `gaps.md` (2026-10-02): 52 modules × 11 dimensions, with `file:line` evidence.
- The 2026-10-04 remediation table: analyze clean, 2,318 tests, 39.1% coverage at that time.
- Fresh checks on 2026-10-26:
  - `flutter analyze --fatal-infos --fatal-warnings` → **2 warnings** (`_repro_mini_player_test.dart`, unused imports), 131 s.
  - `coverage/lcov.info` → **73.4%** hand-written line coverage (85,750 LF / 62,900 LH, generated files excluded), against a **77.0%** floor.
  - `lib/` → 642 hand-written Dart files, **211,434 LOC**; `test/` → 690 files, **116,289 LOC**, **5,238** `test(`/`testWidgets(` declarations.
  - **427** empty `catch` blocks; **0** raw `print(` calls.
  - **57** settings presentation files; **36** routes; **27** feature modules.
  - 18 native DSP stages; the graph is stereo-centric (crossfeed, width, reverb, multiband and bass management assume channels 0/1; no multichannel layout).
  - `docs/adr/015-database-encryption.md` → **Proposed, not implemented**.
  - No biometric/app-lock dependency or implementation found.
  - iOS/desktop shells register `just_audio`/`audio_service` but no native Pulsr DSP library.
  - Four tracked `_probe_*` / `_audit_capture_*` test files marked "TEMPORARY" in their headers; one untracked `_repro_*` test currently breaks analyze.

**Documentation claims that do not survive inspection.** These matter because a max-rate claim is only as good as the numbers behind it:

| Claim | Where it is made | What the tree shows |
|---|---|---|
| "4,000+ AutoEq profiles" | `CLAUDE.md` §2 | **652** entries in `assets/eq_profiles/headphone_profiles.json`; `HeadphoneProfilesRepository` loads only that asset plus user custom profiles. |
| "128-band parametric EQ" | `CLAUDE.md` §2 | `ParametricEQ::MAX_BANDS = 64`; the Dart manager supports 10/32/64 bands. |
| "10/10 across all 11 dimensions" | `README.md` | `flutter analyze` = 2 warnings; local lcov coverage 73.4% against a 77.0% floor. |
| "2,318 tests" | `gaps.md` (2026-10-04) | 5,238 `test(`/`testWidgets(` declarations today — stale, but directionally better. |

**Confidence:** High for the measured facts above; medium for per-feature Q/F/X estimates (they synthesize the baseline audit and current checks, not a fresh line-by-line re-audit of 211k LOC). The intent is a decision-grade ceiling map, not a certification.

**What would raise confidence:** run the full `flutter test --coverage` on a clean tree, add the 100k-track benchmark, and re-audit the five lowest-scoring features (YTM Browse, Desktop/Web, Radio, Party, Cloud) line by line.

---

## Appendix B — The 11-dimension 10/10 checklist

Use this as the acceptance bar for every feature. A feature is not 10/10 until every applicable line is true.

| Dimension | A 10/10 feature has… |
|---|---|
| **Architecture** | Clear layering, small cohesive units, dependency inversion, no god files/objects |
| **Bug density** | No known functional defects; edge cases covered by tests |
| **State** | One source of truth, immutable state, no duplication outside the store |
| **Errors** | Typed `AppError`, no silent/swallowed failures, user-visible recovery |
| **Performance** | No UI-isolate heavy work, bounded per-frame work, no O(n²)/N+1 |
| **Memory** | Bounded caches, deterministic disposal, no leaks |
| **Concurrency** | Mutex/generation guards on shared mutable state; no lost updates |
| **Hygiene** | No dead code, no avoidable `dynamic`, no oversized files, full l10n |
| **Security** | Input/path/URL validation, no credential leakage, no SSRF/arbitrary file ops |
| **Accessibility** | Semantics on every control, ≥48 dp targets, dynamic type/RTL safe |
| **CI / DX / ADR** | Enforced by CI, dedicated tests, documented decisions, real coverage floor |

---

## Appendix C — Verification commands

```bash
# Static analysis (must be zero issues for a 10/10 claim)
flutter analyze --fatal-infos --fatal-warnings

# Full suite + coverage, then enforce the floor
flutter test --coverage
python scripts/check_coverage.py

# Native DSP parity + sanitizer suites (host)
./gradlew :app:testNative

# Native Go party server tests
cd server/pulsr_party && go test ./...

# Ratchets and architecture guards
flutter test test/architecture test/a11y test/security test/fuzz test/property test/perf

# Confirm no temporary probes remain
rg -n "TEMPORARY|_probe_|_repro_|_audit_capture" test/
```

---

## Appendix D — Assumptions

- The "prod" (Pulsr Pure) flavor remains offline-only and strips INTERNET; all YTM capabilities are scoped to dev/ytm builds. The max-rate plan does not change that boundary.
- Android remains Tier 1. iOS and desktop are reach opportunities, not prerequisites for the 10/10 Android claim.
- "Maximum" means the credible 2026 ceiling for a premium offline-first player, not an unbounded feature list. Platform, licensing and physics caps are stated explicitly.
- Adding features does not raise a score. A feature only reaches 10 when Q, F and X all reach 10; breadth without correctness is explicitly penalized.
