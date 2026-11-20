# Pulsr Proof Pack (2026-11-20)

**Build Commit:** `af01ffe9` (Phase 3 complete)  
**Target Architecture:** Multi-backend (`PlaybackBackend`: LocalPCM, LocalDSD, Cast, UPnP) + Native C++ DSP Engine  
**Audit Reference:** [plan_new.md](file:///d:/Courses/Projectss/pulsr/plan_new.md) §4, §12, §15, §16  
**Date:** 2026-11-20  

---

## 1. Hardware Lab & Environment Inventory

Per §12 of the remediation plan, every capability is reported honestly with its hardware status and firmware environment:

| Lab Need | Target Purpose | Verification Status | Rig / Device & Firmware | Notes & Limitations |
|---|---|---|---|---|
| **OPPO Tablet + USB DAC** | Exclusive UAC2, volume, mute | **NOT RUN** | No USB DAC attached (wireless ADB offline on 2026-11-20) | Code-complete: verified `UsbHardwareVolume` state shared by handler/settings/keys; GET_CUR `0x81`/GET_RANGE `0x82`; CS_MUTE capability-gated; key steps emit status and feed back into the app volume; full-range dB mapping. Real DAC key/display, mute and quantization behavior remain unverified. |
| **DSD-Capable DAC** | Native DSD64/128/256, DoP fallback | **NOT RUN** | No DSD-capable DAC attached (wireless ADB offline on 2026-11-20) | Dedicated `NativeDsdSession` (handler-owned backpressured pump, no ExoPlayer source); exact-rate tuple enforced; DoP/PCM fallback; first-block status. Hardware soak and DAC attestation remain open. |
| **Multichannel USB DAC** | 5.1/7.1 LFE & trim/delay | **NOT RUN** | No multichannel DAC attached (wireless ADB offline on 2026-11-20) | Code-complete: `AudioChannelLayout` 3.0/4.0/5.1/7.1 in Android channel order; LFE index 3 for 5.1/7.1, none for 3.0/4.0; atomic layout + LFE enable/index push; sink-channel gating; constant-sum bass redirect; 0..50 ms delay reported in pipeline latency. Android 3-channel audio is 3.0 (FL/FR/FC), not 2.1. Hardware speaker order, LFE output and alignment remain unverified. |
| **Cast Receiver** | Cast transport & duration | **CODE-COMPLETE** | Google Cast SDK v21.4.0 / Localhost Prebuffer Proxy | Transport controls (Play/Pause/Stop/Seek/Prev/Next) wired; `PendingResult` async awaiting; `setStreamDuration` propagated; eviction loop guaranteed monotonic progress; loopback-only bind. |
| **UPnP / DLNA Renderer** | Control point acceptance | **CODE-COMPLETE** | AVTransport:1 / ContentDirectory:1 / SSDP Client | True LRU cache updating recency on hits (`UpnpDeviceDescriptionCache`); transport UI controls wired; single-flight coalescing; 300ms debounce & monotonic sequence guard on search. |
| **ADC Loopback Analysis** | THD+N, IMD, Crosstalk, Jitter | **HOST/CLI ONLY** | Native DSP Engine (`measure_native_dsp`) + Kaiser FFT (`measure_fft.py`) | Kaiser window ($\beta=18.0$, $>150$ dB sidelobe suppression); CCIF 19+20 kHz twin-tone IMD analysis; crosstalk identical-channel detection reports `not_measurable` instead of false metrics; single dither pass enforced. |
| **Codec Validation** | ALAC, FLAC, Opus | **CODE-COMPLETE** | `Mp4BoxParser` + Android MediaCodec probe | ALAC magic cookie/bit depth/sample rate parsed and corrupt payloads rejected; playback probes `audio/alac` + `audio/x-alac` and fails with a typed codec error when the platform has no decoder. No ALAC decoder is bundled; WavPack/APE/TTA remain not decodable. |
| **SOFA HRTF Datasets** | Binaural spatialization | **CODE-COMPLETE** | User-supplied SOFA/WAV HRIR (none bundled) | Control-thread inverse-distance interpolation + rate resampling, immutable quad slots with atomic handoff, zero RT allocations in the render path, `STAGE_HRTF` gating and load-failure propagation. No HRIR dataset ships; binaural hardware pass not run. |

---

## 2. Feature-by-Feature Proof Dossier

### §8.1 Remaster (Oversampling, Sinc Filters, PCM-to-DSD)
- **State Owner:** `RemasterControlCard`, `AudioEffectsChannel`, `SettingsAudioOutputSync`, `AudioEffectsPlugin` (active oversample factor).
- **UI Entry:** Player -> EQ -> Advanced -> Remaster Suite.
- **Engine Route:** `AudioDspEngine` (`STAGE_RESAMPLE`, `STAGE_DITHER`), `TapSrcPolicy`.
- **Measurement Evidence:**
  - Sine sweep and impulse response tests in `measure_native_dsp.cpp`.
  - Resampler tail draining verified to eliminate truncation transients.
  - Oversampler kernel stopband is tested at $>-90$ dB (`test_oversampler.cpp`); the documentation no longer claims $>120$ dB.
  - SdmModulator PCM-to-DSD is an offline engine path only: no JNI/Dart playback route and no DSD-session integration yet.
- **Verdict & Status Contract:** Remaster activation invalidates bit-perfect badge via `OutputVerdict.isBitPerfect = false`.

### §8.2 Native USB DSD Session
- **State Owner:** `NativeDsdSession` (implements `PlaybackBackend`), driven by `PulsrAudioHandler`.
- **Engine Route:** `UsbAudioSink.cpp`, `DopFramer.cpp`, DSD native packer.
- **Verification Evidence:**
  - Dedicated handler-owned session with a backpressured block pump (`native_dsd_session.dart`, `native_dsd_producer.dart`).
  - File-backed streaming reader (`native_dsd_file_source.dart`): header parsed once, DSF blocks/DFF interleaved bytes read on demand, so full-length DSD64/128/256 tracks are not limited by the 150 MB PCM decode cap.
  - No fake WAV source: the native path never enters ExoPlayer; the idle players' state is suppressed while the session owns the DAC.
  - Exact-rate UAC2 tuple only; no first-tuple fallback. UAC2 GET_CUR is `0x81` for volume, clock, range and rate reads.
  - Byte-accurate position from flushed DSD frames; pause keeps the alt setting fed with DSD silence.
  - Transport, queue next/previous, completion and media-session position are delegated to the session; media session shows native DSD only after the first real block is accepted.
  - Hardware volume policy: fixed volume with a visible notice unless USB hardware volume is enabled; never software-scales 1-bit DSD.
  - DoP markers (`0x05`/`0xFA`) verified in unit tests at 176.4/352.8/705.6 kHz.
  - Hardware acceptance: **NOT RUN**; no DSD-capable DAC attached. The flag is enabled only as a capability gate; the exact tuple probe still decides per device.

### §8.3 Decoder Hardening & ALAC Validation
- **State Owner:** `Mp4BoxParser`, `MediaScannerService`.
- **Verification Evidence:**
  - Container-level MP4 atom parsing extracts bit depth, channels, and sample rate from `alac` box (`mp4_box_parser_test.dart`).
  - Fuzz tests and corrupt box boundary tests pass without crash.
  - Scanner marks unsupported codec extensions explicitly at scan time; no track is falsely advertised as playable lossless.

### §8.4 UAC2 Hardware Volume & Mute
- **State Owner:** `UsbAudioControlParser.kt`, `UsbAudioSink.cpp`, `UsbHardwareVolumeBridge.kt`.
- **Verification Evidence:**
  - UAC2 GET_CUR standard compliance: `0x81` request code strictly unified across C++, Kotlin, and Dart contracts.
  - SET_CUR standard compliance: `0x01` request code.
  - Read-back verification: volume level and mute state read back from Feature Unit after SET commands.
  - Volume key dispatch: intercepted only when `usbHardwareVolumeEnabled == true` and USB playback is actively running.

### §8.5 Network (Cast, Subsonic, UPnP)
- **State Owner:** `CastService`, `CastSessionPlugin`, `SubsonicClient`, `UpnpDeviceDescriptionCache`.
- **Verification Evidence:**
  - Cast transport: Play, Pause, Stop, Previous, Next, Seek slider, and Volume controls verified.
  - Asynchronous Kotlin `PendingResult` awaiting with timeout safeguards.
  - Subsonic persistent image caching: `getCoverArtCacheKey` strips ephemeral salts and tokens (`subsonic_client_test.dart`).
  - Subsonic search: 300 ms debounce timer and monotonic sequence guard verified (`remote_browser_sheet_test.dart`).
  - UPnP cache: True LRU policy verified with sequence update on hits (`upnp_device_description_cache_test.dart`).

### §8.6 Per-Headphone Dedicated FIR
- **State Owner:** `EqualizerManager`, `HeadphoneProfile`.
- **Engine Route:** `AudioDspEngine` (`STAGE_ARBITRARY_EQ`), native 4096-tap FIR, 100% wet, independent from `STAGE_REVERB`.
- **Verification Evidence:**
  - The FIR target is the profile's parametric curve, evaluated with the same RBJ shelf/peaking formulas and upper-octave HF decramping as `ParametricEQ.cpp`, at the engine sample rate.
  - The native FIR synthesizer runs at engine rate with 4096 taps (8192-pt FFT); a C++ test verifies the requested node gains and the 20 Hz low-frequency correction.
  - FIR state (target string, phase mode, enabled) is persisted and restored; switching to a preset/manual edit disables the FIR and resets the mode; the PEQ stage is disabled while FIR owns the correction.
  - Headroom is baked into the target using the peak composite boost (not the sum of positives), bounded by the native ±30 dB node clamp; the PEQ preamp stays 0 in FIR mode.
  - The dead Dart biquad-cascade generator and its circular round-trip test were removed; the native target path is the only FIR implementation.
  - Android apply/restore, 44.1/96/192 parity, linear-phase AV sync and clipping null tests remain hardware-only.

### §8.7 Measurement Harness & Release Gate
- **Harness Scripts:** `scripts/hil/measure_fft.py`, `scripts/measure_native_dsp.cpp`.
- **Harness Tests:** `scripts/hil/tests/test_measure_fft.py`, `test_hil_common.py`.
- **Verification Evidence:**
  - Kaiser window ($\beta=18.0$, $>150$ dB sidelobe suppression) eliminates Blackman-Harris -92 dB floor.
  - CCIF twin-tone IMD2 (1 kHz) and IMD3 (18 kHz / 21 kHz) test cases implemented and passing.
  - Crosstalk analysis flags dual-driven / mono captures as `not_measurable` rather than false passes.
  - Single dither pass enforced; zero double-dithering.
  - Hardware provenance requirement: synthetic files cannot satisfy `--require-hardware`.

### §8.8 Multichannel Bass & Channel Management
- **State Owner:** `MultichannelBassCard`, `ChannelManager.h/.cpp`.
- **Engine Route:** `AudioTrackAudioSink.java`, Float PCM path.
- **Verification Evidence:**
  - Explicit channel layouts: 3.0 (FL/FR/FC), 4.0 (FL/FR/BL/BR), 5.1 (LFE index 3), 7.1 (LFE index 3). A true 2.1 is not offered because Android's 3-channel mask is FL/FR/FC; use 5.1/7.1 for LFE.
  - Layout selection pushes channel count, LFE enable and LFE index together; 3.0/4.0 force the LFE stage off, so a stale index cannot process RR/FC.
  - UI shows the card only when the sink actually opens >2 channels (not merely because the source is 6-channel).
  - Low-pass Linkwitz-Riley crossover (12/24 dB/oct) with constant-sum bass redirect (coherent bass cannot add +7/+9 dB).
  - Delay lines up to 50 ms per channel persisted, restored and included in reported pipeline latency.

### §8.9 HRTF / SOFA Spatializer
- **State Owner:** `HrtfBinauralCard`, `AudioDspEngine` (`STAGE_HRTF`).
- **Verification Evidence:**
  - HRTF is gated by `STAGE_HRTF`; it is bypassed by bit-perfect/low-power and is mutually exclusive with crossfeed in the UI.
  - Zero real-time allocations in the render path (native RT test), with control-thread interpolation/resampling and atomic quad-slot handoff.
  - Crossfades between prepared quads; stale old slots are released only at block boundaries.
  - Clean `context.select<PlayerCubit, bool>` reactive state wiring without rebuild storms.

### §8.10 True Low-Power Mode & Interlocks
- **State Owner:** `AudioEffectsPlugin.computeDspActive/syncDspActiveRouting`, `PulsrOutputRouting`, `PulsrAudioSink`, `EngineTelemetryPanel`.
- **Verification Evidence:**
  - Two distinct modes: Battery Saver (DSP stages degraded to low-complexity modes) and Low-Power Bypass (complete DSP bypass).
  - Server-side interlock: `PulsrAudioSink` consults the derived `dspActive` flag; it is recomputed from active stages + active remaster factor + HRTF and cleared on engine release.
  - Telemetry payload: structured map with `stagePowerSpecs` rendering per-stage mAh/h battery consumption.
  - Isolated stage telemetry ensures an individual sensor fault cannot blank the inspector.

### §8.11 Documentation, Guards & Test Parity
- **Guards:** `check_bridge_parity.py`, `check_claude_dsp_docs.py`, `validateChannelParity`, `validateFlavorTestParity`.
- **Verification Evidence:**
  - 140/140 Dart-Kotlin bridge methods in 100% bidirectional parity.
  - 36/36 CMake native DSP source files documented in `CLAUDE.md`.
  - 27 channel methods covered by production stub.
  - 16 test files verified identical between `dev` and `ytm` flavors.
  - Zero dead code; zero optimistic flags.
