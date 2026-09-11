#!/usr/bin/env bash
# Runs every audio-focused Dart suite in one command.
#
#   bash scripts/run_audio_suites.sh
#
# Covers the four-layer audio wiring (route / interruption / settings / telemetry)
# plus the per-session Bluetooth observability harness and the pure output-format
# negotiation table. CI invokes this in .github/workflows/ci.yml.
#
# The native C++ DSP suite (dither correctness, parity) is a separate, host-only
# target and is not run here:
#   cd android && ./gradlew :app:testNative
set -euo pipefail
cd "$(dirname "$0")/.."

flutter test \
  test/data/audio \
  test/core/telemetry \
  test/dsp_expansion_test.dart
