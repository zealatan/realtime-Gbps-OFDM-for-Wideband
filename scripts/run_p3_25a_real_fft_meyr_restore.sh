#!/usr/bin/env bash
# run_p3_25a_real_fft_meyr_restore.sh — P3-25A Real FFT / Meyr Production Restore
#
# Tests meyr_integer_cfo_fft_frontend_top (production frozen hierarchy):
#   meyr_integer_cfo_fft_frontend_top
#   ├─ fft256_dual_symbol_frontend → fft256_xilinx_wrapper (behavioral DFT)
#   └─ meyr_integer_cfo_freq_estimator_top → meyr_integer_cfo_core → peak_detector
#
# Gate outputs:
#   SANITY_GATE: PASS (behavioral DFT, iverilog) — USE_BEHAVIORAL_STUB=3
#   SANITY_GATE: FAIL
#   BLOCKED_*
#
# USAGE:
#   bash scripts/run_p3_25a_real_fft_meyr_restore.sh [--log-dir DIR]
#
# EXIT CODES:
#   0  SANITY_GATE: PASS
#   1  FAIL or BLOCKED

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOG_DIR="${ROOT}/sim_out/p3_25a"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --log-dir) shift; LOG_DIR="$1" ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
    shift
done

mkdir -p "${LOG_DIR}"

gate_out() {
    echo "$1" | tee "${LOG_DIR}/p3_25a_gate.txt"
}

echo "============================================================"
echo " P3-25A Real FFT / Meyr Production Restore"
echo " Log dir: ${LOG_DIR}"
echo "============================================================"
echo ""

# --------------------------------------------------------------------------
# RTL source list (subset: only the modules needed for standalone test)
# --------------------------------------------------------------------------
DUT_SRCS=(
    "${ROOT}/rtl/DUT/peak_detector.v"
    "${ROOT}/rtl/DUT/meyr_pss_sss_product_gen.v"
    "${ROOT}/rtl/DUT/meyr_integer_cfo_core.v"
    "${ROOT}/rtl/DUT/meyr_integer_cfo_freq_estimator_top.v"
    "${ROOT}/rtl/DUT/fft256_xilinx_wrapper.v"
    "${ROOT}/rtl/DUT/fft256_dual_symbol_frontend.v"
    "${ROOT}/rtl/DUT/meyr_integer_cfo_fft_frontend_top.v"
)
TB_SRC="${ROOT}/tb/p3_25a_real_fft_meyr_restore_tb.sv"

# --------------------------------------------------------------------------
# Pre-flight: required files
# --------------------------------------------------------------------------
echo "--- Pre-flight: required files ---"
BLOCKED=0
for f in "${DUT_SRCS[@]}" "${TB_SRC}"; do
    if [[ ! -f "$f" ]]; then
        echo "  [MISS] $f"
        BLOCKED=1
    else
        echo "  [OK]   $(basename "$f")"
    fi
done

for vec in \
    "${ROOT}/vectors/meyr_pss_fft_romhex.txt" \
    "${ROOT}/vectors/meyr_sss_fft_romhex.txt"; do
    if [[ ! -f "$vec" ]]; then
        echo "  [MISS] $vec"
        BLOCKED=1
    else
        echo "  [OK]   $(basename "$vec")"
    fi
done

for mem in \
    "${ROOT}/golden/p3_09_sweep/case_k0.mem" \
    "${ROOT}/golden/p3_09_sweep/case_kp1.mem" \
    "${ROOT}/golden/p3_09_sweep/case_km1.mem" \
    "${ROOT}/golden/p3_09_sweep/case_kp2.mem" \
    "${ROOT}/golden/p3_09_sweep/case_km2.mem" \
    "${ROOT}/golden/p3_09_sweep/case_kp4.mem" \
    "${ROOT}/golden/p3_09_sweep/case_km4.mem" \
    "${ROOT}/golden/p3_09_sweep/case_kp8.mem" \
    "${ROOT}/golden/p3_09_sweep/case_km8.mem"; do
    if [[ ! -f "$mem" ]]; then
        echo "  [MISS] $mem"
        BLOCKED=1
    else
        echo "  [OK]   $(basename "$mem")"
    fi
done

if [[ "${BLOCKED}" -eq 1 ]]; then
    gate_out "SANITY_GATE: BLOCKED_MISSING_FILES"
    exit 1
fi
echo "  All required files present."
echo ""

# --------------------------------------------------------------------------
# Check iverilog availability
# --------------------------------------------------------------------------
if ! command -v iverilog &>/dev/null; then
    gate_out "SANITY_GATE: BLOCKED_IVERILOG_UNAVAILABLE"
    echo "  iverilog not found in PATH."
    exit 1
fi

IVERILOG_VER=$(iverilog -V 2>&1 | head -1)
echo "  Simulator: ${IVERILOG_VER}"
echo ""

# --------------------------------------------------------------------------
# V1: Compile
# --------------------------------------------------------------------------
echo "=== [V1] Compile ==="
VVP="${LOG_DIR}/p3_25a.vvp"
COMPILE_LOG="${LOG_DIR}/p3_25a_compile.log"

(cd "${ROOT}" && \
iverilog -g2012 -Wall \
    -o "${VVP}" \
    "${DUT_SRCS[@]}" \
    "${TB_SRC}" \
) 2>&1 | tee "${COMPILE_LOG}"

if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    gate_out "SANITY_GATE: BLOCKED_COMPILE_ERROR"
    echo "  See ${COMPILE_LOG}"
    exit 1
fi
echo "  Compile: OK"
echo ""

# --------------------------------------------------------------------------
# V2: Hierarchy audit (implicit — compilation proves instantiation)
# V3: Run simulation (k_int CFO sweep, behavioral DFT)
# --------------------------------------------------------------------------
echo "=== [V2+V3] Simulate ==="
SIM_LOG="${LOG_DIR}/p3_25a_sim.log"

(cd "${ROOT}" && vvp "${VVP}") 2>&1 | tee "${SIM_LOG}"
SIM_EXIT=${PIPESTATUS[0]}
echo ""

# --------------------------------------------------------------------------
# Parse gate result
# --------------------------------------------------------------------------
if grep -q "SANITY_GATE: PASS" "${SIM_LOG}"; then
    GATE_RESULT="SANITY_GATE: PASS (behavioral DFT, iverilog)"
elif grep -q "OFFICIAL_GATE: PASS" "${SIM_LOG}"; then
    GATE_RESULT="OFFICIAL_GATE: PASS"
elif grep -q "SANITY_GATE: FAIL" "${SIM_LOG}"; then
    GATE_RESULT="SANITY_GATE: FAIL"
elif grep -q "OFFICIAL_GATE: FAIL" "${SIM_LOG}"; then
    GATE_RESULT="OFFICIAL_GATE: FAIL"
else
    GATE_RESULT="SANITY_GATE: FAIL (no gate line found)"
fi

gate_out "${GATE_RESULT}"
echo ""
echo "  Sim log:  ${SIM_LOG}"
echo "  Gate log: ${LOG_DIR}/p3_25a_gate.txt"

if [[ "${GATE_RESULT}" == *"PASS"* ]]; then
    exit 0
else
    exit 1
fi
