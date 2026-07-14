#!/usr/bin/env bash
# run_p5_rotator_unit.sh — P5-ROT-UNIT Regression
#
# DUT : rtl/complex_rotator.v   (wraps complex_mult_iq with CONJ_B=1)
# TB  : tb/p5_complex_rotator_unit_tb.sv
# Gen : scripts/gen_p5_rotator_golden.py -> golden/p5_rotator_golden.csv
#
# GATE OUTPUT (exactly one):
#   GATE_P5_ROT_UNIT: PASS      — all cases within TOL
#   GATE_P5_ROT_UNIT: FAIL      — at least one case outside TOL or timeout
#   GATE_P5_ROT_UNIT: BLOCKED_* — pre-flight dependency missing
#
# USAGE:
#   bash scripts/run_p5_rotator_unit.sh [OPTIONS]
#
#   Options:
#     --sim iverilog|xsim    simulator (default: iverilog)
#     --log-dir DIR          override log directory (default: sim_out/p5_rotator_unit)
#
# EXIT CODES:
#   0   GATE_P5_ROT_UNIT: PASS
#   1   any other gate outcome

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SIM_TOOL="iverilog"
LOG_DIR="${ROOT}/sim_out/p5_rotator_unit"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --sim)     shift; SIM_TOOL="$1" ;;
        --log-dir) shift; LOG_DIR="$1"  ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
    shift
done

mkdir -p "${LOG_DIR}"
GATE_LOG="${LOG_DIR}/p5_rotator_unit_gate.txt"
SIM_LOG="${LOG_DIR}/p5_rotator_unit_sim.log"

gate_out() {
    local msg="$1"
    echo ""
    echo "========================================================================"
    echo "${msg}"
    echo "========================================================================"
    echo "${msg}" > "${GATE_LOG}"
}

echo "========================================================================"
echo "P5-ROT-UNIT (complex_rotator unit testbench)"
echo "  Date       : $(date '+%Y-%m-%d %H:%M:%S')"
echo "  Simulator  : ${SIM_TOOL}"
echo "  Log dir    : ${LOG_DIR}"
echo "  Root       : ${ROOT}"
echo "========================================================================"

# --------------------------------------------------------------------------
# Golden CSV (regenerate if missing)
# --------------------------------------------------------------------------
echo ""
echo "--- Golden CSV ---"
GOLDEN_CSV="${ROOT}/golden/p5_rotator_golden.csv"
if [[ ! -f "${GOLDEN_CSV}" ]]; then
    echo "  generating: ${GOLDEN_CSV}"
    if ! python3 "${ROOT}/scripts/gen_p5_rotator_golden.py" ; then
        gate_out "GATE_P5_ROT_UNIT: BLOCKED_GOLDEN_GEN_FAILED"
        exit 1
    fi
else
    echo "  [OK]   $(basename ${GOLDEN_CSV})"
fi

# --------------------------------------------------------------------------
# RTL sources (DUT + its only dependency)
# --------------------------------------------------------------------------
RTL_SRCS=(
    "${ROOT}/rtl/complex_mult_iq.v"
    "${ROOT}/rtl/complex_rotator.v"
)

TB_SRC="${ROOT}/tb/p5_complex_rotator_unit_tb.sv"

# --------------------------------------------------------------------------
# Pre-flight: required files
# --------------------------------------------------------------------------
echo ""
echo "--- Required files ---"
BLOCKED=0
for f in "${RTL_SRCS[@]}" "${TB_SRC}" "${GOLDEN_CSV}"; do
    if [[ ! -f "$f" ]]; then
        echo "  [MISS] $f"
        BLOCKED=1
    else
        echo "  [OK]   $(basename $f)"
    fi
done
if [[ "${BLOCKED}" -eq 1 ]]; then
    gate_out "GATE_P5_ROT_UNIT: BLOCKED_MISSING_FILES"
    exit 1
fi

# --------------------------------------------------------------------------
# Run simulation
# --------------------------------------------------------------------------
echo ""

if [[ "${SIM_TOOL}" == "xsim" ]]; then
    if ! command -v xvlog &>/dev/null; then
        gate_out "GATE_P5_ROT_UNIT: BLOCKED_XSIM_UNAVAILABLE"
        echo "  xvlog not found in PATH."
        exit 1
    fi

    pushd "${LOG_DIR}" >/dev/null

    echo "=== [1] xvlog ==="
    xvlog --nolog -sv "${RTL_SRCS[@]}" "${TB_SRC}" 2>&1 | tee "${LOG_DIR}/p5_rotator_unit_xvlog.log"
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        gate_out "GATE_P5_ROT_UNIT: BLOCKED_COMPILE_ERROR"
        popd >/dev/null
        exit 1
    fi

    echo "=== [2] xelab ==="
    xelab --nolog -debug typical \
          p5_complex_rotator_unit_tb \
          -snapshot p5_rotator_unit_snap \
          2>&1 | tee "${LOG_DIR}/p5_rotator_unit_xelab.log"
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        gate_out "GATE_P5_ROT_UNIT: BLOCKED_COMPILE_ERROR"
        popd >/dev/null
        exit 1
    fi

    echo "=== [3] xsim ==="
    xsim --nolog p5_rotator_unit_snap \
         --runall \
         --log "${SIM_LOG}" \
         2>&1 | tee "${LOG_DIR}/p5_rotator_unit_xsim_console.log"

    popd >/dev/null

elif [[ "${SIM_TOOL}" == "iverilog" ]]; then
    IVERILOG_BIN="${IVERILOG_BIN:-/usr/bin/iverilog}"
    VVP_BIN="${VVP_BIN:-/usr/bin/vvp}"
    if [[ ! -x "${IVERILOG_BIN}" ]]; then
        if command -v iverilog &>/dev/null; then
            IVERILOG_BIN="$(command -v iverilog)"
        else
            gate_out "GATE_P5_ROT_UNIT: BLOCKED_IVERILOG_UNAVAILABLE"
            echo "  iverilog not found."
            exit 1
        fi
    fi
    if [[ ! -x "${VVP_BIN}" ]]; then
        if command -v vvp &>/dev/null; then
            VVP_BIN="$(command -v vvp)"
        else
            gate_out "GATE_P5_ROT_UNIT: BLOCKED_VVP_UNAVAILABLE"
            echo "  vvp not found."
            exit 1
        fi
    fi

    VVP="${LOG_DIR}/p5_rotator_unit.vvp"

    echo "=== [1] iverilog: compile ==="
    "${IVERILOG_BIN}" -g2012 \
             -o "${VVP}" \
             "${RTL_SRCS[@]}" \
             "${TB_SRC}" \
             2>&1 | tee "${LOG_DIR}/p5_rotator_unit_compile.log"
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        gate_out "GATE_P5_ROT_UNIT: BLOCKED_COMPILE_ERROR"
        exit 1
    fi
    echo "  Compile OK: ${VVP}"

    echo ""
    echo "=== [2] vvp: simulate (cwd=${ROOT}) ==="
    # cwd must be ROOT so the TB can open golden/p5_rotator_golden.csv via relpath
    (cd "${ROOT}" && "${VVP_BIN}" "${VVP}") 2>&1 | tee "${SIM_LOG}"

else
    echo "ERROR: Unknown simulator '${SIM_TOOL}'." >&2
    gate_out "GATE_P5_ROT_UNIT: BLOCKED_UNKNOWN_SIM"
    exit 1
fi

# --------------------------------------------------------------------------
# Gate evaluation
# --------------------------------------------------------------------------
echo ""
echo "--- Gate evaluation ---"

if grep -qE "^GATE_P5_ROT_UNIT: PASS$" "${SIM_LOG}" 2>/dev/null; then
    gate_out "GATE_P5_ROT_UNIT: PASS"
    grep -E "^\[P5-ROT\] summary" "${SIM_LOG}" 2>/dev/null || true
    exit 0
elif grep -qE "^GATE_P5_ROT_UNIT: FAIL$" "${SIM_LOG}" 2>/dev/null; then
    gate_out "GATE_P5_ROT_UNIT: FAIL"
    grep -E "^\[P5-ROT\] (summary|case\[[0-9]+\].*FAIL)" "${SIM_LOG}" 2>/dev/null | head -20 || true
    exit 1
elif grep -qE "^WDG: TIMEOUT" "${SIM_LOG}" 2>/dev/null; then
    gate_out "GATE_P5_ROT_UNIT: FAIL"
    echo "  Simulation timed out."
    exit 1
else
    gate_out "GATE_P5_ROT_UNIT: FAIL"
    echo "  No gate line found in simulation log."
    echo "  See: ${SIM_LOG}"
    exit 1
fi

echo ""
echo "========================================================================"
echo "Logs:"
echo "  Gate : ${GATE_LOG}"
echo "  Sim  : ${SIM_LOG}"
echo "========================================================================"
