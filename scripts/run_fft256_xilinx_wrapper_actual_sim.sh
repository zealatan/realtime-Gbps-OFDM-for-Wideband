#!/usr/bin/env bash
set -euo pipefail

# run_fft256_xilinx_wrapper_actual_sim.sh
#
# Compile and simulate fft256_xilinx_wrapper with USE_BEHAVIORAL_STUB=0.
# Uses the actual Xilinx xfft_v9_1_8 behavioral model (mixed VHDL/Verilog).
#
# All xsim compilation runs from the REPO ROOT (not build/).
# Compiled libraries land in xsim.dir/ at the repo root.
# Logs land in logs/.
#
# Compile order:
#   1. xvhdl — compile protected xfft VHDL (xfft_v9_1_vh_rfs.vhd)
#   2. xvlog — compile Verilog wrapper + RTL + TB
#   3. xelab — elaborate (mixed-language, finds xfft_v9_1_8 automatically)
#   4. xsim  — run simulation
#
# The xfft_v9_1_vh_rfs.vhd is DRM-protected; xvhdl decrypts it using
# built-in Xilinx keys.  No additional license is required for simulation.
#
# Usage:
#   bash scripts/run_fft256_xilinx_wrapper_actual_sim.sh

VIVADO_SETTINGS="/home/zealatan/Downloads/Vivado/2022.2/settings64.sh"
XFFT_VHDL="/home/zealatan/Downloads/Vivado/2022.2/data/ip/xilinx/xfft_v9_1/hdl/xfft_v9_1_vh_rfs.vhd"
SNAP="fft256_actual_snap"
LOG_PREFIX="logs/fft256_xilinx_wrapper_actual"

# Source Vivado tools
if ! command -v xvlog &>/dev/null; then
    source "${VIVADO_SETTINGS}" 2>/dev/null || true
fi

mkdir -p build logs

echo "[CLEAN] Removing previous fft256_actual artifacts..."
rm -f  "${LOG_PREFIX}"_*.log
rm -rf xsim.dir xsim.jou xsim.log xvlog.log xvlog.pb xelab.log xelab.pb .Xil

echo "================================"
echo "[STEP 1] Compile xfft VHDL model"
echo "================================"
xvhdl "${XFFT_VHDL}" \
    2>&1 | tee "${LOG_PREFIX}_xvhdl.log"

echo ""
echo "==================================="
echo "[STEP 2] Compile Verilog RTL and TB"
echo "==================================="
xvlog -sv \
    ip/fft256_xilinx/fft256_xilinx/fft256_xilinx.v \
    rtl/fft256_xilinx_wrapper.v \
    tb/fft256_xilinx_wrapper_actual_tb.sv \
    2>&1 | tee "${LOG_PREFIX}_xvlog.log"

echo ""
echo "==================================="
echo "[STEP 3] Elaborate (mixed-language)"
echo "==================================="
xelab fft256_xilinx_wrapper_actual_tb \
    -debug typical \
    -timescale 1ns/1ps \
    -s "${SNAP}" \
    2>&1 | tee "${LOG_PREFIX}_xelab.log"

echo ""
echo "========================="
echo "[STEP 4] Run simulation"
echo "========================="
xsim "${SNAP}" \
    -runall \
    2>&1 | tee "${LOG_PREFIX}_xsim.log"

echo ""
echo "==============================="
echo "[RESULTS]"
echo "==============================="

grep -E "T[0-9]+:|PASS|FAIL|CI GATE|latency|packing|xk_index|Config word|Backpressure|Scaling" \
    "${LOG_PREFIX}_xsim.log" | grep -v "NOTE\|event_" | head -60 || true

echo ""
if grep -q "CI GATE: PASSED" "${LOG_PREFIX}_xsim.log"; then
    grep "PASS:.*FAIL:" "${LOG_PREFIX}_xsim.log" | tail -1
    grep "CI GATE: PASSED" "${LOG_PREFIX}_xsim.log" | tail -1
    echo ""
    echo "CI GATE: PASSED"
else
    echo "[ERROR] CI GATE FAILED. See ${LOG_PREFIX}_xsim.log"
    exit 1
fi
