#!/usr/bin/env bash
# run_p5_nco_unit.sh — P5 NCO phase-gen unit TB
#
# DUT: rtl/nco_phase_gen.v
# TB : tb/p5_nco_phase_gen_unit_tb.sv
#
# Verifies the 32-bit phase accumulator behavior in isolation:
#   A) Zero step -> phase stays 0
#   B) Constant +step monotonic accumulation
#   C) Constant -step monotonic accumulation
#   D) Wrap-around at 2^32
#   E) Random steps, expected = sum(steps) mod 2^32
#
# GATE OUTPUT (exactly one):
#   GATE_P5_NCO_UNIT: PASS         — all 5 subtests pass
#   GATE_P5_NCO_UNIT: FAIL         — one or more subtests fail (or watchdog)
#   GATE_P5_NCO_UNIT: BLOCKED_*    — pre-flight dependency missing
#
# USAGE:
#   bash scripts/run_p5_nco_unit.sh [--sim iverilog|xsim] [--log-dir DIR]
#
# EXIT CODES:
#   0  GATE_P5_NCO_UNIT: PASS
#   1  any other gate outcome

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SIM_TOOL="iverilog"
LOG_DIR="${ROOT}/sim_out/p5_nco_unit"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --sim)     shift; SIM_TOOL="$1" ;;
        --log-dir) shift; LOG_DIR="$1"  ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
    shift
done

mkdir -p "${LOG_DIR}"
GATE_LOG="${LOG_DIR}/p5_nco_unit_gate.txt"
SIM_LOG="${LOG_DIR}/p5_nco_unit_sim.log"

gate_out() {
    local msg="$1"
    echo ""
    echo "========================================================================"
    echo "${msg}"
    echo "========================================================================"
    echo "${msg}" > "${GATE_LOG}"
}

echo "========================================================================"
echo "P5 NCO phase-gen unit TB"
echo "  Date       : $(date '+%Y-%m-%d %H:%M:%S')"
echo "  Simulator  : ${SIM_TOOL}"
echo "  Log dir    : ${LOG_DIR}"
echo "  Root       : ${ROOT}"
echo "========================================================================"

# --------------------------------------------------------------------------
# Source list
# --------------------------------------------------------------------------
RTL_SRCS=(
    "${ROOT}/rtl/nco_phase_gen.v"
)
TB_SRC="${ROOT}/tb/p5_nco_phase_gen_unit_tb.sv"

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
        echo "  [OK]   $f"
    fi
done
if [[ "${BLOCKED}" -eq 1 ]]; then
    gate_out "GATE_P5_NCO_UNIT: BLOCKED_MISSING_FILES"
    exit 1
fi

# --------------------------------------------------------------------------
# Run simulation
# --------------------------------------------------------------------------
echo ""

if [[ "${SIM_TOOL}" == "xsim" ]]; then
    if ! command -v xvlog &>/dev/null; then
        gate_out "GATE_P5_NCO_UNIT: BLOCKED_XSIM_UNAVAILABLE"
        echo "  xvlog not found in PATH."
        exit 1
    fi

    echo "=== [1] xvlog ==="
    xvlog --nolog -sv "${RTL_SRCS[@]}" "${TB_SRC}" 2>&1 \
        | tee "${LOG_DIR}/p5_nco_unit_xvlog.log"
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        gate_out "GATE_P5_NCO_UNIT: BLOCKED_COMPILE_ERROR"
        exit 1
    fi

    echo "=== [2] xelab ==="
    xelab --nolog -debug typical \
          p5_nco_phase_gen_unit_tb \
          -snapshot p5_nco_unit_snap \
          2>&1 | tee "${LOG_DIR}/p5_nco_unit_xelab.log"
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        gate_out "GATE_P5_NCO_UNIT: BLOCKED_COMPILE_ERROR"
        exit 1
    fi

    echo "=== [3] xsim ==="
    xsim --nolog p5_nco_unit_snap --runall --log "${SIM_LOG}" 2>&1 \
        | tee "${LOG_DIR}/p5_nco_unit_xsim_console.log"

elif [[ "${SIM_TOOL}" == "iverilog" ]]; then
    IVERILOG_BIN="/usr/bin/iverilog"
    VVP_BIN="/usr/bin/vvp"
    if [[ ! -x "${IVERILOG_BIN}" ]]; then
        if ! command -v iverilog &>/dev/null; then
            gate_out "GATE_P5_NCO_UNIT: BLOCKED_IVERILOG_UNAVAILABLE"
            echo "  iverilog not found."
            exit 1
        fi
        IVERILOG_BIN="$(command -v iverilog)"
        VVP_BIN="$(command -v vvp)"
    fi

    VVP="${LOG_DIR}/p5_nco_unit.vvp"

    echo "=== [1] iverilog: compile ==="
    "${IVERILOG_BIN}" -g2012 \
                      -o "${VVP}" \
                      "${RTL_SRCS[@]}" \
                      "${TB_SRC}" \
                      2>&1 | tee "${LOG_DIR}/p5_nco_unit_compile.log"
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        gate_out "GATE_P5_NCO_UNIT: BLOCKED_COMPILE_ERROR"
        exit 1
    fi
    echo "  Compile OK: ${VVP}"

    echo ""
    echo "=== [2] vvp: simulate ==="
    "${VVP_BIN}" "${VVP}" 2>&1 | tee "${SIM_LOG}"

else
    echo "ERROR: Unknown simulator '${SIM_TOOL}'." >&2
    gate_out "GATE_P5_NCO_UNIT: BLOCKED_UNKNOWN_SIM"
    exit 1
fi

# --------------------------------------------------------------------------
# Gate evaluation
# --------------------------------------------------------------------------
echo ""
echo "--- Gate evaluation ---"

if grep -qE "^GATE_P5_NCO_UNIT: PASS$" "${SIM_LOG}" 2>/dev/null; then
    gate_out "GATE_P5_NCO_UNIT: PASS"
    echo "  All 5 subtests passed."
    echo ""
    grep -E "^\[P5-NCO\]" "${SIM_LOG}" 2>/dev/null || true
    exit 0
elif grep -qE "^GATE_P5_NCO_UNIT: FAIL$" "${SIM_LOG}" 2>/dev/null; then
    gate_out "GATE_P5_NCO_UNIT: FAIL"
    grep -E "^\[P5-NCO\]|^WDG:|^  REASON" "${SIM_LOG}" 2>/dev/null | head -40 || true
    exit 1
elif grep -qE "^WDG: TIMEOUT" "${SIM_LOG}" 2>/dev/null; then
    gate_out "GATE_P5_NCO_UNIT: FAIL"
    echo "  Simulation watchdog timeout."
    grep -E "^WDG:" "${SIM_LOG}" | head -5 || true
    exit 1
else
    gate_out "GATE_P5_NCO_UNIT: FAIL"
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
