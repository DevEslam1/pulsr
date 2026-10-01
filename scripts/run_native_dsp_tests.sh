#!/usr/bin/env bash
# Builds and runs the full native C++ DSP test suite on the host (parity -O3
# build + ASan/UBSan debug build), then runs every CTest target.
#
#   bash scripts/run_native_dsp_tests.sh
#
# This is the same suite the gradle `:app:testNative` task runs, but invoked
# directly via CMake/CTest so CI does not need Gradle, Java, or Flutter.
# Requires: cmake >= 3.22 and a host clang++ (or g++) on PATH.
set -euo pipefail
cd "$(dirname "$0")/.."

ROOT="$(pwd)"
TEST_DIR="$ROOT/android/app/src/test/cpp"
OUT_ROOT="$ROOT/build/nativeDspTests"

CXX="${CXX:-clang++}"
if ! command -v "$CXX" >/dev/null 2>&1; then
  if command -v g++ >/dev/null 2>&1; then
    CXX="g++"
  else
    echo "error: no host C++ compiler (clang++/g++) found" >&2
    exit 1
  fi
fi

echo "== Native DSP tests: compiler=$CXX =="

run_config() {
  local config="$1"      # Release | Debug
  local sanitizers="$2"  # ON | OFF
  local build_dir="$OUT_ROOT/$config"
  echo ""
  echo "== [$config] configuring (sanitizers=$sanitizers) =="
  cmake -S "$TEST_DIR" -B "$build_dir" \
    -DCMAKE_BUILD_TYPE="$config" \
    -DCMAKE_CXX_COMPILER="$CXX" \
    -DPULSR_TEST_SANITIZERS="$sanitizers"
  echo "== [$config] building =="
  cmake --build "$build_dir" --parallel
  echo "== [$config] running CTest =="
  ctest --test-dir "$build_dir" --output-on-failure
}

run_config Release OFF
run_config Debug ON

echo ""
echo "PASSED: native DSP suites (parity Release + sanitizer Debug) green."
