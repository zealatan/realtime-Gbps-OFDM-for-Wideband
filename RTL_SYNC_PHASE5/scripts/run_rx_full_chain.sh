#!/usr/bin/env bash
# run_rx_full_chain.sh
# FULL-RX INTEGRATION STEP 2 gate: SYNC -> FULL DOWNSTREAM (rx_full_chain_top).
# Real Xilinx xfft 9.1 IPs (xsim).  Mirrors run_rx_full_step1.sh; the proven
# step-1 flow ran under the locally installed Vivado 2021.1 (sim part falls
# back to an installed zynquplus variant for functional sim — fine).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VIVADO_DIR="${VIVADO_DIR:-/opt/Xilinx/Vivado/2021.1}"
export XFFT_TARGET_PART="${XFFT_TARGET_PART:-xczu9eg-ffvb1156-2-e}"

if [[ ! -x "$VIVADO_DIR/bin/vivado" ]]; then
    echo "[rx-full-chain] ERROR: vivado not at $VIVADO_DIR/bin/vivado" >&2
    exit 2
fi
# Ensure the B[k] conj-FFT ROM exists (the TB $readmemh's it hierarchically).
python3 "$ROOT/scripts/gen_p5_bk_conj_fft512_rom.py" >/dev/null

cd "$ROOT"
set +e
set +u
# shellcheck disable=SC1090
source "$VIVADO_DIR/settings64.sh" 2>/dev/null || true
set -u
set -e
vivado -mode batch -source vivado_xsim/tcl/run_rx_full_chain.tcl \
    -log vivado_xsim/logs/rx_full_chain_vivado.log \
    -journal vivado_xsim/logs/rx_full_chain_vivado.jou
RC=$?
echo "----------------------------------------------------------------------"
cat vivado_xsim/reports/rx_full_chain_gate.txt 2>/dev/null || echo "[rx-full-chain] no gate file produced"
exit $RC
