#!/usr/bin/env bash
# run_p5_03_smoke.sh — P5-03 Step 2 smoke acceptance gate.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VIVADO_DIR="${VIVADO_DIR:-/home/zealatan/Downloads/Vivado/2022.2}"
export XFFT_TARGET_PART="${XFFT_TARGET_PART:-xczu9eg-ffvb1156-2-e}"

cd "$ROOT"
set +e
# shellcheck disable=SC1090
source "$VIVADO_DIR/settings64.sh"
set -e
vivado -mode batch -source vivado_xsim/tcl/run_p5_03_smoke.tcl \
    -log vivado_xsim/logs/p5_03_smoke_vivado.log \
    -journal vivado_xsim/logs/p5_03_smoke_vivado.jou
