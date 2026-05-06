#!/usr/bin/env bash
set -euo pipefail

mkdir -p build logs

echo "[CLEAN] Cleaning previous simulation outputs..."
rm -rf build/xsim.dir build/.Xil build/*.jou build/*.log build/*.pb build/*.wdb

echo "[RUN] Compiling with xvlog..."

cd build

xvlog -sv \
    ../rtl/cp_autocorr_core.v \
    ../tb/cp_autocorr_core_tb.sv \
    2>&1 | tee ../logs/cp_autocorr_core_xvlog.log

echo "[RUN] Elaborating with xelab..."

xelab cp_autocorr_core_tb \
    -debug typical \
    -s cp_autocorr_core_tb_sim \
    2>&1 | tee ../logs/cp_autocorr_core_xelab.log

echo "[RUN] Running simulation with xsim..."

xsim cp_autocorr_core_tb_sim \
    -runall \
    2>&1 | tee ../logs/cp_autocorr_core_xsim.log

cd ..

echo "[DONE] cp_autocorr_core simulation finished."
echo "[LOG]  logs/cp_autocorr_core_xsim.log"
