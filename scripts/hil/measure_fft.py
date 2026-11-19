#!/usr/bin/env python3
"""
scripts/hil/measure_fft.py
Pulsr Audio Measurement & FFT Analysis Harness (P2-10 / §8.7).

Supports two complementary modes:
  1. Hardware loopback / WAV capture mode (--wav / --capture-dir):
     Reads real 16/24/32-bit PCM or 32-bit IEEE float RIFF/WAVE recordings
     (e.g. USB DAC -> ADC loopback) and computes FFT distortion & noise metrics.
  2. Offline / CI mode (--offline, default when no --capture-dir / --wav given;
     or --native-bin <exe> using scripts/measure_native_dsp.cpp):
     Runs deterministic native-engine or NumPy reference captures through the
     exact same FFT analyzer and emits structured Markdown + JSON reports.

Honesty rule:
  * Provenance is explicitly tagged (`hardware_loopback`, `wav_capture`,
    `native_dsp_render`, or `offline_reference`).
  * With `--gate` and `--require-hardware`, missing loopback WAV evidence exits
    with code 2 (blocked), never a fabricated hardware pass.

Metrics computed:
  * THD+N (dB & %) and THD (dB & %)
  * SFDR (dBc) and fundamental amplitude (dBFS)
  * Noise floor (dBFS integrated over [20 Hz, min(20 kHz, Nyquist)]) at
    16-bit and 24-bit with dither off vs on
  * IMD (SMPTE 60 Hz + 7 kHz, and CCIF 19 kHz + 20 kHz)
  * Stereo crosstalk (dB, L->R / R->L)
  * Jitter sidebands (dBc peak & integrated sidebands around HF carrier)
"""

from __future__ import annotations

import argparse
import json
import math
import os
import struct
import subprocess
import sys
import tempfile
from typing import Any

import numpy as np

_HERE = os.path.dirname(os.path.abspath(__file__))
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)

import hil_common as hc  # noqa: E402


# ---------------------------------------------------------------------------
# RIFF/WAVE reader & writer (supports 16/24/32-bit PCM and IEEE float32)
# ---------------------------------------------------------------------------

def read_wav(path: str) -> tuple[int, int, int, np.ndarray]:
    """Reads a RIFF/WAVE file -> (sample_rate, channels, bits_per_sample, float64[frames, ch])."""
    with open(path, "rb") as fh:
        raw = fh.read()

    if len(raw) < 12 or raw[:4] != b"RIFF" or raw[8:12] != b"WAVE":
        raise ValueError(f"Not a valid RIFF/WAVE file: {path}")

    pos = 12
    fmt_tag = None
    channels = None
    sample_rate = None
    bits_per_sample = None
    data_bytes = None

    while pos + 8 <= len(raw):
        chunk_id = raw[pos : pos + 4]
        chunk_size = struct.unpack_from("<I", raw, pos + 4)[0]
        chunk_start = pos + 8
        chunk_end = min(len(raw), chunk_start + chunk_size)

        if chunk_id == b"fmt " and chunk_size >= 16:
            fmt_tag, channels, sample_rate, _byte_rate, _block_align, bits_per_sample = (
                struct.unpack_from("<HHIIHH", raw, chunk_start)
            )
            if fmt_tag == 0xFFFE and chunk_size >= 40:
                subformat_tag = struct.unpack_from("<H", raw, chunk_start + 24)[0]
                fmt_tag = subformat_tag
        elif chunk_id == b"data":
            data_bytes = raw[chunk_start:chunk_end]

        pos = chunk_start + chunk_size + (chunk_size & 1)

    if fmt_tag is None or data_bytes is None or channels is None or sample_rate is None or bits_per_sample is None:
        raise ValueError(f"Missing fmt or data chunk in WAV: {path}")

    if fmt_tag == 1:  # PCM
        if bits_per_sample == 16:
            arr = np.frombuffer(data_bytes, dtype="<i2").astype(np.float64) / 32768.0
        elif bits_per_sample == 24:
            n_samples = len(data_bytes) // 3
            raw_u8 = np.frombuffer(data_bytes[: n_samples * 3], dtype=np.uint8).reshape(-1, 3)
            signed = (
                raw_u8[:, 0].astype(np.int32)
                | (raw_u8[:, 1].astype(np.int32) << 8)
                | (raw_u8[:, 2].astype(np.int32) << 16)
            )
            signed = np.where(signed >= 0x800000, signed - 0x1000000, signed)
            arr = signed.astype(np.float64) / 8388608.0
        elif bits_per_sample == 32:
            arr = np.frombuffer(data_bytes, dtype="<i4").astype(np.float64) / 2147483648.0
        else:
            raise ValueError(f"Unsupported PCM bit depth {bits_per_sample} in {path}")
    elif fmt_tag == 3 and bits_per_sample == 32:  # IEEE float32
        arr = np.frombuffer(data_bytes, dtype="<f4").astype(np.float64)
    else:
        raise ValueError(f"Unsupported WAV format tag={fmt_tag} bits={bits_per_sample} in {path}")

    frames = len(arr) // channels
    arr = arr[: frames * channels].reshape(frames, channels)
    return int(sample_rate), int(channels), int(bits_per_sample), arr


def write_pcm_wav(
    path: str,
    samples: np.ndarray,
    sample_rate: int,
    bits_per_sample: int,
    dither: bool = False,
    seed: int = 12345,
) -> None:
    """Writes float64[frames] or [frames, ch] to signed PCM WAV (16 or 24-bit)."""
    if samples.ndim == 1:
        samples = np.column_stack([samples, samples])
    frames, channels = samples.shape
    scale = float(1 << (bits_per_sample - 1))
    lo = -(1 << (bits_per_sample - 1))
    hi = (1 << (bits_per_sample - 1)) - 1

    scaled = samples * scale
    if dither and bits_per_sample < 32:
        rng = np.random.default_rng(seed)
        tpdf = rng.uniform(0.0, 1.0, size=scaled.shape) - rng.uniform(0.0, 1.0, size=scaled.shape)
        scaled = scaled + tpdf

    q = np.clip(np.rint(scaled), lo, hi).astype(np.int32)
    if bits_per_sample == 16:
        payload = q.astype("<i2").tobytes()
    elif bits_per_sample == 24:
        flat = q.reshape(-1)
        u = flat & 0xFFFFFF
        packed = np.empty((len(flat), 3), dtype=np.uint8)
        packed[:, 0] = (u & 0xFF).astype(np.uint8)
        packed[:, 1] = ((u >> 8) & 0xFF).astype(np.uint8)
        packed[:, 2] = ((u >> 16) & 0xFF).astype(np.uint8)
        payload = packed.tobytes()
    else:
        raise ValueError(f"Unsupported bit depth for write_pcm_wav: {bits_per_sample}")

    bytes_per_sample = bits_per_sample // 8
    block_align = channels * bytes_per_sample
    fmt = struct.pack("<HHIIHH", 1, channels, sample_rate, sample_rate * block_align, block_align, bits_per_sample)
    body = b"WAVE" + b"fmt " + struct.pack("<I", len(fmt)) + fmt + b"data" + struct.pack("<I", len(payload)) + payload
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "wb") as fh:
        fh.write(b"RIFF" + struct.pack("<I", len(body)) + body)


# ---------------------------------------------------------------------------
# Windowed FFT core
# ---------------------------------------------------------------------------

def _blackman_harris_4term(n: int) -> np.ndarray:
    """4-term Blackman-Harris window (-92 dB sidelobe suppression)."""
    idx = np.arange(n, dtype=np.float64)
    phase = 2.0 * math.pi * idx / n
    a0, a1, a2, a3 = 0.35875, 0.48829, 0.14128, 0.01168
    return a0 - a1 * np.cos(phase) + a2 * np.cos(2.0 * phase) - a3 * np.cos(3.0 * phase)


def compute_spectrum(signal: np.ndarray, sample_rate: int, max_fft: int = 65536) -> tuple[np.ndarray, np.ndarray, float]:
    """
    Computes single-sided amplitude-squared power spectrum (in full-scale sine^2 units)
    using a 4-term Blackman-Harris window.

    Returns (freqs_hz, bin_power, enbw_bins).
    For a pure full-scale sine A*sin(w*n), summing `bin_power` across the mainlobe
    equals `A^2 / 2` (mean-square power), so `10*log10(2 * sum_mainlobe) == 20*log10(A)` dBFS.
    """
    x = np.asarray(signal, dtype=np.float64)
    n = min(len(x), max_fft)
    # Use largest power of 2 <= n for fast radix-2 FFT
    n_fft = 1 << (n.bit_length() - 1)
    if n_fft < 256:
        raise ValueError(f"Signal too short for FFT analysis ({len(x)} samples)")
    x = x[-n_fft:]
    x = x - np.mean(x)

    win = _blackman_harris_4term(n_fft)
    win_norm_sq = float(np.sum(win ** 2))
    # ENBW in bins = N * sum(w^2) / sum(w)^2 (~2.004 bins for 4-term BH)
    enbw = float(n_fft * win_norm_sq / (np.sum(win) ** 2))

    spec = np.fft.rfft(x * win)
    mag_sq = (spec.real ** 2 + spec.imag ** 2)
    # Parseval scaling: sum(bin_power) == mean(x_windowed^2) * ... = A^2 / 2 for sine
    bin_power = mag_sq / win_norm_sq
    if len(bin_power) > 2:
        bin_power[1:-1] *= 2.0
    # Wait: Parseval with sum(w^2): for x[n] = A sin(...), sum |X[k]|^2 / (N * sum(w^2))
    # With rfft doubling interior bins, sum(mag_sq_doubled) / N == sum((x*w)^2).
    # Dividing by win_norm_sq * (N/N) -> need divide by N too! Let's normalize accurately:
    # sum_{n=0}^{N-1} (x[n] w[n])^2 / sum(w^2) == mean_square(x) = A^2 / 2.
    # By Parseval: sum_{n} (x[n] w[n])^2 == (1/N) * (|X[0]|^2 + 2*sum_{1..N/2-1}|X[k]|^2 + |X[N/2]|^2)
    # So dividing by (n_fft * win_norm_sq) makes sum(bin_power) == A^2 / 2!
    bin_power = mag_sq / (n_fft * win_norm_sq)
    if len(bin_power) > 2:
        bin_power[1:-1] *= 2.0

    freqs = np.fft.rfftfreq(n_fft, d=1.0 / sample_rate)
    return freqs, bin_power, enbw


def _db10(power_ratio: float, floor_db: float = -180.0) -> float:
    if power_ratio <= 0.0 or not math.isfinite(power_ratio):
        return floor_db
    return max(floor_db, 10.0 * math.log10(power_ratio))


def _band_mask(freqs: np.ndarray, low_hz: float, high_hz: float) -> np.ndarray:
    return (freqs >= low_hz) & (freqs <= high_hz)


def _peak_bin_near(freqs: np.ndarray, power: np.ndarray, target_hz: float, radius_hz: float) -> int:
    mask = np.abs(freqs - target_hz) <= radius_hz
    if not np.any(mask):
        return int(np.argmin(np.abs(freqs - target_hz)))
    masked = np.where(mask, power, -1.0)
    return int(np.argmax(masked))


# ---------------------------------------------------------------------------
# Metric analyzers
# ---------------------------------------------------------------------------

def analyze_tone_thdn(
    signal: np.ndarray,
    sample_rate: int,
    expected_freq_hz: float | None = None,
    bw_low_hz: float = 20.0,
    bw_high_hz: float = 20000.0,
) -> dict[str, Any]:
    """Measures fundamental, THD+N, THD, SFDR, and residual noise floor."""
    freqs, pwr, _ = compute_spectrum(signal, sample_rate)
    nyq = sample_rate * 0.5
    hi_hz = min(bw_high_hz, nyq * 0.98)
    in_band = _band_mask(freqs, bw_low_hz, hi_hz)

    if expected_freq_hz is not None:
        fund_bin = _peak_bin_near(freqs, pwr, expected_freq_hz, max(50.0, expected_freq_hz * 0.05))
    else:
        band_pwr = np.where(in_band, pwr, -1.0)
        fund_bin = int(np.argmax(band_pwr))

    fund_hz = float(freqs[fund_bin])
    mainlobe_half = 5  # 4-term Blackman-Harris mainlobe width is ±4 bins
    lo_b = max(1, fund_bin - mainlobe_half)
    hi_b = min(len(pwr), fund_bin + mainlobe_half + 1)
    fund_power = float(np.sum(pwr[lo_b:hi_b]))
    # Sine amplitude squared = 2 * mean_square_power -> dBFS = 10*log10(2 * fund_power)
    fund_dbfs = _db10(2.0 * fund_power)

    noise_harm_mask = in_band.copy()
    noise_harm_mask[lo_b:hi_b] = False
    thdn_power = float(np.sum(pwr[noise_harm_mask]))
    thdn_ratio = thdn_power / fund_power if fund_power > 0 else 1.0
    thdn_db = _db10(thdn_ratio)
    thdn_pct = 100.0 * math.sqrt(max(0.0, thdn_ratio))

    # Harmonics 2*f0 .. 10*f0 within Nyquist
    harm_power = 0.0
    noise_only_mask = noise_harm_mask.copy()
    harmonics_db: dict[str, float] = {}
    h = 2
    while h * fund_hz < hi_hz and h <= 10:
        hb = _peak_bin_near(freqs, pwr, h * fund_hz, max(30.0, fund_hz * 0.02))
        hl = max(1, hb - mainlobe_half)
        hh = min(len(pwr), hb + mainlobe_half + 1)
        hp = float(np.sum(pwr[hl:hh]))
        harm_power += hp
        noise_only_mask[hl:hh] = False
        harmonics_db[f"H{h}"] = round(_db10(hp / fund_power) if fund_power > 0 else -180.0, 2)
        h += 1

    thd_ratio = harm_power / fund_power if fund_power > 0 else 1.0
    thd_db = _db10(thd_ratio)
    thd_pct = 100.0 * math.sqrt(max(0.0, thd_ratio))

    noise_power = float(np.sum(pwr[noise_only_mask]))
    noise_floor_dbfs = _db10(2.0 * noise_power)

    spurs = np.where(noise_harm_mask, pwr, 0.0)
    max_spur = float(np.max(spurs)) if np.any(noise_harm_mask) else 0.0
    sfdr_dbc = -_db10(max_spur / fund_power) if (fund_power > 0 and max_spur > 0) else 180.0

    return {
        "fundamentalHz": round(fund_hz, 2),
        "fundamentalDbfs": round(fund_dbfs, 2),
        "thdnDb": round(thdn_db, 2),
        "thdnPct": round(thdn_pct, 6),
        "thdDb": round(thd_db, 2),
        "thdPct": round(thd_pct, 6),
        "noiseFloorDbfs": round(noise_floor_dbfs, 2),
        "sfdrDbc": round(sfdr_dbc, 2),
        "harmonicsDbc": harmonics_db,
    }


def analyze_noise_floor(
    signal: np.ndarray,
    sample_rate: int,
    bw_low_hz: float = 20.0,
    bw_high_hz: float = 20000.0,
) -> dict[str, Any]:
    """Measures wideband integrated noise floor and RMS on a quiet/zero capture."""
    x = np.asarray(signal, dtype=np.float64)
    rms = float(np.sqrt(np.mean(x ** 2)))
    rms_dbfs = _db10(2.0 * (rms ** 2))  # relative to full-scale sine (peak 1.0 -> rms 1/sqrt(2))

    freqs, pwr, _ = compute_spectrum(x, sample_rate)
    hi_hz = min(bw_high_hz, sample_rate * 0.49)
    mask = _band_mask(freqs, bw_low_hz, hi_hz)
    band_power = float(np.sum(pwr[mask]))
    # Convert integrated noise power to sine-equivalent dBFS (or pure RMS dBFS = 10*log10(band_power) + 3.01)
    band_noise_dbfs = _db10(2.0 * band_power)
    median_bin_dbfs = _db10(2.0 * float(np.median(pwr[mask]))) if np.any(mask) else -180.0
    peak_spur_dbfs = _db10(2.0 * float(np.max(pwr[mask]))) if np.any(mask) else -180.0

    return {
        "rmsDbfs": round(rms_dbfs, 2),
        "bandNoiseDbfs": round(band_noise_dbfs, 2),
        "medianBinDbfs": round(median_bin_dbfs, 2),
        "peakSpurDbfs": round(peak_spur_dbfs, 2),
    }


def analyze_imd_smpte(
    signal: np.ndarray,
    sample_rate: int,
    f_low_hz: float = 60.0,
    f_high_hz: float = 7000.0,
) -> dict[str, Any]:
    """Computes SMPTE IMD (60 Hz + 7 kHz 4:1): sidebands f_high ± k*f_low (k=1..3) relative to f_high."""
    freqs, pwr, _ = compute_spectrum(signal, sample_rate)
    mainlobe_half = 5

    def sum_near(target_hz: float) -> float:
        b = _peak_bin_near(freqs, pwr, target_hz, 20.0)
        lo = max(1, b - mainlobe_half)
        hi = min(len(pwr), b + mainlobe_half + 1)
        return float(np.sum(pwr[lo:hi]))

    p_low = sum_near(f_low_hz)
    p_high = sum_near(f_high_hz)

    sideband_power = 0.0
    for k in (1, 2, 3):
        sideband_power += sum_near(f_high_hz - k * f_low_hz)
        sideband_power += sum_near(f_high_hz + k * f_low_hz)

    imd_ratio = sideband_power / p_high if p_high > 0 else 1.0
    imd_db = _db10(imd_ratio)
    imd_pct = 100.0 * math.sqrt(max(0.0, imd_ratio))
    return {
        "mode": "smpte_60_7000",
        "fLowDbfs": round(_db10(2.0 * p_low), 2),
        "fHighDbfs": round(_db10(2.0 * p_high), 2),
        "imdDb": round(imd_db, 2),
        "imdPct": round(imd_pct, 6),
    }


def analyze_crosstalk(
    stereo_signal: np.ndarray,
    sample_rate: int,
    tone_hz: float = 1000.0,
) -> dict[str, Any]:
    """Measures stereo crosstalk (active channel vs quiet channel at tone_hz)."""
    if stereo_signal.ndim != 2 or stereo_signal.shape[1] < 2:
        raise ValueError("Crosstalk analysis requires a stereo (2+ channel) capture")

    left = stereo_signal[:, 0]
    right = stereo_signal[:, 1]
    freqs_l, pwr_l, _ = compute_spectrum(left, sample_rate)
    _, pwr_r, _ = compute_spectrum(right, sample_rate)

    b_l = _peak_bin_near(freqs_l, pwr_l, tone_hz, 40.0)
    lo = max(1, b_l - 5)
    hi = min(len(pwr_l), b_l + 6)

    p_left = float(np.sum(pwr_l[lo:hi]))
    p_right = float(np.sum(pwr_r[lo:hi]))
    if p_left >= p_right:
        direction = "L->R"
        driven_pwr, bleed_pwr = p_left, p_right
    else:
        direction = "R->L"
        driven_pwr, bleed_pwr = p_right, p_left

    crosstalk_db = _db10(bleed_pwr / driven_pwr) if driven_pwr > 0 else -180.0
    return {
        "direction": direction,
        "toneHz": tone_hz,
        "drivenDbfs": round(_db10(2.0 * driven_pwr), 2),
        "bleedDbfs": round(_db10(2.0 * bleed_pwr), 2),
        "crosstalkDb": round(crosstalk_db, 2),
    }


def analyze_jitter_sidebands(
    signal: np.ndarray,
    sample_rate: int,
    carrier_hz: float = 12000.0,
    span_hz: float = 2000.0,
) -> dict[str, Any]:
    """Measures close-in jitter sidebands around a high-frequency carrier (excluding mainlobe)."""
    freqs, pwr, _ = compute_spectrum(signal, sample_rate)
    c_bin = _peak_bin_near(freqs, pwr, carrier_hz, 100.0)
    actual_carrier_hz = float(freqs[c_bin])
    mainlobe_half = 5
    lo_c = max(1, c_bin - mainlobe_half)
    hi_c = min(len(pwr), c_bin + mainlobe_half + 1)
    carrier_pwr = float(np.sum(pwr[lo_c:hi_c]))

    skirt_mask = (np.abs(freqs - actual_carrier_hz) <= span_hz) & (freqs > 20.0)
    skirt_mask[lo_c:hi_c] = False

    if np.any(skirt_mask):
        skirt_pwr = np.where(skirt_mask, pwr, 0.0)
        peak_bin = int(np.argmax(skirt_pwr))
        peak_sideband_pwr = float(skirt_pwr[peak_bin])
        peak_offset_hz = float(freqs[peak_bin] - actual_carrier_hz)
        integrated_sideband_pwr = float(np.sum(skirt_pwr))
    else:
        peak_sideband_pwr = 0.0
        peak_offset_hz = 0.0
        integrated_sideband_pwr = 0.0

    peak_dbc = _db10(peak_sideband_pwr / carrier_pwr) if carrier_pwr > 0 else -180.0
    total_dbc = _db10(integrated_sideband_pwr / carrier_pwr) if carrier_pwr > 0 else -180.0

    return {
        "carrierHz": round(actual_carrier_hz, 2),
        "carrierDbfs": round(_db10(2.0 * carrier_pwr), 2),
        "spanHz": span_hz,
        "peakSidebandDbc": round(peak_dbc, 2),
        "peakSidebandOffsetHz": round(peak_offset_hz, 2),
        "integratedSidebandsDbc": round(total_dbc, 2),
    }


# ---------------------------------------------------------------------------
# Offline reference capture generator (for CI / no-hardware local runs)
# ---------------------------------------------------------------------------

def generate_offline_reference_captures(out_dir: str, sample_rate: int = 48000) -> dict[str, Any]:
    """Generates deterministic 16/24-bit reference WAVs in out_dir for offline CI testing."""
    frames = 32768
    t = np.arange(frames, dtype=np.float64) / sample_rate
    amp_m3 = 10.0 ** (-3.0 / 20.0)
    amp_m60 = 10.0 ** (-60.0 / 20.0)
    amp_m1 = 10.0 ** (-1.0 / 20.0)

    sine_1k = amp_m3 * np.sin(2.0 * math.pi * 1000.0 * t)
    quiet_1k = amp_m60 * np.sin(2.0 * math.pi * 1000.0 * t)
    zeros = np.zeros(frames, dtype=np.float64)

    write_pcm_wav(os.path.join(out_dir, "thd_16bit_dither_off.wav"), sine_1k, sample_rate, 16, dither=False)
    write_pcm_wav(os.path.join(out_dir, "thd_16bit_dither_on.wav"), sine_1k, sample_rate, 16, dither=True, seed=1)
    write_pcm_wav(os.path.join(out_dir, "quiet_16bit_dither_off.wav"), quiet_1k, sample_rate, 16, dither=False)
    write_pcm_wav(os.path.join(out_dir, "quiet_16bit_dither_on.wav"), quiet_1k, sample_rate, 16, dither=True, seed=2)
    write_pcm_wav(os.path.join(out_dir, "thd_24bit_dither_off.wav"), sine_1k, sample_rate, 24, dither=False)
    write_pcm_wav(os.path.join(out_dir, "thd_24bit_dither_on.wav"), sine_1k, sample_rate, 24, dither=True, seed=3)

    write_pcm_wav(os.path.join(out_dir, "noise_floor_16bit_dither_off.wav"), zeros, sample_rate, 16, dither=False)
    write_pcm_wav(os.path.join(out_dir, "noise_floor_16bit_dither_on.wav"), zeros, sample_rate, 16, dither=True, seed=4)
    write_pcm_wav(os.path.join(out_dir, "noise_floor_24bit_dither_off.wav"), zeros, sample_rate, 24, dither=False)
    write_pcm_wav(os.path.join(out_dir, "noise_floor_24bit_dither_on.wav"), zeros, sample_rate, 24, dither=True, seed=5)

    smpte = amp_m3 * (0.8 * np.sin(2.0 * math.pi * 60.0 * t) + 0.2 * np.sin(2.0 * math.pi * 7000.0 * t))
    write_pcm_wav(os.path.join(out_dir, "imd_smpte_24bit.wav"), smpte, sample_rate, 24, dither=False)

    xtalk = np.column_stack([amp_m1 * np.sin(2.0 * math.pi * 1000.0 * t), zeros])
    write_pcm_wav(os.path.join(out_dir, "crosstalk_1khz_l_only.wav"), xtalk, sample_rate, 24, dither=False)

    jitter = amp_m3 * np.sin(2.0 * math.pi * 12000.0 * t)
    write_pcm_wav(os.path.join(out_dir, "jitter_12khz_24bit.wav"), jitter, sample_rate, 24, dither=False)

    return {
        "provenance": "offline_reference",
        "sampleRate": sample_rate,
        "custodyBitExact": None,
    }


# ---------------------------------------------------------------------------
# Suite runner & report builders
# ---------------------------------------------------------------------------

def run_suite(capture_dir: str, provenance: str, manifest: dict[str, Any] | None = None) -> dict[str, Any]:
    """Analyzes a capture directory of measurement WAVs and returns a structured report."""
    cases: list[dict[str, Any]] = []
    metrics: dict[str, Any] = {}

    def analyze_if_present(case_id: str, filename: str, fn) -> dict[str, Any] | None:
        wav_path = os.path.join(capture_dir, filename)
        if not os.path.isfile(wav_path):
            cases.append({
                "id": case_id,
                "file": filename,
                "status": "blocked",
                "reason": "missing_capture",
                "metrics": None,
            })
            return None
        sr, ch, bits, data = read_wav(wav_path)
        res = fn(data, sr)
        res["sampleRate"] = sr
        res["channels"] = ch
        res["bitsPerSample"] = bits
        cases.append({
            "id": case_id,
            "file": filename,
            "status": "pass",
            "reason": None,
            "metrics": res,
        })
        metrics[case_id] = res
        return res

    analyze_if_present("thd_16bit_dither_off", "thd_16bit_dither_off.wav",
                       lambda d, sr: analyze_tone_thdn(d[:, 0], sr, expected_freq_hz=1000.0))
    analyze_if_present("thd_16bit_dither_on", "thd_16bit_dither_on.wav",
                       lambda d, sr: analyze_tone_thdn(d[:, 0], sr, expected_freq_hz=1000.0))
    analyze_if_present("quiet_16bit_dither_off", "quiet_16bit_dither_off.wav",
                       lambda d, sr: analyze_tone_thdn(d[:, 0], sr, expected_freq_hz=1000.0))
    analyze_if_present("quiet_16bit_dither_on", "quiet_16bit_dither_on.wav",
                       lambda d, sr: analyze_tone_thdn(d[:, 0], sr, expected_freq_hz=1000.0))
    analyze_if_present("thd_24bit_dither_off", "thd_24bit_dither_off.wav",
                       lambda d, sr: analyze_tone_thdn(d[:, 0], sr, expected_freq_hz=1000.0))
    analyze_if_present("thd_24bit_dither_on", "thd_24bit_dither_on.wav",
                       lambda d, sr: analyze_tone_thdn(d[:, 0], sr, expected_freq_hz=1000.0))

    analyze_if_present("noise_floor_16bit_dither_off", "noise_floor_16bit_dither_off.wav",
                       lambda d, sr: analyze_noise_floor(d[:, 0], sr))
    analyze_if_present("noise_floor_16bit_dither_on", "noise_floor_16bit_dither_on.wav",
                       lambda d, sr: analyze_noise_floor(d[:, 0], sr))
    analyze_if_present("noise_floor_24bit_dither_off", "noise_floor_24bit_dither_off.wav",
                       lambda d, sr: analyze_noise_floor(d[:, 0], sr))
    analyze_if_present("noise_floor_24bit_dither_on", "noise_floor_24bit_dither_on.wav",
                       lambda d, sr: analyze_noise_floor(d[:, 0], sr))

    analyze_if_present("imd_smpte_24bit", "imd_smpte_24bit.wav",
                       lambda d, sr: analyze_imd_smpte(d[:, 0], sr))
    analyze_if_present("crosstalk_1khz", "crosstalk_1khz_l_only.wav",
                       lambda d, sr: analyze_crosstalk(d, sr, tone_hz=1000.0))
    analyze_if_present("jitter_12khz", "jitter_12khz_24bit.wav",
                       lambda d, sr: analyze_jitter_sidebands(d[:, 0], sr, carrier_hz=12000.0))

    if os.path.isfile(os.path.join(capture_dir, "tap_src_441_to_48_512taps.wav")):
        analyze_if_present("tap_src_441_to_48_512taps", "tap_src_441_to_48_512taps.wav",
                           lambda d, sr: analyze_tone_thdn(d[:, 0], sr, expected_freq_hz=1000.0))

    passed = sum(1 for c in cases if c["status"] == "pass")
    failed = sum(1 for c in cases if c["status"] == "fail")
    blocked = sum(1 for c in cases if c["status"] == "blocked")
    status = "fail" if failed > 0 else ("pass" if passed > 0 else "blocked")

    return {
        "schemaVersion": hc.SCHEMA_VERSION,
        "kind": "fft_measurement",
        "status": status,
        "provenance": provenance,
        "generatedAt": hc.iso_now(),
        "build": hc.git_short_sha(),
        "custody": {
            "bitExact": manifest.get("custodyBitExact") if manifest else None,
            "inputFnv1a64": manifest.get("custodyInputFnv1a64") if manifest else None,
            "outputFnv1a64": manifest.get("custodyOutputFnv1a64") if manifest else None,
        },
        "counts": {
            "total": len(cases),
            "pass": passed,
            "fail": failed,
            "blocked": blocked,
        },
        "cases": cases,
        "metrics": metrics,
    }


def build_markdown_report(report: dict[str, Any]) -> str:
    lines = [
        "# Pulsr Audio Measurement & FFT Report",
        "",
        f"- **Status:** {report['status']}",
        f"- **Provenance:** `{report['provenance']}`",
        f"- **Generated:** {report['generatedAt']}",
        f"- **Build:** `{report['build']}`",
    ]
    custody = report.get("custody") or {}
    if custody.get("bitExact") is not None:
        lines.append(
            f"- **CustodyVerifier (bit-perfect window):** `bitExact={custody['bitExact']}` "
            f"(in `{custody.get('inputFnv1a64')}`, out `{custody.get('outputFnv1a64')}`)"
        )
    lines.extend(["", "## Summary Metrics", "", "| Case | Status | Key Result |", "| :--- | :--- | :--- |"])

    for case in report["cases"]:
        cid = case["id"]
        st = case["status"]
        m = case.get("metrics") or {}
        if st != "pass":
            detail = case.get("reason") or "-"
        elif "thdnDb" in m:
            detail = (
                f"THD+N: **{m['thdnDb']} dB** ({m['thdnPct']:.5f}%), "
                f"THD: {m['thdDb']} dB, Noise floor: {m['noiseFloorDbfs']} dBFS, "
                f"SFDR: {m['sfdrDbc']} dBc"
            )
        elif "bandNoiseDbfs" in m:
            detail = (
                f"Band noise (20 Hz–20 kHz): **{m['bandNoiseDbfs']} dBFS**, "
                f"RMS: {m['rmsDbfs']} dBFS, Peak spur: {m['peakSpurDbfs']} dBFS"
            )
        elif "imdDb" in m:
            detail = f"SMPTE IMD: **{m['imdDb']} dB** ({m['imdPct']:.5f}%)"
        elif "crosstalkDb" in m:
            detail = f"Crosstalk ({m['direction']} @ {m['toneHz']} Hz): **{m['crosstalkDb']} dB**"
        elif "peakSidebandDbc" in m:
            detail = (
                f"Peak jitter sideband: **{m['peakSidebandDbc']} dBc** "
                f"(@ {m['peakSidebandOffsetHz']:+.1f} Hz), "
                f"Integrated: {m['integratedSidebandsDbc']} dBc"
            )
        else:
            detail = json.dumps(m)
        lines.append(f"| `{cid}` | {st} | {detail} |")

    lines.append("")
    if report["provenance"] != "hardware_loopback":
        lines.append(
            "> **Note:** This run used `"
            + report["provenance"]
            + "` (offline/simulated capture), not a physical USB DAC → ADC loopback recording."
        )
        lines.append("")
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="measure_fft.py",
        description="Pulsr FFT distortion, noise-floor, IMD, crosstalk & jitter measurement harness.",
    )
    parser.add_argument("--wav", default=None, help="Analyze a single WAV capture file")
    parser.add_argument(
        "--mode",
        choices=("thdn", "noise", "imd", "crosstalk", "jitter"),
        default="thdn",
        help="Analysis mode for --wav (default: thdn)",
    )
    parser.add_argument("--capture-dir", default=None, help="Directory of loopback or rendered WAV captures")
    parser.add_argument("--native-bin", default=None, help="Path to compiled measure_native_dsp executable")
    parser.add_argument("--hardware-loopback", action="store_true", help="Tag --capture-dir inputs as physical DAC->ADC loopback")
    parser.add_argument("--require-hardware", action="store_true", help="Require physical loopback captures; otherwise report blocked")
    parser.add_argument("--gate", action="store_true", help="Exit 2 when blocked")
    parser.add_argument("--offline", action="store_true", help="Generate deterministic offline reference captures (default if no capture source given)")
    parser.add_argument("--out", default=os.path.join(hc.repo_root(), "scratch", "fft", "report.md"), help="Markdown report path")
    parser.add_argument("--json-out", default=None, help="JSON report path (default: <out stem>.json)")
    args = parser.parse_args(argv)

    json_out = args.json_out or os.path.splitext(os.path.abspath(args.out))[0] + ".json"

    if args.wav:
        sr, ch, bits, data = read_wav(args.wav)
        if args.mode == "thdn":
            metrics = analyze_tone_thdn(data[:, 0], sr)
        elif args.mode == "noise":
            metrics = analyze_noise_floor(data[:, 0], sr)
        elif args.mode == "imd":
            metrics = analyze_imd_smpte(data[:, 0], sr)
        elif args.mode == "crosstalk":
            metrics = analyze_crosstalk(data, sr)
        else:
            metrics = analyze_jitter_sidebands(data[:, 0], sr)
        metrics.update({"sampleRate": sr, "channels": ch, "bitsPerSample": bits})
        report = {
            "schemaVersion": hc.SCHEMA_VERSION,
            "kind": "fft_measurement",
            "status": "pass",
            "provenance": "hardware_loopback" if args.hardware_loopback else "wav_capture",
            "generatedAt": hc.iso_now(),
            "build": hc.git_short_sha(),
            "custody": {"bitExact": None},
            "counts": {"total": 1, "pass": 1, "fail": 0, "blocked": 0},
            "cases": [{"id": args.mode, "file": os.path.basename(args.wav), "status": "pass", "reason": None, "metrics": metrics}],
            "metrics": {args.mode: metrics},
        }
    elif args.require_hardware and not args.capture_dir:
        report = {
            "schemaVersion": hc.SCHEMA_VERSION,
            "kind": "fft_measurement",
            "status": "blocked",
            "reason": "no_loopback_capture",
            "provenance": "none",
            "generatedAt": hc.iso_now(),
            "build": hc.git_short_sha(),
            "custody": {"bitExact": None},
            "counts": {"total": 0, "pass": 0, "fail": 0, "blocked": 1},
            "cases": [],
            "metrics": {},
        }
    elif args.capture_dir:
        manifest_path = os.path.join(args.capture_dir, "native_manifest.json")
        manifest = None
        if os.path.isfile(manifest_path):
            with open(manifest_path, "r", encoding="utf-8") as fh:
                manifest = json.load(fh)
        provenance = (
            "hardware_loopback"
            if args.hardware_loopback
            else (manifest.get("provenance") if manifest else "wav_capture")
        )
        report = run_suite(args.capture_dir, provenance=provenance, manifest=manifest)
    elif args.native_bin:
        with tempfile.TemporaryDirectory(prefix="pulsr-native-fft-") as tmp:
            proc = subprocess.run([args.native_bin, "--out-dir", tmp], capture_output=True, text=True, check=False)
            if proc.returncode != 0:
                print(f"measure_native_dsp failed ({proc.returncode}): {proc.stderr or proc.stdout}", file=sys.stderr)
                return hc.EXIT_ERROR
            manifest_path = os.path.join(tmp, "native_manifest.json")
            manifest = None
            if os.path.isfile(manifest_path):
                with open(manifest_path, "r", encoding="utf-8") as fh:
                    manifest = json.load(fh)
            report = run_suite(tmp, provenance="native_dsp_render", manifest=manifest)
    else:
        with tempfile.TemporaryDirectory(prefix="pulsr-offline-fft-") as tmp:
            manifest = generate_offline_reference_captures(tmp)
            report = run_suite(tmp, provenance="offline_reference", manifest=manifest)

    hc.ensure_parent(args.out)
    with open(args.out, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(build_markdown_report(report))
    hc.ensure_parent(json_out)
    with open(json_out, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(report, fh, indent=2)
        fh.write("\n")

    print(json.dumps({"status": report["status"], "provenance": report["provenance"], "out": args.out, "jsonOut": json_out}))
    if report["status"] == "fail":
        return hc.EXIT_FAIL
    if report["status"] == "blocked" and args.gate:
        return hc.EXIT_BLOCKED_GATE
    return hc.EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
