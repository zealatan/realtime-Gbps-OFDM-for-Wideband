#!/usr/bin/env bash
# run_session_L_p3_23a_stress.sh — P3-23A Multi-Frame and Reset Stress Runner
#
# Usage:
#   bash scripts/run_session_L_p3_23a_stress.sh [--sim iverilog|xsim]
#
# Default simulator: iverilog  (produces SANITY_STRESS_GATE only)
# xsim (Vivado) produces official STRESS_GATE; requires Vivado WSL2 interop.
#
# Gate policy:
#   iverilog: SANITY_STRESS_GATE: PASS / FAIL
#   xsim:     STRESS_GATE: PASS / FAIL
#
# Watchdog: 2500000 cycles (~20 full frames)
# Expected runtime: ~2M cycles, ~15-20 seconds in iverilog

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SIM_TOOL="iverilog"

for arg in "$@"; do
    case "$arg" in
        --sim) ;;
        iverilog|xsim) SIM_TOOL="$arg" ;;
    esac
done

# Consume --sim VALUE pairs
while [[ $# -gt 0 ]]; do
    case "$1" in
        --sim) SIM_TOOL="$2"; shift 2 ;;
        *) shift ;;
    esac
done 2>/dev/null || true

echo ""
echo "=== session_L_p3_23a_stress ==="
echo "    Simulator: ${SIM_TOOL}"
echo ""

# --------------------------------------------------------------------------
# Production DUT source list — single source of truth.
# --------------------------------------------------------------------------
FILELIST="${ROOT}/scripts/phase3_dut_filelist.f"
mapfile -t DUT_SRCS < <(grep -v '^#' "${FILELIST}" | grep -v '^[[:space:]]*$' | sed "s|^|${ROOT}/|")

TB_SRC="${ROOT}/tb/session_L_p3_23a_stress_tb.sv"

# --------------------------------------------------------------------------
# Pre-flight checks
# --------------------------------------------------------------------------
echo "--- Pre-flight checks ---"
BLOCKED=0

if [[ ! -f "${ROOT}/golden/phase3_iq_stimulus.mem" ]]; then
    echo "  BLOCKED: golden/phase3_iq_stimulus.mem not found"
    echo "           Run: python3 scripts/gen_phase3_iq_stimulus.py"
    BLOCKED=1
fi

for f in "${DUT_SRCS[@]}" "${TB_SRC}"; do
    if [[ ! -f "$f" ]]; then
        echo "  MISSING: $f"
        BLOCKED=1
    fi
done

if [[ "${BLOCKED}" -eq 1 ]]; then
    echo ""
    echo "SANITY_STRESS_GATE: BLOCKED_PREREQ"
    exit 1
fi
echo "  All required files present."

# --------------------------------------------------------------------------
# Output directories
# --------------------------------------------------------------------------
mkdir -p "${ROOT}/sim_out/session_L_p3_23a"
mkdir -p "${ROOT}/logs"
mkdir -p "${ROOT}/reports/session_L_p3_23a"

SIM_LOG="${ROOT}/logs/session_L_p3_23a_sim.log"
VVP_OUT="${ROOT}/sim_out/session_L_p3_23a/session_L_p3_23a.vvp"
GATE_FILE="${ROOT}/reports/session_L_p3_23a/stress_gate.txt"

# --------------------------------------------------------------------------
# iverilog path
# --------------------------------------------------------------------------
if [[ "${SIM_TOOL}" == "xsim" ]]; then
    echo ""
    echo "xsim path: invoke from Windows Vivado or set VIVADO_BIN."
    echo "SANITY_STRESS_GATE: BLOCKED_XSIM_UNAVAILABLE"
    exit 1
fi

if ! command -v iverilog &>/dev/null; then
    echo "SANITY_STRESS_GATE: BLOCKED_IVERILOG_NOT_FOUND"
    exit 1
fi

# --------------------------------------------------------------------------
# Compile
# --------------------------------------------------------------------------
echo ""
echo "=== [1] iverilog: compile ==="
iverilog -g2012 \
    -I "${ROOT}/vectors" \
    -o "${VVP_OUT}" \
    "${DUT_SRCS[@]}" \
    "${TB_SRC}" \
    2>&1 | tee "${ROOT}/logs/session_L_p3_23a_compile.log"

if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    echo "SANITY_STRESS_GATE: FAIL (compile error)"
    exit 1
fi
echo "  Compile: OK"

# --------------------------------------------------------------------------
# Simulate
# --------------------------------------------------------------------------
echo ""
echo "=== [2] vvp: simulate (watchdog=2500000 cycles) ==="
echo "    This runs L1 (10 frames), L2, L3, L4 in one pass."
echo "    Expected time: ~15-25 seconds."
echo ""

cd "${ROOT}"
vvp "${VVP_OUT}" 2>&1 | tee "${SIM_LOG}"
SIM_EXIT=${PIPESTATUS[0]}
cd - >/dev/null

# --------------------------------------------------------------------------
# Parse gate result
# --------------------------------------------------------------------------
echo ""
echo "=== [3] Gate ==="

STRESS_RESULT=$(grep -E "^STRESS_GATE:" "${SIM_LOG}" | tail -1 || echo "")

if [[ -z "${STRESS_RESULT}" ]]; then
    echo "SANITY_STRESS_GATE: FAIL (no gate line in simulation output)"
    echo "SANITY_STRESS_GATE: FAIL (no gate line found)" > "${GATE_FILE}"
    exit 1
fi

# Prepend SANITY_ for iverilog gate
GATE_LABEL="SANITY_${STRESS_RESULT}"
echo "${GATE_LABEL}"
echo "  Sim log: ${SIM_LOG}"

{
    echo "${GATE_LABEL}"
    echo "Simulator: iverilog"
    echo "Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo ""
    grep -E "^\[L[1234]\]|PASS|FAIL|STRESS|checks" "${SIM_LOG}" || true
} > "${GATE_FILE}"

if echo "${STRESS_RESULT}" | grep -q "PASS"; then
    exit 0
else
    exit 1
fi
