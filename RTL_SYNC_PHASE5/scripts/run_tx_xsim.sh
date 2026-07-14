#!/usr/bin/env bash
# run_tx_xsim.sh [gate]
#
# OFDM-TX sim gates with the REAL Xilinx xfft_N 9.1 IP under xsim
# (Vivado 2021.1, matching the pre-compiled simlib + build_zcu216_ip IP
# sim sources, exactly like the RX-FFT-frontend gate).
#
#   gate (default: all):
#     map    - tx_subcarrier_map_tb   (spectrum EXACT vs tx_spec_in.hex)
#     ifft   - tx_ifft_frontend_tb    (IDFT+CP vs tx_dsym_out.hex, TOL 64)
#     top    - tx_ofdm_top_tb         (full 4032 slot vs tx_slot_4032.hex)
#     loop   - tx_rx_loop_tb          (TX->RX end-to-end, BER 0)
#     all    - run all four in order
#
# Outputs: vivado_xsim/logs/tx_<tag>_{compile,elab,sim}.log
#          vivado_xsim/reports/tx_<tag>_gate.txt
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

VIVADO_DIR="${VIVADO_DIR:-/opt/Xilinx/Vivado/2021.1}"
if [[ ! -x "$VIVADO_DIR/bin/vivado" ]]; then
    echo "[tx] ERROR: vivado not found at $VIVADO_DIR/bin/vivado" >&2
    echo "[tx]        set VIVADO_DIR to a 2021.1 install." >&2
    exit 2
fi
mkdir -p vivado_xsim/logs vivado_xsim/reports
set +u; source "$VIVADO_DIR/settings64.sh" 2>/dev/null || true; set -u

# regenerate the TX ROMs + stage golden (deterministic; safe to re-run)
python3 scripts/gen_tx_roms.py >/dev/null 2>&1 || true

TX_MAP="rtl/tx_subcarrier_map.v"
TX_IFFT="rtl/tx_ifft_frontend.v"
TX_TOP="rtl/tx_ofdm_top.v rtl/tx_subcarrier_map.v rtl/tx_ifft_frontend.v"
RX_RTL="rtl/rx_downstream_top.v rtl/rx_fft_frontend.v rtl/rx_ch_est.v rtl/rx_equalizer.v rtl/rx_eq_complex_div.v rtl/rx_demod_16qam.v"

run_one() {
    local tag="$1" tb_name="$2" tb_file="$3" rtl_list="$4"
    echo "######################################################################"
    echo "# TX gate: $tag  ($tb_name)"
    echo "######################################################################"
    TX_GATE_TAG="$tag" TX_TB_NAME="$tb_name" TX_TB_FILE="$tb_file" \
    TX_RTL_LIST="$rtl_list" \
    vivado -mode batch \
        -source vivado_xsim/tcl/run_tx_unit.tcl \
        -log vivado_xsim/logs/tx_${tag}_vivado.log \
        -journal vivado_xsim/logs/tx_${tag}_vivado.jou
    local rc=$?
    echo "----------------------------------------------------------------------"
    cat vivado_xsim/reports/tx_${tag}_gate.txt 2>/dev/null || echo "[tx] no gate file for $tag"
    return $rc
}

GATE="${1:-all}"
rc_all=0
case "$GATE" in
    map)  run_one TXMAP  tx_subcarrier_map_tb tb/tx_subcarrier_map_tb.sv "$TX_MAP"  || rc_all=1 ;;
    ifft) run_one TXIFFT tx_ifft_frontend_tb  tb/tx_ifft_frontend_tb.sv  "$TX_IFFT" || rc_all=1 ;;
    top)  run_one TXTOP  tx_ofdm_top_tb       tb/tx_ofdm_top_tb.sv       "$TX_TOP"  || rc_all=1 ;;
    loop) run_one TXLOOP tx_rx_loop_tb        tb/tx_rx_loop_tb.sv        "$TX_TOP $RX_RTL" || rc_all=1 ;;
    all)
        run_one TXMAP  tx_subcarrier_map_tb tb/tx_subcarrier_map_tb.sv "$TX_MAP"  || rc_all=1
        run_one TXIFFT tx_ifft_frontend_tb  tb/tx_ifft_frontend_tb.sv  "$TX_IFFT" || rc_all=1
        run_one TXTOP  tx_ofdm_top_tb       tb/tx_ofdm_top_tb.sv       "$TX_TOP"  || rc_all=1
        run_one TXLOOP tx_rx_loop_tb        tb/tx_rx_loop_tb.sv        "$TX_TOP $RX_RTL" || rc_all=1
        ;;
    *) echo "[tx] unknown gate '$GATE' (map|ifft|top|loop|all)"; exit 2 ;;
esac

echo "======================================================================"
if [[ $rc_all -eq 0 ]]; then echo "TX_XSIM: ALL PASS"; else echo "TX_XSIM: FAIL (rc=$rc_all)"; fi
exit $rc_all
