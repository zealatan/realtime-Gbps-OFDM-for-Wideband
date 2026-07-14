#!/usr/bin/env bash
# run_impair_clean_gate.sh -- PHASE-2 clean multi-mod loopback gate.
# Registry token: IMPAIR_CLEAN_GATE: PASS  (4 mods, BER must be 0)
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/run_tx_rx_impair.sh" clean
