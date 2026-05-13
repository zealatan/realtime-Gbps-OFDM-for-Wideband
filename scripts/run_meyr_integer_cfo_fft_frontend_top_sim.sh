#!/usr/bin/env bash
set -euo pipefail

mkdir -p build logs

echo "[CLEAN] Removing previous meyr_integer_cfo_fft_frontend_top artifacts..."
rm -f  build/meyr_integer_cfo_fft_frontend_top*.log \
       build/meyr_integer_cfo_fft_frontend_top*.pb \
       build/meyr_integer_cfo_fft_frontend_top*.jou \
       build/meyr_integer_cfo_fft_frontend_top*.wdb
rm -rf build/xsim.dir build/.Xil

echo "[RUN] Compiling with xvlog..."
cd build

xvlog -sv \
    ../rtl/peak_detector.v \
    ../rtl/meyr_integer_cfo_core.v \
    ../rtl/meyr_pss_sss_product_gen.v \
    ../rtl/meyr_term2_ref_rom.v \
    ../rtl/meyr_integer_cfo_freq_estimator_top.v \
    ../rtl/fft256_dual_symbol_frontend.v \
    ../rtl/meyr_integer_cfo_fft_frontend_top.v \
    ../tb/fft256_behavioral_model.sv \
    ../tb/meyr_integer_cfo_fft_frontend_top_tb.sv \
    2>&1 | tee ../logs/meyr_integer_cfo_fft_frontend_top_xvlog.log

echo "[RUN] Elaborating with xelab..."
xelab meyr_integer_cfo_fft_frontend_top_tb \
    -debug typical \
    -timescale 1ns/1ps \
    -s meyr_integer_cfo_fft_frontend_top_snap \
    2>&1 | tee ../logs/meyr_integer_cfo_fft_frontend_top_xelab.log

echo "[RUN] Running simulation with xsim..."
xsim meyr_integer_cfo_fft_frontend_top_snap \
    -runall \
    2>&1 | tee ../logs/meyr_integer_cfo_fft_frontend_top_xsim.log

cd ..

echo ""
echo "[RESULTS]"
grep -E "T[0-9]+:|PASS|FAIL|CI GATE" logs/meyr_integer_cfo_fft_frontend_top_xsim.log || true

if grep -qE 'CI GATE: FAILED|FATAL' logs/meyr_integer_cfo_fft_frontend_top_xsim.log; then
    echo "[ERROR] Failures detected in logs/meyr_integer_cfo_fft_frontend_top_xsim.log"
    exit 1
fi

echo "[PASS] CI GATE: PASSED"
