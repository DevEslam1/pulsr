#!/usr/bin/env python3
"""smoke.py - USB DAC playback smoke gate.

Measured on real hardware through a rig driver (--driver-cmd):
  * start latency   < 500 ms
  * stop latency    < 300 ms
  * no underrun growth over the observation window (default 60 s)

Without a device, a driver, or any measured metric the result is "blocked".
A missing measurement is never reported as zero underruns.
"""

from __future__ import annotations

import argparse
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import hil_common as hc

START_MS_MAX = 500.0
STOP_MS_MAX = 300.0
UNDERRUN_GROWTH_MAX = 0
DEFAULT_DURATION_S = 60.0


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
        make_case("start_latency", "blocked", reason, detail, target={"startMsMax": START_MS_MAX}),
        make_case("stop_latency", "blocked", reason, detail, target={"stopMsMax": STOP_MS_MAX}),
        make_case(
            "underrun_stability",
            "blocked",
            reason,
            detail,
            target={"growthMax": UNDERRUN_GROWTH_MAX},
        ),
    ]


def collect_samples(driver, serial, duration_s, interval_s):
    """Poll stats until the window elapses; return (samples, elapsed_ms)."""
    samples = []
    started = time.monotonic()
    next_at = 0.0
    while next_at <= duration_s:
        wait = next_at - (time.monotonic() - started)
        if wait > 0:
            time.sleep(wait)
        payload = driver.invoke(action="stats", serial=serial, case="smoke")
        elapsed_ms = (time.monotonic() - started) * 1000.0
        samples.append(
            {
                "tMs": round(elapsed_ms, 1),
                "underrunCount": hc.numeric(payload, "underrunCount"),
                "overrunCount": hc.numeric(payload, "overrunCount"),
                "bufferMs": hc.numeric(payload, "bufferMs"),
                "cpuPct": hc.numeric(payload, "cpuPct"),
                "memMb": hc.numeric(payload, "memMb"),
                "frames": hc.numeric(payload, "frames"),
            }
        )
        print(
            "sample %d at %.0f ms: underruns=%s overruns=%s"
            % (len(samples), elapsed_ms, samples[-1]["underrunCount"], samples[-1]["overrunCount"]),
            flush=True,
        )
        next_at += max(0.5, interval_s)
    return samples, (time.monotonic() - started) * 1000.0


def main(argv=None):
    parser = argparse.ArgumentParser(
        prog="smoke.py", description="USB DAC playback start/stop latency and underrun smoke gate."
    )
    hc.add_output_args(parser, "smoke")
    hc.add_device_args(parser)
    hc.add_driver_args(parser)
    parser.add_argument("--duration", type=float, default=DEFAULT_DURATION_S,
                        help="observation window in seconds (default: %(default)s)")
    parser.add_argument("--interval", type=float, default=5.0,
                        help="stats polling interval in seconds (default: %(default)s)")
    parser.add_argument("--timeout", type=int, default=120, help="per-driver-call timeout (seconds)")
    args = parser.parse_args(argv)

    probe = hc.probe_adb(args.adb)
    env = hc.environment(probe)
    serials = hc.ready_serials(probe)
    parameters = {
        "durationS": args.duration,
        "intervalS": args.interval,
        "dryRun": bool(args.dry_run),
        "driverConfigured": bool(args.driver_cmd),
        "targets": {"startMsMax": START_MS_MAX, "stopMsMax": STOP_MS_MAX,
                    "underrunGrowthMax": UNDERRUN_GROWTH_MAX},
        "devicesAttached": len(serials),
    }

    if not serials:
        result = hc.blocked_result(
            "smoke", "no_device",
            detail=env.get("adbError") or "adb reported zero attached devices",
            parameters=parameters, environment_block=env, cases=blocked_cases("no_device"),
        )
        return hc.finish(result, args.out, args.gate)

    serial = args.serial or serials[0]
    if serial not in serials:
        result = hc.blocked_result(
            "smoke", "no_device", detail="requested --serial is not attached",
            parameters=parameters, environment_block=env, cases=blocked_cases("no_device"),
        )
        return hc.finish(result, args.out, args.gate)

    env = hc.annotate_device(env, probe["path"], serial)

    if args.dry_run:
        result = hc.blocked_result(
            "smoke", "dry_run", detail="dry run: no playback started",
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
            "smoke", "no_usb_audio_endpoint", detail=detail,
            parameters=parameters, environment_block=env,
            cases=blocked_cases("no_usb_audio_endpoint", detail),
        )
        return hc.finish(result, args.out, args.gate)

    if not args.driver_cmd:
        detail = "device attached but --driver-cmd was not supplied; latency cannot be measured"
        result = hc.blocked_result(
            "smoke", "no_driver", detail=detail,
            parameters=parameters, environment_block=env, cases=blocked_cases("no_driver", detail),
        )
        return hc.finish(result, args.out, args.gate)

    driver = hc.Driver(args.driver_cmd, timeout=args.timeout)
    parameters["durationS"] = max(1.0, args.duration)

    try:
        start_payload = driver.invoke(action="start", serial=serial, case="smoke",
                                      durationS=parameters["durationS"])
    except hc.HilError as exc:
        result = hc.make_result(
            "smoke", "error", reason="driver_error", parameters=parameters,
            environment_block=env, blockers=[hc.blocker("driver_error", str(exc)[:300])],
        )
        return hc.finish(result, args.out, args.gate)

    if start_payload.get("status") == "blocked":
        reason = start_payload.get("reason") or "driver_blocked"
        detail = "rig driver refused to start playback"
        result = hc.blocked_result(
            "smoke", reason, detail=detail, parameters=parameters,
            environment_block=env, cases=blocked_cases(reason, detail),
        )
        return hc.finish(result, args.out, args.gate)

    start_ms = hc.numeric(start_payload, "startMs")
    samples = []
    sample_error = None
    try:
        samples, _elapsed = collect_samples(
            driver, serial, parameters["durationS"], max(0.5, args.interval)
        )
    except hc.HilError as exc:
        sample_error = str(exc)[:300]

    stop_ms = None
    stop_error = None
    try:
        stop_payload = driver.invoke(action="stop", serial=serial, case="smoke")
        stop_ms = hc.numeric(stop_payload, "stopMs")
    except hc.HilError as exc:
        stop_error = str(exc)[:300]

    final = samples[-1] if samples else {}
    baseline = samples[0] if samples else {}
    underruns_final = final.get("underrunCount")
    underruns_base = baseline.get("underrunCount")
    growth = None
    if underruns_final is not None and underruns_base is not None:
        growth = underruns_final - underruns_base

    cases = []
    if start_ms is None:
        cases.append(make_case("start_latency", "blocked", "metric_unavailable",
                               "driver did not report startMs", target={"startMsMax": START_MS_MAX}))
    elif start_ms < START_MS_MAX:
        cases.append(make_case("start_latency", "pass", metrics={"startMs": start_ms},
                               target={"startMsMax": START_MS_MAX}))
    else:
        cases.append(make_case("start_latency", "fail", "start_latency_exceeded",
                               "startMs %.1f >= %.0f" % (start_ms, START_MS_MAX),
                               metrics={"startMs": start_ms}, target={"startMsMax": START_MS_MAX}))

    if stop_ms is None:
        cases.append(make_case("stop_latency", "blocked", "metric_unavailable",
                               stop_error or "driver did not report stopMs",
                               target={"stopMsMax": STOP_MS_MAX}))
    elif stop_ms < STOP_MS_MAX:
        cases.append(make_case("stop_latency", "pass", metrics={"stopMs": stop_ms},
                               target={"stopMsMax": STOP_MS_MAX}))
    else:
        cases.append(make_case("stop_latency", "fail", "stop_latency_exceeded",
                               "stopMs %.1f >= %.0f" % (stop_ms, STOP_MS_MAX),
                               metrics={"stopMs": stop_ms}, target={"stopMsMax": STOP_MS_MAX}))

    if growth is None:
        cases.append(make_case("underrun_stability", "blocked", "metric_unavailable",
                               sample_error or "underrun counters unavailable",
                               target={"growthMax": UNDERRUN_GROWTH_MAX}))
    elif growth <= UNDERRUN_GROWTH_MAX:
        cases.append(make_case("underrun_stability", "pass",
                               metrics={"underrunGrowth": growth, "underrunCount": underruns_final,
                                        "overrunCount": final.get("overrunCount")},
                               target={"growthMax": UNDERRUN_GROWTH_MAX}))
    else:
        cases.append(make_case("underrun_stability", "fail", "underrun_growth",
                               "underruns grew by %d over %.0f s" % (growth, parameters["durationS"]),
                               metrics={"underrunGrowth": growth, "underrunCount": underruns_final},
                               target={"growthMax": UNDERRUN_GROWTH_MAX}))

    status = overall_status(cases)
    reason = None
    if status == "blocked":
        reason = next((case["reason"] for case in cases if case.get("status") == "blocked"), "incomplete")
    elif status == "fail":
        reason = "latency_or_underrun_gate"
    blockers = []
    if status == "blocked":
        for case in cases:
            if case.get("status") == "blocked":
                blockers.append(hc.blocker(case["reason"], case.get("detail"), case["id"]))

    result = hc.make_result(
        "smoke", status, reason=reason, parameters=parameters,
        metrics={
            "startMs": start_ms,
            "stopMs": stop_ms,
            "underrunCount": underruns_final,
            "overrunCount": final.get("overrunCount"),
            "driftPpm": None,
            "bufferMs": final.get("bufferMs"),
            "cpuPct": final.get("cpuPct"),
            "memMb": final.get("memMb"),
        },
        cases=cases,
        blockers=blockers,
        environment_block=env,
    )
    return hc.finish(result, args.out, args.gate)


if __name__ == "__main__":
    sys.exit(hc.run_main(main))
