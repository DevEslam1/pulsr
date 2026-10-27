# Pulsr — Native Audio Test Matrix

**Date:** 2026-10-27
**Scope:** multichannel channel management, DSD512, UAC2 hardware volume
**Host:** Windows, Clang 20.1.3, CMake 4.x, Ninja; DSP sources compiled with the production `-O3 -std=c++20 -fno-strict-aliasing` flags.

> **Status:** DSD512 and the multichannel trim/delay engine are implemented and host-tested. UAC2 hardware volume is **not implemented** here: it needs an Android USB host connection and a UAC2 DAC to verify control-transfer behaviour. The legacy composite `test_native_all` has one pre-existing platform-sensitive dither tolerance failure; every other host test is green.

---

## 1. Host suite result

```text
ctest --test-dir build/testNativeHost --output-on-failure
13/14 tests passed
```

| Test | Result | Notes |
|---|---|---|
| `test_native_all` | **FAIL** | Legacy composite; stops at the dither max-deviation assertion (>2 LSB). Pre-existing; needs a separate dither audit, not a tolerance bump. |
| `test_dsp_stress` | pass | |
| `test_bypass_transparency` | pass | |
| `test_reverb_*` (3) | pass | |
| `test_dsd_dc_soak` | pass | |
| `test_dsd_decoder_correctness` | pass | Includes the new **DSD512 → 768 kHz** case. |
| `test_limiter_true_peak` | pass | Latency expectation now includes `LookaheadLimiter::FILTER_DELAY`. |
| `test_sinc_resampler` | pass | |
| `test_dop_framer` | pass | |
| `test_resampler_polyphase` | pass | |
| `test_channel_manager` | **pass (new)** | Trims, delays, 8-channel boundary, bypass. |
| `test_dsp_effects` | pass | Saturation transition tolerance corrected to 0.15 (natural 440 Hz slope + harmonics). |

**Reproduce**

```powershell
cmake -S android/app/src/test/cpp -B build/testNativeHost -G Ninja `
  -DCMAKE_BUILD_TYPE=Release `
  "-DCMAKE_CXX_COMPILER=C:/Program Files/Windhawk/Compiler/bin/clang++.exe" `
  "-DCMAKE_MAKE_PROGRAM=$(Get-Command ninja).Source"
cmake --build build/testNativeHost --parallel
ctest --test-dir build/testNativeHost --output-on-failure
```

---

## 2. Multichannel channel manager

**Code:** `android/app/src/main/cpp/ChannelManager.{h,cpp}`
**Stage:** `STAGE_CHANNEL_MANAGER = 1 << 18`
**Params:** `ChannelManagerParamSet { enabled, channelCount (2–8), trimDb[8], delayMs[8] }`

What it does:

- Per-channel gain trim (`-30…+12 dB`) with a 20 ms ramp.
- Per-channel delay (`0…50 ms`) via preallocated ring buffers.
- Accepts 2–8 interleaved channels. Channels beyond the declared layout pass through untouched.
- Runs **after** EQ/dynamics/DVC and **before** the lookahead limiter, so a boosted surround channel is still caught by the brickwall.
- Delay buffers are preallocated for 768 kHz / 50 ms in the constructor. This was required by the RT-allocation test: a sample-rate change must not allocate on the audio thread.
- Bass management is deliberately **not** implicit. Routing bass to LFE needs a channel-layout contract (LFE index, satellite crossover, distances); that is a separate stage.

**Verified by `test_channel_manager`:**

| Case | Result |
|---|---|
| -6.0206 dB on ch1 → 0.25 from 0.5 | pass |
| 10 ms delay on ch2 → silent before 480 frames, 0.5 after | pass |
| Disabled → bit-transparent | pass |
| 8-channel buffer with 6-channel layout → ch6/7 untouched | pass |

**Still required for a product 10/10:** JNI setter, Kotlin facade, Dart channel, settings UI, and a real 5.1/7.1 DAC loopback test. The engine and host proof exist; the control surface does not.

---

## 3. DSD512

**Native:** `DsdDecoder::DsdRate::DSD512 = 512` (22.5792 MHz).
**Dart:** `DsdDacCapabilities.dsd512`, `supportsRate(512)`, decode target `768000 Hz`; DoP remains capped at DSD256 because there is no standard 1411.2 kHz DoP carrier.

**Host test:** 0.05 s of DSD512 silence decoded to **38,400 PCM frames at 768 kHz**, all finite. Decimation ratio `22579200 / 768000 = 29.4` verified.

**Dart tests:** `test/data/audio/dop_dsd_test.dart` — 14/14, including “DSD512 is a native PCM capability, not a DoP carrier”.

**Still required:** a USB DAC that advertises 768 kHz PCM (or native DSD512) for an end-to-end hardware pass.

---

## 4. UAC2 hardware volume — pending

Not implemented in this pass. The correct UAC2 request shape is:

| Field | Volume | Mute |
|---|---|---|
| `bmRequestType` | `0x21` (host→device, class, interface) | `0x21` |
| `bRequest` | `0x01` SET_CUR | `0x01` |
| `wValue` | `(0x01 << 8) | channel` (Volume Control) | `(0x02 << 8) | channel` |
| `wIndex` | interface number | interface number |
| data | int16 LE, 1/256 dB steps | uint8 0/1 |

A correct implementation must read `GET_MIN/GET_MAX/GET_RES` first (0x81/0x82/0x83) and map the UI percentage into the DAC's actual dB range; hard-coding 0…-60 dB will be wrong on many devices. It also needs a hardware mute path separate from software attenuation. This cannot be certified without an Android USB host + UAC2 DAC, so it is intentionally left out rather than shipped blind.

**Hardware matrix to run when a DAC is available:**

1. Pixel + UAC2 DAC (e.g. iFi/Topping/FiiO), Android 14+.
2. Verify `GET_CUR` matches the DAC's own display after each 10% step.
3. Verify mute is honoured in bit-perfect mode with software volume at unity.
4. Verify unplug/replug restores the prior hardware volume, not 100%.
5. Verify a DAC that exposes only a 0…-40 dB range maps correctly (no clipped UI steps).
6. Verify no capacitive pop on volume 0 → 100 transitions.

---

## 5. What is honest to claim

- **DSD512 decode:** implemented and host-verified.
- **Multichannel trim/delay engine:** implemented and host-verified; not yet reachable from the UI.
- **UAC2 hardware volume:** not implemented; hardware-dependent.
- **Native matrix:** 13/14 green; the remaining failure is the legacy composite's dither deviation (>2 LSB), not the new multichannel/DSD512 code. That needs a dedicated dither audit before this row can be called 10/10.
