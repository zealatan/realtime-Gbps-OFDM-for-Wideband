#!/usr/bin/env bash
# run_session_D_p3_15a_full_c_golden_equivalence.sh — Session D / P3-15A
#
# Full C golden vs RTL equivalence framework runner.
#
# Steps:
#   1. Export C reference golden JSON
#   2. (Optional) Rebuild golden_dump binary
#   3. Compile and run RTL observable dump TB
#   4. Normalize RTL outputs to JSON
#   5. Run staged comparison against C reference
#   6. Write final report
#
# DUT: rtl/phase3_sync_axis_dma_wrapper.v  (same as Session C)
# TB:  tb/session_D_p3_15a_phase3_observable_dump_tb.sv
#
# Gate rules:
#   EQUIV_GATE: PASS                 — all available stages pass
#   EQUIV_GATE: PARTIAL_PASS_BLOCKED — available pass, some blocked (no C M_AXIS golden yet)
#   EQUIV_GATE: FAIL                 — any available stage fails
#
# When using iverilog (not xsim):
#   SANITY_EQUIV_GATE: PARTIAL_PASS_BLOCKED
#   (never claim official PASS for iverilog; xsim required for CI_GATE)
#
# Usage:
#   ./scripts/run_session_D_p3_15a_full_c_golden_equivalence.sh [--sim xsim|iverilog] [--regen]
#
# Options:
#   --sim   xsim|iverilog     Simulator (default: iverilog)
#   --regen                   Re-run golden_dump binary to refresh C reference
#   --skip-sim                Skip RTL simulation (use existing output files)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SIM_TOOL="iverilog"
REGEN_FLAG=""
SKIP_SIM=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --sim)      SIM_TOOL="$2"; shift 2 ;;
        --regen)    REGEN_FLAG="--regen"; shift ;;
        --skip-sim) SKIP_SIM=1; shift ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

LOGS="${ROOT}/logs"
SIM_OUT="${ROOT}/sim_out/session_D_p3_15a"
GOLDEN_D="${ROOT}/golden/session_D_p3_15a"
REPORTS="${ROOT}/reports/session_D_p3_15a"

mkdir -p "${LOGS}" "${SIM_OUT}" "${GOLDEN_D}" "${REPORTS}"

cd "${ROOT}"

echo "======================================================================"
echo "Session D / P3-15A — Full C Golden Equivalence Framework"
echo "  Simulator: ${SIM_TOOL}"
echo "  Regen:     ${REGEN_FLAG:-no}"
echo "======================================================================"

# ==========================================================================
# Step 1: Export C reference golden JSON
# ==========================================================================
echo ""
echo "=== [1] Export C reference golden ==="

if ! command -v python3 &>/dev/null; then
    echo "ERROR: python3 not found in PATH." >&2; exit 1
fi

python3 "${SCRIPT_DIR}/export_c_reference_phase3_golden.py" ${REGEN_FLAG} \
    2>&1 | tee "${LOGS}/session_D_p3_15a_c_export.log"
C_EXPORT_STATUS="${PIPESTATUS[0]}"

if [[ ! -f "${GOLDEN_D}/c_reference_observables.json" ]]; then
    echo "ERROR: C reference JSON not created." >&2; exit 1
fi
echo "  C reference JSON: ${GOLDEN_D}/c_reference_observables.json"

# ==========================================================================
# Step 2: Check ROM stubs (same as Session C)
# ==========================================================================
echo ""
echo "=== [2] ROM stub check ==="
for f in "${ROOT}/vectors/meyr_pss_reference_romhex.txt" \
          "${ROOT}/vectors/meyr_sss_reference_romhex.txt"; do
    if [[ ! -f "$f" ]]; then
        echo "  Creating zero stub: $f"
        python3 -c "print('\n'.join(['00000000']*256))" > "$f"
    fi
done
echo "  ROM stubs OK"

# ==========================================================================
# Step 3: Compile and run RTL observable dump TB
# ==========================================================================
if [[ ${SKIP_SIM} -eq 1 ]]; then
    echo ""
    echo "=== [3] RTL simulation SKIPPED (--skip-sim) ==="
else
    echo ""
    echo "=== [3] RTL observable dump simulation ==="

    # Source list (same as Session C)
    LEGACY_SRCS=(
        "${ROOT}/rtl/phase2_legacy/complex_mult.v"
        "${ROOT}/rtl/phase2_legacy/complex_to_mag.v"
        "${ROOT}/rtl/phase2_legacy/delay_sample.v"
        "${ROOT}/rtl/phase2_legacy/delayT.v"
        "${ROOT}/rtl/phase2_legacy/moving_avg_optimized.v"
        "${ROOT}/rtl/phase2_legacy/ram_2port.v"
    )

    UNIT_TEST_SRCS=(
        "${ROOT}/rtl/unit_test/and2.v"
        "${ROOT}/rtl/unit_test/cp_autocorr_core.v"
        "${ROOT}/rtl/unit_test/timing_metric_core.v"
    )

    RTL_SRCS=(
        "${ROOT}/rtl/timing_sync_top.v"
        "${ROOT}/rtl/frac_cfo_estimator.v"
        "${ROOT}/rtl/timing_frac_cfo_top.v"
        "${ROOT}/rtl/iq_frame_buffer.v"
        "${ROOT}/rtl/frac_cfo_corrector_top.v"
        "${ROOT}/rtl/fft256_dual_symbol_frontend.v"
        "${ROOT}/rtl/meyr_term2_ref_rom.v"
        "${ROOT}/rtl/meyr_integer_cfo_fft_frontend_top.v"
        "${ROOT}/rtl/axis_complex_mult.v"
        "${ROOT}/rtl/complex_mult_iq.v"
        "${ROOT}/rtl/complex_rotator.v"
        "${ROOT}/rtl/cordic_atan2.v"
        "${ROOT}/rtl/nco_phase_gen.v"
        "${ROOT}/rtl/peak_detector.v"
        "${ROOT}/rtl/meyr_integer_cfo_core.v"
        "${ROOT}/rtl/meyr_pss_sss_product_gen.v"
        "${ROOT}/rtl/meyr_integer_cfo_freq_estimator_top.v"
        "${ROOT}/rtl/pss_sss_symbol_extractor.v"
        "${ROOT}/rtl/slot_start_controller.v"
        "${ROOT}/rtl/sample_power_sq.v"
        "${ROOT}/rtl/sliding_window_sum.v"
        "${ROOT}/rtl/frame_detect_fsm.v"
        "${ROOT}/rtl/frame_detector.v"
        "${ROOT}/rtl/frac_cfo_frame_corrector_top.v"
        "${ROOT}/rtl/phase3_sync_top.v"
        "${ROOT}/rtl/iq_replay_buffer_576.v"
        "${ROOT}/rtl/phase3_axi_lite_regs.v"
        "${ROOT}/rtl/phase3_sync_axis_dma_wrapper.v"
    )

    TB_SRC="${ROOT}/tb/session_D_p3_15a_phase3_observable_dump_tb.sv"
    ALL_SRCS=( "${LEGACY_SRCS[@]}" "${UNIT_TEST_SRCS[@]}" "${RTL_SRCS[@]}" )

    # Pre-flight checks
    MISSING=0
    for f in "${ALL_SRCS[@]}" "${TB_SRC}"; do
        if [[ ! -f "$f" ]]; then
            echo "  MISSING: $f"; MISSING=$((MISSING + 1))
        fi
    done
    if [[ $MISSING -gt 0 ]]; then
        echo "ERROR: $MISSING source file(s) missing." >&2; exit 1
    fi
    if [[ ! -f "${ROOT}/golden/phase3_iq_stimulus.mem" ]]; then
        echo "ERROR: golden/phase3_iq_stimulus.mem not found." >&2
        echo "  Run: python3 scripts/gen_phase3_iq_stimulus.py" >&2
        exit 1
    fi

    SIM_VVP="${ROOT}/sim_out/session_D_p3_15a.vvp"
    SIM_LOG="${LOGS}/session_D_p3_15a_sim.log"
    COMPILE_LOG="${LOGS}/session_D_p3_15a_compile.log"

    if [[ "${SIM_TOOL}" == "iverilog" ]]; then
        command -v iverilog &>/dev/null || {
            echo "BLOCKED_IVERILOG_UNAVAILABLE" >&2; exit 1
        }
        echo "  Compiling with iverilog..."
        iverilog -g2012 \
            -I "${ROOT}/vectors" \
            -o "${SIM_VVP}" \
            "${ALL_SRCS[@]}" \
            "${TB_SRC}" \
            2>&1 | tee "${COMPILE_LOG}"
        COMPILE_EXIT="${PIPESTATUS[0]}"
        if [[ ${COMPILE_EXIT} -ne 0 ]]; then
            echo "ERROR: iverilog compile failed (exit ${COMPILE_EXIT})" >&2
            echo "  See: ${COMPILE_LOG}" >&2; exit 1
        fi
        echo "  Compile: OK"
        echo "  Simulating..."
        vvp "${SIM_VVP}" 2>&1 | tee "${SIM_LOG}"
        SIM_EXIT="${PIPESTATUS[0]}"

    elif [[ "${SIM_TOOL}" == "xsim" ]]; then
        command -v xvlog &>/dev/null || {
            echo "BLOCKED_XSIM_UNAVAILABLE"; exit 1
        }
        WORK="${ROOT}/sim_out/session_D_p3_15a_work"
        mkdir -p "${WORK}"
        pushd "${WORK}" > /dev/null
        xvlog --nolog "${ALL_SRCS[@]}" 2>&1 | tee "${COMPILE_LOG}"
        xvlog --nolog -sv "${TB_SRC}" 2>&1 | tee -a "${COMPILE_LOG}"
        xelab --nolog -debug typical session_D_p3_15a_phase3_observable_dump_tb \
              -snapshot session_D_p3_15a_snap \
              --include "${ROOT}/vectors" \
              2>&1 | tee "${LOGS}/session_D_p3_15a_xelab.log"
        xsim --nolog session_D_p3_15a_snap --runall \
             --log "${SIM_LOG}" 2>&1
        popd > /dev/null
        SIM_EXIT=0

    else
        echo "ERROR: Unknown simulator '${SIM_TOOL}'" >&2; exit 1
    fi

    echo ""
    echo "--- Simulation summary ---"
    grep -E "PASS|FAIL|SANITY_GATE|WDG|SESSION_D|ERROR" "${SIM_LOG}" 2>/dev/null || true
fi

# ==========================================================================
# Step 4: Normalize RTL outputs
# ==========================================================================
echo ""
echo "=== [4] Normalize RTL outputs ==="

RTL_OBS="${SIM_OUT}/rtl_observables.txt"
if [[ ! -f "${RTL_OBS}" ]]; then
    echo "  [warn] rtl_observables.txt not found — normalization will produce partial JSON"
fi

python3 "${SCRIPT_DIR}/normalize_rtl_phase3_outputs.py" \
    --sim-dir "${SIM_OUT}" \
    2>&1 | tee "${LOGS}/session_D_p3_15a_normalize.log"
NORMALIZE_EXIT="${PIPESTATUS[0]}"

RTL_JSON="${SIM_OUT}/rtl_observables.json"
if [[ ! -f "${RTL_JSON}" ]]; then
    echo "ERROR: RTL JSON not created." >&2; exit 1
fi
echo "  RTL observables JSON: ${RTL_JSON}"

# ==========================================================================
# Step 4b: Generate C M_AXIS IQ golden (P3-15B)
# ==========================================================================
echo ""
echo "=== [4b] Generate C M_AXIS IQ golden ==="

GEN_GOLDEN_LOG="${LOGS}/session_D_p3_15a_gen_c_iq.log"
python3 "${SCRIPT_DIR}/gen_c_m_axis_iq_golden.py" \
    2>&1 | tee "${GEN_GOLDEN_LOG}"
GEN_EXIT="${PIPESTATUS[0]}"

if [[ ${GEN_EXIT} -ne 0 ]]; then
    echo "  [warn] gen_c_m_axis_iq_golden.py exited ${GEN_EXIT} — Stage 4/5 may remain BLOCKED"
else
    echo "  C IQ golden: ${GOLDEN_D}/c_m_axis_iq_golden.txt"
fi

# ==========================================================================
# Step 5: Run staged comparison
# ==========================================================================
echo ""
echo "=== [5] Staged comparison ==="

COMPARE_LOG="${LOGS}/session_D_p3_15a_compare.log"
python3 "${SCRIPT_DIR}/compare_full_phase3_against_c_reference.py" \
    --c-ref "${GOLDEN_D}/c_reference_observables.json" \
    --rtl   "${RTL_JSON}" \
    --report-dir "${REPORTS}" \
    2>&1 | tee "${COMPARE_LOG}"
COMPARE_EXIT="${PIPESTATUS[0]}"

# ==========================================================================
# Step 6: Final gate
# ==========================================================================
echo ""
echo "======================================================================"
echo "=== [6] Session D / P3-15A Final Gate ==="
echo "======================================================================"

GATE_RESULT=""
GATE_LINE=""

if grep -qE "^EQUIV_GATE: FAIL"                 "${COMPARE_LOG}" 2>/dev/null; then
    GATE_RESULT="FAIL"
elif grep -qE "^EQUIV_GATE: PASS$"              "${COMPARE_LOG}" 2>/dev/null; then
    GATE_RESULT="PASS"
elif grep -qE "^EQUIV_GATE: PARTIAL_PASS_BLOCKED" "${COMPARE_LOG}" 2>/dev/null; then
    GATE_RESULT="PARTIAL_PASS_BLOCKED"
else
    GATE_RESULT="UNKNOWN"
fi

if [[ "${SIM_TOOL}" == "iverilog" ]]; then
    case "${GATE_RESULT}" in
        PASS)
            echo "SANITY_EQUIV_GATE: PASS (iverilog)"
            echo "  All stages PASS — Stages 0-5 complete."
            echo "  NOTE: iverilog sanity only; xsim required for official CI_GATE PASS."
            GATE_LINE="SANITY_EQUIV_GATE: PASS (iverilog)"
            ;;
        PARTIAL_PASS_BLOCKED)
            echo "SANITY_EQUIV_GATE: PARTIAL_PASS_BLOCKED"
            echo "  Available fields match C reference."
            echo "  Blocked: Stage 4/5 require C M_AXIS golden provision."
            GATE_LINE="SANITY_EQUIV_GATE: PARTIAL_PASS_BLOCKED"
            ;;
        FAIL)
            echo "SANITY_EQUIV_GATE: FAIL"
            echo "  One or more available required fields mismatched."
            echo "  See: ${COMPARE_LOG}"
            GATE_LINE="SANITY_EQUIV_GATE: FAIL"
            ;;
        *)
            echo "SANITY_EQUIV_GATE: UNKNOWN"
            echo "  Could not determine gate from compare log."
            GATE_LINE="SANITY_EQUIV_GATE: UNKNOWN"
            ;;
    esac
else
    case "${GATE_RESULT}" in
        PASS)
            echo "EQUIV_GATE: PASS"
            GATE_LINE="EQUIV_GATE: PASS"
            ;;
        PARTIAL_PASS_BLOCKED)
            echo "EQUIV_GATE: PARTIAL_PASS_BLOCKED"
            GATE_LINE="EQUIV_GATE: PARTIAL_PASS_BLOCKED"
            ;;
        FAIL)
            echo "EQUIV_GATE: FAIL"
            GATE_LINE="EQUIV_GATE: FAIL"
            ;;
        *)
            echo "EQUIV_GATE: UNKNOWN"
            GATE_LINE="EQUIV_GATE: UNKNOWN"
            ;;
    esac
fi

echo ""
echo "  Logs:"
echo "    C export:   ${LOGS}/session_D_p3_15a_c_export.log"
echo "    Sim:        ${LOGS}/session_D_p3_15a_sim.log"
echo "    Normalize:  ${LOGS}/session_D_p3_15a_normalize.log"
echo "    Compare:    ${LOGS}/session_D_p3_15a_compare.log"
echo "    Report:     ${REPORTS}/equivalence_comparison_result.txt"

# Write final gate to report
{
    echo ""
    echo "Runner gate: ${GATE_LINE}"
    echo "Simulator: ${SIM_TOOL}"
    echo "Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
} >> "${REPORTS}/equivalence_comparison_result.txt"

if [[ "${GATE_RESULT}" == "FAIL" ]]; then
    exit 1
else
    exit 0
fi
