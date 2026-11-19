# USB UAC1/UAC2 Fix Set — Independent Review #2

**Repository:** `D:\Courses\Projectss\pulsr` (working tree dirty with the intended fixes; no source was edited,
committed, reset or checked out during this review)
**Date:** 2026-11-19
**Reviewer:** independent USB Audio Class review (second pass over the corrected fix set)
**Verdict:** **PASS on all ten prior findings — not clean overall.** Every P1/P2/P3 item from the first review
is genuinely fixed and covered by a test that would fail on the old code. One **new, CI-blocking** side effect
of the P2-2 fix (a deliberate leak that LeakSanitizer will report) must be handled before merge, plus three P3
notes. No product-code regression (double free, use-after-free, deadlock, wrong control encoding, mid-stream
device switch) was found.

Severity counts: **P0 = 0 · P1 = 1 · P2 = 0 · P3 = 3.**

---

## 1. Scope and method

Reviewed the current files, not only the diff:

| File | Lines |
| :--- | ---: |
| `android/app/src/main/cpp/UsbAudioSink.cpp` | 1626 |
| `android/app/src/main/cpp/UsbAudioSink.h` | 329 |
| `android/app/src/main/cpp/eq_jni_bridge.cpp` (USB symbols, `:1700-1815`) | 1912 |
| `android/app/src/main/kotlin/com/pulsr/music/UsbAudioControlParser.kt` | 1622 |
| `android/app/src/main/kotlin/com/pulsr/music/UsbExclusivePlugin.kt` | 1495 |
| `android/app/src/test/cpp/test_usb_sink.cpp` | 992 |
| `android/app/src/test/kotlin/com/pulsr/music/UsbAudioControlParserTest.kt` | 867 |
| `android/app/src/test/kotlin/com/pulsr/music/UsbControlProtocolTest.kt` | 943 |

Supporting reads: `android/app/src/test/cpp/CMakeLists.txt`, `scripts/run_native_dsp_tests.sh`,
`.github/workflows/ci.yml`, `git diff` of the five changed USB sources (read-only).

Evidence tiers are marked per claim: **[verified]** = read in the current file and/or exercised by a run;
**[inferred]** = mechanism verified in code against a documented toolchain/OS behaviour, not executed here;
**[not verified]** = could not be established in this environment.

---

## 2. Test results

| # | Command | Result |
| :-- | :--- | :--- |
| 1 | `cmake --build android/app/build/testNative/Release --target test_usb_sink --parallel 2` | **OK** — `ninja: no work to do.` The binary is already current (`test_usb_sink.exe` 18:35:55 is newer than `UsbAudioSink.cpp` 18:35:38). |
| 2 | `android/app/build/testNative/Release/test_usb_sink.exe` | **PASS**, exit 0. Output: `[TEST] USB UAC2 sink host-verifiable math...` / `[PASS] USB descriptor parsing, feedback decode, and packet sizing verified.` |
| 3 | `gradlew :app:testDevDebugUnitTest --tests ...UsbControlProtocolTest --tests ...UsbAudioControlParserTest -x :app:compileDevDebugUnitTestJavaWithJavac --offline --no-daemon` | First invocation: `BUILD SUCCESSFUL` **but `:app:testDevDebugUnitTest UP-TO-DATE`** — Gradle executed nothing, so that run is *not* evidence. Re-ran the identical command with `--rerun`: `> Task :app:testDevDebugUnitTest` executed, `BUILD SUCCESSFUL in 35s`. |
| 4 | `gradlew :app:compileDevDebugKotlin --offline --no-daemon` | First invocation `UP-TO-DATE`; re-ran with `--rerun`: task executed, `BUILD SUCCESSFUL in 1m 6s`, exit 0. |
| 5 | *extra:* Debug + ASan configure/build of `test_usb_sink` (`-DPULSR_TEST_SANITIZERS=ON`) | Configure, compile and link **succeeded**; execution **failed to load** with `0xC0000135` (STATUS_DLL_NOT_FOUND) even with `libclang_rt.asan_dynamic-i386.dll` on `PATH` and beside the exe. No runtime sanitizer evidence is available on this host — see §4/F1 and §7. |

JUnit XML written at 18:48:03 (i.e. by the `--rerun`):

| Suite | Tests | Failures | Errors | Skipped |
| :--- | ---: | ---: | ---: | ---: |
| `com.pulsr.music.UsbAudioControlParserTest` | 39 | 0 | 0 | 0 |
| `com.pulsr.music.UsbControlProtocolTest` | 50 | 0 | 0 | 0 |
| **Total** | **89** | **0** | **0** | **0** |

`-x :app:compileDevDebugUnitTestJavaWithJavac` was used only because of the **pre-existing, unrelated**
`FloatDspAudioSinkTest.java` mismatch. It is not a USB finding and was not investigated further.

> Note on the `--rerun` deviation: the requested commands are incremental, and the tree had already been built
> by an earlier run, so the literal commands reported UP-TO-DATE. Both Gradle tasks were re-executed with
> `--rerun` to produce real evidence; no source file was touched.

---

## 3. Prior findings — verification

| ID | Status | Evidence |
| :--- | :--- | :--- |
| **P1-1** Clock validity is post-condition only | **Fixed** | `UsbAudioControlParser.kt:1479-1480` — "No validity pre-check: an unprogrammed clock is expected to report 0", then `attemptClockProgram(...)` is called first. `:1515-1523` — `setSampleRateWithResult(..., 2, clock, ...)` runs **before** `isClockValid(...)`, and validity is the acceptance gate. The pin loop `:1488-1495` sets the pin first and never consults validity before trying. Test `UsbControlProtocolTest.kt:736-752` + harness `SelectorDevice` (`:575-655`): `unlockedUntilProgrammed` answers `CLOCK_VALID = 0` until that clock's own rate write lands (`programmedClocks += entity`), so the test genuinely covers 0-before-SET / 1-after-SET; it asserts `VERIFIED`, a real `SET_CUR` (`0x21/1/0x0100/0x0B00/4`), the post-read `0xA1/1/0x0200/0x0B00/1`, and that no pin was switched. **[verified]** |
| **P2-2** `Abandon()` + forced teardown | **Fixed** | `UsbAudioSink.cpp:424-499`: stops/joins the worker, drains the writer gate, resets `producerOwner_`/`producerRawDepth_`/DoP phase/`deliveryEpoch_`, withdraws `DspEngineRegistry` sink depth, gates `directUsbActive` off, moves URB header storage into an intentionally leaked vector (`:465-469`), drops payload pointers without `delete[]` (`:470-471`), then `claimed_ = false; fd_ = -1; exclusive_ = false` (`:496-498`). Host test `test_usb_sink.cpp:182-198,795` asserts the pristine state **and** that the next `Open` reaches the normal platform path (`InvalidArgs` on a host without usbfs) instead of `ClaimFailed` — i.e. no permanent ladder. **[verified]** |
| **P2-3** Diagnostics off the main thread | **Fixed** | `UsbExclusivePlugin.kt:290-306`: `getDiagnostics` now runs inside `runAsync` with the identical six-key map (`lastError`, `underrunCount`, `overrunCount`, `channelMismatchFrames`, `isStreamActive`, `bufferedMs`); `:308` `getBufferedMs -> runAsync { safeGetBufferedMs() }`. `git diff` confirms the map literal is byte-identical apart from indentation. Values and `safe*` error swallowing unchanged. **[verified]** |
| **P2-4** Bounded-drain deadline is host-testable | **Fixed** | `UsbAudioSink.h:191-200` + `.cpp:549` take `(int timeoutMs = 2000, UrbReap reap = reapUsbfsUrb)`; the deadline loop is not `#if`-ed out (`:585-605`). Test `test_usb_sink.cpp:58-63` (`reapNever` → `EAGAIN`) + `:171-180,793`: asserts `drainUrbCompletions(0, reapNever) == false`, `lastError == ETIMEDOUT`, `IsExclusive()`, `hasOutstandingUrbs()`, and that both storage vectors survived. **[verified]** |
| **P3-5** Route-aware selection | **Fixed** | `UsbAudioControlParser.kt:426` — `if (requireRouteMatch && !bestRouteMatched) return null`. `routeMatched` is only set by the VID/PID or name branches (`:391`, `:413`); the standard-audio bonus at `:419` (`score += 50`) never touches it. Plugin passes `requireRouteMatch = true` at `UsbExclusivePlugin.kt:538` and keeps its normal audio-class/vendor ordering when null. Test `UsbAudioControlParserTest.kt:621-683` proves the first-DAC fallback is gone for both an unrelated hint and a plain call. **[verified]** |
| **P3-6** Selector restore failure | **Fixed** | Distinct enum member `UsbAudioControlParser.kt:1341-1355`; restore attempted twice `:1496-1504`, then `return RateSetResult.SELECTOR_RESTORE_FAILED`. Plugin `:1152-1159` maps it to `failure("clock_selector_restore_failed")` and returns **before** the `else` at `:1174` that sets `lastRateVerified = true` — it cannot be recorded as verified. Tests `UsbControlProtocolTest.kt:696-706` (restore succeeds → `FAILED`, pin back to 1) and `:708-720` (`SELECTOR_RESTORE_FAILED`, `isSuccess == false`, `refusedPinWrites == [1, 1]` = one retry). **[verified]** |
| **P3-7** Dead native symbols | **Fixed** | `QuerySupportedRates` is deleted outright by the diff, including the `0x0B` CLOCK_SOURCE scan and the fabricated `{44100 … 768000}` fallback. `nativeUsbQuerySupportedRates` declaration and all callers are gone; `querySupportedRates` now routes to `refreshAdvertisedRates`. Only `nativeUsbStreamStartWithFormat` exists (`eq_jni_bridge.cpp:1730`, Kotlin `:145`), and it always passes `alreadyConfigured = true`. Grep for `nativeUsbStreamStart|nativeUsbQuerySupportedRates|QuerySupportedRates` over the tree returns **no production references**. **[verified]** |
| **P3-8** Successful drain must not latch EPROTO | **Fixed** | `UsbAudioSink.cpp:608-616`: after `hasOutstandingUrbs()` is false, a `sawUnknownCompletion` flag clears `lastError_` to 0 and logs (rate-limited). Test `test_usb_sink.cpp:200-212,797` scripts one stranger completion followed by both real URBs and asserts `GetLastError() == 0` with exclusivity/storage still intact. **[verified]** |
| **P3-9** `isClockValid` doc encoding | **Fixed** | `UsbAudioControlParser.kt:1390-1404` documents `GET_CUR(CS_CLOCK_VALID_CONTROL)` as `0xA1 / 0x01 / 0x0200 / (clockId shl 8) | interface`, one byte, and states it is a post-condition. Code matches (`:1412-1418`). **[verified]** |

Residual (not a regression): `UsbAudioSink::ParseSupportedRatesFromDescriptors` (`.h:112`, `.cpp:1556`) now has
**no production caller** — it survives only for the host tests (`test_usb_sink.cpp:373-423`,
`test_golden_vectors.h:436-456`). Keeping it as the host-verifiable UAC1 parser is defensible; if P3-7's
"zero references" rule is meant to cover dead *production* API, this is the one remaining candidate.

---

## 4. New findings

### F1 — P1 (inferred): the deliberate leak makes the ASan Debug suite fail in CI

**Where:** `android/app/src/main/cpp/UsbAudioSink.cpp:465-471` (leak) exercised by
`android/app/src/test/cpp/test_usb_sink.cpp:182-198` and `:171-180` (two `Abandon()` calls), run from
`:793-797`. Pipeline: `.github/workflows/ci.yml:124-138` (`native-dsp-tests`, `ubuntu-latest`) →
`scripts/run_native_dsp_tests.sh:57-58` which does `run_config Debug ON` and
`ctest --test-dir "$build_dir" --output-on-failure` under `set -euo pipefail`.

**Evidence (code, verified):**

```cpp
// UsbAudioSink.cpp:465-471 — deliberate, documented leak
if (!urbStorage_.empty()) {
    (void)new std::vector<uint8_t>(std::move(urbStorage_));
}
if (!feedbackUrbStorage_.empty()) {
    (void)new std::vector<uint8_t>(std::move(feedbackUrbStorage_));
}
urbBuffers_.clear();      // payload arrays deliberately leaked
feedbackBuffers_.clear(); // payload arrays deliberately leaked
```

The `new` pointer is discarded, and the payload arrays are dropped without `delete[]`, so both are
**unreachable at exit**. `scripts/run_native_dsp_tests.sh` passes `-DPULSR_TEST_SANITIZERS=ON`
(`-fsanitize=address,undefined`), and a repo-wide search finds no `ASAN_OPTIONS`, `detect_leaks` or `LSAN`
setting anywhere.

**Mechanism [inferred]:** on Linux, `-fsanitize=address` enables LeakSanitizer by default; LSan runs at process
exit, reports these as direct leaks, and exits non-zero. `ctest` therefore marks `test_usb_sink` failed, and
`set -euo pipefail` aborts the sanitizer job. Net effect: **the P2-2 fix turns the `native-dsp-tests` CI job red**
without any functional defect.

**What I could not do:** execute it. This host is Windows/i686-mingw; Windows ASan has no LSan, and the
instrumented binary does not even load here (exit `0xC0000135`), so the failure is **not observable on this
machine**. It needs one Linux run (or the fix below) to confirm.

**Fix (either):**
1. Run the sanitizer CTest pass with `ASAN_OPTIONS=detect_leaks=0` (leak checking is already covered by the
   deliberate-leak contract, not by LSan), **or**
2. Mark the abandoned blocks with `__lsan_ignore_object(ptr)` (weak declaration behind `#if defined(__has_feature)`)
   at the two `new` sites, **or**
3. Skip the two `Abandon()` assertions under `__SANITIZE_ADDRESS__` — least desirable, it removes coverage.

Preferred: (2), because it keeps leak checking on for the rest of the suite and documents the intent in code.

### F2 — P3: the bounded drain is not bounded when completions are *unrecognized*

**Where:** `android/app/src/main/cpp/UsbAudioSink.cpp:585-601`.

```cpp
while (hasOutstandingUrbs()) {
    void* urb = nullptr;
    if (reap(fd_, &urb) < 0) {
        ...
        if (std::chrono::steady_clock::now() >= deadline) break;   // deadline only here
        ...
        continue;
    }
    ...
    if (!markReaped(urb, &feedback, &index)) {
        lastError_.store(EPROTO, ...);
        sawUnknownCompletion = true;
    }                                                              // loops with no deadline check
}
```

A `reap` that keeps **succeeding** while returning a pointer this sink does not own never reaches the deadline
check, so the loop is unbounded. That is exactly the state `markReaped` exists to detect (a duplicate or
foreign completion), and the loop runs while `controlMutex_` is held — so `Close()`, `Open()`, `Abandon()` and
`GetBufferedMs()` would wedge behind it, which is the hang the bounded drain was introduced to prevent. Low
likelihood (the kernel delivers each completion once) but cheap to close.

**Fix:** hoist the deadline test to the top of the `while` body (or `break` after N unrecognized completions)
so every iteration is bounded, not only the failing-reap path.

### F3 — P3: `lastError` stays `ETIMEDOUT` after a successful forced teardown

**Where:** `UsbAudioSink.cpp:424-499` (`Abandon` never touches `lastError_`), surfaced by
`UsbExclusivePlugin.kt:746` (`"lastError" to safeGetLastError()` in `buildStatus`) and `:299`
(`getDiagnostics`).

After `Abandon()`, `clearStreaming` returns true (`:1393`) and `stopStreamingInternal` reports
`success = true`, but the status map still carries `lastError = 110 (ETIMEDOUT)` — and keeps carrying it for
every subsequent `getStatus`/`getDiagnostics` until the next successful `Open`, which is the only place that
clears it (`UsbAudioSink.cpp:163`). The header documents `Abandon` as returning the sink to "pristine pre-Open
state"; a pristine sink reporting a live error code is inconsistent. Impact is diagnostics-only (no consumer of
`UsbExclusiveStatus.lastError` was found that turns it into an error state), hence P3.

**Fix:** either `lastError_.store(0)` at the end of `Abandon()` (matching the "pristine" contract), or keep the
code deliberately and document it as "the reason this stream was abandoned"; if kept, do not report it as an
active fault while `success == true`.

### F4 — P3 (test gap): `Abandon()` is never called twice by a test

**Where:** `test_usb_sink.cpp:182-198` calls it once per staged stream; nothing calls it back-to-back.

By inspection it is idempotent (second call sees empty vectors, `fd_` already `-1`, no worker), and it is safe
because it takes `controlMutex_` and spins only on `kWriterBusy`, which `endWrite()` clears without taking that
mutex (no lock-order inversion). But the brief's "safe if called twice" invariant is currently unguarded
against future edits, and `clearStreaming(true)` can reach it twice in one teardown
(`closeLocked` after a forced start). **Fix:** add `sink.Abandon(); sink.Abandon();` plus a follow-up `Open`
assertion to `abandonRecoversCleanStart`.

---

## 5. New-regression checklist (answers to each item in the brief)

| Question | Answer | Evidence |
| :--- | :--- | :--- |
| `Abandon()` must not free kernel-owned URB headers/payloads | **Correct.** Header blocks are moved into a leaked vector (addresses preserved for `urbs_`), payload arrays are dropped without `delete[]`. | `.cpp:465-471`, comments at `:460-464` |
| `Abandon()` safe if called twice | **Yes by inspection**; untested (F4). Empty vectors, `fd_ == -1`, no joinable worker. | `.cpp:455-499` |
| `Abandon()` deadlocks with the writer gate | **No.** It holds `controlMutex_` and spins on `kWriterBusy`; `endWrite()` (`:1202-1204`) only does an atomic `fetch_and`, and `WaitForWriteSpace` releases the bit before returning. No path takes `controlMutex_` while holding `kWriterBusy`. | `.cpp:430-437`, `:1202`, `:1314-1352` |
| Does the leak break the ASan Debug suite | **Yes on Linux/CI [inferred]** — see F1. Not observable on this Windows host (no LSan; runtime does not load). | F1 |
| `clearStreaming(force=true)` state machine | **Consistent.** Logical state (`directStatus`, `directOwner`, `streaming`, `streamFormat`, `lastRateVerified`) is dropped first; a non-forced failed drain sets `drainPending = true` and returns false *before* any release; the forced path abandons, then alt-0/release/rebind on the still-open connection, then `drainPending = !drained && !abandoned`. Claims are cleared only after the release call; the connection is never closed here. | `UsbExclusivePlugin.kt:1333-1395` |
| `startStreaming` forced recovery loops or skips a healthy path | **No.** A healthy identical stream returns early (`:1037-1051`); otherwise `clearStreaming()` runs once, and only on failure `clearStreaming(releaseOnDrainFailure = true)` runs once. A second failure returns `usb_drain_incomplete`; there is no loop. | `:1056-1068` |
| `getDiagnostics` / `getBufferedMs` values and error handling unchanged | **Yes.** Same six keys, same `safe*` helpers, same return types; only the dispatch thread changed. | `:290-308`, `:181-188` |
| `SELECTOR_RESTORE_FAILED` cannot set `lastRateVerified = true` | **Correct.** Explicit early return at `:1152-1159`; `lastRateVerified = true` exists only in the `else` at `:1174` for `VERIFIED`. | `:1152-1176` |
| Route matching: `+50` is not a route match | **Correct.** `routeMatched` is set only by VID/PID (`:391`) or name (`:413`); `:419` adds the bonus without touching it; `:426` enforces it. | `UsbAudioControlParser.kt:373-427` |
| No mid-stream switch | **Correct.** `findAudioDevice` returns `openedDevice` first while it is still attached, before any route-aware or ordering logic. | `UsbExclusivePlugin.kt:411-419` |
| UAC1 SET/GET encodings | **Correct.** SET `0x22 / 0x01 / 0x0100 / endpoint / 3 bytes`; GET `0xA2 / 0x81 / 0x0100 / endpoint / 3 bytes` (`0x22 | 0x80`, request `0x81`). | `UsbAudioControlParser.kt:1362-1371` |
| UAC2 SET/GET, validity, selector, 4-byte rate | **Correct.** SET `0x21/0x01/0x0100/(clock<<8)|iface/4`; GET `0xA1/0x01/.../4`; validity `0xA1/0x01/0x0200/.../1`; selector `0x21/0x01/0x0100/(selector<<8)|iface/1`; range `0xA1/0x02/0x0100/...`. No off-by-one in `bRequest`, `wValue` or `wIndex`. | `:1362-1381`, `:1412-1418`, `:1436-1445`, `:1540-1580` |
| `Abandon`/`Close`/`Open` ownership and fd handling | **Consistent.** With `alreadyConfigured = true` the native side sets `claimed_ = false` (`.cpp:257`), so `Close()` never issues `RELEASEINTERFACE`/`CONNECT` for an interface Kotlin claimed — Kotlin's `rebindKernelDriver` owns that (`UsbExclusivePlugin.kt:1285-1312`). `Open` joins a stale worker before touching storage and refuses to start over unreturned URBs. | `.cpp:129-185`, `:257`, `:783-794` |
| Stale `lastError` | **One case:** after `Abandon` — F3. Otherwise `Open` clears it (`:163`) and a successful drain clears a latched `EPROTO` (`:613`). | F3 |
| `std::terminate` | **No path found.** `Close()` always joins a joinable worker before returning; `Open()` joins before reassigning; `~UsbAudioSink` joins before anything else. | `.cpp:89-111`, `:142-146`, `:413-416` |
| Double free / use-after-free | **None found.** `Abandon` frees the ring only after joining the worker and draining an admitted writer; the leaked payloads are never `delete[]`-ed afterwards because the vectors are cleared. `closeLocked` closes the connection only after `Abandon` has dropped the fd reference. | `.cpp:424-499`, `UsbExclusivePlugin.kt:1474-1490` |

---

## 6. Recommended fixes, in order

1. **(P1, blocks merge)** Keep the deliberate leak, but stop LSan reporting it: add `__lsan_ignore_object` at
   `UsbAudioSink.cpp:465-469` (weak/feature-guarded) **or** set `ASAN_OPTIONS=detect_leaks=0` for the Debug
   CTest pass in `scripts/run_native_dsp_tests.sh`. Confirm with one Linux run of
   `bash scripts/run_native_dsp_tests.sh`.
2. **(P3)** Bound the unrecognized-completion path in `drainUrbCompletions` (`UsbAudioSink.cpp:585-601`).
3. **(P3)** Decide `lastError_` on `Abandon` (`UsbAudioSink.cpp:424-499`) and make the status honest either way.
4. **(P3)** Add a back-to-back `Abandon(); Abandon(); Open(...)` regression to `test_usb_sink.cpp`.
5. *(Optional)* Remove or explicitly document `ParseSupportedRatesFromDescriptors` as test-only API.

---

## 7. Limits of this review

- **No hardware.** USB claim/alt-setting/clock programming against a real DAC, `USBDEVFS_*` behaviour and the
  ALSA rebind ordering are unexercised; the host test can only reach the non-usbfs stub.
- **No runtime sanitizer evidence.** The Debug ASan build links but cannot execute on this Windows host
  (`0xC0000135`). F1 is therefore a mechanism-level inference, clearly labelled as such.
- `routeAwareAudioDevice` is Android-only and has no unit test; its behaviour was verified by reading the code
  and the parser test it delegates to.
- Android `UsbDeviceConnection`/`AudioManager` behaviour under two attached DACs was not verified on a device.

## 8. Out of scope (noted, not investigated)

- The pre-existing `FloatDspAudioSinkTest.java` mismatch that forces `-x :app:compileDevDebugUnitTestJavaWithJavac`.
- `HiResDacPlugin.kt:1759` calls `selectPreferredAudioDevice` without `requireRouteMatch`; that is a
  "preferred device" query rather than the streaming path, so it is unaffected by P3-5.
