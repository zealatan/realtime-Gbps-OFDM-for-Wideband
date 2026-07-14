#!/usr/bin/env bash
# run_p3_08_meyr_backend.sh — P3-08 Meyr backend bring-up runner
#
# Usage: bash scripts/run_p3_08_meyr_backend.sh [--sim xsim|iverilog]
#
# IMPORTANT: xsim (Vivado) is the OFFICIAL CI simulator.
#   --sim iverilog  is available as a quick local sanity check ONLY.
#   iverilog results are NOT official CI sign-off.
#
# For the authoritative CI gate use:
#   bash scripts/run_phase3_sync_xsim.sh
#
# Step 1: regenerate real Meyr reference ROMs from stimulus
# Step 2: run full Phase 3 sync simulation
# Step 3: print comparison results

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

SIM="xsim"
while [[ $# -gt 0 ]]; do
    case $1 in
        --sim) SIM="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

echo "=========================================="
echo "P3-08 Meyr Backend Bring-up"
echo "  Simulator: $SIM"
echo "=========================================="

echo ""
echo "--- Step 1: Generate Meyr reference ROMs ---"
python3 scripts/gen_meyr_reference_roms.py
echo "[P3-08] ROM generation complete."

echo ""
echo "--- Step 2: Run Phase 3 sync simulation ---"
bash scripts/run_phase3_sync_sim.sh --sim "$SIM"

echo ""
echo "[P3-08] Done."
