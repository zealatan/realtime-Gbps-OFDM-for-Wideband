#!/usr/bin/env bash
# run_ber_longrun.sh
# Flash the 11_full_rx_loopback BER bitstream + ELF and capture the UART so the
# on-chip HW BER counter results (ZCU216_BER: markers) are recorded.
#   1. start UART capture on $UART (default /dev/ttyUSB1) in background
#   2. run the xsct flash+run script (scripts/run_11_full_rx_loopback.xsct)
#   3. stop UART, print the BER markers
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UART="${UART:-/dev/ttyUSB1}"
LABEL="${1:-berlong}"
TS="$(date +%Y%m%d_%H%M%S)"
ULOG="$ROOT/tests/11_full_rx_loopback/uart_ber_${LABEL}_${TS}.log"
XLOG="$ROOT/tests/11_full_rx_loopback/xsct_ber_${LABEL}_${TS}.log"

echo "[BER-RUN] UART=$UART  ULOG=$ULOG  XLOG=$XLOG"

# --- 1. configure + capture UART -------------------------------------------
stty -F "$UART" 115200 cs8 -cstopb -parenb -ixon raw 2>/dev/null || \
    echo "[BER-RUN] WARN stty failed on $UART"
: > "$ULOG"
cat "$UART" >> "$ULOG" &
UART_PID=$!
echo "[BER-RUN] UART capture PID=$UART_PID"

# --- 2. run xsct flash + app -----------------------------------------------
"$ROOT/scripts/xsct_2021_compat.sh" "$ROOT/scripts/run_11_full_rx_loopback.xsct" "$LABEL" \
    > "$XLOG" 2>&1
XRC=$?
echo "[BER-RUN] xsct exit=$XRC"

# xsct often SIGABRTs on teardown ("Tcl_FindHashEntry on deleted table") AFTER
# starting the app; the app keeps running on the board. Keep capturing UART for
# a fixed generous window so the full BER long-run + readback output is recorded
# regardless of the xsct exit timing.
echo "[BER-RUN] holding UART capture ${UART_HOLD:-25}s for app to finish streaming..."
sleep "${UART_HOLD:-25}"
kill "$UART_PID" 2>/dev/null
wait "$UART_PID" 2>/dev/null

echo "[BER-RUN] ===== UART (BER + loop markers) ====="
grep -aE "ZCU216_BER:|ZCU216_DLOOP:" "$ULOG" || \
    echo "[BER-RUN] (no markers captured -- check $ULOG and $XLOG)"
echo "[BER-RUN] full UART log: $ULOG"
exit $XRC
