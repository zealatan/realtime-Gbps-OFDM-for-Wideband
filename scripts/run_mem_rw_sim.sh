#!/usr/bin/env bash
set -euo pipefail

mkdir -p build logs

echo "[CLEAN] Removing previous mem_rw artifacts..."
rm -f  build/mem_rw*.log build/mem_rw*.pb \
       build/mem_rw*.jou build/mem_rw*.wdb
rm -rf build/xsim.dir build/.Xil

echo "[RUN] Compiling with xvlog..."
cd build

xvlog -sv \
    ../tb/axi_mem_model.sv \
    ../tb/mem_rw_tb.sv \
    2>&1 | tee ../logs/mem_rw_xvlog.log

echo "[RUN] Elaborating with xelab..."
xelab mem_rw_tb \
    -debug typical \
    -s mem_rw_tb_sim \
    2>&1 | tee ../logs/mem_rw_xelab.log

echo "[RUN] Running simulation with xsim..."
xsim mem_rw_tb_sim \
    -runall \
    2>&1 | tee ../logs/mem_rw_xsim.log

cd ..

echo "[DONE] Simulation finished."

# CI gate: any [FAIL] or FATAL line means the run failed
if grep -qE '\[FAIL\]|FATAL' logs/mem_rw_xsim.log; then
    echo "[ERROR] Failures detected in logs/mem_rw_xsim.log"
    exit 1
fi

echo "[PASS] No failures detected."
