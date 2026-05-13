#!/usr/bin/env bash
set -euo pipefail

# Source Vivado tools if not already on PATH
if ! command -v xvlog &>/dev/null; then
    source /home/zealatan/Downloads/Vivado/2022.2/settings64.sh 2>/dev/null || true
fi

mkdir -p build logs

echo "[CLEAN] Removing previous cordic_atan2_xilinx_wrapper artifacts..."
rm -f  build/cordic_atan2_xilinx_wrapper*.log \
       build/cordic_atan2_xilinx_wrapper*.pb  \
       build/cordic_atan2_xilinx_wrapper*.jou \
       build/cordic_atan2_xilinx_wrapper*.wdb
rm -rf build/xsim.dir build/.Xil

echo "[RUN] Compiling with xvlog..."
cd build

xvlog -sv \
    ../rtl/cordic_atan2_xilinx_wrapper.v \
    ../tb/cordic_atan2_xilinx_wrapper_tb.sv \
    2>&1 | tee ../logs/cordic_atan2_xilinx_wrapper_xvlog.log

echo "[RUN] Elaborating with xelab..."
xelab cordic_atan2_xilinx_wrapper_tb \
    -debug typical \
    -timescale 1ns/1ps \
    -s cordic_atan2_xilinx_wrapper_snap \
    2>&1 | tee ../logs/cordic_atan2_xilinx_wrapper_xelab.log

echo "[RUN] Running simulation with xsim..."
xsim cordic_atan2_xilinx_wrapper_snap \
    -runall \
    2>&1 | tee ../logs/cordic_atan2_xilinx_wrapper_xsim.log

cd ..

echo ""
echo "[RESULTS]"
grep -E "T[0-9]+:|PASS|FAIL|CI GATE" \
    logs/cordic_atan2_xilinx_wrapper_xsim.log || true

if grep -qE 'CI GATE: FAILED|\[FAIL\]|FATAL' \
        logs/cordic_atan2_xilinx_wrapper_xsim.log; then
    echo "[ERROR] Failures detected in logs/cordic_atan2_xilinx_wrapper_xsim.log"
    exit 1
fi

echo "[PASS] CI GATE: PASSED"
