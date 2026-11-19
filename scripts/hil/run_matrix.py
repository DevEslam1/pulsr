#!/usr/bin/env python3
"""run_matrix.py - Pulsr USB Audio Class device matrix.

Iterates a target matrix (built-in Tier A/B list by default) and, for each
entry, either runs a real playback probe through --play-cmd or reports
status="blocked".  A case can never pass without a probe result produced by an
attached device during this run.

Exit codes: 0 pass or blocked (dry-run), 2 blocked with --gate, 1 failing case,
3 unexpected error.
"""

from __future__ import annotations

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import hil_common as hc

# Built-in target list.  Tier A = common audiophile setups that must work;
# Tier B = exotic rates/features that need dedicated hardware.
BUILTIN_MATRIX = (
    # --- Tier A ---
    {"id": "uac2-async-44100", "tier": "A", "class": "UAC2", "rate": 44100, "bits": 24,
     "channels": 2, "label": "UAC2 HS async 44.1 kHz", "features": ["async", "uac2"]},
    {"id": "uac2-async-48000", "tier": "A", "class": "UAC2", "rate": 48000, "bits": 24,
     "channels": 2, "label": "UAC2 HS async 48 kHz", "features": ["async", "uac2"]},
    {"id": "uac2-async-96000", "tier": "A", "class": "UAC2", "rate": 96000, "bits": 24,
     "channels": 2, "label": "UAC2 HS async 96 kHz", "features": ["async", "uac2"]},
    {"id": "uac2-async-192000", "tier": "A", "class": "UAC2", "rate": 192000, "bits": 24,
     "channels": 2, "label": "UAC2 HS async 192 kHz", "features": ["async", "uac2"]},
    {"id": "uac2-async-384000", "tier": "A", "class": "UAC2", "rate": 384000, "bits": 24,
     "channels": 2, "label": "UAC2 HS async 384 kHz", "features": ["async", "uac2"]},
    {"id": "uac1-fs-44100", "tier": "A", "class": "UAC1", "rate": 44100, "bits": 16,
     "channels": 2, "label": "UAC1 full-speed 44.1 kHz", "features": ["uac1"]},
    {"id": "uac1-fs-48000", "tier": "A", "class": "UAC1", "rate": 48000, "bits": 16,
     "channels": 2, "label": "UAC1 full-speed 48 kHz", "features": ["uac1"]},
    {"id": "uac1-hs-96000", "tier": "A", "class": "UAC1", "rate": 96000, "bits": 24,
     "channels": 2, "label": "UAC1 high-speed 96 kHz", "features": ["uac1"]},
    {"id": "uac1-hs-192000", "tier": "A", "class": "UAC1", "rate": 192000, "bits": 24,
     "channels": 2, "label": "UAC1 high-speed 192 kHz", "features": ["uac1"]},
    {"id": "uac2-24in32", "tier": "A", "class": "UAC2", "rate": 96000, "bits": 32,
     "channels": 2, "label": "24-bit source in 32-bit transport", "features": ["uac2", "24in32"]},
    {"id": "uac2-hardware-volume", "tier": "A", "class": "UAC2", "rate": 48000, "bits": 24,
     "channels": 2, "label": "Hardware-volume DAC", "features": ["uac2", "hwvol"]},
    {"id": "uac1-feedbackless-dongle", "tier": "A", "class": "UAC1", "rate": 48000, "bits": 16,
     "channels": 2, "label": "Feedback-less dongle (no async feedback EP)",
     "features": ["uac1", "feedbackless"]},
    # --- Tier B ---
    {"id": "uac2-705600", "tier": "B", "class": "UAC2", "rate": 705600, "bits": 24,
     "channels": 2, "label": "UAC2 HS 705.6 kHz", "features": ["async", "uac2", "hires"]},
    {"id": "uac2-768000", "tier": "B", "class": "UAC2", "rate": 768000, "bits": 24,
     "channels": 2, "label": "UAC2 HS 768 kHz", "features": ["async", "uac2", "hires"]},
    {"id": "uac2-dop-dsd128", "tier": "B", "class": "UAC2", "rate": 352800, "bits": 24,
     "channels": 2, "label": "DoP DAC (DSD128 over PCM)", "features": ["uac2", "dop"]},
    {"id": "uac2-6ch", "tier": "B", "class": "UAC2", "rate": 96000, "bits": 24,
     "channels": 6, "label": "6-channel multichannel", "features": ["uac2", "multichannel"]},
    {"id": "uac2-8ch", "tier": "B", "class": "UAC2", "rate": 96000, "bits": 24,
     "channels": 8, "label": "8-channel multichannel", "features": ["uac2", "multichannel"]},
    {"id": "uac2-32bit-384000", "tier": "B", "class": "UAC2", "rate": 384000, "bits": 32,
     "channels": 2, "label": "32-bit PCM 384 kHz", "features": ["async", "uac2", "32bit"]},
)


def _coerce_entry(raw, index):
    if not isinstance(raw, dict):
        raise hc.HilError("matrix entry %d is not an object" % index)
    entry = dict(raw)
    entry.setdefault("tier", "B")
    entry["tier"] = str(entry["tier"]).upper()
    if entry["tier"] not in ("A", "B"):
        raise hc.HilError("matrix entry %r has invalid tier %r" % (entry.get("id"), entry.get("tier")))
    if not entry.get("id"):
        raise hc.HilError("matrix entry %d has no id" % index)
    for key in ("rate", "bits", "channels"):
        if key in entry:
            try:
                entry[key] = int(entry[key])
            except (TypeError, ValueError):
                raise hc.HilError("matrix entry %r has non-integer %s" % (entry["id"], key))
        else:
            entry[key] = None
    features = entry.get("features") or []
    if isinstance(features, str):
        features = [part.strip() for part in features.split(",") if part.strip()]
    entry["features"] = list(features)
    if not entry.get("class"):
        entry["class"] = "UAC2"
    entry.setdefault("label", entry["id"])
    return entry


def parse_yaml_ish(text):
    """Minimal YAML-ish list parser: `- key: value` entries, comments allowed."""
    entries = []
    current = None
    for lineno, raw in enumerate(text.splitlines(), 1):
        line = raw.split("#", 1)[0].rstrip()
        if not line.strip():
            continue
        stripped = line.strip()
        if stripped in ("cases:", "matrix:"):
            continue
        if stripped.startswith("- "):
            if current is not None:
                entries.append(current)
            current = {}
            stripped = stripped[2:].strip()
            if not stripped:
                continue
        if current is None:
            raise hc.HilError("matrix file line %d: expected a '- key: value' entry" % lineno)
        if ":" not in stripped:
            raise hc.HilError("matrix file line %d: expected 'key: value'" % lineno)
        key, _, value = stripped.partition(":")
        key = key.strip()
        value = value.strip()
        if not key:
            raise hc.HilError("matrix file line %d: empty key" % lineno)
        if value.startswith("[") and value.endswith("]"):
            current[key] = [part.strip().strip("\"'") for part in value[1:-1].split(",") if part.strip()]
        elif value.lower() in ("true", "false"):
            current[key] = value.lower() == "true"
        else:
            try:
                current[key] = int(value)
            except ValueError:
                try:
                    current[key] = float(value)
                except ValueError:
                    current[key] = value.strip("\"'")
    if current is not None:
        entries.append(current)
    return entries


def load_matrix(path):
    if not path:
        return [_coerce_entry(entry, i) for i, entry in enumerate(BUILTIN_MATRIX)]
    if not os.path.isfile(path):
        raise hc.HilError("matrix file not found: %s" % path)
    with open(path, "r", encoding="utf-8-sig") as fh:
        text = fh.read()
    if not text.strip():
        raise hc.HilError("matrix file is empty: %s" % path)
    if path.lower().endswith(".json"):
        try:
            data = json.loads(text)
        except ValueError as exc:
            raise hc.HilError("matrix file is not valid JSON: %s" % exc)
        if isinstance(data, dict):
            data = data.get("cases") or data.get("matrix")
        if not isinstance(data, list) or not data:
            raise hc.HilError("matrix JSON must be a non-empty list or {cases: [...]}")
    else:
        data = parse_yaml_ish(text)
    if not data:
        raise hc.HilError("matrix file defines no cases: %s" % path)
    entries = [_coerce_entry(raw, i) for i, raw in enumerate(data)]
    seen = set()
    for entry in entries:
        if entry["id"] in seen:
            raise hc.HilError("duplicate matrix case id: %s" % entry["id"])
        seen.add(entry["id"])
    return entries


def filter_tier(entries, tier):
    if tier == "all":
        return list(entries)
    return [entry for entry in entries if entry["tier"] == tier]


def case_blocked(entry, reason, detail=None):
    case = {
        "id": entry["id"],
        "tier": entry["tier"],
        "label": entry.get("label"),
        "status": "blocked",
        "reason": reason,
        "target": {
            "class": entry.get("class"),
            "rate": entry.get("rate"),
            "bits": entry.get("bits"),
            "channels": entry.get("channels"),
            "features": entry.get("features"),
        },
        "evidence": None,
    }
    if detail:
        case["detail"] = detail
    return case


def summarize_blockers(cases):
    grouped = {}
    for case in cases:
        if case.get("status") == "blocked":
            grouped.setdefault(case.get("reason") or "blocked", []).append(case["id"])
    blockers = []
    for reason, ids in sorted(grouped.items()):
        blockers.append(
            hc.blocker(
                reason,
                "%d of %d matrix cases blocked (e.g. %s)" % (len(ids), len(cases), ", ".join(ids[:4])),
            )
        )
    return blockers


def overall_status(cases):
    statuses = [case.get("status") for case in cases]
    if not statuses:
        return "blocked"
    if "fail" in statuses:
        return "fail"
    if "error" in statuses:
        return "error"
    if all(status == "pass" for status in statuses):
        return "pass"
    return "blocked"


def run_case(entry, driver, serial):
    payload = driver.invoke(
        action="matrix",
        serial=serial,
        case=entry["id"],
        rate=entry.get("rate") or "",
        bits=entry.get("bits") or "",
        channels=entry.get("channels") or "",
    )
    claimed = payload.get("status")
    if claimed not in hc.STATUSES:
        raise hc.HilError("driver reported invalid status %r" % (claimed,))
    case = {
        "id": entry["id"],
        "tier": entry["tier"],
        "label": entry.get("label"),
        "status": claimed,
        "reason": payload.get("reason"),
        "target": {
            "class": entry.get("class"),
            "rate": entry.get("rate"),
            "bits": entry.get("bits"),
            "channels": entry.get("channels"),
            "features": entry.get("features"),
        },
        "evidence": hc.redact_obj(payload.get("evidence", payload), [serial]),
    }
    if claimed == "blocked" and not case["reason"]:
        raise hc.HilError("driver reported blocked without a reason")
    return case


def main(argv=None):
    parser = argparse.ArgumentParser(
        prog="run_matrix.py",
        description="Run the Pulsr USB DAC matrix; blocked is reported honestly, never as a pass.",
    )
    hc.add_output_args(parser, "matrix")
    hc.add_device_args(parser)
    parser.add_argument(
        "--play-cmd",
        "--driver-cmd",
        dest="play_cmd",
        default=None,
        help="playback probe command template ({action}, {serial}, {case} placeholders); "
        "must print one JSON object as its last stdout line",
    )
    parser.add_argument("--tier", choices=("A", "B", "all"), default="all", help="matrix tier to run")
    parser.add_argument("--matrix", default=None, help="optional JSON or YAML-ish matrix file")
    parser.add_argument("--timeout", type=int, default=300, help="per-case driver timeout in seconds")
    parser.add_argument("--list", action="store_true", help="print the resolved matrix and exit")
    args = parser.parse_args(argv)

    entries = filter_tier(load_matrix(args.matrix), args.tier)
    if not entries:
        raise hc.HilError("matrix tier %r selects no cases" % args.tier)
    if args.list:
        for entry in entries:
            print("%s\t%s\t%s\t%s Hz\t%s bit\t%s ch\t%s" % (
                entry["tier"], entry["id"], entry.get("class"), entry.get("rate"),
                entry.get("bits"), entry.get("channels"), entry.get("label")))
        return hc.EXIT_OK

    probe = hc.probe_adb(args.adb)
    env = hc.environment(probe)
    serials = hc.ready_serials(probe)
    parameters = {
        "tier": args.tier,
        "matrixSource": args.matrix or "builtin",
        "caseCount": len(entries),
        "dryRun": bool(args.dry_run),
        "driverConfigured": bool(args.play_cmd),
        "perCaseTimeoutS": args.timeout,
        "devicesAttached": len(serials),
    }

    if not serials:
        detail = env.get("adbError") or "adb reported zero attached devices"
        cases = [case_blocked(entry, "no_device") for entry in entries]
        result = hc.blocked_result(
            "matrix", "no_device", detail=detail, parameters=parameters,
            environment_block=env, cases=cases,
        )
        return hc.finish(result, args.out, args.gate)

    serial = args.serial or serials[0]
    if serial not in serials:
        cases = [case_blocked(entry, "no_device", "requested serial %s is not attached" % hc.redact_token(serial))
                 for entry in entries]
        result = hc.blocked_result(
            "matrix", "no_device", detail="requested --serial is not attached",
            parameters=parameters, environment_block=env, cases=cases,
        )
        return hc.finish(result, args.out, args.gate)

    env = hc.annotate_device(env, probe["path"], serial)

    if args.dry_run:
        cases = [case_blocked(entry, "dry_run") for entry in entries]
        result = hc.blocked_result(
            "matrix", "dry_run", detail="dry run: no playback probe executed",
            parameters=parameters, environment_block=env, cases=cases,
        )
        return hc.finish(result, args.out, args.gate)

    usb = hc.usb_audio_report(probe["path"], serial)
    parameters["usbAudio"] = {
        "source": usb.get("source"),
        "detected": usb.get("detected"),
        "matches": len(usb.get("matches") or []),
        "error": usb.get("error"),
    }
    if not usb.get("detected"):
        detail = usb.get("error") or "dumpsys usb / lsusb showed no audio-class endpoint"
        cases = [case_blocked(entry, "no_usb_audio_endpoint", detail) for entry in entries]
        result = hc.blocked_result(
            "matrix", "no_usb_audio_endpoint", detail=detail,
            parameters=parameters, environment_block=env, cases=cases,
        )
        return hc.finish(result, args.out, args.gate)

    if not args.play_cmd:
        detail = "device attached but --play-cmd was not supplied; no probe to attribute a verdict to"
        cases = [case_blocked(entry, "no_playback_driver", detail) for entry in entries]
        result = hc.blocked_result(
            "matrix", "no_playback_driver", detail=detail,
            parameters=parameters, environment_block=env, cases=cases,
        )
        return hc.finish(result, args.out, args.gate)

    driver = hc.Driver(args.play_cmd, timeout=args.timeout)
    cases = []
    for entry in entries:
        try:
            cases.append(run_case(entry, driver, serial))
        except hc.HilError as exc:
            cases.append(
                {
                    "id": entry["id"],
                    "tier": entry["tier"],
                    "label": entry.get("label"),
                    "status": "error",
                    "reason": "driver_error",
                    "detail": str(exc)[:300],
                    "target": {"class": entry.get("class"), "rate": entry.get("rate"),
                               "bits": entry.get("bits"), "channels": entry.get("channels")},
                    "evidence": None,
                }
            )

    status = overall_status(cases)
    reason = None
    if status == "blocked":
        reason = "incomplete_matrix"
    elif status == "fail":
        reason = "case_failed"
    elif status == "error":
        reason = "case_error"
    result = hc.make_result(
        "matrix", status,
        reason=reason,
        parameters=parameters,
        cases=cases,
        blockers=summarize_blockers(cases) if status == "blocked" else [],
        environment_block=env,
        artifacts=[],
    )
    return hc.finish(result, args.out, args.gate)


if __name__ == "__main__":
    sys.exit(hc.run_main(main))
