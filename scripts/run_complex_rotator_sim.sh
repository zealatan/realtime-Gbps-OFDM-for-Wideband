#!/usr/bin/env bash
set -euo pipefail

mkdir -p build logs

echo "[CLEAN] Cleaning previous simulation outputs..."
rm -rf build/xsim.dir build/.Xil build/*.jou build/*.log build/*.pb build/*.wdb

echo "[RUN] Compiling with xvlog..."

cd build

xvlog -sv \
    ../rtl/axis_complex_mult.v \
    ../rtl/complex_mult_iq.v \
    ../rtl/complex_rotator.v \
    ../tb/complex_rotator_tb.sv \
    2>&1 | tee ../logs/complex_rotator_xvlog.log

echo "[RUN] Elaborating with xelab..."

xelab complex_rotator_tb \
    -debug typical \
    -timescale 1ns/1ps \
    -s complex_rotator_tb_sim \
    2>&1 | tee ../logs/complex_rotator_xelab.log

echo "[RUN] Running simulation with xsim..."

xsim complex_rotator_tb_sim \
    -runall \
    2>&1 | tee ../logs/complex_rotator_xsim.log

cd ..

echo "[DONE] complex_rotator simulation finished."
echo "[LOG]  logs/complex_rotator_xsim.log"
