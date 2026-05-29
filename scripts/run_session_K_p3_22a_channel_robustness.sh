#!/usr/bin/env bash
# run_session_K_p3_22a_channel_robustness.sh — P3-22A Channel Robustness Validation
#
# DUT: phase3_sync_axis_dma_wrapper (same RTL as Session E)
# TB:  tb/session_K_p3_22a_channel_robustness_tb.sv
#
# Pipeline:
#   1. Generate 15 channel-impaired stimulus files (golden/p3_22a/*.mem)
#   2. For each case: compile RTL+TB with case-specific STIM_FILE, simulate
#   3. Parse per-case results (CASE_PASS / CASE_PARTIAL_PASS / CASE_FAIL)
#   4. Aggregate into CHANNEL_GATE
#
# Gate criteria:
#   CHANNEL_GATE: PASS         — all 11 gate-required cases → CASE_PASS
#   CHANNEL_GATE: PARTIAL_PASS — ≥ 8/11 required CASE_PASS; rest documented
#   CHANNEL_GATE: FAIL         — < 8 required CASE_PASS
#
# Gate-required cases (11):
#   awgn_snr30dB, awgn_snr20dB
#   mp2tap_d1, mp2tap_d4, mp2tap_d8, mp2tap_d16, mp2tap_d32
#   mp3tap_d1, mp3tap_d4, mp3tap_d8, mp3tap_d16
#
# Documented-only (3):
#   awgn_snr15dB, awgn_snr10dB — threshold limited; detection expected to fail
#   mp3tap_d32                 — 3rd tap delay=64 > CP_LEN; soft boundary
#
# Negative test (1):
#   neg_mp2tap_d33 — delay=33 > CP_LEN; any outcome documented as WARN/FAIL
#
# USAGE:
#   bash scripts/run_session_K_p3_22a_channel_robustness.sh [OPTIONS]
#
#   --sim iverilog|xsim    simulator (default: iverilog)
#   --log-dir DIR          log directory (default: sim_out/session_K_p3_22a)
#   --gen-only             generate vectors then exit (no simulation)
#   --skip-gen             skip vector generation (use existing golden/p3_22a/)
#   --case NAME            run a single named case (for debugging)
#
# EXIT CODES:
#   0  CHANNEL_GATE: PASS
#   1  CHANNEL_GATE: PARTIAL_PASS, FAIL, or BLOCKED_*

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SIM_TOOL="iverilog"
LOG_DIR="${ROOT}/sim_out/session_K_p3_22a"
GEN_ONLY=0
SKIP_GEN=0
SINGLE_CASE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --sim)       shift; SIM_TOOL="$1"   ;;
        --log-dir)   shift; LOG_DIR="$1"    ;;
        --gen-only)  GEN_ONLY=1             ;;
        --skip-gen)  SKIP_GEN=1             ;;
        --case)      shift; SINGLE_CASE="$1";;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
    shift
done

mkdir -p "${LOG_DIR}"

GATE_LOG="${LOG_DIR}/p3_22a_channel_gate.txt"
SUMMARY="${LOG_DIR}/p3_22a_summary.txt"

gate_out() {
    local msg="$1"
    echo ""
    echo "========================================================================"
    echo "${msg}"
    echo "========================================================================"
    echo "${msg}" > "${GATE_LOG}"
}

echo "========================================================================"
echo "P3-22A Channel Robustness Validation"
echo "  Date      : $(date '+%Y-%m-%d %H:%M:%S')"
echo "  Simulator : ${SIM_TOOL}"
echo "  Log dir   : ${LOG_DIR}"
echo "  Root      : ${ROOT}"
echo "========================================================================"

# --------------------------------------------------------------------------
# Sentinel: require manifest from gen step
# --------------------------------------------------------------------------
MANIFEST="${ROOT}/golden/p3_22a/manifest.json"

# --------------------------------------------------------------------------
# Step 1: Generate channel vectors
# --------------------------------------------------------------------------
if [[ "${SKIP_GEN}" -eq 0 ]]; then
    echo ""
    echo "--- Step 1: Generating channel vectors ---"
    python3 "${SCRIPT_DIR}/gen_p3_22a_channel_vectors.py"
    if [[ $? -ne 0 ]]; then
        gate_out "CHANNEL_GATE: BLOCKED_GEN_FAILED"
        exit 1
    fi
else
    echo ""
    echo "--- Step 1: Skipping vector generation (--skip-gen) ---"
fi

if [[ ! -f "${MANIFEST}" ]]; then
    gate_out "CHANNEL_GATE: BLOCKED_MISSING_MANIFEST"
    echo "  golden/p3_22a/manifest.json not found."
    echo "  Run without --skip-gen to generate vectors."
    exit 1
fi

[[ "${GEN_ONLY}" -eq 1 ]] && { echo "--- --gen-only: done ---"; exit 0; }

# --------------------------------------------------------------------------
# ROM stubs
# --------------------------------------------------------------------------
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
# Source file lists (identical to Session E runner)
# --------------------------------------------------------------------------
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

TB_SRC="${ROOT}/tb/session_K_p3_22a_channel_robustness_tb.sv"
ALL_SRCS=( "${LEGACY_SRCS[@]}" "${UNIT_TEST_SRCS[@]}" "${RTL_SRCS[@]}" )

# --------------------------------------------------------------------------
# Pre-flight: required files
# --------------------------------------------------------------------------
echo ""
echo "--- Pre-flight: required files ---"
BLOCKED=0
for f in "${ALL_SRCS[@]}" "${TB_SRC}"; do
    if [[ ! -f "$f" ]]; then
        echo "  [MISS] $f"
        BLOCKED=1
    fi
done
if [[ "${BLOCKED}" -eq 1 ]]; then
    gate_out "CHANNEL_GATE: BLOCKED_MISSING_FILES"
    exit 1
fi
echo "  All source files present."

# --------------------------------------------------------------------------
# xsim check
# --------------------------------------------------------------------------
if [[ "${SIM_TOOL}" == "xsim" ]]; then
    if ! command -v xvlog &>/dev/null; then
        gate_out "CHANNEL_GATE: BLOCKED_XSIM_UNAVAILABLE"
        echo "  xvlog not found in PATH.  Install Vivado and source settings64.sh."
        exit 1
    fi
elif [[ "${SIM_TOOL}" == "iverilog" ]]; then
    if ! command -v iverilog &>/dev/null; then
        gate_out "CHANNEL_GATE: BLOCKED_IVERILOG_UNAVAILABLE"
        exit 1
    fi
else
    gate_out "CHANNEL_GATE: BLOCKED_UNKNOWN_SIM"
    exit 1
fi

# --------------------------------------------------------------------------
# Test case list (name + gate-required flag)
# Format: "case_name:required"
# --------------------------------------------------------------------------
ALL_CASES=(
    "awgn_snr30dB:1"
    "awgn_snr20dB:1"
    "awgn_snr15dB:0"
    "awgn_snr10dB:0"
    "mp2tap_d1:1"
    "mp2tap_d4:1"
    "mp2tap_d8:1"
    "mp2tap_d16:1"
    "mp2tap_d32:1"
    "mp3tap_d1:1"
    "mp3tap_d4:1"
    "mp3tap_d8:1"
    "mp3tap_d16:1"
    "mp3tap_d32:0"
    "neg_mp2tap_d33:0"
)

# If --case given, run only that one case
if [[ -n "${SINGLE_CASE}" ]]; then
    ALL_CASES=("${SINGLE_CASE}:0")
    echo ""
    echo "--- Single-case mode: ${SINGLE_CASE} ---"
fi

# --------------------------------------------------------------------------
# Step 2: Compile once (iverilog) or check xsim environment
# --------------------------------------------------------------------------
# For iverilog we recompile per case (STIM_FILE is a compile-time macro).
# For xsim we would need a different approach (not yet implemented).

# --------------------------------------------------------------------------
# Per-case simulation loop
# --------------------------------------------------------------------------
echo ""
echo "--- Step 2: Simulating all test cases ---"
echo ""

# Summary table
printf "%-20s  %-8s  %-6s  %-6s  %-6s  %-6s  %-6s  %-8s\n" \
    "case" "required" "found" "drift" "frac" "intapp" "count" "result" \
    | tee "${SUMMARY}"
printf '%0.s-' {1..80} | tee -a "${SUMMARY}"
echo | tee -a "${SUMMARY}"

n_required=0
n_req_pass=0

for case_entry in "${ALL_CASES[@]}"; do
    CASE_NAME="${case_entry%%:*}"
    REQUIRED="${case_entry##*:}"

    # Check .mem file exists
    STIM_PATH="golden/p3_22a/${CASE_NAME}.mem"
    if [[ ! -f "${ROOT}/${STIM_PATH}" ]]; then
        echo "  [MISS] ${STIM_PATH} — skipping (run gen step first)"
        printf "%-20s  %-8s  %-6s  %-6s  %-6s  %-6s  %-6s  %-8s\n" \
            "${CASE_NAME}" "${REQUIRED}" "-" "-" "-" "-" "-" "MISSING" \
            | tee -a "${SUMMARY}"
        continue
    fi

    CASE_LOG="${LOG_DIR}/${CASE_NAME}_sim.log"
    CASE_VVP="${LOG_DIR}/${CASE_NAME}.vvp"
    CASE_VH="${LOG_DIR}/${CASE_NAME}_stim.vh"

    # Write the per-case STIM_FILE defines header
    printf '`define STIM_FILE "%s"\n' "${STIM_PATH}" > "${CASE_VH}"

    echo "  [SIM] ${CASE_NAME}  (required=${REQUIRED})"

    if [[ "${SIM_TOOL}" == "iverilog" ]]; then
        # Compile with per-case STIM_FILE header first in source list
        iverilog -g2012 \
                 "${CASE_VH}" \
                 "${ALL_SRCS[@]}" \
                 "${TB_SRC}" \
                 -o "${CASE_VVP}" \
                 2> "${LOG_DIR}/${CASE_NAME}_compile.log"
        compile_rc=$?
        if [[ ${compile_rc} -ne 0 ]]; then
            echo "       Compile FAILED (see ${CASE_NAME}_compile.log)"
            echo "COMPILE_FAIL" > "${CASE_LOG}"
            CASE_RESULT="COMPILE_FAIL"
        else
            # Simulate (working dir = ROOT so relative paths in $readmemh resolve)
            (cd "${ROOT}" && vvp "${CASE_VVP}") > "${CASE_LOG}" 2>&1
        fi
    fi  # (xsim path not implemented)

    # Parse result from log
    CASE_RESULT=$(grep -oP "^CASE_(PASS|PARTIAL_PASS|FAIL)$" "${CASE_LOG}" | tail -1)
    [[ -z "${CASE_RESULT}" ]] && CASE_RESULT="NO_GATE_LINE"

    # Extract RESULT fields for summary
    RLINE=$(grep "^RESULT " "${CASE_LOG}" | tail -1)
    FF=$(echo "${RLINE}"  | grep -oP "frame_found=\K[0-9-]+"  || echo "?")
    FD=$(echo "${RLINE}"  | grep -oP "frame_drift=\K[0-9-]+"  || echo "?")
    FV=$(echo "${RLINE}"  | grep -oP "frac_valid=\K[0-9]+"    || echo "?")
    IA=$(echo "${RLINE}"  | grep -oP "int_applied=\K[0-9]+"   || echo "?")
    OC=$(echo "${RLINE}"  | grep -oP "out_count=\K[0-9]+"     || echo "?")

    printf "%-20s  %-8s  %-6s  %-6s  %-6s  %-6s  %-6s  %-8s\n" \
        "${CASE_NAME}" "${REQUIRED}" "${FF}" "${FD}" "${FV}" "${IA}" "${OC}" \
        "${CASE_RESULT}" | tee -a "${SUMMARY}"

    # Gate accounting
    if [[ "${REQUIRED}" -eq 1 ]]; then
        n_required=$((n_required + 1))
        [[ "${CASE_RESULT}" == "CASE_PASS" ]] && n_req_pass=$((n_req_pass + 1))
    fi

    rm -f "${CASE_VH}" "${CASE_VVP}"
done

# --------------------------------------------------------------------------
# Step 3: CHANNEL_GATE aggregation
# --------------------------------------------------------------------------
echo ""
echo "========================================================================"
echo "Gate accounting:"
echo "  Required cases : ${n_required}"
echo "  Required PASS  : ${n_req_pass}"

if [[ ${n_req_pass} -eq ${n_required} && ${n_required} -gt 0 ]]; then
    gate_out "CHANNEL_GATE: PASS"
    echo "  All ${n_required} gate-required cases passed."
elif [[ ${n_req_pass} -ge 8 ]]; then
    gate_out "CHANNEL_GATE: PARTIAL_PASS"
    echo "  ${n_req_pass}/${n_required} required cases passed."
    echo "  See summary for individual case results."
else
    gate_out "CHANNEL_GATE: FAIL"
    echo "  Only ${n_req_pass}/${n_required} required cases passed (threshold: 8)."
    echo "  Review failing cases; expected failures at awgn_snr15/10 and neg_mp2tap_d33."
fi

echo ""
echo "Logs:"
echo "  Gate    : ${GATE_LOG}"
echo "  Summary : ${SUMMARY}"
echo "  Per-case: ${LOG_DIR}/<case>_sim.log"
echo "========================================================================"

grep -E "^CHANNEL_GATE: PASS$" "${GATE_LOG}" &>/dev/null && exit 0 || exit 1
