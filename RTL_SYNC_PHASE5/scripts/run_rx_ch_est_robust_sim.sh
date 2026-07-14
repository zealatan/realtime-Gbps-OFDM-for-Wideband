#!/usr/bin/env bash
# run_rx_ch_est_robust_sim.sh -- compile + simulate the ROBUST rx_ch_est TB
# (N non-identity frequency-selective channels). Default = xsim (OFFICIAL).
#   --sim xsim     (default) | iverilog (SANITY only)
# Part: xczu49dr-ffvf1760-2-e (ZCU216). Functional xsim is part-agnostic for
# this pure-RTL DUT (no Xilinx IP), but we pass the part for the record.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SIM="xsim"
PART="xczu49dr-ffvf1760-2-e"
while [[ $# -gt 0 ]]; do case $1 in --sim) SIM="$2"; shift 2;; *) echo "bad arg $1"; exit 1;; esac; done

LOGS="${ROOT}/logs"; SIM_OUT="${ROOT}/sim_out"
mkdir -p "${LOGS}" "${SIM_OUT}"
cd "${ROOT}"
RTL="${ROOT}/rtl/rx_ch_est.v"
TB="${ROOT}/tb/rx_ch_est_robust_tb.sv"
GOLD="${ROOT}/golden/rx_ch_est_robust"

# regenerate golden (deterministic) so the TB always matches the model
python3 "${ROOT}/scripts/gen_rx_ch_est_robust.py" > "${LOGS}/rx_ch_est_robust_gen.log" 2>&1 || \
    { echo "GEN FAILED"; cat "${LOGS}/rx_ch_est_robust_gen.log"; exit 3; }
NCASE=$(grep -m1 '^N=' "${GOLD}/meta.txt" | cut -d= -f2)
echo "=== robust golden: ${NCASE} cases ==="

if [[ "${SIM}" == "iverilog" ]]; then
    echo "=== iverilog (SANITY only) ==="
    iverilog -g2012 -I "${ROOT}/rtl" -P rx_ch_est_robust_tb.NCASE=${NCASE} \
        -o "${SIM_OUT}/rx_ch_est_robust.vvp" "${RTL}" "${TB}" \
        2>&1 | tee "${LOGS}/rx_ch_est_robust_compile.log"
    vvp "${SIM_OUT}/rx_ch_est_robust.vvp" 2>&1 | tee "${LOGS}/rx_ch_est_robust_sim.log"
elif [[ "${SIM}" == "xsim" ]]; then
    if [[ -z "${XILINX_VIVADO:-}" ]] && ! command -v xvlog &>/dev/null; then
        for s in /opt/Xilinx/Vivado/*/settings64.sh /tools/Xilinx/Vivado/*/settings64.sh; do
            [[ -f "$s" ]] && source "$s" && break
        done
    fi
    command -v xvlog &>/dev/null || { echo "CI_GATE: BLOCKED_XSIM_UNAVAILABLE"; exit 2; }
    WORK="${SIM_OUT}/rx_ch_est_robust_work"; mkdir -p "${WORK}"; cd "${WORK}"
    xvlog -i "${ROOT}/rtl" "${RTL}" 2>&1 | tee "${LOGS}/rx_ch_est_robust_xvlog.log"
    xvlog --sv -i "${ROOT}/rtl" "${TB}" 2>&1 | tee -a "${LOGS}/rx_ch_est_robust_xvlog.log"
    xelab -debug off -top rx_ch_est_robust_tb -snapshot rx_ch_est_robust_snap \
        -generic_top "W_ROM=\"${ROOT}/rtl/rx_ch_est_rom/ce_interp_W.hex\"" \
        -generic_top "NCASE=${NCASE}" \
        2>&1 | tee "${LOGS}/rx_ch_est_robust_xelab.log"
    xsim rx_ch_est_robust_snap --runall \
        -testplusarg "GOLD=${GOLD}" \
        2>&1 | tee "${LOGS}/rx_ch_est_robust_sim.log" || true
fi

LOG="${LOGS}/rx_ch_est_robust_sim.log"
echo "=== GATE (part ${PART}) ==="
if grep -q "CI GATE: PASSED" "${LOG}"; then echo "CI_GATE: PASS (${SIM})"; exit 0
else echo "CI_GATE: FAIL (${SIM})"; exit 1; fi
