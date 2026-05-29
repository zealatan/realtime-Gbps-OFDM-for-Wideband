#!/usr/bin/env bash
# run_p3_10a_iq_replay_buffer_sim.sh — P3-10A standalone replay buffer simulation
#
# DUT:  rtl/iq_replay_buffer_576.v
# TB:   tb/p3_10a_iq_replay_buffer_tb.sv
#
# Usage:
#   bash scripts/run_p3_10a_iq_replay_buffer_sim.sh [--sim xsim|iverilog]
#
# IMPORTANT: xsim (Vivado) is the OFFICIAL CI simulator.
#   The default here is iverilog for convenience (standalone unit test),
#   but iverilog results are NOT official CI sign-off.
#   Use --sim xsim for official revalidation once Vivado is available.
#
# Prerequisites (iverilog, quick sanity):
#   iverilog + vvp in PATH  (tested with iverilog 11.0)
#
# Output:
#   sim_out/p3_10a_iq_replay_buffer.vvp  (iverilog binary)
#   Console: per-test PASS/FAIL + CI_GATE result

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${SCRIPT_DIR}/.."
cd "${ROOT}"

SIM_TOOL="iverilog"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --sim) SIM_TOOL="$2"; shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

echo "=========================================="
echo "P3-10A iq_replay_buffer_576 simulation"
echo "  Simulator: ${SIM_TOOL}"
echo "=========================================="

mkdir -p sim_out

# Source files (DUT only; no other dependencies)
RTL_SRC="rtl/iq_replay_buffer_576.v"
TB_SRC="tb/p3_10a_iq_replay_buffer_tb.sv"

if [[ "${SIM_TOOL}" == "iverilog" ]]; then

    echo ""
    echo "--- Compiling with iverilog ---"
    iverilog -g2012 \
        -o sim_out/p3_10a_iq_replay_buffer.vvp \
        ${RTL_SRC} \
        ${TB_SRC}
    echo "[compile] OK"

    echo ""
    echo "--- Running simulation ---"
    vvp sim_out/p3_10a_iq_replay_buffer.vvp

elif [[ "${SIM_TOOL}" == "xsim" ]]; then

    echo ""
    echo "--- Compiling with xvlog/xelab ---"
    xvlog -sv ${RTL_SRC} ${TB_SRC}
    xelab -timescale 1ns/1ps -debug typical \
        -top p3_10a_iq_replay_buffer_tb \
        -snapshot p3_10a_snap
    echo ""
    echo "--- Running simulation ---"
    xsim p3_10a_snap --runall

else
    echo "Unknown simulator: ${SIM_TOOL}" >&2
    exit 1
fi

echo ""
echo "=========================================="
echo "P3-10A simulation complete."
echo "=========================================="
