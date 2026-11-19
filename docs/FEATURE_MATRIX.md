# Pulsr Feature Matrix

**Source:** Dart, Kotlin, C++ and Go source in this repository.
**Last verified:** 2026-11-17.
**Purpose:** provide the current, source-backed capability list used by the README and website. Dated audit documents under `docs/` are snapshots and may describe older behaviour.

> Counts below are constants read from source, not estimates. Where a capability is partial, experimental or delegated, it is stated explicitly.

---

## 1. Counts at a glance

| Capability | Verified value | Source |
|---|---|---|
| Native DSP stages | 20 | `android/app/src/main/cpp/AudioDspEngine.h` (`DspStageMask`) |
| Concurrent DSP engines | 16 | `AudioDspEngine.h` (`DspEngineRegistry::kMaxEngines`) |
| Parametric EQ bands | 64 maximum | `DspParams.h`, `ParametricEQ.h` |
| EQ band modes in UI | 10 / 32 / 64 | `lib/data/audio/equalizer_manager.dart` |
| Biquad filter types | 8 | `DspParams.h` (`FilterType`) |
| Dynamic EQ bands | 8 | `AudioEffectsPlugin.kt`, `DynamicEqParamSet` |
| Multiband compressor bands | 4 | `MultibandCompressor.h` |
| Channel manager | 2–8 channels, 50 ms delay | `ChannelManager.h` |
| Convolution IR limit | 2,000,000 samples / 10 s | `MAX_IR_SAMPLES`, `IrBounds.h` |
| Reverb programs | 9 | `lib/domain/models/reverb_preset.dart` |
| Bundled AutoEQ profiles | 652 | `assets/eq_profiles/headphone_profiles.json` |
| DSD rates | DSD64–DSD512 | `DsdDecoder.h` |
| DSD→PCM ceiling | 768 kHz | `DsdDecoder.cpp` |
| DoP carriers | 176.4 / 352.8 / 705.6 kHz | `lib/data/audio/dop_encoder.dart` |
| USB wire formats | S16_LE / S24_3LE / S32_LE | `UsbAudioSink.h` |
| AAudio encodings | 16-bit / float / 24-packed / 32-bit | `AAudioAudioSink.java` |
| Now Playing themes | 11 | `theme_registry.dart` |
| Visualizer styles | 8 + Off | `audio_visualizer.dart` |
| Quran surahs bundled | 114 | `lib/data/quran/quran_uthmani_text.dart` |
| Quran reciter styles | 5 | `lib/domain/models/quran_mode_profile.dart` |
| Smart-playlist fields | 16 fields × 8 operators | `lib/domain/models/smart_playlist_criteria.dart` |
| Queue slots | 3 | `lib/features/queue/` |
| Remote source protocols | WebDAV, FTP, SMB (SMB Android-only) | `remote_provider_factory.dart` |
| Radio station cap | 500 user stations; 40 curated on demand | `radio_station_store.dart` |
| Party protocol frames | 13 frame types, 15 actions, 12 host-gated | `server/pulsr_party/protocol/protocol.go` |
| Party room size | 2–10, default 5 | `server/pulsr_party/config.go`, `party.go` |
| Locales | English, Arabic, Spanish | `lib/l10n/app_*.arb` |
| Test files | 833 `*_test.dart` | `test/` |

---

## 1a. Generated capability matrix

> Generated from `AudioCapabilityMatrix.current`. `test/architecture/audio_capability_matrix_test.dart` re-derives every value from the native/Kotlin sources and fails when this block is stale, so the table cannot drift from the build.

<!-- BEGIN GENERATED CAPABILITY MATRIX -->
| Capability | This build |
| :--- | :--- |
| Native DSP stages | 20 |
| Parametric EQ bands | 64 |
| Dynamic EQ bands | 8 |
| Multiband compressor bands | 4 |
| Channel manager | 2–8 channels, 50 ms max delay |
| Convolution IR | 2000000 samples / 10 s |
| DSD decode | DSD64–DSD512 |
| DoP carriers | 176400 / 352800 / 705600 Hz |
| Highest PCM rate | 768000 Hz |
| USB wire formats | s16_le / s24_3le / s32_le |
| AAudio encodings | int16 / float / i24_packed / int32 |
| Native DSD producer | available |
<!-- END GENERATED CAPABILITY MATRIX -->

---

## 2. Audio and DSP

### Equalization
- 10-band graphic, 32-band and 64-band parametric modes.
- Eight biquad types: peaking, low/high shelf, low/high pass, notch, band-pass, all-pass.
- Per-band gain ±15 dB, preamp ±15 dB, per-band solo and mute.
- 1,024-node arbitrary-response graphic EQ with optional linear phase (1,024-tap FIR, 2,048 FFT).
- Twelve bundled presets and a crest-aware recommended preamp.
- 652 bundled five-band headphone profiles, device-name matching, online AutoEQ search and user imports.

### Dynamics and tone
- 8-band dynamic EQ with threshold, ratio, attack, release, cut/boost modes.
- 4-band multiband compressor with Linkwitz-Riley crossovers.
- Lookahead true-peak limiter (4× oversampling, 48-tap polyphase, 0–20 ms lookahead).
- Dynamic bass with nine presets.
- Harmonic saturation: Tape, Tube and Class-A models with 4× oversampling.
- ReplayGain track/album with preamp and clipping protection.
- TPDF dither at 16-bit boundaries.
- Direct Volume Control in the float DSP path.

### Spatial and bass management
- Crossfeed: BS2B default, Chu Moy, Jan Meier and custom (200–700 µs delay).
- Stereo width 0–2 and a 3-band imager with bass mono.
- Loudness contour: up to +10 dB at 100 Hz and +4 dB at 8 kHz.
- Sub crossover: 60–150 Hz, Linkwitz-Riley 12/24 dB per octave.
- Panner is balance/mono only; platform spatializer state is surfaced separately.
- Channel manager for 2–8 channels with trim and up to 50 ms delay.

### Reverb and convolution
- Nine programs from Studio (0.35 s) to Cathedral (5.0 s) plus Custom IR.
- Partitioned FFT convolution with wet/dry, predelay, damping and cross-channel blend.
- Custom IR bounds enforced at load (sample count, duration, channels).

### Voicing and scripting
- DAC Voicing: Sharp linear-phase, Slow NOS-like and Minimum-phase, plus even-harmonic warmth.
- ViPER-DDC `.vdc` import with up to 256 sections and dual 44.1/48 kHz coefficient banks.
- LiveProg EEL/JSFX subset: 8,192 instructions, 2,048 memory slots, 8 sliders.

### DSD and SACD
- DSD64, DSD128, DSD256 and DSD512 decode to PCM at 44.1–768 kHz.
- DoP v1.1 framing at 176.4/352.8/705.6 kHz; DSD512 has no DoP carrier and falls back.
- Native DSD output is **not available** in this build. The UAC2 DSD alternate-setting probe, the `DSD_U32` sink path and the 1-bit packer are implemented and unit-tested, but no playback producer opens a DSD stream and pumps frames into it, so the transport resolver falls back to DoP or PCM with an explicit reason. DoP framing is likewise unverified on hardware (`dop_carrier_not_measured`).
- SACD ISO indexing, TOC parsing and DSF extraction before playback.

### Playback
- Gapless preload, linear/exponential crossfade, Automix BPM/key analysis (40–240 BPM, 24 keys).
- A-B loop, per-track delay, long-form bookmarks, silence skip and sleep timer with fade.
- ReplayGain, per-song EQ/volume/BPM overrides and per-device profiles.
- 9-layer ambient sound mixer, up to four concurrent layers.

---

## 3. Output and bit-perfect policy

### Output paths
- Media3 `PulsrAudioSink` with `DEFAULT → FLOAT → AAUDIO` mode selection and fallback.
- AAudio direct: 16-bit, float32, 24-bit packed and API 31+ exclusive 32-bit; maximum two channels; default 150 ms target buffer.
- USB-DAC exclusive path plus a native UAC2 isochronous sink (S16/S24_3/S32) that is marked experimental in source.
- 32-bit float DSP path with TPDF requantization at a 16-bit boundary.
- 18 target sample rates from 8 kHz to 768 kHz; bit depths 16/24/32.
- Bluetooth codec information and latency calibration, not codec switching.

### Bit-perfect verdicts
- Eligible: FLAC, ALAC, WAV, AIFF, DSD/DSF/DFF and integer PCM prefixes. WavPack, APE and TTA are recognized by the policy but lack bundled decoders in this build.
- Blocked: MP3, AAC, Opus, Vorbis, WMA, AC-3, live radio and Bluetooth-transcoded output.
- Ambiguous containers (`.m4a`, `.mp4`, `.ogg`, `.oga`, `.mka`, `.webm`) are allowed but report `source_codec_unconfirmed`.
- 32-bit float sources report `source_32bit_float_conversion_not_lossless`.
- `verified` requires matching source/output rate, sufficient output depth, no DSP/gain/speed/pitch/silence-skip/channel remap and unity digital volume.
- DoP is treated as a carrier and never reported as `verified` (`dop_carrier_not_measured`).

### Custody and diagnostics
- Chain-of-custody capture: 4,096 frames × 2 channels hashed at input and output.
- Exportable JSON certificate; `bitExactMeasured` only when both digests match.
- 19 live telemetry slots including limiter/dynamic-EQ/multiband gain reduction, RTF, thermal level, safety attenuation and EQ headroom.
- DSP inspector, A/B level-matched compare, xrun counters, safe mode and redacted diagnostics bundle.

---

## 4. Experience and interface

### Now Playing
- 11 themes: Classic Standard, Card Glass Overlay, Vinyl Circle, Minimalist Waveform, Vinyl Turntable Studio, CD Turntable, Retro Cassette Deck, Full-Bleed Waveform, Karaoke Lyrics Immersion, Clean Modern Flow and Milkdrop Visualizer.
- Theme Studio with palette, corner radius, ambient glow, live preview and JSON export/import.
- AMOLED pure black, light theme, high-contrast mode and scheduled light/dark switching.

### Visuals and karaoke
- Eight visualizer styles plus Off: Frequency Bars, Smooth Wave, Radial Pulse, Ambient Particles, 3D Terrain, Album-Art Reactive, Custom JSON and Milkdrop.
- Milkdrop GPU shader (`shaders/milkdrop.frag`) with Canvas fallback under GPU Saver; `.milk` and `.json` preset import.
- Karaoke: YIN live pitch, pitch highway, ±12 semitone shift, practice loop and 0–100 per-line scoring.
- Animated canvas artwork from Apple Music, Tidal and community sources where available.

### Lyrics
- LRC parsing, tap-to-seek lines, millisecond offset editor and lyrics editor.
- LRCLIB lookup when local lyrics are missing.
- Online translation and romanization into the app's current locale.
- Shareable lyric cards.

---

## 5. Library and organisation

- Reactive Drift SQLite database with eight library views: Songs, Downloaded, Albums, Artists, Favorites, Folders, Genres and Years.
- Folder tree and flat folder browser, hidden-folder exclusions and `.nomedia` compliance.
- In-place tag editor for title, artist, album, genre, year, track/disc number and comment; embedded artwork; batch editing; online metadata matching.
- Smart playlists with 16 fields, 8 operators, match-all/any, limits and live preview.
- Duplicate finder with metadata/duration passes and content checksum verification.
- Missing-artwork backfill from the iTunes Search API with rate limiting and backoff.
- Library statistics, artwork grid, favorites and recents.
- Three persisted queue slots with drag reorder, add-next/add-last and save-as-playlist.
- CUE sheet playback for single-file album images.
- Internet radio: 40 curated stations imported on demand, 500-station user cap, live radio-browser directory across three mirrors and M3U import.
- Remote sources: WebDAV, FTP and SMB (Android-only), with byte-range reads, local cache index, local HTTP stream server and 100-source cap.
- DLNA/UPnP casting: SSDP discovery, AVTransport control, position polling and local media HTTP server. Google Cast discovery over mDNS.

---

## 6. Pulsr Party

- Go WebSocket server with protocol v1: 13 frame types and 15 control actions, 12 host-gated.
- Six-character room codes, nickname join, host promotion, kick and 2–10 members (default 5).
- Monotonic server clock and NTP-style client offset from a 12-sample window; minimum-RTT sample wins; 120 s TTL and 10 s ping loop.
- Host-only or democratic queue; autoplay supplier survives host leave.
- Host speaker-delay alignment and seek/watch deadbands.
- Self-hostable server (`server/pulsr_party/`); default hosted endpoint is overridable.

---

## 7. Quran Mode

- All 114 surahs of Tanzil Uthmani 1.1 bundled offline (1.5 MB XML plus Dart mirror).
- Surah index, Mushaf page reader and reading-only mode.
- Five reciter styles: Murattal, Mujawwad, Tarawih, Memorization and Sleep.
- Hifz blind recall, ayah repeat (single or range), tempo at 0.5×/0.75×/1.0×.
- Mosque ambience convolution reverb and vocal warmth.
- Bookmarks, resume prompts and recitation auto-detection.

---

## 8. Android integration and tools

- Home-screen widget with five layouts and nine actions (play/pause, prev/next, favorite, shuffle, repeat, queue, open, main).
- Quick Settings playback tile and search-suggestions provider.
- MediaSession, lock-screen controls and foreground media playback service.
- File intents: `VIEW`, `SEND`, `SEND_MULTIPLE`, `MUSIC_PLAYER` and `MEDIA_PLAY_FROM_SEARCH`.
- Assistant bridge with four launcher shortcuts and five resolver intents.
- Command palette (27 commands) and 13 keyboard shortcuts on desktop/tablet shells.
- Spoken track announcements via Android TTS with delay, volume, ducking, cast and bit-perfect gates.
- System behaviour controls: audio focus, USB release policy, background USB close, volume rocker track switch, linear/log volume and fade-out on pause.
- USB ergonomics: per-DAC VID/PID quirk profile, settle silence, force 16-bit, alt-setting reset, HID claim and transfer size.
- Diagnostics: device/output summary, DSP stages, xrun counters, safe mode, self-test and redacted bundle export.
- Audio profiles: capture/apply/share/import complete DSP snapshots with ten rolling backups.
- In-app update check against GitHub Releases.

---

## 9. Online / Plus and integrations

- Pure build removes `INTERNET`, network state, local-network and data-sync permissions at manifest level.
- Plus build (`ENABLE_YTM=true`) adds YouTube Music search, browse, stream and download.
- InnerTube `WEB_REMIX` search; Rhino signature and `n`-transform solving with cached rules; PoToken/visitor tokens; `signatureTimestamp`; authenticated `WEB` fallback for age-restricted tracks.
- Geo/egress block classification and per-signal circuit breakers.
- Three concurrent downloads, four-way chunked fetch, Range resume, 403 re-resolution, cancel tokens and a foreground service.
- Three quality tiers: 256, 128 and 64 kbps.
- SOCKS5/HTTP proxy pool, DNS-over-HTTPS, cellular failover, Wi-Fi-only and offline-only modes.
- SponsorBlock with six categories and a 256-entry LRU cache.
- Scrobbling to Last.fm, ListenBrainz, Libre.fm and custom webhooks, with offline replay and a stats screen.
- Discord Rich Presence via a built-in Gateway v9 client.
- Optional Firestore sync plus local JSON backup export/import; Firestore is hard-off in Pure builds.
- Device profiles, four automation triggers (Bluetooth, headphones, USB DAC, charging), theme scheduler and hearing-safety dose tracking (EN 62368-1 / WHO-ITU H.870).
- Bluetooth latency calibration from a tap test, round-trip probe and ten-codec table.

---

## 10. Platforms and explicit limits

- Android 9+ (API 28) through target SDK 37 is the supported platform.
- iOS, Windows, macOS and Linux contain stock Flutter runners only; native audio and packaging are not shipped.
- The web target is a shell only.
- Sinc playback resampling is delegated/unsupported: `hasSincResampler = false`; enabling returns `DSP_UNSUPPORTED`.
- AAudio is limited to two channels; speed, pitch and silence skip suspend AAudio to AudioTrack.
- Android `Equalizer`/`LoudnessEnhancer` do not affect AAudio output.
- The native UAC2 direct sink is marked experimental in source.
- APE, WMA, TTA, TAK, WavPack, MPC, MOD, IT, XM and S3M are recognized but not decodable in this build.
- MQA is core unfold only; no authenticated render is claimed.
- No blind A/B/X UI ships; `DspAbxHelper` is an unreferenced domain helper.
- The party server is required for group listening; the default is overridable and self-hostable.

---

## 11. Source map

| Area | Path |
|---|---|
| Native DSP | `android/app/src/main/cpp/` |
| Dart audio | `lib/data/audio/` |
| Bit-perfect policy | `lib/data/audio/bit_perfect_chain.dart`, `lib/core/constants/audio_feature_info.dart` |
| Custody | `lib/core/services/chain_of_custody_service.dart`, `CustodyVerifier.h` |
| Player UI | `lib/features/player/presentation/` |
| Themes | `lib/features/player/presentation/themes/` |
| Library | `lib/features/library/`, `lib/data/repositories/` |
| Quran | `lib/features/quran_mode/`, `lib/data/quran/` |
| Party server | `server/pulsr_party/` |
| Remote sources | `lib/features/remote_sources/` |
| DLNA | `lib/features/dlna/` |
| Tools | `lib/features/{audio_profiles,diagnostics,usb_tools,system_behavior,announcements,assistant}/` |
| Online | `lib/core/services/ytm_*`, `lib/features/downloads/` |
| Localization | `lib/l10n/app_{en,ar,es}.arb` |
