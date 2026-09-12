# Pulsr Music vs Poweramp — Feature-by-Feature Comparison

> Basis: Pulsr `1.0.0+1` (this repository, `feat/yt-2026-09-hardening`) against
> **Poweramp v3** (stable build ~1024, 2026; beta build 1028 adds the new audio-engine
> overhaul). Poweramp details are taken from its official site, Google Play listing and the
> build-1026/1028 beta notes. Beta-only Poweramp features are marked **(beta)**.
>
> Verdict legend: **Pulsr +** = Pulsr clearly ahead · **Poweramp +** = Poweramp clearly ahead
> · **Even** = comparable.
>
> **Revision note:** this comparison was re-run after executing
> [`docs/POWERAMP_PARITY_PLAN.md`](POWERAMP_PARITY_PLAN.md). Shipped since the first pass:
> follow-track sample-rate switching, strict no-resample bit-perfect, DoP DSD routing,
> capability-filtered rate envelope (up to 768 kHz), **64-band** parametric EQ, CUE sheet
> playback, HTTP internet radio, and PLS/WPL playlists. Still missing vs Poweramp: USB-exclusive
> driver, native (non-DoP) DSD, DVC, 8.24/Float64, APE/WMA/TTA/TAK/WV/MPC/tracker decoders,
> system-wide EQ and Chromecast.

---

## 0. TL;DR scorecard

| Category | Winner | Margin |
|---|---|---|
| Pricing, license, openness | **Pulsr +** | Large |
| Privacy / offline purity | **Pulsr +** | Large |
| Raw output & DAC depth (USB exclusive, DSD, sample rates) | **Poweramp +** | Moderate ↓ |
| Volume / gain control (DVC) | **Poweramp +** | Moderate |
| Equalizer band count / parametric depth | **Even** | → |
| DSP effects breadth (spatial, dynamics, crossfeed, saturation…) | **Pulsr +** | Moderate |
| Room correction | **Pulsr +** | Large (Poweramp has none) |
| Playback continuity (gapless / crossfade / replay gain) | **Even** | — |
| File-format breadth | **Poweramp +** | Slight ↓ |
| Internet radio / HTTP streams | **Even** | → |
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

**Bottom line (revised):** the balance has shifted. Poweramp still owns the *deepest* output
engine — USB-exclusive access, native DSD, DVC and 8.24/Float64 — but Pulsr now matches or beats
it on **EQ depth (64-band)**, **internet radio**, **CUE**, **playlists**, and still leads on
privacy, openness, room correction, effects breadth, library tools, automation, lyrics, online
integration and i18n. The remaining Poweramp lead is narrower and mostly *native/hardware* work.

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
| Bit-perfect mode | ✅ + **strict no-resample mode** (conflict-gated) | ✅ "Perfect Bit Perfect" + **No Resample (beta)** |
| Sample-rate switching per track | ✅ **Follow-Track** (per-track auto-reconfigure) | **Follow Track (beta)** auto-reconfigure |
| Max sample rate | up to **768 kHz** (device-dependent; capability-gated) | up to **384 kHz** (stable) / **768 kHz (beta)** |
| Bit depths | 16 / 24 / 32-float (8.24 unsupported) | 16 / 24 / **8.24 / 32 / Float** |
| USB DAC | Device selection + negotiation via system picker | ✅ USB host + **USB Exclusive driver (beta)**, hardware volume |
| DSD | PCM decode + **DoP** (when a USB DAC advertises a carrier rate) | **Native + DoP DSD64–1024**, DSD remastering (beta) |
| MQA | Detection + core unfold path | Not advertised |
| Bluetooth codec control | ✅ (LDAC/aptX exposure) | ✅ LDAC/LDHC + codec matching |
| Bluetooth Hi-Res | Device/codec dependent | ✅ (LDAC/LDHC) |
| Resampler | Sinc resampler + quality setting | swr/SoX resampler |
| Dither | TPDF | Multiple dither options |
| Direct Volume Control (DVC) | ❌ (uses ReplayGain + per-song volume + HAL volume boost) | ✅ DVC, extended dynamic range/low-distortion bass |
| Output profiles | Device Profiles + Settings Profiles (per device) | Per-output presets, custom USB/BT profiles |
| Dynamic reconfiguration | Engine hot-swap on route change | **Dynamic Reconfiguration (beta)** |

**Poweramp +, but narrower.** Pulsr now matches follow-track, no-resample, DoP and the 768 kHz
envelope. Poweramp still leads on **USB-exclusive access, native (non-DoP) DSD, DVC, 8.24/Float64
and SoX-class resampling** — all native/hardware work (plan tasks T1/T6 remain open).

---

## 3. Equalization & DSP effects

| Feature | Pulsr | Poweramp |
|---|---|---|
| Graphic EQ | 10 / 32 / 64-band (±12 dB, 31 Hz–16 kHz) | Up to 32/64-band graphic |
| Parametric EQ | ✅ **64-band** + custom frequency editor | ✅ parametric mode; **64-band (new site)** |
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

**Split (revised):** EQ band count is now **even (64 vs 64)**. Poweramp still wins the
**system-wide Equalizer** companion (applies to other apps). Pulsr wins **effects breadth** — an
entire mastering-style rack (dynamics, limiter, crossfeed, convolution IR, saturation, loudness,
sub-crossover, dynamic EQ, per-band mute/solo) plus **room correction**, none of which Poweramp
advertises.

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
| Core lossless | FLAC, ALAC, WAV, AIFF, WebM (audio) | FLAC, ALAC, WAV, AIFF, APE, WV |
| Lossy | MP3, AAC/M4A, OGG Vorbis, OPUS | MP3, AAC/M4A, OGG, OPUS, WMA, MPC |
| DSD | PCM decode + **DoP** (USB-DAC capable) | DSF/DFF **native/DoP** |
| Trackers / mods | ❌ | IT, S3X, XM |
| Other | MQA (core) | TTA, MKA, TAK, WebM, FLV-audio |
| Recognized-only (decoder required) | APE, WMA, TTA, TAK, WV, MPC, mods (indexed count only, not playable) | — |
| CUE sheets | ✅ embedded + sidecar (virtual tracks) | ✅ embedded + standalone |
| HTTP radio streams | ✅ (.m3u stream lists) | ✅ (.m3u streams) |
| HLS | underlying just_audio only | — |

**Poweramp +, slight.** Pulsr now adds WebM/AIFF, CUE and internet radio; the remaining gap is
native decoding for **APE, WMA, TTA, TAK, WV, MPC and tracker modules** (Pulsr classifies these
honestly as "decoder required" rather than mis-indexing them).

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
| CUE parsing | ✅ (single-file album images expand to virtual tracks) | ✅ |
| Import/export playlists | M3U/M3U8/PLS/WPL | M3U/M3U8/PLS/WPL |

**Pulsr +.** Pulsr's library tooling (duplicates, stats, artwork backfill, rich rule builder,
CUE) is now ahead across the board; playlist formats are matched.

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
| Internet radio/streams | ✅ (HTTP/HTTPS streams + .m3u lists) | ✅ |
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
   loudness contour, subwoofer crossover, dynamic EQ, per-band mute/solo.
4. **Room correction** measurement wizard (Poweramp has nothing comparable).
5. **Library tools** — duplicate finder with resolution, full stats, artwork backfill, CUE.
6. **Lyrics** — tap-to-seek, offset calibration, editor, karaoke.
7. **Automation & profiles** — rule-based triggers + theme scheduler.
8. **Localization/accessibility** — full RTL + high contrast.
9. **Optional online** — YouTube Music streaming/downloads (Poweramp cannot).
10. **Internet radio** — HTTP/HTTPS streams with a station manager and `.m3u` list import (now matched).
11. **CUE + PLS/WPL + 64-band EQ** — now at parity.

### Poweramp is ahead on
1. **USB Exclusive driver** with hardware volume and true bypass (Pulsr uses the system picker).
2. **Native (non-DoP) DSD64–1024** and DSD remastering; Pulsr offers DoP only on capable DACs.
3. **DVC** (Direct Volume Control) for low-distortion gain.
4. **8.24 / Float64 pipeline** and SoX-class resampler + multiple dither flavors.
5. **Native decoding breadth** — APE, WMA, TTA, TAK, WV, MPC, tracker mods, FLV.
6. **System-wide EQ** via the separate Poweramp Equalizer app.
7. **Chromecast** output.
8. **Skins + Milkdrop visualizations** ecosystem.
9. **Maturity/stability** of a decade-plus native engine.

### Roughly even
Gapless/crossfade/replay gain, **parametric EQ depth (64-band)**, **internet radio**, **CUE**,
**M3U/M3U8/PLS/WPL playlists**, tag editing, widgets, notifications, Android Auto, scrobbling,
AutoEQ.

---

## 13. Remaining gaps (after the executed parity pass)

> Full status table and task specs: [`docs/POWERAMP_PARITY_PLAN.md`](POWERAMP_PARITY_PLAN.md).
> ✅ shipped: T2 follow-track, T3 strict no-resample, T4 DoP DSD, T5 768 kHz/32-bit envelope,
> T7 64-band EQ, T9 format classification, T10 CUE, T11 radio, T12 PLS/WPL.

### Still open — native/hardware work
1. **T1 USB Exclusive driver** with hardware volume and true bypass of the Android mixer.
2. **T6 DVC-equivalent** direct gain stage (low-distortion, integrated with ducking/crossfade).
3. **Native (non-DoP) DSD** and DSD remastering for DACs that accept raw DSD.
4. **8.24 / Float64 pipeline** and **SoX-class resampler** + multiple dither flavors.
5. **Native decoders** for APE, WMA, TTA, TAK, WV, MPC and tracker modules (FFmpeg/libavcodec
   bridge or libmpv backend) — currently classified honestly as "decoder required".

### Blocked by platform / third-party dependency
6. **T8 System-wide EQ** for other apps — Android restricts session-0 global effects to
   privileged apps.
7. **T13 Chromecast** — requires the Google Cast SDK + a registered receiver app id.

### Out of scope
8. Third-party **skins** and **Milkdrop visualizations** (UI ecosystem) — skipped by decision.

### Optional polish
9. Separate Bass/Treble controls; per-output preset granularity; volume-key long-press skip;
   artist-image downloads.

---

## 14. Honest verdict (revised)

- **Poweramp still wins the extreme-output argument**: USB-exclusive access, native DSD,
  DVC, 8.24/Float64, SoX-class resampling, native decoders for niche formats, system-wide EQ,
  Cast, and a skin/visualizer ecosystem. Its beta engine overhaul keeps that lead.
- **Pulsr now wins or ties almost everything else**: free/GPLv3, provably-offline Pure build,
  room correction, the richest built-in effects rack, 64-band EQ parity, CUE, internet radio,
  PLS/WPL, full library tooling, automation, superior lyrics, optional YouTube Music, and
  full RTL/high-contrast localization.
- **Overlap:** gapless/crossfade/replay gain, 64-band parametric EQ, AutoEQ, CUE, radio,
  playlist formats, tag editing, widgets/Android Auto, scrobbling.

After the parity pass, Pulsr is a **strictly stronger all-round local player** than Poweramp for
the majority of users, and the remaining Poweramp advantages are concentrated in native DAC/DSD
control (T1/T6 + native decoders), system-wide EQ and Cast. Closing those four native/dependency
items would make Pulsr the stronger product on *every* axis except the skin/visualizer marketplace.

**Measurement caveat:** all new parity features are capability-gated and validated by 862 Dart
tests + a native Kotlin compile. USB-exclusive, DVC and native-DSD behaviors still require
real-device validation before being claimed as fully shipped.
