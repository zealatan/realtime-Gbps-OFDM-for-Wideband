#!/usr/bin/env bash
# run_12_xcvr_loopback.sh
# Flash the 12_xcvr_loopback bitstream + ELF (mode-selectable OFDM transceiver)
# and run the 3-mode (TX/RX/LOOPBACK) silicon test, capturing UART + the three
# per-mode JTAG dumps, then computing host BER + TX slot-match.
#   1. start UART capture on $UART (default /dev/ttyUSB1)
#   2. run scripts/run_12_xcvr_loopback.xsct (flash + run + dump 3 buffers)
#   3. stop UART, print ZCU216_XCVR: markers
#   4. run scripts/xcvr_host_eval.sh (LOOPBACK/RX BER + TX slot-match)
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UART="${UART:-/dev/ttyUSB1}"
LABEL="${1:-xcvr}"
TS="$(date +%Y%m%d_%H%M%S)"
TDIR="$ROOT/tests/12_xcvr_loopback"
mkdir -p "$TDIR"
ULOG="$TDIR/uart_${LABEL}_${TS}.log"
XLOG="$TDIR/xsct_${LABEL}_${TS}.log"

echo "[XCVR-RUN] UART=$UART  ULOG=$ULOG  XLOG=$XLOG"

stty -F "$UART" 115200 cs8 -cstopb -parenb -ixon raw 2>/dev/null || \
    echo "[XCVR-RUN] WARN stty failed on $UART"
: > "$ULOG"
cat "$UART" >> "$ULOG" &
UART_PID=$!
echo "[XCVR-RUN] UART capture PID=$UART_PID"

"$ROOT/scripts/xsct_2021_compat.sh" "$ROOT/scripts/run_12_xcvr_loopback.xsct" "$LABEL" \
    > "$XLOG" 2>&1
XRC=$?
echo "[XCVR-RUN] xsct exit=$XRC"

echo "[XCVR-RUN] holding UART ${UART_HOLD:-30}s for the 3-mode sequence + dumps..."
sleep "${UART_HOLD:-30}"
kill "$UART_PID" 2>/dev/null
wait "$UART_PID" 2>/dev/null

echo "[XCVR-RUN] ===== UART (ZCU216_XCVR markers) ====="
grep -aE "ZCU216_XCVR" "$ULOG" || echo "[XCVR-RUN] (no markers -- check $ULOG and $XLOG)"
echo "[XCVR-RUN] full UART log: $ULOG"

echo "[XCVR-RUN] ===== HOST EVAL (BER + TX slot-match) ====="
"$ROOT/scripts/xcvr_host_eval.sh" "$LABEL"
exit $XRC
