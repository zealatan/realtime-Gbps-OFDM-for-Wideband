#!/usr/bin/env bash
# run_tx_rx_loop_allmods.sh
# -------------------------------------------------------------------------
# Phase-1 multi-modulation CLEAN digital loopback gate:
#   tx_ofdm_top (mod_sel) -> rx_downstream_top (mod_sel) -> BER
# run under xsim with the REAL Xilinx xfft 9.1 IPs, for QPSK / 16-QAM /
# 64-QAM / 256-QAM (mod_sel = 0..3).  CLEAN loopback => BER must be 0 for
# all four.  Drives tb/tx_rx_loop_tb.sv with +MOD=<n>.
#
# Emits per-mod gate files vivado_xsim/reports/tx_TXLOOP_M<n>_gate.txt and a
# combined PASS/FAIL summary.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

VIVADO_DIR="${VIVADO_DIR:-/opt/Xilinx/Vivado/2021.1}"
if [[ ! -x "$VIVADO_DIR/bin/vivado" ]]; then
    echo "[loop-allmods] ERROR: vivado not at $VIVADO_DIR/bin/vivado" >&2
    exit 2
fi
mkdir -p vivado_xsim/logs vivado_xsim/reports
set +u; source "$VIVADO_DIR/settings64.sh" 2>/dev/null || true; set -u

# regen TX ROMs + per-mod golden (deterministic)
python3 scripts/gen_tx_roms.py            >/dev/null 2>&1 || true
python3 scripts/rx_downstream_ref.py      >/dev/null 2>&1 || true

TX_TOP="rtl/tx_ofdm_top.v rtl/tx_subcarrier_map.v rtl/tx_ifft_frontend.v"
RX_RTL="rtl/rx_downstream_top.v rtl/rx_fft_frontend.v rtl/rx_ch_est.v rtl/rx_equalizer.v rtl/rx_eq_complex_div.v rtl/rx_demod_qam.v"

declare -a NAMES=(qpsk 16qam 64qam 256qam)
overall=0
declare -a RESULTS=()
for M in 0 1 2 3; do
    tag="TXLOOP_M${M}"
    echo "######################################################################"
    echo "# CLEAN loopback gate: MOD=$M (${NAMES[$M]})"
    echo "######################################################################"
    TX_GATE_TAG="$tag" TX_TB_NAME="tx_rx_loop_tb" TX_TB_FILE="tb/tx_rx_loop_tb.sv" \
    TX_RTL_LIST="$TX_TOP $RX_RTL" TX_PLUSARGS="MOD=$M" \
    vivado -mode batch \
        -source vivado_xsim/tcl/run_tx_unit.tcl \
        -log vivado_xsim/logs/tx_${tag}_vivado.log \
        -journal vivado_xsim/logs/tx_${tag}_vivado.jou
    rc=$?
    echo "----------------------------------------------------------------------"
    if grep -q "RESULT: PASS" "vivado_xsim/logs/tx_${tag}_sim.log" 2>/dev/null; then
        ber=$(grep -m1 "bit errors" "vivado_xsim/logs/tx_${tag}_sim.log" 2>/dev/null | tr -dc '0-9 ' )
        RESULTS+=("MOD=$M ${NAMES[$M]} : PASS  (bit errors=$ber)")
    else
        RESULTS+=("MOD=$M ${NAMES[$M]} : FAIL (rc=$rc)")
        overall=1
    fi
done

echo "======================================================================"
echo " PHASE-1 MULTI-MOD CLEAN LOOPBACK SUMMARY"
for r in "${RESULTS[@]}"; do echo "   $r"; done
if [[ $overall -eq 0 ]]; then echo "TXRX_LOOP_ALLMODS: PASS (all four BER=0)"; else echo "TXRX_LOOP_ALLMODS: FAIL"; fi
echo "======================================================================"
exit $overall
