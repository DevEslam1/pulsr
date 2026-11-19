#!/usr/bin/env python3
"""Shared plumbing for the Pulsr USB Audio Class hardware-in-the-loop harness.

Honesty rule for every gate built on this module:

  * status="pass" may only come from evidence a real attached device produced
    during this run.
  * status="blocked" means the gate could not be evaluated (no device, no
    relay, no playback driver, no capture).  Blocked is not "pass", and it is
    not a failure either.
  * metrics that were not measured are null - never 0.  A zero underrun count
    is a measurement, absence of the measurement is null.

Nothing in this file fabricates device data.  If adb is missing or no device is
attached, callers must emit a blocked result with reason="no_device".
"""

from __future__ import annotations

import datetime as _dt
import glob as _glob
import hashlib
import json
import os
import platform
import re
import shlex
import shutil
import struct
import subprocess
import sys

SCHEMA_VERSION = 1
KINDS = ("matrix", "smoke", "soak", "unplug_replug", "bitexact")
STATUSES = ("pass", "fail", "blocked", "error")
METRIC_KEYS = (
    "startMs",
    "stopMs",
    "underrunCount",
    "overrunCount",
    "driftPpm",
    "bufferMs",
    "cpuPct",
    "memMb",
)

EXIT_OK = 0
EXIT_FAIL = 1
EXIT_BLOCKED_GATE = 2
EXIT_ERROR = 3

# Markers that suggest a USB audio endpoint in `adb shell dumpsys usb` /
# `adb shell lsusb` output.  This is a heuristic: it decides whether it is
# worth *trying* to use a device, never whether a case passed.
_USB_AUDIO_HINTS = (
    re.compile(r"\bclass[\s:=]+0*1\b", re.IGNORECASE),
    re.compile(r"\buac\s?[12]\b", re.IGNORECASE),
    re.compile(r"\bdac\b", re.IGNORECASE),
    re.compile(r"\baudio\b", re.IGNORECASE),
    re.compile(r"\bheadset\b", re.IGNORECASE),
    re.compile(r"\b0x01\b", re.IGNORECASE),
)


class HilError(RuntimeError):
    """Expected, user-facing failure: printed as one line, never a traceback."""


# --------------------------------------------------------------------------
# Time, paths, process helpers
# --------------------------------------------------------------------------


def iso_now():
    """UTC timestamp with millisecond precision, e.g. 2026-11-19T09:31:02.114Z."""
    now = _dt.datetime.now(_dt.timezone.utc)
    return now.strftime("%Y-%m-%dT%H:%M:%S.") + "%03dZ" % (now.microsecond // 1000)


def parse_iso(value):
    """Parse an ISO-8601 string; raises ValueError when malformed."""
    if not isinstance(value, str):
        raise ValueError("not a string")
    return _dt.datetime.fromisoformat(value.replace("Z", "+00:00"))


def repo_root(start=None):
    """Walk up from this file until a repo marker (.git or pubspec.yaml) is found."""
    fallback = os.path.abspath(start or os.path.dirname(os.path.abspath(__file__)))
    current = fallback
    while True:
        if os.path.isdir(os.path.join(current, ".git")) or os.path.isfile(
            os.path.join(current, "pubspec.yaml")
        ):
            return current
        parent = os.path.dirname(current)
        if parent == current:
            return fallback
        current = parent


def default_out(kind):
    return os.path.join(repo_root(), "scratch", "hil", "%s.json" % kind)


def ensure_parent(path):
    parent = os.path.dirname(os.path.abspath(path))
    if parent:
        os.makedirs(parent, exist_ok=True)
    return path


def run_cmd(argv, timeout=30, cwd=None):
    """Run a command without ever raising for expected conditions.

    Returns {"rc": int|None, "stdout": str, "stderr": str, "error": str|None}.
    rc is None when the process could not be started or timed out.
    """
    try:
        proc = subprocess.run(
            argv,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
            cwd=cwd,
            encoding="utf-8",
            errors="replace",
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
        return {
            "rc": proc.returncode,
            "stdout": proc.stdout or "",
            "stderr": proc.stderr or "",
            "error": None,
        }
    except FileNotFoundError as exc:
        return {"rc": None, "stdout": "", "stderr": "", "error": "command not found: %s" % (exc.filename or argv[0])}
    except subprocess.TimeoutExpired:
        return {"rc": None, "stdout": "", "stderr": "", "error": "timed out after %ss" % timeout}
    except OSError as exc:
        return {"rc": None, "stdout": "", "stderr": "", "error": str(exc)}


def git_short_sha(root=None, timeout=15):
    """Short HEAD sha, or the literal string "unknown" - never invented."""
    res = run_cmd(["git", "-C", root or repo_root(), "rev-parse", "--short", "HEAD"], timeout=timeout)
    out = (res["stdout"] or "").strip()
    if res["rc"] == 0 and re.fullmatch(r"[0-9a-f]{7,40}", out):
        return out
    return "unknown"


# --------------------------------------------------------------------------
# Redaction
# --------------------------------------------------------------------------

_EMAIL_RE = re.compile(r"[\w.+-]+@[\w-]+\.[\w.-]+")
_IPV4_RE = re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b")
_MAC_RE = re.compile(r"\b(?:[0-9a-fA-F]{2}[:-]){5}[0-9a-fA-F]{2}\b")
# Uppercase + digit alphanumeric token of length >= 8: the usual Android serial
# shape (R58M1234ABCD).  Lowercase hex (git shas, sha256 digests) is left alone
# so evidence manifests stay verifiable.
_SERIALISH_RE = re.compile(r"\b(?=[A-Za-z0-9]{8,}\b)(?=[A-Za-z0-9]*[A-Z])(?=[A-Za-z0-9]*\d)[A-Za-z0-9]+\b")


def token_hash(token):
    return hashlib.sha256(token.encode("utf-8", "replace")).hexdigest()[:8]


def redact_token(token):
    if not token:
        return token
    return "<redacted:%s>" % token_hash(str(token))


def redact_text(text, serials=()):
    """Mask emails, IPs, MACs, serial-shaped tokens and explicitly known serials."""
    if not isinstance(text, str) or not text:
        return text
    out = text
    for serial in serials:
        if serial:
            out = re.sub(re.escape(serial), redact_token(serial), out)
    out = _EMAIL_RE.sub("<redacted:email>", out)
    out = _MAC_RE.sub("<redacted:mac>", out)
    out = _IPV4_RE.sub("<redacted:ip>", out)
    out = _SERIALISH_RE.sub(lambda m: redact_token(m.group(0)), out)
    return out


def redact_obj(obj, serials=()):
    if isinstance(obj, str):
        return redact_text(obj, serials)
    if isinstance(obj, list):
        return [redact_obj(item, serials) for item in obj]
    if isinstance(obj, dict):
        return {key: redact_obj(value, serials) for key, value in obj.items()}
    return obj


# --------------------------------------------------------------------------
# adb device discovery
# --------------------------------------------------------------------------


def split_command(template):
    """Split a user-supplied command template, keeping Windows paths intact."""
    if not template:
        return []
    if os.name == "nt":
        if '"' in template:
            return [tok.strip('"') for tok in shlex.split(template, posix=False)]
        return template.split()
    return shlex.split(template)


def parse_adb_devices(text):
    """Parse `adb devices -l` output into a list of dicts. No text -> []."""
    devices = []
    for raw in (text or "").splitlines():
        line = raw.strip()
        if not line:
            continue
        if line.startswith("List of devices") or line.startswith("*") or line.startswith("adb server"):
            continue
        parts = line.split()
        if len(parts) < 2:
            continue
        serial, state = parts[0], parts[1]
        if state not in ("device", "offline", "unauthorized", "bootloader", "recovery", "sideload", "unknown"):
            continue
        info = {"serial": serial, "state": state}
        for token in parts[2:]:
            if ":" in token:
                key, _, value = token.partition(":")
                info[key] = value
        devices.append(info)
    return devices


def probe_adb(adb_path="auto", timeout=20):
    """Locate adb and list attached devices. Never raises for missing adb."""
    if adb_path == "auto":
        adb_path = os.environ.get("ADB") or shutil.which("adb")
    result = {
        "path": adb_path,
        "version": None,
        "devices": [],
        "error": None,
        "checked": False,
    }
    if not adb_path:
        result["error"] = "adb not found on PATH"
        return result
    if not os.path.isfile(adb_path) and not shutil.which(adb_path):
        result["error"] = "adb not found: %s" % adb_path
        return result
    result["checked"] = True
    ver = run_cmd([adb_path, "version"], timeout=timeout)
    if ver["rc"] == 0:
        lines = [line.strip() for line in (ver["stdout"] or "").splitlines() if line.strip()]
        if lines:
            result["version"] = lines[0]
    dev = run_cmd([adb_path, "devices", "-l"], timeout=timeout)
    if dev["rc"] != 0:
        result["error"] = (dev["stderr"] or "").strip()[:300] or "adb devices failed"
        return result
    result["devices"] = parse_adb_devices(dev["stdout"])
    return result


def ready_serials(probe):
    """Serials in state "device" (usable), preserving order."""
    return [d["serial"] for d in probe.get("devices", []) if d.get("state") == "device"]


def environment(probe=None):
    """Serial-redacted environment block for result JSON."""
    probe = probe if probe is not None else probe_adb()
    devices = []
    for dev in probe.get("devices", []):
        devices.append(
            {
                "serial": redact_token(dev.get("serial", "")),
                "state": dev.get("state"),
                "model": dev.get("model") or dev.get("product"),
                "device": dev.get("device"),
                "transport": dev.get("transport_id"),
            }
        )
    return {
        "os": "%s %s" % (platform.system(), platform.version() or platform.release()),
        "adb": probe.get("path"),
        "adbVersion": probe.get("version"),
        "adbError": probe.get("error"),
        "devices": devices,
        "python": sys.version.split()[0],
    }


def collect_environment(adb_path="auto"):
    return environment(probe_adb(adb_path))


def annotate_device(env_block, adb_path, serial, timeout=20):
    """Return a copy of the environment block with ro.build.version.sdk recorded."""
    annotated = dict(env_block)
    annotated["androidSdk"] = android_sdk(adb_path, serial, timeout=timeout)
    return annotated


def _is_usb_audio_line(line):
    if not line or len(line) > 400:
        return False
    return any(pattern.search(line) for pattern in _USB_AUDIO_HINTS)


def usb_audio_report(adb_path, serial, timeout=30):
    """Look for USB audio endpoints via dumpsys usb, falling back to lsusb.

    Returns a dict; detected=True only when a line matched an audio-class hint.
    Raw output is not stored - only redacted matching lines - so DAC serial
    numbers do not leak into evidence bundles.
    """
    report = {
        "source": None,
        "detected": False,
        "matches": [],
        "lineCount": 0,
        "error": None,
        "serial": redact_token(serial),
    }
    if not adb_path or not serial:
        report["error"] = "adb or serial unavailable"
        return report
    first_error = None
    for source, argv in (
        ("dumpsys_usb", [adb_path, "-s", serial, "shell", "dumpsys", "usb"]),
        ("lsusb", [adb_path, "-s", serial, "shell", "lsusb"]),
    ):
        res = run_cmd(argv, timeout=timeout)
        text = res["stdout"] or ""
        if res["rc"] != 0 or not text.strip():
            if first_error is None:
                err = (res["stderr"] or "").strip()[:200]
                first_error = err or "no output from %s" % source
            continue
        if report["source"] is None:
            report["source"] = source
            report["lineCount"] = len(text.splitlines())
        matches = []
        for idx, line in enumerate(text.splitlines(), 1):
            if _is_usb_audio_line(line):
                matches.append({"line": idx, "text": redact_text(line.strip())[:200]})
        if matches:
            report["matches"] = matches[:20]
            report["detected"] = True
            report["source"] = source
            report["lineCount"] = len(text.splitlines())
            report["error"] = None
            return report
    report["error"] = first_error
    return report


def android_sdk(adb_path, serial, timeout=20):
    """ro.build.version.sdk as int, or None when it cannot be read."""
    res = run_cmd([adb_path, "-s", serial, "shell", "getprop", "ro.build.version.sdk"], timeout=timeout)
    if res["rc"] != 0:
        return None
    value = (res["stdout"] or "").strip()
    return int(value) if value.isdigit() else None


def start_pid(adb_path, package, serial=None, timeout=20):
    """pidof a package on the device, or None. Used for pid-stability checks."""
    argv = [adb_path]
    if serial:
        argv += ["-s", serial]
    argv += ["shell", "pidof", package]
    res = run_cmd(argv, timeout=timeout)
    value = (res["stdout"] or "").strip().split()
    return int(value[0]) if value and value[0].isdigit() else None


# --------------------------------------------------------------------------
# Result schema
# --------------------------------------------------------------------------


def metric_defaults(overrides=None):
    metrics = {key: None for key in METRIC_KEYS}
    for key, value in (overrides or {}).items():
        if key not in METRIC_KEYS:
            raise HilError("unknown metric %r (allowed: %s)" % (key, ", ".join(METRIC_KEYS)))
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            raise HilError("metric %r must be a number or None" % key)
        metrics[key] = value
    return metrics


def blocker(reason, detail=None, case=None):
    item = {"reason": reason}
    if detail:
        item["detail"] = detail
    if case:
        item["case"] = case
    return item


def make_result(
    kind,
    status,
    *,
    reason=None,
    parameters=None,
    metrics=None,
    cases=None,
    blockers=None,
    artifacts=None,
    environment_block=None,
    build=None,
):
    if kind not in KINDS:
        raise HilError("unknown result kind %r" % (kind,))
    if status not in STATUSES:
        raise HilError("unknown status %r" % (status,))
    return {
        "schemaVersion": SCHEMA_VERSION,
        "kind": kind,
        "status": status,
        "reason": reason,
        "generatedAt": iso_now(),
        "build": build if build is not None else git_short_sha(),
        "environment": environment_block if environment_block is not None else collect_environment(),
        "parameters": dict(parameters or {}),
        "metrics": metric_defaults(metrics),
        "cases": list(cases or []),
        "blockers": list(blockers or []),
        "artifacts": list(artifacts or []),
    }


def blocked_result(
    kind,
    reason,
    *,
    detail=None,
    parameters=None,
    environment_block=None,
    cases=None,
    extra_blockers=None,
    metrics=None,
    artifacts=None,
    build=None,
):
    blockers = [blocker(reason, detail)]
    blockers.extend(extra_blockers or [])
    return make_result(
        kind,
        "blocked",
        reason=reason,
        parameters=parameters,
        metrics=metrics,
        cases=cases,
        blockers=blockers,
        artifacts=artifacts,
        environment_block=environment_block,
        build=build,
    )


def validate_result(doc):
    """Return a list of schema problems; empty list means valid."""
    problems = []
    if not isinstance(doc, dict):
        return ["result must be a JSON object"]
    required = (
        "schemaVersion",
        "kind",
        "status",
        "reason",
        "generatedAt",
        "build",
        "environment",
        "parameters",
        "metrics",
        "cases",
        "blockers",
        "artifacts",
    )
    for key in required:
        if key not in doc:
            problems.append("missing key %r" % key)
    if doc.get("schemaVersion") != SCHEMA_VERSION:
        problems.append("schemaVersion must be %d" % SCHEMA_VERSION)
    if doc.get("kind") not in KINDS:
        problems.append("kind must be one of %s" % ", ".join(KINDS))
    status = doc.get("status")
    if status not in STATUSES:
        problems.append("status must be one of %s" % ", ".join(STATUSES))
    if not isinstance(doc.get("build"), str) or not doc.get("build"):
        problems.append("build must be a non-empty string")
    generated = doc.get("generatedAt")
    if not isinstance(generated, str):
        problems.append("generatedAt must be an ISO-8601 string")
    else:
        try:
            parse_iso(generated)
        except ValueError:
            problems.append("generatedAt is not ISO-8601: %r" % generated)
    env = doc.get("environment")
    if not isinstance(env, dict):
        problems.append("environment must be an object")
    else:
        if not isinstance(env.get("os"), str):
            problems.append("environment.os must be a string")
        if "adb" not in env:
            problems.append("environment.adb must be present (null when adb is absent)")
        if not isinstance(env.get("devices"), list):
            problems.append("environment.devices must be a list")
    if not isinstance(doc.get("parameters"), dict):
        problems.append("parameters must be an object")
    metrics = doc.get("metrics")
    if not isinstance(metrics, dict):
        problems.append("metrics must be an object")
    else:
        for key in METRIC_KEYS:
            if key not in metrics:
                problems.append("metrics.%s missing" % key)
                continue
            value = metrics[key]
            if value is not None and (isinstance(value, bool) or not isinstance(value, (int, float))):
                problems.append("metrics.%s must be a number or null" % key)
    cases = doc.get("cases")
    if not isinstance(cases, list):
        problems.append("cases must be a list")
    else:
        for idx, case in enumerate(cases):
            if not isinstance(case, dict):
                problems.append("cases[%d] must be an object" % idx)
                continue
            if not case.get("id"):
                problems.append("cases[%d].id missing" % idx)
            if case.get("status") not in STATUSES:
                problems.append("cases[%d].status is invalid" % idx)
            if case.get("status") == "blocked" and not case.get("reason"):
                problems.append("cases[%d] is blocked without a reason" % idx)
    blockers = doc.get("blockers")
    if not isinstance(blockers, list):
        problems.append("blockers must be a list")
    else:
        for idx, item in enumerate(blockers):
            if not isinstance(item, dict) or not item.get("reason"):
                problems.append("blockers[%d] must have a reason" % idx)
    if not isinstance(doc.get("artifacts"), list):
        problems.append("artifacts must be a list")
    reason = doc.get("reason")
    if reason is not None and not isinstance(reason, str):
        problems.append("reason must be a string or null")
    if status == "blocked":
        if not reason:
            problems.append("blocked results must set reason")
        if not blockers:
            problems.append("blocked results must list at least one blocker")
    if status == "pass":
        if reason:
            problems.append("passing results must not set reason")
        if blockers:
            problems.append("passing results must not carry blockers")
        if isinstance(cases, list) and any(
            isinstance(case, dict) and case.get("status") != "pass" for case in cases
        ):
            problems.append("passing results must not contain non-pass cases")
    return problems


def write_result(doc, path):
    ensure_parent(path)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(doc, fh, indent=2, ensure_ascii=True)
        fh.write("\n")
    return os.path.abspath(path)


def write_jsonl(rows, path):
    """Write one JSON object per line (sample/cycle sidecar logs)."""
    ensure_parent(path)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        for row in rows:
            fh.write(json.dumps(row, ensure_ascii=True) + "\n")
    return os.path.abspath(path)


def exit_code_for(status, gate=False):
    if status == "pass":
        return EXIT_OK
    if status == "blocked":
        return EXIT_BLOCKED_GATE if gate else EXIT_OK
    if status == "fail":
        return EXIT_FAIL
    return EXIT_ERROR


def finish(doc, out_path, gate=False):
    """Validate, write and announce a result; return the process exit code."""
    problems = validate_result(doc)
    if problems:
        print("warning: result does not satisfy the HIL schema: %s" % "; ".join(problems), file=sys.stderr)
    write_result(doc, out_path)
    announce(doc, out_path)
    return exit_code_for(doc.get("status"), gate)


def announce(doc, out_path):
    kind = doc.get("kind")
    status = doc.get("status")
    reason = doc.get("reason")
    label = status if not reason else "%s (%s)" % (status, reason)
    print("%s: %s -> %s" % (kind, label, out_path))


def add_output_args(parser, kind, with_dry_run=True):
    parser.add_argument("--out", default=default_out(kind), help="result JSON path (default: %(default)s)")
    parser.add_argument("--gate", action="store_true", help="exit 2 when blocked (CI hardware gate)")
    if with_dry_run:
        parser.add_argument(
            "--dry-run",
            action="store_true",
            help="probe read-only state only; never send play/relay commands",
        )
    return parser


def add_device_args(parser):
    parser.add_argument(
        "--adb",
        default="auto",
        help="path to adb (default: resolve from PATH); a bogus path is treated as adb-missing",
    )
    parser.add_argument("--serial", default=None, help="target device serial (default: first attached device)")
    return parser


def add_driver_args(parser):
    parser.add_argument(
        "--driver-cmd",
        default=None,
        help="playback driver command template; {action}, {serial}, {case} placeholders; "
        "must print one JSON object as its last stdout line",
    )
    return parser


def run_main(main_fn, argv=None):
    """Run a script entrypoint, converting expected failures into clean exit codes."""
    debug = os.environ.get("HIL_DEBUG", "") not in ("", "0", "false", "False")
    try:
        return int(main_fn(argv))
    except HilError as exc:
        print("error: %s" % exc, file=sys.stderr)
        if debug:
            raise
        return EXIT_ERROR
    except BrokenPipeError:
        return EXIT_OK
    except KeyboardInterrupt:
        print("interrupted", file=sys.stderr)
        return 130
    except Exception as exc:  # noqa: BLE001 - no tracebacks for operators
        print("unexpected error: %s: %s" % (type(exc).__name__, exc), file=sys.stderr)
        if debug:
            raise
        return EXIT_ERROR


# --------------------------------------------------------------------------
# Playback / relay driver contract
# --------------------------------------------------------------------------


class Driver:
    """Runs a user-supplied rig command and parses its JSON reply.

    Contract (documented in README.md): the command prints exactly one JSON
    object as its final stdout line.  The harness records that payload as the
    rig's claim; it never substitutes its own numbers.
    """

    def __init__(self, template, timeout=120):
        self.template = template
        self.timeout = timeout
        self.tokens = split_command(template)
        if not self.tokens:
            raise HilError("driver command template is empty")

    def invoke(self, **fields):
        argv = []
        for token in self.tokens:
            try:
                argv.append(token.format(**fields))
            except KeyError as exc:
                raise HilError("driver template references unknown placeholder %s" % exc)
        res = run_cmd(argv, timeout=self.timeout)
        if res["rc"] is None:
            raise HilError("driver could not run: %s" % res["error"])
        stdout = res["stdout"] or ""
        if res["rc"] != 0:
            detail = (res["stderr"] or stdout).strip().splitlines()
            raise HilError("driver exited %s: %s" % (res["rc"], detail[-1][:300] if detail else "no output"))
        payload = None
        for line in reversed(stdout.strip().splitlines()):
            line = line.strip()
            if not line.startswith("{"):
                continue
            try:
                payload = json.loads(line)
            except ValueError:
                continue
            break
        if not isinstance(payload, dict):
            raise HilError("driver output did not end with a JSON object")
        return payload


def numeric(payload, key):
    """Return payload[key] as int/float, or None. Never coerces strings."""
    value = (payload or {}).get(key)
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    return value


def first_diff(path_a, path_b, offset_a=0, offset_b=0, limit=None):
    """Offset of the first differing byte relative to the compared region.

    Returns None when the two regions are identical.
    """
    position = 0
    with open(path_a, "rb") as fa, open(path_b, "rb") as fb:
        fa.seek(offset_a)
        fb.seek(offset_b)
        while True:
            chunk_a = fa.read(65536)
            chunk_b = fb.read(65536)
            if not chunk_a and not chunk_b:
                return None
            if not chunk_a or not chunk_b:
                return position + min(len(chunk_a), len(chunk_b))
            if chunk_a != chunk_b:
                for idx, (byte_a, byte_b) in enumerate(zip(chunk_a, chunk_b)):
                    if byte_a != byte_b:
                        return position + idx
                return position + min(len(chunk_a), len(chunk_b))
            position += len(chunk_a)
            if limit is not None and position >= limit:
                return None


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


# --------------------------------------------------------------------------
# WAV parsing (bit-exact capture)
# --------------------------------------------------------------------------


def scan_wav(path):
    """Parse a RIFF/WAVE header and return format + payload location."""
    try:
        size = os.path.getsize(path)
    except OSError as exc:
        raise HilError("cannot read %s: %s" % (path, exc))
    with open(path, "rb") as fh:
        header = fh.read(12)
        if len(header) < 12 or header[0:4] not in (b"RIFF", b"RIFX") or header[8:12] != b"WAVE":
            raise HilError("%s is not a RIFF/WAVE file" % os.path.basename(path))
        info = {
            "container": "wav",
            "audioFormat": None,
            "bits": None,
            "channels": None,
            "rate": None,
            "blockAlign": None,
            "dataOffset": None,
            "dataSize": None,
            "truncated": False,
        }
        pos = 12
        while pos + 8 <= size:
            fh.seek(pos)
            chunk_id = fh.read(4)
            size_raw = fh.read(4)
            if len(size_raw) < 4:
                break
            chunk_size = struct.unpack("<I", size_raw)[0]
            body = pos + 8
            if chunk_id == b"fmt " and chunk_size >= 16:
                fmt = fh.read(min(chunk_size, 40))
                if len(fmt) >= 16:
                    audio_format, channels, rate, _byte_rate, block_align, bits = struct.unpack(
                        "<HHIIHH", fmt[:16]
                    )
                    info.update(
                        {
                            "audioFormat": audio_format,
                            "channels": channels,
                            "rate": rate,
                            "blockAlign": block_align,
                            "bits": bits,
                        }
                    )
            elif chunk_id == b"data":
                available = max(0, size - body)
                declared = chunk_size
                if declared == 0xFFFFFFFF or declared > available:
                    info["truncated"] = True
                    declared = available
                info["dataOffset"] = body
                info["dataSize"] = declared
                break
            pos = body + chunk_size + (chunk_size & 1)
    if info["dataOffset"] is None:
        raise HilError("%s has no data chunk" % os.path.basename(path))
    return info


def read_payload(path, offset=0, size=None):
    with open(path, "rb") as fh:
        fh.seek(offset)
        return fh.read() if size is None else fh.read(size)
