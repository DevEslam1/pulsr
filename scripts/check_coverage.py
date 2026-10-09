#!/usr/bin/env python3
"""Fail when lcov line coverage drops below the floor (a ratchet).

Generated code (drift/freezed/go_router codegen, mockito mocks and the
generated localizations) is excluded from the measurement: it is not
hand-written and cannot be meaningfully tested. Coverage is reported over
hand-written `lib/` sources only.

Floor history (raise as coverage improves; never lower):
  2026-09-16:  3.0  baseline measured ~3.2% over ~36.5k instrumented lines.
  2026-10-04: 35.0  measured 39.5% over ~85.9k instrumented lines after the
                    full suite went green (2,315 tests).
  2026-10-05: 43.0  measured 43.5% over ~88.3k instrumented lines after the
                    feature-test reorganization + toggle matrix (2,770 tests).
  2026-10-09: 77.0  hand-written only (generated excluded); measured 78.0%
                    over ~77.8k instrumented lines after the coverage push
                    (4,863 tests).

Usage: run after `flutter test --coverage`, then `python3 scripts/check_coverage.py`.
"""
import pathlib
import sys

FLOOR = 77.0

GENERATED_SUFFIXES = (".g.dart", ".freezed.dart", ".gr.dart", ".mocks.dart")
GENERATED_PREFIXES = ("lib/l10n/generated/",)


def is_generated(source: str) -> bool:
    normalized = source.replace("\\", "/")
    if normalized.startswith(GENERATED_PREFIXES):
        return True
    return normalized.endswith(GENERATED_SUFFIXES)


def main() -> int:
    path = pathlib.Path("coverage/lcov.info")
    if not path.exists():
        print("coverage/lcov.info not found; run `flutter test --coverage` first.")
        return 1

    lines_found = 0
    lines_hit = 0
    raw_found = 0
    raw_hit = 0
    current_generated = False

    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith("SF:"):
            current_generated = is_generated(line[3:].strip())
        elif line.startswith("LF:"):
            value = int(line[3:])
            raw_found += value
            if not current_generated:
                lines_found += value
        elif line.startswith("LH:"):
            value = int(line[3:])
            raw_hit += value
            if not current_generated:
                lines_hit += value

    if lines_found == 0:
        print("No LF records in lcov; cannot compute coverage.")
        return 1

    pct = 100.0 * lines_hit / lines_found
    raw_pct = 100.0 * raw_hit / raw_found if raw_found else 0.0
    print(
        f"Hand-written line coverage: {pct:.2f}% "
        f"(floor {FLOOR:.1f}%, {lines_hit}/{lines_found}) | "
        f"raw incl. generated: {raw_pct:.2f}% ({raw_hit}/{raw_found})"
    )
    return 0 if pct >= FLOOR else 1


if __name__ == "__main__":
    sys.exit(main())
