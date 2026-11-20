# EQ and DSP device validation

Run this after `:app:testNative` is green, on a release-equivalent Android
build. Use the same lossless stereo reference track and keep output volume
below 70% for every route.

## Common checks

- Enable EQ, change each band, then relaunch the app: the saved curve must
  return without a pop, channel swap, or changed playback position.
- Toggle every enabled DSP stage on and off twice: no audible click, drop-out,
  or stale control state is acceptable.
- Switch profiles while playing and while paused; confirm the final selected
  profile, not an earlier selection, is the one audible after two seconds.
- Enable bit-perfect output when available: DSP and non-1.0x rate controls
  must explain that they are unavailable; disabling bit-perfect must restore
  the previous DSP state.

## Wired headphones

- Verify EQ, crossfeed, reverb, saturation, dynamics, limiter, and stereo
  balance independently.
- Confirm crossfeed stays disabled on built-in speaker, car, HDMI, and other
  non-headphone routes while the user preference remains saved.

## Bluetooth

Run the common checks for SBC/AAC and, where hardware supports it, LDAC.

- Reconnect the device during playback and confirm the chain resynchronizes.
- Check that codec compensation changes only the active engine curve, not the
  stored user EQ values.
- Confirm no audio glitch occurs while switching codec quality or route.

## USB DAC

- Test 44.1, 48, and the DAC's highest supported sample rate.
- Connect/disconnect while playback is active; verify session reattachment,
  latency compensation, and no stale DSP state.
## DSP Inspector and Reliability Diagnostics

- Open the DSP Inspector sheet during active playback:
  - Confirm active format chips display Sample Rate (e.g. 96.0 kHz), Bit Depth (e.g. 24-bit), Codec (e.g. FLAC / LDAC), and Pipeline Latency (e.g. 128 frames / 2.9 ms).
  - Verify Bit-Perfect state indicator reflects active bypass correctly.
  - Tap "Resync DSP": verify the button is disabled while running, surfaces an accessible snackbar upon completion or failure, and immediately refreshes the active diagnostics.
  - Inspect Reliability Telemetry counters: verify Native Rejections, Bridge Failures, Route-Resync Failures, Session Reattach Failures, and Auto-Degrade activations/recoveries start at zero or accurately reflect fault counts without exceeding 1,000,000.
  - Induce a simulated bridge error and confirm the displayed error string redacts all local storage paths and auth tokens.

## Quran Mode and Metadata Validation

- Play regular music tracks: confirm the Quran Mode sheet displays the clean "No Quran Metadata" empty-state card; ordinary bookmarks and per-track EQ preferences remain completely unaffected.
- Play catalog Quran tracks (with valid `QuranMetadata`):
  - Confirm Surah name, Surah number, reciter, and Ayah range display accurately without inferring from filename.
  - Tap "Save Quran Bookmark": verify notification surfaces Surah and Ayah; confirm bookmark persists and appears as a resume action.
  - Tap resume action: confirm playback seeks to the bookmarked Ayah position.
  - When accurate Ayah timings are present, test Ayah Repeat modes (Repeat Off, Repeat Ayah, Repeat Range) and verify boundary enforcement.
  - Verify all five Quran reciter styles (Murattal, Mujawwad, Tarawih, Memorization, Sleep) and the 0.5x/0.75x/1.0x tempo steps remain isolated from ordinary player settings.

## DSD, DoP and USB Exclusive Checks

- With a compatible USB DAC, select each DSD output mode (PCM / DoP / Native) and confirm the app either opens the requested path or reports the explicit fallback reason.
- Verify DoP carrier rates are limited to the DAC-advertised 176.4 / 352.8 / 705.6 kHz and that DSD512 does not claim a DoP carrier.
- Enable USB-DAC exclusive output, confirm unity gain in bit-perfect mode, then switch the track rate and verify the stream reopens at the new rate.
- Run the chain-of-custody capture on a lossless source and confirm the certificate only reports `bitExactMeasured` when input and output digests match.
- Repeat with a lossy source, an ambiguous `.m4a`/`.ogg` container and a 32-bit float source; confirm the verdict is blocked or `unverified` with the expected reason code.

## Remaster, Dedicated FIR & Multichannel Validation

- **Remaster**: Enable Remaster follow-rate upsampling (x2/x4/x8). Verify the sink reopens at the multiplied rate bounded by DAC capability (step-down 8-4-2-1). Confirm bit-perfect badge is disabled (`OutputVerdict.isBitPerfect = false`) when Remaster is active.
- **Dedicated FIR**: Select a headphone profile with FIR enabled. Confirm a 100% wet correction stage is inserted (`STAGE_FIR`), independent from Reverb. Verify frequency response matches native PEQ within $\pm 0.1$ dB across 20 Hz – 20 kHz.
- **Multichannel Bass Management**: On 5.1 and 7.1 surround systems, confirm LFE redirection filter (Linkwitz-Riley 12/24 dB/oct) routes sub-bass correctly and channel trim/delay lines persist across app restarts. Confirm trim/delay panel is hidden on stereo ($\le 2$ channels).
- **True Low-Power Mode**: Toggle Low-Power Bypass. Verify the DSP processing thread is completely skipped only when all DSP stages (EQ, Preamp, Remaster, HRTF) are off. Confirm server-side interlock rejects bypass if any DSP stage is engaged. Verify per-stage mAh/h battery telemetry renders in the inspector.

## Network & Streaming Device Checks

- **Cast Transport**: Connect to a Google Cast receiver. Verify Play, Pause, Stop, Seek slider, and Prev/Next transport buttons work reliably and update remote receiver state. Verify `durationMs` is accurately propagated.
- **Subsonic Caching**: Browse a Subsonic / Navidrome library. Verify cover art URLs use canonical cache keys (`getCoverArtCacheKey`) without ephemeral auth salts/tokens, preventing image reload flickers. Test rapid search typing and confirm 300 ms debounce timer prevents out-of-order queries.
- **UPnP / DLNA LRU**: Browse and control a DLNA MediaRenderer. Verify `UpnpDeviceDescriptionCache` updates recency on cache hits and evicts the least recently used entries when capacity is exceeded.

## FFT Loopback & Harmonic Distortion Gate

- Run the high-dynamic-range Kaiser FFT harness on recorded loopback captures:
  ```bash
  python scripts/hil/measure_fft.py input.wav --mode full --out scratch/fft/report.md
  python scripts/hil/measure_fft.py input.wav --mode ccif --out scratch/fft/ccif_report.md
  ```
- Verify:
  - 24-bit THD+N $\le -100$ dBFS (ideal target $\le -115$ dBFS).
  - 16-bit THD+N $\le -90$ dBFS.
  - CCIF 19+20 kHz twin-tone IMD2 / IMD3 $\le -95$ dBFS.
  - Crosstalk returns `not_measurable` on dual-driven/mono inputs rather than false pass/fail metrics.
  - Harness derives non-zero exit code on threshold failure.

## Automated Android Integration Tests

- Execute the automated instrumentation suite on a physical device or emulator:
  ```bash
  cd android && ./gradlew connectedAndroidTest
  ```
- Validates:
  - Audio session recreation and ID re-binding.
  - Output route changes (wired, speaker, Bluetooth, USB DAC).
  - Bluetooth disconnect/reconnect chain resynchronization.
  - USB DAC connect/disconnect format handling.
  - Bit-perfect enable/disable restoration.

## Evidence to capture for a failure

- Device model, Android version, output route, codec/sample rate/bit depth.
- Reproduction steps and whether the failure is audible, visual, or both.
- Exported DSP debug report and a redacted logcat around the route/profile
  change; never include account tokens or local media paths.
