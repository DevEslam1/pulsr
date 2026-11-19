# USB UAC1/UAC2 Fix Set — Independent Review #3 (final four changes)

**Repository:** `D:\Courses\Projectss\pulsr` (working tree dirty with the intended fixes; no source file was edited,
committed, reset or checked out during this review — the only file written is this one)
**Date:** 2026-11-19
**Reviewer:** independent USB Audio Class review (third pass, limited to the four follow-up items of review #2)
**Verdict:** **PASS on all four items — no P0/P1/P2 defect.** The LSan annotation is correctly built and complete,
the drain is now bounded on every path, `Abandon()` clears the stale error, and all four behaviours are covered by
assertions that the host binary actually executes. One **new, non-blocking P3** was introduced by the annotation:
four `-Wunused-variable` warnings in the production Android native build. Nothing functional regressed.

Severity counts: **P0 = 0 · P1 = 0 · P2 = 0 · P3 = 1.**

---

## 1. Scope and method

Reviewed the current files, not only the diff. Supporting reads: JNI bridge, Kotlin teardown state machine,
CI workflow, both CMakeLists, the native test runner script, and the Android NDK ASan runtime binary.

| File | Lines |
| :--- | ---: |
| `android/app/src/main/cpp/UsbAudioSink.cpp` | 1673 |
| `android/app/src/main/cpp/UsbAudioSink.h` | 334 |
| `android/app/src/test/cpp/test_usb_sink.cpp` | 1028 |

**Scope check — only the permitted files changed for these four items [verified].** File modification times after
the review #2 test run (JUnit written 18:48) are, in order: `UsbAudioSink.h` 18:56:19, `UsbAudioSink.cpp`
18:55:54, `test_usb_sink.cpp` 18:54:09. Every other USB-related file is older (`UsbExclusivePlugin.kt` 18:39,
`eq_jni_bridge.cpp` 18:33, the two Kotlin test files 18:31/18:32, all Dart files ≤ 18:05). The four items therefore
touched exactly the three allowed files; the `+/-1 %` cadence steering and the `alreadyConfigured` signature that
also appear in the `git diff` are review-1 items, not new scope creep.

Evidence tiers: **[verified]** = read in the current tree and/or exercised by a run here; **[inferred]** =
mechanism established from code plus documented toolchain behaviour, not executed here; **[not verified]** = could
not be established in this environment.

---

## 2. Test results

| # | Command | Result |
| :-- | :--- | :--- |
| 1 | `cmake --build android/app/build/testNative/Release --target test_usb_sink --parallel 2` | **OK** — `ninja: no work to do.` Not a stale-binary artifact: `test_usb_sink.exe` is 18:56:22, i.e. newer than both edited sources (18:55:54 / 18:54:09), so the binary already contains all three files. |
| 2 | `android/app/build/testNative/Release/test_usb_sink.exe` | **PASS**, exit 0. Output: `[TEST] USB UAC2 sink host-verifiable math...` / `[PASS] USB descriptor parsing, feedback decode, and packet sizing verified.` `check()` (`test_usb_sink.cpp:337-342`) prints `[FAIL] <what>` per failure and `main` returns the failure count, so exit 0 means **every** assertion passed, including the four new ones. |
| 3 | `gradlew :app:testDevDebugUnitTest --tests ...UsbControlProtocolTest --tests ...UsbAudioControlParserTest -x :app:compileDevDebugUnitTestJavaWithJavac --offline --no-daemon` | `BUILD SUCCESSFUL in 31s` **but `:app:testDevDebugUnitTest UP-TO-DATE`** — Gradle executed nothing, so that run is *not* evidence. |
| 3b | Same command **+ `--rerun`** | `> Task :app:testDevDebugUnitTest` executed, **`BUILD SUCCESSFUL in 34s`** (450 tasks: 2 executed). This is the run the JUnit numbers below come from. |
| 4 | `gradlew :app:compileDevDebugKotlin --offline --no-daemon` | Task executed (1 of 229), **`BUILD SUCCESSFUL in 29s`**, exit 0. |
| 5 | *extra:* NDK 28.2 `clang++ --target=aarch64-linux-android26 -std=c++20 -fsyntax-only -Wall -Wextra` on `UsbAudioSink.cpp` (project's own `-Wall -Wextra` from `android/app/src/main/cpp/CMakeLists.txt:20-26`) | Exit 0, **4 warnings** — see P3-1. |
| 6 | *extra:* same flags on `eq_jni_bridge.cpp` | Exit 0, **0 warnings** — the header/JNI contract still matches after the `.h` edit. |

JUnit XML (`build/app/test-results/testDevDebugUnitTest/`, timestamp `2026-11-19T17:01:11Z`):

| Suite | Tests | Failures | Errors | Skipped |
| :--- | ---: | ---: | ---: | ---: |
| `com.pulsr.music.UsbAudioControlParserTest` | 39 | 0 | 0 | 0 |
| `com.pulsr.music.UsbControlProtocolTest` | 50 | 0 | 0 | 0 |
| **Total** | **89** | **0** | **0** | **0** |

`-x :app:compileDevDebugUnitTestJavaWithJavac` was needed only because of the **pre-existing, unrelated**
`FloatDspAudioSinkTest.java` mismatch. It is not a USB finding and was not investigated.

---

## 3. Item 1 — LSan annotation (`UsbAudioSink.cpp:73-90`, `129-139`, `496-511`)

**Guard ladder [verified].** `defined(__has_feature)` → `__has_feature(address_sanitizer)` (Clang), then
`__SANITIZE_ADDRESS__` (GCC); only if one is set **and** `__linux__ || __ANDROID__` is defined is the symbol
declared and called (`:86-88`), otherwise the macro is `((void)0)` (`:90`). On this Windows host the guard is
false, and the host build compiles and links with no undefined symbol — the no-op is real, not an accidental
declaration.

**The `new` side effect is not swallowed [verified].** Both call sites bind the allocation to a local first
(`auto* leakedOut = new ...;` at `:130`, `:497`) and only then annotate it. A `(void)0` expansion therefore cannot
drop the allocation or the `std::move`. This is the right pattern and it survives the P3-1 fix below.

**Coverage is complete [verified].** All four allocations are annotated:
- destructor: `leakedOut` `:131`, `leakedIn` `:133`;
- `Abandon()`: `leakedOut` `:498`, `leakedIn` `:502`;
- every payload array in `urbBuffers_` `:134-136` and `feedbackBuffers_` `:137-139` / `:504-506`, `:507-509`,
  each null-checked before annotation.

**Does the vector's internal buffer need its own annotation? No [verified against the tool's documentation].**
LeakSanitizer documents `__lsan_ignore_object(const void *p)` as marking "the heap object pointed to by `p`
(and anything reachable from it) as a non-leak"
([clang.llvm.org/docs/LeakSanitizer.html](https://clang.llvm.org/docs/LeakSanitizer.html)). The `std::vector`
object holds its begin/end/capacity pointers, so the moved-in heap buffer is reachable from the ignored object and
is covered. Annotating the buffer separately would be redundant.

**The Android branch links [verified on the real runtime binary].** `llvm-nm -D --defined-only` on
`ndk/28.2.13676358/.../libclang_rt.asan-aarch64-android.so` lists `T __lsan_ignore_object` (plus
`__lsan_disable/enable/do_leak_check`), so the `__ANDROID__` + ASan combination resolves at link time rather than
failing on a missing symbol. NDK 27/29/30 ship the same family of runtimes.

**No new leak for real allocations [verified].** The annotation allocates no user memory and is applied only on the
two abandon paths; the normal frees are untouched (`releaseResources` `:812-823`, `freeFeedbackResources`
`:766-780`). The only allocations that stay unreachable at exit are the deliberate ones.

**Residual: the LSan report itself is [inferred], not observed.** This host is Windows with no WSL and no
LSan-capable runtime (review #2 already established that the instrumented Windows binary does not load), so
"no LSan report remains" follows from the documented `ignore_object` semantics plus verified symbol availability —
it is not an executed leak check. The CI job that needs it is `native-dsp-tests` → `ubuntu-latest` → `clang` →
`bash scripts/run_native_dsp_tests.sh` (`.github/workflows/ci.yml:124-138`), which builds Debug with
`-DPULSR_TEST_SANITIZERS=ON` and runs `ctest` with **no** `ASAN_OPTIONS`, i.e. LSan active. One Linux run of that
script would close the loop.

---

## 4. Item 2 — Bounded drain (`UsbAudioSink.cpp:593-664`)

**Deadline is checked every iteration [verified].** `deadline` is computed once (`:620-621`) and tested at the
**top** of the `while` body (`:627`), before every `reap`, so the loop is bounded on three distinct paths:
idle `EAGAIN` (1 ms backoff, `:635-637`), a hard reap error (returns immediately, `:629-634`), and a **successful
reap of a pointer this sink does not own** (`markReaped` fails → `EPROTO` + `sawUnknownCompletion`, `:640-649`,
then loops). The previous unbounded path — reaps that keep succeeding with foreign/duplicate pointers — is gone.

**Timeout retains ownership and reports honestly [verified].** After the break, `hasOutstandingUrbs()` still true →
`lastError_ = ETIMEDOUT` (`:652`) and `return false` (`:653`), with header storage, payloads, the interface claim
and `exclusive_` all untouched (`:650-652`). Nothing is freed.

**The host foreign-pointer test really drives it [verified by run].**
`UsbAudioSinkTestAccess::duplicateCompletionDrainIsBounded` (`test_usb_sink.cpp:221-229`) stages one OUT and one IN
URB and calls `drainUrbCompletions(20, reapAlwaysForeign)`; `reapAlwaysForeign` (`:76-79`) always "succeeds" with
`&gUsbStrangerUrb`. Under the old code that loop never re-enters the deadline check and the test hangs; now it
returns `false` with `ETIMEDOUT` while `IsExclusive()`, `hasOutstandingUrbs()` and both storage vectors survive —
all asserted.

**The 0 ms case is legitimate [verified].** `std::max(0, timeoutMs)` (`:621`) with `0` makes the first deadline
test true, so the call performs zero reaps and reports `ETIMEDOUT` when anything is outstanding. The header states
this explicitly (`.h:203-204`: "timeoutMs = 0 budgets no reaps at all, so it can only succeed when nothing is
outstanding"), and the only production caller uses the 2000 ms default (`:810`). Tests use `0` precisely to prove
retention without burning wall-clock, and `unknownCompletionClearsProtocolError` was deliberately moved to
`1000` ms (`:236-238`) because a 0 ms drain now performs no reaps — the test encodes the new semantics rather than
working around them.

**No unbounded path remains in the drain.** The only indefinite wait left in teardown is the writer-gate spin
(`releaseResources` `:787-789`, `Abandon` `:465-467`), which waits for an already-admitted producer to leave, not
for the kernel to return URBs; it is pre-existing, was accepted in review #2, and `endWrite()` clears the bit
without taking `controlMutex_` (no lock-order inversion).

---

## 5. Item 3 — `Abandon()` and `lastError_` (`UsbAudioSink.cpp:454-542`)

**`lastError_` is cleared [verified].** `lastError_.store(0, release)` at `:542`, after `claimed_ = false`, `fd_ = -1`
and `exclusive_.store(false)` (`:534-538`), so the status/diagnostics maps built from `GetLastError()`
(`UsbExclusivePlugin.kt:299`, `:746`) stop reporting a dead stream.

**A failed-drain `Close()` still returns false and keeps `ETIMEDOUT` [verified].** `releaseResources()` returns at
`:810` *before* the `exclusive_.store(false)` at `:839`, so the claim stays live; `nativeUsbStreamStop` maps
`Close()` to `JNI_FALSE` (`eq_jni_bridge.cpp:1756-1763`), and `UsbExclusivePlugin.clearStreaming` turns that into
`usb_drain_incomplete` (`:1445-1449`). Tests assert the return values that were previously ignored:
`!sink.releaseResources()` + `ETIMEDOUT` (`test:284-292`), `!sink.Close()` on undrained ownership (`:315-319`), and
`drainFailed` inside `abandonRecoversCleanStart` (`:199-201`).

**`Abandon()` is idempotent [verified by run].** The second call closes an already-closed gate, finds no joinable
worker, no outstanding URBs and empty storage, so it allocates nothing new, issues no ioctl (`fd_ == -1`) and only
re-stores the same scalars. Test: two back-to-back calls with `pristine()` re-asserted after the second
(`:189-215`).

**Double `Abandon()` + `Open` reaches the normal host path, not `ClaimFailed` [verified by run].** `Open` first
rejects a live sink (`:196-199`), then requires `releaseResources()` to succeed and `hasOutstandingUrbs()` to be
false (`:206-211`); after `Abandon` both hold, so on this host it proceeds to the `#else` branch and returns
`InvalidArgs` (`:421-425`). Asserted exactly (`reopened`, `:212-214`).

**No double free / use-after-free [verified by inspection].** `Abandon` frees only the ring (`ring_.clear()` +
`shrink_to_fit()`) after joining the worker and draining an admitted writer; the URB header storage is *moved* into
a leaked vector (allocation address preserved, so every pointer in `urbs_` stays valid), payload pointers are
dropped without `delete[]`, and every later `Close`/`Open` finds empty vectors and `fd_ == -1`, so nothing frees
them twice. After `Abandon`, `drainUrbCompletions` returns at `!hasOutstandingUrbs()` (`:594`) and never
dereferences the abandoned storage.

**`lastError = 0` does not hide a live fault [verified].** `Abandon` is reached only from
`clearStreaming(releaseOnDrainFailure = true)` **after** a failed drain (`UsbExclusivePlugin.kt:1355-1372`), i.e.
after the caller has decided to release the interface and close the connection. A *successful* drain never calls
`Abandon`, so a genuine worker error (e.g. `EPIPE` latched at `:1223`) is still reported by the next status read.
There is no path where a live stream's error is wiped.

---

## 6. Item 4 — Do the tests assert the changes?

Yes — every item has a behavioural assertion that the release host binary executes; none is compile-only.

| Item | Assertion | Would it catch a regression? |
| :--- | :--- | :--- |
| LSan annotation | Not directly assertable (no LSan on this host). Covered indirectly by the P3-1 compile check and in CI by `ctest` under ASan. | Only on Linux/CI [inferred] |
| Deadline at loop top | `duplicateCompletionDrainIsBounded` returns `false` + `ETIMEDOUT`, storage/claim retained, with an always-foreign reap (`test:221-229`, `:829`) | **Yes** — hangs on the old code |
| Timeout retention | `drainDeadlineRetainsOwnership` with `reapNever` and 0 ms (`:178-187`, `:827`) | Yes |
| `Abandon` clears `lastError_` | `GetLastError() == 0` inside `pristine()` after `Abandon` (`:192-197`, `:207-209`) | **Yes** — fails on the old code (ETIMEDOUT) |
| Double `Abandon` | Second call + `pristine()` again (`:204-209`) | Yes |
| Next `Open` clean | `Open(...) == UsbStreamResult::InvalidArgs`, not `ClaimFailed` (`:212-214`) | Yes (guards the claim ladder) |
| Drain return values | `!releaseResources()`, `!Close()`, then `Close()` true (`:287-299`, `:315-322`, `:791-797`) | Yes — previously discarded |

---

## 7. New-regression checklist

| Question | Answer | Evidence |
| :--- | :--- | :--- |
| `Abandon()` must not free kernel-owned pointers | **Correct.** Header storage is moved into a leaked vector (addresses preserved), payload arrays are dropped without `delete[]`. | `.cpp:490-511` |
| `Abandon()` safe if called twice | **Yes**, and now tested. | `.cpp:454-542`, `test:189-215` |
| `lastError = 0` hides a live fault | **No.** Only the forced post-failure path clears it; a successful drain never abandons. | `UsbExclusivePlugin.kt:1355-1372` |
| `drain` still returns false on `ETIMEDOUT` | **Yes**, and the false return now propagates through `nativeUsbStreamStop` to `usb_drain_incomplete`. | `.cpp:650-653`, `eq_jni_bridge.cpp:1756-1763`, `UsbExclusivePlugin.kt:1445-1449` |
| `Close`/`Open` ownership intact | **Yes.** `Open` refuses on outstanding URBs; `Close` fails without clearing `exclusive_`; both clear the claim only after a proven drain. | `.cpp:206-211`, `:810`, `:839` |
| Writes/`submitAll` unchanged by the annotation | **Yes.** The four annotation sites are inert in production builds. | `.cpp:129-139`, `:496-509` |
| New unbounded loop introduced | **No.** The drain is bounded at `:627`; the writer-gate spin is pre-existing and unrelated. | `.cpp:620-653` |
| Double free / use-after-free | **None found.** Empty vectors + `fd_ = -1` after `Abandon` mean no later path frees the moved/dropped buffers. | `.cpp:512-538` |

---

## 8. Findings

### P3-1 (new, non-blocking): the annotation adds four `-Wunused-variable` warnings to the production Android build

**Where:** `UsbAudioSink.cpp:130`, `:132`, `:497`, `:501`; guard at `:86-90`.
**Evidence [verified by compiling the TU with the NDK toolchain and the project's own flags]:**

```text
android/app/src/main/cpp/UsbAudioSink.cpp:130:15: warning: unused variable 'leakedOut' [-Wunused-variable]
android/app/src/main/cpp/UsbAudioSink.cpp:132:15: warning: unused variable 'leakedIn'  [-Wunused-variable]
android/app/src/main/cpp/UsbAudioSink.cpp:497:15: warning: unused variable 'leakedOut' [-Wunused-variable]
android/app/src/main/cpp/UsbAudioSink.cpp:501:15: warning: unused variable 'leakedIn'  [-Wunused-variable]
4 warnings generated.
```

`android/app/src/main/cpp/CMakeLists.txt:20-26` sets `-Wall -Wextra` globally (with only `-Werror=return-type`), so
every Gradle/Studio native build now prints these four warnings in a translation unit that was otherwise
warning-clean (same compile produced no other diagnostic). Nothing fails: `-Werror` is not enabled, and the
sanitizer branch uses the variable so CI/LSan builds are silent.

**Why it happens:** in non-ASan builds the macro expands to `((void)0)`, which does not consume its argument, so
the bound local is genuinely unused. Binding the pointer to a local was the right call for the `new` side effect —
the fix is to make the no-op branch consume it instead.

**Fix (one line, `.h`-free):**

```cpp
#else
#define PULSR_LSAN_IGNORE_OBJECT(ptr) ((void)(ptr))   // was ((void)0)
#endif
```

`(void)(ptr)` still evaluates and discards the expression, so the "never swallow the `new`" property is preserved
(strictly strengthened), the call sites keep their explicit locals, and the four warnings disappear.

---

## 9. Notes (observed, not counted as findings)

1. **macOS is excluded from the guard.** LSan's documented supported platforms include macOS, but `:86` requires
   `__linux__ || __ANDROID__`, so a Mac developer running `scripts/run_native_dsp_tests.sh` would still fail the
   Debug sanitizer pass on the deliberate leak. CI is Ubuntu-only and the platform gate is what keeps a Windows
   ASan build (no LSan) linkable, so this is a defensible trade-off; adding `|| defined(__APPLE__)` would close it
   if Macs are supported dev hosts. [inferred]
2. **Stale counters after `Abandon`.** `underrunCount_` / `overrunCount_` are zeroed by the next `Open`
   (`.cpp:215-218`), not by `Abandon`, so diagnostics read between the forced teardown and the next open can show
   the dead stream's counters alongside `isStreamActive = false`. Cosmetic; `lastError` was the item in scope.
3. **`Abandon` leaks header storage whenever it is non-empty, without consulting `hasOutstandingUrbs()`**
   (`.cpp:496-502`), unlike the destructor (`:121-139`). Only the failed-drain caller reaches it, where outstanding
   URBs are guaranteed, so a clean stop cannot leak; noted only for symmetry with the destructor's condition.

---

## 10. Limits of this review

- **No Linux/ASan execution.** Windows host, no WSL, and the instrumented Windows binary does not load (review #2),
  so "no LSan report remains" is a documented-semantics inference plus a verified symbol, not an observed run.
- **No USB hardware**, as before: claim/alt-setting/clock programming, `USBDEVFS_*` and ALSA rebind ordering are
  unexercised; the host test can only reach the non-usbfs stub.
- The NDK compile in §2/#5 is `-fsyntax-only` with the project's warning flags, not a full Gradle native build.

## 11. Out of scope (noted only)

- The pre-existing `FloatDspAudioSinkTest.java` mismatch that forces `-x :app:compileDevDebugUnitTestJavaWithJavac`.
- The `+/-1 %` cadence-steering widening: review-1 item, unchanged by these four changes, its tests pass.
- `ParseSupportedRatesFromDescriptors` remains test-only API (review #2 residual note).

## 12. Recommendation

Apply the one-line P3-1 macro fix, then merge. Confirm the LSan outcome with one Linux run of
`bash scripts/run_native_dsp_tests.sh`; nothing else in the four items needs to change.
