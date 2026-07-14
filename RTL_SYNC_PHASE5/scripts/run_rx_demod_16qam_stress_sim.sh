#!/usr/bin/env bash
# run_rx_demod_16qam_stress_sim.sh
# Generate stress vectors, then compile + simulate the rx_demod_16qam
# stress self-checking TB with xsim (Vivado 2021.1, part xczu49dr).
# Golden $fopen paths are relative to ROOT, so run from ROOT.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${SCRIPT_DIR}/.."
cd "${ROOT}"

VIV="${VIV:-/opt/Xilinx/Vivado/2021.1}"
export PATH="${VIV}/bin:${PATH}"

echo "[stress] regenerating stress vectors ..."
python3 "${SCRIPT_DIR}/gen_rx_demod_16qam_stress.py"

LOGDIR="${ROOT}/sim_out/rx_demod_16qam_stress"
rm -rf "${LOGDIR}" "${ROOT}/xsim.dir" "${ROOT}/.Xil"
mkdir -p "${LOGDIR}"

echo "[stress] xvlog ..."
xvlog --nolog -sv \
    "${ROOT}/rtl/rx_demod_16qam.v" \
    "${ROOT}/tb/rx_demod_16qam_stress_tb.sv" 2>&1 | tee "${LOGDIR}/xvlog.log"

echo "[stress] xelab ..."
xelab --nolog -debug typical work.rx_demod_16qam_stress_tb \
    -s demod_stress_sim 2>&1 | tee "${LOGDIR}/xelab.log"

echo "[stress] xsim ..."
xsim --nolog demod_stress_sim -runall 2>&1 | tee "${LOGDIR}/xsim.log"

echo "[stress] result:"
grep -E "RESULT:|BER|vector errors|MISMATCH|FATAL|loaded" "${LOGDIR}/xsim.log" || true
