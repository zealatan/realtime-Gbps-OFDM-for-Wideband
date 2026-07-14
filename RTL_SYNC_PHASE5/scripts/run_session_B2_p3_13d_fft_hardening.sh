#!/usr/bin/env bash
# run_session_B2_p3_13d_fft_hardening.sh — P3-13D Real FFT Hardening
#
# Runs three robustness sub-tests against the Meyr FFT integer-CFO path:
#
#   B2-1  Input backpressure at 0/10/25/50% adp_valid stall rates.
#         Verify peak_index and int_cfo preserved; no deadlock.
#
#   B2-2  Frame boundary: pss_only, sss_only, pss+sss, back-to-back.
#         Verify flush logic (FLUSH_COUNT=1) and frame separation.
#
#   B2-3  Latency characterisation.
#         Prints PSS-stream, PSS-processing-gap, SSS-stream, post-stream-to-done.
#
# GATE:
#   FFT_HARDENING_GATE: PASS  — all B2-1 and B2-2 cases pass
#   FFT_HARDENING_GATE: FAIL  — any case fails or compile error
#
# DUT:   meyr_fft256_actual_integration_top (USE_BEHAVIORAL_STUB=3, iverilog)
# Stim:  golden/p3_09_sweep/case_k0.mem
# ROMs:  vectors/meyr_pss_fft_romhex.txt / meyr_sss_fft_romhex.txt
#
# USAGE:
#   bash scripts/run_session_B2_p3_13d_fft_hardening.sh [--log-dir DIR]
#
# EXIT CODES:
#   0  FFT_HARDENING_GATE: PASS
#   1  FFT_HARDENING_GATE: FAIL or blocked

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

LOG_DIR="${ROOT}/sim_out/session_B2_p3_13d"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --log-dir) shift; LOG_DIR="$1" ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
    shift
done

mkdir -p "${LOG_DIR}"
GATE_LOG="${LOG_DIR}/p3_13d_gate.txt"
SIM_LOG="${LOG_DIR}/p3_13d_sim.log"
VVP="${LOG_DIR}/p3_13d.vvp"

echo "========================================================================"
echo "P3-13D Real FFT Hardening"
echo "  Date     : $(date '+%Y-%m-%d %H:%M:%S')"
echo "  Root     : ${ROOT}"
echo "  Log dir  : ${LOG_DIR}"
echo "========================================================================"

# --------------------------------------------------------------------------
# Tool check
# --------------------------------------------------------------------------
if ! command -v iverilog &>/dev/null; then
    echo ""
    echo "ERROR: iverilog not found in PATH."
    echo "FFT_HARDENING_GATE: FAIL — iverilog unavailable" | tee "${GATE_LOG}"
    exit 1
fi
echo "  iverilog : $(iverilog -V 2>&1 | head -1)"

# --------------------------------------------------------------------------
# RTL source list (same 7 files as P3-13B behavioral-DFT path)
# --------------------------------------------------------------------------
RTL_SRCS=(
    "${ROOT}/rtl/meyr_fft256_harness_adapter.v"
    "${ROOT}/rtl/meyr_fft256_actual_integration_top.v"
    "${ROOT}/rtl/fft256_xilinx_wrapper.v"
    "${ROOT}/rtl/meyr_integer_cfo_freq_estimator_top.v"
    "${ROOT}/rtl/meyr_integer_cfo_core.v"
    "${ROOT}/rtl/meyr_pss_sss_product_gen.v"
    "${ROOT}/rtl/peak_detector.v"
)
TB_SRC="${ROOT}/tb/session_B2_p3_13d_fft_hardening_tb.sv"

# --------------------------------------------------------------------------
# Pre-flight: required files
# --------------------------------------------------------------------------
echo ""
echo "--- Required files ---"
BLOCKED=0

check_file() {
    local f="$1"
    local bf="${f#${ROOT}/}"
    if [[ -f "$f" ]]; then
        echo "  [OK]   ${bf}"
    else
        echo "  [MISS] ${bf}"
        BLOCKED=1
    fi
}

for f in "${RTL_SRCS[@]}"; do check_file "$f"; done
check_file "${TB_SRC}"
check_file "${ROOT}/vectors/meyr_pss_fft_romhex.txt"
check_file "${ROOT}/vectors/meyr_sss_fft_romhex.txt"
check_file "${ROOT}/golden/p3_09_sweep/case_k0.mem"

if [[ "${BLOCKED}" -eq 1 ]]; then
    echo ""
    echo "FFT_HARDENING_GATE: FAIL — missing required files (see above)" | tee "${GATE_LOG}"
    exit 1
fi

# --------------------------------------------------------------------------
# Compile
# --------------------------------------------------------------------------
echo ""
echo "--- iverilog compile (USE_BEHAVIORAL_STUB=3) ---"

iverilog -g2012 \
    -P "session_B2_p3_13d_fft_hardening_tb.USE_BEHAVIORAL_STUB=3" \
    -o "${VVP}" \
    "${TB_SRC}" \
    "${RTL_SRCS[@]}" \
    2>&1 | tee "${LOG_DIR}/p3_13d_compile.log"
CC_RC=${PIPESTATUS[0]}

if [[ "${CC_RC}" -ne 0 ]]; then
    echo ""
    echo "FFT_HARDENING_GATE: FAIL — compile error (rc=${CC_RC})" | tee "${GATE_LOG}"
    exit 1
fi
echo "  Compile OK: ${VVP}"

# --------------------------------------------------------------------------
# Simulate
# --------------------------------------------------------------------------
echo ""
echo "--- vvp simulation ---"

(cd "${ROOT}" && vvp "${VVP}") 2>&1 | tee "${SIM_LOG}"
SIM_RC=${PIPESTATUS[0]}

# --------------------------------------------------------------------------
# Gate evaluation
# --------------------------------------------------------------------------
echo ""
echo "--- Gate evaluation ---"

if grep -q "^FFT_HARDENING_GATE: PASS" "${SIM_LOG}"; then
    echo "FFT_HARDENING_GATE: PASS" | tee "${GATE_LOG}"
    echo "  All B2-1 backpressure and B2-2 boundary cases passed."
    echo ""
    echo "--- Latency table ---"
    grep "^\[B2-3\]" "${SIM_LOG}" || true
    echo ""
    echo "--- Sub-gate summary ---"
    grep -E "^B2-[123]_GATE:" "${SIM_LOG}" || true
    exit 0
else
    echo "FFT_HARDENING_GATE: FAIL" | tee "${GATE_LOG}"
    echo ""
    echo "--- Failure details ---"
    grep -E "^\[B2-[123]\] FAIL" "${SIM_LOG}" | head -20 || true
    echo ""
    echo "--- Sub-gate summary ---"
    grep -E "^B2-[123]_GATE:" "${SIM_LOG}" || true
    echo ""
    echo "  Full log: ${SIM_LOG}"
    exit 1
fi
