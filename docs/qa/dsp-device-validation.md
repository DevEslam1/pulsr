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
  - Verify Quran reciter style tuning (Murattal, Mujawwad, etc.) and learning speed remain isolated from ordinary player settings.

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
