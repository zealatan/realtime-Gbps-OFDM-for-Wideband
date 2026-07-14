#!/usr/bin/env bash
# run_rx_fft_frontend_rand_xsim.sh
#
# RX FFT FRONT-END ROBUST multi-vector gate: drive rx_fft_frontend with N
# random + edge-case 4032-sample slots (golden/rx_fft_rand/*) and the REAL
# Xilinx xfft_N 9.1 IP under xsim; compare every 12x256 freq block to the
# integer-domain golden.
#
#   PASS  -> "RXFFT_RAND_GATE: PASS"  (TB prints "RESULT: PASS")
#   FAIL  -> "RXFFT_RAND_GATE: FAIL"
#
# Regenerate vectors first (deterministic seed):
#   python3 scripts/gen_rx_fft_frontend_random.py
#
# Uses Vivado 2021.1 to match the pre-compiled simlib, exactly like the
# single-frame run_rx_fft_frontend_xsim.sh gate.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

# (re)generate the random vectors if missing
if [[ ! -f golden/rx_fft_rand/slots_in.hex ]]; then
    echo "[rxfft-rand] generating random vectors..."
    python3 scripts/gen_rx_fft_frontend_random.py
fi

VIVADO_DIR="${VIVADO_DIR:-/opt/Xilinx/Vivado/2021.1}"
if [[ ! -x "$VIVADO_DIR/bin/vivado" ]]; then
    echo "[rxfft-rand] ERROR: vivado not found at $VIVADO_DIR/bin/vivado" >&2
    echo "[rxfft-rand]        set VIVADO_DIR to a 2021.1 install." >&2
    exit 2
fi

mkdir -p vivado_xsim/logs vivado_xsim/reports

set +u
source "$VIVADO_DIR/settings64.sh" 2>/dev/null || true
set -u

vivado -mode batch \
    -source vivado_xsim/tcl/run_rx_fft_frontend_rand_unit.tcl \
    -log vivado_xsim/logs/rxfft_rand_vivado.log \
    -journal vivado_xsim/logs/rxfft_rand_vivado.jou
RC=$?

echo "----------------------------------------------------------------------"
cat vivado_xsim/reports/rxfft_rand_gate.txt 2>/dev/null || echo "[rxfft-rand] no gate file produced"
exit $RC
