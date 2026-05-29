#!/usr/bin/env bash
# run_session_D4_p3_15d_regression.sh — P3-15D Long-Run Randomized Equivalence Regression
#
# Session D4 — expands the P3-15C 5-stimulus suite to 100 random cases.
#
# Sub-tests:
#   D4-1  Generate 100 random stimuli (randomised CFO, offset, amplitude, noise)
#   D4-2  Metadata equivalence  (frame_start, peak_lag, slot_start, frac_cfo, int_cfo)
#   D4-3  IQ equivalence        (576 corrected samples, ≤1 LSB)
#   D4-4  Failure clustering    (frame_detect / frac_cfo / int_cfo / iq_mismatch)
#   D4-5  Dashboard             docs/session_D4_randomized_equivalence_dashboard.md
#
# Gate:
#   RANDOM_EQUIV_GATE: PASS  — 100/100 cases pass
#   RANDOM_EQUIV_GATE: FAIL  — any failure or blocked
#
# DUT: phase3_sync_axis_dma_wrapper (iverilog)
# TB:  session_D3_p3_15c_equiv_tb.sv  (reused, plusarg-driven)
#
# Usage:
#   bash scripts/run_session_D4_p3_15d_regression.sh [--n-cases N] [--skip-gen]
#                                                     [--log-dir DIR]
#
# Exit: 0=PASS  1=FAIL
#
# Runtime estimate: ~2s per case × 100 = ~3 minutes (iverilog)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SCRIPTS="${ROOT}/scripts"

# ── Defaults ──────────────────────────────────────────────────────────────────
N_CASES=100
SKIP_GEN=0
LOG_DIR="${ROOT}/logs"
SIM_OUT="${ROOT}/sim_out/session_D4_p3_15d"
REPORTS="${ROOT}/reports/session_D4_p3_15d"
GOLDEN_D="${ROOT}/golden/p3_15d_stimuli"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --n-cases)    shift; N_CASES="$1" ;;
        --skip-gen)   SKIP_GEN=1 ;;
        --log-dir)    shift; LOG_DIR="$1" ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
    shift
done

mkdir -p "${LOG_DIR}" "${SIM_OUT}" "${REPORTS}" "${REPORTS}/per_case"

GATE_LOG="${REPORTS}/random_equiv_gate.txt"

echo "========================================================================"
echo "P3-15D  Long-Run Randomized Equivalence Regression"
echo "  Date     : $(date '+%Y-%m-%d %H:%M:%S')"
echo "  Root     : ${ROOT}"
echo "  N_Cases  : ${N_CASES}"
echo "  Log dir  : ${LOG_DIR}"
echo "========================================================================"

# ── Tool checks ────────────────────────────────────────────────────────────────
for tool in iverilog vvp python3 gcc; do
    if ! command -v "${tool}" &>/dev/null; then
        echo "ERROR: ${tool} not found in PATH"
        echo "RANDOM_EQUIV_GATE: FAIL (${tool} unavailable)" | tee "${GATE_LOG}"
        exit 1
    fi
done
echo "  iverilog : $(iverilog -V 2>&1 | head -1)"
echo "  python3  : $(python3 --version 2>&1)"

# ── Step 1: Generate stimuli ───────────────────────────────────────────────────
echo ""
echo "=== [1] Generate ${N_CASES} random stimuli ==="

if [[ "${SKIP_GEN}" -eq 0 ]]; then
    python3 "${SCRIPTS}/gen_p3_15d_random_stimuli.py" \
        --n-cases "${N_CASES}" \
        2>&1 | tee "${LOG_DIR}/session_D4_p3_15d_gen.log"
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        echo "RANDOM_EQUIV_GATE: FAIL (stimulus generation failed)" | tee "${GATE_LOG}"
        exit 1
    fi
else
    echo "  --skip-gen: reusing existing stimuli in ${GOLDEN_D}"
fi

# Verify stimulus files exist
BLOCKED=0
for (( i=0; i<N_CASES; i++ )); do
    id=$(printf "case_%03d" "${i}")
    for ext in .mem .f32 _meta.json; do
        if [[ ! -f "${GOLDEN_D}/${id}${ext}" ]]; then
            echo "  MISSING: ${GOLDEN_D}/${id}${ext}"
            BLOCKED=1
        fi
    done
done
if [[ "${BLOCKED}" -ne 0 ]]; then
    echo "RANDOM_EQUIV_GATE: FAIL (missing stimulus files)" | tee "${GATE_LOG}"
    exit 1
fi
echo "  All ${N_CASES} stimulus sets present."

# ── Step 2: Compile ────────────────────────────────────────────────────────────
echo ""
echo "=== [2] Compile RTL + TB ==="

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
if [[ "${MISSING_SRCS}" -gt 0 ]]; then
    echo "RANDOM_EQUIV_GATE: FAIL (${MISSING_SRCS} source file(s) missing)" | tee "${GATE_LOG}"
    exit 1
fi

VVP_OUT="${SIM_OUT}/session_D4_p3_15d.vvp"
iverilog -g2012 \
    -I "${ROOT}/vectors" \
    -o "${VVP_OUT}" \
    "${ALL_SRCS[@]}" "${TB_SRC}" \
    2>&1 | tee "${LOG_DIR}/session_D4_p3_15d_compile.log"
CC_RC=${PIPESTATUS[0]}
if [[ "${CC_RC}" -ne 0 ]]; then
    echo "RANDOM_EQUIV_GATE: FAIL (compile error rc=${CC_RC})" | tee "${GATE_LOG}"
    exit 1
fi
echo "  Compile: OK → ${VVP_OUT}"

# ── Build golden_dump if needed ────────────────────────────────────────────────
GOLDEN_DUMP="${SCRIPTS}/golden_dump"
if [[ ! -x "${GOLDEN_DUMP}" ]]; then
    echo "  Building golden_dump..."
    gcc -O2 -lm -o "${GOLDEN_DUMP}" "${SCRIPTS}/golden_dump.c"
fi

# ── Step 3: Per-case loop ──────────────────────────────────────────────────────
echo ""
echo "=== [3] Per-case simulation + compare (${N_CASES} cases) ==="

cd "${ROOT}"

PASS_COUNT=0
FAIL_COUNT=0
FAIL_LIST=""

for (( i=0; i<N_CASES; i++ )); do
    CASE_ID=$(printf "case_%03d" "${i}")
    STIM_MEM="${GOLDEN_D}/${CASE_ID}.mem"
    STIM_F32="${GOLDEN_D}/${CASE_ID}.f32"
    STIM_META="${GOLDEN_D}/${CASE_ID}_meta.json"
    OUT_PFX="${SIM_OUT}/${CASE_ID}"
    GOLDEN_TXT="${GOLDEN_D}/${CASE_ID}_golden.txt"
    AUTOCORR_TXT="${GOLDEN_D}/${CASE_ID}_autocorr.txt"
    SIM_LOG="${LOG_DIR}/session_D4_p3_15d_${CASE_ID}_sim.log"
    JSON_OUT="${REPORTS}/per_case/${CASE_ID}.json"

    # 3a: C reference golden (Steps 1-3)
    "${GOLDEN_DUMP}" "${STIM_F32}" "${GOLDEN_TXT}" "${AUTOCORR_TXT}" \
        > "${LOG_DIR}/session_D4_p3_15d_${CASE_ID}_golden.log" 2>&1
    if [[ ! -f "${GOLDEN_TXT}" ]]; then
        echo "  ${CASE_ID}: FAIL (golden_dump failed)"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAIL_LIST="${FAIL_LIST} ${CASE_ID}(golden)"
        continue
    fi

    # 3b: RTL simulation
    vvp "${VVP_OUT}" \
        "+STIM_FILE=${STIM_MEM}" \
        "+OUT_PREFIX=${OUT_PFX}" \
        "+STIM_LABEL=${CASE_ID}" \
        > "${SIM_LOG}" 2>&1
    STIM_GATE=$(grep -E "^STIM_GATE:" "${SIM_LOG}" | tail -1 || echo "")
    if [[ -z "${STIM_GATE}" ]] || echo "${STIM_GATE}" | grep -q "FAIL"; then
        echo "  ${CASE_ID}: FAIL (RTL structural check: ${STIM_GATE})"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAIL_LIST="${FAIL_LIST} ${CASE_ID}(rtl)"
        # Write minimal JSON for dashboard
        python3 -c "
import json, sys
with open('${JSON_OUT}','w') as f:
    json.dump({'case_id':'${CASE_ID}','passed':False,
               'failure_clusters':['rtl_structural'],
               'd2':{'passed':False},'d3':{'passed':False}}, f)
    f.write('\n')
" 2>/dev/null || true
        continue
    fi

    # 3c: Python equivalence compare
    python3 "${SCRIPTS}/compare_session_D4_p3_15d_equiv.py" \
        --case-id "${CASE_ID}" \
        --golden  "${GOLDEN_TXT}" \
        --meta    "${STIM_META}" \
        --status  "${OUT_PFX}_status.txt" \
        --m-axis  "${OUT_PFX}_m_axis_iq.txt" \
        --frac    "${OUT_PFX}_frac_iq.txt" \
        --json-out "${JSON_OUT}" \
        > "${LOG_DIR}/session_D4_p3_15d_${CASE_ID}_compare.log" 2>&1
    CMP_RC=${PIPESTATUS[0]}

    EQUIV=$(grep -E "^CASE_EQUIV_GATE:" \
        "${LOG_DIR}/session_D4_p3_15d_${CASE_ID}_compare.log" | tail -1 || echo "")

    if echo "${EQUIV}" | grep -q "PASS"; then
        PASS_COUNT=$((PASS_COUNT + 1))
        if (( i % 10 == 0 || i == N_CASES - 1 )); then
            echo "  ${CASE_ID}: PASS  [${PASS_COUNT}/${N_CASES}]"
        fi
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAIL_LIST="${FAIL_LIST} ${CASE_ID}"
        echo "  ${CASE_ID}: FAIL  (${EQUIV})"
    fi
done

# ── Step 4: Gate ───────────────────────────────────────────────────────────────
echo ""
echo "=== [4] Gate ==="
echo "  Cases passed: ${PASS_COUNT}/${N_CASES}"
echo "  Cases failed: ${FAIL_COUNT}/${N_CASES}"
[[ -n "${FAIL_LIST}" ]] && echo "  Failures:${FAIL_LIST}"

# ── Step 5: Dashboard ─────────────────────────────────────────────────────────
echo ""
echo "=== [5] Dashboard ==="
DASHBOARD="${ROOT}/docs/session_D4_randomized_equivalence_dashboard.md"
mkdir -p "$(dirname "${DASHBOARD}")"

python3 "${SCRIPTS}/gen_p3_15d_dashboard.py" \
    --per-case-dir "${REPORTS}/per_case" \
    --n-cases      "${N_CASES}" \
    --out          "${DASHBOARD}"

DASH_RC=$?
if [[ "${DASH_RC}" -eq 0 ]]; then
    echo "  Dashboard: ${DASHBOARD}"
else
    echo "  WARNING: dashboard generation failed (rc=${DASH_RC})"
fi

# ── Final gate ─────────────────────────────────────────────────────────────────
echo ""
echo "=== [6] Final Gate ==="

{
    if [[ "${FAIL_COUNT}" -eq 0 ]]; then
        echo "RANDOM_EQUIV_GATE: PASS"
    else
        echo "RANDOM_EQUIV_GATE: FAIL (${FAIL_COUNT}/${N_CASES} failed)"
    fi
    echo "Simulator: iverilog"
    echo "Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo "Cases: ${PASS_COUNT}/${N_CASES} passed"
    [[ -n "${FAIL_LIST}" ]] && echo "Failed:${FAIL_LIST}"
} | tee "${GATE_LOG}"

if [[ "${FAIL_COUNT}" -eq 0 ]]; then
    exit 0
else
    exit 1
fi
