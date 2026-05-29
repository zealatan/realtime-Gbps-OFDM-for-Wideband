#!/usr/bin/env bash
# run_session_J_p3_21a_cfo_coverage.sh — P3-21A CFO Coverage Expansion
#
# Runs three sub-gates that together verify CFO robustness across the full
# Phase3 synchronization pipeline:
#
#   J1 — Integer CFO Sweep (standalone Meyr, behavioral DFT)
#          k_int ∈ {0, ±1, ±2, ±4, ±8, ±12, ±16}  (13 cases)
#          DUT: meyr_fft256_actual_integration_top (USE_BEHAVIORAL_STUB=3)
#          Checks: peak_index == 255 + k_int,  int_cfo == k_int
#
#   J2 — Fractional CFO Sweep (full wrapper)
#          frac ∈ {-0.45, -0.30, -0.15, 0, +0.15, +0.30, +0.45}  (7 cases)
#          DUT: phase3_sync_axis_dma_wrapper
#          Checks: frame_found, frac_cfo_valid, output_count==576, TLAST
#
#   J3 — Combined Sweep (full wrapper, bypass-FFT limitation documented)
#          (k_int, frac) ∈ {(+16,+0.45), (-16,-0.45), (+12,-0.30), (-12,+0.30)}
#          DUT: phase3_sync_axis_dma_wrapper
#          Checks: same as J2 (int_cfo not checked due to bypass-FFT)
#
# GATE OUTPUTS:
#   CFO_GATE: PASS  — J1_GATE + J2_GATE + J3_GATE all PASS
#   CFO_GATE: FAIL  — one or more sub-gates fail
#
# Sub-gate strings extracted from simulation logs:
#   J1_GATE: PASS / J1_GATE: FAIL
#   J2_GATE: PASS / J2_GATE: FAIL
#   J3_GATE: PASS / J3_GATE: FAIL
#
# USAGE:
#   bash scripts/run_session_J_p3_21a_cfo_coverage.sh [OPTIONS]
#
#   Options:
#     --skip-gen        Skip vector generation (use existing golden/p3_21a_sweep/)
#     --skip-j1         Skip J1 (integer CFO sweep)
#     --skip-j2j3       Skip J2 and J3 (full wrapper sweep)
#     --log-dir DIR     Override log directory (default: sim_out/session_J_p3_21a)
#
# EXIT CODES:
#   0  CFO_GATE: PASS
#   1  CFO_GATE: FAIL
#   2  Pre-flight blocked (missing files or tools)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SKIP_GEN=0
SKIP_J1=0
SKIP_J2J3=0
LOG_DIR="${ROOT}/sim_out/session_J_p3_21a"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-gen)   SKIP_GEN=1  ;;
        --skip-j1)    SKIP_J1=1   ;;
        --skip-j2j3)  SKIP_J2J3=1 ;;
        --log-dir)    shift; LOG_DIR="$1" ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done

mkdir -p "${LOG_DIR}"
GATE_LOG="${LOG_DIR}/p3_21a_gate.txt"
J1_LOG="${LOG_DIR}/p3_21a_j1.log"
J2J3_LOG="${LOG_DIR}/p3_21a_j2j3.log"

echo "========================================================================"
echo "P3-21A CFO Coverage Expansion"
echo "  Date       : $(date '+%Y-%m-%d %H:%M:%S')"
echo "  Root       : ${ROOT}"
echo "  Log dir    : ${LOG_DIR}"
echo "========================================================================"

# ---------------------------------------------------------------------------
# Tool detection
# ---------------------------------------------------------------------------
HAVE_IVERILOG=0
command -v iverilog &>/dev/null && HAVE_IVERILOG=1

if [[ "${HAVE_IVERILOG}" -eq 0 ]]; then
    echo ""
    echo "ERROR: iverilog not found in PATH.  Install iverilog 11+ to continue."
    echo "CFO_GATE: FAIL — iverilog unavailable" | tee "${GATE_LOG}"
    exit 2
fi

IVERILOG_VER=$(iverilog -V 2>&1 | head -1 || true)
echo "  iverilog   : ${IVERILOG_VER}"

# ---------------------------------------------------------------------------
# Step 1: Generate sweep vectors
# ---------------------------------------------------------------------------
echo ""
echo "========================================================================"
echo "Step 1: Vector Generation"
echo "========================================================================"

if [[ "${SKIP_GEN}" -eq 1 ]]; then
    echo "  --skip-gen: reusing existing vectors in golden/p3_21a_sweep/"
else
    if ! command -v python3 &>/dev/null; then
        echo "ERROR: python3 not found — cannot generate vectors." >&2
        echo "CFO_GATE: FAIL — python3 unavailable" | tee "${GATE_LOG}"
        exit 2
    fi

    echo "  Running: python3 scripts/gen_p3_21a_cfo_sweep_vectors.py"
    python3 "${SCRIPT_DIR}/gen_p3_21a_cfo_sweep_vectors.py" 2>&1 | tee "${LOG_DIR}/p3_21a_gen.log"
    GEN_RC=${PIPESTATUS[0]}
    if [[ "${GEN_RC}" -ne 0 ]]; then
        echo ""
        echo "ERROR: Vector generation failed (rc=${GEN_RC})." >&2
        echo "CFO_GATE: FAIL — vector generation error" | tee "${GATE_LOG}"
        exit 2
    fi
    echo "  Vector generation complete."
fi

# Verify J1 vector files exist
echo ""
echo "--- Checking J1 vector files ---"
J1_BLOCKED=0
for tag in kp0 kp1 km1 kp2 km2 kp4 km4 kp8 km8 kp12 km12 kp16 km16; do
    f="golden/p3_21a_sweep/j1_${tag}.mem"
    if [[ -f "${ROOT}/${f}" ]]; then
        echo "  [OK]   ${f}"
    else
        echo "  [MISS] ${f}"
        J1_BLOCKED=1
    fi
done

# Verify J2 vector files exist
echo ""
echo "--- Checking J2 vector files ---"
J2_BLOCKED=0
for tag in m045 m030 m015 p000 p015 p030 p045; do
    f="golden/p3_21a_sweep/j2_frac_${tag}.mem"
    if [[ -f "${ROOT}/${f}" ]]; then
        echo "  [OK]   ${f}"
    else
        echo "  [MISS] ${f}"
        J2_BLOCKED=1
    fi
done

# Verify J3 vector files exist
echo ""
echo "--- Checking J3 vector files ---"
J3_BLOCKED=0
for tag in kp16_fp045 km16_fm045 kp12_fm030 km12_fp030; do
    f="golden/p3_21a_sweep/j3_${tag}.mem"
    if [[ -f "${ROOT}/${f}" ]]; then
        echo "  [OK]   ${f}"
    else
        echo "  [MISS] ${f}"
        J3_BLOCKED=1
    fi
done

if [[ "${J1_BLOCKED}" -eq 1 ]] || [[ "${J2_BLOCKED}" -eq 1 ]] || [[ "${J3_BLOCKED}" -eq 1 ]]; then
    echo ""
    echo "ERROR: Missing sweep vector files — run without --skip-gen." >&2
    echo "CFO_GATE: FAIL — missing vector files" | tee "${GATE_LOG}"
    exit 2
fi

# ---------------------------------------------------------------------------
# Step 2: J1 — Integer CFO Sweep (standalone Meyr, behavioral DFT)
# ---------------------------------------------------------------------------
J1_GATE_RESULT="SKIPPED"

if [[ "${SKIP_J1}" -eq 0 ]]; then
    echo ""
    echo "========================================================================"
    echo "Step 2: J1 — Integer CFO Sweep (Meyr, USE_BEHAVIORAL_STUB=3)"
    echo "========================================================================"

    J1_RTL_SRCS=(
        "${ROOT}/rtl/meyr_fft256_harness_adapter.v"
        "${ROOT}/rtl/meyr_fft256_actual_integration_top.v"
        "${ROOT}/rtl/fft256_xilinx_wrapper.v"
        "${ROOT}/rtl/meyr_integer_cfo_freq_estimator_top.v"
        "${ROOT}/rtl/meyr_integer_cfo_core.v"
        "${ROOT}/rtl/meyr_pss_sss_product_gen.v"
        "${ROOT}/rtl/peak_detector.v"
    )
    J1_TB="${ROOT}/tb/session_J_p3_21a_j1_meyr_sweep_tb.sv"
    J1_VVP="${LOG_DIR}/p3_21a_j1.vvp"

    echo ""
    echo "--- Checking J1 source files ---"
    J1_SRC_BLOCKED=0
    for f in "${J1_RTL_SRCS[@]}" "${J1_TB}"; do
        bf="${f#${ROOT}/}"
        if [[ -f "$f" ]]; then
            echo "  [OK]   ${bf}"
        else
            echo "  [MISS] ${bf}"
            J1_SRC_BLOCKED=1
        fi
    done
    for f in "vectors/meyr_pss_fft_romhex.txt" "vectors/meyr_sss_fft_romhex.txt"; do
        if [[ -f "${ROOT}/${f}" ]]; then
            echo "  [OK]   ${f}"
        else
            echo "  [MISS] ${f}  — run: python3 scripts/gen_meyr_fft_reference_roms.py"
            J1_SRC_BLOCKED=1
        fi
    done

    if [[ "${J1_SRC_BLOCKED}" -eq 1 ]]; then
        echo ""
        echo "J1_GATE: FAIL — missing source files"
        J1_GATE_RESULT="FAIL"
    else
        echo ""
        echo "--- J1 compile (iverilog -g2012) ---"
        iverilog -g2012 \
            -P "session_J_p3_21a_j1_meyr_sweep_tb.USE_BEHAVIORAL_STUB=3" \
            -o "${J1_VVP}" \
            "${J1_TB}" \
            "${J1_RTL_SRCS[@]}" \
            2>&1 | tee "${LOG_DIR}/p3_21a_j1_compile.log"
        J1_CC=${PIPESTATUS[0]}

        if [[ "${J1_CC}" -ne 0 ]]; then
            echo ""
            echo "J1_GATE: FAIL — compile error (rc=${J1_CC})"
            J1_GATE_RESULT="FAIL"
        else
            echo "  Compile OK: ${J1_VVP}"
            echo ""
            echo "--- J1 simulate (vvp) ---"
            # Run from ROOT so relative paths (golden/, vectors/) resolve correctly
            (cd "${ROOT}" && vvp "${J1_VVP}") 2>&1 | tee "${J1_LOG}"
            J1_SIM_RC=${PIPESTATUS[0]}

            echo ""
            echo "--- J1 gate evaluation ---"
            if grep -q "^J1_GATE: PASS" "${J1_LOG}"; then
                echo "J1_GATE: PASS"
                J1_GATE_RESULT="PASS"
            else
                echo "J1_GATE: FAIL"
                J1_GATE_RESULT="FAIL"
                grep -E "^\[J1\] (FAIL|PASS)" "${J1_LOG}" | tail -20 || true
            fi
        fi
    fi
else
    echo ""
    echo "=== J1: SKIPPED (--skip-j1) ==="
fi

# ---------------------------------------------------------------------------
# Step 3: J2/J3 — Full Wrapper Sweep
# ---------------------------------------------------------------------------
J2_GATE_RESULT="SKIPPED"
J3_GATE_RESULT="SKIPPED"

if [[ "${SKIP_J2J3}" -eq 0 ]]; then
    echo ""
    echo "========================================================================"
    echo "Step 3: J2/J3 — Full Wrapper Sweep (phase3_sync_axis_dma_wrapper)"
    echo "========================================================================"

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

    J2J3_TB="${ROOT}/tb/session_J_p3_21a_j2j3_wrapper_tb.sv"
    J2J3_VVP="${LOG_DIR}/p3_21a_j2j3.vvp"
    ALL_SRCS=( "${LEGACY_SRCS[@]}" "${UNIT_TEST_SRCS[@]}" "${RTL_SRCS[@]}" )

    echo ""
    echo "--- ROM stubs ---"
    for f in "${ROOT}/vectors/meyr_pss_reference_romhex.txt" \
              "${ROOT}/vectors/meyr_sss_reference_romhex.txt"; do
        if [[ ! -f "$f" ]]; then
            echo "  creating zero stub: $(basename $f)"
            python3 -c "print('\n'.join(['00000000']*256))" > "$f"
        else
            echo "  [OK]   $(basename $f)"
        fi
    done

    echo ""
    echo "--- Checking J2/J3 source files ---"
    J2J3_SRC_BLOCKED=0
    for f in "${ALL_SRCS[@]}" "${J2J3_TB}"; do
        bf="${f#${ROOT}/}"
        if [[ ! -f "$f" ]]; then
            echo "  [MISS] ${bf}"
            J2J3_SRC_BLOCKED=1
        fi
    done
    if [[ "${J2J3_SRC_BLOCKED}" -eq 0 ]]; then
        echo "  All ${#ALL_SRCS[@]} RTL sources + TB present."
    fi

    if [[ "${J2J3_SRC_BLOCKED}" -eq 1 ]]; then
        echo ""
        echo "J2_GATE: FAIL — missing source files"
        echo "J3_GATE: FAIL — missing source files"
        J2_GATE_RESULT="FAIL"
        J3_GATE_RESULT="FAIL"
    else
        echo ""
        echo "--- J2/J3 compile (iverilog -g2012) ---"
        iverilog -g2012 \
            -o "${J2J3_VVP}" \
            "${ALL_SRCS[@]}" \
            "${J2J3_TB}" \
            2>&1 | tee "${LOG_DIR}/p3_21a_j2j3_compile.log"
        J2J3_CC=${PIPESTATUS[0]}

        if [[ "${J2J3_CC}" -ne 0 ]]; then
            echo ""
            echo "J2_GATE: FAIL — compile error (rc=${J2J3_CC})"
            echo "J3_GATE: FAIL — compile error (rc=${J2J3_CC})"
            J2_GATE_RESULT="FAIL"
            J3_GATE_RESULT="FAIL"
        else
            echo "  Compile OK: ${J2J3_VVP}"
            echo ""
            echo "--- J2/J3 simulate (vvp) ---"
            (cd "${ROOT}" && vvp "${J2J3_VVP}") 2>&1 | tee "${J2J3_LOG}"

            echo ""
            echo "--- J2/J3 gate evaluation ---"
            if grep -q "^J2_GATE: PASS" "${J2J3_LOG}"; then
                echo "J2_GATE: PASS"
                J2_GATE_RESULT="PASS"
            else
                echo "J2_GATE: FAIL"
                J2_GATE_RESULT="FAIL"
            fi
            if grep -q "^J3_GATE: PASS" "${J2J3_LOG}"; then
                echo "J3_GATE: PASS"
                J3_GATE_RESULT="PASS"
            else
                echo "J3_GATE: FAIL"
                J3_GATE_RESULT="FAIL"
            fi

            if [[ "${J2_GATE_RESULT}" != "PASS" ]] || [[ "${J3_GATE_RESULT}" != "PASS" ]]; then
                grep -E "^\[(J2|J3)\] (FAIL|PASS)" "${J2J3_LOG}" | tail -20 || true
            fi
        fi
    fi
else
    echo ""
    echo "=== J2/J3: SKIPPED (--skip-j2j3) ==="
fi

# ---------------------------------------------------------------------------
# Aggregate CFO_GATE
# ---------------------------------------------------------------------------
echo ""
echo "========================================================================"
echo "P3-21A CFO Coverage — Summary"
echo "========================================================================"
echo ""
echo "  J1 (integer CFO sweep, behavioral DFT) : ${J1_GATE_RESULT}"
echo "  J2 (frac CFO sweep, full wrapper)      : ${J2_GATE_RESULT}"
echo "  J3 (combined sweep, full wrapper)      : ${J3_GATE_RESULT}"
echo ""

# CFO_GATE: PASS iff all non-skipped sub-gates pass
CFO_PASS=1

check_subgate() {
    local name="$1"; local result="$2"
    if [[ "${result}" == "FAIL" ]]; then
        CFO_PASS=0
        echo "  FAIL: ${name}"
    fi
}

check_subgate "J1_GATE" "${J1_GATE_RESULT}"
check_subgate "J2_GATE" "${J2_GATE_RESULT}"
check_subgate "J3_GATE" "${J3_GATE_RESULT}"

echo ""
if [[ "${CFO_PASS}" -eq 1 ]]; then
    echo "CFO_GATE: PASS" | tee "${GATE_LOG}"
    echo "  All enabled sub-gates passed."
    echo ""
    echo "========================================================================"
    exit 0
else
    echo "CFO_GATE: FAIL" | tee "${GATE_LOG}"
    echo "  One or more sub-gates failed — see logs:"
    echo "    J1 : ${J1_LOG}"
    echo "    J2/J3 : ${J2J3_LOG}"
    echo ""
    echo "========================================================================"
    exit 1
fi
