#!/usr/bin/env bash
# RF 6c-2: program the rfsync bitstream, run the firmware (run_rf_sync), capture
# UART (ZCU216_RFSYNC: fsv/fsi/peak/int_cfo lines) and dump the corrected DUT
# m_axis buffer over JTAG. UART0 = if01-port0 @115200.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
label="${1:-rfsync}"

UART=/dev/serial/by-id/usb-Xilinx_ZCU216_812308158457-if01-port0
ULOG="tests/08_rfdc_capture/uart_${label}.log"
mkdir -p tests/08_rfdc_capture

for cand in "$HOME"/xilinx/Vitis/Vitis/*/settings64.sh \
    /tools/Xilinx/Vitis/*/settings64.sh /tool/Xilinx/Vitis/*/settings64.sh \
    /opt/Xilinx/Vitis/*/settings64.sh; do
    [ -r "$cand" ] && { source "$cand"; break; }
done

# Start UART capture in background.
if [ -e "$UART" ]; then
    stty -F "$UART" 115200 -echo raw 2>/dev/null || true
    : > "$ULOG"
    timeout 60 cat "$UART" > "$ULOG" 2>/dev/null &
    UPID=$!
    echo "run_rfsync: UART capture -> $ULOG (pid $UPID)"
else
    echo "run_rfsync: WARN UART $UART not found; UART not captured"
    UPID=""
fi

set +e
scripts/xsct_2021_compat.sh scripts/run_rfdc_capture.xsct "$label"
rc=$?
set -e
echo "run_rfsync: xsct rc=$rc"

# give the firmware time to finish printing then stop UART capture
sleep 3
[ -n "$UPID" ] && { kill "$UPID" 2>/dev/null; wait "$UPID" 2>/dev/null; }

echo "=== ZCU216_RFSYNC UART lines ==="
grep -E 'ZCU216_RFSYNC|ZCU216_RFDC: (PASS|FAIL)' "$ULOG" 2>/dev/null || \
    echo "(no RFSYNC lines captured; see $ULOG)"
echo "=== dump file ==="
ls -l "tests/08_rfdc_capture/capture_${label}.bin" 2>/dev/null || echo "(no dump)"
