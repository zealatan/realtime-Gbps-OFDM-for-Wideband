#!/usr/bin/env bash
# run_session_I_p3_20a_axi_backpressure_stress.sh — Session I / P3-20A
#
# AXI4-Stream protocol + backpressure stress test runner.
#
# Tests:
#   I1: S_AXIS input stall probabilities (0/10/25/50%) — frame detection + output_count
#   I2: M_AXIS output stall probabilities (0/10/25/50%) — no deadlock, no sample loss
#   I3: M_AXIS burst stall durations (1/4/8/16/32 cycles) — replay resume correct
#   I4: AXI4-Stream tvalid/tdata/tlast stability assertions
#
# Gate:
#   AXI_GATE: PASS  — all 12 test cases pass, 0 AXI assertion violations
#   AXI_GATE: FAIL  — any test case fails or any assertion fires
#
# When using iverilog (not xsim):
#   SANITY_AXI_GATE: PASS (iverilog)
#   (official CI_GATE requires xsim)
#
# Usage:
#   ./scripts/run_session_I_p3_20a_axi_backpressure_stress.sh [--sim xsim|iverilog]
#
# Options:
#   --sim   xsim|iverilog     Simulator (default: iverilog)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SIM_TOOL="iverilog"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --sim) SIM_TOOL="$2"; shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

LOGS="${ROOT}/logs"
SIM_OUT="${ROOT}/sim_out/session_I_p3_20a"
REPORTS="${ROOT}/reports/session_I_p3_20a"

mkdir -p "${LOGS}" "${SIM_OUT}" "${REPORTS}"

cd "${ROOT}"

COMPILE_LOG="${LOGS}/session_I_p3_20a_compile.log"
SIM_LOG="${SIM_OUT}/session_I_p3_20a_sim.log"
SIM_VVP="${SIM_OUT}/session_I_p3_20a.vvp"
REPORT="${REPORTS}/axi_backpressure_stress_result.txt"

TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"

echo "============================================================"
echo " Session I / P3-20A — AXI Backpressure Stress"
echo " Simulator: ${SIM_TOOL}"
echo " Time:      ${TIMESTAMP}"
echo "============================================================"

# ---------------------------------------------------------------------------
# Production DUT source list — single source of truth.
# ---------------------------------------------------------------------------
FILELIST="${ROOT}/scripts/phase3_dut_filelist.f"
mapfile -t DUT_SRCS < <(grep -v '^#' "${FILELIST}" | grep -v '^[[:space:]]*$' | sed "s|^|${ROOT}/|")

TB_SRC="${ROOT}/tb/session_I_p3_20a_axi_backpressure_stress_tb.sv"

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------

echo ""
echo "--- Pre-flight checks ---"
MISSING=0
for f in "${DUT_SRCS[@]}" "${TB_SRC}"; do
    if [[ ! -f "$f" ]]; then
        echo "  MISSING: $f" >&2
        MISSING=1
    fi
done
if [[ ${MISSING} -ne 0 ]]; then
    echo "ERROR: Missing source files — aborting" >&2; exit 1
fi
echo "  All source files present: OK"

# ---------------------------------------------------------------------------
# Compile and simulate
# ---------------------------------------------------------------------------

echo ""
echo "--- Step 1: Compile + Simulate ---"

if [[ "${SIM_TOOL}" == "iverilog" ]]; then
    command -v iverilog &>/dev/null || {
        echo "BLOCKED_IVERILOG_UNAVAILABLE" >&2; exit 1
    }
    echo "  Compiling with iverilog..."
    iverilog -g2012 \
        -I "${ROOT}/vectors" \
        -o "${SIM_VVP}" \
        "${DUT_SRCS[@]}" \
        "${TB_SRC}" \
        2>&1 | tee "${COMPILE_LOG}"
    COMPILE_EXIT="${PIPESTATUS[0]}"
    if [[ ${COMPILE_EXIT} -ne 0 ]]; then
        echo "ERROR: iverilog compile failed (exit ${COMPILE_EXIT})" >&2
        echo "  See: ${COMPILE_LOG}" >&2; exit 1
    fi
    echo "  Compile: OK"
    echo "  Simulating (this may take several minutes) ..."
    vvp "${SIM_VVP}" 2>&1 | tee "${SIM_LOG}"
    SIM_EXIT="${PIPESTATUS[0]}"

elif [[ "${SIM_TOOL}" == "xsim" ]]; then
    command -v xvlog &>/dev/null || {
        echo "BLOCKED_XSIM_UNAVAILABLE"; exit 1
    }
    WORK="${ROOT}/sim_out/session_I_p3_20a_work"
    mkdir -p "${WORK}"
    pushd "${WORK}" > /dev/null
    xvlog --nolog "${DUT_SRCS[@]}" 2>&1 | tee "${COMPILE_LOG}"
    xvlog --nolog -sv "${TB_SRC}" 2>&1 | tee -a "${COMPILE_LOG}"
    xelab --nolog -debug typical session_I_p3_20a_axi_backpressure_stress_tb \
        -s session_I_p3_20a_sim 2>&1 | tee -a "${COMPILE_LOG}"
    COMPILE_EXIT="${PIPESTATUS[0]}"
    if [[ ${COMPILE_EXIT} -ne 0 ]]; then
        echo "ERROR: xsim compile failed (exit ${COMPILE_EXIT})" >&2; exit 1
    fi
    xsim session_I_p3_20a_sim --nolog --runall 2>&1 | tee "${SIM_LOG}"
    SIM_EXIT="${PIPESTATUS[0]}"
    popd > /dev/null
else
    echo "ERROR: Unknown simulator: ${SIM_TOOL}" >&2; exit 1
fi

if [[ ${SIM_EXIT} -ne 0 ]]; then
    echo "WARN: Simulator exited with non-zero status ${SIM_EXIT} (may be $finish)" >&2
fi
echo "  Simulation complete."

# ---------------------------------------------------------------------------
# Step 2: Parse results
# ---------------------------------------------------------------------------

echo ""
echo "--- Step 2: Parse gate result ---"

# Extract AXI_GATE line from sim log
GATE_RAW=""
if grep -q "AXI_GATE: PASS" "${SIM_LOG}" 2>/dev/null; then
    GATE_RAW="PASS"
elif grep -q "AXI_GATE: FAIL" "${SIM_LOG}" 2>/dev/null; then
    GATE_RAW="FAIL"
else
    GATE_RAW="UNKNOWN"
fi

# Extract per-test PASS/FAIL lines (TB format: "[PASS] TCn-Cx:" and "[FAIL] TCn-Cx:")
TC_PASS=$(grep -c "\[PASS\] TC" "${SIM_LOG}" 2>/dev/null || true)
TC_FAIL=$(grep -c "\[FAIL\] TC" "${SIM_LOG}" 2>/dev/null || true)
AXI_ASSERT_FAIL=$(grep -c "\[I4[abcABC] FAIL\]" "${SIM_LOG}" 2>/dev/null || true)
WATCHDOG_HIT=$(grep -c "WATCHDOG" "${SIM_LOG}" 2>/dev/null || true)

echo "  Test cases PASS : ${TC_PASS}"
echo "  Test cases FAIL : ${TC_FAIL}"
echo "  AXI assert fails: ${AXI_ASSERT_FAIL}"
echo "  Watchdog hits   : ${WATCHDOG_HIT}"
echo "  Gate raw        : ${GATE_RAW}"

# ---------------------------------------------------------------------------
# Step 3: Print gate line
# ---------------------------------------------------------------------------

echo ""
echo "--- Gate ---"

if [[ "${SIM_TOOL}" == "iverilog" ]]; then
    case "${GATE_RAW}" in
        PASS)
            echo "SANITY_AXI_GATE: PASS (iverilog)"
            echo "  All test cases PASS — I1/I2/I3/I4 complete."
            echo "  NOTE: iverilog sanity only; xsim required for official CI_GATE PASS."
            GATE_LINE="SANITY_AXI_GATE: PASS (iverilog)"
            ;;
        FAIL)
            echo "SANITY_AXI_GATE: FAIL (iverilog)"
            echo "  One or more test cases FAIL — see sim log."
            GATE_LINE="SANITY_AXI_GATE: FAIL (iverilog)"
            ;;
        *)
            echo "SANITY_AXI_GATE: UNKNOWN (iverilog) — could not parse AXI_GATE from sim output"
            GATE_LINE="SANITY_AXI_GATE: UNKNOWN"
            ;;
    esac
elif [[ "${SIM_TOOL}" == "xsim" ]]; then
    case "${GATE_RAW}" in
        PASS)
            echo "AXI_GATE: PASS (xsim)"
            GATE_LINE="AXI_GATE: PASS (xsim)"
            ;;
        FAIL)
            echo "AXI_GATE: FAIL (xsim)"
            GATE_LINE="AXI_GATE: FAIL (xsim)"
            ;;
        *)
            echo "AXI_GATE: UNKNOWN (xsim)"
            GATE_LINE="AXI_GATE: UNKNOWN"
            ;;
    esac
fi

# ---------------------------------------------------------------------------
# Step 4: Write report
# ---------------------------------------------------------------------------

{
    echo "# Session I / P3-20A — AXI Backpressure Stress Result"
    echo "# Generated: ${TIMESTAMP}"
    echo "# Simulator: ${SIM_TOOL}"
    echo ""
    echo "GATE: ${GATE_LINE}"
    echo ""
    echo "TC_PASS:          ${TC_PASS}"
    echo "TC_FAIL:          ${TC_FAIL}"
    echo "AXI_ASSERT_FAIL:  ${AXI_ASSERT_FAIL}"
    echo "WATCHDOG_HITS:    ${WATCHDOG_HIT}"
    echo ""
    echo "--- Per-test case results ---"
    grep "\[PASS\] TC\|\[FAIL\] TC" "${SIM_LOG}" 2>/dev/null || echo "(none)"
    echo ""
    echo "--- AXI assertion violations ---"
    grep "\[I4[abcABC] FAIL\]" "${SIM_LOG}" 2>/dev/null || echo "(none)"
} > "${REPORT}"

echo ""
echo "  Report: ${REPORT}"
echo "  Sim log: ${SIM_LOG}"
echo ""
echo "============================================================"
echo " ${GATE_LINE}"
echo "============================================================"
