#!/usr/bin/env bash
# run_cfo_allmods_gate.sh -- PHASE-2 CFO robustness (all mods) gate.
# Registry token: CFO_ALLMODS_GATE: PASS  (4 mods, EPS=0.25 sc, sync corrects -> BER 0)
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/run_rx_cfo_allmods.sh" 250
