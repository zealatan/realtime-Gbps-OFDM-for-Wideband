#!/usr/bin/env bash
# run_p3_13b_real_fft_xsim.sh — P3-13B Official xsim runner / behavioral DFT fallback
#
# PURPOSE
#   Validate the real FFT Meyr integer CFO path using the k_int sweep vectors.
#   Two execution modes (selected by tool availability):
#
#   MODE A — Real Xilinx FFT IP (xsim, USE_BEHAVIORAL_STUB=0):
#     Requires: Vivado + xsim + Xilinx FFT IP (ip/fft256_xilinx/).
#     Flow:     xvlog → xelab → xsim --runall
#     Gate:     OFFICIAL_GATE: PASS  (all 9 nonzero k_int cases must pass)
#               OFFICIAL_GATE: FAIL  (any case fails)
#
#   MODE B — Behavioral DFT fallback (iverilog, USE_BEHAVIORAL_STUB=3):
#     Requires: iverilog 11+.
#     Flow:     iverilog -P ... → vvp
#     Gate:     SANITY_GATE: PASS (behavioral DFT, iverilog)
#               OFFICIAL_GATE: FAIL (xsim not available)
#     The behavioral DFT computes the exact 256-pt DFT using real arithmetic
#     and is mathematically identical to the Xilinx FFT output (no scaling
#     differences affect peak location for these test vectors).
#
# GATE RULES
#   - OFFICIAL_GATE: PASS is ONLY printed when MODE A passes all 9 k_int cases.
#   - SANITY_GATE: PASS is printed when MODE B passes all 9 k_int cases.
#   - Both gates include the FAIL variant when the run exits non-zero or
#     the gate string is not found in the log.
#
# NONZERO k_int CASES REQUIRED
#   k_int ∈ {−8, −4, −2, −1, 0, +1, +2, +4, +8}
#   Expected: peak_index = 255 + k_int, int_cfo = k_int
#
# BIN/SIGN CONVENTION (see Section 5 of docs/p3_13b_real_fft_validation.md)
#   - FFT output: natural bin order 0..255 (xk_index from Xilinx IP or
#     m_axis_tuser from behavioral DFT, both natural order).
#   - Zero-CFO maps to bin 255 (center of 511-lag correlation).
#   - Negative k_int → peak_index < 255 (lower bin).
#   - Positive k_int → peak_index > 255 (higher bin).
#   - int_cfo is decoded as: peak_index − 255 (signed).
#
# USAGE
#   bash scripts/run_p3_13b_real_fft_xsim.sh [--force-dft] [--log-dir DIR]
#
#   --force-dft   Force MODE B (behavioral DFT) even if xsim is available.
#   --log-dir DIR Override log directory (default: sim_out/p3_13b).
#
# EXIT CODES
#   0  — gate passed (OFFICIAL or SANITY)
#   1  — gate failed or simulation error
#   2  — all tools unavailable; cannot run simulation

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

FORCE_DFT=0
LOG_DIR="${ROOT}/sim_out/p3_13b"

for arg in "$@"; do
    case "$arg" in
        --force-dft)  FORCE_DFT=1 ;;
        --log-dir)    shift; LOG_DIR="$1" ;;
    esac
done

mkdir -p "${LOG_DIR}"

XSIM_LOG="${LOG_DIR}/p3_13b_xsim.log"
DFT_LOG="${LOG_DIR}/p3_13b_dft.log"
GATE_LOG="${LOG_DIR}/p3_13b_gate.txt"

# ---------------------------------------------------------------------------
# Tool detection
# ---------------------------------------------------------------------------
HAVE_XSIM=0
HAVE_VIVADO=0
HAVE_IVERILOG=0

command -v xsim    &>/dev/null && HAVE_XSIM=1
command -v vivado  &>/dev/null && HAVE_VIVADO=1
command -v iverilog &>/dev/null && HAVE_IVERILOG=1

echo "========================================================================"
echo "P3-13B Real FFT xsim Validation Runner"
echo "  Date       : $(date '+%Y-%m-%d %H:%M:%S')"
echo "  Project    : ${ROOT}"
echo "  Log dir    : ${LOG_DIR}"
echo "  xsim       : ${HAVE_XSIM}   vivado: ${HAVE_VIVADO}"
echo "  iverilog   : ${HAVE_IVERILOG}"
echo "========================================================================"

# ---------------------------------------------------------------------------
# Required file check (common to both modes)
# ---------------------------------------------------------------------------
BLOCKED=0
check_file() {
    if [[ -f "${ROOT}/$1" ]]; then
        echo "  [OK]   $1"
    else
        echo "  [MISS] $1  — MISSING"
        BLOCKED=1
    fi
}

echo ""
echo "--- Required files ---"
check_file "rtl/meyr_fft256_actual_integration_top.v"
check_file "rtl/fft256_xilinx_wrapper.v"
check_file "rtl/meyr_fft256_harness_adapter.v"
check_file "rtl/meyr_integer_cfo_freq_estimator_top.v"
check_file "rtl/meyr_integer_cfo_core.v"
check_file "rtl/meyr_pss_sss_product_gen.v"
check_file "rtl/peak_detector.v"
check_file "tb/p3_13a_real_fft_meyr_tb.sv"
check_file "vectors/meyr_pss_fft_romhex.txt"
check_file "vectors/meyr_sss_fft_romhex.txt"
for tag in k0 kp1 km1 kp2 km2 kp4 km4 kp8 km8; do
    check_file "golden/p3_09_sweep/case_${tag}.mem"
done

if [[ "${BLOCKED}" -eq 1 ]]; then
    echo ""
    echo "OFFICIAL_GATE: FAIL — missing required files (see above)"
    echo "OFFICIAL_GATE: FAIL — missing required files" > "${GATE_LOG}"
    exit 1
fi

# ---------------------------------------------------------------------------
# MODE A: Real Xilinx FFT IP via xsim
# ---------------------------------------------------------------------------
run_xsim_mode() {
    echo ""
    echo "=== MODE A: Real Xilinx FFT IP (xsim, USE_BEHAVIORAL_STUB=0) ==="

    # Check for Xilinx FFT IP netlist
    IP_DIR="${ROOT}/ip/fft256_xilinx/fft256_xilinx"
    IP_XCI="${IP_DIR}/fft256_xilinx.xci"
    IP_SIM="${IP_DIR}/sim/fft256_xilinx.v"

    if [[ ! -f "${IP_XCI}" ]]; then
        echo "  [BLOCKED] Xilinx FFT IP XCI not found: ${IP_XCI}"
        echo "            Generate with Vivado: create_ip + generate_target simulation"
        return 1
    fi
    if [[ ! -f "${IP_SIM}" ]]; then
        echo "  [BLOCKED] Xilinx FFT IP sim netlist not found: ${IP_SIM}"
        echo "            Run Vivado generate_target to create simulation files."
        return 1
    fi

    echo "  [OK]   FFT IP: ${IP_SIM}"

    local XSIM_WD="${LOG_DIR}/xsim_work"
    mkdir -p "${XSIM_WD}"

    echo ""
    echo "--- Step 1: xvlog (compile RTL + TB) ---"
    (
        cd "${XSIM_WD}"

        # Compile Xilinx IP simulation netlist (plain Verilog)
        xvlog -nolog \
            "${IP_SIM}" \
            2>&1 | tee "${XSIM_LOG}.xvlog_ip"

        # Compile project RTL (plain Verilog)
        xvlog -nolog -sv \
            "${ROOT}/rtl/fft256_xilinx_wrapper.v" \
            "${ROOT}/rtl/meyr_fft256_harness_adapter.v" \
            "${ROOT}/rtl/meyr_fft256_actual_integration_top.v" \
            "${ROOT}/rtl/meyr_integer_cfo_freq_estimator_top.v" \
            "${ROOT}/rtl/meyr_integer_cfo_core.v" \
            "${ROOT}/rtl/meyr_pss_sss_product_gen.v" \
            "${ROOT}/rtl/peak_detector.v" \
            2>&1 | tee "${XSIM_LOG}.xvlog_rtl"

        # Compile testbench (SystemVerilog)
        xvlog -nolog -sv \
            -d USE_BEHAVIORAL_STUB=0 \
            "${ROOT}/tb/p3_13a_real_fft_meyr_tb.sv" \
            2>&1 | tee "${XSIM_LOG}.xvlog_tb"
    )

    echo ""
    echo "--- Step 2: xelab ---"
    (
        cd "${XSIM_WD}"
        xelab -nolog \
            --relax \
            -debug all \
            -top p3_13a_real_fft_meyr_tb \
            -snapshot p3_13b_xsim_snap \
            2>&1 | tee "${XSIM_LOG}.xelab"
    )

    echo ""
    echo "--- Step 3: xsim --runall ---"
    (
        cd "${XSIM_WD}"
        xsim p3_13b_xsim_snap \
            --runall \
            --log "${XSIM_LOG}" \
            2>&1 | tee "${XSIM_LOG}.console"
    )
    local SIM_RC=$?

    echo ""
    echo "--- Gate evaluation (real Xilinx IP) ---"
    if grep -q "OFFICIAL_GATE: PASS" "${XSIM_LOG}.console" 2>/dev/null; then
        echo "OFFICIAL_GATE: PASS" | tee "${GATE_LOG}"
        echo "  All 9 k_int sweep cases passed under real Xilinx FFT IP + xsim."
        return 0
    else
        echo "OFFICIAL_GATE: FAIL" | tee "${GATE_LOG}"
        grep -E '^\[TB\] (PASS|FAIL|ERROR)' "${XSIM_LOG}.console" 2>/dev/null || true
        echo "  See ${XSIM_LOG}.console for details."
        return 1
    fi
}

# ---------------------------------------------------------------------------
# MODE B: Behavioral DFT fallback (iverilog, USE_BEHAVIORAL_STUB=3)
# ---------------------------------------------------------------------------
run_dft_mode() {
    echo ""
    echo "=== MODE B: Behavioral DFT fallback (iverilog, USE_BEHAVIORAL_STUB=3) ==="
    echo "  Mathematically exact 256-pt DFT; results identical to Xilinx FFT"
    echo "  for peak-index and int_cfo (no fixed-point scaling differences)."

    local VVP="${LOG_DIR}/p3_13b_dft.vvp"

    echo ""
    echo "--- Compiling with iverilog ---"
    iverilog -g2012 \
        -P p3_13a_real_fft_meyr_tb.USE_BEHAVIORAL_STUB=3 \
        -o "${VVP}" \
        "${ROOT}/tb/p3_13a_real_fft_meyr_tb.sv" \
        "${ROOT}/rtl/meyr_fft256_harness_adapter.v" \
        "${ROOT}/rtl/meyr_fft256_actual_integration_top.v" \
        "${ROOT}/rtl/fft256_xilinx_wrapper.v" \
        "${ROOT}/rtl/meyr_integer_cfo_freq_estimator_top.v" \
        "${ROOT}/rtl/meyr_integer_cfo_core.v" \
        "${ROOT}/rtl/meyr_pss_sss_product_gen.v" \
        "${ROOT}/rtl/peak_detector.v" \
        2>&1
    local CC=$?
    if [[ ${CC} -ne 0 ]]; then
        echo "  COMPILE FAILED (rc=${CC})"
        echo "OFFICIAL_GATE: FAIL — iverilog compile error" > "${GATE_LOG}"
        return 1
    fi
    echo "  Compile OK: ${VVP}"

    echo ""
    echo "--- Running simulation ---"
    vvp "${VVP}" 2>&1 | tee "${DFT_LOG}"
    local SIM_RC=${PIPESTATUS[0]}

    echo ""
    echo "--- Gate evaluation (behavioral DFT) ---"
    if grep -q "SANITY_GATE: PASS" "${DFT_LOG}"; then
        echo ""
        echo "SANITY_GATE: PASS (behavioral DFT, iverilog)" | tee -a "${GATE_LOG}"
        echo "  All 9 k_int sweep cases passed (exact DFT, mathematical validation)."
        echo ""
        echo "OFFICIAL_GATE: FAIL — xsim/Vivado not available; run under Vivado"
        echo "  for OFFICIAL_GATE (requires Xilinx FFT IP + xsim)."
        echo "OFFICIAL_GATE: FAIL — xsim unavailable" >> "${GATE_LOG}"

        # Print case summary
        echo ""
        echo "--- Case results ---"
        grep -E '^\[TB\] PASS' "${DFT_LOG}" || true
        grep -E '^\[TB\] FAIL' "${DFT_LOG}" || true
        return 0
    else
        echo "SANITY_GATE: FAIL (behavioral DFT, iverilog)" | tee -a "${GATE_LOG}"
        echo "OFFICIAL_GATE: FAIL" >> "${GATE_LOG}"
        grep -E '^\[TB\] (PASS|FAIL|ERROR)' "${DFT_LOG}" || true
        echo "  See ${DFT_LOG} for details."
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Main: select mode and run
# ---------------------------------------------------------------------------
echo ""
if [[ "${FORCE_DFT}" -eq 0 ]] && [[ "${HAVE_XSIM}" -eq 1 ]]; then
    run_xsim_mode
    RC=$?
elif [[ "${HAVE_IVERILOG}" -eq 1 ]]; then
    if [[ "${HAVE_XSIM}" -eq 0 ]] && [[ "${FORCE_DFT}" -eq 0 ]]; then
        echo "NOTE: xsim not found — falling back to behavioral DFT mode."
        echo "      OFFICIAL_GATE requires Vivado + Xilinx FFT IP + xsim."
        echo "      Install Vivado and source settings64.sh to obtain OFFICIAL_GATE."
        echo ""
    fi
    run_dft_mode
    RC=$?
else
    echo "OFFICIAL_GATE: FAIL — no simulation tool available (xsim or iverilog required)"
    echo "OFFICIAL_GATE: FAIL — no tools" > "${GATE_LOG}"
    RC=2
fi

echo ""
echo "========================================================================"
echo "Log files:"
echo "  Gate:  ${GATE_LOG}"
[[ -f "${DFT_LOG}" ]]  && echo "  DFT:   ${DFT_LOG}"
[[ -f "${XSIM_LOG}.console" ]] && echo "  xsim:  ${XSIM_LOG}.console"
echo "========================================================================"

exit ${RC}
