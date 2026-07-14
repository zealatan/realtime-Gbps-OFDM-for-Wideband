#!/usr/bin/env bash
# clksweep_one.sh <mhz_tag> <mwr_hex> <por_index>
# One full POR at a given pl_clk0: UART capture + program+POR+run+dump.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UART="${UART:-/dev/ttyUSB1}"
MHZ="$1"; MWR="$2"; POR="$3"
LABEL="clk${MHZ}_por${POR}"
TS="$(date +%H%M%S)"
ULOG="$ROOT/tests/11_full_rx_loopback/uart_${LABEL}_${TS}.log"
XLOG="$ROOT/tests/11_full_rx_loopback/xsct_${LABEL}_${TS}.log"

stty -F "$UART" 115200 cs8 -cstopb -parenb -ixon raw 2>/dev/null || true
: > "$ULOG"
cat "$UART" >> "$ULOG" &
UART_PID=$!

timeout 180 "$ROOT/scripts/xsct_2021_compat.sh" "$ROOT/scripts/run_11_clksweep.xsct" "$LABEL" "$MWR" \
    > "$XLOG" 2>&1
XRC=$?

sleep 4
kill "$UART_PID" 2>/dev/null
wait "$UART_PID" 2>/dev/null

echo "=== [$LABEL] xsct_exit=$XRC mwr=$MWR ==="
grep -aE "PL0_REF_CTRL|ZCU216_DLOOP:|ZCU216_FRX_APP|capture_buf dumped" "$XLOG" 2>/dev/null | sed 's/^/  X: /'
grep -aE "ZCU216_DLOOP:|ZCU216_BER:|DLOOP" "$ULOG" 2>/dev/null | tail -8 | sed 's/^/  U: /'
DUMP="$ROOT/tests/11_full_rx_loopback/frxbits_${LABEL}.bin"
if [ -f "$DUMP" ]; then echo "  DUMP ok: $(stat -c%s "$DUMP") bytes -> $DUMP"; else echo "  DUMP MISSING"; fi
