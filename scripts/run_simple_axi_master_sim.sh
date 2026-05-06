#!/usr/bin/env bash
set -euo pipefail

mkdir -p build logs

echo "[CLEAN] Removing previous simple_axi_master artifacts..."
rm -f  build/simple_axi_master*.log build/simple_axi_master*.pb \
       build/simple_axi_master*.jou build/simple_axi_master*.wdb
rm -rf build/xsim.dir build/.Xil

echo "[RUN] Compiling with xvlog..."
cd build

xvlog -sv \
    ../tb/axi_mem_model.sv \
    ../rtl/simple_axi_master.v \
    ../tb/simple_axi_master_tb.sv \
    2>&1 | tee ../logs/simple_axi_master_xvlog.log

echo "[RUN] Elaborating with xelab..."
xelab simple_axi_master_tb \
    -debug typical \
    -s simple_axi_master_tb_sim \
    2>&1 | tee ../logs/simple_axi_master_xelab.log

echo "[RUN] Running simulation with xsim..."
xsim simple_axi_master_tb_sim \
    -runall \
    2>&1 | tee ../logs/simple_axi_master_xsim.log

cd ..

echo "[DONE] Simulation finished."

# CI gate: any [FAIL] or FATAL line means the run failed
if grep -qE '\[FAIL\]|FATAL' logs/simple_axi_master_xsim.log; then
    echo "[ERROR] Failures detected in logs/simple_axi_master_xsim.log"
    exit 1
fi

echo "[PASS] No failures detected."
