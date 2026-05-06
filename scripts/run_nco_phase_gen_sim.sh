#!/usr/bin/env bash
set -euo pipefail

mkdir -p build logs

echo "[CLEAN] Cleaning previous simulation outputs..."
rm -rf build/xsim.dir build/.Xil build/*.jou build/*.log build/*.pb build/*.wdb

echo "[RUN] Compiling with xvlog..."

cd build

xvlog -sv \
    ../rtl/nco_phase_gen.v \
    ../tb/nco_phase_gen_tb.sv \
    2>&1 | tee ../logs/nco_phase_gen_xvlog.log

echo "[RUN] Elaborating with xelab..."

xelab nco_phase_gen_tb \
    -debug typical \
    -s nco_phase_gen_tb_sim \
    2>&1 | tee ../logs/nco_phase_gen_xelab.log

echo "[RUN] Running simulation with xsim..."

xsim nco_phase_gen_tb_sim \
    -runall \
    2>&1 | tee ../logs/nco_phase_gen_xsim.log

cd ..

echo "[DONE] nco_phase_gen simulation finished."
echo "[LOG]  logs/nco_phase_gen_xsim.log"
