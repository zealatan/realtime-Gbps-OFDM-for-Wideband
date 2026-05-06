#!/usr/bin/env bash
set -euo pipefail

mkdir -p build logs

echo "[CLEAN] Cleaning previous simulation outputs..."
rm -rf build/xsim.dir build/.Xil build/*.jou build/*.log build/*.pb build/*.wdb

echo "[RUN] Compiling with xvlog..."

cd build

xvlog -sv \
    ../rtl/cordic_atan2.v \
    ../tb/cordic_atan2_tb.sv \
    2>&1 | tee ../logs/cordic_atan2_xvlog.log

echo "[RUN] Elaborating with xelab..."

xelab cordic_atan2_tb \
    -debug typical \
    -s cordic_atan2_tb_sim \
    2>&1 | tee ../logs/cordic_atan2_xelab.log

echo "[RUN] Running simulation with xsim..."

xsim cordic_atan2_tb_sim \
    -runall \
    2>&1 | tee ../logs/cordic_atan2_xsim.log

cd ..

echo "[DONE] cordic_atan2 simulation finished."
echo "[LOG]  logs/cordic_atan2_xsim.log"
