#!/usr/bin/env bash
# D1 3-way (C ↔ Python ↔ RTL) gate.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GATE="$ROOT/reports/p5_d1/p5_d1_3way_gate.txt"

cache_valid() {
    [[ -s "$GATE" ]] || return 1
    grep -q 'P5_D1_3WAY_GATE: PASS' "$GATE" || return 1
    for src in "$ROOT/ref/dump_p5_d1.c" \
               "$ROOT/scripts/check_p5_d1_3way.py" \
               "$ROOT/scripts/gen_p5_bk_conj_fft512_rom.py" \
               "$ROOT/golden/p5_d1/c_dump.txt"; do
        [[ -e "$src" ]] || continue
        if [[ "$src" -nt "$GATE" ]]; then return 1; fi
    done
    return 0
}
if cache_valid; then
    cat "$GATE" | sed 's/$/ [CACHED]/'; exit 0
fi

# Rebuild C dump (idempotent, very fast)
mkdir -p "$ROOT/golden/p5_d1"
gcc -O0 -o /tmp/dump_p5_d1 "$ROOT/ref/dump_p5_d1.c" -I "$ROOT/ref" -lm
/tmp/dump_p5_d1 > "$ROOT/golden/p5_d1/c_dump.txt"
python3 "$ROOT/scripts/check_p5_d1_3way.py"
