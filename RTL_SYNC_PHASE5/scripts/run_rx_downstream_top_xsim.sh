#!/usr/bin/env bash
# run_rx_downstream_top_xsim.sh
#
# RX DOWNSTREAM full-chain integration gate: drive the golden 4032-sample
# slot (tx_slot_iq_4032.hex) + pilot_rom into rx_downstream_top with the
# REAL Xilinx xfft_N 9.1 IP under xsim, collect the demod bits and verify
# BER == 0 vs golden/rx_downstream/tx_bits.txt.
#
#   PASS  -> "RXDS_GATE: PASS"   (TB prints "RESULT: PASS")
#   FAIL  -> "RXDS_GATE: FAIL"
#
# Uses Vivado 2021.1 to match the pre-compiled simlib (sim_out/xsim_simlib)
# and the build_zcu216_ip IP sim sources vintage, exactly like the per-
# module RX-FFT gate (scripts/run_rx_fft_frontend_xsim.sh).
#
# Outputs:
#   vivado_xsim/logs/rxds_{compile,elab,sim}.log
#   vivado_xsim/reports/rxds_gate.txt
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

VIVADO_DIR="${VIVADO_DIR:-/opt/Xilinx/Vivado/2021.1}"
if [[ ! -x "$VIVADO_DIR/bin/vivado" ]]; then
    echo "[rxds] ERROR: vivado not found at $VIVADO_DIR/bin/vivado" >&2
    echo "[rxds]        set VIVADO_DIR to a 2021.1 install." >&2
    exit 2
fi

mkdir -p vivado_xsim/logs vivado_xsim/reports

set +u
source "$VIVADO_DIR/settings64.sh" 2>/dev/null || true
set -u

vivado -mode batch \
    -source vivado_xsim/tcl/run_rx_downstream_top_unit.tcl \
    -log vivado_xsim/logs/rxds_vivado.log \
    -journal vivado_xsim/logs/rxds_vivado.jou
RC=$?

echo "----------------------------------------------------------------------"
cat vivado_xsim/reports/rxds_gate.txt 2>/dev/null || echo "[rxds] no gate file produced"
exit $RC
