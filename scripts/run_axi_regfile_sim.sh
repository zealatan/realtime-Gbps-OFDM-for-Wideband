#!/usr/bin/env bash
set -euo pipefail

mkdir -p build logs

echo "[CLEAN] Removing previous axi_regfile artifacts..."
rm -f  build/axi_lite_regfile*.log build/axi_lite_regfile*.pb \
       build/axi_lite_regfile*.jou build/axi_lite_regfile*.wdb
rm -rf build/xsim.dir build/.Xil

echo "[RUN] Compiling with xvlog..."
cd build

xvlog -sv \
    ../rtl/axi_lite_regfile.v \
    ../tb/axi_lite_regfile_tb.sv \
    2>&1 | tee ../logs/axi_lite_xvlog.log

echo "[RUN] Elaborating with xelab..."
xelab axi_lite_regfile_tb \
    -debug typical \
    -s axi_lite_regfile_tb_sim \
    2>&1 | tee ../logs/axi_lite_xelab.log

echo "[RUN] Running simulation with xsim..."
xsim axi_lite_regfile_tb_sim \
    -runall \
    2>&1 | tee ../logs/axi_lite_xsim.log

cd ..

echo "[DONE] Simulation finished."

# CI gate: any [FAIL] or FATAL line means the run failed
if grep -qE '\[FAIL\]|FATAL' logs/axi_lite_xsim.log; then
    echo "[ERROR] Failures detected in logs/axi_lite_xsim.log"
    exit 1
fi

echo "[PASS] No failures detected."
