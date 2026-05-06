#!/usr/bin/env bash
set -euo pipefail

mkdir -p build logs

echo "[CLEAN] Cleaning previous simulation outputs..."
rm -rf build/xsim.dir build/.Xil build/*.jou build/*.log build/*.pb build/*.wdb

echo "[RUN] Compiling with xvlog..."

cd build

xvlog -sv \
    ../rtl/cordic_atan2.v \
    ../rtl/frac_cfo_estimator.v \
    ../tb/frac_cfo_estimator_tb.sv \
    2>&1 | tee ../logs/frac_cfo_estimator_xvlog.log

echo "[RUN] Elaborating with xelab..."

xelab frac_cfo_estimator_tb \
    -debug typical \
    -s frac_cfo_estimator_tb_sim \
    2>&1 | tee ../logs/frac_cfo_estimator_xelab.log

echo "[RUN] Running simulation with xsim..."

xsim frac_cfo_estimator_tb_sim \
    -runall \
    2>&1 | tee ../logs/frac_cfo_estimator_xsim.log

cd ..

echo "[DONE] frac_cfo_estimator simulation finished."
echo "[LOG]  logs/frac_cfo_estimator_xsim.log"
