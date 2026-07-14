#!/usr/bin/env bash
# run_p5_cp_unit.sh — streaming_cp_autocorr unit-TB runner
#
# DUT : rtl/streaming_cp_autocorr.v   (NSC=256, CP_LEN=32)
# TB  : tb/p5_cp_autocorr_unit_tb.sv
#
# GATE OUTPUT (exactly one):
#   GATE_P5_CP_UNIT: PASS          — peak sample_index in [21, 25]
#   GATE_P5_CP_UNIT: FAIL          — peak out of window or pipeline didn't fire
#   GATE_P5_CP_UNIT: BLOCKED_*     — pre-flight dependency missing
#
# USAGE:
#   bash scripts/run_p5_cp_unit.sh [OPTIONS]
#     --sim iverilog|xsim    simulator (default: iverilog)
#     --log-dir DIR          override log directory (default: sim_out/p5_cp_unit)
#
# EXIT CODES:
#   0  GATE_P5_CP_UNIT: PASS
#   1  any other gate outcome

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SIM_TOOL="iverilog"
LOG_DIR="${ROOT}/sim_out/p5_cp_unit"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --sim)     shift; SIM_TOOL="$1" ;;
        --log-dir) shift; LOG_DIR="$1"  ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
    shift
done

mkdir -p "${LOG_DIR}"
GATE_LOG="${LOG_DIR}/p5_cp_unit_gate.txt"
SIM_LOG="${LOG_DIR}/p5_cp_unit_sim.log"

gate_out() {
    local msg="$1"
    echo ""
    echo "========================================================================"
    echo "${msg}"
    echo "========================================================================"
    echo "${msg}" > "${GATE_LOG}"
}

echo "========================================================================"
echo "P5 streaming_cp_autocorr Unit Regression"
echo "  Date       : $(date '+%Y-%m-%d %H:%M:%S')"
echo "  Simulator  : ${SIM_TOOL}"
echo "  Log dir    : ${LOG_DIR}"
echo "  Root       : ${ROOT}"
echo "========================================================================"

# --------------------------------------------------------------------------
# Minimal source list — only what streaming_cp_autocorr needs
# --------------------------------------------------------------------------
RTL_DIR="${ROOT}/rtl"

RTL_SRCS=(
    "${RTL_DIR}/streaming_cp_autocorr.v"
    "${RTL_DIR}/delay_sample.v"
    "${RTL_DIR}/complex_mult.v"
    "${RTL_DIR}/moving_avg_optimized.v"
    "${RTL_DIR}/sample_power_sq.v"
    "${RTL_DIR}/complex_to_mag.v"
    "${RTL_DIR}/delayT.v"
    "${RTL_DIR}/ram_2port.v"
)

TB_SRC="${ROOT}/tb/p5_cp_autocorr_unit_tb.sv"
STIM_FILE="${ROOT}/golden/phase3_iq_stimulus_q15.hex"

# --------------------------------------------------------------------------
# Pre-flight: required files
# --------------------------------------------------------------------------
echo ""
echo "--- Required files ---"
BLOCKED=0
for f in "${RTL_SRCS[@]}" "${TB_SRC}"; do
    if [[ ! -f "$f" ]]; then
        echo "  [MISS] $f"
        BLOCKED=1
    else
        echo "  [OK]   $(basename "$f")"
    fi
done
if [[ ! -f "${STIM_FILE}" ]]; then
    echo "  [MISS] golden/phase3_iq_stimulus_q15.hex"
    BLOCKED=1
else
    echo "  [OK]   golden/phase3_iq_stimulus_q15.hex"
fi
if [[ "${BLOCKED}" -eq 1 ]]; then
    gate_out "GATE_P5_CP_UNIT: BLOCKED_MISSING_FILES"
    exit 1
fi

# --------------------------------------------------------------------------
# Run simulation
# --------------------------------------------------------------------------
echo ""

if [[ "${SIM_TOOL}" == "xsim" ]]; then
    if ! command -v xvlog &>/dev/null; then
        gate_out "GATE_P5_CP_UNIT: BLOCKED_XSIM_UNAVAILABLE"
        echo "  xvlog not found in PATH."
        exit 1
    fi

    echo "=== [1] xvlog ==="
    ( cd "${ROOT}" && xvlog --nolog -sv "${RTL_SRCS[@]}" "${TB_SRC}" ) \
        2>&1 | tee "${LOG_DIR}/p5_cp_unit_xvlog.log"
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        gate_out "GATE_P5_CP_UNIT: BLOCKED_COMPILE_ERROR"
        exit 1
    fi

    echo "=== [2] xelab ==="
    ( cd "${ROOT}" && xelab --nolog -debug typical \
            p5_cp_autocorr_unit_tb \
            -snapshot p5_cp_unit_snap ) \
        2>&1 | tee "${LOG_DIR}/p5_cp_unit_xelab.log"
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        gate_out "GATE_P5_CP_UNIT: BLOCKED_COMPILE_ERROR"
        exit 1
    fi

    echo "=== [3] xsim ==="
    ( cd "${ROOT}" && xsim --nolog p5_cp_unit_snap --runall \
            --log "${SIM_LOG}" ) \
        2>&1 | tee "${LOG_DIR}/p5_cp_unit_xsim_console.log"

elif [[ "${SIM_TOOL}" == "iverilog" ]]; then
    if ! command -v iverilog &>/dev/null; then
        gate_out "GATE_P5_CP_UNIT: BLOCKED_IVERILOG_UNAVAILABLE"
        echo "  iverilog not found in PATH."
        exit 1
    fi

    VVP="${LOG_DIR}/p5_cp_unit.vvp"

    echo "=== [1] iverilog: compile ==="
    iverilog -g2012 \
             -o "${VVP}" \
             "${RTL_SRCS[@]}" \
             "${TB_SRC}" \
             2>&1 | tee "${LOG_DIR}/p5_cp_unit_compile.log"
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        gate_out "GATE_P5_CP_UNIT: BLOCKED_COMPILE_ERROR"
        exit 1
    fi
    echo "  Compile OK: ${VVP}"

    echo ""
    echo "=== [2] vvp: simulate ==="
    ( cd "${ROOT}" && vvp "${VVP}" ) 2>&1 | tee "${SIM_LOG}"

else
    echo "ERROR: Unknown simulator '${SIM_TOOL}'." >&2
    gate_out "GATE_P5_CP_UNIT: BLOCKED_UNKNOWN_SIM"
    exit 1
fi

# --------------------------------------------------------------------------
# Gate evaluation
# --------------------------------------------------------------------------
echo ""
echo "--- Gate evaluation ---"

if grep -qE "^GATE_P5_CP_UNIT: PASS$" "${SIM_LOG}" 2>/dev/null; then
    gate_out "GATE_P5_CP_UNIT: PASS"
    grep -E "Peak (sample_idx|\|P\|)|Captured beats" "${SIM_LOG}" 2>/dev/null || true
    exit 0
elif grep -qE "^GATE_P5_CP_UNIT: FAIL$" "${SIM_LOG}" 2>/dev/null; then
    gate_out "GATE_P5_CP_UNIT: FAIL"
    grep -E "Peak (sample_idx|\|P\|)|REASON|WDG:" "${SIM_LOG}" 2>/dev/null | head -10 || true
    exit 1
else
    gate_out "GATE_P5_CP_UNIT: FAIL"
    echo "  No gate line found in simulation log."
    echo "  See: ${SIM_LOG}"
    exit 1
fi
