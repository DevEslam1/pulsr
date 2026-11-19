#!/usr/bin/env python3
"""unplug_replug.py - USB DAC hot-plug recovery gate.

Each cycle drives a documented relay/hub switch command (--relay-cmd) to cut and
restore VBUS/data, then measures how long playback takes to recover through the
rig driver (--driver-cmd), asserting:
  * recovery latency < 2000 ms for every cycle
  * the app process id does not change (no silent restart)
  * the DAC's pending-drain flag is cleared after recovery

Without --relay-cmd the gate reports blocked/no_relay and claims zero cycles:
it will not pretend a cable was pulled.  Without a device it reports
blocked/no_device.  Neither is a pass.
"""

from __future__ import annotations

import argparse
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import hil_common as hc

DEFAULT_CYCLES = 500
DEFAULT_MAX_RECOVERY_MS = 2000.0
DEFAULT_SETTLE_S = 1.0
POLL_S = 0.1


def make_case(case_id, status, reason=None, detail=None, metrics=None, target=None):
    case = {"id": case_id, "status": status, "reason": reason, "metrics": metrics or {}}
    if detail:
        case["detail"] = detail
    if target is not None:
        case["target"] = target
    return case


def blocked_cases(reason, detail=None):
    return [
        make_case("cycles_completed", "blocked", reason, detail),
        make_case("recovery_budget", "blocked", reason, detail,
                  target={"maxRecoveryMs": DEFAULT_MAX_RECOVERY_MS}),
        make_case("pid_stability", "blocked", reason, detail),
        make_case("drain_pending_cleared", "blocked", reason, detail),
    ]


def relay_cycle(template, timeout, **fields):
    """Run the relay command; a non-zero exit is a rig error, not a test failure."""
    argv = []
    for token in hc.split_command(template):
        try:
            argv.append(token.format(**fields))
        except KeyError as exc:
            raise hc.HilError("relay template references unknown placeholder %s" % exc)
    res = hc.run_cmd(argv, timeout=timeout)
    if res["rc"] is None:
        raise hc.HilError("relay command could not run: %s" % res["error"])
    if res["rc"] != 0:
        lines = (res["stderr"] or res["stdout"] or "").strip().splitlines()
        raise hc.HilError("relay exited %s: %s" % (res["rc"], lines[-1][:200] if lines else "no output"))


def wait_for_recovery(driver, serial, cycle, max_wait_s):
    """Poll the rig until it reports recovery; return the observed payload."""
    deadline = time.monotonic() + max_wait_s
    last = {}
    while True:
        payload = driver.invoke(action="status", serial=serial, case="unplug", cycle=cycle)
        last = payload
        if payload.get("recovered") is True or hc.numeric(payload, "recoveryMs") is not None:
            return payload
        if time.monotonic() >= deadline:
            return last
        time.sleep(POLL_S)


def main(argv=None):
    parser = argparse.ArgumentParser(
        prog="unplug_replug.py",
        description="Unplug/replug recovery gate driven by a relay/hub switch command.",
    )
    hc.add_output_args(parser, "unplug_replug")
    hc.add_device_args(parser)
    hc.add_driver_args(parser)
    parser.add_argument("--cycles", type=int, default=DEFAULT_CYCLES,
                        help="number of unplug/replug cycles (default: %(default)s)")
    parser.add_argument("--relay-cmd", default=None,
                        help="relay/hub command template with {action} (off|on) and {cycle}; "
                        "documented in scripts/hil/README.md")
    parser.add_argument("--max-recovery-ms", type=float, default=DEFAULT_MAX_RECOVERY_MS,
                        help="per-cycle recovery budget in ms (default: %(default)s)")
    parser.add_argument("--settle", type=float, default=DEFAULT_SETTLE_S,
                        help="seconds to hold the link down per cycle (default: %(default)s)")
    parser.add_argument("--timeout", type=int, default=60, help="per-command timeout (seconds)")
    args = parser.parse_args(argv)

    if args.cycles <= 0:
        raise hc.HilError("--cycles must be greater than 0")

    probe = hc.probe_adb(args.adb)
    env = hc.environment(probe)
    serials = hc.ready_serials(probe)
    parameters = {
        "cyclesRequested": args.cycles,
        "cyclesCompleted": 0,
        "relayConfigured": bool(args.relay_cmd),
        "driverConfigured": bool(args.driver_cmd),
        "maxRecoveryMs": args.max_recovery_ms,
        "settleS": args.settle,
        "dryRun": bool(args.dry_run),
        "devicesAttached": len(serials),
    }
    missing_relay = None if args.relay_cmd else hc.blocker(
        "no_relay", "no --relay-cmd supplied; no cable was pulled and zero cycles are claimed"
    )

    if not serials:
        result = hc.blocked_result(
            "unplug_replug", "no_device",
            detail=env.get("adbError") or "adb reported zero attached devices",
            parameters=parameters, environment_block=env,
            cases=blocked_cases("no_device"),
            extra_blockers=[missing_relay] if missing_relay else None,
        )
        return hc.finish(result, args.out, args.gate)

    serial = args.serial or serials[0]
    if serial not in serials:
        result = hc.blocked_result(
            "unplug_replug", "no_device", detail="requested --serial is not attached",
            parameters=parameters, environment_block=env, cases=blocked_cases("no_device"),
            extra_blockers=[missing_relay] if missing_relay else None,
        )
        return hc.finish(result, args.out, args.gate)

    env = hc.annotate_device(env, probe["path"], serial)

    if not args.relay_cmd:
        detail = "no --relay-cmd supplied; no cable was pulled and zero cycles are claimed"
        result = hc.blocked_result(
            "unplug_replug", "no_relay", detail=detail,
            parameters=parameters, environment_block=env, cases=blocked_cases("no_relay", detail),
        )
        return hc.finish(result, args.out, args.gate)

    if args.dry_run:
        result = hc.blocked_result(
            "unplug_replug", "dry_run", detail="dry run: relay not actuated, zero cycles claimed",
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
            "unplug_replug", "no_usb_audio_endpoint", detail=detail,
            parameters=parameters, environment_block=env,
            cases=blocked_cases("no_usb_audio_endpoint", detail),
        )
        return hc.finish(result, args.out, args.gate)

    if not args.driver_cmd:
        detail = "device and relay present but --driver-cmd is missing; recovery cannot be observed"
        result = hc.blocked_result(
            "unplug_replug", "no_probe_driver", detail=detail,
            parameters=parameters, environment_block=env,
            cases=blocked_cases("no_probe_driver", detail),
        )
        return hc.finish(result, args.out, args.gate)

    driver = hc.Driver(args.driver_cmd, timeout=args.timeout)
    cycles = []
    relay_error = None
    for cycle in range(1, args.cycles + 1):
        try:
            relay_cycle(args.relay_cmd, args.timeout, action="off", cycle=cycle, serial=serial)
            time.sleep(max(0.0, args.settle))
            relay_cycle(args.relay_cmd, args.timeout, action="on", cycle=cycle, serial=serial)
        except hc.HilError as exc:
            relay_error = "cycle %d: %s" % (cycle, exc)
            break

        started = time.monotonic()
        try:
            payload = wait_for_recovery(driver, serial, cycle, args.timeout)
        except hc.HilError as exc:
            cycles.append({"cycle": cycle, "ok": False, "reason": "driver_error",
                           "detail": str(exc)[:200]})
            break
        elapsed_ms = round((time.monotonic() - started) * 1000.0, 1)
        reported = hc.numeric(payload, "recoveryMs")
        recovered = payload.get("recovered")
        drain = payload.get("drainPending")
        cycles.append(
            {
                "cycle": cycle,
                "recoveryMs": reported if reported is not None else elapsed_ms,
                "recoverySource": "rig" if reported is not None else "harness",
                "recovered": recovered if isinstance(recovered, bool) else (reported is not None),
                "pid": payload.get("pid") if isinstance(payload.get("pid"), int) else None,
                "drainPending": drain if isinstance(drain, bool) else None,
                "underrunCount": hc.numeric(payload, "underrunCount"),
                "overrunCount": hc.numeric(payload, "overrunCount"),
                "bufferMs": hc.numeric(payload, "bufferMs"),
                "ok": bool(recovered if isinstance(recovered, bool) else (reported is not None)),
            }
        )
        if cycle == 1 or cycle % 50 == 0 or cycle == args.cycles:
            print("cycle %d/%d: recovery=%s ms pid=%s" % (
                cycle, args.cycles, cycles[-1]["recoveryMs"], cycles[-1]["pid"]), flush=True)

    parameters["cyclesCompleted"] = len([c for c in cycles if c.get("ok")])
    artifacts = []
    if cycles:
        sidecar = os.path.splitext(os.path.abspath(args.out))[0] + ".cycles.jsonl"
        artifacts.append(hc.write_jsonl(cycles, sidecar))

    if relay_error and not cycles:
        result = hc.make_result(
            "unplug_replug", "error", reason="relay_error", parameters=parameters,
            environment_block=env, artifacts=artifacts,
            blockers=[hc.blocker("relay_error", relay_error)],
        )
        return hc.finish(result, args.out, args.gate)

    measured = [c for c in cycles if c.get("recoveryMs") is not None]
    over_budget = [c for c in measured if c["recoveryMs"] >= args.max_recovery_ms]
    pids = [c["pid"] for c in cycles if c.get("pid") is not None]
    drain_flags = [c["drainPending"] for c in cycles if c.get("drainPending") is not None]
    worst = max(measured, key=lambda c: c["recoveryMs"]) if measured else None

    cases = [
        make_case(
            "cycles_completed",
            "pass" if len(cycles) == args.cycles else "fail",
            None if len(cycles) == args.cycles else "cycles_incomplete",
            None if len(cycles) == args.cycles else "completed %d of %d cycles"
            % (len(cycles), args.cycles),
            metrics={"completed": len(cycles), "requested": args.cycles},
        )
    ]

    if not measured:
        cases.append(make_case("recovery_budget", "blocked", "metric_unavailable",
                               "no cycle reported a recovery time",
                               target={"maxRecoveryMs": args.max_recovery_ms}))
    elif over_budget:
        cases.append(make_case("recovery_budget", "fail", "recovery_budget_exceeded",
                               "%d cycle(s) at or above %.0f ms; worst %.1f ms"
                               % (len(over_budget), args.max_recovery_ms, worst["recoveryMs"]),
                               metrics={"worstRecoveryMs": worst["recoveryMs"],
                                        "overBudget": len(over_budget)},
                               target={"maxRecoveryMs": args.max_recovery_ms}))
    else:
        cases.append(make_case("recovery_budget", "pass",
                               metrics={"worstRecoveryMs": worst["recoveryMs"],
                                        "cyclesMeasured": len(measured)},
                               target={"maxRecoveryMs": args.max_recovery_ms}))

    if not pids:
        cases.append(make_case("pid_stability", "blocked", "metric_unavailable",
                               "rig driver did not report a pid"))
    elif len(set(pids)) == 1:
        cases.append(make_case("pid_stability", "pass", metrics={"pid": pids[0], "observations": len(pids)}))
    else:
        cases.append(make_case("pid_stability", "fail", "process_restarted",
                               "%d distinct pids observed: %s" % (len(set(pids)), sorted(set(pids))[:5]),
                               metrics={"distinctPids": len(set(pids))}))

    if not drain_flags:
        cases.append(make_case("drain_pending_cleared", "blocked", "metric_unavailable",
                               "rig driver did not report drainPending"))
    elif any(drain_flags):
        cases.append(make_case("drain_pending_cleared", "fail", "drain_pending_stuck",
                               "%d cycle(s) left drainPending set" % sum(1 for flag in drain_flags if flag)))
    else:
        cases.append(make_case("drain_pending_cleared", "pass",
                               metrics={"observations": len(drain_flags)}))

    statuses = [case["status"] for case in cases]
    if "fail" in statuses:
        status, reason = "fail", "hotplug_gate"
    elif "error" in statuses:
        status, reason = "error", "hotplug_error"
    elif all(item == "pass" for item in statuses):
        status, reason = "pass", None
    else:
        status = "blocked"
        reason = next((case["reason"] for case in cases if case["status"] == "blocked"), "incomplete")
    blockers = []
    if status == "blocked":
        for case in cases:
            if case["status"] == "blocked":
                blockers.append(hc.blocker(case["reason"], case.get("detail"), case["id"]))

    last_cycle = cycles[-1] if cycles else {}
    result = hc.make_result(
        "unplug_replug", status, reason=reason, parameters=parameters,
        metrics={
            "startMs": None,
            "stopMs": None,
            "underrunCount": hc.numeric(last_cycle, "underrunCount"),
            "overrunCount": hc.numeric(last_cycle, "overrunCount"),
            "driftPpm": None,
            "bufferMs": hc.numeric(last_cycle, "bufferMs"),
            "cpuPct": None,
            "memMb": None,
        },
        cases=cases,
        blockers=blockers,
        environment_block=env,
        artifacts=artifacts,
    )
    result["summary"] = {
        "cyclesRequested": args.cycles,
        "cyclesCompleted": parameters["cyclesCompleted"],
        "worstRecoveryMs": worst["recoveryMs"] if worst else None,
        "distinctPids": len(set(pids)) if pids else None,
        "relayError": relay_error,
    }
    return hc.finish(result, args.out, args.gate)


if __name__ == "__main__":
    sys.exit(hc.run_main(main))
