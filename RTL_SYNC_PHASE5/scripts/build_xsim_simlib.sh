#!/usr/bin/env bash
# build_xsim_simlib.sh - one-time precompile of Xilinx xsim libraries.
# After this runs once (~5-10 min), every subsequent xelab on real
# IPs uses the precompiled libs, cutting cold gate launches from
# ~3 min to ~30 s.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VIVADO_DIR="${VIVADO_DIR:-/home/zealatan/Downloads/Vivado/2022.2}"
export XILINX_SIMLIB="${XILINX_SIMLIB:-$ROOT/sim_out/xsim_simlib}"
mkdir -p "$XILINX_SIMLIB"
echo "[simlib] target: $XILINX_SIMLIB"

cd "$ROOT"
set +e
# shellcheck disable=SC1090
source "$VIVADO_DIR/settings64.sh"
set -e
vivado -mode batch -source scripts/build_xsim_simlib.tcl \
    -log sim_out/xsim_simlib/build.log \
    -journal sim_out/xsim_simlib/build.jou
