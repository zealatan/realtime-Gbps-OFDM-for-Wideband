#!/usr/bin/env bash
# run_rx_eq_div_xsim.sh — ZF equalizer complex-divider unit gate (xsim)
#
# UUT : rtl/rx_eq_complex_div.v  (+ rtl/rx_equalizer_recip_lut.hex)
# TB  : tb/rx_eq_complex_div_tb.sv
# Golden : golden/rx_downstream/{fft_out,hest,eq_out}.hex + data_indx.txt
#
# GATE OUTPUT (exactly one): GATE_RX_EQ_DIV_UNIT: PASS|FAIL
# EXIT 0 iff PASS.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT}"

XSIM_BIN="${XSIM_BIN:-/opt/Xilinx/Vivado/2021.1/bin}"
WORK="${ROOT}/sim_out/rx_eq_div_xsim"
G="${ROOT}/golden/rx_downstream"

rm -rf "${WORK}"; mkdir -p "${WORK}/golden_in" "${WORK}/golden_lut"
cp "${G}/fft_out.hex" "${G}/hest.hex" "${G}/eq_out.hex" "${WORK}/golden_in/"
tr ',' '\n' < "${G}/data_indx.txt" | grep -v '^$' > "${WORK}/golden_in/data_indx_lines.txt"
cp "${ROOT}/rtl/rx_equalizer_recip_lut.hex" "${WORK}/golden_lut/"

cd "${WORK}"
export PATH="${XSIM_BIN}:${PATH}"

xvlog -sv "${ROOT}/rtl/rx_eq_complex_div.v" "${ROOT}/rtl/rx_equalizer.v" \
          "${ROOT}/tb/rx_eq_complex_div_tb.sv" "${ROOT}/tb/rx_equalizer_tb.sv" \
      > xvlog.log 2>&1 || { echo "GATE_RX_EQ_DIV_UNIT: FAIL (xvlog)"; tail -30 xvlog.log; exit 1; }

FAILS=0
# --- core divider gate ---
xelab -debug off rx_eq_complex_div_tb -s eq_sim \
      > xelab1.log 2>&1 || { echo "GATE_RX_EQ_DIV_UNIT: FAIL (xelab)"; tail -30 xelab1.log; exit 1; }
xsim eq_sim -R > xsim_div.log 2>&1
grep -E "GATE_RX_EQ_DIV_UNIT|worst|drove" xsim_div.log
grep -q "GATE_RX_EQ_DIV_UNIT: PASS" xsim_div.log || FAILS=$((FAILS+1))

# --- AXI-Stream wrapper gate (random backpressure) ---
xelab -debug off rx_equalizer_tb -s ax_sim \
      > xelab2.log 2>&1 || { echo "GATE_RX_EQ_AXIS_UNIT: FAIL (xelab)"; tail -30 xelab2.log; exit 1; }
xsim ax_sim -R > xsim_axis.log 2>&1
grep -E "GATE_RX_EQ_AXIS_UNIT|received" xsim_axis.log
grep -q "GATE_RX_EQ_AXIS_UNIT: PASS" xsim_axis.log || FAILS=$((FAILS+1))

[ "${FAILS}" -eq 0 ] && exit 0 || exit 1
