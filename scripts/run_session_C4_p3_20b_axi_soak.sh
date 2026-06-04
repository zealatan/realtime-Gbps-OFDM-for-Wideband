#!/usr/bin/env bash
# run_session_C4_p3_20b_axi_soak.sh — P3-20B AXI Soak Test
#
# DUT: phase3_sync_axis_dma_wrapper
# TB:  tb/session_C4_p3_20b_axi_soak_tb.sv
# CHK: tb/common/axi_stream_checker.sv
#
# Modes (passed to TB via +MODE=<mode> plusarg):
#   quick     10 frames B1 + 10 frames B3 each; watchdog 15M cycles (~4M expected)
#   standard  100 frames B1 + 100 frames B3 each; watchdog 80M cycles (~41M expected)
#   soak      100 B1 + 1000 B2 + 100 B3 each; watchdog 220M cycles (~155M expected)
#
# Default (no flags): run quick first, then standard if quick passes.
# --quick:    run quick only.
# --standard: run standard only.
# --soak:     run soak only (enables the 1000-frame B2 phase).
#
# USAGE:
#   bash scripts/run_session_C4_p3_20b_axi_soak.sh [--quick|--standard|--soak]
#                                                   [--sim iverilog|xsim]
#                                                   [--log-dir DIR]
#
# EXIT CODES:
#   0  AXI_SOAK_GATE: PASS
#   1  AXI_SOAK_GATE: FAIL or BLOCKED_*

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SIM_TOOL="iverilog"
LOG_DIR="${ROOT}/sim_out/session_C4_p3_20b"
RUN_QUICK=0
RUN_STANDARD=0
RUN_SOAK=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --quick)    RUN_QUICK=1    ;;
        --standard) RUN_STANDARD=1 ;;
        --soak)     RUN_SOAK=1     ;;
        --sim)      shift; SIM_TOOL="$1" ;;
        --log-dir)  shift; LOG_DIR="$1"  ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
    shift
done

# Default: run quick then standard
if [[ $RUN_QUICK -eq 0 && $RUN_STANDARD -eq 0 && $RUN_SOAK -eq 0 ]]; then
    RUN_QUICK=1
    RUN_STANDARD=1
fi

mkdir -p "${LOG_DIR}"
GATE_LOG="${LOG_DIR}/p3_20b_axi_soak_gate.txt"
COMPILE_LOG="${LOG_DIR}/p3_20b_compile.log"
VVP_FILE="${LOG_DIR}/p3_20b_axi_soak.vvp"

gate_out() {
    local msg="$1"
    echo ""
    echo "========================================================================"
    echo "${msg}"
    echo "========================================================================"
    echo "${msg}" > "${GATE_LOG}"
}

echo "========================================================================"
echo "P3-20B AXI Soak Test"
echo "  Date      : $(date '+%Y-%m-%d %H:%M:%S')"
echo "  Simulator : ${SIM_TOOL}"
echo "  Log dir   : ${LOG_DIR}"
modes=""
[[ $RUN_QUICK    -eq 1 ]] && modes="${modes} quick"
[[ $RUN_STANDARD -eq 1 ]] && modes="${modes} standard"
[[ $RUN_SOAK     -eq 1 ]] && modes="${modes} soak"
echo "  Modes     :${modes}"
echo "========================================================================"

# --------------------------------------------------------------------------
# Prerequisites
# --------------------------------------------------------------------------
GOLDEN="${ROOT}/golden/phase3_iq_stimulus.mem"
if [[ ! -f "${GOLDEN}" ]]; then
    gate_out "AXI_SOAK_GATE: BLOCKED_MISSING_GOLDEN"
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
CHK_SRC="${ROOT}/tb/common/axi_stream_checker.sv"
TB_SRC="${ROOT}/tb/session_C4_p3_20b_axi_soak_tb.sv"

# --------------------------------------------------------------------------
# Pre-flight
# --------------------------------------------------------------------------
echo ""
echo "--- Pre-flight ---"
BLOCKED=0
for f in "${DUT_SRCS[@]}" "${CHK_SRC}" "${TB_SRC}"; do
    [[ ! -f "$f" ]] && { echo "  [MISS] $f"; BLOCKED=1; }
done
[[ "${BLOCKED}" -eq 1 ]] && { gate_out "AXI_SOAK_GATE: BLOCKED_MISSING_FILES"; exit 1; }
echo "  All source files present."

if [[ "${SIM_TOOL}" == "iverilog" ]]; then
    command -v iverilog &>/dev/null || { gate_out "AXI_SOAK_GATE: BLOCKED_IVERILOG_UNAVAILABLE"; exit 1; }
elif [[ "${SIM_TOOL}" == "xsim" ]]; then
    command -v xvlog   &>/dev/null || { gate_out "AXI_SOAK_GATE: BLOCKED_XSIM_UNAVAILABLE"; exit 1; }
else
    gate_out "AXI_SOAK_GATE: BLOCKED_UNKNOWN_SIM"; exit 1
fi

# --------------------------------------------------------------------------
# Compile (once; all modes share the same binary)
# --------------------------------------------------------------------------
echo ""
echo "--- Compiling ---"
if [[ "${SIM_TOOL}" == "iverilog" ]]; then
    iverilog -g2012 \
             "${DUT_SRCS[@]}" \
             "${CHK_SRC}" \
             "${TB_SRC}" \
             -o "${VVP_FILE}" \
             2> "${COMPILE_LOG}"
    if [[ $? -ne 0 ]]; then
        echo "  Compile FAILED (see ${COMPILE_LOG}):"
        head -20 "${COMPILE_LOG}" >&2
        gate_out "AXI_SOAK_GATE: BLOCKED_COMPILE_FAILED"
        exit 1
    fi
    echo "  Compile OK → ${VVP_FILE}"
fi

# --------------------------------------------------------------------------
# sim_once: run one simulation pass, print directly to stdout, store gate
# in LAST_GATE.  Must NOT be called via $() — output goes to terminal live.
# --------------------------------------------------------------------------
LAST_GATE=""
sim_once() {
    local mode="$1"
    local hint="$2"
    local log="${LOG_DIR}/p3_20b_${mode}_sim.log"
    echo ""
    echo "--- Simulating [${mode}] (${hint}) ---"
    if [[ "${SIM_TOOL}" == "iverilog" ]]; then
        (cd "${ROOT}" && vvp "${VVP_FILE}" "+MODE=${mode}") | tee "${log}"
    fi
    # Extract gate from the saved log — NOT from captured stdout
    LAST_GATE=$(grep -oP "^AXI_SOAK_GATE: \K(PASS|FAIL)$" "${log}" | tail -1)
    LAST_GATE="${LAST_GATE:-FAIL}"
}

# --------------------------------------------------------------------------
# Run selected modes (print live; read gate from log after each run)
# --------------------------------------------------------------------------
FINAL_GATE="PASS"
QUICK_GATE=""
STANDARD_GATE=""
SOAK_GATE=""

if [[ $RUN_QUICK -eq 1 ]]; then
    sim_once "quick" "~4M cycles, <5s"
    QUICK_GATE="${LAST_GATE}"
    if [[ "${QUICK_GATE}" != "PASS" ]]; then
        FINAL_GATE="FAIL"
        if [[ $RUN_STANDARD -eq 1 ]]; then
            echo ""
            echo "  [SKIP] standard mode skipped — quick failed"
            RUN_STANDARD=0
        fi
    fi
fi

if [[ $RUN_STANDARD -eq 1 ]]; then
    sim_once "standard" "~41M cycles, <20s"
    STANDARD_GATE="${LAST_GATE}"
    [[ "${STANDARD_GATE}" != "PASS" ]] && FINAL_GATE="FAIL"
fi

if [[ $RUN_SOAK -eq 1 ]]; then
    sim_once "soak" "~155M cycles, expect 60-90s"
    SOAK_GATE="${LAST_GATE}"
    [[ "${SOAK_GATE}" != "PASS" ]] && FINAL_GATE="FAIL"
fi

# --------------------------------------------------------------------------
# Summary and gate file
# --------------------------------------------------------------------------
echo ""
echo "========================================================================"
echo "Mode results:"
[[ -n "${QUICK_GATE}"    ]] && echo "  quick    : ${QUICK_GATE}"
[[ -n "${STANDARD_GATE}" ]] && echo "  standard : ${STANDARD_GATE}"
[[ -n "${SOAK_GATE}"     ]] && echo "  soak     : ${SOAK_GATE}"
[[ $RUN_STANDARD -eq 0 && $RUN_QUICK -eq 1 && "${QUICK_GATE}" != "PASS" ]] && \
    echo "  standard : SKIPPED (quick failed)"
echo ""
gate_out "AXI_SOAK_GATE: ${FINAL_GATE}"
echo ""
echo "Gate log : ${GATE_LOG}"
echo "========================================================================"

[[ "${FINAL_GATE}" == "PASS" ]] && exit 0 || exit 1
