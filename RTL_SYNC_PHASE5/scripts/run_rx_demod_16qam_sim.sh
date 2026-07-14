#!/usr/bin/env bash
# run_rx_demod_16qam_sim.sh
# Compile + simulate rx_demod_16qam self-checking TB with xsim (Vivado).
# Golden $readmemh / $fopen paths are relative to ROOT, so run from ROOT.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${SCRIPT_DIR}/.."
cd "${ROOT}"

VIV="${VIV:-/opt/Xilinx/Vivado/2021.1}"
export PATH="${VIV}/bin:${PATH}"

LOGDIR="${ROOT}/sim_out/rx_demod_16qam"
rm -rf "${LOGDIR}" "${ROOT}/xsim.dir" "${ROOT}/.Xil"
mkdir -p "${LOGDIR}"

echo "[demod] xvlog ..."
xvlog --nolog -sv \
    "${ROOT}/rtl/rx_demod_16qam.v" \
    "${ROOT}/tb/rx_demod_16qam_tb.sv" 2>&1 | tee "${LOGDIR}/xvlog.log"

echo "[demod] xelab ..."
xelab --nolog -debug typical work.rx_demod_16qam_tb \
    -s demod_sim 2>&1 | tee "${LOGDIR}/xelab.log"

echo "[demod] xsim ..."
xsim --nolog demod_sim -runall 2>&1 | tee "${LOGDIR}/xsim.log"

echo "[demod] result:"
grep -E "RESULT:|BER|bit errors|FATAL|WARN" "${LOGDIR}/xsim.log" || true
