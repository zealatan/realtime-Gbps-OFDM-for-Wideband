#!/usr/bin/env bash
# run_p5_corrected_gate.sh — P5-CORRECTED bit-exact gate (ISS-04).
# Depends on the nightly TB having dumped sim_out/p5_07/nightly_{frac,mout}.hex.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RPT_DIR="$ROOT/reports/p5_corrected"
mkdir -p "$RPT_DIR"
GATE="$RPT_DIR/p5_corrected_gate.txt"

FRAC="$ROOT/sim_out/p5_07/nightly_frac.hex"
MOUT="$ROOT/sim_out/p5_07/nightly_mout.hex"

cache_valid() {
    [[ -s "$FRAC" && -s "$MOUT" && -s "$GATE" ]] || return 1
    grep -q 'P5_CORRECTED_GATE: PASS' "$GATE" || return 1
    for src in "$ROOT"/rtl/*.v \
               "$ROOT/tb/p5_03_continuous_nightly_tb.sv" \
               "$ROOT/scripts/gen_p5_corrected_golden.py"; do
        [[ -e "$src" ]] || continue
        if [[ "$src" -nt "$GATE" ]]; then return 1; fi
    done
    return 0
}

if cache_valid; then
    cat "$GATE" | sed 's/$/ [CACHED]/'
    exit 0
fi

# Ensure dumps exist by running the nightly cache wrapper first.
bash "$ROOT/scripts/run_p5_03_nightly_gate.sh" >/dev/null 2>&1 || true

if [[ ! -s "$FRAC" || ! -s "$MOUT" ]]; then
    echo "P5_CORRECTED_GATE: FAIL · nightly dumps missing" | tee "$GATE"
    exit 1
fi
python3 "$ROOT/scripts/gen_p5_corrected_golden.py"
