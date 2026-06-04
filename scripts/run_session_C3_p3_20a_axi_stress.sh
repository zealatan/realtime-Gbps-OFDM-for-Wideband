#!/usr/bin/env bash
# run_session_C3_p3_20a_axi_stress.sh — P3-20A AXI Protocol + Random Backpressure Stress
#
# DUT: phase3_sync_axis_dma_wrapper
# TB:  tb/session_C3_p3_20a_axi_stress_tb.sv
#
# Single simulation; 9 runs covering:
#   C3-1  S_AXIS valid gap sweep     (gap 0/10/25/50%, stall=0%)
#   C3-2  M_AXIS ready stall sweep   (gap=0%, stall 10/25/50%)
#   C3-3  Combined S+M stalls        (25%/25%, 50%/50%)
#   C3-4  tdata/tlast stability      (global: 0 violations required)
#
# Gate:
#   AXI_STRESS_GATE: PASS  — all 9 runs pass + 0 stability errors
#   AXI_STRESS_GATE: FAIL  — any run fails or stability violation detected
#
# USAGE:
#   bash scripts/run_session_C3_p3_20a_axi_stress.sh [OPTIONS]
#
#   --sim iverilog|xsim    simulator (default: iverilog)
#   --log-dir DIR          log directory (default: sim_out/session_C3_p3_20a)
#
# EXIT CODES:
#   0  AXI_STRESS_GATE: PASS
#   1  AXI_STRESS_GATE: FAIL or BLOCKED_*

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SIM_TOOL="iverilog"
LOG_DIR="${ROOT}/sim_out/session_C3_p3_20a"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --sim)     shift; SIM_TOOL="$1" ;;
        --log-dir) shift; LOG_DIR="$1"  ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
    shift
done

mkdir -p "${LOG_DIR}"

GATE_LOG="${LOG_DIR}/p3_20a_axi_stress_gate.txt"
SIM_LOG="${LOG_DIR}/p3_20a_axi_stress_sim.log"

gate_out() {
    local msg="$1"
    echo ""
    echo "========================================================================"
    echo "${msg}"
    echo "========================================================================"
    echo "${msg}" > "${GATE_LOG}"
}

echo "========================================================================"
echo "P3-20A AXI Protocol + Random Backpressure Stress"
echo "  Date      : $(date '+%Y-%m-%d %H:%M:%S')"
echo "  Simulator : ${SIM_TOOL}"
echo "  Log dir   : ${LOG_DIR}"
echo "========================================================================"

# --------------------------------------------------------------------------
# Prerequisites
# --------------------------------------------------------------------------
GOLDEN="${ROOT}/golden/phase3_iq_stimulus.mem"
if [[ ! -f "${GOLDEN}" ]]; then
    gate_out "AXI_STRESS_GATE: BLOCKED_MISSING_GOLDEN"
    echo "  Run: python3 scripts/gen_phase3_iq_stimulus.py"
    exit 1
fi

echo ""
echo "--- ROM stubs ---"
for f in "${ROOT}/vectors/meyr_pss_reference_romhex.txt" \
          "${ROOT}/vectors/meyr_sss_reference_romhex.txt"; do
    if [[ ! -f "$f" ]]; then
        echo "  creating zero stub: $(basename "$f")"
        python3 -c "print('\n'.join(['00000000']*256))" > "$f"
    else
        echo "  [OK]   $(basename "$f")"
    fi
done

# --------------------------------------------------------------------------
# Production DUT source list — single source of truth.
# --------------------------------------------------------------------------
FILELIST="${ROOT}/scripts/phase3_dut_filelist.f"
mapfile -t DUT_SRCS < <(grep -v '^#' "${FILELIST}" | grep -v '^[[:space:]]*$' | sed "s|^|${ROOT}/|")
TB_SRC="${ROOT}/tb/session_C3_p3_20a_axi_stress_tb.sv"

# --------------------------------------------------------------------------
# Pre-flight
# --------------------------------------------------------------------------
echo ""
echo "--- Pre-flight ---"
BLOCKED=0
for f in "${DUT_SRCS[@]}" "${TB_SRC}"; do
    [[ ! -f "$f" ]] && { echo "  [MISS] $f"; BLOCKED=1; }
done
[[ "${BLOCKED}" -eq 1 ]] && { gate_out "AXI_STRESS_GATE: BLOCKED_MISSING_FILES"; exit 1; }
echo "  All source files present."

if [[ "${SIM_TOOL}" == "iverilog" ]]; then
    command -v iverilog &>/dev/null || { gate_out "AXI_STRESS_GATE: BLOCKED_IVERILOG_UNAVAILABLE"; exit 1; }
elif [[ "${SIM_TOOL}" == "xsim" ]]; then
    command -v xvlog   &>/dev/null || { gate_out "AXI_STRESS_GATE: BLOCKED_XSIM_UNAVAILABLE";    exit 1; }
else
    gate_out "AXI_STRESS_GATE: BLOCKED_UNKNOWN_SIM"; exit 1
fi

# --------------------------------------------------------------------------
# Compile
# --------------------------------------------------------------------------
echo ""
echo "--- Compiling ---"
VVP_FILE="${LOG_DIR}/p3_20a_axi_stress.vvp"
COMPILE_LOG="${LOG_DIR}/p3_20a_compile.log"

if [[ "${SIM_TOOL}" == "iverilog" ]]; then
    iverilog -g2012 \
             "${DUT_SRCS[@]}" \
             "${TB_SRC}" \
             -o "${VVP_FILE}" \
             2> "${COMPILE_LOG}"
    if [[ $? -ne 0 ]]; then
        echo "  Compile FAILED (see ${COMPILE_LOG}):"
        head -20 "${COMPILE_LOG}" >&2
        gate_out "AXI_STRESS_GATE: BLOCKED_COMPILE_FAILED"
        exit 1
    fi
    echo "  Compile OK → ${VVP_FILE}"
fi

# --------------------------------------------------------------------------
# Simulate
# --------------------------------------------------------------------------
echo ""
echo "--- Simulating (9 runs, watchdog: 2M cycles) ---"

if [[ "${SIM_TOOL}" == "iverilog" ]]; then
    (cd "${ROOT}" && vvp "${VVP_FILE}") | tee "${SIM_LOG}"
fi

echo ""

# --------------------------------------------------------------------------
# Parse gate
# --------------------------------------------------------------------------
GATE_RESULT=$(grep -oP "^AXI_STRESS_GATE: \K(PASS|FAIL)$" "${SIM_LOG}" | tail -1)

if [[ -z "${GATE_RESULT}" ]]; then
    gate_out "AXI_STRESS_GATE: FAIL"
    echo "  No gate line found."
    exit 1
fi

C31=$(grep "^C31_RESULT" "${SIM_LOG}" | tail -1 || echo "C31_RESULT missing")
C32=$(grep "^C32_RESULT" "${SIM_LOG}" | tail -1 || echo "C32_RESULT missing")
C33=$(grep "^C33_RESULT" "${SIM_LOG}" | tail -1 || echo "C33_RESULT missing")
C34=$(grep "^C34_RESULT" "${SIM_LOG}" | tail -1 || echo "C34_RESULT missing")

echo "========================================================================"
echo "Phase results:"
echo "  ${C31}"
echo "  ${C32}"
echo "  ${C33}"
echo "  ${C34}"
echo ""
gate_out "AXI_STRESS_GATE: ${GATE_RESULT}"

echo ""
echo "Logs:  gate=${GATE_LOG}  sim=${SIM_LOG}  compile=${COMPILE_LOG}"
echo "========================================================================"

[[ "${GATE_RESULT}" == "PASS" ]] && exit 0 || exit 1
