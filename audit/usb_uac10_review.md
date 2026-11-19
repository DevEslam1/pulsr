# USB Audio Class (UAC1/UAC2) fix-set review

**Scope:** `UsbAudioSink.cpp/.h`, `eq_jni_bridge.cpp` (USB section), `UsbAudioControlParser.kt`,
`UsbExclusivePlugin.kt`, `test_usb_sink.cpp`, `UsbAudioControlParserTest.kt`,
`UsbControlProtocolTest.kt` (plus `HiResDacPlugin.kt` for cross-checks).
**Tree:** dirty, reviewed read-only. No source file was edited; no commit/reset/checkout was run.

**Snapshot reviewed** (SHA-256 prefix / mtime):

| File | Hash | mtime |
| --- | --- | --- |
| `UsbExclusivePlugin.kt` | `465CB23CF833` | 18:16:08 |
| `UsbAudioControlParser.kt` | `3DCC91A2A230` | 18:02:57 |
| `UsbAudioSink.cpp` | `3885F7C523F4` | 18:01:31 |
| `UsbAudioSink.h` | `70B538F38D77` | 17:47:07 |
| `test_usb_sink.cpp` | `F38E209F5715` | 17:53:14 |
| `UsbControlProtocolTest.kt` | `5A09DD2CF4D3` | 18:03:12 |

The native test binary was force-rebuilt from this `UsbAudioSink.cpp` (object deleted, relinked at
18:24) and the Kotlin tests were re-run after the final read, so the results below belong to this
snapshot.

---

## Verdict

**Not ready to ship as-is.** 10 of the 11 original findings are implemented correctly and are
covered by tests that assert the fixed behaviour. One fix (finding 9, UAC2 Clock Validity) is in the
wrong place in the control flow and can refuse to program a working clock (P1). The bounded-teardown
rewrite (finding 3) is correct on the normal stop path but becomes unrecoverable after a forced
teardown with a failed drain (P2), and two smaller robustness/coverage gaps remain.

| Severity | Count |
| --- | --- |
| P0 | 0 |
| P1 | 1 |
| P2 | 3 |
| P3 | 5 |

---

## Test results (all from the commands in the brief, run in order)

1. `cmake --build android/app/build/testNative/Release --target test_usb_sink --parallel 2`
   → **BUILD OK** (first run `ninja: no work to do`; the target was then force-relinked from the
   current `UsbAudioSink.cpp` — `[1/2] Building CXX object …UsbAudioSink.cpp.obj`, `[2/2] Linking`).
2. `test_usb_sink.exe`
   → `[TEST] USB UAC2 sink host-verifiable math...`
   → `[PASS] USB descriptor parsing, feedback decode, and packet sizing verified.`
   → exit 0.
3. `gradlew :app:testDevDebugUnitTest --tests …UsbControlProtocolTest --tests …UsbAudioControlParserTest -x :app:compileDevDebugUnitTestJavaWithJavac --offline --no-daemon`
   → **BUILD SUCCESSFUL** in 30 s. JUnit XML:
   `UsbAudioControlParserTest` 38 tests / 0 failures / 0 errors / 0 skipped;
   `UsbControlProtocolTest` 48 tests / 0 failures / 0 errors / 0 skipped (**86 tests, 0 skipped**).
   Re-run of `--tests 'com.pulsr.music.*Usb*'` executed the same two classes; there are no other
   USB Kotlin test classes in the module.
4. `gradlew :app:compileDevDebugKotlin --offline --no-daemon`
   → **BUILD SUCCESSFUL**. The `devDebug` Kotlin outputs were (re)generated at 18:17:33 from the
   current sources by step 3, so this task is legitimately `UP-TO-DATE`; the changed plugin classes
   (`UsbExclusivePlugin.class`, `UsbAudioControlParser.class`, `UsbAudioProtocol.class`) are present
   and current.

---

## Fix-by-fix verification

| # | Original finding | Status | Evidence |
| --- | --- | --- | --- |
| 1 | UAC2 `QuerySupportedRates` scanned `0x0B`, fabricated a fallback | **Fixed** (native dead code, see P3-7) | `UsbAudioSink.cpp:1560-1566` scans `0x0A`; `:1609-1616` returns only parsed rates; the fabricated list is gone from both the Linux and non-Linux branches (`:1620`). Kotlin no longer calls it: `UsbExclusivePlugin.kt:1392-1399` uses `refreshAdvertisedRates`, and there is no `external fun nativeUsbQuerySupportedRates` declaration. |
| 2 | Feedback-less steering clamped to ±0.1 % | **Fixed** | `UsbAudioSink.cpp:1417` `deltaMax = nominalRate/100` (±1 %); steps at `:1427`, dead bands `<200`, `>800`, recentre `300..700` (`:1428-1438`). Test proves a 0.2 % error survives (`test_usb_sink.cpp:727-735`) and that the full ±1 % range is reachable (`:736-744`); the older −0.1 %/47952 assertions were updated to 47520/48480. |
| 3 | Teardown blocked forever in `REAPURB` | **Mostly fixed** — P2-2, P2-4 | `drainUrbCompletions(int timeoutMs = 2000)` uses `USBDEVFS_REAPURBNDELAY` + steady_clock deadline (`UsbAudioSink.cpp:459-510`), `ETIMEDOUT` on expiry (`:502-507`); `releaseResources`/`Close` return `bool` (`:623-680`, `:399-421`); on failure it returns before freeing and keeps `exclusive_` (`:649`); `Open` refuses to start on a half-torn-down sink (`:176-186`). Kotlin `clearStreaming` keeps claims and sets `drainPending` when the drain is unproven (`UsbExclusivePlugin.kt:1308-1325`), `stopStreaming` surfaces `usb_drain_incomplete` (`:1369-1389`). Destructor joins the worker and leak-preserves storage (`UsbAudioSink.cpp:89-108`). |
| 4 | `selectFormat` could pick 20/18-bit alts | **Fixed** | `UsbAudioControlParser.kt:1139` `PACKABLE_BIT_DEPTHS = {16,24,32}`; filtered at `:1214` and constrained to `depth..subslotSize*8` (`:1215`). Test: `UsbControlProtocolTest.kt:551-564`. |
| 5 | Volume fallback could pick the capture path | **Fixed** | `UsbAudioControlParser.kt:890-899` — first candidate only when `playbackTerminalId == null`; otherwise the Feature Unit must be on the terminal's source chain. Tests: `featureUnitOffThePlaybackPathIsNotASilentFallback`, `featureUnitIsStillFoundWithoutAnyStreamingInterface` (`UsbAudioControlParserTest.kt:766-800`). |
| 6 | UAC1 continuous ranges stopped at 384 k | **Fixed** | `STANDARD_SAMPLE_RATES` includes 705600/768000 (`UsbAudioControlParser.kt:31-34`), and the native list at `UsbAudioSink.cpp:1447-1449`. Test: `continuousUac1RangeCoversSevenHundredSixtyEightKilohertz` (`UsbAudioControlParserTest.kt:723-742`). |
| 7 | UAC3 parsed with the UAC1 format layout | **Fixed** | Format/subslot decoding is gated on UAC2, else `UAC1 || (UAC_NONE && protocol 0x00)` (`UsbAudioControlParser.kt:806-836`), so UAC3 leaves `curSubslot = 0` and `flushAltSetting()` drops it (`:466-490`). Test: `uac3StreamingFormatIsNotParsedWithTheUac1Layout` (`UsbAudioControlParserTest.kt:745-758`); plugin refuses UAC3 explicitly (`UsbExclusivePlugin.kt:1063-1066`). |
| 8 | Clock Selector was read but never written | **Fixed** (P3-6) | `programPlaybackClock` tries the active clock, then every other pin, keeps a working pin, restores the original on failure (`UsbAudioControlParser.kt:1429-1466`); `SET_CUR` is `0x21 / 0x01 / 0x0100 / (selectorId<<8)|iface`, 1 byte (`:1399-1412`). Tests assert the exact bytes and both success/failure paths (`UsbControlProtocolTest.kt:658-712`). |
| 9 | Clock Validity was not checked | **Partially correct — P1-1, P3-9** | `isClockValid` sends `0xA1 / 0x01 / 0x0200 / (clockId<<8)|iface`, 1 byte, fail-open on unreadable/failed, false on 0 (`UsbAudioControlParser.kt:1375-1392`) — the request is `0x01`, not `0x02`. Test asserts `Request(0xA1, 0x01, 0x0200, 0x0B00, 1)` (`UsbControlProtocolTest.kt:738-753`). But the result is used only *before* programming (see P1-1). |
| 10 | Empty rates in status / native overclaim | **Fixed** | `applyParsed` seeds only descriptor rates (`UsbExclusivePlugin.kt:577-585`); `refreshAdvertisedRates` caches the queried list, UAC1 descriptor list on refusal, empty for UAC2/UAC3 (`:594-615`); `buildStatus` publishes the cache (`:697`) and UAC2 alts share the clock-wide list (`:739-746`); cleared on device change in `closeLocked` (`:1415`). `queryPlaybackRates` returns only GET_RANGE subranges, then the single current value, else empty (`UsbAudioControlParser.kt:1528-1558`). Tests: `uac2RateDiscovery*` (`UsbControlProtocolTest.kt:843-879`). |
| 11 | Device selection ignored the routed USB output | **Fixed** (P3-5) | `findAudioDevice` keeps `openedDevice` while attached (no switch mid-stream), then `routeAwareAudioDevice` (`UsbExclusivePlugin.kt:396-460`), which maps `AudioDeviceInfo.productName`/`address` via `selectPreferredAudioDevice` (VID:PID → name → standard audio class, non-audio filtered by `hasAudioControlAndStreamingPair`). Test: `selectPreferredAudioDevicePrefersRoutedVidPidThenNameThenStandardAudio`. |

### Control-encoding regression checks (all unchanged / correct)

- UAC1 rate: `SET_CUR 0x22 / 0x01 / 0x0100 / endpoint`, 3 bytes; read-back `0xA2 / 0x81 / 0x0100 /
  endpoint`, 3 bytes — `UsbAudioControlParser.kt:1337-1356`; asserted end-to-end by
  `programPlaybackClockDelegatesToTheUac1EndpointPath` (`UsbControlProtocolTest.kt:713-725`).
- UAC2 rate: `0x21 / 0x01 / 0x0100 / (clockId<<8)|AC`, 4 bytes; read-back `0xA1 / 0x01`, 4 bytes —
  `:1339-1348`.
- UAC1 volume: `0x21|0xA1`, `wValue = 0x02<<8 | channel`, `wIndex = unitId<<8 | iface` (`:1024-1026`);
  RANGE selectors `0x82/0x83/0x84` (`:1040-1046`).
- UAC2 clock source subtype `0x0A`, selector `0x0B`, multiplier `0x0C` (`:182-190`).
- Clock validity control `0x02` as the CS code (`wValue = 0x0200`), request `0x01`.

---

## Findings

### P1-1 — UAC2 Clock Validity gates the sample-rate write, and is never checked afterwards

**File:** `android/app/src/main/kotlin/com/pulsr/music/UsbAudioControlParser.kt:1442-1448`
(consumed at `UsbExclusivePlugin.kt:1120-1124`)

```kotlin
val selection = resolveActiveClockSelection(transport, parsed) ?: return FAILED
if (isClockValid(transport, selection.clock)) {          // 1442
    val current = setSampleRateWithResult(...)           // 1443-1446
    if (current.isSuccess) return current
}
val selectorId = selection.selectorId ?: return FAILED   // 1448
```

`isClockValid` is a *pre-condition* for the `SET_CUR(CS_SAM_FREQ_CONTROL)`. If the device declares a
readable Clock Validity control (`bmControls D3..D2 != 0b00`, parsed at `:722-726`) and answers `0`,
the clock is never programmed; with no multi-input selector on the path the call returns `FAILED`,
which `startStreamingInternal` maps to `clock_not_verified` (`UsbExclusivePlugin.kt:1121-1124`) and
direct USB never starts. There is no second validity read after programming anywhere in the file
(`isClockValid` has exactly the two call sites at `:1442` and `:1459`).

UAC2 defines `CLOCK_VALID` as "the clock is currently valid/locked", so a clock that is not yet
programmed is allowed to report `0`; requiring validity to *write* the frequency inverts the check.
The likely hardware impact (DACs that report unlocked until the rate is set can no longer stream) is
an inference — I could not test a device — but the control-flow defect is certain, and the previous
code (`git show HEAD:…UsbAudioControlParser.kt`) programmed the clock unconditionally, so this is a
behavioural regression introduced by the fix.

**Recommended fix:** attempt `setSampleRateWithResult` once regardless of validity, then use
`isClockValid` as a post-condition (surface `UNVERIFIED_READBACK_UNSUPPORTED`/`FAILED` honestly).
Only consult validity before switching *selector pins*, where choosing a locked source is the whole
point.

### P2-2 — A forced teardown after a failed drain permanently disables direct USB for the process

**Files:** `android/app/src/main/cpp/UsbAudioSink.cpp:649, 676`;
`android/app/src/main/kotlin/com/pulsr/music/UsbExclusivePlugin.kt:1405-1408, 1292-1325`

`releaseResources()` keeps `fd_`, `urbOwned_` and the buffers on a failed drain (`:649`) and only
sets `fd_ = -1` on success (`:676`). `closeLocked()` then force-releases and closes the connection
(`UsbExclusivePlugin.kt:1405-1408`), which invalidates the usbfs descriptor. Nothing resets the
native ownership bookkeeping.

Every later `Open` starts with `releaseResources()` (`UsbAudioSink.cpp:176-186`) →
`drainUrbCompletions()` → `fd_` is the dead descriptor → `ioctl(REAPURBNDELAY)` returns `EBADF`
(or `ENOTTY` if the fd number was recycled) → `lastError_` stored, `return false` (`:486-488`) →
`ClaimFailed`. `startStreamingInternal` calls `clearStreaming()` first, so it returns
`usb_drain_incomplete` forever; the only recovery is a process restart. `drainPending` is reported
honestly (`UsbExclusivePlugin.kt:1324, 1418-1420`), so the UI at least shows the stuck state — but
the feature never comes back.

Trigger: `closeLocked()` = device detach, plugin dispose, or permission loss while a drain timed out
(the wedge the 2 s budget was added for). Narrow, but it is exactly the failure mode the fix targets.

**Recommended fix:** give the sink an explicit `Abandon()` (or `Close(force = true)`) used by the
forced path: drop ownership flags, set `fd_ = -1`, leak the preallocated URB storage deliberately
(the destructor already does this at `:104-109`), and let the next `Open` start clean. Keep the
strict "never free unproven storage" rule for the normal stop path only.

### P2-3 — Main-thread status getters can block for the full 2 s drain

**Files:** `android/app/src/main/kotlin/com/pulsr/music/UsbExclusivePlugin.kt:280-296`;
`android/app/src/main/cpp/UsbAudioSink.cpp:1187-1188` (with `Close` holding the mutex at `:399-421`)

`"getDiagnostics"` and `"getBufferedMs"` are handled inline in `onMethodCall` (platform/main
thread), unlike every other USB method which uses `runAsync`. Both reach
`safeGetBufferedMs()` → `UsbAudioSink::GetBufferedMs()`, which takes `controlMutex_`. `Close()`
holds that mutex across the worker join and the up-to-2 s bounded drain. `exclusive_usb_chip.dart:87`
polls `getDiagnostics` on a timer, so a `stopStreaming` in flight freezes the UI for up to ~2 s.
The Dart-side `.timeout()` cannot help: the platform-channel call itself is blocking the main thread.

**Recommended fix:** route both methods through `runAsync`, or make `GetBufferedMs` lock-free by
reading `sampleRate_`, `ringWrite_`, `ringRead_` as atomics (the fields already are) and taking
`numUrbs_/packetsPerUrb_/serviceIntervalUs_` from an atomic snapshot.

### P2-4 — The bounded-drain deadline has no regression test

**File:** `android/app/src/test/cpp/test_usb_sink.cpp:159-200`

The `USBDEVFS_REAPURBNDELAY` loop lives inside `#if defined(__linux__) || defined(__ANDROID__)`
(`UsbAudioSink.cpp:460-508`), so on the host build `drainUrbCompletions` reduces to
`return !hasOutstandingUrbs()`. The updated tests assert only the *contract* ("returns false and
retains storage while ownership is outstanding", `test_usb_sink.cpp:163-200`) — they would still pass
if `REAPURBNDELAY` were reverted to blocking `REAPURB` or the deadline were removed. The original
"`Close()` blocks forever" bug is therefore untested.

**Recommended fix:** inject the reap callable the same way `UrbSubmit` is injected
(`bool drainUrbCompletions(int timeoutMs, Reap reap = reapUsbfsUrb)`), and add a test where the reap
never completes: `drainUrbCompletions(0)` must return false with `lastError_ == ETIMEDOUT` and keep
`exclusive_`.

### P3-5 — Route-aware selection returns a non-routed device when the hint does not match

**Files:** `android/app/src/main/kotlin/com/pulsr/music/UsbAudioControlParser.kt:392-425`;
`UsbExclusivePlugin.kt:487-524`

`selectPreferredAudioDevice` starts at `bestScore = Int.MIN_VALUE`, so the first qualifying device
always wins; it never returns `null` while any audio candidate exists. `routeAwareAudioDevice`'s
contract says "null means no route hint", so `findAudioDevice` returns that first candidate and skips
its own "permitted audio class first" ordering (`UsbExclusivePlugin.kt:416-455`). With two DACs
attached and an unroutable/empty route product name, the app can select the unpermitted DAC and
raise a permission prompt for the wrong device.

**Recommended fix:** return `null` when the best score carries no route match (e.g. `score < 50`),
so the existing ordering applies; keep the current fallback only for the genuinely routeless case.

### P3-6 — Selector restore failure is ignored

**File:** `android/app/src/main/kotlin/com/pulsr/music/UsbAudioControlParser.kt:1464`

`setClockSelectorPin(transport, selectorId, interfaceNumber, originalPin)` discards its `Boolean`.
If the restore `SET_CUR` fails, the function still reports `FAILED` while the DAC remains on a pin
that was just proven unable to deliver the rate, and the next attempt re-resolves from that state.

**Recommended fix:** retry once, and log/surface `selector_restore_failed` (a distinct
`RateSetResult` or a diagnostic counter) instead of silently returning `FAILED`.

### P3-7 — Dead JNI surface keeps an untested start path and an unscoped native clock scan

**Files:** `android/app/src/main/cpp/eq_jni_bridge.cpp:1723-1730, 1760-1770`;
`UsbAudioSink.cpp:1560-1566`

`nativeUsbStreamStart` (the `alreadyConfigured = false` path that claims and issues
`SETINTERFACE`) and `nativeUsbQuerySupportedRates` have no Kotlin declaration or caller any more
(verified by grep over `android/app/src/main`). Keeping them means the double-`SETINTERFACE` clock
reset can be reintroduced by a future caller, and `QuerySupportedRates`' UAC2 scan treats *any*
`CS_INTERFACE` subtype `0x0A` anywhere in the configuration as a clock, without checking that the
interface is AudioControl (`:1556-1566`).

**Recommended fix:** delete both exports (and the static helper), or at minimum require
`bInterfaceClass == 0x01 && bInterfaceSubClass == 0x01` before collecting clock IDs.

### P3-8 — `lastError_` keeps a stale `EPROTO` after a later successful drain

**File:** `android/app/src/main/cpp/UsbAudioSink.cpp:496-507`

An unrecognized completion sets `lastError_ = EPROTO` and the loop continues; if the remaining URBs
are then reaped, the function returns true and `Close()` reports success, but diagnostics keep
reporting `EPROTO` (until the next `Open` clears it at `:185`). Harmless functionally, misleading in
the bug-report bundle.

**Recommended fix:** count unknown completions in a separate diagnostic and clear `lastError_` when
the drain completes with `hasOutstandingUrbs() == false`.

### P3-9 — `isClockValid` doc comment states the wrong request code

**File:** `android/app/src/main/kotlin/com/pulsr/music/UsbAudioControlParser.kt:1371`

The comment says `GET_CUR(CS_CLOCK_VALID_CONTROL)` is
`0xA1 / 0x02 / 0x0200 / (clockId shl 8) | interface`, but the code (correctly) sends
`REQ_CUR = 0x01` with `CS_CLOCK_VALID_CONTROL = 0x0200` (`:1384`), and the test pins `0x01`
(`UsbControlProtocolTest.kt:748`). This is exactly the `0x01`-vs-`0x02` confusion the fix was
meant to remove; the comment invites a future "correction" back to the broken request.

**Recommended fix:** change the comment to `0xA1 / 0x01 / 0x0200 / …`.

---

## Regression checks (no defect found)

- **Ownership / double-free:** `releaseResources` frees only after a successful drain; repeated calls
  are idempotent (`urbBuffers_.clear()` before the next loop); the destructor joins the worker and
  leak-moves storage when ownership is unproven (`UsbAudioSink.cpp:89-110`); `Open` reaps a
  self-exited worker before reassigning it (`:170-174`). No double free or `std::terminate` path
  found.
- **`clearStreaming` / `drainPending`:** claims are kept and `drainPending` set on an unproven drain
  (`:1308-1312`); `drainPending` now survives `closeLocked` (`:1324`, `:1418-1420`); `stopStreaming`
  reports `usb_drain_incomplete` instead of pretending success (`:1369-1385`). Retry happens on the
  next start/stop, and on a failed `buildStatus` self-heal (`:671-679`).
- **`refreshAdvertisedRates`:** runs only on the worker (`startStreamingInternal`,
  `querySupportedRatesInternal`, both via `runAsync`), swallows query failures, does not fail the
  stream, and is emptied on device change (`applyParsed`, `closeLocked`). No fabrication: UAC2/UAC3
  with an unreadable clock range yield `emptyList()`.
- **Route selection:** never picks a device without an AudioControl+AudioStreaming pair, and keeps
  `openedDevice` while attached, so it cannot switch DACs during an active stream.
- **Threading:** all new control transfers (active-clock resolution, selector read/write, rate
  program/verify, clock-range query) run on `UsbExclusiveWorker`. The only main-thread USB JNI calls
  are the two status getters in P2-3.
- **`StreamFormat.matches`** now accepts a narrower depth inside an already-open wire container
  (`16..wireBitDepth`, `:1174-1180`) — a 16-bit track on a 24-bit alt reuses the endpoint instead of
  restarting it, and `WritePcm` still zero-pads low bytes (`SinkQuantizer.h:112-122`). Wider requests
  reopen.
- **UAC3:** `altSettingFormats` stays empty, `streamingSupported` is false, and start fails with
  `uac3_unsupported` rather than a parse error.

### Non-blocking observations (not counted as findings)

- `refreshAdvertisedRates` is called twice per start (`UsbExclusivePlugin.kt:1104` before
  `setInterface`, `:1139` after the clock). With 1 s control timeouts a wedged device adds up to
  ~6 s to the start future (worker thread, not main). The second read usually returns the same range.
- The +1 % up-steer can be physically unreachable when the alternate setting's `wMaxPacketSize`
  leaves no packet headroom: `maxFramesPerPacket_ = min(capacityFrames, nominalFrames + 1)`
  (`UsbAudioSink.cpp:230`) and `NextPacketFrames` clamps to it (`:1401-1409`). Frames are not lost
  (they stay in the ring), the command simply saturates earlier than the ±1 % clamp suggests.
- Hardware volume is now unavailable on devices whose AudioControl topology cannot place a Feature
  Unit on the playback terminal (intentional per finding 5, but worth a user-facing reason string
  rather than silently hiding the slider).

---

## Pre-existing blocker (out of scope, as instructed)

`gradlew :app:compileDevDebugUnitTestJavaWithJavac` fails on an unrelated dirty-tree mismatch:

```
FloatDspAudioSinkTest.java:1165: error: method configurePendingReplacement in class
FloatDspAudioSink cannot be applied to given types;
    oldWrapper.configurePendingReplacement(replacement, delayed, 0, null);
  required: FloatDspAudioSink
  found:    FloatDspAudioSink,Format,int,<null>
```

This is why both Kotlin test commands were run with `-x :app:compileDevDebugUnitTestJavaWithJavac`.
It does not involve the USB path and was not counted against the fix set.

---

## Bottom line

The parser-side fixes (1, 2, 4–8, 10, 11) are correct, and the tests genuinely assert the new
behaviour rather than just compiling. The teardown rewrite is sound on the normal stop path but needs
the forced-teardown recovery described in P2-2 and a deadline test per P2-4. The one blocking defect
is P1-1: Clock Validity is consulted before the frequency write, so a UAC2 DAC that reports its clock
unlocked until programmed can be refused outright, with no post-program validity check to catch the
real failure.
