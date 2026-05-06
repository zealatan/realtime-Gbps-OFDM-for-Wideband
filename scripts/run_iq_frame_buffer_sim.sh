#!/usr/bin/env bash
set -euo pipefail

mkdir -p build logs

echo "[CLEAN] Cleaning previous simulation outputs..."
rm -rf build/xsim.dir build/.Xil build/*.jou build/*.log build/*.pb build/*.wdb

echo "[RUN] Compiling with xvlog..."

cd build

xvlog -sv \
    ../rtl/iq_frame_buffer.v \
    ../tb/iq_frame_buffer_tb.sv \
    2>&1 | tee ../logs/iq_frame_buffer_xvlog.log

echo "[RUN] Elaborating with xelab..."

xelab iq_frame_buffer_tb \
    -debug typical \
    -s iq_frame_buffer_tb_sim \
    2>&1 | tee ../logs/iq_frame_buffer_xelab.log

echo "[RUN] Running simulation with xsim..."

xsim iq_frame_buffer_tb_sim \
    -runall \
    2>&1 | tee ../logs/iq_frame_buffer_xsim.log

cd ..

echo "[DONE] iq_frame_buffer simulation finished."
echo "[LOG]  logs/iq_frame_buffer_xsim.log"
