#!/usr/bin/env python3
"""Tests for the Pulsr FFT & audio measurement harness (scripts/hil/measure_fft.py).

Runs under pytest (`python -m pytest scripts/hil/tests -q`) and standalone
(`python scripts/hil/tests/test_measure_fft.py`) with plain asserts.
"""

from __future__ import annotations

import json
import math
import os
import shutil
import struct
import sys
import tempfile
import wave

_HERE = os.path.dirname(os.path.abspath(__file__))
_HIL_DIR = os.path.dirname(_HERE)
if _HIL_DIR not in sys.path:
    sys.path.insert(0, _HIL_DIR)

import hil_common as hc  # noqa: E402
import measure_fft  # noqa: E402


def _tempdir():
    return tempfile.mkdtemp(prefix="pulsr-fft-test-")


def _write_sine_wav(path: str, freq: float = 1000.0, rate: int = 48000, duration_s: float = 0.5, amp_dbfs: float = -3.0):
    total_frames = int(rate * duration_s)
    amp = 10.0 ** (amp_dbfs / 20.0)
    with wave.open(path, "wb") as wf:
        wf.setnchannels(2)
        wf.setsampwidth(2)
        wf.setframerate(rate)
        raw = bytearray()
        for i in range(total_frames):
            val = int(amp * math.sin(2.0 * math.pi * freq * (i / rate)) * 32767.0)
            val = max(-32768, min(32767, val))
            sample = struct.pack("<hh", val, val)
            raw.extend(sample)
        wf.writeframes(raw)


def _write_stereo_sine_wav(path: str, freq_l: float = 1000.0, freq_r: float = 0.0, rate: int = 48000, duration_s: float = 0.5):
    total_frames = int(rate * duration_s)
    with wave.open(path, "wb") as wf:
        wf.setnchannels(2)
        wf.setsampwidth(2)
        wf.setframerate(rate)
        raw = bytearray()
        for i in range(total_frames):
            val_l = int(0.707 * math.sin(2.0 * math.pi * freq_l * (i / rate)) * 32767.0)
            val_r = int(0.707 * math.sin(2.0 * math.pi * freq_r * (i / rate)) * 32767.0) if freq_r > 0 else 0
            val_l = max(-32768, min(32767, val_l))
            val_r = max(-32768, min(32767, val_r))
            raw.extend(struct.pack("<hh", val_l, val_r))
        wf.writeframes(raw)


def test_offline_reference_matrix_produces_full_report():
    tmp = _tempdir()
    try:
        md_path = os.path.join(tmp, "report.md")
        json_path = os.path.join(tmp, "report.json")
        code = measure_fft.main(["--offline", "--out", md_path, "--json-out", json_path])
        assert code == hc.EXIT_OK, f"Expected EXIT_OK, got {code}"
        assert os.path.isfile(md_path)
        assert os.path.isfile(json_path)

        with open(json_path, "r", encoding="utf-8") as f:
            data = json.load(f)

        assert data["schemaVersion"] == 1
        assert data["kind"] == "fft_measurement"
        assert data["status"] == "pass"
        assert data["provenance"] == "offline_reference"
        assert data["counts"]["total"] >= 10
        assert data["counts"]["fail"] == 0

        case_ids = {c["id"]: c for c in data["cases"]}
        assert "thd_16bit_dither_off" in case_ids
        assert "thd_16bit_dither_on" in case_ids
        assert "thd_24bit_dither_on" in case_ids
        assert "noise_floor_16bit_dither_on" in case_ids
        assert "noise_floor_24bit_dither_on" in case_ids
        assert "imd_smpte_24bit" in case_ids
        assert "crosstalk_1khz" in case_ids
        assert "jitter_12khz" in case_ids

        # Verify dither on 16-bit linearizes quantization distortion
        thd_off = case_ids["thd_16bit_dither_off"]["metrics"]["thdDb"]
        thd_on = case_ids["thd_16bit_dither_on"]["metrics"]["thdDb"]
        assert thd_on < thd_off, f"Dither on THD ({thd_on} dB) should be lower than dither off ({thd_off} dB)"

        # Verify 24-bit noise floor is lower than 16-bit noise floor
        nf_16 = case_ids["noise_floor_16bit_dither_on"]["metrics"]["bandNoiseDbfs"]
        nf_24 = case_ids["noise_floor_24bit_dither_on"]["metrics"]["bandNoiseDbfs"]
        assert nf_24 < nf_16 - 30.0, f"24-bit noise floor ({nf_24}) should be >30 dB quieter than 16-bit ({nf_16})"

        # Verify markdown content
        with open(md_path, "r", encoding="utf-8") as f:
            md_text = f.read()
        assert "# Pulsr Audio Measurement & FFT Report" in md_text
        assert "offline_reference" in md_text
        assert "thd_16bit_dither_on" in md_text
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_single_wav_thdn_and_noise_measurement():
    tmp = _tempdir()
    try:
        wav_path = os.path.join(tmp, "sine_1k.wav")
        _write_sine_wav(wav_path, freq=1000.0, rate=48000, duration_s=0.5, amp_dbfs=-3.0)

        json_path = os.path.join(tmp, "out.json")
        code = measure_fft.main(["--wav", wav_path, "--mode", "thdn", "--json-out", json_path])
        assert code == hc.EXIT_OK

        with open(json_path, "r", encoding="utf-8") as f:
            data = json.load(f)

        assert data["status"] == "pass"
        assert len(data["cases"]) == 1
        metrics = data["cases"][0]["metrics"]
        assert abs(metrics["fundamentalHz"] - 1000.0) < 5.0
        assert abs(metrics["fundamentalDbfs"] - (-3.0)) < 0.5
        assert metrics["thdnDb"] < -80.0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_single_wav_crosstalk():
    tmp = _tempdir()
    try:
        wav_path = os.path.join(tmp, "crosstalk.wav")
        _write_stereo_sine_wav(wav_path, freq_l=1000.0, freq_r=0.0, rate=48000, duration_s=0.5)

        json_path = os.path.join(tmp, "xtalk.json")
        code = measure_fft.main(["--wav", wav_path, "--mode", "crosstalk", "--json-out", json_path])
        assert code == hc.EXIT_OK

        with open(json_path, "r", encoding="utf-8") as f:
            data = json.load(f)

        assert data["status"] == "pass"
        metrics = data["cases"][0]["metrics"]
        assert metrics["crosstalkDb"] < -80.0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_hardware_loopback_without_device_reports_blocked():
    tmp = _tempdir()
    try:
        json_path = os.path.join(tmp, "loopback.json")
        code = measure_fft.main(["--hardware-loopback", "--require-hardware", "--gate", "--json-out", json_path])
        assert code == hc.EXIT_BLOCKED_GATE

        with open(json_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        assert data["status"] == "blocked"
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


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
        except Exception as exc:  # noqa: BLE001
            failures.append((name, exc))
            print(f"FAIL {name}: {type(exc).__name__}: {exc}")
        else:
            print(f"PASS {name}")
    print(f"{len(tests) - len(failures)} passed, {len(failures)} failed, {len(tests)} total")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
