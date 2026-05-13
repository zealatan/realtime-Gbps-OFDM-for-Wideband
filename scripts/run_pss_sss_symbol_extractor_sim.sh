#!/usr/bin/env bash
set -euo pipefail

mkdir -p build logs

echo "[CLEAN] Cleaning previous pss_sss_symbol_extractor artifacts..."
rm -rf build/xsim.dir build/.Xil
rm -f  build/pss_sss_symbol_extractor*.log \
       build/pss_sss_symbol_extractor*.pb  \
       build/pss_sss_symbol_extractor*.jou \
       build/pss_sss_symbol_extractor*.wdb

echo "[RUN] Compiling with xvlog..."
cd build

xvlog -sv \
    ../rtl/pss_sss_symbol_extractor.v \
    ../tb/pss_sss_symbol_extractor_tb.sv \
    2>&1 | tee ../logs/pss_sss_symbol_extractor_xvlog.log

echo "[RUN] Elaborating with xelab..."
xelab pss_sss_symbol_extractor_tb \
    -debug typical \
    -timescale 1ns/1ps \
    -s pss_sss_symbol_extractor_snap \
    2>&1 | tee ../logs/pss_sss_symbol_extractor_xelab.log

echo "[RUN] Running simulation with xsim..."
xsim pss_sss_symbol_extractor_snap \
    -runall \
    2>&1 | tee ../logs/pss_sss_symbol_extractor_xsim.log

cd ..

echo ""
echo "[RESULTS]"
grep -E "T[0-9]+:|PASS|CI GATE|\[FAIL\]" logs/pss_sss_symbol_extractor_xsim.log || true

if grep -qE 'CI GATE: FAILED|\[FAIL\]|FATAL' logs/pss_sss_symbol_extractor_xsim.log 2>/dev/null; then
    echo "[ERROR] Failures detected — see logs/pss_sss_symbol_extractor_xsim.log"
    exit 1
fi

echo "[DONE] logs/pss_sss_symbol_extractor_xsim.log"
