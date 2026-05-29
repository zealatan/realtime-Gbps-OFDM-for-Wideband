#!/usr/bin/env bash
# run_session_C4_p3_20b_axi_soak.sh — P3-20B AXI Soak Test
#
# DUT: phase3_sync_axis_dma_wrapper
# TB:  tb/session_C4_p3_20b_axi_soak_tb.sv
# CHK: tb/common/axi_stream_checker.sv
#
# Phases:
#   B1   100 frames, no backpressure
#   B2   1000 frames, no backpressure
#   B3   100 frames × 10% / 25% / 50% M_AXIS stall
#   B4   Replay restart soak (replay_done count vs frame count)
#   B5   Counter stability (output_count never decreases)
#   CHK  AXI-S assertion checker A1-A5
#
# Gate:
#   AXI_SOAK_GATE: PASS  — all phases pass
#   AXI_SOAK_GATE: FAIL  — any failure
#
# USAGE:
#   bash scripts/run_session_C4_p3_20b_axi_soak.sh [OPTIONS]
#
#   --sim iverilog|xsim   simulator (default: iverilog)
#   --log-dir DIR         log directory (default: sim_out/session_C4_p3_20b)
#
# EXIT CODES:
#   0  AXI_SOAK_GATE: PASS
#   1  AXI_SOAK_GATE: FAIL or BLOCKED_*

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SIM_TOOL="iverilog"
LOG_DIR="${ROOT}/sim_out/session_C4_p3_20b"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --sim)     shift; SIM_TOOL="$1" ;;
        --log-dir) shift; LOG_DIR="$1"  ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
    shift
done

mkdir -p "${LOG_DIR}"

GATE_LOG="${LOG_DIR}/p3_20b_axi_soak_gate.txt"
SIM_LOG="${LOG_DIR}/p3_20b_axi_soak_sim.log"
COMPILE_LOG="${LOG_DIR}/p3_20b_compile.log"
VVP_FILE="${LOG_DIR}/p3_20b_axi_soak.vvp"

gate_out() {
    local msg="$1"
    echo ""
    echo "========================================================================"
    echo "${msg}"
    echo "========================================================================"
    echo "${msg}" > "${GATE_LOG}"
}

echo "========================================================================"
echo "P3-20B AXI Soak Test"
echo "  Date      : $(date '+%Y-%m-%d %H:%M:%S')"
echo "  Simulator : ${SIM_TOOL}"
echo "  Log dir   : ${LOG_DIR}"
echo "========================================================================"

# --------------------------------------------------------------------------
# Prerequisites
# --------------------------------------------------------------------------
GOLDEN="${ROOT}/golden/phase3_iq_stimulus.mem"
if [[ ! -f "${GOLDEN}" ]]; then
    gate_out "AXI_SOAK_GATE: BLOCKED_MISSING_GOLDEN"
    echo "  Run: python3 scripts/gen_phase3_iq_stimulus.py"
    exit 1
fi

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
# Source lists (identical to Session C3)
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
CHK_SRC="${ROOT}/tb/common/axi_stream_checker.sv"
TB_SRC="${ROOT}/tb/session_C4_p3_20b_axi_soak_tb.sv"
ALL_SRCS=( "${LEGACY_SRCS[@]}" "${UNIT_TEST_SRCS[@]}" "${RTL_SRCS[@]}" )

# --------------------------------------------------------------------------
# Pre-flight
# --------------------------------------------------------------------------
echo ""
echo "--- Pre-flight ---"
BLOCKED=0
for f in "${ALL_SRCS[@]}" "${CHK_SRC}" "${TB_SRC}"; do
    [[ ! -f "$f" ]] && { echo "  [MISS] $f"; BLOCKED=1; }
done
[[ "${BLOCKED}" -eq 1 ]] && { gate_out "AXI_SOAK_GATE: BLOCKED_MISSING_FILES"; exit 1; }
echo "  All source files present."

if [[ "${SIM_TOOL}" == "iverilog" ]]; then
    command -v iverilog &>/dev/null || { gate_out "AXI_SOAK_GATE: BLOCKED_IVERILOG_UNAVAILABLE"; exit 1; }
elif [[ "${SIM_TOOL}" == "xsim" ]]; then
    command -v xvlog   &>/dev/null || { gate_out "AXI_SOAK_GATE: BLOCKED_XSIM_UNAVAILABLE";    exit 1; }
else
    gate_out "AXI_SOAK_GATE: BLOCKED_UNKNOWN_SIM"; exit 1
fi

# --------------------------------------------------------------------------
# Compile
# --------------------------------------------------------------------------
echo ""
echo "--- Compiling ---"

if [[ "${SIM_TOOL}" == "iverilog" ]]; then
    iverilog -g2012 \
             "${ALL_SRCS[@]}" \
             "${CHK_SRC}" \
             "${TB_SRC}" \
             -o "${VVP_FILE}" \
             2> "${COMPILE_LOG}"
    if [[ $? -ne 0 ]]; then
        echo "  Compile FAILED (see ${COMPILE_LOG}):"
        head -20 "${COMPILE_LOG}" >&2
        gate_out "AXI_SOAK_GATE: BLOCKED_COMPILE_FAILED"
        exit 1
    fi
    echo "  Compile OK → ${VVP_FILE}"
fi

# --------------------------------------------------------------------------
# Simulate
# --------------------------------------------------------------------------
echo ""
echo "--- Simulating (B1:100 + B2:1000 + B3:300 frames, watchdog: 220M cycles) ---"
echo "    (B2 takes ~103M cycles — expect ~30-60s on typical hardware)"

if [[ "${SIM_TOOL}" == "iverilog" ]]; then
    (cd "${ROOT}" && vvp "${VVP_FILE}") | tee "${SIM_LOG}"
fi

echo ""

# --------------------------------------------------------------------------
# Parse gate
# --------------------------------------------------------------------------
GATE_RESULT=$(grep -oP "^AXI_SOAK_GATE: \K(PASS|FAIL)$" "${SIM_LOG}" | tail -1)

if [[ -z "${GATE_RESULT}" ]]; then
    gate_out "AXI_SOAK_GATE: FAIL"
    echo "  No gate line found in simulation log."
    exit 1
fi

B1=$(grep "^B1_GATE:"  "${SIM_LOG}" | tail -1 || echo "B1_GATE missing")
B2=$(grep "^B2_GATE:"  "${SIM_LOG}" | tail -1 || echo "B2_GATE missing")
B3=$(grep "^B3_GATE:"  "${SIM_LOG}" | tail -1 || echo "B3_GATE missing")
B4=$(grep "^B4_GATE:"  "${SIM_LOG}" | tail -1 || echo "B4_GATE missing")
B5=$(grep "^B5_GATE:"  "${SIM_LOG}" | tail -1 || echo "B5_GATE missing")
CK=$(grep "^CHK_GATE:" "${SIM_LOG}" | tail -1 || echo "CHK_GATE missing")

echo "========================================================================"
echo "Phase results:"
echo "  ${B1}"
echo "  ${B2}"
echo "  ${B3}"
echo "  ${B4}"
echo "  ${B5}"
echo "  ${CK}"
echo ""
gate_out "AXI_SOAK_GATE: ${GATE_RESULT}"

echo ""
echo "Logs:  gate=${GATE_LOG}  sim=${SIM_LOG}  compile=${COMPILE_LOG}"
echo "========================================================================"

[[ "${GATE_RESULT}" == "PASS" ]] && exit 0 || exit 1
