#!/usr/bin/env bash
# run_session_C2_p3_14d_replay_hardening.sh — P3-14D Replay Correction Hardening
#
# DUT: phase3_sync_axis_dma_wrapper (same RTL as Sessions E and K)
# TB:  tb/session_C2_p3_14d_replay_hardening_tb.sv
#
# Single simulation covers four phases:
#   C2-1  Replay backpressure (5/3 tready pattern, max burst=3 < STALL_TIMEOUT=254)
#   C2-2  Integer CFO sweep (13 step_words: k_int 0 +-1 +-2 +-4 +-8 +-12 +-16)
#   C2-3  4 consecutive frames without reset (auto-rearm via replay_done)
#   C2-4  Rotator stability (phase continuity + phase reset)
#
# Gate:
#   REPLAY_HARDENING_GATE: PASS  — all four phases pass
#   REPLAY_HARDENING_GATE: FAIL  — any phase fails
#
# USAGE:
#   bash scripts/run_session_C2_p3_14d_replay_hardening.sh [OPTIONS]
#
#   --sim iverilog|xsim    simulator (default: iverilog)
#   --log-dir DIR          log directory (default: sim_out/session_C2_p3_14d)
#
# EXIT CODES:
#   0  REPLAY_HARDENING_GATE: PASS
#   1  REPLAY_HARDENING_GATE: FAIL or BLOCKED_*

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SIM_TOOL="iverilog"
LOG_DIR="${ROOT}/sim_out/session_C2_p3_14d"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --sim)     shift; SIM_TOOL="$1" ;;
        --log-dir) shift; LOG_DIR="$1"  ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
    shift
done

mkdir -p "${LOG_DIR}"

GATE_LOG="${LOG_DIR}/p3_14d_replay_gate.txt"
SIM_LOG="${LOG_DIR}/p3_14d_replay_sim.log"

gate_out() {
    local msg="$1"
    echo ""
    echo "========================================================================"
    echo "${msg}"
    echo "========================================================================"
    echo "${msg}" > "${GATE_LOG}"
}

echo "========================================================================"
echo "P3-14D Replay Correction Hardening"
echo "  Date      : $(date '+%Y-%m-%d %H:%M:%S')"
echo "  Simulator : ${SIM_TOOL}"
echo "  Log dir   : ${LOG_DIR}"
echo "  Root      : ${ROOT}"
echo "========================================================================"

# --------------------------------------------------------------------------
# Prerequisite: golden stimulus
# --------------------------------------------------------------------------
GOLDEN="${ROOT}/golden/phase3_iq_stimulus.mem"
if [[ ! -f "${GOLDEN}" ]]; then
    gate_out "REPLAY_HARDENING_GATE: BLOCKED_MISSING_GOLDEN"
    echo "  golden/phase3_iq_stimulus.mem not found."
    echo "  Run: python3 scripts/gen_phase3_iq_stimulus.py"
    exit 1
fi
echo ""
echo "--- Stimulus: ${GOLDEN} ---"

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
# Source file lists (identical to Session E/K runners)
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

TB_SRC="${ROOT}/tb/session_C2_p3_14d_replay_hardening_tb.sv"
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
    gate_out "REPLAY_HARDENING_GATE: BLOCKED_MISSING_FILES"
    exit 1
fi
echo "  All source files present."

# --------------------------------------------------------------------------
# Simulator availability check
# --------------------------------------------------------------------------
if [[ "${SIM_TOOL}" == "iverilog" ]]; then
    if ! command -v iverilog &>/dev/null; then
        gate_out "REPLAY_HARDENING_GATE: BLOCKED_IVERILOG_UNAVAILABLE"
        exit 1
    fi
elif [[ "${SIM_TOOL}" == "xsim" ]]; then
    if ! command -v xvlog &>/dev/null; then
        gate_out "REPLAY_HARDENING_GATE: BLOCKED_XSIM_UNAVAILABLE"
        exit 1
    fi
else
    gate_out "REPLAY_HARDENING_GATE: BLOCKED_UNKNOWN_SIM"
    exit 1
fi

# --------------------------------------------------------------------------
# Compile
# --------------------------------------------------------------------------
echo ""
echo "--- Compiling ---"
VVP_FILE="${LOG_DIR}/p3_14d_replay.vvp"
COMPILE_LOG="${LOG_DIR}/p3_14d_compile.log"

if [[ "${SIM_TOOL}" == "iverilog" ]]; then
    iverilog -g2012 \
             "${ALL_SRCS[@]}" \
             "${TB_SRC}" \
             -o "${VVP_FILE}" \
             2> "${COMPILE_LOG}"
    compile_rc=$?
    if [[ ${compile_rc} -ne 0 ]]; then
        echo "  Compile FAILED (see ${COMPILE_LOG}):"
        head -20 "${COMPILE_LOG}" >&2
        gate_out "REPLAY_HARDENING_GATE: BLOCKED_COMPILE_FAILED"
        exit 1
    fi
    echo "  Compile OK → ${VVP_FILE}"
fi

# --------------------------------------------------------------------------
# Simulate
# --------------------------------------------------------------------------
echo ""
echo "--- Simulating (watchdog: 3M cycles) ---"

if [[ "${SIM_TOOL}" == "iverilog" ]]; then
    (cd "${ROOT}" && vvp "${VVP_FILE}") | tee "${SIM_LOG}"
fi

echo ""

# --------------------------------------------------------------------------
# Parse gate result
# --------------------------------------------------------------------------
GATE_RESULT=$(grep -oP "^REPLAY_HARDENING_GATE: \K(PASS|FAIL)$" "${SIM_LOG}" | tail -1)

if [[ -z "${GATE_RESULT}" ]]; then
    gate_out "REPLAY_HARDENING_GATE: FAIL"
    echo "  No gate line found in simulation output."
    exit 1
fi

# Extract per-phase results for summary
C21=$(grep "^C21_RESULT" "${SIM_LOG}" | tail -1 || echo "C21_RESULT missing")
C22=$(grep "^C22_RESULT" "${SIM_LOG}" | tail -1 || echo "C22_RESULT missing")
C23=$(grep "^C23_RESULT" "${SIM_LOG}" | tail -1 || echo "C23_RESULT missing")
C24=$(grep "^C24_RESULT" "${SIM_LOG}" | tail -1 || echo "C24_RESULT missing")

echo "========================================================================"
echo "Phase results:"
echo "  ${C21}"
echo "  ${C22}"
echo "  ${C23}"
echo "  ${C24}"
echo ""
gate_out "REPLAY_HARDENING_GATE: ${GATE_RESULT}"

echo ""
echo "Logs:"
echo "  Gate    : ${GATE_LOG}"
echo "  Sim log : ${SIM_LOG}"
echo "  Compile : ${COMPILE_LOG}"
echo "========================================================================"

if [[ "${GATE_RESULT}" == "PASS" ]]; then
    exit 0
else
    exit 1
fi
