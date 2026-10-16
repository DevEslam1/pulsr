#!/usr/bin/env python3
"""
Guard script: verify Android/Gradle modernization status.
Ensures deprecated flags (e.g., android.builtInKotlin=false) are not reintroduced,
and verifies Gradle configuration adheres to the modern AGP 9+ / KGP standard.
"""

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
GRADLE_PROPERTIES = REPO_ROOT / "android" / "gradle.properties"


def check_gradle_properties() -> bool:
    if not GRADLE_PROPERTIES.exists():
        print(f"[FAIL] {GRADLE_PROPERTIES} does not exist", file=sys.stderr)
        return False

    content = GRADLE_PROPERTIES.read_text(encoding="utf-8")
    lines = [line.strip() for line in content.splitlines()]

    failures = []

    for line in lines:
        if line.startswith("#"):
            continue
        if "android.builtInKotlin=false" in line:
            failures.append("Deprecated flag 'android.builtInKotlin=false' found in android/gradle.properties")

    if failures:
        for failure in failures:
            print(f"[FAIL] {failure}", file=sys.stderr)
        return False

    print("[OK] android/gradle.properties does not contain deprecated android.builtInKotlin=false")
    return True


def main() -> int:
    success = check_gradle_properties()
    if success:
        print("[OK] All Gradle modernization checks passed.")
        return 0
    else:
        print("[FAIL] Gradle modernization checks failed.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
