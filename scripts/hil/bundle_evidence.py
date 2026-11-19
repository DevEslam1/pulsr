#!/usr/bin/env python3
"""bundle_evidence.py - deterministic evidence zip for USB HIL runs.

Packs result JSONs and logs into dist/usb-evidence/<build>-<timestamp>.zip with
a manifest.json holding the sha256 of every entry.  Files whose names look like
they contain device serial numbers or PII (*serial*, *pii*) are refused and
listed in the manifest as excluded.

Determinism: entries are sorted, zip metadata is fixed, so the same inputs and
--timestamp produce byte-identical archives.
"""

from __future__ import annotations

import argparse
import datetime as _dt
import hashlib
import json
import os
import shutil
import sys
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import hil_common as hc

FIXED_ZIP_TIME = (1980, 1, 1, 0, 0, 0)
SENSITIVE_MARKERS = ("serial", "pii")


def arcname_for(path):
    root = hc.repo_root()
    absolute = os.path.abspath(path)
    try:
        relative = os.path.relpath(absolute, root)
    except ValueError:
        # Different Windows drive than the repo: keep it under a hashed folder.
        relative = ""
    if not relative or relative.startswith(".."):
        relative = os.path.join(
            "external", hc.token_hash(os.path.dirname(absolute)), os.path.basename(absolute)
        )
    return relative.replace("\\", "/")


def is_sensitive(name):
    lowered = name.lower()
    return any(marker in lowered for marker in SENSITIVE_MARKERS)


def collect_files(inputs, out_dir):
    files, excluded, missing = [], [], []
    seen = set()

    def add(path):
        absolute = os.path.abspath(path)
        if absolute in seen:
            return
        seen.add(absolute)
        base = os.path.basename(absolute)
        if is_sensitive(base):
            excluded.append({"file": base, "reason": "sensitive_name"})
            return
        if os.path.islink(absolute):
            excluded.append({"file": base, "reason": "symlink"})
            return
        try:
            if os.path.commonpath([os.path.realpath(absolute), os.path.realpath(out_dir)]) == os.path.realpath(out_dir):
                return
        except ValueError:
            pass
        if not os.path.isfile(absolute):
            return
        files.append(absolute)

    for entry in inputs:
        if not os.path.exists(entry):
            missing.append(entry)
            continue
        if os.path.isdir(entry):
            for root, dirs, names in os.walk(entry):
                dirs.sort()
                for name in sorted(names):
                    add(os.path.join(root, name))
        else:
            add(entry)

    used = {}
    planned = []
    for path in sorted(files, key=arcname_for):
        arcname = arcname_for(path)
        if arcname in used:
            arcname = "duplicate/%s/%s" % (hc.token_hash(path), os.path.basename(path))
        used[arcname] = path
        planned.append({"path": path, "arcname": arcname})
    return planned, excluded, missing


def parse_timestamp(value):
    if not value:
        now = _dt.datetime.now(_dt.timezone.utc).replace(microsecond=0)
        return now
    text = value.strip()
    if len(text) == 16 and text.endswith("Z") and "T" in text:
        try:
            return _dt.datetime.strptime(text, "%Y%m%dT%H%M%SZ").replace(tzinfo=_dt.timezone.utc)
        except ValueError:
            pass
    try:
        parsed = hc.parse_iso(text)
    except ValueError:
        raise hc.HilError("--timestamp is not ISO-8601: %s" % value)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=_dt.timezone.utc)
    return parsed.astimezone(_dt.timezone.utc).replace(microsecond=0)


def write_entry(zf, arcname, source_path):
    info = zipfile.ZipInfo(arcname, date_time=FIXED_ZIP_TIME)
    info.compress_type = zipfile.ZIP_DEFLATED
    info.external_attr = 0o644 << 16
    info.create_system = 3
    info.flag_bits |= 0x800
    with open(source_path, "rb") as src, zf.open(info, "w") as dest:
        shutil.copyfileobj(src, dest, 1024 * 1024)


def main(argv=None):
    parser = argparse.ArgumentParser(
        prog="bundle_evidence.py",
        description="Assemble a deterministic USB HIL evidence zip with a sha256 manifest.",
    )
    parser.add_argument("--inputs", nargs="+", default=[os.path.join(hc.repo_root(), "scratch", "hil")],
                        help="files or directories to bundle (default: scratch/hil)")
    parser.add_argument("--out-dir", default=os.path.join(hc.repo_root(), "dist", "usb-evidence"),
                        help="output directory (default: %(default)s)")
    parser.add_argument("--build", default=None, help="build label (default: git short sha)")
    parser.add_argument("--timestamp", default=None,
                        help="ISO-8601 or YYYYMMDDTHHMMSSZ stamp; fixes the archive name and metadata")
    parser.add_argument("--report", default=None, help="optional path to write the manifest as JSON")
    args = parser.parse_args(argv)

    build = args.build or hc.git_short_sha()
    safe_build = "".join(ch if ch.isalnum() or ch in "._-" else "-" for ch in build) or "unknown"
    moment = parse_timestamp(args.timestamp)
    stamp = moment.strftime("%Y%m%dT%H%M%SZ")
    iso_stamp = moment.strftime("%Y-%m-%dT%H:%M:%S.000Z")

    planned, excluded, missing = collect_files(args.inputs, args.out_dir)

    manifest_files = []
    for item in planned:
        manifest_files.append(
            {
                "path": item["arcname"],
                "bytes": os.path.getsize(item["path"]),
                "sha256": hc.sha256_file(item["path"]),
            }
        )
    manifest = {
        "schemaVersion": hc.SCHEMA_VERSION,
        "tool": "scripts/hil/bundle_evidence.py",
        "build": build,
        "timestamp": iso_stamp,
        "files": manifest_files,
        "excluded": excluded,
        "missingInputs": [os.path.basename(path) for path in missing],
    }

    os.makedirs(args.out_dir, exist_ok=True)
    zip_path = os.path.join(args.out_dir, "%s-%s.zip" % (safe_build, stamp))
    temp_path = zip_path + ".tmp"
    manifest_bytes = (json.dumps(manifest, indent=2, ensure_ascii=True) + "\n").encode("utf-8")

    try:
        with zipfile.ZipFile(temp_path, "w", zipfile.ZIP_DEFLATED) as zf:
            info = zipfile.ZipInfo("manifest.json", date_time=FIXED_ZIP_TIME)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            info.create_system = 3
            info.flag_bits |= 0x800
            zf.writestr(info, manifest_bytes)
            for item in planned:
                write_entry(zf, item["arcname"], item["path"])
        os.replace(temp_path, zip_path)
    except OSError as exc:
        raise hc.HilError("cannot write %s: %s" % (zip_path, exc))
    finally:
        if os.path.exists(temp_path):
            os.remove(temp_path)

    if args.report:
        hc.ensure_parent(args.report)
        with open(args.report, "w", encoding="utf-8", newline="\n") as fh:
            json.dump(manifest, fh, indent=2, ensure_ascii=True)
            fh.write("\n")

    digest = hc.sha256_file(zip_path)
    print(
        "bundle: %d file(s), %d excluded -> %s (sha256 %s)"
        % (len(planned), len(excluded), zip_path, digest)
    )
    if missing:
        print("warning: %d input path(s) did not exist" % len(missing), file=sys.stderr)
    if not planned:
        print("warning: no evidence files matched; archive contains only manifest.json", file=sys.stderr)
    print(os.path.abspath(zip_path))
    return hc.EXIT_OK


if __name__ == "__main__":
    sys.exit(hc.run_main(main))
