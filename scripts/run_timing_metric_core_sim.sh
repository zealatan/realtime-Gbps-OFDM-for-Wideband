#!/usr/bin/env bash
set -euo pipefail

mkdir -p build logs

echo "[CLEAN] Cleaning previous simulation outputs..."
rm -rf build/xsim.dir build/.Xil build/*.jou build/*.log build/*.pb build/*.wdb

echo "[RUN] Compiling with xvlog..."

cd build

xvlog -sv \
    ../rtl/timing_metric_core.v \
    ../tb/timing_metric_core_tb.sv \
    2>&1 | tee ../logs/timing_metric_core_xvlog.log

echo "[RUN] Elaborating with xelab..."

xelab timing_metric_core_tb \
    -debug typical \
    -s timing_metric_core_tb_sim \
    2>&1 | tee ../logs/timing_metric_core_xelab.log

echo "[RUN] Running simulation with xsim..."

xsim timing_metric_core_tb_sim \
    -runall \
    2>&1 | tee ../logs/timing_metric_core_xsim.log

cd ..

echo "[DONE] timing_metric_core simulation finished."
echo "[LOG]  logs/timing_metric_core_xsim.log"
