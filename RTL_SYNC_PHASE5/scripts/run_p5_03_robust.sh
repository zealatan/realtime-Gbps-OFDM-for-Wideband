#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VIVADO_DIR="${VIVADO_DIR:-/home/zealatan/Downloads/Vivado/2022.2}"
export XFFT_TARGET_PART="${XFFT_TARGET_PART:-xczu9eg-ffvb1156-2-e}"
cd "$ROOT"
set +e; source "$VIVADO_DIR/settings64.sh"; set -e
vivado -mode batch -source vivado_xsim/tcl/run_p5_03_robust.tcl \
    -log vivado_xsim/logs/p5_03_robust_vivado.log \
    -journal vivado_xsim/logs/p5_03_robust_vivado.jou
