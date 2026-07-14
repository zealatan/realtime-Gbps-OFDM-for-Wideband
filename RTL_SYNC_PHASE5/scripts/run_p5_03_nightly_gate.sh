#!/usr/bin/env bash
# run_p5_03_nightly_gate.sh - cache-aware wrapper for P5-CONT-NIGHTLY.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RPT_DIR="$ROOT/reports/p5_03_continuous"
mkdir -p "$RPT_DIR"
GATE="$RPT_DIR/p5_cont_nightly_gate.txt"
D_GATE="$ROOT/vivado_xsim/reports/p5_03_nightly_gate.txt"
D_SIMLOG="$ROOT/vivado_xsim/logs/p5_03_nightly_sim.log"

cache_valid() {
    [[ -s "$D_GATE" && -s "$D_SIMLOG" ]] || return 1
    grep -q 'P5_CONT_NIGHTLY_GATE: PASS' "$D_GATE" || return 1
    grep -q 'GATE: PASS_P5_CONT_NIGHTLY' "$D_SIMLOG" || return 1
    for src in \
        "$ROOT"/rtl/*.v \
        "$ROOT"/rtl/xfft_N/xfft_N.xci \
        "$ROOT"/rtl/xfft_2N/xfft_2N.xci \
        "$ROOT"/rtl/xfft_IFFT/xfft_IFFT.xci \
        "$ROOT/tb/p5_03_continuous_nightly_tb.sv" \
        "$ROOT/golden/phase3_iq_stimulus.mem"; do
        [[ -e "$src" ]] || continue
        if [[ "$src" -nt "$D_SIMLOG" ]]; then return 1; fi
    done
    return 0
}

if cache_valid; then
    echo "P5_CONT_NIGHTLY_GATE: PASS [CACHED · $D_SIMLOG]" | tee "$GATE"
    exit 0
fi

bash "$ROOT/scripts/run_p5_03_nightly.sh" >/dev/null 2>&1 || true
if grep -q 'P5_CONT_NIGHTLY_GATE: PASS' "$D_GATE" 2>/dev/null \
   && grep -q 'GATE: PASS_P5_CONT_NIGHTLY' "$D_SIMLOG" 2>/dev/null; then
    echo "P5_CONT_NIGHTLY_GATE: PASS" | tee "$GATE"
    exit 0
fi
SUM="$(grep -m1 'NIGHTLY\]' "$D_SIMLOG" 2>/dev/null | tail -1)"
echo "P5_CONT_NIGHTLY_GATE: FAIL · $SUM" | tee "$GATE"
exit 1
