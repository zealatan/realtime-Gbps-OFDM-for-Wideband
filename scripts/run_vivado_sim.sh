#!/usr/bin/env bash
set -euo pipefail

mkdir -p build logs

echo "[CLEAN] Cleaning previous simulation outputs..."
rm -rf build/xsim.dir build/.Xil build/*.jou build/*.log build/*.pb build/*.wdb

echo "[RUN] Compiling with xvlog..."

cd build

xvlog -sv \
    ../rtl/and2.v \
    ../tb/and2_tb.sv \
    2>&1 | tee ../logs/xvlog.log

echo "[RUN] Elaborating with xelab..."

xelab and2_tb \
    -debug typical \
    -s and2_tb_sim \
    2>&1 | tee ../logs/xelab.log

echo "[RUN] Running simulation with xsim..."

xsim and2_tb_sim \
    -runall \
    2>&1 | tee ../logs/xsim.log

cd ..

echo "[DONE] Vivado simulation finished."
echo "[LOG] logs/xsim.log"
