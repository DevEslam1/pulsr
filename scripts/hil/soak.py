#!/usr/bin/env python3
"""soak.py - long-duration gapless USB DAC soak gate.

Runs a gapless playlist loop for --hours (default 8), samples underrun/overrun
counters every --sample-interval seconds (default 10), detects counter
regressions (a counter that goes backwards means the evidence is invalid), and
compares expected vs actual elapsed duration to report clock drift in ppm.

Raw samples go to a sidecar JSONL next to --out; the result JSON holds the
aggregate.  No device -> blocked/no_device.  No measured counters -> null, never 0.
"""

from __future__ import annotations

import argparse
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import hil_common as hc

DEFAULT_HOURS = 8.0
DEFAULT_INTERVAL_S = 10.0
DEFAULT_MAX_DRIFT_PPM = 100.0


def make_case(case_id, status, reason=None, detail=None, metrics=None, target=None):
    case = {"id": case_id, "status": status, "reason": reason, "metrics": metrics or {}}
    if detail:
        case["detail"] = detail
    if target is not None:
        case["target"] = target
    return case


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


def blocked_cases(reason, detail=None):
    return [
        make_case("samples_collected", "blocked", reason, detail),
        make_case("counter_monotonicity", "blocked", reason, detail),
        make_case("duration_drift", "blocked", reason, detail,
                  target={"maxDriftPpm": DEFAULT_MAX_DRIFT_PPM}),
        make_case("underrun_budget", "blocked", reason, detail),
        make_case("overrun_budget", "blocked", reason, detail),
    ]


def mean_of(samples, key):
    values = [s[key] for s in samples if s.get(key) is not None]
    return round(sum(values) / len(values), 3) if values else None


def max_of(samples, key):
    values = [s[key] for s in samples if s.get(key) is not None]
    return max(values) if values else None


def find_regressions(samples):
    """Fields that must never decrease across samples."""
    watched = ("frames", "underrunCount", "overrunCount")
    regressions = []
    for idx in range(1, len(samples)):
        prev, current = samples[idx - 1], samples[idx]
        for field in watched:
            before, after = prev.get(field), current.get(field)
            if before is None or after is None:
                continue
            if after < before:
                regressions.append(
                    {"sample": idx, "field": field, "previous": before, "current": after}
                )
    return regressions


def sample_once(driver, serial, started):
    payload = driver.invoke(action="stats", serial=serial, case="soak")
    return {
        "tMs": round((time.monotonic() - started) * 1000.0, 1),
        "frames": hc.numeric(payload, "frames"),
        "sampleRate": hc.numeric(payload, "sampleRate"),
        "underrunCount": hc.numeric(payload, "underrunCount"),
        "overrunCount": hc.numeric(payload, "overrunCount"),
        "bufferMs": hc.numeric(payload, "bufferMs"),
        "cpuPct": hc.numeric(payload, "cpuPct"),
        "memMb": hc.numeric(payload, "memMb"),
        "driverDriftPpm": hc.numeric(payload, "driftPpm"),
    }


def main(argv=None):
    parser = argparse.ArgumentParser(
        prog="soak.py", description="Gapless playback soak gate with underrun/overrun sampling."
    )
    hc.add_output_args(parser, "soak")
    hc.add_device_args(parser)
    hc.add_driver_args(parser)
    parser.add_argument("--hours", type=float, default=DEFAULT_HOURS,
                        help="soak duration in hours (default: %(default)s)")
    parser.add_argument("--sample-interval", type=float, default=DEFAULT_INTERVAL_S,
                        help="seconds between counter samples (default: %(default)s)")
    parser.add_argument("--max-samples", type=int, default=None,
                        help="stop after N samples (bounded local verification; marks truncated)")
    parser.add_argument("--max-drift-ppm", type=float, default=DEFAULT_MAX_DRIFT_PPM,
                        help="absolute duration drift budget in ppm (default: %(default)s)")
    parser.add_argument("--max-underruns", type=int, default=0,
                        help="allowed underrun growth over the run (default: %(default)s)")
    parser.add_argument("--max-overruns", type=int, default=0,
                        help="allowed overrun growth over the run (default: %(default)s)")
    parser.add_argument("--timeout", type=int, default=120, help="per-driver-call timeout (seconds)")
    args = parser.parse_args(argv)

    if args.hours <= 0:
        raise hc.HilError("--hours must be greater than 0")
    if args.sample_interval <= 0:
        raise hc.HilError("--sample-interval must be greater than 0")

    probe = hc.probe_adb(args.adb)
    env = hc.environment(probe)
    serials = hc.ready_serials(probe)
    parameters = {
        "hours": args.hours,
        "sampleIntervalS": args.sample_interval,
        "maxSamples": args.max_samples,
        "truncated": False,
        "playlist": "gapless-loop",
        "dryRun": bool(args.dry_run),
        "driverConfigured": bool(args.driver_cmd),
        "targets": {"maxDriftPpm": args.max_drift_ppm,
                    "maxUnderruns": args.max_underruns, "maxOverruns": args.max_overruns},
        "devicesAttached": len(serials),
    }

    if not serials:
        result = hc.blocked_result(
            "soak", "no_device",
            detail=env.get("adbError") or "adb reported zero attached devices",
            parameters=parameters, environment_block=env, cases=blocked_cases("no_device"),
        )
        return hc.finish(result, args.out, args.gate)

    serial = args.serial or serials[0]
    if serial not in serials:
        result = hc.blocked_result(
            "soak", "no_device", detail="requested --serial is not attached",
            parameters=parameters, environment_block=env, cases=blocked_cases("no_device"),
        )
        return hc.finish(result, args.out, args.gate)

    env = hc.annotate_device(env, probe["path"], serial)

    if args.dry_run:
        result = hc.blocked_result(
            "soak", "dry_run", detail="dry run: soak not started",
            parameters=parameters, environment_block=env, cases=blocked_cases("dry_run"),
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
        result = hc.blocked_result(
            "soak", "no_usb_audio_endpoint", detail=detail,
            parameters=parameters, environment_block=env,
            cases=blocked_cases("no_usb_audio_endpoint", detail),
        )
        return hc.finish(result, args.out, args.gate)

    if not args.driver_cmd:
        detail = "device attached but --driver-cmd was not supplied; counters cannot be sampled"
        result = hc.blocked_result(
            "soak", "no_driver", detail=detail,
            parameters=parameters, environment_block=env, cases=blocked_cases("no_driver", detail),
        )
        return hc.finish(result, args.out, args.gate)

    samples_out = os.path.splitext(os.path.abspath(args.out))[0] + ".samples.jsonl"
    artifacts = []
    driver = hc.Driver(args.driver_cmd, timeout=args.timeout)
    started = time.monotonic()
    duration_s = args.hours * 3600.0
    deadline = started + duration_s
    interval = args.sample_interval
    samples = []
    truncated = False
    sample_error = None

    try:
        driver.invoke(action="start", serial=serial, case="soak", hours=args.hours,
                      playlist="gapless-loop")
        next_at = started
        while True:
            if args.max_samples is not None and len(samples) >= args.max_samples:
                truncated = True
                break
            now = time.monotonic()
            if now > deadline:
                break
            wait = next_at - now
            if wait > 0:
                time.sleep(wait)
            samples.append(sample_once(driver, serial, started))
            if len(samples) % 10 == 0 or len(samples) == 1:
                last = samples[-1]
                print(
                    "sample %d at %.0f s: frames=%s underruns=%s overruns=%s"
                    % (len(samples), last["tMs"] / 1000.0, last["frames"],
                       last["underrunCount"], last["overrunCount"]),
                    flush=True,
                )
            next_at += interval
    except hc.HilError as exc:
        sample_error = str(exc)[:300]
    finally:
        try:
            driver.invoke(action="stop", serial=serial, case="soak")
        except hc.HilError as exc:
            parameters["stopError"] = str(exc)[:300]

    parameters["truncated"] = truncated
    parameters["samplesCollected"] = len(samples)
    if samples:
        artifacts.append(hc.write_jsonl(samples, samples_out))

    if sample_error and not samples:
        result = hc.make_result(
            "soak", "error", reason="driver_error", parameters=parameters,
            environment_block=env, artifacts=artifacts,
            blockers=[hc.blocker("driver_error", sample_error)],
        )
        return hc.finish(result, args.out, args.gate)

    last = samples[-1] if samples else {}
    first = samples[0] if samples else {}
    total_frames = last.get("frames")
    sample_rate = last.get("sampleRate")
    actual_ms = last.get("tMs")
    expected_ms = None
    drift_ppm = None
    if total_frames is not None and sample_rate:
        expected_ms = round(total_frames / float(sample_rate) * 1000.0, 3)
        if expected_ms > 0 and actual_ms is not None:
            drift_ppm = round((actual_ms - expected_ms) / expected_ms * 1000000.0, 3)

    regressions = find_regressions(samples)
    underrun_growth = None
    if last.get("underrunCount") is not None and first.get("underrunCount") is not None:
        underrun_growth = last["underrunCount"] - first["underrunCount"]
    overrun_growth = None
    if last.get("overrunCount") is not None and first.get("overrunCount") is not None:
        overrun_growth = last["overrunCount"] - first["overrunCount"]

    cases = []
    if len(samples) < 2:
        cases.append(make_case("samples_collected", "blocked", "insufficient_samples",
                               sample_error or "at least two samples are required"))
    else:
        cases.append(make_case("samples_collected", "pass",
                               metrics={"samples": len(samples), "truncated": truncated}))

    if len(samples) < 2:
        cases.append(make_case("counter_monotonicity", "blocked", "insufficient_samples",
                               "need at least two samples"))
    elif regressions:
        cases.append(make_case("counter_monotonicity", "fail", "counter_regression",
                               "%d counter regression(s); first: %s" % (len(regressions), regressions[0]),
                               metrics={"regressions": len(regressions)}))
    else:
        cases.append(make_case("counter_monotonicity", "pass", metrics={"regressions": 0}))

    if drift_ppm is None:
        cases.append(make_case("duration_drift", "blocked", "metric_unavailable",
                               "frames or sampleRate missing from driver stats",
                               target={"maxDriftPpm": args.max_drift_ppm}))
    elif abs(drift_ppm) <= args.max_drift_ppm:
        cases.append(make_case("duration_drift", "pass", metrics={"driftPpm": drift_ppm},
                               target={"maxDriftPpm": args.max_drift_ppm}))
    else:
        cases.append(make_case("duration_drift", "fail", "drift_budget_exceeded",
                               "|%.1f ppm| > %.1f ppm" % (drift_ppm, args.max_drift_ppm),
                               metrics={"driftPpm": drift_ppm},
                               target={"maxDriftPpm": args.max_drift_ppm}))

    for case_id, growth, budget in (
        ("underrun_budget", underrun_growth, args.max_underruns),
        ("overrun_budget", overrun_growth, args.max_overruns),
    ):
        if growth is None:
            cases.append(make_case(case_id, "blocked", "metric_unavailable",
                                   "counter not reported by driver", target={"maxGrowth": budget}))
        elif growth <= budget:
            cases.append(make_case(case_id, "pass", metrics={"growth": growth},
                                   target={"maxGrowth": budget}))
        else:
            cases.append(make_case(case_id, "fail", "%s_exceeded" % case_id.split("_")[0],
                                   "counter grew by %d (budget %d)" % (growth, budget),
                                   metrics={"growth": growth}, target={"maxGrowth": budget}))

    status = overall_status(cases)
    reason = None
    if status == "blocked":
        reason = next((case["reason"] for case in cases if case.get("status") == "blocked"), "incomplete")
    elif status == "fail":
        reason = "soak_gate"
    blockers = []
    if status == "blocked":
        for case in cases:
            if case.get("status") == "blocked":
                blockers.append(hc.blocker(case["reason"], case.get("detail"), case["id"]))

    summary = {
        "totalFrames": total_frames,
        "sampleRate": sample_rate,
        "expectedDurationMs": expected_ms,
        "actualDurationMs": actual_ms,
        "driftPpm": drift_ppm,
        "driverDriftPpm": last.get("driverDriftPpm"),
        "sampleCount": len(samples),
        "regressions": regressions[:20],
        "regressionCount": len(regressions),
        "truncated": truncated,
    }
    result = hc.make_result(
        "soak", status, reason=reason, parameters=parameters,
        metrics={
            "startMs": None,
            "stopMs": None,
            "underrunCount": last.get("underrunCount"),
            "overrunCount": last.get("overrunCount"),
            "driftPpm": drift_ppm,
            "bufferMs": last.get("bufferMs"),
            "cpuPct": mean_of(samples, "cpuPct"),
            "memMb": max_of(samples, "memMb"),
        },
        cases=cases,
        blockers=blockers,
        environment_block=env,
        artifacts=artifacts,
    )
    # Aggregate-only extras; kept out of the fixed schema keys on purpose.
    result["summary"] = summary
    return hc.finish(result, args.out, args.gate)


if __name__ == "__main__":
    sys.exit(hc.run_main(main))
