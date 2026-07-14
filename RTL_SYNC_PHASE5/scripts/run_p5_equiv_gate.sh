#!/usr/bin/env bash
# run_p5_equiv_gate.sh
#
# P5-EQUIV: drive meyr_cfo_top with C-derived stimulus for k_int in [-8..+8]
# and assert peak_idx = k_int mod 2N AND cfo_int = k_int bit-exact for all
# 17 cases. PASS iff 17/17.
#
# Caching policy (because the underlying P5-D runner spins up Vivado batch
# + regenerates the IPs, which takes 3-5 minutes):
#   If vivado_xsim/reports/p5_d_gate.txt already shows
#   "P5_D_LEVEL1_GATE: PASS" AND the sim log shows the 17/17 line AND the
#   sim log is newer than ALL of:
#       rtl/meyr_*.v   rtl/complex_mult*.v   rtl/xfft_*/*.xci
#       scripts/gen_p5_bk_conj_fft512_rom.py
#       scripts/gen_p5_d_stimulus.py
#       tb/p5_d_meyr_cfo_top_unit_tb.sv
#   then we trust the cached result and skip the Vivado batch run.
# Otherwise, run the P5-D runner fresh.
#
# Outputs:
#   reports/p5_equiv/p5_equiv_gate.txt   - one-line gate result
#   reports/p5_equiv/p5_equiv_sim.log    - per-case sim transcript
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RPT_DIR="$ROOT/reports/p5_equiv"
mkdir -p "$RPT_DIR"
GATE="$RPT_DIR/p5_equiv_gate.txt"
SIMLOG_OUT="$RPT_DIR/p5_equiv_sim.log"

D_GATE="$ROOT/vivado_xsim/reports/p5_d_gate.txt"
D_SIMLOG="$ROOT/vivado_xsim/logs/p5_d_sim.log"

cache_valid() {
    [[ -s "$D_GATE" && -s "$D_SIMLOG" ]] || return 1
    grep -q 'GATE: PASS_P5_D_LEVEL1' "$D_SIMLOG" || return 1
    grep -q 'pass=17  fail=0' "$D_SIMLOG" || return 1
    local newer
    for src in \
        "$ROOT"/rtl/meyr_*.v \
        "$ROOT"/rtl/complex_mult*.v \
        "$ROOT"/rtl/xfft_N/xfft_N.xci \
        "$ROOT"/rtl/xfft_2N/xfft_2N.xci \
        "$ROOT"/rtl/xfft_IFFT/xfft_IFFT.xci \
        "$ROOT/scripts/gen_p5_bk_conj_fft512_rom.py" \
        "$ROOT/scripts/gen_p5_d_stimulus.py" \
        "$ROOT/tb/p5_d_meyr_cfo_top_unit_tb.sv"; do
        [[ -e "$src" ]] || continue
        if [[ "$src" -nt "$D_SIMLOG" ]]; then
            return 1
        fi
    done
    return 0
}

if cache_valid; then
    echo "P5_EQUIV_GATE: PASS (17/17 cases · k_int in [-8..+8]) [CACHED · $D_SIMLOG]" | tee "$GATE"
    cp "$D_SIMLOG" "$SIMLOG_OUT" 2>/dev/null || true
    exit 0
fi

# Cache miss: run the P5-D runner fresh.
bash "$ROOT/scripts/run_p5_d_meyr_cfo_top_unit.sh" >/dev/null 2>&1 || true

# D_GATE format: "P5_D_LEVEL1_GATE: PASS ..."  (word order != simlog)
# D_SIMLOG format: "GATE: PASS_P5_D_LEVEL1 ..."  + "[P5-D] Summary: pass=17 fail=0"
if grep -q 'P5_D_LEVEL1_GATE: PASS' "$D_GATE" 2>/dev/null \
   && grep -q 'GATE: PASS_P5_D_LEVEL1' "$D_SIMLOG" 2>/dev/null \
   && grep -q 'pass=17  fail=0' "$D_SIMLOG" 2>/dev/null; then
    echo "P5_EQUIV_GATE: PASS (17/17 cases · k_int in [-8..+8])" | tee "$GATE"
    cp "$D_SIMLOG" "$SIMLOG_OUT" 2>/dev/null || true
    exit 0
fi

SUM="$(grep -m1 'P5-D] Summary' "$D_SIMLOG" 2>/dev/null || echo 'NO_SUMMARY')"
echo "P5_EQUIV_GATE: FAIL · $SUM" | tee "$GATE"
cp "$D_SIMLOG" "$SIMLOG_OUT" 2>/dev/null || true
exit 1
