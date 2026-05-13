#!/usr/bin/env bash
set -euo pipefail

# run_fft256_xilinx_wrapper_stub_sim.sh — Compile and simulate the
# fft256_xilinx_wrapper stub testbench (USE_BEHAVIORAL_STUB=1).
#
# This script does NOT test FFT correctness.
# It verifies compile, interface, and stub behavior only.
# Actual Xilinx FFT XCI is not required for this test.
#
# Usage:
#   bash scripts/run_fft256_xilinx_wrapper_stub_sim.sh
#
# See docs/step36A_fft256_xilinx_ip_audit.md for context.

# Source Vivado tools if not already on PATH
if ! command -v xvlog &>/dev/null; then
    source /home/zealatan/Downloads/Vivado/2022.2/settings64.sh 2>/dev/null || true
fi

mkdir -p build logs

echo "[CLEAN] Removing previous fft256_xilinx_wrapper_stub artifacts..."
rm -f  build/fft256_xilinx_wrapper_stub*.log \
       build/fft256_xilinx_wrapper_stub*.pb  \
       build/fft256_xilinx_wrapper_stub*.jou \
       build/fft256_xilinx_wrapper_stub*.wdb
rm -rf build/xsim.dir build/.Xil

echo "[RUN] Compiling with xvlog..."
cd build

xvlog -sv \
    ../rtl/fft256_xilinx_wrapper.v \
    ../tb/fft256_xilinx_wrapper_stub_tb.sv \
    2>&1 | tee ../logs/fft256_xilinx_wrapper_stub_xvlog.log

echo "[RUN] Elaborating with xelab..."
xelab fft256_xilinx_wrapper_stub_tb \
    -debug typical \
    -timescale 1ns/1ps \
    -s fft256_xilinx_wrapper_stub_snap \
    2>&1 | tee ../logs/fft256_xilinx_wrapper_stub_xelab.log

echo "[RUN] Running simulation with xsim..."
xsim fft256_xilinx_wrapper_stub_snap \
    -runall \
    2>&1 | tee ../logs/fft256_xilinx_wrapper_stub_xsim.log

cd ..

echo ""
echo "[RESULTS]"
grep -E "T[0-9]+:|PASS|FAIL|CI GATE|WARNING|NOTE" \
    logs/fft256_xilinx_wrapper_stub_xsim.log || true

if grep -qE 'CI GATE: FAILED|\[FAIL\]|FATAL' \
        logs/fft256_xilinx_wrapper_stub_xsim.log; then
    echo "[ERROR] Failures detected in logs/fft256_xilinx_wrapper_stub_xsim.log"
    exit 1
fi

echo "[PASS] CI GATE: PASSED"
