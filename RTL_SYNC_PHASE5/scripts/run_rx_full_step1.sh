#!/usr/bin/env bash
# run_rx_full_step1.sh
# FULL-RX INTEGRATION STEP 1 gate: SYNC -> FFT front-end seam (rx_full_top).
# Real Xilinx xfft 9.1 IPs (xsim). Mirrors run_p5_d_continuous_wrapper.sh.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VIVADO_DIR="${VIVADO_DIR:-/home/zealatan/Downloads/Vivado/2022.2}"
export XFFT_TARGET_PART="${XFFT_TARGET_PART:-xczu9eg-ffvb1156-2-e}"

if [[ ! -x "$VIVADO_DIR/bin/vivado" ]]; then
    echo "[rx-full-step1] ERROR: vivado not at $VIVADO_DIR/bin/vivado" >&2
    exit 2
fi
# Ensure the B[k] conj-FFT ROM exists (the TB $readmemh's it hierarchically).
python3 "$ROOT/scripts/gen_p5_bk_conj_fft512_rom.py" >/dev/null

cd "$ROOT"
set +e
# shellcheck disable=SC1090
source "$VIVADO_DIR/settings64.sh"
set -e
vivado -mode batch -source vivado_xsim/tcl/run_rx_full_step1.tcl \
    -log vivado_xsim/logs/rx_full_step1_vivado.log \
    -journal vivado_xsim/logs/rx_full_step1_vivado.jou
