#!/usr/bin/env bash
set -euo pipefail

mkdir -p build logs

echo "[CLEAN] Cleaning previous simulation outputs..."
rm -rf build/xsim.dir build/.Xil build/*.jou build/*.log build/*.pb build/*.wdb

echo "[RUN] Compiling with xvlog..."

cd build

xvlog -sv \
    ../rtl/axis_complex_mult.v \
    ../rtl/complex_mult_iq.v \
    ../rtl/complex_rotator.v \
    ../rtl/nco_phase_gen.v \
    ../rtl/frac_cfo_corrector_top.v \
    ../rtl/cp_autocorr_core.v \
    ../rtl/timing_metric_core.v \
    ../rtl/peak_detector.v \
    ../rtl/timing_sync_top.v \
    ../rtl/cordic_atan2.v \
    ../rtl/frac_cfo_estimator.v \
    ../rtl/timing_frac_cfo_top.v \
    ../rtl/iq_frame_buffer.v \
    ../rtl/frame_detector.v \
    ../rtl/frac_cfo_frame_corrector_top.v \
    ../tb/frac_cfo_frame_corrector_top_tb.sv \
    2>&1 | tee ../logs/frac_cfo_frame_corrector_top_xvlog.log

echo "[RUN] Elaborating with xelab..."

xelab frac_cfo_frame_corrector_top_tb \
    -debug typical \
    -timescale 1ns/1ps \
    -s frac_cfo_frame_corrector_top_tb_sim \
    2>&1 | tee ../logs/frac_cfo_frame_corrector_top_xelab.log

echo "[RUN] Running simulation with xsim..."

xsim frac_cfo_frame_corrector_top_tb_sim \
    -runall \
    2>&1 | tee ../logs/frac_cfo_frame_corrector_top_xsim.log

cd ..

echo "[DONE] frac_cfo_frame_corrector_top simulation finished."
echo "[LOG]  logs/frac_cfo_frame_corrector_top_xsim.log"
