# Pulsr Music vs Poweramp — Feature-by-Feature Comparison

> Basis: Pulsr `1.0.0+1` (this repository, `feat/yt-2026-09-hardening`) against
> **Poweramp v3** (stable build ~1024, 2026; beta build 1028 adds the new audio-engine
> overhaul). Poweramp details are taken from its official site, Google Play listing and the
> build-1026/1028 beta notes. Beta-only Poweramp features are marked **(beta)**.
>
> Verdict legend: **Pulsr +** = Pulsr clearly ahead · **Poweramp +** = Poweramp clearly ahead
> · **Even** = comparable.

---

## 0. TL;DR scorecard

| Category | Winner | Margin |
|---|---|---|
| Pricing, license, openness | **Pulsr +** | Large |
| Privacy / offline purity | **Pulsr +** | Large |
| Raw output & DAC depth (USB exclusive, DSD, sample rates) | **Poweramp +** | Large |
| Volume / gain control (DVC) | **Poweramp +** | Moderate |
| Equalizer band count / parametric depth | **Poweramp +** | Moderate |
| DSP effects breadth (spatial, dynamics, crossfeed, saturation…) | **Pulsr +** | Moderate |
| Room correction | **Pulsr +** | Large (Poweramp has none) |
| Playback continuity (gapless / crossfade / replay gain) | **Even** | — |
| File-format breadth | **Poweramp +** | Moderate |
| Internet radio / HTTP streams | **Poweramp +** | Large |
| Online music (streaming + downloads) | **Pulsr +** | Large (different domain) |
| Library tools (stats, duplicates, artwork backfill) | **Pulsr +** | Moderate |
| Smart playlists | **Pulsr +** | Slight |
| Lyrics | **Pulsr +** | Moderate |
| Tag/metadata editing | **Even** | — |
| UI themes / skins | **Poweramp +** | Slight (ecosystem) |
| Visualizations | **Poweramp +** | Slight (Milkdrop) |
| Widgets / notification / Android Auto | **Even** | — |
| Cast (Chromecast) | **Poweramp +** | Large |
| Automation & device profiles | **Pulsr +** | Moderate |
| Scrobbling & listening stats | **Pulsr +** | Slight |
| Optional cloud sync | **Pulsr +** | Slight |
| Localization / accessibility | **Pulsr +** | Moderate |
| System-wide EQ for other apps | **Poweramp +** | Large (separate app) |

**Bottom line:** Poweramp is still the deeper *audiophile output engine* (USB-exclusive,
native/DoP DSD, 64-band parametric, DVC, extreme sample rates, format breadth). Pulsr is the
more *private, open, modern library and feature platform* (offline-pure build, room correction,
rich effects, library tools, automation, lyrics, online integration, i18n). Neither dominates
the other outright.

---

## 1. Pricing, licensing & philosophy

| Aspect | Pulsr | Poweramp |
|---|---|---|
| Price | Free | 15-day full trial, then paid unlocker (~$5.49) |
| License | GPLv3 (open source) | Closed source |
| Ads / trackers | None | None (paid model) |
| Accounts | Optional (only for cloud/YTM) | None required |
| Architecture | Flutter + Dart + Drift SQLite, native DSP/JNI | Native C++/Java engine |
| Extensibility | Open source, plugin-ish services | Third-party **skins** and **visualizations** ecosystem |

**Pulsr +.** Being free, GPLv3 and auditable is a structural advantage. Poweramp's paid model is
fair for what it delivers, but Pulsr wins on cost and openness.

---

## 2. Audio engine & output

| Feature | Pulsr | Poweramp |
|---|---|---|
| Internal precision | Float32 output path | Float32, **Float64 DSP pipeline (beta)** |
| Hi-Res output | ✅ (device-dependent) | ✅ |
| AAudio direct output | ✅ (+ buffer control) | ✅ |
| OpenSL ES | — (uses AAudio/just_audio/ExoPlayer) | ✅ |
| Bit-perfect mode | ✅ (disables DSP) | ✅ "Perfect Bit Perfect" + **No Resample (beta)** |
| Sample-rate switching per track | Target rate negotiation | **Follow Track (beta)** auto-reconfigure |
| Max sample rate | 44.1 kHz–192 kHz (device-dependent) | up to **384 kHz** (stable) / **768 kHz (beta)** |
| Bit depths | 16 / 24 / 32-float | 16 / 24 / **8.24 / 32 / Float** |
| USB DAC | Device selection + negotiation via system picker | ✅ USB host + **USB Exclusive driver (beta)**, hardware volume |
| DSD | Decodes DSF/DFF to PCM | **Native + DoP DSD64–1024**, DSD remastering (beta) |
| MQA | Detection + core unfold path | Not advertised |
| Bluetooth codec control | ✅ (LDAC/aptX exposure) | ✅ LDAC/LDHC + codec matching |
| Bluetooth Hi-Res | Device/codec dependent | ✅ (LDAC/LDHC) |
| Resampler | Sinc resampler + quality setting | swr/SoX resampler |
| Dither | TPDF | Multiple dither options |
| Direct Volume Control (DVC) | ❌ (uses ReplayGain + per-song volume + HAL volume boost) | ✅ DVC, extended dynamic range/low-distortion bass |
| Output profiles | Device Profiles + Settings Profiles (per device) | Per-output presets, custom USB/BT profiles |
| Dynamic reconfiguration | Engine hot-swap on route change | **Dynamic Reconfiguration (beta)** |

**Poweramp +, decisively.** This is Poweramp's core competence. Pulsr's chain is legitimate
(bit-perfect, float, AAudio, BT codec) but lacks exclusive USB, native/DoP DSD, DVC and the
extreme sample-rate/bit-depth envelope.

---

## 3. Equalization & DSP effects

| Feature | Pulsr | Poweramp |
|---|---|---|
| Graphic EQ | 10-band (±12 dB, 31 Hz–16 kHz) | Up to 32/64-band graphic |
| Parametric EQ | ✅ **32-band** + custom frequency editor | ✅ parametric mode; **64-band (new site)** |
| Per-band mute/solo | ✅ | — (not advertised) |
| Manual preamp | ✅ (−12…+12 dB) | ✅ (range widened −24…+24 dB beta) |
| AutoEQ headphone presets | ✅ bundled + online search + per-song auto-apply | ✅ AutoEQ presets (hundreds on Poweramp Equalizer) |
| Separate Bass / Treble | Bass boost (preset + HAL) | ✅ dedicated Bass and Treble |
| 3D spatializer / virtualizer | ✅ | stereo eXpansion only |
| Stereo width (mid/side) | ✅ | stereo eXpansion |
| Mono mix / balance | ✅ | ✅ |
| Multiband dynamics / compressor | ✅ | ❌ |
| Lookahead brickwall limiter | ✅ | ❌ |
| Crossfeed | ✅ | ❌ |
| Convolution reverb + custom WAV IR | ✅ | Reverb presets only |
| Harmonic saturation / exciter | ✅ | ❌ |
| Loudness contour (Fletcher–Munson) | ✅ | ❌ |
| Subwoofer crossover | ✅ | ❌ |
| Dynamic EQ | ✅ | ❌ |
| Sinc resampler / dither controls | ✅ | ✅ |
| Room correction (measurement wizard) | ✅ | ❌ |
| System-wide EQ (other apps) | ❌ | ✅ via separate **Poweramp Equalizer** app |
| Preset import/export / A-B compare | ✅ (A/B flat + 4 slots, JSON exchange) | ✅ presets export/backup/share |

**Split:** Poweramp wins **EQ band count and parametric surgical depth** (64 vs 32) and the
**system-wide Equalizer** companion. Pulsr wins **effects breadth** — it has an entire
mastering-style rack (dynamics, limiter, crossfeed, convolution IR, saturation, loudness,
sub-crossover, dynamic EQ) plus **room correction**, none of which Poweramp advertises.

---

## 4. Playback, queue & continuity

| Feature | Pulsr | Poweramp |
|---|---|---|
| Gapless | ✅ + encoder-delay trims | ✅ "gapless smoothing" |
| Crossfade | ✅ curves, BPM sync, native gain ramp | ✅ |
| ReplayGain | ✅ track/album + preamp | ✅ |
| Speed / pitch | ✅ both, 0.1–8.0x (extended) | ✅ Tempo effect |
| Reverb effect | ✅ convolution + IR | ✅ presets |
| A-B loop | ✅ | Partially (via seek) |
| Per-track delay | ✅ | ❌ |
| Long-form bookmarks / auto-resume | ✅ (podcast/audiobook) | ✅ resume |
| Per-song volume / EQ / BPM | ✅ | ✅ per-song? EQ presets per output |
| Queue system | ✅ 3 persisted slots, drag reorder | ✅ dynamic queue |
| Sleep timer | ✅ 4 modes (duration/eoT/N/eoQ) | ✅ |
| Silence skip | ✅ | ❌ (skip short tracks instead) |
| SponsorBlock | ✅ (online) | ❌ |
| Auto-resume on headset reconnect | ✅ automation triggers | ✅ |
| Volume-key long-press skip | ❌ (mini-player gestures instead) | ✅ (adb-enabled) |
| Skip short tracks | Scan-time min-duration filter | ✅ runtime ignore-short / video tracks |

**Even → Pulsr slight edge.** Pulsr offers more playback *automation* (BPM crossfade, per-track
delay, silence skip, SponsorBlock, 3 queues); Poweramp offers classic ergonomics (volume-key
skip, ignore-short-track, dynamic queue). Call it a tie with feature overlap in both directions.

---

## 5. File formats & streams

| | Pulsr | Poweramp |
|---|---|---|
| Core lossless | FLAC, ALAC, WAV, AIFF (PCM) | FLAC, ALAC, WAV, AIFF, APE, WV |
| Lossy | MP3, AAC/M4A, OGG Vorbis, OPUS | MP3, AAC/M4A, OGG, OPUS, WMA, MPC |
| DSD | DSF/DFF → **PCM only** | DSF/DFF **native/DoP** |
| Trackers / mods | ❌ | IT, S3X, XM |
| Other | MQA (core) | TTA, MKA, TAK, WebM, FLV-audio |
| CUE sheets | Parser exists but **unwired** | ✅ embedded + standalone |
| HTTP radio streams | ❌ | ✅ (.m3u streams) |
| HLS | underlying just_audio only | — |

**Poweramp +.** Noticeably broader format and stream coverage; CUE and internet radio are the
most user-visible missing pieces in Pulsr.

---

## 6. Library, metadata & organization

| Feature | Pulsr | Poweramp |
|---|---|---|
| Indexing | Drift SQLite + FTS5, <2 s for 10k | Native fast C++ scanner |
| Browse modes | Songs, Albums, Artists, Genres, Folders, Years, Playlists, Favorites, Downloaded | Folders + library categories |
| Folder tree (hierarchical) | ✅ (breadcrumbs) | ✅ Folders Hierarchy |
| Genre hierarchy view | ✅ | genre categories |
| Smart playlists / rule builder | ✅ incl. BPM, ratings, codec, year | ✅ smart playlists |
| Search | FTS5 + Arabic/Latin normalization + fuzzy fallback | ✅ |
| Ratings | ✅ 0–5 | ✅ |
| Play statistics | ✅ dedicated Stats screen | Most Played / Recently Played lists |
| Duplicate finder | ✅ with keep/delete | ❌ not advertised |
| Missing album art | ✅ online backfill | ✅ |
| Artist image/bio | ✅ bio lookup | ✅ artist images |
| Tag editor | ✅ in-place + **batch** + online metadata | ✅ tag editor |
| Album art embed | ✅ gallery/camera | ✅ |
| CUE parsing | ❌ unwired | ✅ |
| Import/export playlists | M3U/M3U8 | M3U/M3U8/PLS/WPL |

**Pulsr +.** Pulsr's library tooling (duplicates, stats, artwork backfill, rich rule builder) is
ahead; Poweramp counters with CUE and wider playlist formats.

---

## 7. Lyrics

| | Pulsr | Poweramp |
|---|---|---|
| Synced LRC | ✅ millisecond autoscroll | ✅ synchronized |
| Plain text fallback | ✅ | ✅ |
| Embedded tags | ✅ | ✅ |
| Online lookup | ✅ LRCLIB + YouTube Music | ✅ lyrics search via plugin |
| Tap-to-seek | ✅ | ❌ |
| Offset calibration | ✅ ±50 ms | ❌ |
| Lyrics editor | ✅ (sidecar .lrc) | ❌ |
| Karaoke mode | ✅ full-screen | ❌ |

**Pulsr +.** Clearly more capable here.

---

## 8. UI, themes, visualizations & customization

| | Pulsr | Poweramp |
|---|---|---|
| Player themes | 8 built-in + **Custom Theme Studio** | Light/Dark skins, Pro Buttons, static seekbar |
| Third-party skins | ❌ (open source; theme export) | ✅ large paid skin ecosystem |
| Dynamic album-art theming | ✅ Aura palette extraction | skin/accent based |
| AMOLED / high contrast | ✅ | ✅ dark skins |
| Visualizations | 8 styles (bar/wave/circular/particles/3D terrain/album-reactive/custom JSON) | ✅ spectrum + **Milkdrop .milk presets** |
| Widgets | ✅ interactive (play/pause/next/prev/seek/fav/shuffle/repeat) | ✅ highly customizable |
| Mini-player | ✅ swipeable, drag-seek | ✅ |

**Poweramp + (slight).** Poweramp's skin and Milkdrop visualization ecosystems are deep; Pulsr
has a strong free built-in set plus a theme studio but no marketplace.

---

## 9. OS integration & automation

| | Pulsr | Poweramp |
|---|---|---|
| Android Auto | ✅ | ✅ |
| MediaStyle notification / lock screen | ✅ | ✅ |
| Headset/hardware buttons | ✅ | ✅ |
| Home-screen widget | ✅ | ✅ |
| **Chromecast / Cast** | ❌ | ✅ |
| File intent handling (open audio from other apps) | ✅ | ✅ |
| Device Profiles (auto per output) | ✅ | ✅ per-output presets |
| Automation rules (trigger profiles on events) | ✅ | ❌ |
| Theme scheduler (day/night) | ✅ | ❌ |
| Settings profiles / bundles | ✅ | ✅ backup/restore |
| Proxy + Wi-Fi-only + adaptive quality | ✅ | ❌ (streams only) |

**Even → Pulsr slight edge.** Poweramp wins Chromecast; Pulsr wins rule-based automation and
scheduled theming.

---

## 10. Online music & privacy

| | Pulsr | Poweramp |
|---|---|---|
| Local playback | ✅ | ✅ |
| Internet radio/streams | ❌ | ✅ |
| Online streaming service | ✅ **YouTube Music** (optional build) | ❌ |
| Offline downloads from service | ✅ (YTM) | ❌ |
| Scrobbling | ✅ Last.fm + **ListenBrainz** + stats | ✅ Last.fm/scrobble |
| Optional cloud sync | ✅ favorites/playlists (Firestore, opt-in) | ✅ settings backup |
| Pure offline build (no INTERNET permission) | ✅ **Pulsr Pure** | ❌ requires network for covers/streams/Cast |
| Telemetry | None; **no INTERNET permission in Pure** | None (but full network permission) |
| Open source / auditable | ✅ GPLv3 | ❌ |

**Pulsr + (privacy), Poweramp + (radio/Cast).** Pulsr's optional YTM build is a different value
proposition; Poweramp's network use is for covers/streams/Cast, not tracking.

---

## 11. Localization & accessibility

| | Pulsr | Poweramp |
|---|---|---|
| Languages | English, Spanish, **Arabic (RTL)** | Many community translations |
| RTL support | ✅ | partial |
| High-contrast theme | ✅ | dark skins |
| Edge-to-edge Android 14+ | ✅ | ✅ |

**Pulsr +.** Full RTL plus high contrast is a stronger first-class story; Poweramp has more raw
translation count.

---

## 12. Where each app clearly wins

### Pulsr is ahead on
1. **Price / open source / auditable** (GPLv3, free).
2. **Privacy by construction** — Pulsr Pure removes the INTERNET permission at the manifest.
3. **Effects breadth** — dynamics, limiter, crossfeed, convolution reverb + IR, saturation,
   loudness contour, subwoofer crossover, dynamic EQ.
4. **Room correction** measurement wizard (Poweramp has nothing comparable).
5. **Library tools** — duplicate finder with resolution, full stats, artwork backfill.
6. **Lyrics** — tap-to-seek, offset calibration, editor, karaoke.
7. **Automation & profiles** — rule-based triggers + theme scheduler.
8. **Localization/accessibility** — full RTL + high contrast.
9. **Optional online** — YouTube Music streaming/downloads (Poweramp cannot).

### Poweramp is ahead on
1. **Output depth** — USB Exclusive driver, native/DoP DSD64–1024, bit-perfect/no-resample,
   Follow-Track, up to 384/768 kHz, 8.24/32/float.
2. **DVC** (Direct Volume Control) for low-distortion gain.
3. **64-band parametric EQ** and per-output granularity.
4. **System-wide EQ** via the separate Poweramp Equalizer app.
5. **Format breadth** — APE, WMA, TTA, MKA, TAK, WV, tracker mods, WebM.
6. **CUE sheet playback** and **HTTP internet radio**.
7. **Chromecast** output.
8. **Skins + Milkdrop visualizations** ecosystem.
9. **Maturity/stability** of a decade-plus native engine.

### Roughly even
Playback continuity (gapless/crossfade/replay gain), tag editing, widgets, notifications,
Android Auto, scrobbling, AutoEQ.

---

## 13. Roadmap to reach/beat Poweramp

> Execution-ready task breakdown for an autonomous agent: [`docs/POWERAMP_PARITY_PLAN.md`](POWERAMP_PARITY_PLAN.md)
> (workstreams T1–T13, files, native channel contracts, migrations, tests, and blockers).

Prioritized for the Pulsr codebase (maps to `docs/PULSR_FEATURES_SPEC.md` gaps where relevant).

### P0 — Output-engine parity (the biggest gaps)
1. **USB Exclusive / direct-DAC driver** with hardware volume and true bypass (currently
   system-picker only; `HiResAudioService`).
2. **Native + DoP DSD output** (currently DSF/DFF decode to PCM; `DsdDecoderHelper`/`DopEncoder`
   dormant). Target DSD64–256 at minimum.
3. **Follow-Track sample-rate switching** + **No-Resample / Perfect bit-perfect** mode.
4. Raise the **sample-rate/bit-depth envelope** (384 kHz where device allows; 8.24/32/float)
   and expose per-output caps.
5. **DVC-equivalent gain stage** or a proven low-distortion volume path.

### P1 — User-visible feature gaps
6. **Wire `CueParser`** into playback (embedded + sidecar `.cue`).
7. **Internet radio / HTTP stream** playback (`.m3u` stream URLs) and stream playlist import.
8. **PLS/WPL** playlist import/export alongside M3U.
9. **Format breadth**: APE, WMA, TTA, MKA/TAK, WV, AIFF, WebM, and tracker mods (via decoder
   extensions).
10. **Chromecast / Google Cast** output.
11. Raise parametric EQ to **64 bands** (or unlimited) to match Poweramp's flagship.
12. Multiple **dither** flavors and **swr/SoX-class** resampler options.

### P2 — Polish / ecosystem
13. **Separate Bass/Treble** controls (distinct from bass-boost presets).
14. Importable/shareable **skin format** beyond the Theme Studio.
15. **Milkdrop-compatible** visualization presets.
16. Verify/expand **auto-resume on headset reconnect** and add **volume-key long-press skip**.
17. Per-output preset granularity by output type (headset/BT/USB/speaker).
18. Artist-image downloading and richer artist pages.

---

## 14. Honest verdict

- **If you want the deepest possible DAC/DSD/output control, format breadth, internet radio,
  Cast, a 64-band EQ, DVC and a skin/visualizer ecosystem → Poweramp stays ahead.** Its new
  (beta) engine overhaul widens that lead.
- **If you want a free, open-source, privacy-pure player with a modern library, the richest
  built-in effects rack, room correction, superior lyrics and automation, and optional
  YouTube Music → Pulsr is the better product today.**
- **Overlap:** gapless/crossfade/replay gain, AutoEQ, tag editing, widgets/Android Auto,
  scrobbling — both are competitive.

Pulsr is already a credible Poweramp alternative for local-library users and beats it on
privacy, openness, library tooling and effects breadth. To win the **audiophile output**
argument outright, Pulsr must land the P0 output-engine items above (USB-exclusive, native/DoP
DSD, follow-track/no-resample, DVC, wider rate/depth), then close CUE/radio/Cast in P1.
