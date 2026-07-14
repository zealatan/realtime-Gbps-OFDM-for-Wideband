#!/usr/bin/env bash
# run_rx_cfo_allmods.sh  --  PHASE-2 CFO robustness across modulations.
# -------------------------------------------------------------------------
# Drives tb/rx_cfo_allmods_tb.sv (sync chain CFO correction, end to end)
# for QPSK / 16-QAM / 64-QAM / 256-QAM, applying a fixed carrier frequency
# offset (default EPS=0.25 subcarrier).  The FROZEN synchronizer's frac+int
# CFO estimator must correct it -> BER must be 0 for every modulation.
#
#   $1 (CFO_MILLI) : EPS*1000 in subcarrier-spacing units (default 250).
#
# Real Xilinx xfft 9.1 IPs (xsim).  Emits a per-mod summary + gate token
#   CFO_ALLMODS_GATE: PASS|FAIL   (all 4 mods BER=0 with the CFO applied)
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

VIVADO_DIR="${VIVADO_DIR:-/opt/Xilinx/Vivado/2021.1}"
export XFFT_TARGET_PART="${XFFT_TARGET_PART:-xczu9eg-ffvb1156-2-e}"
if [[ ! -x "$VIVADO_DIR/bin/vivado" ]]; then
    echo "[cfo] ERROR: vivado not at $VIVADO_DIR/bin/vivado" >&2; exit 2
fi
mkdir -p vivado_xsim/logs vivado_xsim/reports
set +u; source "$VIVADO_DIR/settings64.sh" 2>/dev/null || true; set -u

# the TB reads the B[k] conj-FFT ROM hierarchically
python3 scripts/gen_p5_bk_conj_fft512_rom.py >/dev/null 2>&1 || true
python3 scripts/rx_downstream_ref.py          >/dev/null 2>&1 || true

CFO_MILLI="${1:-250}"
declare -a NAMES=(qpsk 16qam 64qam 256qam)
SUMMARY="vivado_xsim/reports/cfo_allmods_summary.txt"
: > "$SUMMARY"
overall=0

echo "###### CFO robustness (EPS=$(awk "BEGIN{print $CFO_MILLI/1000.0}") subcarrier) : sync must correct -> BER 0 ######" | tee -a "$SUMMARY"
for M in 0 1 2 3; do
    tag="M${M}_${CFO_MILLI}"
    CFO_TAG="$tag" CFO_PLUSARGS="MOD=$M CFO_MILLI=$CFO_MILLI" \
    vivado -mode batch \
        -source vivado_xsim/tcl/run_rx_cfo_allmods.tcl \
        -log vivado_xsim/logs/rx_cfo_${tag}_vivado.log \
        -journal vivado_xsim/logs/rx_cfo_${tag}_vivado.jou >/dev/null 2>&1
    line=$(grep -m1 "^CFO_RESULT" "vivado_xsim/logs/rx_cfo_${tag}_sim.log" 2>/dev/null)
    echo "  ${NAMES[$M]}: $line" | tee -a "$SUMMARY"
    echo "$line" | grep -q -- "-> PASS" || overall=1
done

echo "======================================================================" | tee -a "$SUMMARY"
[[ $overall -eq 0 ]] && echo "CFO_ALLMODS_GATE: PASS" | tee -a "$SUMMARY" \
                     || echo "CFO_ALLMODS_GATE: FAIL" | tee -a "$SUMMARY"
echo "======================================================================" | tee -a "$SUMMARY"
exit $overall
