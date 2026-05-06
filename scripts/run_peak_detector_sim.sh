#!/usr/bin/env bash
set -euo pipefail

mkdir -p build logs

echo "[CLEAN] Cleaning previous simulation outputs..."
rm -rf build/xsim.dir build/.Xil build/*.jou build/*.log build/*.pb build/*.wdb

echo "[RUN] Compiling with xvlog..."

cd build

xvlog -sv \
    ../rtl/peak_detector.v \
    ../tb/peak_detector_tb.sv \
    2>&1 | tee ../logs/peak_detector_xvlog.log

echo "[RUN] Elaborating with xelab..."

xelab peak_detector_tb \
    -debug typical \
    -s peak_detector_tb_sim \
    2>&1 | tee ../logs/peak_detector_xelab.log

echo "[RUN] Running simulation with xsim..."

xsim peak_detector_tb_sim \
    -runall \
    2>&1 | tee ../logs/peak_detector_xsim.log

cd ..

echo "[DONE] peak_detector simulation finished."
echo "[LOG]  logs/peak_detector_xsim.log"
