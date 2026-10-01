#!/usr/bin/env python3
"""
CI Guard: Native DSP test-coverage drift checker.

The native DSP engine is compiled twice: once into the shipped shared library
(`android/app/src/main/cpp/CMakeLists.txt` -> `pulsr_dsp`) and once into the
host test suite (`android/app/src/test/cpp/CMakeLists.txt`). If a new DSP
translation unit is added to production but not to the host test build, it
silently ships untested.

This guard verifies every host-testable production DSP source (i.e. everything
except the JNI/AAudio Android-only bridges, which cannot link on the host) is
present in the test CMake `DSP_SRCS` list.

Exit code 0 = in sync, 1 = drift detected.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

MAIN_CMAKE = Path("android/app/src/main/cpp/CMakeLists.txt")
TEST_CMAKE = Path("android/app/src/test/cpp/CMakeLists.txt")

# Android-only translation units with no host-testable logic: they either need
# the JNI headers or the AAudio/Android NDK audio API and are intentionally
# excluded from the host build.
ANDROID_ONLY = {
    "eq_jni_bridge.cpp",
    "AAudioSink.cpp",
    "aaudio_jni_bridge.cpp",
}

# Sources built per-target in the test CMake that are not part of DSP_SRCS but
# are still compiled (e.g. DopFramer is header-only; ConvolutionReverb and
# SincResampler are added to REVERB_SRCS). Collect them from the whole file.
def main_sources() -> set[str]:
    text = MAIN_CMAKE.read_text(encoding="utf-8")
    # add_library(pulsr_dsp SHARED ... ) block
    block = re.search(r"add_library\(pulsr_dsp SHARED(.*?)\)", text, re.S)
    if not block:
        print("[NATIVE DRIFT] Could not locate add_library(pulsr_dsp ...) block")
        return set()
    return set(re.findall(r"([A-Za-z0-9_]+\.cpp)", block.group(1)))


def test_sources() -> set[str]:
    text = TEST_CMAKE.read_text(encoding="utf-8")
    # Every `${MAIN_CPP}/<name>.cpp` reference anywhere in the test CMake.
    return set(re.findall(r"\$\{MAIN_CPP\}/([A-Za-z0-9_]+\.cpp)", text))


def main() -> int:
    main_set = main_sources()
    test_set = test_sources()
    if not main_set:
        print("[NATIVE DRIFT] No production DSP sources found; guard misconfigured.")
        return 1

    expected = main_set - ANDROID_ONLY
    missing = sorted(expected - test_set)

    print(f"[NATIVE DRIFT] production DSP sources: {len(main_set)}")
    print(f"[NATIVE DRIFT] android-only (excluded): {sorted(ANDROID_ONLY)}")
    print(f"[NATIVE DRIFT] host-test expected: {len(expected)}")
    print(f"[NATIVE DRIFT] host-test referenced: {len(test_set & expected)}")

    if missing:
        print(
            "[NATIVE DRIFT FAILED] Production DSP sources missing from the host "
            f"test build: {missing}. Add them to {TEST_CMAKE}."
        )
        return 1

    print("[NATIVE DRIFT PASSED] All host-testable DSP sources are covered by the native suite.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
