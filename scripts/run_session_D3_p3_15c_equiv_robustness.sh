#!/usr/bin/env bash
# run_session_D3_p3_15c_equiv_robustness.sh — P3-15C Equivalence Robustness Runner
#
# Runs Session D3: 5-stimulus C-reference equivalence expansion.
#
# Steps:
#   1. Generate 5 stimuli   (scripts/gen_p3_15c_multi_stimuli.py)
#   2. Compile RTL + D3 TB  (iverilog)
#   3. For each stimulus:
#        a. Run golden_dump.c to get C reference golden_values.txt
#        b. Simulate with vvp +STIM_FILE= +OUT_PREFIX=
#        c. Run Python compare script
#   4. Emit ROBUST_EQUIV_GATE: PASS / FAIL
#
# Gate:
#   iverilog: SANITY_ROBUST_EQUIV_GATE: PASS / FAIL
#   xsim:     ROBUST_EQUIV_GATE: PASS / FAIL (requires Vivado)
#
# Usage:
#   bash scripts/run_session_D3_p3_15c_equiv_robustness.sh [--sim iverilog|xsim]
#
# Watchdog: 200000 cycles per stimulus (~2s each)

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="${ROOT}/scripts"
SIM_TOOL="iverilog"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --sim) SIM_TOOL="$2"; shift 2 ;;
        *) shift ;;
    esac
done

echo ""
echo "=== session_D3_p3_15c_equiv_robustness ==="
echo "    Simulator: ${SIM_TOOL}"
echo ""

# ── Output directories ─────────────────────────────────────────────────────────
SIM_OUT="${ROOT}/sim_out/session_D3_p3_15c"
LOGS="${ROOT}/logs"
REPORTS="${ROOT}/reports/session_D3_p3_15c"
GOLDEN_D="${ROOT}/golden/p3_15c_stimuli"

mkdir -p "${SIM_OUT}" "${LOGS}" "${REPORTS}"

# ── xsim not available in this environment ────────────────────────────────────
if [[ "${SIM_TOOL}" == "xsim" ]]; then
    echo "SANITY_ROBUST_EQUIV_GATE: BLOCKED_XSIM_UNAVAILABLE"
    exit 1
fi

if ! command -v iverilog &>/dev/null; then
    echo "SANITY_ROBUST_EQUIV_GATE: BLOCKED_IVERILOG_NOT_FOUND"
    exit 1
fi

if ! command -v python3 &>/dev/null; then
    echo "SANITY_ROBUST_EQUIV_GATE: BLOCKED_PYTHON3_NOT_FOUND"
    exit 1
fi

# ── Step 1: Generate stimuli ───────────────────────────────────────────────────
echo "=== [1] Generate stimuli ==="
python3 "${SCRIPTS}/gen_p3_15c_multi_stimuli.py" \
    2>&1 | tee "${LOGS}/session_D3_p3_15c_gen.log"
if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    echo "SANITY_ROBUST_EQUIV_GATE: FAIL (stimulus generation failed)"
    exit 1
fi

# Verify stimulus files
BLOCKED=0
for id in stim_01 stim_02 stim_03 stim_04 stim_05; do
    if [[ ! -f "${GOLDEN_D}/${id}.mem" ]]; then
        echo "  MISSING: ${GOLDEN_D}/${id}.mem"
        BLOCKED=1
    fi
    if [[ ! -f "${GOLDEN_D}/${id}.f32" ]]; then
        echo "  MISSING: ${GOLDEN_D}/${id}.f32"
        BLOCKED=1
    fi
done
if [[ $BLOCKED -ne 0 ]]; then
    echo "SANITY_ROBUST_EQUIV_GATE: FAIL (missing stimulus files)"
    exit 1
fi
echo "  All 5 stimulus files present."

# ── Step 2: Compile ────────────────────────────────────────────────────────────
echo ""
echo "=== [2] Compile ==="

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
TB_SRC="${ROOT}/tb/session_D3_p3_15c_equiv_tb.sv"
ALL_SRCS=( "${LEGACY_SRCS[@]}" "${UNIT_TEST_SRCS[@]}" "${RTL_SRCS[@]}" )

MISSING_SRCS=0
for f in "${ALL_SRCS[@]}" "${TB_SRC}"; do
    if [[ ! -f "$f" ]]; then
        echo "  MISSING: $f"
        MISSING_SRCS=$((MISSING_SRCS + 1))
    fi
done
if [[ $MISSING_SRCS -gt 0 ]]; then
    echo "SANITY_ROBUST_EQUIV_GATE: FAIL (${MISSING_SRCS} source file(s) missing)"
    exit 1
fi

VVP_OUT="${SIM_OUT}/session_D3_p3_15c.vvp"

iverilog -g2012 \
    -I "${ROOT}/vectors" \
    -o "${VVP_OUT}" \
    "${ALL_SRCS[@]}" "${TB_SRC}" \
    2>&1 | tee "${LOGS}/session_D3_p3_15c_compile.log"

if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    echo "SANITY_ROBUST_EQUIV_GATE: FAIL (compile error)"
    exit 1
fi
echo "  Compile: OK  → ${VVP_OUT}"

# ── Check golden_dump binary ───────────────────────────────────────────────────
GOLDEN_DUMP="${SCRIPTS}/golden_dump"
if [[ ! -x "${GOLDEN_DUMP}" ]]; then
    echo "  golden_dump not found or not executable — building..."
    gcc -O2 -lm -o "${GOLDEN_DUMP}" "${SCRIPTS}/golden_dump.c"
    echo "  Built: ${GOLDEN_DUMP}"
fi

# ── Step 3: Per-stimulus loop ──────────────────────────────────────────────────
echo ""
echo "=== [3] Per-stimulus simulation + compare ==="

STIM_IDS=( stim_01 stim_02 stim_03 stim_04 stim_05 )
PASS_COUNT=0
FAIL_COUNT=0
FAIL_LIST=""

cd "${ROOT}"

for STIM_ID in "${STIM_IDS[@]}"; do
    echo ""
    echo "--- ${STIM_ID} ---"

    STIM_MEM="${GOLDEN_D}/${STIM_ID}.mem"
    STIM_F32="${GOLDEN_D}/${STIM_ID}.f32"
    OUT_PFX="${SIM_OUT}/${STIM_ID}"
    GOLDEN_TXT="${GOLDEN_D}/${STIM_ID}_golden.txt"
    AUTOCORR_TXT="${GOLDEN_D}/${STIM_ID}_autocorr.txt"
    SIM_LOG="${LOGS}/session_D3_p3_15c_${STIM_ID}_sim.log"

    # 3a: C reference golden
    echo "  [3a] golden_dump: ${STIM_F32}"
    "${GOLDEN_DUMP}" "${STIM_F32}" "${GOLDEN_TXT}" "${AUTOCORR_TXT}" \
        2>&1 | tee "${LOGS}/session_D3_p3_15c_${STIM_ID}_golden.log"
    if [[ ! -f "${GOLDEN_TXT}" ]]; then
        echo "  ERROR: golden_dump did not produce ${GOLDEN_TXT}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAIL_LIST="${FAIL_LIST} ${STIM_ID}(golden_dump)"
        continue
    fi

    # 3b: RTL simulation
    echo "  [3b] vvp simulation"
    vvp "${VVP_OUT}" \
        "+STIM_FILE=${STIM_MEM}" \
        "+OUT_PREFIX=${OUT_PFX}" \
        "+STIM_LABEL=${STIM_ID}" \
        2>&1 | tee "${SIM_LOG}"
    SIM_EXIT=${PIPESTATUS[0]}

    STIM_GATE=$(grep -E "^STIM_GATE:" "${SIM_LOG}" | tail -1 || echo "")
    if [[ -z "${STIM_GATE}" ]] || echo "${STIM_GATE}" | grep -q "FAIL"; then
        echo "  RTL structural check: FAIL"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAIL_LIST="${FAIL_LIST} ${STIM_ID}(rtl)"
        continue
    fi
    echo "  RTL structural check: PASS"

    # 3c: Python compare
    echo "  [3c] Python equivalence compare"
    python3 "${SCRIPTS}/compare_session_D3_p3_15c_equiv.py" \
        --stim-id "${STIM_ID}" \
        --golden  "${GOLDEN_TXT}" \
        --status  "${OUT_PFX}_status.txt" \
        --m-axis  "${OUT_PFX}_m_axis_iq.txt" \
        --frac    "${OUT_PFX}_frac_iq.txt" \
        2>&1 | tee "${LOGS}/session_D3_p3_15c_${STIM_ID}_compare.log"
    CMP_EXIT=${PIPESTATUS[0]}

    EQUIV_RESULT=$(grep -E "^STIM_EQUIV_GATE:" \
        "${LOGS}/session_D3_p3_15c_${STIM_ID}_compare.log" | tail -1 || echo "")

    if echo "${EQUIV_RESULT}" | grep -q "PASS"; then
        echo "  ${STIM_ID}: PASS"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  ${STIM_ID}: FAIL"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAIL_LIST="${FAIL_LIST} ${STIM_ID}"
    fi
done

# ── Step 4: Final gate ─────────────────────────────────────────────────────────
echo ""
echo "=== [4] Gate ==="
echo "  Stimuli passed: ${PASS_COUNT}/5"
echo "  Stimuli failed: ${FAIL_COUNT}/5"

GATE_FILE="${REPORTS}/robust_equiv_gate.txt"

if [[ ${FAIL_COUNT} -eq 0 ]]; then
    GATE="ROBUST_EQUIV_GATE: PASS"
    SANITY_GATE="SANITY_ROBUST_EQUIV_GATE: PASS"
else
    GATE="ROBUST_EQUIV_GATE: FAIL (failed:${FAIL_LIST})"
    SANITY_GATE="SANITY_ROBUST_EQUIV_GATE: FAIL (failed:${FAIL_LIST})"
fi

echo "${SANITY_GATE}"
echo "  Sim log dir: ${LOGS}/"

{
    echo "${SANITY_GATE}"
    echo "Simulator: iverilog"
    echo "Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo ""
    echo "Stimuli:"
    for STIM_ID in "${STIM_IDS[@]}"; do
        CMP_LOG="${LOGS}/session_D3_p3_15c_${STIM_ID}_compare.log"
        RESULT=$(grep -E "^STIM_EQUIV_GATE:" "${CMP_LOG}" 2>/dev/null | tail -1 || echo "no result")
        echo "  ${STIM_ID}: ${RESULT}"
    done
} > "${GATE_FILE}"

if [[ ${FAIL_COUNT} -eq 0 ]]; then
    exit 0
else
    exit 1
fi
