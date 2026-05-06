#!/usr/bin/env bash
set -euo pipefail

mkdir -p build logs

echo "[CLEAN] Removing previous axis_complex_mult artifacts..."
rm -f  build/axis_complex_mult*.log build/axis_complex_mult*.pb \
       build/axis_complex_mult*.jou build/axis_complex_mult*.wdb
rm -rf build/xsim.dir build/.Xil

echo "[RUN] Compiling with xvlog..."
cd build

xvlog -sv \
    ../rtl/axis_complex_mult.v \
    ../tb/axis_complex_mult_tb.sv \
    2>&1 | tee ../logs/axis_complex_mult_xvlog.log

echo "[RUN] Elaborating with xelab..."
xelab axis_complex_mult_tb \
    -debug typical \
    -timescale 1ns/1ps \
    -s axis_complex_mult_snap \
    2>&1 | tee ../logs/axis_complex_mult_xelab.log

echo "[RUN] Running simulation with xsim..."
xsim axis_complex_mult_snap \
    -runall \
    2>&1 | tee ../logs/axis_complex_mult_xsim.log

cd ..

echo ""
echo "[RESULTS]"
grep -E "\[PASS\]|\[FAIL\]|CI GATE|---" logs/axis_complex_mult_xsim.log || true

if grep -qE '\[FAIL\]|FATAL' logs/axis_complex_mult_xsim.log; then
    echo "[ERROR] Failures detected in logs/axis_complex_mult_xsim.log"
    exit 1
fi

echo "[PASS] CI GATE: PASSED"
