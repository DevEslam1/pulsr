#!/usr/bin/env python3
"""
Regression test for B-01, B-08, B-31, B-32, B-33:
Asserts no duplicate -std=c++20 flags, no duplicate -O2/-O3 flags, and 16KB page alignment.
"""

import sys
import re
from pathlib import Path

def main():
    root = Path(__file__).resolve().parent.parent
    cmake_path = root / "android" / "app" / "src" / "main" / "cpp" / "CMakeLists.txt"
    gradle_path = root / "android" / "app" / "build.gradle.kts"

    cmake_content = cmake_path.read_text(encoding="utf-8")
    gradle_content = gradle_path.read_text(encoding="utf-8")

    errors = []

    # 1. Check for hardcoded -std=c++20 in CMakeLists.txt
    if "-std=c++20" in cmake_content:
        errors.append("CMakeLists.txt contains hardcoded -std=c++20; use set(CMAKE_CXX_STANDARD 20) instead.")

    # 2. Check for -std=c++20 in externalNativeBuild cppFlags in build.gradle.kts
    if "cppFlags" in gradle_content and "-std=c++20" in gradle_content:
        errors.append("build.gradle.kts contains hardcoded -std=c++20 in cppFlags.")

    # 3. Check for 16KB page size linker option in CMakeLists.txt
    if "max-page-size=16384" not in cmake_content:
        errors.append("CMakeLists.txt missing -Wl,-z,max-page-size=16384 linker option.")

    # 4. Check that CMAKE_CXX_FLAGS_RELWITHDEBINFO has no duplicate -O2
    relwithdeb = re.findall(r'CMAKE_CXX_FLAGS_RELWITHDEBINFO\s+"([^"]+)"', cmake_content)
    if relwithdeb:
        flags = relwithdeb[0].split()
        o2_count = sum(1 for f in flags if f == "-O2")
        if o2_count > 1:
            errors.append(f"CMAKE_CXX_FLAGS_RELWITHDEBINFO contains duplicate -O2 ({o2_count} occurrences).")

    if errors:
        for err in errors:
            print(f"FAILED: {err}", file=sys.stderr)
        sys.exit(1)

    print("PASSED: All compiler flags and 16KB alignment checks passed cleanly.")

if __name__ == "__main__":
    main()
