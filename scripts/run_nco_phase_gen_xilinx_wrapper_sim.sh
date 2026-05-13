#!/usr/bin/env bash
set -euo pipefail

mkdir -p build logs

echo "[CLEAN] Cleaning previous simulation outputs..."
rm -rf build/xsim.dir build/.Xil build/*.jou build/*.log build/*.pb build/*.wdb

echo "[RUN] Compiling with xvlog..."

cd build

xvlog -sv \
    ../rtl/nco_phase_gen.v \
    ../rtl/nco_phase_gen_xilinx_wrapper.v \
    ../tb/nco_phase_gen_xilinx_wrapper_tb.sv \
    2>&1 | tee ../logs/nco_phase_gen_xilinx_wrapper_xvlog.log

echo "[RUN] Elaborating with xelab..."

xelab nco_phase_gen_xilinx_wrapper_tb \
    -debug typical \
    -s nco_phase_gen_xilinx_wrapper_tb_sim \
    2>&1 | tee ../logs/nco_phase_gen_xilinx_wrapper_xelab.log

echo "[RUN] Running simulation with xsim..."

xsim nco_phase_gen_xilinx_wrapper_tb_sim \
    -runall \
    2>&1 | tee ../logs/nco_phase_gen_xilinx_wrapper_xsim.log

cd ..

echo "[DONE] nco_phase_gen_xilinx_wrapper simulation finished."
echo "[LOG]  logs/nco_phase_gen_xilinx_wrapper_xsim.log"

echo "[CHECK] Checking for failures..."
if grep -q "CI GATE: FAILED\|\[FAIL\]\|FATAL" logs/nco_phase_gen_xilinx_wrapper_xsim.log 2>/dev/null; then
    grep "CI GATE\|\[FAIL\]\|FATAL" logs/nco_phase_gen_xilinx_wrapper_xsim.log | head -20
    echo "[RESULT] SIMULATION FAILED"
    exit 1
fi
grep "CI GATE\|PASS:" logs/nco_phase_gen_xilinx_wrapper_xsim.log 2>/dev/null | tail -5 || true
echo "[RESULT] SIMULATION PASSED"
