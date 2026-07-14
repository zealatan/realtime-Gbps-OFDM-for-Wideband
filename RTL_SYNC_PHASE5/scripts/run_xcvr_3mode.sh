#!/usr/bin/env bash
# run_xcvr_3mode.sh — 3-mode (TX/RX/LOOPBACK) ofdm_transceiver_top gate.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VIVADO_DIR="${VIVADO_DIR:-/opt/Xilinx/Vivado/2021.1}"
export XFFT_TARGET_PART="${XFFT_TARGET_PART:-xczu9eg-ffvb1156-2-e}"
python3 "$ROOT/scripts/gen_p5_bk_conj_fft512_rom.py" >/dev/null
cd "$ROOT"
set +e; set +u
source "$VIVADO_DIR/settings64.sh" 2>/dev/null || true
set -u; set -e
vivado -mode batch -source vivado_xsim/tcl/run_xcvr_3mode.tcl \
    -log vivado_xsim/logs/xcvr_3mode_vivado.log \
    -journal vivado_xsim/logs/xcvr_3mode_vivado.jou
RC=$?
echo "----------------------------------------------------------------------"
cat vivado_xsim/reports/xcvr_3mode_gate.txt 2>/dev/null || echo "[xcvr-3mode] no gate file produced"
exit $RC
