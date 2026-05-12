#!/usr/bin/env bash
set -euo pipefail

mkdir -p build logs

echo "[CLEAN] Removing previous meyr_integer_cfo_core artifacts..."
rm -f  build/meyr_integer_cfo_core*.log build/meyr_integer_cfo_core*.pb \
       build/meyr_integer_cfo_core*.jou build/meyr_integer_cfo_core*.wdb
rm -rf build/xsim.dir build/.Xil

echo "[RUN] Compiling with xvlog..."
cd build

xvlog -sv \
    ../rtl/peak_detector.v \
    ../rtl/meyr_integer_cfo_core.v \
    ../tb/meyr_integer_cfo_core_tb.sv \
    2>&1 | tee ../logs/meyr_integer_cfo_core_xvlog.log

echo "[RUN] Elaborating with xelab..."
xelab meyr_integer_cfo_core_tb \
    -debug typical \
    -timescale 1ns/1ps \
    -s meyr_integer_cfo_core_snap \
    2>&1 | tee ../logs/meyr_integer_cfo_core_xelab.log

echo "[RUN] Running simulation with xsim..."
xsim meyr_integer_cfo_core_snap \
    -runall \
    2>&1 | tee ../logs/meyr_integer_cfo_core_xsim.log

cd ..

echo ""
echo "[RESULTS]"
grep -E "T[0-9]+:|PASS|FAIL|CI GATE" logs/meyr_integer_cfo_core_xsim.log || true

if grep -qE 'CI GATE: FAILED|FAIL:|FATAL' logs/meyr_integer_cfo_core_xsim.log; then
    echo "[ERROR] Failures detected in logs/meyr_integer_cfo_core_xsim.log"
    exit 1
fi

echo "[PASS] CI GATE: PASSED"
