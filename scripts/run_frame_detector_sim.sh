#!/usr/bin/env bash
set -euo pipefail

mkdir -p build logs

echo "[CLEAN] Cleaning previous simulation outputs..."
rm -rf build/xsim.dir build/.Xil build/*.jou build/*.log build/*.pb build/*.wdb

echo "[RUN] Compiling with xvlog..."

cd build

xvlog -sv \
    ../rtl/frame_detector.v \
    ../tb/frame_detector_tb.sv \
    2>&1 | tee ../logs/frame_detector_xvlog.log

echo "[RUN] Elaborating with xelab..."

xelab frame_detector_tb \
    -debug typical \
    -s frame_detector_tb_sim \
    2>&1 | tee ../logs/frame_detector_xelab.log

echo "[RUN] Running simulation with xsim..."

xsim frame_detector_tb_sim \
    -runall \
    2>&1 | tee ../logs/frame_detector_xsim.log

cd ..

echo "[DONE] frame_detector simulation finished."
echo "[LOG]  logs/frame_detector_xsim.log"
