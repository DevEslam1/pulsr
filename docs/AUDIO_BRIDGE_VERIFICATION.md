# Bit-perfect and native bridge verification

Verified on 2026-10-03. This audit fixes the identified software defects; it does
not certify every device or establish a 10/10 hardware rating.

## Corrections

- Correct Android 14 mixer API names and signatures. Select only advertised
  bit-perfect mixer attributes and reject a requested rate/depth mismatch.
  Allow OFF without requiring a supported mixer-attribute list.
- Correct the JNI escaping of the `just_audio` package name, restoring AAudio
  native method resolution. The smoke runner checks generated JNI headers
  against the actual library exports before running.
- Require exclusive sharing for an exclusive request, including reconnection;
  remove shared fallback and enforce unity gain in exclusive PCM/DoP mode.
- Keep paused streams paused during flush. Preserve playback counters across
  recovery, and handle heap buffers and partial writes correctly.
- Rebuild the Media3 renderer when switching AAudio or float output while
  retaining the queue, position and playback settings.
- Preserve PCM16 and float bytes during native DSP bypass, including bypassing
  Java gain ramps. Correct PCM16 quantization at unity gain.
- Process high-resolution PCM before Media3's float sink, whose float pipeline
  otherwise skips the custom DSP processor. Preserve pending output over partial
  delegate writes so retries do not process a block twice.
- Serialize settings transitions and commit state after native acknowledgement.
  Strict OFF clears hardware mode and bypass; failed OFF retains enabled state.
  Restore DSP after route loss and clear unsupported saved strict settings.
- Reject conflicting DVC settings on AAudio/bypass paths. Keep failure reasons
  and capability changes visible, and include rate, depth and route in target
  format caching. Cache active-player output preferences only after acceptance.

## Completed validation

| Check | Result |
| --- | --- |
| Focused Flutter regression tests | 72 passed |
| Focused Dart analysis | No issues |
| Android Kotlin and vendored Java compilation | Passed |
| Production native builds | Passed for arm64-v8a, armeabi-v7a and x86_64 |
| Native bypass suite | Passed, including repeated ON/OFF and stale DoP state |
| Full native DSP suite | Passed, including snapshot races and allocation checks |
| Native mutation stress test | 5,541,519 swaps in 19,977 ms; no NaN/Inf |
| AAudio Java/JNI runtime | Open/write/play/pause/flush/close and bounds passed |
| PCM quantization | All 65,536 PCM16 values checked |
| Actual native DSP processor | PCM16 ON/OFF/ON/OFF and exact float bypass passed |
| Actual AAudio Media3 sink | Partial/heap writes and playback controls passed |
| Production float sink wrapper | Float/PCM24/PCM32 toggles and partial retries passed |

The JNI and C++ runtime checks ran on a temporary x86_64 Android emulator, using
the production native library. The four standalone JNI harnesses are regression
checks, not a full Flutter application playback test. The emulator cannot prove
successful USB exclusive negotiation; it verifies that a rejected exclusive
request never silently becomes shared output.

Logs are in `build/audio-audit-*.log`. The reusable emulator smoke runner is
`scripts/run_audio_bridge_smoke.ps1`; supply `-SdkRoot`, `-JdkRoot`, and
`-NativeLibrary` pointing to the current x86_64 production library. Its default
device serial is `emulator-5554`, and its C++ runtime is for x86_64.

## Physical-device acceptance still required

Use an Android 14+ device and a USB DAC advertising bit-perfect mixer support.
Repeat ON/OFF/ON during playback and while paused, seek and change tracks, switch
AAudio/float output, and unplug/replug the DAC. Verify truthful switch state,
restored DSP on OFF, preserved playback state, and actionable failure reasons.

Check 44.1/48/96/192 kHz at each depth actually supported by the DAC. Verify
the negotiated stream and DAC rate, exclusive sharing, unity output, and a
digital loopback comparison to the decoded source. Check unsupported formats
and routes as well as successful ones. Verify DoP marker integrity and DAC lock
with compatible hardware.

Exact byte preservation inside the DSP bypass does not establish end-to-end
bit-perfect output. Decoder conversion, playback speed, channel mapping,
AudioTrack format and device behavior also matter. In particular, converting
32-bit integer PCM to float can lose low-order bits; the PCM32 wrapper test
verifies conversion and toggle behavior, not exact preservation of every
32-bit integer value. No end-to-end 32-bit integer or DoP certification is
claimed by this audit.
