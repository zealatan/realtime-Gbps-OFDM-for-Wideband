#!/usr/bin/env bash
# run_p3_02_reference_style_frame_detector_sim.sh
# Compile and simulate reference_style_frame_detector (P3-02).
# Requires: iverilog (or vcs/xvlog), verilator optional.
# Usage: bash scripts/run_p3_02_reference_style_frame_detector_sim.sh [--vcs | --xvlog]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${SCRIPT_DIR}/.."

RTL="${ROOT}/rtl"
LEG="${ROOT}/rtl/phase2_legacy"
TB="${ROOT}/tb"
OUT="${ROOT}/sim_out/p3_02"
mkdir -p "${OUT}"

TOOL="${1:-iverilog}"

echo "[p3-02] Simulator: ${TOOL}"
echo "[p3-02] Root: ${ROOT}"

# ── Source file lists ────────────────────────────────────────────────────
RTL_SOURCES=(
    "${LEG}/ram_2port.v"
    "${LEG}/sample_power_sq.v"
    "${RTL}/reference_style_frame_detector.v"
)

TB_SOURCES=(
    "${TB}/p3_02_reference_style_frame_detector_tb.sv"
)

case "${TOOL}" in

# ── Icarus Verilog ───────────────────────────────────────────────────────
iverilog)
    echo "[p3-02] Compiling with iverilog..."
    iverilog -g2012 -Wall \
        -o "${OUT}/sim" \
        "${RTL_SOURCES[@]}" "${TB_SOURCES[@]}"

    echo "[p3-02] Running simulation..."
    cd "${OUT}"
    ./sim | tee "${OUT}/sim.log"
    echo "[p3-02] Log: ${OUT}/sim.log"
    ;;

# ── Synopsys VCS ─────────────────────────────────────────────────────────
vcs)
    echo "[p3-02] Compiling with vcs..."
    vcs -sverilog -full64 +v2k \
        "${RTL_SOURCES[@]}" "${TB_SOURCES[@]}" \
        -o "${OUT}/simv" \
        -Mdir "${OUT}/csrc"

    echo "[p3-02] Running simulation..."
    "${OUT}/simv" | tee "${OUT}/sim.log"
    ;;

# ── Xilinx xvlog/xsim ────────────────────────────────────────────────────
xvlog)
    echo "[p3-02] Compiling with xvlog/xsim..."
    xvlog --sv "${RTL_SOURCES[@]}" "${TB_SOURCES[@]}"
    xelab -debug typical p3_02_reference_style_frame_detector_tb -s p3_02_sim
    xsim p3_02_sim --runall | tee "${OUT}/sim.log"
    ;;

*)
    echo "Unknown tool: ${TOOL}. Use: iverilog | vcs | xvlog" >&2
    exit 1
    ;;
esac

# ── Check result ─────────────────────────────────────────────────────────
if grep -q "RESULT: PASS" "${OUT}/sim.log"; then
    echo "[p3-02] ✓ PASS"
    exit 0
else
    echo "[p3-02] ✗ FAIL — see ${OUT}/sim.log"
    exit 1
fi
