#!/usr/bin/env bash
# run_session_B3_p3_13e_fft_protocol.sh — B3 FFT Protocol + Meyr Invariant Runner
#
# Compiles the FFT + Meyr DUTs and the B3 verification TB, simulates, and
# extracts the FFT_PROTOCOL_GATE result.
#
# Gate:
#   iverilog: SANITY_FFT_PROTOCOL_GATE: PASS / FAIL
#   xsim:     FFT_PROTOCOL_GATE: PASS / FAIL (requires Vivado)
#
# Usage:
#   bash scripts/run_session_B3_p3_13e_fft_protocol.sh [--sim iverilog|xsim]

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIM_TOOL="iverilog"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --sim) SIM_TOOL="$2"; shift 2 ;;
        *) shift ;;
    esac
done

echo ""
echo "=== session_B3_p3_13e_fft_protocol ==="
echo "    Simulator: ${SIM_TOOL}"
echo ""

# ── Output directories ─────────────────────────────────────────────────────────
SIM_OUT="${ROOT}/sim_out/session_B3_p3_13e"
LOGS="${ROOT}/logs"
REPORTS="${ROOT}/reports/session_B3_p3_13e"

mkdir -p "${SIM_OUT}" "${LOGS}" "${REPORTS}"

# ── xsim not available in this environment ────────────────────────────────────
if [[ "${SIM_TOOL}" == "xsim" ]]; then
    echo "SANITY_FFT_PROTOCOL_GATE: BLOCKED_XSIM_UNAVAILABLE"
    exit 1
fi

if ! command -v iverilog &>/dev/null; then
    echo "SANITY_FFT_PROTOCOL_GATE: BLOCKED_IVERILOG_NOT_FOUND"
    exit 1
fi

# ── Step 1: Compile ────────────────────────────────────────────────────────────
echo "=== [1] Compile ==="

RTL_SRCS=(
    "${ROOT}/rtl/fft256_dual_symbol_frontend.v"
    "${ROOT}/rtl/meyr_pss_sss_product_gen.v"
    "${ROOT}/rtl/meyr_term2_ref_rom.v"
    "${ROOT}/rtl/peak_detector.v"
    "${ROOT}/rtl/meyr_integer_cfo_core.v"
    "${ROOT}/rtl/meyr_integer_cfo_freq_estimator_top.v"
    "${ROOT}/rtl/meyr_integer_cfo_fft_frontend_top.v"
)
TB_SRC="${ROOT}/tb/session_B3_p3_13e_fft_protocol_tb.sv"

MISSING=0
for f in "${RTL_SRCS[@]}" "${TB_SRC}"; do
    if [[ ! -f "$f" ]]; then
        echo "  MISSING: $f"
        MISSING=$((MISSING + 1))
    fi
done
if [[ $MISSING -gt 0 ]]; then
    echo "SANITY_FFT_PROTOCOL_GATE: FAIL (${MISSING} source file(s) missing)"
    exit 1
fi

VVP_OUT="${SIM_OUT}/session_B3_p3_13e.vvp"
COMPILE_LOG="${LOGS}/session_B3_p3_13e_compile.log"

iverilog -g2012 \
    -I "${ROOT}/vectors" \
    -o "${VVP_OUT}" \
    "${RTL_SRCS[@]}" "${TB_SRC}" \
    2>&1 | tee "${COMPILE_LOG}"

if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    echo "SANITY_FFT_PROTOCOL_GATE: FAIL (compile error)"
    exit 1
fi
echo "  Compile: OK  → ${VVP_OUT}"

# ── Step 2: Simulate ───────────────────────────────────────────────────────────
echo ""
echo "=== [2] Simulate ==="

SIM_LOG="${LOGS}/session_B3_p3_13e_sim.log"

cd "${ROOT}"
vvp "${VVP_OUT}" 2>&1 | tee "${SIM_LOG}"
SIM_EXIT=${PIPESTATUS[0]}

# ── Step 3: Extract gate ───────────────────────────────────────────────────────
echo ""
echo "=== [3] Gate ==="

GATE_RAW=$(grep -E "^FFT_PROTOCOL_GATE:" "${SIM_LOG}" | tail -1 || echo "")

GATE_FILE="${REPORTS}/fft_protocol_gate.txt"

if echo "${GATE_RAW}" | grep -q "PASS"; then
    SANITY_GATE="SANITY_FFT_PROTOCOL_GATE: PASS"
    echo "${SANITY_GATE}"
elif [[ -z "${GATE_RAW}" ]]; then
    SANITY_GATE="SANITY_FFT_PROTOCOL_GATE: FAIL (no gate line in sim log)"
    echo "${SANITY_GATE}"
else
    SANITY_GATE="SANITY_FFT_PROTOCOL_GATE: FAIL"
    echo "${SANITY_GATE}"
fi

{
    echo "${SANITY_GATE}"
    echo "Simulator: iverilog"
    echo "Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo ""
    echo "Raw gate: ${GATE_RAW}"
    echo ""
    echo "Pass/Fail summary:"
    grep -E "^(PASS|FAIL)" "${SIM_LOG}" || echo "  (no PASS/FAIL lines found)"
} > "${GATE_FILE}"

echo "  Report: ${GATE_FILE}"
echo "  Sim log: ${SIM_LOG}"

if echo "${SANITY_GATE}" | grep -q "PASS"; then
    exit 0
else
    exit 1
fi
