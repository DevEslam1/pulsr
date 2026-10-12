#!/usr/bin/env python3
"""
CI Guard: CMake DSP source list vs CLAUDE.md §4.6 consistency checker.

Ensures every DSP source file compiled in `android/app/src/main/cpp/CMakeLists.txt`
is explicitly documented in `CLAUDE.md` §4.6 with its responsibility.
Exit code 0 = in sync, 1 = drift detected.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

MAIN_CMAKE = Path("android/app/src/main/cpp/CMakeLists.txt")
CLAUDE_MD = Path("CLAUDE.md")


def main() -> int:
    cmake_text = MAIN_CMAKE.read_text(encoding="utf-8")
    dsp_core = re.search(r"set\(DSP_CORE_SOURCES(.*?)\)", cmake_text, re.S)
    if dsp_core:
        core_files = set(re.findall(r"([A-Za-z0-9_]+\.cpp)", dsp_core.group(1)))
        jni_sources = re.search(r"set\(JNI_BRIDGE_SOURCES(.*?)\)", cmake_text, re.S)
        jni_files = set(re.findall(r"([A-Za-z0-9_]+\.cpp)", jni_sources.group(1))) if jni_sources else set()
        cmake_sources = core_files | jni_files
    else:
        block = re.search(r"add_library\(pulsr_dsp SHARED(.*?)\)", cmake_text, re.S)
        if not block:
            print("[DOCS GUARD ERROR] Could not parse CMake sources")
            return 1
        cmake_sources = set(re.findall(r"([A-Za-z0-9_]+\.cpp)", block.group(1)))

    claude_text = CLAUDE_MD.read_text(encoding="utf-8")
    section_start = claude_text.find("Native & Backend Subsystems")
    if section_start == -1:
        print("[DOCS GUARD ERROR] Could not find §4.6 in CLAUDE.md")
        return 1

    section_end = claude_text.find("## 5.", section_start)
    if section_end == -1:
        section_end = len(claude_text)
    section_text = claude_text[section_start:section_end]
    missing = []
    for src in sorted(cmake_sources):
        # Allow checking either Source.cpp or Source.cpp / .h
        base = src.replace(".cpp", "")
        if f"`{src}`" not in section_text and f"`{base}.cpp" not in section_text and f"{base}.cpp" not in section_text:
            missing.append(src)

    if missing:
        print(f"[DOCS GUARD FAILED] CMake source files not documented in CLAUDE.md §4.6: {missing}")
        return 1

    print(f"[DOCS GUARD PASSED] All {len(cmake_sources)} CMake DSP sources documented in CLAUDE.md §4.6.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
