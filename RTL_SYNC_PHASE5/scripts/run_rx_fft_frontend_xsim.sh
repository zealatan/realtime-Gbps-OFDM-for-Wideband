#!/usr/bin/env bash
# run_rx_fft_frontend_xsim.sh
#
# RX FFT FRONT-END unit gate: drive rx_fft_frontend with the golden
# 4032-sample slot and the REAL Xilinx xfft_N 9.1 IP under xsim, compare
# the 12x256 freq bins to golden/rx_downstream/fft_out.hex.
#
#   PASS  -> "RXFFT_GATE: PASS"  (TB prints "RESULT: PASS")
#   FAIL  -> "RXFFT_GATE: FAIL"
#
# Uses Vivado 2021.1 to match the pre-compiled simlib (sim_out/xsim_simlib)
# and the build_zcu216_ip IP sim sources vintage, exactly like the P5-D gate.
#
# Outputs:
#   vivado_xsim/logs/rxfft_{compile,elab,sim}.log
#   vivado_xsim/reports/rxfft_gate.txt
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

VIVADO_DIR="${VIVADO_DIR:-/opt/Xilinx/Vivado/2021.1}"
if [[ ! -x "$VIVADO_DIR/bin/vivado" ]]; then
    echo "[rxfft] ERROR: vivado not found at $VIVADO_DIR/bin/vivado" >&2
    echo "[rxfft]        set VIVADO_DIR to a 2021.1 install." >&2
    exit 2
fi

mkdir -p vivado_xsim/logs vivado_xsim/reports

# settings64 may source DocNav helpers that print noise; tolerate it.
set +u
source "$VIVADO_DIR/settings64.sh" 2>/dev/null || true
set -u

vivado -mode batch \
    -source vivado_xsim/tcl/run_rx_fft_frontend_unit.tcl \
    -log vivado_xsim/logs/rxfft_vivado.log \
    -journal vivado_xsim/logs/rxfft_vivado.jou
RC=$?

echo "----------------------------------------------------------------------"
cat vivado_xsim/reports/rxfft_gate.txt 2>/dev/null || echo "[rxfft] no gate file produced"
exit $RC
