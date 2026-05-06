#!/usr/bin/env bash
set -euo pipefail

mkdir -p build logs

echo "[CLEAN] Removing previous axis_add_one artifacts..."
rm -f  build/axis_add_one*.log build/axis_add_one*.pb \
       build/axis_add_one*.jou build/axis_add_one*.wdb
rm -rf build/xsim.dir build/.Xil

echo "[RUN] Compiling with xvlog..."
cd build

xvlog -sv \
    ../rtl/axis_add_one.v \
    ../tb/axis_add_one_tb.sv \
    2>&1 | tee ../logs/axis_add_one_xvlog.log

echo "[RUN] Elaborating with xelab..."
xelab axis_add_one_tb \
    -debug typical \
    -s axis_add_one_tb_sim \
    -timescale 1ns/1ps \
    2>&1 | tee ../logs/axis_add_one_xelab.log

echo "[RUN] Running simulation with xsim..."
xsim axis_add_one_tb_sim \
    -runall \
    2>&1 | tee ../logs/axis_add_one_xsim.log

cd ..

echo "[DONE] Simulation finished."

if grep -qE '\[FAIL\]|FATAL' logs/axis_add_one_xsim.log; then
    echo "[ERROR] Failures detected in logs/axis_add_one_xsim.log"
    exit 1
fi

echo "[PASS] No failures detected."
