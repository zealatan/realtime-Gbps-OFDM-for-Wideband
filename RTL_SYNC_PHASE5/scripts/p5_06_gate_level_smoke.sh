#!/usr/bin/env bash
# p5_06_gate_level_smoke.sh
# Gate-level smoke sim using funcsim netlist (no SDF, no timing-accurate
# annotation). Sanity check that the synthesized netlist:
#   (1) Elaborates against Xilinx unisim + secureip libraries.
#   (2) Drives the P5-CONT-SMOKE testbench to its PASS line for one slot.
# The timesim+SDF variant exists but is too slow for routine regression
# (1-2h per slot on this host); kept for one-off triage.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VIVADO_DIR="${VIVADO_DIR:-/home/zealatan/Downloads/Vivado/2022.2}"

cd "$ROOT"
set +e; source "$VIVADO_DIR/settings64.sh"; set -e
export PATH="$VIVADO_DIR/bin:$PATH"

GLOG_DIR="$ROOT/vivado_xsim/logs"
GRPT_DIR="$ROOT/reports/p5_06_gate_level"
mkdir -p "$GLOG_DIR" "$GRPT_DIR"
GATE="$GRPT_DIR/p5_06_gate_level_smoke.txt"

BUILD="$GLOG_DIR/p5_06_gate_smoke_build"
rm -rf "$BUILD" && mkdir -p "$BUILD"
cd "$BUILD"

NETLIST="$ROOT/sim_out/gate_level/phase3_wrapper_funcsim.v"
CLOG="$GLOG_DIR/p5_06_gate_smoke_compile.log"
ELOG="$GLOG_DIR/p5_06_gate_smoke_elab.log"
SLOG="$GLOG_DIR/p5_06_gate_smoke_sim.log"

echo "[GATE-SMOKE] elaborating funcsim netlist..."
xvlog --nolog "$NETLIST" \
      "$ROOT/tb/p5_03_continuous_smoke_tb.sv" 2>&1 | tee "$CLOG" | tail -10

echo "[GATE-SMOKE] xelab gate-level snapshot..."
xelab --nolog \
      -L unisims_ver -L unimacro_ver -L secureip -L xpm \
      --snapshot p5_06_gate_snap \
      work.p5_03_continuous_smoke_tb 2>&1 | tee "$ELOG" | tail -15

if ! grep -q 'Built simulation snapshot' "$ELOG"; then
    echo "P5_06_GATE_LEVEL_GATE: BLOCKED_ELAB · gate-level elaboration failed" | tee "$GATE"
    exit 1
fi

echo "[GATE-SMOKE] running 1-slot smoke..."
xsim --nolog p5_06_gate_snap --runall --onerror quit 2>&1 \
    | tee "$SLOG" | tail -25

if grep -q 'GATE: PASS_P5_CONT_SMOKE' "$SLOG"; then
    echo "P5_06_GATE_LEVEL_GATE: PASS · funcsim netlist drives P5-CONT-SMOKE to PASS" | tee "$GATE"
    exit 0
elif grep -q 'GATE: FAIL_P5_CONT_SMOKE' "$SLOG"; then
    echo "P5_06_GATE_LEVEL_GATE: FAIL · funcsim netlist failed P5-CONT-SMOKE" | tee "$GATE"
    exit 1
else
    echo "P5_06_GATE_LEVEL_GATE: FAIL · no PASS/FAIL line emitted" | tee "$GATE"
    exit 1
fi
