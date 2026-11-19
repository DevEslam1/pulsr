# Pulsr USB Audio Class HIL harness

Hardware-in-the-loop (HIL) gates for the USB DAC path. Every gate is designed to
answer one question **honestly**:

> Did a real attached device produce evidence that this case works?

If the answer is "no evidence", the gate reports `status: "blocked"` and exits 0
(exit 2 with `--gate`). It does **not** report a pass, and it does not invent
zeroes for counters it never read.

---

## 1. Quick start

Windows (PowerShell 5.1):

```powershell
cd 'D:\Courses\Projectss\pulsr'
python scripts/hil/run_matrix.py --dry-run --out scratch/hil/matrix.json
python scripts/hil/smoke.py --dry-run --out scratch/hil/smoke.json
python scripts/hil/soak.py --dry-run --out scratch/hil/soak.json
python scripts/hil/unplug_replug.py --dry-run --out scratch/hil/unplug.json
python scripts/hil/analyze_results.py scratch/hil/*.json --out scratch/hil/summary.md
python scripts/hil/tests/test_hil_common.py

# PowerShell wrappers forward arguments and exit codes unchanged
powershell -NoProfile -File scripts/hil/run_matrix.ps1 -DryRun -Out scratch/hil/matrix_ps.json
```

Linux / CI (bash):

```bash
python3 scripts/hil/run_matrix.py --tier A --gate --out scratch/hil/matrix.json
python3 scripts/hil/analyze_results.py scratch/hil/*.json --out scratch/hil/summary.md
python3 scripts/hil/bundle_evidence.py --inputs scratch/hil
```

With no DAC attached, every command above reports `blocked` / `no_device`. That
is the expected result on a developer laptop and is not a failure.

---

## 2. Exit codes

| Code | Meaning |
| :--- | :--- |
| 0 | `pass`, or `blocked` without `--gate` (honest "not evaluated") |
| 1 | `fail` - a device was present and a gate was violated |
| 2 | `blocked` **with** `--gate` (CI hardware gate not met) |
| 3 | `error` - unexpected condition (corrupt input, broken rig command) |

`analyze_results.py` uses 0 = green, 1 = red (failure/error/unreadable evidence),
2 = blocked (not green, not red). An empty input set is 2: no evidence is not
evidence of health.

---

## 3. Result schema

Every gate writes one JSON document (`kind` distinguishes the gate):

```json
{
  "schemaVersion": 1,
  "kind": "matrix | smoke | soak | unplug_replug | bitexact",
  "status": "pass | fail | blocked | error",
  "reason": "no_device | null | ...",
  "generatedAt": "2026-11-19T12:34:56.789Z",
  "build": "1703058e",
  "environment": { "os": "...", "adb": "...", "devices": [] },
  "parameters": {},
  "metrics": {
    "startMs": null, "stopMs": null, "underrunCount": null, "overrunCount": null,
    "driftPpm": null, "bufferMs": null, "cpuPct": null, "memMb": null
  },
  "cases": [],
  "blockers": [],
  "artifacts": []
}
```

Rules that matter:

* **`null` means "not measured"** - it never means zero. A real `underrunCount: 0`
  is a measurement; `null` is an absent measurement.
* `status: "pass"` requires at least one device-produced case, and no non-pass
  case.
* `status: "blocked"` always carries a `reason` and at least one entry in
  `blockers`.
* `build` is `git rev-parse --short HEAD` or the literal string `unknown`.
* Device serials are stored redacted (`<redacted:hash8>`) in `environment`.
* `soak` and `unplug_replug` add a top-level `summary` object (total frames,
  expected vs actual duration, worst recovery, etc.).

`hil_common.validate_result()` enforces all of the above; the test suite asserts
that a fabricated pass is rejected.

---

## 4. Device detection

Performed on every run:

1. `adb devices -l` - any device in state `device` is usable. Zero devices or a
   missing adb => `blocked` / `no_device` (never a pass).
2. `adb -s <serial> shell getprop ro.build.version.sdk` - recorded when available.
3. `adb -s <serial> shell dumpsys usb`, falling back to `adb -s <serial> shell
   lsusb`, looking for interface class 1 (audio), `UAC1`/`UAC2`, `DAC`, `audio`,
   `headset`.

The USB scan is a **heuristic**. It decides whether it is worth trying to use a
device; it never upgrades a case to `pass`. If the scan finds no audio endpoint
the matrix reports `blocked` / `no_usb_audio_endpoint`.

Gates that measure playback (`smoke`, `soak`, `unplug_replug`) run the same
endpoint check before touching the rig, so a phone with no DAC attached cannot
silently produce speaker measurements labelled as USB evidence. The SDK level
from `getprop` is recorded as `environment.androidSdk`.

`--adb PATH` exists for rigs with adb outside `PATH` and for hermetic tests.
`--serial SERIAL` pins one device when several are attached.

---

## 5. Gate reference

### 5.1 `run_matrix.py`

Iterates the built-in Tier A/B list (18 targets): UAC1 FS 44.1/48, UAC1 HS
96/192, UAC2 HS async 44.1/48/96/192/384, 24-in-32, hardware-volume DAC,
feedback-less dongle, 705.6/768 kHz, DoP, 6/8-channel, 32-bit 384 kHz.

```
--tier A|B|all   --matrix FILE   --dry-run   --out PATH   --gate
--play-cmd CMD   --adb PATH      --serial S   --timeout S  --list
```

A custom matrix is a JSON list (or `{"cases": [...]}`) or a YAML-ish list:

```yaml
- id: my-dac-48k
  tier: A
  class: UAC2
  rate: 48000
  bits: 24
  channels: 2
  label: "Bench DAC"
  features: [async, uac2]
```

Case verdicts are only `pass`/`fail` when a `--play-cmd` probe ran for that case.
Without it: `blocked` / `no_playback_driver`.

### 5.2 `smoke.py`

Start latency < 500 ms, stop latency < 300 ms, zero underrun growth over
`--duration` (default 60 s). Metrics come from the rig driver; missing metrics
produce `blocked` / `metric_unavailable`, not a pass.

### 5.3 `soak.py`

Gapless playlist loop for `--hours` (default 8), sampling every
`--sample-interval` (default 10 s). Detects counter regressions (a counter that
decreases invalidates the evidence), gates on `--max-drift-ppm` (default 100),
`--max-underruns` / `--max-overruns` growth (default 0). Samples are written to
`<out>.samples.jsonl` and referenced in `artifacts`.

`--max-samples N` bounds the run for local verification and sets
`parameters.truncated = true`; a truncated run never claims more than it measured.

### 5.4 `unplug_replug.py`

`--cycles` (default 500) with `--relay-cmd`. Per cycle: relay off, hold
`--settle`, relay on, poll for recovery. Asserts every `recoveryMs < 2000`,
a single stable pid, and `drainPending` cleared.

Without `--relay-cmd` the gate reports `blocked` / `no_relay` and claims **zero**
cycles (`parameters.cyclesCompleted = 0`). When no device is attached at all,
`no_device` takes precedence and `no_relay` is still listed in `blockers`.

Relay contract (`--relay-cmd`): any command template with `{action}` (`off` or
`on`), `{cycle}` and `{serial}` placeholders, e.g.

```
python tools/relay_usb.py --port COM7 --state {action}
```

Exit code 0 means the relay actuated. Non-zero aborts the run with `error`.

### 5.5 `capture_bitexact.py`

Compares a captured WAV/raw payload against the source **byte for byte**:

```
--source FILE --capture FILE [--raw --bits 24 --channels 2 --rate 48000]
--allow-ulp 0 (default; any other value is rejected)
```

Parses RIFF/WAVE chunks (16/24/32-bit PCM), compares only the `data` payload,
and reports sha256 of both payloads plus the payload-relative first differing
byte. Missing capture => `blocked` / `no_capture`. Format differences (bits,
rate, channels, block align) fail the `format_match` case before the byte
comparison is trusted.

---

## 6. Rig driver contract (`--driver-cmd`)

The harness does not talk to a DAC itself: the rig owns that. A driver is a
command template; the harness substitutes `{action}`, `{serial}`, `{case}`,
`{cycle}`, `{hours}`, `{durationS}` and expects **one JSON object as the last
stdout line**:

| action | required JSON | used by |
| :--- | :--- | :--- |
| `start` | `{"startMs": 123}` | smoke, soak, matrix |
| `stats` | `{"frames": 480000, "sampleRate": 48000, "underrunCount": 0, "overrunCount": 0, "bufferMs": 8, "cpuPct": 3.1, "memMb": 210}` | smoke, soak |
| `stop` | `{"stopMs": 88}` | smoke |
| `status` | `{"recovered": true, "pid": 4242, "drainPending": false, "recoveryMs": 640}` | unplug |
| matrix probe | `{"status": "pass|fail|blocked", "reason": null, "evidence": {...}}` | matrix |

Non-zero exit or unparsable output becomes `error` (3) - never a silent pass.
Drivers may return `{"status": "blocked", "reason": "..."}` to refuse a run; that
is propagated honestly.

---

## 7. Analysis and evidence

`analyze_results.py` aggregates gate JSONs into `summary.md` + `summary.json`:
verdict GREEN/RED/BLOCKED, per-file table, blocked reasons, failing cases, and
skipped inputs (e.g. a previous `summary.json`). It accepts directories, files
and shell-style globs; PowerShell does not expand wildcards for native
executables, so the script expands them itself.

`bundle_evidence.py` builds `dist/usb-evidence/<build>-<timestamp>.zip`:

* entries sorted, fixed zip timestamps => byte-identical archives for identical
  inputs and `--timestamp`;
* `manifest.json` with `bytes` + `sha256` for every entry;
* files whose names match `*serial*` or `*pii*` are **refused** and listed under
  `excluded`;
* symlinks and the output directory itself are skipped;
* the last stdout line is the absolute zip path.

Serials in result JSON are redacted, and raw `adb`/`dumpsys` output is never
stored - only counts and redacted matching lines.

---

## 8. CI (`.github/workflows/usb-hil.yml`)

| Job | Runner | Trigger | Behaviour |
| :--- | :--- | :--- | :--- |
| `native-sanitizers` | `ubuntu-latest` | all triggers | `cmake -S android/app/src/test/cpp -DPULSR_TEST_SANITIZERS=ON`, build, `ctest` |
| `kotlin-usb` | `ubuntu-latest` | all triggers | `:app:testDevDebugUnitTest` filtered to the USB control tests |
| `hil-matrix` | `[self-hosted, android-usb]` | nightly Tier A, weekly full, manual | `run_matrix.py --gate` |
| `hil-soak` | `[self-hosted, android-usb]` | nightly (needs matrix) | `soak.py --hours 8 --gate` |

Exit 2 from `--gate` is mapped to a workflow **warning**, not a failure: an
absent DAC must not turn the repository red. Exit 1 (a real device run that
failed) fails the job. The soak job waits for the matrix job and is skipped when
the matrix job fails.

The self-hosted runner needs `python3`, a working `adb`, and the app under test
installed. If no runner with the `android-usb` label is registered, GitHub will
queue the job - that is a runner provisioning issue, not a gate result.

Unplug/replug runs are not scheduled by default because they need physical relay
hardware. Add a job using the same pattern with:

```
python3 scripts/hil/unplug_replug.py --relay-cmd "<your relay command>" --gate --out scratch/hil/unplug.json
```

---

## 9. What is deliberately not claimed

* No sample-rate capability is inferred from `adb`. Only a probe on the rig can
  produce a case verdict.
* No playback simulation: without `--driver-cmd` there is no latency, underrun,
  drift or recovery number, and the result is `blocked`.
* `--allow-ulp` above 0 is refused: this harness has no dithering tolerance.
* Blocked results are never summarized as green by `analyze_results.py`, even
  when every blocked gate exited 0.
