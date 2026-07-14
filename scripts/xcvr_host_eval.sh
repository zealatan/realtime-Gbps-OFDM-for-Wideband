#!/usr/bin/env bash
# xcvr_host_eval.sh — evaluate the 3-mode transceiver silicon captures.
#   LOOPBACK : ber_demod_bits.py --frames 1   (xcvr_lb_buf, 1 frame)
#   RX       : ber_demod_bits.py --frames 5   (xcvr_rx_buf, multi-frame)
#   TX       : xcvr_tx_slot_check.py          (xcvr_tx_buf, emitted slot)
# Usage: scripts/xcvr_host_eval.sh <label>
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LABEL="${1:-run}"
T="$ROOT/tests/12_xcvr_loopback"

echo "================= LOOPBACK (mode 2) BER ================="
python3 "$SCRIPT_DIR/ber_demod_bits.py" --bin "$T/xcvr_lb_buf_${LABEL}.bin" --frames 1
echo
echo "================= RX (mode 1) BER ======================="
# Try frames 1..5; report the best contiguous run.
for NF in 5 4 3 2 1; do
    echo "--- RX attempt --frames $NF ---"
    python3 "$SCRIPT_DIR/ber_demod_bits.py" --bin "$T/xcvr_rx_buf_${LABEL}.bin" --frames $NF && break
done
echo
echo "================= TX (mode 0) slot-match ================"
python3 "$SCRIPT_DIR/xcvr_tx_slot_check.py" --bin "$T/xcvr_tx_buf_${LABEL}.bin" --lsb 3
