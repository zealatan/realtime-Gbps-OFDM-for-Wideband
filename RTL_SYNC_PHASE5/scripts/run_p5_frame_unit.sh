#!/usr/bin/env bash
# run_p5_frame_unit.sh — P5 frame_detector unit regression
#
# DUT: rtl/frame_detector.v (modular wrapper)
# TB : tb/p5_frame_detector_unit_tb.sv
#
# This is a self-contained unit test: it pulls in ONLY the four files
# the DUT needs (frame_detector + sample_power_sq + sliding_window_sum +
# frame_detect_fsm) and uses an internal reg-array IQ buffer stub instead
# of the retired iq_replay_buffer / phase3_sync_top integration path.
#
# GATE OUTPUT (exactly one):
#   GATE_P5_FRAME_UNIT: PASS    — frame_found=1 and frame_index within 41 ±1
#   GATE_P5_FRAME_UNIT: FAIL    — any check failed
#   GATE_P5_FRAME_UNIT: BLOCKED_* — pre-flight dependency missing
#
# USAGE:
#   bash scripts/run_p5_frame_unit.sh [OPTIONS]
#
#   Options:
#     --sim iverilog|xsim    simulator (default: iverilog)
#     --log-dir DIR          override log directory (default: sim_out/p5_frame_unit)
#
# EXIT CODES:
#   0  GATE_P5_FRAME_UNIT: PASS
#   1  any other gate outcome

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SIM_TOOL="iverilog"
LOG_DIR="${ROOT}/sim_out/p5_frame_unit"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --sim)     shift; SIM_TOOL="$1" ;;
        --log-dir) shift; LOG_DIR="$1"  ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
    shift
done

mkdir -p "${LOG_DIR}"
GATE_LOG="${LOG_DIR}/p5_frame_unit_gate.txt"
SIM_LOG="${LOG_DIR}/p5_frame_unit_sim.log"

gate_out() {
    local msg="$1"
    echo ""
    echo "========================================================================"
    echo "${msg}"
    echo "========================================================================"
    echo "${msg}" > "${GATE_LOG}"
}

echo "========================================================================"
echo "P5 frame_detector unit regression"
echo "  Date       : $(date '+%Y-%m-%d %H:%M:%S')"
echo "  Simulator  : ${SIM_TOOL}"
echo "  Log dir    : ${LOG_DIR}"
echo "  Root       : ${ROOT}"
echo "========================================================================"

# --------------------------------------------------------------------------
# Minimal RTL source list (NO phase3_dut_filelist.f — its symlinks are dead)
# --------------------------------------------------------------------------
RTL_DIR="${ROOT}/rtl"

RTL_SRCS=(
    "${RTL_DIR}/frame_detector.v"
    "${RTL_DIR}/sample_power_sq.v"
    "${RTL_DIR}/sliding_window_sum.v"
    "${RTL_DIR}/frame_detect_fsm.v"
)

TB_SRC="${ROOT}/tb/p5_frame_detector_unit_tb.sv"
STIM_FILE="${ROOT}/golden/phase3_iq_stimulus_q15.hex"

# --------------------------------------------------------------------------
# Pre-flight
# --------------------------------------------------------------------------
echo ""
echo "--- Required files ---"
BLOCKED=0
for f in "${RTL_SRCS[@]}" "${TB_SRC}" "${STIM_FILE}"; do
    if [[ ! -f "$f" ]]; then
        echo "  [MISS] $f"
        BLOCKED=1
    else
        echo "  [OK]   $(realpath --relative-to="${ROOT}" "$f")"
    fi
done
if [[ "${BLOCKED}" -eq 1 ]]; then
    gate_out "GATE_P5_FRAME_UNIT: BLOCKED_MISSING_FILES"
    exit 1
fi

# --------------------------------------------------------------------------
# Run simulation
# --------------------------------------------------------------------------
echo ""

if [[ "${SIM_TOOL}" == "xsim" ]]; then
    if ! command -v xvlog &>/dev/null; then
        gate_out "GATE_P5_FRAME_UNIT: BLOCKED_XSIM_UNAVAILABLE"
        echo "  xvlog not found in PATH."
        exit 1
    fi

    pushd "${ROOT}" >/dev/null

    echo "=== [1] xvlog ==="
    xvlog --nolog -sv "${RTL_SRCS[@]}" "${TB_SRC}" \
          2>&1 | tee "${LOG_DIR}/p5_frame_unit_xvlog.log"
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        popd >/dev/null
        gate_out "GATE_P5_FRAME_UNIT: BLOCKED_COMPILE_ERROR"
        exit 1
    fi

    echo "=== [2] xelab ==="
    xelab --nolog -debug typical \
          p5_frame_detector_unit_tb \
          -snapshot p5_frame_unit_snap \
          2>&1 | tee "${LOG_DIR}/p5_frame_unit_xelab.log"
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        popd >/dev/null
        gate_out "GATE_P5_FRAME_UNIT: BLOCKED_COMPILE_ERROR"
        exit 1
    fi

    echo "=== [3] xsim ==="
    xsim --nolog p5_frame_unit_snap \
         --runall \
         --log "${SIM_LOG}" \
         2>&1 | tee "${LOG_DIR}/p5_frame_unit_xsim_console.log"
    popd >/dev/null

elif [[ "${SIM_TOOL}" == "iverilog" ]]; then
    if ! command -v iverilog &>/dev/null; then
        gate_out "GATE_P5_FRAME_UNIT: BLOCKED_IVERILOG_UNAVAILABLE"
        echo "  iverilog not found in PATH."
        exit 1
    fi

    VVP="${LOG_DIR}/p5_frame_unit.vvp"

    echo "=== [1] iverilog: compile ==="
    iverilog -g2012 \
             -o "${VVP}" \
             "${RTL_SRCS[@]}" \
             "${TB_SRC}" \
             2>&1 | tee "${LOG_DIR}/p5_frame_unit_compile.log"
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        gate_out "GATE_P5_FRAME_UNIT: BLOCKED_COMPILE_ERROR"
        exit 1
    fi
    echo "  Compile OK: ${VVP}"

    echo ""
    echo "=== [2] vvp: simulate (cwd=${ROOT}) ==="
    # $readmemh path is relative — run from repo root
    pushd "${ROOT}" >/dev/null
    vvp "${VVP}" 2>&1 | tee "${SIM_LOG}"
    popd >/dev/null

else
    echo "ERROR: Unknown simulator '${SIM_TOOL}'." >&2
    gate_out "GATE_P5_FRAME_UNIT: BLOCKED_UNKNOWN_SIM"
    exit 1
fi

# --------------------------------------------------------------------------
# Gate evaluation
# --------------------------------------------------------------------------
echo ""
echo "--- Gate evaluation ---"

if grep -qE "^GATE_P5_FRAME_UNIT: PASS$" "${SIM_LOG}" 2>/dev/null; then
    gate_out "GATE_P5_FRAME_UNIT: PASS"
    grep -E "^\[PASS\]|^\[FAIL\]|^  (cycle_cnt|done_seen|frame_)" "${SIM_LOG}" || true
    exit 0
elif grep -qE "^GATE_P5_FRAME_UNIT: FAIL" "${SIM_LOG}" 2>/dev/null; then
    gate_out "GATE_P5_FRAME_UNIT: FAIL"
    grep -E "^\[PASS\]|^\[FAIL\]|^  (cycle_cnt|done_seen|frame_)" "${SIM_LOG}" | head -40 || true
    exit 1
else
    gate_out "GATE_P5_FRAME_UNIT: FAIL"
    echo "  No gate line found in simulation log."
    echo "  See: ${SIM_LOG}"
    exit 1
fi
