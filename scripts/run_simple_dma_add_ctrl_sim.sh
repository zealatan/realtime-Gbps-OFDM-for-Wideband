#!/usr/bin/env bash
set -euo pipefail

mkdir -p build logs

echo "[CLEAN] Removing previous simple_dma_add_ctrl artifacts..."
rm -f  build/simple_dma_add_ctrl*.log build/simple_dma_add_ctrl*.pb \
       build/simple_dma_add_ctrl*.jou build/simple_dma_add_ctrl*.wdb
rm -rf build/xsim.dir build/.Xil

echo "[RUN] Compiling with xvlog..."
cd build

xvlog -sv \
    ../tb/axi_mem_model.sv \
    ../rtl/simple_dma_add_nword.v \
    ../rtl/simple_dma_add_ctrl.v \
    ../tb/simple_dma_add_ctrl_tb.sv \
    2>&1 | tee ../logs/simple_dma_add_ctrl_xvlog.log

echo "[RUN] Elaborating with xelab..."
xelab simple_dma_add_ctrl_tb \
    -debug typical \
    -s simple_dma_add_ctrl_tb_sim \
    2>&1 | tee ../logs/simple_dma_add_ctrl_xelab.log

echo "[RUN] Running simulation with xsim..."
xsim simple_dma_add_ctrl_tb_sim \
    -runall \
    2>&1 | tee ../logs/simple_dma_add_ctrl_xsim.log

cd ..

echo "[DONE] Simulation finished."

if grep -qE '\[FAIL\]|FATAL' logs/simple_dma_add_ctrl_xsim.log; then
    echo "[ERROR] Failures detected in logs/simple_dma_add_ctrl_xsim.log"
    exit 1
fi

echo "[PASS] No failures detected."
