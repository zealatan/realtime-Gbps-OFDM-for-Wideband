#!/usr/bin/env bash
# run_rx_ch_est_sim.sh -- compile + simulate rx_ch_est unit TB.
#   --sim xsim     (default, OFFICIAL) | iverilog (SANITY only)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SIM="xsim"
while [[ $# -gt 0 ]]; do case $1 in --sim) SIM="$2"; shift 2;; *) echo "bad arg $1"; exit 1;; esac; done

LOGS="${ROOT}/logs"; SIM_OUT="${ROOT}/sim_out"
mkdir -p "${LOGS}" "${SIM_OUT}"
cd "${ROOT}"
RTL="${ROOT}/rtl/rx_ch_est.v"
TB="${ROOT}/tb/rx_ch_est_tb.sv"

if [[ "${SIM}" == "iverilog" ]]; then
    echo "=== iverilog (SANITY only) ==="
    iverilog -g2012 -I "${ROOT}/rtl" -o "${SIM_OUT}/rx_ch_est.vvp" "${RTL}" "${TB}" \
        2>&1 | tee "${LOGS}/rx_ch_est_compile.log"
    vvp "${SIM_OUT}/rx_ch_est.vvp" 2>&1 | tee "${LOGS}/rx_ch_est_sim.log"
elif [[ "${SIM}" == "xsim" ]]; then
    if [[ -z "${XILINX_VIVADO:-}" ]] && ! command -v xvlog &>/dev/null; then
        for s in /opt/Xilinx/Vivado/*/settings64.sh /tools/Xilinx/Vivado/*/settings64.sh; do
            [[ -f "$s" ]] && source "$s" && break
        done
    fi
    command -v xvlog &>/dev/null || { echo "CI_GATE: BLOCKED_XSIM_UNAVAILABLE"; exit 2; }
    WORK="${SIM_OUT}/rx_ch_est_work"; mkdir -p "${WORK}"; cd "${WORK}"
    xvlog -i "${ROOT}/rtl" "${RTL}" 2>&1 | tee "${LOGS}/rx_ch_est_xvlog.log"
    xvlog --sv -i "${ROOT}/rtl" "${TB}" 2>&1 | tee -a "${LOGS}/rx_ch_est_xvlog.log"
    # override W_ROM to absolute path so the DUT $readmemh resolves from WORK cwd
    xelab -debug off -top rx_ch_est_tb -snapshot rx_ch_est_snap \
        -generic_top "W_ROM=\"${ROOT}/rtl/rx_ch_est_rom/ce_interp_W.hex\"" \
        2>&1 | tee "${LOGS}/rx_ch_est_xelab.log"
    xsim rx_ch_est_snap --runall \
        -testplusarg "GOLD=${ROOT}/golden/rx_downstream" \
        2>&1 | tee "${LOGS}/rx_ch_est_sim.log" || true
fi

LOG="${LOGS}/rx_ch_est_sim.log"
echo "=== GATE ==="
if grep -q "CI GATE: PASSED" "${LOG}"; then echo "CI_GATE: PASS (${SIM})"; exit 0
else echo "CI_GATE: FAIL (${SIM})"; exit 1; fi
