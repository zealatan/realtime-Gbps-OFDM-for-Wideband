#!/usr/bin/env bash
# run_session_E_p3_16a_full_end_to_end_phase3.sh — P3-16A Full End-to-End Phase3 Regression
#
# DUT: phase3_sync_axis_dma_wrapper (P3-14B RTL)
# TB:  tb/session_E_p3_16a_full_end_to_end_phase3_tb.sv
#
# Exercises the complete Phase3 pipeline in a single simulation:
#   frame_detector → frac_cfo_corrector → pss_sss_symbol_extractor
#   → meyr_integer_cfo (FFT + core) → replay buffer → integer NCO/rotator
#   → M_AXIS DMA output
#
# GATE OUTPUTS (exactly one emitted):
#   INTEGRATION_GATE: PASS         — all 8 checks pass
#   INTEGRATION_GATE: PARTIAL_PASS — C1-C4 pass (frame+Meyr OK), C5-C8 fail
#   INTEGRATION_GATE: FAIL         — frame not detected or catastrophic failure
#   INTEGRATION_GATE: BLOCKED_*    — pre-flight dependency missing
#
# Checks:
#   C1  frame_found          latch_frame_found == 1
#   C2  frame_index          ∈ [40, 42]  (golden=41, ±1)
#   C3  frac_cfo_valid       fractional CFO pipeline complete
#   C4  int_cfo_valid        Meyr FFT + estimator complete (implies FFT done)
#   C5  int_cfo_applied      AXI reg 0x44 == 1 (replay started)
#   C6  output_count         AXI reg 0x14 == 576
#   C7  tlast_at_575         TLAST fires at M_AXIS beat 575
#   C8  m_axis_continuity    max idle gap < 8 cycles during replay
#
# FFT NOTE:
#   phase3_sync_top uses fft256_dual_symbol_frontend (time-domain bypass).
#   For k_int=0 stimulus this is numerically correct (int_cfo=0 expected).
#   Non-zero k_int validation requires the Xilinx FFT IP path (P3-13B/C).
#
# USAGE:
#   bash scripts/run_session_E_p3_16a_full_end_to_end_phase3.sh [OPTIONS]
#
#   Options:
#     --sim iverilog|xsim    simulator (default: iverilog)
#     --log-dir DIR          override log directory (default: sim_out/session_E_p3_16a)
#
# EXIT CODES:
#   0  INTEGRATION_GATE: PASS
#   1  INTEGRATION_GATE: PARTIAL_PASS, FAIL, or BLOCKED_*

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SIM_TOOL="iverilog"
LOG_DIR="${ROOT}/sim_out/session_E_p3_16a"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --sim)     shift; SIM_TOOL="$1" ;;
        --log-dir) shift; LOG_DIR="$1"  ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
    shift
done

mkdir -p "${LOG_DIR}"
GATE_LOG="${LOG_DIR}/p3_16a_gate.txt"
SIM_LOG="${LOG_DIR}/p3_16a_sim.log"

gate_out() {
    local msg="$1"
    echo ""
    echo "========================================================================"
    echo "${msg}"
    echo "========================================================================"
    echo "${msg}" > "${GATE_LOG}"
}

echo "========================================================================"
echo "P3-16A Full End-to-End Phase3 Integrated Regression"
echo "  Date       : $(date '+%Y-%m-%d %H:%M:%S')"
echo "  Simulator  : ${SIM_TOOL}"
echo "  Log dir    : ${LOG_DIR}"
echo "  Root       : ${ROOT}"
echo "========================================================================"

# --------------------------------------------------------------------------
# ROM stubs (zero-filled if not generated) — needed by meyr_integer_cfo_core
# --------------------------------------------------------------------------
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

# --------------------------------------------------------------------------
# Source file lists (same as Session C / P3-14C runner)
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

TB_SRC="${ROOT}/tb/session_E_p3_16a_full_end_to_end_phase3_tb.sv"

ALL_SRCS=( "${LEGACY_SRCS[@]}" "${UNIT_TEST_SRCS[@]}" "${RTL_SRCS[@]}" )

# --------------------------------------------------------------------------
# Pre-flight: required files
# --------------------------------------------------------------------------
echo ""
echo "--- Required files ---"
BLOCKED=0
for f in "${ALL_SRCS[@]}" "${TB_SRC}"; do
    if [[ ! -f "$f" ]]; then
        echo "  [MISS] $f"
        BLOCKED=1
    fi
done
if [[ -f "${ROOT}/golden/phase3_iq_stimulus.mem" ]]; then
    echo "  [OK]   golden/phase3_iq_stimulus.mem"
else
    echo "  [MISS] golden/phase3_iq_stimulus.mem"
    echo "         Run: python3 scripts/gen_phase3_iq_stimulus.py"
    BLOCKED=1
fi
if [[ "${BLOCKED}" -eq 1 ]]; then
    gate_out "INTEGRATION_GATE: BLOCKED_MISSING_FILES"
    exit 1
fi
echo "  All source files present."

# --------------------------------------------------------------------------
# Run simulation
# --------------------------------------------------------------------------
echo ""

if [[ "${SIM_TOOL}" == "xsim" ]]; then
    if ! command -v xvlog &>/dev/null; then
        gate_out "INTEGRATION_GATE: BLOCKED_XSIM_UNAVAILABLE"
        echo "  xvlog not found in PATH.  Install Vivado and source settings64.sh."
        exit 1
    fi

    echo "=== [1] xvlog ==="
    xvlog --nolog -sv "${ALL_SRCS[@]}" "${TB_SRC}" 2>&1 | tee "${LOG_DIR}/p3_16a_xvlog.log"
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        gate_out "INTEGRATION_GATE: BLOCKED_COMPILE_ERROR"
        exit 1
    fi

    echo "=== [2] xelab ==="
    xelab --nolog -debug typical \
          session_E_p3_16a_full_end_to_end_phase3_tb \
          -snapshot p3_16a_snap \
          2>&1 | tee "${LOG_DIR}/p3_16a_xelab.log"
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        gate_out "INTEGRATION_GATE: BLOCKED_COMPILE_ERROR"
        exit 1
    fi

    echo "=== [3] xsim ==="
    xsim --nolog p3_16a_snap \
         --runall \
         --log "${SIM_LOG}" \
         2>&1 | tee "${LOG_DIR}/p3_16a_xsim_console.log"

elif [[ "${SIM_TOOL}" == "iverilog" ]]; then
    if ! command -v iverilog &>/dev/null; then
        gate_out "INTEGRATION_GATE: BLOCKED_IVERILOG_UNAVAILABLE"
        echo "  iverilog not found in PATH."
        exit 1
    fi

    VVP="${LOG_DIR}/p3_16a.vvp"

    echo "=== [1] iverilog: compile ==="
    iverilog -g2012 \
             -o "${VVP}" \
             "${ALL_SRCS[@]}" \
             "${TB_SRC}" \
             2>&1 | tee "${LOG_DIR}/p3_16a_compile.log"
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        gate_out "INTEGRATION_GATE: BLOCKED_COMPILE_ERROR"
        exit 1
    fi
    echo "  Compile OK: ${VVP}"

    echo ""
    echo "=== [2] vvp: simulate ==="
    vvp "${VVP}" 2>&1 | tee "${SIM_LOG}"

else
    echo "ERROR: Unknown simulator '${SIM_TOOL}'." >&2
    gate_out "INTEGRATION_GATE: BLOCKED_UNKNOWN_SIM"
    exit 1
fi

# --------------------------------------------------------------------------
# Gate evaluation from simulation log
# --------------------------------------------------------------------------
echo ""
echo "--- Gate evaluation ---"

if grep -qE "^INTEGRATION_GATE: PASS$" "${SIM_LOG}" 2>/dev/null; then
    gate_out "INTEGRATION_GATE: PASS"
    echo "  All 8 regression checks passed."
    echo ""
    grep -E "^  C[0-9]" "${SIM_LOG}" 2>/dev/null || true
    exit 0

elif grep -qE "^INTEGRATION_GATE: PARTIAL_PASS$" "${SIM_LOG}" 2>/dev/null; then
    gate_out "INTEGRATION_GATE: PARTIAL_PASS"
    echo "  Frame detection and Meyr pipeline passed (C1-C4)."
    echo "  Replay/M_AXIS issues detected (C5-C8 not all passing)."
    echo ""
    grep -E "^  (C[0-9]|REASON)" "${SIM_LOG}" 2>/dev/null | head -20 || true
    exit 1

elif grep -qE "^INTEGRATION_GATE: FAIL$" "${SIM_LOG}" 2>/dev/null; then
    gate_out "INTEGRATION_GATE: FAIL"
    grep -E "^  REASON:" "${SIM_LOG}" 2>/dev/null | head -10 || true
    exit 1

elif grep -qE "^WDG: TIMEOUT" "${SIM_LOG}" 2>/dev/null; then
    gate_out "INTEGRATION_GATE: FAIL"
    echo "  Simulation timed out (watchdog 200000 cycles)."
    grep -E "^WDG:" "${SIM_LOG}" | head -5 || true
    exit 1

else
    gate_out "INTEGRATION_GATE: FAIL"
    echo "  No INTEGRATION_GATE line found in simulation log."
    echo "  See: ${SIM_LOG}"
    exit 1
fi

echo ""
echo "========================================================================"
echo "Logs:"
echo "  Gate : ${GATE_LOG}"
echo "  Sim  : ${SIM_LOG}"
echo "========================================================================"
