#!/usr/bin/env bash
# android/app/src/main/cpp/fuzz/fuzz.sh
# Build and execute libFuzzer targets with ASan and UBSan sanitizers.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CPP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
DURATION="${1:-10}" # Default: 10s smoke run in CI

mkdir -p "${BUILD_DIR}"

CXX="${CXX:-clang++}"
CXXFLAGS="-std=c++20 -O2 -g -fsanitize=fuzzer,address,undefined -fno-omit-frame-pointer -I${CPP_DIR}"

TARGETS=("graphic_eq" "viper_ddc" "liveprog" "dsd")

echo "===================================================="
echo "  Pulsr DSP libFuzzer Build & Execution (ASan+UBSan)"
echo "  Smoke Run Duration: ${DURATION}s per target"
echo "===================================================="

# Compile targets
for target in "${TARGETS[@]}"; do
    echo "[BUILD] Compiling fuzz_${target}..."
    case "${target}" in
        graphic_eq)
            ${CXX} ${CXXFLAGS} \
                "${SCRIPT_DIR}/fuzz_graphic_eq.cc" \
                "${CPP_DIR}/ArbitraryResponseEq.cpp" \
                -o "${BUILD_DIR}/fuzz_graphic_eq"
            ;;
        viper_ddc)
            ${CXX} ${CXXFLAGS} \
                "${SCRIPT_DIR}/fuzz_viper_ddc.cc" \
                "${CPP_DIR}/ViperDdc.cpp" \
                -o "${BUILD_DIR}/fuzz_viper_ddc"
            ;;
        liveprog)
            ${CXX} ${CXXFLAGS} \
                "${SCRIPT_DIR}/fuzz_liveprog.cc" \
                "${CPP_DIR}/LiveProg.cpp" \
                -o "${BUILD_DIR}/fuzz_liveprog"
            ;;
        dsd)
            ${CXX} ${CXXFLAGS} \
                "${SCRIPT_DIR}/fuzz_dsd.cc" \
                "${CPP_DIR}/DsdDecoder.cpp" \
                -o "${BUILD_DIR}/fuzz_dsd"
            ;;
    esac
    echo "[BUILD] OK: ${BUILD_DIR}/fuzz_${target}"
done

# Execute smoke runs
for target in "${TARGETS[@]}"; do
    echo "----------------------------------------------------"
    echo "[RUN] Executing fuzz_${target} (smoke ${DURATION}s)..."
    CORPUS_DIR="${SCRIPT_DIR}/corpus/${target}"
    mkdir -p "${CORPUS_DIR}"
    "${BUILD_DIR}/fuzz_${target}" \
        "${CORPUS_DIR}" \
        -max_total_time="${DURATION}" \
        -print_final_stats=1 \
        -artifact_prefix="${BUILD_DIR}/crash-"
    echo "[RUN] PASS: fuzz_${target}"
done

echo "===================================================="
echo "  ALL FUZZ TARGETS COMPLETED CLEANLY WITH 0 CRASHES!"
echo "===================================================="
