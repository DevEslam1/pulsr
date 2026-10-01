#!/usr/bin/env python3
"""
AutoEQ dataset generator for Pulsr.

Fetches real parametric EQ corrections from the upstream AutoEQ repository
(https://github.com/jaakkopasanen/AutoEq) and converts them into the unified
Pulsr `headphone_profiles.json` schema understood by
`lib/domain/models/headphone_profile.dart`:

    {
      "id": "autoeq_oratory1990_over-ear_sony_wh-1000xm5",
      "name": "Sony WH-1000XM5",
      "brand": "Sony",
      "model": "WH-1000XM5",
      "category": "Over-Ear",
      "gains": [...10 ISO-band gains derived from the filters...],
      "bassBoost": 0.0,
      "preampGain": -6.2,
      "filters": [
        {"frequency": 105.0, "gain": 5.5, "q": 0.70, "type": 1},
        ...
      ],
      "source": "AutoEQ/oratory1990"
    }

The `filters` array carries the genuine AutoEQ parametric filters (freq/Q/gain/
type) so the native 64-band parametric EQ can reproduce the exact correction
instead of a flattened 10-band approximation. `gains` is retained so legacy
consumers and the EQ graph still have a coarse view.

Usage
-----
    py scripts/generate_autoeq_dataset.py --curated
        Fetch a hand-picked set of popular headphone models (default).

    py scripts/generate_autoeq_dataset.py --all --sources oratory1990 crinacle
        Fetch every measurement from the given sources. Slow (thousands of
        HTTP requests) but produces the full offline database.

    py scripts/generate_autoeq_dataset.py --sources oratory1990 --limit 300
        Fetch at most N profiles per (source, category, target).

By default the merged result is written to
`assets/eq_profiles/headphone_profiles.json`, preserving any entries that are
not replaced (hand-authored target curves). Use `--out` to pick another path.

Network access is required. This is a build-time tool; the shipped app remains
fully offline.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, field

GITHUB_API = "https://api.github.com/repos/jaakkopasanen/AutoEq"
RAW_BASE = "https://raw.githubusercontent.com/jaakkopasanen/AutoEq/master"

# Filter type ordinals must match `EqFilterType` in
# lib/domain/models/headphone_profile.dart and `FilterType` in
# android/app/src/main/cpp/DspParams.h.
TYPE_PEAKING = 0
TYPE_LOW_SHELF = 1
TYPE_HIGH_SHELF = 2
TYPE_LOW_PASS = 3
TYPE_HIGH_PASS = 4

_TYPE_CODES = {
    "PK": TYPE_PEAKING,
    "PEAKING": TYPE_PEAKING,
    "LS": TYPE_LOW_SHELF,
    "LOWSHELF": TYPE_LOW_SHELF,
    "LSC": TYPE_LOW_SHELF,
    "HS": TYPE_HIGH_SHELF,
    "HIGHSHELF": TYPE_HIGH_SHELF,
    "HSC": TYPE_HIGH_SHELF,
    "LP": TYPE_LOW_PASS,
    "LOWPASS": TYPE_LOW_PASS,
    "HP": TYPE_HIGH_PASS,
    "HIGHPASS": TYPE_HIGH_PASS,
}

# ISO 10-band centers, mirrored from EqPreset.centerFrequencies.
ISO_BANDS = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]

# A curated list of widely-owned models. Matching is normalized substring
# against "<brand> <model>" so a single entry can cover several measurements
# (e.g. "WH-1000XM5" matches the ANC-on/off variants). Order is preference.
CURATED = [
    "Sony WH-1000XM5",
    "Sony WH-1000XM4",
    "Sony WH-1000XM3",
    "Sony WF-1000XM5",
    "Sony WF-1000XM4",
    "Apple AirPods Pro 2",
    "Apple AirPods Pro",
    "Apple AirPods Max",
    "Apple AirPods 3",
    "Apple EarPods",
    "Sennheiser HD 600",
    "Sennheiser HD 650",
    "Sennheiser HD 660S",
    "Sennheiser HD 800 S",
    "Sennheiser Momentum 4",
    "Sennheiser IE 200",
    "Sennheiser IE 600",
    "Beyerdynamic DT 770 Pro",
    "Beyerdynamic DT 990 Pro",
    "Beyerdynamic DT 1990 Pro",
    "Audio-Technica ATH-M50x",
    "Audio-Technica ATH-M40x",
    "Bose QuietComfort 45",
    "Bose QuietComfort Ultra",
    "Anker Soundcore Space Q45",
    "Anker Soundcore Space One",
    "Anker Soundcore Life Q30",
    "Samsung Galaxy Buds 2 Pro",
    "Samsung Galaxy Buds 3 Pro",
    "Moondrop Chu II",
    "Moondrop Aria",
    "Moondrop Kato",
    "Moondrop Blessing 2",
    "7Hz Salnotes Zero",
    "7Hz Timeless",
    "Shure SE215",
    "Shure SE846",
    "JBL Tune 510BT",
    "JBL Tune 710BT",
    "AKG K371",
    "AKG K702",
    "AKG K712",
    "HiFiMan Sundara",
    "HiFiMan HE400se",
    "Philips Fidelio X2HR",
    "Philips SHP9500",
    "Koss KSC75",
    "Koss Porta Pro",
    "Grado SR60e",
    "Dan Clark Audio Aeon 2",
]

# Category inference from the AutoEQ directory segment.
_CATEGORY_MAP = {
    "over-ear": "Over-Ear",
    "on-ear": "On-Ear",
    "in-ear": "In-Ear",
    "earbud": "Earbuds",
    "earbuds": "Earbuds",
    "tws": "TWS Earbuds",
    "true wireless": "TWS Earbuds",
}


@dataclass
class Filter:
    frequency: float
    gain: float
    q: float
    type: int


@dataclass
class Profile:
    id: str
    name: str
    brand: str
    model: str
    category: str
    gains: list[float]
    preamp_gain: float
    filters: list[Filter] = field(default_factory=list)
    source: str = "AutoEQ"

    def to_json(self) -> dict:
        return {
            "id": self.id,
            "name": self.name,
            "brand": self.brand,
            "model": self.model,
            "category": self.category,
            "gains": [round(g, 2) for g in self.gains],
            "bassBoost": 0.0,
            "preampGain": round(self.preamp_gain, 2),
            "filters": [
                {
                    "frequency": round(f.frequency, 2),
                    "gain": round(f.gain, 2),
                    "q": round(f.q, 3),
                    "type": f.type,
                }
                for f in self.filters
            ],
            "source": self.source,
        }


def _http_get(url: str, retries: int = 3) -> bytes:
    headers = {"User-Agent": "pulsr-autoeq-generator"}
    token = os.environ.get("GITHUB_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(req, timeout=30) as resp:
                return resp.read()
        except urllib.error.HTTPError as e:
            if e.code in (403, 429) and attempt < retries - 1:
                # Rate-limited: back off.
                time.sleep(5 * (attempt + 1))
                continue
            raise
        except (urllib.error.URLError, TimeoutError):
            if attempt < retries - 1:
                time.sleep(2 * (attempt + 1))
                continue
            raise
    raise RuntimeError(f"failed to fetch {url}")


def list_parametric_eq_paths(source: str) -> list[str]:
    """Return every ParametricEQ.txt path under results/<source>.

    Enumerates the category subtrees (earbud/in-ear/over-ear/...) via the
    contents API, then walks each category's git subtree recursively. The whole
    repository tree is far too large for the recursive git-tree API (GitHub
    truncates it), but individual category subtrees are small and complete.
    """
    contents = json.loads(
        _http_get(f"{GITHUB_API}/contents/results/{source}").decode()
    )
    paths: list[str] = []
    for entry in contents:
        if entry.get("type") != "dir":
            continue
        subtree = json.loads(
            _http_get(f"{GITHUB_API}/git/trees/{entry['sha']}?recursive=1").decode()
        )
        prefix = f"results/{source}/{entry['name']}/"
        for node in subtree.get("tree", []):
            if node.get("type") != "blob":
                continue
            path = node.get("path", "")
            if path.endswith("ParametricEQ.txt"):
                paths.append(prefix + path)
    return paths


_FILTER_RE = re.compile(
    r"Filter\s+\d+:\s+(ON|OFF)\s+(\w+)\s+Fc\s+([\d.]+)\s+Hz"
    r"(?:\s+Gain\s+(-?[\d.]+)\s+dB)?\s+Q\s+([\d.]+)",
    re.IGNORECASE,
)
_PREAMP_RE = re.compile(r"Preamp:\s+(-?[\d.]+)\s+dB", re.IGNORECASE)


def parse_parametric_eq(text: str) -> tuple[float, list[Filter]]:
    """Parse an AutoEQ ParametricEQ.txt into (preampDb, filters)."""
    preamp = 0.0
    m = _PREAMP_RE.search(text)
    if m:
        preamp = float(m.group(1))
    filters: list[Filter] = []
    for fm in _FILTER_RE.finditer(text):
        enabled, type_code, fc, gain, q = fm.groups()
        if enabled.upper() != "ON":
            continue
        ftype = _TYPE_CODES.get(type_code.upper())
        if ftype is None:
            continue
        filters.append(
            Filter(
                frequency=float(fc),
                gain=float(gain) if gain is not None else 0.0,
                q=float(q),
                type=ftype,
            )
        )
    return preamp, filters


def _biquad_magnitude(f: Filter, freq: float, sample_rate: float = 48000.0) -> float:
    """Magnitude of a single RBJ biquad at `freq` (curve-evaluation only)."""
    if f.frequency <= 0:
        return 1.0
    a = 1.0 if abs(f.gain) < 1e-9 else 10 ** (f.gain / 40.0)
    w0 = 2 * math.pi * f.frequency / sample_rate
    w = 2 * math.pi * freq / sample_rate
    if w0 <= 0 or w0 >= math.pi:
        return 1.0
    cosw0, sinw0 = math.cos(w0), math.sin(w0)

    if f.type == TYPE_LOW_SHELF:
        alpha = sinw0 / 2 * math.sqrt((a + 1 / a) * (1 / max(f.q, 0.1) - 1) + 2)
        b0 = a * ((a + 1) - (a - 1) * cosw0 + 2 * math.sqrt(a) * alpha)
        b1 = 2 * a * ((a - 1) - (a + 1) * cosw0)
        b2 = a * ((a + 1) - (a - 1) * cosw0 - 2 * math.sqrt(a) * alpha)
        a0 = (a + 1) + (a - 1) * cosw0 + 2 * math.sqrt(a) * alpha
        a1 = -2 * ((a - 1) + (a + 1) * cosw0)
        a2 = (a + 1) + (a - 1) * cosw0 - 2 * math.sqrt(a) * alpha
    elif f.type == TYPE_HIGH_SHELF:
        alpha = sinw0 / 2 * math.sqrt((a + 1 / a) * (1 / max(f.q, 0.1) - 1) + 2)
        b0 = a * ((a + 1) + (a - 1) * cosw0 + 2 * math.sqrt(a) * alpha)
        b1 = -2 * a * ((a - 1) + (a + 1) * cosw0)
        b2 = a * ((a + 1) + (a - 1) * cosw0 - 2 * math.sqrt(a) * alpha)
        a0 = (a + 1) - (a - 1) * cosw0 + 2 * math.sqrt(a) * alpha
        a1 = 2 * ((a - 1) - (a + 1) * cosw0)
        a2 = (a + 1) - (a - 1) * cosw0 - 2 * math.sqrt(a) * alpha
    elif f.type in (TYPE_LOW_PASS, TYPE_HIGH_PASS):
        alpha = sinw0 / (2 * max(f.q, 0.1))
        if f.type == TYPE_LOW_PASS:
            b0, b1, b2 = (1 - cosw0) / 2, 1 - cosw0, (1 - cosw0) / 2
        else:
            b0, b1, b2 = (1 + cosw0) / 2, -(1 + cosw0), (1 + cosw0) / 2
        a0, a1, a2 = 1 + alpha, -2 * cosw0, 1 - alpha
    else:  # peaking
        alpha = sinw0 / (2 * max(f.q, 0.1))
        b0, b1, b2 = 1 + alpha * a, -2 * cosw0, 1 - alpha * a
        a0, a1, a2 = 1 + alpha / a, -2 * cosw0, 1 - alpha / a

    cosw, cos2w = math.cos(w), math.cos(2 * w)
    num2 = b0 * b0 + b1 * b1 + b2 * b2 + 2 * (b0 * b1 + b1 * b2) * cosw + 2 * b0 * b2 * cos2w
    den2 = a0 * a0 + a1 * a1 + a2 * a2 + 2 * (a0 * a1 + a1 * a2) * cosw + 2 * a0 * a2 * cos2w
    if den2 <= 0:
        return 1.0
    return math.sqrt(max(num2, 0) / den2)


def composite_gain_at(filters: list[Filter], freq: float) -> float:
    linear = 1.0
    for f in filters:
        linear *= _biquad_magnitude(f, freq)
    if linear <= 0:
        return 0.0
    return 20 * math.log10(linear)


def gains_from_filters(filters: list[Filter]) -> list[float]:
    return [round(composite_gain_at(filters, c), 2) for c in ISO_BANDS]


def brand_model_from_name(full_name: str) -> tuple[str, str]:
    """Best-effort brand/model split from an AutoEQ directory name."""
    name = full_name.strip()
    # Strip trailing measurement qualifiers: "(ANC on)", "(wired, passive)"...
    clean = re.sub(r"\s*\([^)]*\)\s*$", "", name).strip()
    parts = clean.split(" ", 1)
    if len(parts) == 2:
        return parts[0], parts[1]
    return clean, clean


def slugify(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", value.lower()).strip("_")


def category_from_path(path: str) -> str:
    segments = path.split("/")
    # results/<source>/<category>/<device>/<device> ParametricEQ.txt
    for seg in segments[2:]:
        key = seg.lower()
        if key in _CATEGORY_MAP:
            return _CATEGORY_MAP[key]
    # Fall back on keyword sniffing of the device folder.
    device = segments[-2].lower() if len(segments) >= 2 else ""
    if "in-ear" in device or " iem" in device:
        return "In-Ear"
    return "Over-Ear"


def device_from_path(path: str) -> str:
    """The device directory name (parent of the ParametricEQ.txt file)."""
    segments = path.split("/")
    return segments[-2] if len(segments) >= 2 else segments[-1]


def build_profile(path: str, source: str) -> Profile | None:
    try:
        text = _http_get(f"{RAW_BASE}/{urllib.parse.quote(path)}").decode(
            "utf-8", errors="replace"
        )
    except Exception as e:  # noqa: BLE001
        print(f"  ! skip {path}: {e}", file=sys.stderr)
        return None
    preamp, filters = parse_parametric_eq(text)
    if not filters:
        return None
    device = device_from_path(path)
    brand, model = brand_model_from_name(device)
    category = category_from_path(path)
    gains = gains_from_filters(filters)
    return Profile(
        id=f"autoeq_{slugify(source)}_{slugify(category)}_{slugify(brand)}_{slugify(model)}",
        name=re.sub(r"\s*\([^)]*\)\s*$", "", device).strip(),
        brand=brand,
        model=model,
        category=category,
        gains=gains,
        preamp_gain=preamp,
        filters=filters,
        source=f"AutoEQ/{source}",
    )


def select_curated(paths: list[str]) -> list[str]:
    """Pick, for each curated device, the shortest-matching plausible path."""
    chosen: dict[str, str] = {}
    for target in CURATED:
        norm_target = re.sub(r"[^a-z0-9]", "", target.lower())
        best: str | None = None
        best_key: tuple[int, int] | None = None
        for path in paths:
            device = path.split("/")[-2]
            norm_device = re.sub(r"[^a-z0-9]", "", device.lower())
            if norm_target and norm_target in norm_device:
                # Prefer the plainest (shortest) directory name.
                key = (len(device), path.count("/"))
                if best_key is None or key < best_key:
                    best, best_key = path, key
        if best:
            chosen[target] = best
        else:
            print(f"  . no match for curated '{target}'", file=sys.stderr)
    return list(chosen.values())


def load_existing(path: str) -> list[dict]:
    if not os.path.exists(path):
        return []
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
        return data if isinstance(data, list) else []
    except Exception:  # noqa: BLE001
        return []


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate the Pulsr AutoEQ dataset.")
    parser.add_argument("--all", action="store_true", help="fetch every measurement")
    parser.add_argument("--curated", action="store_true", help="fetch the curated set (default)")
    parser.add_argument(
        "--sources",
        nargs="+",
        default=["oratory1990", "crinacle"],
        help="AutoEQ measurement sources to pull from",
    )
    parser.add_argument("--limit", type=int, default=0, help="max profiles per source (0 = unlimited)")
    parser.add_argument(
        "--out",
        default=os.path.join("assets", "eq_profiles", "headphone_profiles.json"),
        help="output JSON path",
    )
    parser.add_argument(
        "--no-merge",
        action="store_true",
        help="overwrite instead of preserving existing non-AutoEQ entries",
    )
    args = parser.parse_args()

    if not args.all:
        args.curated = True

    all_paths: list[str] = []
    for source in args.sources:
        print(f"Listing {source} ...")
        try:
            paths = list_parametric_eq_paths(source)
        except Exception as e:  # noqa: BLE001
            print(f"  ! failed to list {source}: {e}", file=sys.stderr)
            continue
        print(f"  found {len(paths)} ParametricEQ.txt files")
        if args.limit:
            paths = paths[: args.limit]
        all_paths.extend((source, p) for p in paths)

    if args.curated and not args.all:
        # Curate only within the first source (oratory1990 preferred).
        primary = [p for (s, p) in all_paths if s == args.sources[0]]
        selected = select_curated(primary)
        all_paths = [(args.sources[0], p) for p in selected]

    profiles: list[Profile] = []
    seen_ids: set[str] = set()
    for i, (source, path) in enumerate(all_paths, 1):
        print(f"[{i}/{len(all_paths)}] {path}")
        prof = build_profile(path, source)
        if prof is None:
            continue
        if prof.id in seen_ids:
            continue
        seen_ids.add(prof.id)
        profiles.append(prof)

    profiles.sort(key=lambda p: (p.brand.lower(), p.model.lower()))

    if args.no_merge:
        merged = [p.to_json() for p in profiles]
    else:
        existing = load_existing(args.out)
        preserved = [
            e for e in existing
            if not str(e.get("id", "")).startswith("autoeq_")
        ]
        merged = preserved + [p.to_json() for p in profiles]

    os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as fh:
        json.dump(merged, fh, indent=2, ensure_ascii=False)
        fh.write("\n")

    print(f"\nWrote {len(merged)} profiles ({len(profiles)} AutoEQ) to {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
