#!/usr/bin/env bash
# run_p5_frac_unit.sh — P5-FRAC-UNIT: frac_cfo_estimator unit regression
#
# DUT  : rtl/frac_cfo_estimator.v  +  rtl/cordic_atan2.v
# TB   : tb/p5_frac_cfo_estimator_unit_tb.sv
# Gold : golden/p5_frac_cfo_golden.csv   (regenerated if missing)
#
# GATE OUTPUT (exactly one):
#   GATE_P5_FRAC_UNIT: PASS                       — all cases within ±32 LSB
#   GATE_P5_FRAC_UNIT: FAIL  pass=X/N             — at least one case out of band
#   GATE_P5_FRAC_UNIT: BLOCKED_*                  — pre-flight dep missing
#
# USAGE:
#   bash scripts/run_p5_frac_unit.sh [OPTIONS]
#
#   Options:
#     --sim iverilog|xsim    simulator (default: iverilog)
#     --log-dir DIR          override log directory (default: sim_out/p5_frac_unit)
#
# EXIT CODES:
#   0  GATE_P5_FRAC_UNIT: PASS
#   1  any other gate outcome

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SIM_TOOL="iverilog"
LOG_DIR="${ROOT}/sim_out/p5_frac_unit"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --sim)     shift; SIM_TOOL="$1" ;;
        --log-dir) shift; LOG_DIR="$1"  ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
    shift
done

mkdir -p "${LOG_DIR}"
GATE_LOG="${LOG_DIR}/p5_frac_unit_gate.txt"
SIM_LOG="${LOG_DIR}/p5_frac_unit_sim.log"

gate_out() {
    local msg="$1"
    echo ""
    echo "========================================================================"
    echo "${msg}"
    echo "========================================================================"
    echo "${msg}" > "${GATE_LOG}"
}

echo "========================================================================"
echo "P5-FRAC-UNIT  frac_cfo_estimator unit regression"
echo "  Date       : $(date '+%Y-%m-%d %H:%M:%S')"
echo "  Simulator  : ${SIM_TOOL}"
echo "  Log dir    : ${LOG_DIR}"
echo "  Root       : ${ROOT}"
echo "========================================================================"

# --------------------------------------------------------------------------
# Golden vectors — regenerate if missing
# --------------------------------------------------------------------------
GOLDEN="${ROOT}/golden/p5_frac_cfo_golden.csv"
GOLDEN_GEN="${ROOT}/scripts/gen_p5_frac_cfo_golden.py"
echo ""
echo "--- Golden vectors ---"
if [[ ! -f "${GOLDEN}" ]]; then
    if [[ ! -f "${GOLDEN_GEN}" ]]; then
        gate_out "GATE_P5_FRAC_UNIT: BLOCKED_MISSING_GOLDEN_GENERATOR"
        echo "  Missing: ${GOLDEN_GEN}"
        exit 1
    fi
    echo "  Generating golden via $(basename ${GOLDEN_GEN}) ..."
    python3 "${GOLDEN_GEN}" 2>&1 | tee "${LOG_DIR}/p5_frac_unit_golden_gen.log"
    if [[ ! -f "${GOLDEN}" ]]; then
        gate_out "GATE_P5_FRAC_UNIT: BLOCKED_GOLDEN_GEN_FAILED"
        exit 1
    fi
fi
echo "  [OK]   $(basename ${GOLDEN})  ($(wc -l <"${GOLDEN}") lines)"

# --------------------------------------------------------------------------
# RTL sources (minimal — frac_cfo_estimator only depends on cordic_atan2)
# --------------------------------------------------------------------------
RTL_SRCS=(
    "${ROOT}/rtl/cordic_atan2.v"
    "${ROOT}/rtl/frac_cfo_estimator.v"
)

TB_SRC="${ROOT}/tb/p5_frac_cfo_estimator_unit_tb.sv"

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
        echo "  [OK]   ${f#${ROOT}/}"
    fi
done
if [[ "${BLOCKED}" -eq 1 ]]; then
    gate_out "GATE_P5_FRAC_UNIT: BLOCKED_MISSING_FILES"
    exit 1
fi

# --------------------------------------------------------------------------
# Run simulation
# --------------------------------------------------------------------------
echo ""

if [[ "${SIM_TOOL}" == "xsim" ]]; then
    if ! command -v xvlog &>/dev/null; then
        gate_out "GATE_P5_FRAC_UNIT: BLOCKED_XSIM_UNAVAILABLE"
        echo "  xvlog not found in PATH."
        exit 1
    fi

    echo "=== [1] xvlog ==="
    xvlog --nolog -sv "${RTL_SRCS[@]}" "${TB_SRC}" 2>&1 | tee "${LOG_DIR}/p5_frac_unit_xvlog.log"
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        gate_out "GATE_P5_FRAC_UNIT: BLOCKED_COMPILE_ERROR"
        exit 1
    fi

    echo "=== [2] xelab ==="
    xelab --nolog -debug typical \
          p5_frac_cfo_estimator_unit_tb \
          -snapshot p5_frac_unit_snap \
          2>&1 | tee "${LOG_DIR}/p5_frac_unit_xelab.log"
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        gate_out "GATE_P5_FRAC_UNIT: BLOCKED_COMPILE_ERROR"
        exit 1
    fi

    echo "=== [3] xsim ==="
    ( cd "${ROOT}" && xsim --nolog p5_frac_unit_snap \
         --runall \
         --log "${SIM_LOG}" \
         2>&1 | tee "${LOG_DIR}/p5_frac_unit_xsim_console.log" )

elif [[ "${SIM_TOOL}" == "iverilog" ]]; then
    if ! command -v iverilog &>/dev/null; then
        gate_out "GATE_P5_FRAC_UNIT: BLOCKED_IVERILOG_UNAVAILABLE"
        echo "  iverilog not found in PATH."
        exit 1
    fi

    VVP="${LOG_DIR}/p5_frac_unit.vvp"

    echo "=== [1] iverilog: compile ==="
    iverilog -g2012 \
             -o "${VVP}" \
             "${RTL_SRCS[@]}" \
             "${TB_SRC}" \
             2>&1 | tee "${LOG_DIR}/p5_frac_unit_compile.log"
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        gate_out "GATE_P5_FRAC_UNIT: BLOCKED_COMPILE_ERROR"
        exit 1
    fi
    echo "  Compile OK: ${VVP}"

    echo ""
    echo "=== [2] vvp: simulate ==="
    # Run from ROOT so the TB's relative `golden/...` path resolves.
    ( cd "${ROOT}" && vvp "${VVP}" 2>&1 | tee "${SIM_LOG}" )

else
    echo "ERROR: Unknown simulator '${SIM_TOOL}'." >&2
    gate_out "GATE_P5_FRAC_UNIT: BLOCKED_UNKNOWN_SIM"
    exit 1
fi

# --------------------------------------------------------------------------
# Gate evaluation
# --------------------------------------------------------------------------
echo ""
echo "--- Gate evaluation ---"

if grep -qE "^GATE_P5_FRAC_UNIT: PASS$" "${SIM_LOG}" 2>/dev/null; then
    gate_out "GATE_P5_FRAC_UNIT: PASS"
    grep -E "^\[P5-FRAC\] summary" "${SIM_LOG}" 2>/dev/null || true
    exit 0
elif grep -qE "^GATE_P5_FRAC_UNIT: FAIL" "${SIM_LOG}" 2>/dev/null; then
    gate_out "GATE_P5_FRAC_UNIT: FAIL"
    grep -E "^GATE_P5_FRAC_UNIT: FAIL" "${SIM_LOG}" | head -1 || true
    grep -E "FAIL$" "${SIM_LOG}" | head -10 || true
    exit 1
elif grep -qE "^WDG: " "${SIM_LOG}" 2>/dev/null; then
    gate_out "GATE_P5_FRAC_UNIT: FAIL"
    echo "  Simulation watchdog tripped."
    grep -E "^WDG:" "${SIM_LOG}" | head -5 || true
    exit 1
else
    gate_out "GATE_P5_FRAC_UNIT: FAIL"
    echo "  No gate line found in simulation log."
    echo "  See: ${SIM_LOG}"
    exit 1
fi
