#!/usr/bin/env bash
set -euo pipefail

mkdir -p build logs

echo "[CLEAN] Removing previous meyr_pss_sss_product_gen artifacts..."
rm -f  build/meyr_pss_sss_product_gen*.log build/meyr_pss_sss_product_gen*.pb \
       build/meyr_pss_sss_product_gen*.jou build/meyr_pss_sss_product_gen*.wdb
rm -rf build/xsim.dir build/.Xil

echo "[RUN] Compiling with xvlog..."
cd build

xvlog -sv \
    ../rtl/meyr_pss_sss_product_gen.v \
    ../tb/meyr_pss_sss_product_gen_tb.sv \
    2>&1 | tee ../logs/meyr_pss_sss_product_gen_xvlog.log

echo "[RUN] Elaborating with xelab..."
xelab meyr_pss_sss_product_gen_tb \
    -debug typical \
    -timescale 1ns/1ps \
    -s meyr_pss_sss_product_gen_snap \
    2>&1 | tee ../logs/meyr_pss_sss_product_gen_xelab.log

echo "[RUN] Running simulation with xsim..."
xsim meyr_pss_sss_product_gen_snap \
    -runall \
    2>&1 | tee ../logs/meyr_pss_sss_product_gen_xsim.log

cd ..

echo ""
echo "[RESULTS]"
grep -E "T[0-9]+:|PASS|FAIL|CI GATE" logs/meyr_pss_sss_product_gen_xsim.log || true

if grep -qE 'CI GATE: FAILED|FATAL' logs/meyr_pss_sss_product_gen_xsim.log; then
    echo "[ERROR] Failures detected in logs/meyr_pss_sss_product_gen_xsim.log"
    exit 1
fi

echo "[PASS] CI GATE: PASSED"
