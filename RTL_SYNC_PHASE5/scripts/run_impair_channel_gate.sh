#!/usr/bin/env bash
# run_impair_channel_gate.sh -- PHASE-2 multipath (freq-selective) channel gate.
# Registry token: IMPAIR_CHANNEL_GATE: PASS  (4 mods, pilot CE + ZF EQ -> BER 0)
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/run_tx_rx_impair.sh" channel
