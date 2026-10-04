#!/usr/bin/env python3
"""Fail when lcov line coverage drops below the floor (a ratchet).

Floor history (raise as coverage improves; never lower):
  2026-09-16: 3.0   baseline measured ~3.2% over ~36.5k instrumented lines.
  2026-10-04: 35.0  measured 39.5% over ~85.9k instrumented lines after the
                    full suite went green (2,315 tests).

Usage: run after `flutter test --coverage`, then `python3 scripts/check_coverage.py`.
"""
import pathlib
import sys

FLOOR = 35.0

path = pathlib.Path("coverage/lcov.info")
if not path.exists():
    print("coverage/lcov.info not found; run `flutter test --coverage` first.")
    sys.exit(1)

lines_found = 0
lines_hit = 0
for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
    if line.startswith("LF:"):
        lines_found += int(line[3:])
    elif line.startswith("LH:"):
        lines_hit += int(line[3:])

if lines_found == 0:
    print("No LF records in lcov; cannot compute coverage.")
    sys.exit(1)

pct = 100.0 * lines_hit / lines_found
print(f"Line coverage: {pct:.2f}% (floor {FLOOR:.1f}%, {lines_hit}/{lines_found})")
sys.exit(0 if pct >= FLOOR else 1)