#!/usr/bin/env bash
# run_tx_rx_impair.sh  --  PHASE-2 diverse-impairment regression driver.
# -------------------------------------------------------------------------
# Drives tb/tx_rx_impair_tb.sv through the proven run_tx_unit.tcl xsim flow
# (REAL Xilinx xfft_N 9.1 IP) across the test matrix:
#
#   modulation x { CLEAN, AWGN sweep, MULTIPATH }
#
# for QPSK / 16-QAM / 64-QAM / 256-QAM.  CFO (which needs the real sync
# chain) is covered separately by run_rx_cfo_allmods.sh.
#
# Usage:
#   run_tx_rx_impair.sh clean      # 4 mods, IMP=0, BER must be 0
#   run_tx_rx_impair.sh awgn       # 4 mods, IMP=1, per-mod SNR sweep
#   run_tx_rx_impair.sh channel    # 4 mods, IMP=2, multipath, BER ~0
#   run_tx_rx_impair.sh all        # all three (default)
#
# Emits a parseable summary; gate tokens:
#   IMPAIR_CLEAN_GATE:   PASS|FAIL   (all 4 mods clean BER=0)
#   IMPAIR_CHANNEL_GATE: PASS|FAIL   (all 4 mods multipath BER=0)
#   the AWGN sweep is informative (BER-vs-SNR table printed, not gated).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

VIVADO_DIR="${VIVADO_DIR:-/opt/Xilinx/Vivado/2021.1}"
if [[ ! -x "$VIVADO_DIR/bin/vivado" ]]; then
    echo "[impair] ERROR: vivado not at $VIVADO_DIR/bin/vivado" >&2
    exit 2
fi
mkdir -p vivado_xsim/logs vivado_xsim/reports
set +u; source "$VIVADO_DIR/settings64.sh" 2>/dev/null || true; set -u

python3 scripts/gen_tx_roms.py            >/dev/null 2>&1 || true
python3 scripts/rx_downstream_ref.py      >/dev/null 2>&1 || true

TX_TOP="rtl/tx_ofdm_top.v rtl/tx_subcarrier_map.v rtl/tx_ifft_frontend.v"
RX_RTL="rtl/rx_downstream_top.v rtl/rx_fft_frontend.v rtl/rx_ch_est.v rtl/rx_equalizer.v rtl/rx_eq_complex_div.v rtl/rx_demod_qam.v"
declare -a NAMES=(qpsk 16qam 64qam 256qam)

# Per-mod AWGN SNR sweep (dB), spanning each modulation's threshold region.
# NOTE: this is REAL fixed-point RTL with pilot-based ZF channel estimation;
# the noise also corrupts the pilots, so the ZF EQ enhances noise and the
# operating point sits ~8-10 dB above the AWGN-ideal soft-decision curve.
# The sweeps are chosen to span each mod from "many errors" down toward 0,
# and to expose the modulation-order ordering (QPSK lowest, 256-QAM highest).
declare -A SNRSET
SNRSET[0]="8 12 16 20"
SNRSET[1]="14 18 22 26"
SNRSET[2]="20 24 28 32"
SNRSET[3]="26 30 34 38"

# run one xsim point : args  TAG  MOD  IMP  SNRDB  SEED
run_point() {
    local tag="$1" M="$2" IMP="$3" SNRDB="$4" SEED="$5"
    TX_GATE_TAG="$tag" TX_TB_NAME="tx_rx_impair_tb" TX_TB_FILE="tb/tx_rx_impair_tb.sv" \
    TX_RTL_LIST="$TX_TOP $RX_RTL" TX_PLUSARGS="MOD=$M IMP=$IMP SNRDB=$SNRDB SEED=$SEED" \
    vivado -mode batch \
        -source vivado_xsim/tcl/run_tx_unit.tcl \
        -log vivado_xsim/logs/tx_${tag}_vivado.log \
        -journal vivado_xsim/logs/tx_${tag}_vivado.jou >/dev/null 2>&1
    grep -m1 "^IMP_RESULT" "vivado_xsim/logs/tx_${tag}_sim.log" 2>/dev/null
}

MODE="${1:-all}"
SUMMARY="vivado_xsim/reports/impair_summary.txt"
: > "$SUMMARY"

clean_overall=0
channel_overall=0

do_clean() {
    echo "###### CLEAN loopback (IMP=0) : BER must be 0 ######" | tee -a "$SUMMARY"
    for M in 0 1 2 3; do
        line=$(run_point "IMP_CLEAN_M${M}" "$M" 0 100 1)
        echo "  ${NAMES[$M]}: $line" | tee -a "$SUMMARY"
        echo "$line" | grep -q -- "-> PASS" || clean_overall=1
    done
}

do_channel() {
    echo "###### MULTIPATH 3-tap channel (IMP=2) : pilot CE + ZF EQ -> BER ~0 ######" | tee -a "$SUMMARY"
    for M in 0 1 2 3; do
        line=$(run_point "IMP_CHAN_M${M}" "$M" 2 100 1)
        echo "  ${NAMES[$M]}: $line" | tee -a "$SUMMARY"
        echo "$line" | grep -q -- "-> PASS" || channel_overall=1
    done
}

do_awgn() {
    echo "###### AWGN waterfall (IMP=1) : per-mod BER-vs-SNR ######" | tee -a "$SUMMARY"
    for M in 0 1 2 3; do
        for SNR in ${SNRSET[$M]}; do
            line=$(run_point "IMP_AWGN_M${M}_S${SNR}" "$M" 1 "$SNR" "$((SNR*7+M))")
            echo "  ${NAMES[$M]} SNR=${SNR}dB: $line" | tee -a "$SUMMARY"
        done
    done
}

case "$MODE" in
    clean)   do_clean ;;
    channel) do_channel ;;
    awgn)    do_awgn ;;
    all)     do_clean; do_channel; do_awgn ;;
    *) echo "usage: $0 {clean|channel|awgn|all}"; exit 2 ;;
esac

echo "======================================================================" | tee -a "$SUMMARY"
if [[ "$MODE" == "clean" || "$MODE" == "all" ]]; then
    [[ $clean_overall -eq 0 ]] && echo "IMPAIR_CLEAN_GATE: PASS" | tee -a "$SUMMARY" \
                               || echo "IMPAIR_CLEAN_GATE: FAIL" | tee -a "$SUMMARY"
fi
if [[ "$MODE" == "channel" || "$MODE" == "all" ]]; then
    [[ $channel_overall -eq 0 ]] && echo "IMPAIR_CHANNEL_GATE: PASS" | tee -a "$SUMMARY" \
                                 || echo "IMPAIR_CHANNEL_GATE: FAIL" | tee -a "$SUMMARY"
fi
echo "======================================================================" | tee -a "$SUMMARY"

rc=0
[[ "$MODE" == "clean"   && $clean_overall   -ne 0 ]] && rc=1
[[ "$MODE" == "channel" && $channel_overall -ne 0 ]] && rc=1
[[ "$MODE" == "all" && ( $clean_overall -ne 0 || $channel_overall -ne 0 ) ]] && rc=1
exit $rc
