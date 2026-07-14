#!/usr/bin/env bash
# One reproducible RF FFT loopback capture per physical condition.
#
# Usage:
#   scripts/capture_run.sh <label>     e.g. connected | removed
#
# Produces (all named by <label> so reruns never overwrite and others can
# reproduce/compare):
#   tests/08_rfdc_capture/capture_<label>.bin        raw lane-0 ADC samples (JTAG dump)
#   tests/08_rfdc_capture/capture_<label>_fft.txt     offline FFT summary (peak freq, SNR)
#   tests/08_rfdc_capture/capture_<label>_fft.png     spectrum plot
set -euo pipefail

label="${1:-}"
if [ -z "$label" ]; then
    echo "usage: scripts/capture_run.sh <label>   (e.g. connected | removed)" >&2
    exit 2
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

# Vitis settings64.sh location differs per machine; pick the first that exists.
for cand in \
    "$HOME"/xilinx/Vitis/Vitis/*/settings64.sh \
    /tools/Xilinx/Vitis/*/settings64.sh \
    /tool/Xilinx/Vitis/*/settings64.sh \
    /opt/Xilinx/Vitis/*/settings64.sh; do
    if [ -r "$cand" ]; then source "$cand"; break; fi
done

echo "=== [$label] program + run + JTAG dump ==="
# xsct sometimes returns nonzero on a harmless rdi_xsct teardown crash AFTER the
# work is done; verify the dump file instead of trusting the exit code.
set +e
scripts/xsct_2021_compat.sh scripts/run_rfdc_capture.xsct "$label"
xsct_rc=$?
set -e
if [ "$xsct_rc" -ne 0 ]; then
    echo "note: xsct exited rc=$xsct_rc (possible harmless teardown crash); continuing if dump exists"
fi
if [ ! -f "tests/08_rfdc_capture/capture_${label}.bin" ]; then
    echo "ERROR: dump tests/08_rfdc_capture/capture_${label}.bin was not produced; aborting" >&2
    exit 1
fi

echo "=== [$label] offline FFT ==="
python3 scripts/fft_capture.py "tests/08_rfdc_capture/capture_${label}.bin"

echo "=== [$label] artifacts ==="
ls -1 "tests/08_rfdc_capture/capture_${label}.bin" \
       "tests/08_rfdc_capture/capture_${label}_fft.png" \
       "tests/08_rfdc_capture/capture_${label}_fft.txt" 2>/dev/null || true
