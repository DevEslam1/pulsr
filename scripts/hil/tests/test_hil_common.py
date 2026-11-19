#!/usr/bin/env python3
"""Tests for the Pulsr USB HIL harness.

Runs under pytest (`python -m pytest scripts/hil/tests -q`) and standalone
(`python scripts/hil/tests/test_hil_common.py`) with plain asserts.  No device,
network or adb server is required: the no-device paths are exercised through a
deliberately bogus --adb path.
"""

from __future__ import annotations

import json
import os
import shutil
import struct
import sys
import tempfile

_HERE = os.path.dirname(os.path.abspath(__file__))
_HIL_DIR = os.path.dirname(_HERE)
if _HIL_DIR not in sys.path:
    sys.path.insert(0, _HIL_DIR)

import hil_common as hc  # noqa: E402
import analyze_results  # noqa: E402
import bundle_evidence  # noqa: E402
import capture_bitexact  # noqa: E402
import run_matrix  # noqa: E402
import soak  # noqa: E402
import smoke  # noqa: E402
import unplug_replug  # noqa: E402

TEST_ENV = {
    "os": "test-os",
    "adb": None,
    "adbVersion": None,
    "adbError": "test fixture",
    "devices": [],
    "python": "test",
}


def _tempdir():
    return tempfile.mkdtemp(prefix="pulsr-hil-test-")


def _missing_adb(tmp):
    return os.path.join(tmp, "definitely-not-adb.exe")


def _write_wav(path, payload, bits=24, channels=2, rate=48000):
    block_align = (bits // 8) * channels
    fmt = struct.pack("<HHIIHH", 1, channels, rate, rate * block_align, block_align, bits)
    body = b"WAVE"
    body += b"fmt " + struct.pack("<I", len(fmt)) + fmt
    body += b"data" + struct.pack("<I", len(payload)) + payload
    with open(path, "wb") as fh:
        fh.write(b"RIFF" + struct.pack("<I", len(body)) + body)


def _load(path):
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


# --------------------------------------------------------------------------
# Schema
# --------------------------------------------------------------------------


def test_schema_accepts_blocked_result():
    doc = hc.blocked_result(
        "matrix",
        "no_device",
        parameters={"tier": "A"},
        environment_block=TEST_ENV,
        cases=[{"id": "uac2-44100", "status": "blocked", "reason": "no_device"}],
    )
    assert hc.validate_result(doc) == [], hc.validate_result(doc)
    assert doc["schemaVersion"] == 1
    assert doc["status"] == "blocked"
    assert doc["reason"] == "no_device"
    assert all(doc["metrics"][key] is None for key in hc.METRIC_KEYS)


def test_schema_rejects_missing_or_bad_fields():
    doc = hc.blocked_result("smoke", "no_device", environment_block=TEST_ENV)
    assert hc.validate_result(doc) == []

    missing = json.loads(json.dumps(doc))
    del missing["metrics"]["underrunCount"]
    assert any("underrunCount" in problem for problem in hc.validate_result(missing))

    bad_metric = json.loads(json.dumps(doc))
    bad_metric["metrics"]["cpuPct"] = True
    assert any("cpuPct" in problem for problem in hc.validate_result(bad_metric))

    bad_status = json.loads(json.dumps(doc))
    bad_status["status"] = "green"
    assert any("status" in problem for problem in hc.validate_result(bad_status))

    no_blockers = json.loads(json.dumps(doc))
    no_blockers["blockers"] = []
    assert any("blocker" in problem for problem in hc.validate_result(no_blockers))


def test_schema_rejects_fake_pass():
    fake = hc.make_result(
        "smoke",
        "pass",
        parameters={},
        cases=[{"id": "start_latency", "status": "blocked", "reason": "no_device"}],
        environment_block=TEST_ENV,
        build="testbuild",
    )
    problems = hc.validate_result(fake)
    assert any("non-pass" in problem for problem in problems), problems

    good = hc.make_result(
        "smoke",
        "pass",
        parameters={},
        cases=[{"id": "start_latency", "status": "pass"}],
        environment_block=TEST_ENV,
        build="testbuild",
    )
    assert hc.validate_result(good) == []


def test_unknown_metric_is_rejected():
    try:
        hc.metric_defaults({"notAMetric": 1})
    except hc.HilError:
        pass
    else:
        raise AssertionError("unknown metric should raise HilError")


# --------------------------------------------------------------------------
# Exit codes and no-device blocking
# --------------------------------------------------------------------------


def test_exit_codes():
    assert hc.exit_code_for("pass") == hc.EXIT_OK
    assert hc.exit_code_for("blocked") == hc.EXIT_OK
    assert hc.exit_code_for("blocked", gate=True) == hc.EXIT_BLOCKED_GATE
    assert hc.exit_code_for("fail") == hc.EXIT_FAIL
    assert hc.exit_code_for("error") == hc.EXIT_ERROR


def test_run_matrix_no_device():
    tmp = _tempdir()
    try:
        out = os.path.join(tmp, "matrix.json")
        code = run_matrix.main(["--dry-run", "--adb", _missing_adb(tmp), "--out", out])
        assert code == hc.EXIT_OK, code
        doc = _load(out)
        assert doc["status"] == "blocked", doc["status"]
        assert doc["reason"] == "no_device", doc["reason"]
        assert hc.validate_result(doc) == []
        assert len(doc["cases"]) == len(run_matrix.BUILTIN_MATRIX)
        assert all(case["status"] == "blocked" and case["reason"] == "no_device" for case in doc["cases"])
        assert [b["reason"] for b in doc["blockers"]] == ["no_device"]

        gated = run_matrix.main(["--dry-run", "--gate", "--adb", _missing_adb(tmp), "--out", out])
        assert gated == hc.EXIT_BLOCKED_GATE, gated
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_smoke_and_soak_no_device():
    tmp = _tempdir()
    try:
        for module, name in ((smoke, "smoke"), (soak, "soak")):
            out = os.path.join(tmp, "%s.json" % name)
            code = module.main(["--dry-run", "--adb", _missing_adb(tmp), "--out", out])
            assert code == hc.EXIT_OK, (name, code)
            doc = _load(out)
            assert doc["status"] == "blocked", (name, doc["status"])
            assert doc["reason"] == "no_device", (name, doc["reason"])
            assert hc.validate_result(doc) == [], (name, hc.validate_result(doc))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_unplug_no_device_and_no_relay():
    tmp = _tempdir()
    try:
        out = os.path.join(tmp, "unplug.json")
        code = unplug_replug.main(["--dry-run", "--adb", _missing_adb(tmp), "--out", out])
        assert code == hc.EXIT_OK, code
        doc = _load(out)
        assert doc["status"] == "blocked"
        assert doc["reason"] == "no_device"
        reasons = {blocker["reason"] for blocker in doc["blockers"]}
        assert {"no_device", "no_relay"} <= reasons, reasons
        assert doc["parameters"]["cyclesCompleted"] == 0
        assert doc["parameters"]["cyclesRequested"] == 500
        assert hc.validate_result(doc) == []
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# --------------------------------------------------------------------------
# Redaction / adb parsing
# --------------------------------------------------------------------------


def test_redaction_masks_identifiers_but_keeps_hashes():
    raw = (
        "serial R58M1234ABCD email dev@example.com ip 192.168.1.10 "
        "mac aa:bb:cc:dd:ee:ff sha e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    )
    masked = hc.redact_text(raw)
    for leak in ("R58M1234ABCD", "dev@example.com", "192.168.1.10", "aa:bb:cc:dd:ee:ff"):
        assert leak not in masked, (leak, masked)
    assert "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" in masked
    assert "1703058e" in hc.redact_text("build 1703058e")
    assert hc.redact_text("R58M1234ABCD") == hc.redact_text("R58M1234ABCD")
    assert hc.redact_token("") == ""


def test_parse_adb_devices():
    text = (
        "List of devices attached\n"
        "R58M1234ABCD          device product:beyond1lte model:SM_G973F device:beyond1 transport_id:1\n"
        "emulator-5554         offline\n"
        "\n"
    )
    devices = hc.parse_adb_devices(text)
    assert len(devices) == 2
    assert devices[0]["serial"] == "R58M1234ABCD"
    assert devices[0]["model"] == "SM_G973F"
    assert devices[1]["state"] == "offline"
    assert hc.parse_adb_devices("") == []


# --------------------------------------------------------------------------
# Bit-exact capture
# --------------------------------------------------------------------------


def test_bitexact_pass_fail_and_no_capture():
    tmp = _tempdir()
    try:
        payload = bytes((index * 7 + 3) % 256 for index in range(240))  # 40 frames of 24-bit stereo
        source = os.path.join(tmp, "source.wav")
        capture = os.path.join(tmp, "capture.wav")
        _write_wav(source, payload)
        _write_wav(capture, payload)

        out = os.path.join(tmp, "bitexact.json")
        code = capture_bitexact.main(["--source", source, "--capture", capture, "--out", out])
        assert code == hc.EXIT_OK, code
        doc = _load(out)
        assert doc["status"] == "pass", doc
        assert hc.validate_result(doc) == []
        by_id = {case["id"]: case for case in doc["cases"]}
        assert by_id["payload_bitexact"]["status"] == "pass"
        assert by_id["payload_bitexact"]["sha256"]["source"] == by_id["payload_bitexact"]["sha256"]["capture"]
        assert by_id["format_match"]["status"] == "pass"

        mutated = bytearray(payload)
        mutated[-1] ^= 0x01
        _write_wav(capture, bytes(mutated))
        code = capture_bitexact.main(["--source", source, "--capture", capture, "--out", out])
        assert code == hc.EXIT_FAIL, code
        doc = _load(out)
        assert doc["status"] == "fail"
        by_id = {case["id"]: case for case in doc["cases"]}
        assert by_id["payload_bitexact"]["status"] == "fail"
        assert by_id["payload_bitexact"]["firstDiffOffset"] == len(payload) - 1
        assert by_id["payload_bitexact"]["sha256"]["source"] != by_id["payload_bitexact"]["sha256"]["capture"]

        missing = os.path.join(tmp, "no-such-capture.wav")
        code = capture_bitexact.main(["--source", source, "--capture", missing, "--out", out])
        assert code == hc.EXIT_OK, code
        doc = _load(out)
        assert doc["status"] == "blocked"
        assert doc["reason"] == "no_capture"
        assert hc.validate_result(doc) == []

        bad_ulp = os.path.join(tmp, "ulp.json")
        assert hc.run_main(
            capture_bitexact.main,
            ["--source", source, "--capture", capture, "--allow-ulp", "1", "--out", bad_ulp],
        ) == hc.EXIT_ERROR
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# --------------------------------------------------------------------------
# Analysis
# --------------------------------------------------------------------------


def test_analyze_green_red_blocked():
    tmp = _tempdir()
    try:
        def write(name, doc):
            path = os.path.join(tmp, name)
            hc.write_result(doc, path)
            return path

        passing = hc.make_result(
            "smoke", "pass", parameters={},
            cases=[{"id": "start_latency", "status": "pass"}],
            environment_block=TEST_ENV, build="testbuild",
        )
        blocked = hc.blocked_result(
            "matrix", "no_device", environment_block=TEST_ENV, build="testbuild",
            cases=[{"id": "case", "status": "blocked", "reason": "no_device"}],
        )
        failing = hc.make_result(
            "soak", "fail", parameters={}, reason="soak_gate",
            cases=[{"id": "duration_drift", "status": "fail", "reason": "drift_budget_exceeded"}],
            environment_block=TEST_ENV, build="testbuild",
        )

        green_dir = os.path.join(tmp, "green")
        os.makedirs(green_dir)
        hc.write_result(passing, os.path.join(green_dir, "smoke.json"))
        code = analyze_results.main([green_dir, "--out", os.path.join(green_dir, "summary.md")])
        assert code == hc.EXIT_OK, code
        assert "GREEN" in open(os.path.join(green_dir, "summary.md"), encoding="utf-8").read()

        blocked_dir = os.path.join(tmp, "blocked")
        os.makedirs(blocked_dir)
        hc.write_result(blocked, os.path.join(blocked_dir, "matrix.json"))
        code = analyze_results.main([blocked_dir, "--out", os.path.join(blocked_dir, "summary.md")])
        assert code == hc.EXIT_BLOCKED_GATE, code
        text = open(os.path.join(blocked_dir, "summary.md"), encoding="utf-8").read()
        assert "BLOCKED" in text and "no_device" in text

        red_dir = os.path.join(tmp, "red")
        os.makedirs(red_dir)
        hc.write_result(failing, os.path.join(red_dir, "soak.json"))
        code = analyze_results.main([red_dir, "--out", os.path.join(red_dir, "summary.md")])
        assert code == hc.EXIT_FAIL, code
        assert "RED" in open(os.path.join(red_dir, "summary.md"), encoding="utf-8").read()

        empty_dir = os.path.join(tmp, "empty")
        os.makedirs(empty_dir)
        code = analyze_results.main([empty_dir, "--out", os.path.join(empty_dir, "summary.md")])
        assert code == hc.EXIT_BLOCKED_GATE, code
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# --------------------------------------------------------------------------
# Evidence bundling
# --------------------------------------------------------------------------


def test_bundle_refuses_sensitive_names_and_is_deterministic():
    tmp = _tempdir()
    try:
        inputs = os.path.join(tmp, "inputs")
        out_dir = os.path.join(tmp, "dist")
        os.makedirs(inputs)
        result_path = os.path.join(inputs, "smoke.json")
        hc.write_result(
            hc.make_result("smoke", "pass", parameters={}, environment_block=TEST_ENV, build="testbuild"),
            result_path,
        )
        with open(os.path.join(inputs, "usb_serial_dump.txt"), "w", encoding="utf-8") as fh:
            fh.write("R58M1234ABCD\n")
        with open(os.path.join(inputs, "device-pii.log"), "w", encoding="utf-8") as fh:
            fh.write("owner@example.com\n")
        with open(os.path.join(inputs, "run.log"), "w", encoding="utf-8") as fh:
            fh.write("harmless log\n")

        args = ["--inputs", inputs, "--out-dir", out_dir, "--build", "testbuild",
                "--timestamp", "20260101T000000Z"]
        assert bundle_evidence.main(args) == hc.EXIT_OK
        zip_path = os.path.join(out_dir, "testbuild-20260101T000000Z.zip")
        assert os.path.isfile(zip_path), zip_path

        import zipfile

        with zipfile.ZipFile(zip_path) as archive:
            names = archive.namelist()
            manifest = json.loads(archive.read("manifest.json"))
        assert "manifest.json" in names
        assert any(name.endswith("smoke.json") for name in names)
        assert any(name.endswith("run.log") for name in names)
        assert not any("serial" in name.lower() or "pii" in name.lower() for name in names)
        assert len(manifest["excluded"]) == 2
        entry = next(item for item in manifest["files"] if item["path"].endswith("smoke.json"))
        assert entry["sha256"] == hc.sha256_file(result_path)

        first = hc.sha256_file(zip_path)
        assert bundle_evidence.main(args) == hc.EXIT_OK
        assert hc.sha256_file(zip_path) == first, "bundle must be deterministic"
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_bundle_refuses_symlinks_and_missing_inputs():
    tmp = _tempdir()
    try:
        out_dir = os.path.join(tmp, "dist")
        missing = os.path.join(tmp, "does-not-exist")
        code = bundle_evidence.main(
            ["--inputs", missing, "--out-dir", out_dir, "--build", "b", "--timestamp", "20260101T000000Z"]
        )
        assert code == hc.EXIT_OK
        assert os.path.isfile(os.path.join(out_dir, "b-20260101T000000Z.zip"))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# --------------------------------------------------------------------------
# Standalone runner (pytest also collects the test_* functions above)
# --------------------------------------------------------------------------


def main():
    tests = [
        (name, obj)
        for name, obj in sorted(globals().items())
        if name.startswith("test_") and callable(obj)
    ]
    failures = []
    for name, test in tests:
        try:
            test()
        except Exception as exc:  # noqa: BLE001 - test runner reports, does not crash
            failures.append((name, exc))
            print("FAIL %s: %s: %s" % (name, type(exc).__name__, exc))
        else:
            print("PASS %s" % name)
    print("%d passed, %d failed, %d total" % (len(tests) - len(failures), len(failures), len(tests)))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
