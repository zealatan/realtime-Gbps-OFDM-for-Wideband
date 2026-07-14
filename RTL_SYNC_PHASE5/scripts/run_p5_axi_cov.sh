#!/usr/bin/env bash
# C2 AXI-Lite register coverage gate (cache-aware).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VIVADO_DIR="${VIVADO_DIR:-/home/zealatan/Downloads/Vivado/2022.2}"
export XFFT_TARGET_PART="${XFFT_TARGET_PART:-xczu9eg-ffvb1156-2-e}"
GATE="$ROOT/vivado_xsim/reports/p5_axi_cov_gate.txt"
LATEST_TB="$ROOT/tb/p5_axi_lite_cov_tb.sv"

cache_valid() {
    [[ -s "$GATE" ]] || return 1
    grep -q 'P5_AXI_COV_GATE: PASS' "$GATE" || return 1
    for src in "$ROOT"/rtl/*.v "$LATEST_TB"; do
        [[ -e "$src" ]] || continue
        if [[ "$src" -nt "$GATE" ]]; then return 1; fi
    done
    return 0
}
if cache_valid; then
    echo "P5_AXI_COV_GATE: PASS [CACHED]"; exit 0
fi
cd "$ROOT"
set +e; source "$VIVADO_DIR/settings64.sh"; set -e
vivado -mode batch -source vivado_xsim/tcl/run_p5_axi_lite_cov.tcl \
    -log vivado_xsim/logs/p5_axi_cov_vivado.log \
    -journal vivado_xsim/logs/p5_axi_cov_vivado.jou
