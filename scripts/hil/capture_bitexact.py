#!/usr/bin/env python3
"""capture_bitexact.py - bit-exact capture verification for USB DAC output.

Compares a captured WAV (or raw PCM) against the source file byte for byte.
16/24/32-bit PCM WAV is parsed from the RIFF chunks; the comparison is over the
`data` payload only (headers legitimately differ between capture tools).

There is no dithering tolerance: --allow-ulp accepts 0 only.  If the capture is
missing the result is blocked/no_capture - a missing capture is not a pass.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import hil_common as hc

SUPPORTED_BITS = (16, 24, 32)


def sha256_payload(path, offset, size):
    digest = hashlib.sha256()
    remaining = size
    with open(path, "rb") as fh:
        fh.seek(offset)
        while remaining > 0:
            chunk = fh.read(min(1024 * 1024, remaining))
            if not chunk:
                break
            digest.update(chunk)
            remaining -= len(chunk)
    return digest.hexdigest()


def describe(path, raw, bits, channels, rate):
    """Return (format dict, payload offset, payload size)."""
    if raw:
        size = os.path.getsize(path)
        block_align = (bits // 8) * channels
        return (
            {
                "container": "raw",
                "audioFormat": None,
                "bits": bits,
                "channels": channels,
                "rate": rate,
                "blockAlign": block_align,
                "dataOffset": 0,
                "dataSize": size,
                "frames": size // block_align if block_align else None,
                "partialFrame": bool(block_align and size % block_align),
            },
            0,
            size,
        )
    info = hc.scan_wav(path)
    frames = info["dataSize"] // info["blockAlign"] if info.get("blockAlign") else None
    info["frames"] = frames
    info["partialFrame"] = bool(info.get("blockAlign") and info["dataSize"] % info["blockAlign"])
    return info, info["dataOffset"], info["dataSize"]


def main(argv=None):
    parser = argparse.ArgumentParser(
        prog="capture_bitexact.py",
        description="Byte-exact comparison of a captured USB DAC stream against its source.",
    )
    hc.add_output_args(parser, "bitexact", with_dry_run=False)
    parser.add_argument("--source", required=False, help="source WAV/raw PCM file")
    parser.add_argument("--capture", required=False, help="captured WAV/raw PCM file")
    parser.add_argument("--raw", action="store_true", help="treat both files as headerless PCM")
    parser.add_argument("--bits", type=int, default=None, help="raw PCM bit depth (16/24/32)")
    parser.add_argument("--channels", type=int, default=None, help="raw PCM channel count")
    parser.add_argument("--rate", type=int, default=None, help="raw PCM sample rate")
    parser.add_argument("--allow-ulp", type=int, default=0,
                        help="dithering tolerance in ULP; only 0 (bit-exact) is supported")
    args = parser.parse_args(argv)

    if args.allow_ulp != 0:
        raise hc.HilError("--allow-ulp %d is not supported: this gate is bit-exact by design" % args.allow_ulp)
    if args.raw and not (args.bits and args.channels and args.rate):
        raise hc.HilError("--raw requires --bits, --channels and --rate")
    if args.raw and args.bits not in SUPPORTED_BITS:
        raise hc.HilError("--bits must be one of %s" % ", ".join(str(b) for b in SUPPORTED_BITS))

    parameters = {
        "allowUlp": args.allow_ulp,
        "raw": bool(args.raw),
        "source": os.path.basename(args.source) if args.source else None,
        "capture": os.path.basename(args.capture) if args.capture else None,
    }

    def blocked(reason, detail=None):
        case = {"id": "payload_bitexact", "status": "blocked", "reason": reason, "detail": detail}
        return hc.blocked_result(
            "bitexact", reason, detail=detail, parameters=parameters, cases=[case]
        )

    if not args.source:
        return hc.finish(blocked("no_source", "--source was not supplied"), args.out, args.gate)
    if not os.path.isfile(args.source):
        return hc.finish(blocked("no_source", "source file does not exist"), args.out, args.gate)
    if not args.capture:
        return hc.finish(blocked("no_capture", "--capture was not supplied"), args.out, args.gate)
    if not os.path.isfile(args.capture):
        return hc.finish(blocked("no_capture", "capture file does not exist"), args.out, args.gate)

    try:
        source_fmt, source_offset, source_size = describe(
            args.source, args.raw, args.bits, args.channels, args.rate
        )
        capture_fmt, capture_offset, capture_size = describe(
            args.capture, args.raw, args.bits, args.channels, args.rate
        )
    except hc.HilError as exc:
        return hc.finish(blocked("unreadable_audio", str(exc)[:300]), args.out, args.gate)

    keys = ("container", "audioFormat", "bits", "channels", "rate", "blockAlign")
    format_mismatch = [key for key in keys if source_fmt.get(key) != capture_fmt.get(key)]

    identical = source_size == capture_size
    diff_offset = hc.first_diff(
        args.source, args.capture, source_offset, capture_offset, min(source_size, capture_size)
    )

    cases = [
        {
            "id": "format_match",
            "status": "fail" if format_mismatch else "pass",
            "reason": "format_mismatch" if format_mismatch else None,
            "detail": "mismatched fields: %s" % ", ".join(format_mismatch) if format_mismatch else None,
            "source": {key: source_fmt.get(key) for key in keys},
            "capture": {key: capture_fmt.get(key) for key in keys},
        },
        {
            "id": "payload_bitexact",
            "status": "pass" if (identical and diff_offset is None) else "fail",
            "reason": None if (identical and diff_offset is None) else "byte_mismatch",
            "sha256": {
                "source": sha256_payload(args.source, source_offset, source_size),
                "capture": sha256_payload(args.capture, capture_offset, capture_size),
            },
            "comparedBytes": min(source_size, capture_size),
            "sourceBytes": source_size,
            "captureBytes": capture_size,
            "lengthDelta": capture_size - source_size,
            "firstDiffOffset": diff_offset if not identical or diff_offset is not None else None,
            "frames": {
                "source": source_fmt.get("frames"),
                "capture": capture_fmt.get("frames"),
            },
            "bitDepthSupported": source_fmt.get("bits") in SUPPORTED_BITS,
            "partialFrame": bool(source_fmt.get("partialFrame") or capture_fmt.get("partialFrame")),
        },
    ]

    failed = any(case["status"] == "fail" for case in cases)
    status = "fail" if failed else "pass"
    detail = None
    if failed:
        bad = next(case for case in cases if case["status"] == "fail")
        if bad["id"] == "format_match":
            detail = "capture format differs from source"
        else:
            detail = "first differing byte at offset %s (source %d bytes, capture %d bytes)" % (
                bad["firstDiffOffset"], source_size, capture_size)
    result = hc.make_result(
        "bitexact", status, reason="bit_mismatch" if failed else None,
        parameters=parameters, cases=cases,
        blockers=[hc.blocker("bit_mismatch", detail)] if failed else [],
    )
    return hc.finish(result, args.out, args.gate)


if __name__ == "__main__":
    sys.exit(hc.run_main(main))
