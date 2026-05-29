#!/usr/bin/env bash
# run_session_C_p3_14c_dma_replay_golden_compare.sh — P3-14C Full DMA Replay Golden Compare
#
# DUT: rtl/phase3_sync_axis_dma_wrapper.v  (P3-14B, with P3-14C debug ports)
# TB:  tb/session_C_p3_14c_dma_replay_golden_tb.sv
# Ref: scripts/compare_session_C_p3_14c_dma_replay_golden.py
#
# Gate rules:
#   SANITY_GATE: PASS — structural checks only (INT_CFO_APPLIED=1, OUTPUT_COUNT=576, TLAST)
#   OFFICIAL_GATE: PASS — sample-by-sample IQ comparison passes (Python model)
#
# Usage:
#   ./scripts/run_session_C_p3_14c_dma_replay_golden_compare.sh [--sim xsim|iverilog]
#
# Default: iverilog

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${SCRIPT_DIR}/.."

SIM_TOOL="iverilog"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --sim) SIM_TOOL="$2"; shift 2 ;;
        *)     echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

mkdir -p "${ROOT}/logs"
mkdir -p "${ROOT}/sim_out/session_C_p3_14c"

cd "${ROOT}"

echo "=== P3-14C Full DMA Replay Golden Compare ==="
echo "    Simulator: ${SIM_TOOL}"
echo ""

# --------------------------------------------------------------------------
# ROM stub check
# --------------------------------------------------------------------------
echo "=== [pre] Checking ROM stubs ==="
for f in "${ROOT}/vectors/meyr_pss_reference_romhex.txt" \
          "${ROOT}/vectors/meyr_sss_reference_romhex.txt"; do
    if [[ ! -f "$f" ]]; then
        echo "  WARNING: creating zero stub: $f"
        python3 -c "print('\n'.join(['00000000']*256))" > "$f"
    fi
done
echo "  ROM stubs OK"

# --------------------------------------------------------------------------
# Source file lists (same as P3-14B runner)
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

TB_SRC="${ROOT}/tb/session_C_p3_14c_dma_replay_golden_tb.sv"

ALL_SRCS=( "${LEGACY_SRCS[@]}" "${UNIT_TEST_SRCS[@]}" "${RTL_SRCS[@]}" )

# --------------------------------------------------------------------------
# Pre-flight checks
# --------------------------------------------------------------------------
echo "=== [pre] Checking source files ==="
MISSING=0
for f in "${ALL_SRCS[@]}" "${TB_SRC}"; do
    if [[ ! -f "$f" ]]; then
        echo "  MISSING: $f"
        MISSING=$((MISSING + 1))
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
echo "  All source files present"
echo "  Stimulus: golden/phase3_iq_stimulus.mem"

# --------------------------------------------------------------------------
# Step 1: Compile and simulate
# --------------------------------------------------------------------------
if [[ "${SIM_TOOL}" == "xsim" ]]; then
    echo "=== [1] xvlog ==="
    command -v xvlog &>/dev/null || { echo "BLOCKED_XSIM_UNAVAILABLE"; exit 1; }
    xvlog --nolog -sv "${ALL_SRCS[@]}" "${TB_SRC}"
    echo "=== [2] xelab ==="
    xelab --nolog -debug typical p3_14c_golden_tb \
          -snapshot p3_14c_golden_snap \
          --include "${ROOT}/vectors"
    echo "=== [3] xsim ==="
    xsim --nolog p3_14c_golden_snap \
         --runall \
         --log "${ROOT}/logs/p3_14c_golden_xsim.log"
    LOG="${ROOT}/logs/p3_14c_golden_xsim.log"
elif [[ "${SIM_TOOL}" == "iverilog" ]]; then
    echo "=== [1] iverilog: compile ==="
    command -v iverilog &>/dev/null || { echo "BLOCKED_IVERILOG_UNAVAILABLE" >&2; exit 1; }
    iverilog -g2012 \
             -I "${ROOT}/vectors" \
             -o "${ROOT}/sim_out/p3_14c_golden.vvp" \
             "${ALL_SRCS[@]}" \
             "${TB_SRC}"
    echo "  Compile: OK"
    echo "=== [2] vvp: simulate ==="
    vvp "${ROOT}/sim_out/p3_14c_golden.vvp" \
        2>&1 | tee "${ROOT}/logs/p3_14c_golden_iverilog.log"
    LOG="${ROOT}/logs/p3_14c_golden_iverilog.log"
else
    echo "ERROR: Unknown simulator '${SIM_TOOL}'." >&2; exit 1
fi

echo ""
echo "--- Simulation summary ---"
grep -E "PASS|FAIL|SANITY_GATE|ERROR|WDG" "${LOG}" || true
echo ""

# --------------------------------------------------------------------------
# Step 2: Run Python golden compare
# --------------------------------------------------------------------------
echo "=== [3] Python golden compare ==="
if ! command -v python3 &>/dev/null; then
    echo "ERROR: python3 not found in PATH." >&2; exit 1
fi

COMPARE_LOG="${ROOT}/logs/p3_14c_golden_compare.log"
python3 "${ROOT}/scripts/compare_session_C_p3_14c_dma_replay_golden.py" \
    2>&1 | tee "${COMPARE_LOG}"

echo ""
echo "--- Compare summary ---"
grep -E "PASS|FAIL|OFFICIAL_GATE|MISMATCH" "${COMPARE_LOG}" | head -20
echo ""

# --------------------------------------------------------------------------
# Step 3: Gate evaluation
# --------------------------------------------------------------------------
SIM_SANITY_PASS=0
SIM_OFFICIAL_PASS=0
PY_OFFICIAL_PASS=0

grep -qE "^SANITY_GATE: PASS$"   "${LOG}"          2>/dev/null && SIM_SANITY_PASS=1
grep -qE "^OFFICIAL_GATE: PASS$" "${COMPARE_LOG}"  2>/dev/null && PY_OFFICIAL_PASS=1

echo "=== RESULT ==="
if [[ ${PY_OFFICIAL_PASS} -eq 1 && ${SIM_SANITY_PASS} -eq 1 ]]; then
    echo "OFFICIAL_GATE: PASS"
    echo "  Sample-by-sample IQ comparison passed."
    echo "  Replay buffer + integer CFO correction numerically verified."
    exit 0
elif [[ ${SIM_SANITY_PASS} -eq 1 ]]; then
    echo "SANITY_GATE: PASS"
    echo "  Structural checks passed; Python IQ compare failed or not run."
    echo "  See: ${COMPARE_LOG}"
    exit 1
else
    echo "SANITY_GATE: FAIL"
    echo "  Structural checks did not pass."
    echo "  Sim log:     ${LOG}"
    echo "  Compare log: ${COMPARE_LOG}"
    exit 1
fi
