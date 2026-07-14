#!/usr/bin/env bash
# run_p3_24a_cp_autocorr_restore.sh — P3-24A CP Autocorr Restore Regression
#
# DUT: phase3_sync_axis_dma_wrapper (full Phase 3 pipeline)
# TB:  tb/p3_24a_cp_autocorr_restore_tb.sv
#
# Verifies that timing_sync_top (streaming_cp_autocorr adapter) produces
# correct peak_lag≈23, slot_start≈64, and full pipeline output (576 beats).
#
# GATE OUTPUT (exactly one):
#   SANITY_CP_AUTOCORR_RESTORE_GATE: PASS   — all 8 checks pass
#   SANITY_CP_AUTOCORR_RESTORE_GATE: FAIL   — one or more checks fail
#   SANITY_CP_AUTOCORR_RESTORE_GATE: BLOCKED_* — pre-flight dependency missing
#
# USAGE:
#   bash scripts/run_p3_24a_cp_autocorr_restore.sh [OPTIONS]
#
#   Options:
#     --sim iverilog|xsim    simulator (default: iverilog)
#     --log-dir DIR          override log directory (default: sim_out/p3_24a)
#
# EXIT CODES:
#   0  SANITY_CP_AUTOCORR_RESTORE_GATE: PASS
#   1  any other gate outcome

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SIM_TOOL="iverilog"
LOG_DIR="${ROOT}/sim_out/p3_24a"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --sim)     shift; SIM_TOOL="$1" ;;
        --log-dir) shift; LOG_DIR="$1"  ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
    shift
done

mkdir -p "${LOG_DIR}"
GATE_LOG="${LOG_DIR}/p3_24a_gate.txt"
SIM_LOG="${LOG_DIR}/p3_24a_sim.log"

gate_out() {
    local msg="$1"
    echo ""
    echo "========================================================================"
    echo "${msg}"
    echo "========================================================================"
    echo "${msg}" > "${GATE_LOG}"
}

echo "========================================================================"
echo "P3-24A CP Autocorr Restore Regression"
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
        mkdir -p "$(dirname "$f")"
        echo "  creating zero stub: $(basename $f)"
        python3 -c "print('\n'.join(['00000000']*256))" > "$f"
    else
        echo "  [OK]   $(basename $f)"
    fi
done

# --------------------------------------------------------------------------
# All RTL sources from rtl/DUT/
# --------------------------------------------------------------------------
DUT_DIR="${ROOT}/rtl/DUT"

RTL_SRCS=(
    "${DUT_DIR}/complex_mult.v"
    "${DUT_DIR}/complex_rotator.v"
    "${DUT_DIR}/complex_to_mag.v"
    "${DUT_DIR}/delay_sample.v"
    "${DUT_DIR}/delayT.v"
    "${DUT_DIR}/fft256_dual_symbol_frontend.v"
    "${DUT_DIR}/fft256_xilinx_wrapper.v"
    "${DUT_DIR}/frac_cfo_corrector_top.v"
    "${DUT_DIR}/frac_cfo_estimator.v"
    "${DUT_DIR}/frac_cfo_frame_corrector_top.v"
    "${DUT_DIR}/frame_detect_fsm.v"
    "${DUT_DIR}/frame_detector.v"
    "${DUT_DIR}/iq_frame_buffer.v"
    "${DUT_DIR}/iq_replay_buffer_576.v"
    "${DUT_DIR}/meyr_integer_cfo_fft_frontend_top.v"
    "${DUT_DIR}/meyr_integer_cfo_freq_estimator_top.v"
    "${DUT_DIR}/moving_avg_optimized.v"
    "${DUT_DIR}/nco_phase_gen.v"
    "${DUT_DIR}/peak_detector.v"
    "${DUT_DIR}/phase3_axi_lite_regs.v"
    "${DUT_DIR}/phase3_sync_axis_dma_wrapper.v"
    "${DUT_DIR}/phase3_sync_top.v"
    "${DUT_DIR}/pss_sss_symbol_extractor.v"
    "${DUT_DIR}/ram_2port.v"
    "${DUT_DIR}/sample_power_sq.v"
    "${DUT_DIR}/sliding_window_sum.v"
    "${DUT_DIR}/slot_start_controller.v"
    "${DUT_DIR}/streaming_cp_autocorr.v"
    "${DUT_DIR}/timing_frac_cfo_top.v"
    "${DUT_DIR}/timing_metric_core.v"
    # New modules for P3-24A
    "${DUT_DIR}/timing_sync_top.v"
    "${DUT_DIR}/cordic_atan2.v"
    "${DUT_DIR}/complex_mult_iq.v"
    "${DUT_DIR}/meyr_pss_sss_product_gen.v"
    "${DUT_DIR}/meyr_integer_cfo_core.v"
)

TB_SRC="${ROOT}/tb/p3_24a_cp_autocorr_restore_tb.sv"

# --------------------------------------------------------------------------
# Pre-flight: required files
# --------------------------------------------------------------------------
echo ""
echo "--- Required files ---"
BLOCKED=0
for f in "${RTL_SRCS[@]}" "${TB_SRC}"; do
    if [[ ! -f "$f" ]]; then
        echo "  [MISS] $f"
        BLOCKED=1
    fi
done
if [[ ! -f "${ROOT}/golden/phase3_iq_stimulus.mem" ]]; then
    echo "  [MISS] golden/phase3_iq_stimulus.mem"
    echo "         Run: python3 scripts/gen_phase3_iq_stimulus.py"
    BLOCKED=1
else
    echo "  [OK]   golden/phase3_iq_stimulus.mem"
fi
if [[ "${BLOCKED}" -eq 1 ]]; then
    gate_out "SANITY_CP_AUTOCORR_RESTORE_GATE: BLOCKED_MISSING_FILES"
    exit 1
fi
echo "  All source files present."

# --------------------------------------------------------------------------
# Run simulation
# --------------------------------------------------------------------------
echo ""

if [[ "${SIM_TOOL}" == "xsim" ]]; then
    if ! command -v xvlog &>/dev/null; then
        gate_out "SANITY_CP_AUTOCORR_RESTORE_GATE: BLOCKED_XSIM_UNAVAILABLE"
        echo "  xvlog not found in PATH."
        exit 1
    fi

    echo "=== [1] xvlog ==="
    xvlog --nolog -sv "${RTL_SRCS[@]}" "${TB_SRC}" 2>&1 | tee "${LOG_DIR}/p3_24a_xvlog.log"
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        gate_out "SANITY_CP_AUTOCORR_RESTORE_GATE: BLOCKED_COMPILE_ERROR"
        exit 1
    fi

    echo "=== [2] xelab ==="
    xelab --nolog -debug typical \
          p3_24a_cp_autocorr_restore_tb \
          -snapshot p3_24a_snap \
          2>&1 | tee "${LOG_DIR}/p3_24a_xelab.log"
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        gate_out "SANITY_CP_AUTOCORR_RESTORE_GATE: BLOCKED_COMPILE_ERROR"
        exit 1
    fi

    echo "=== [3] xsim ==="
    xsim --nolog p3_24a_snap \
         --runall \
         --log "${SIM_LOG}" \
         2>&1 | tee "${LOG_DIR}/p3_24a_xsim_console.log"

elif [[ "${SIM_TOOL}" == "iverilog" ]]; then
    if ! command -v iverilog &>/dev/null; then
        gate_out "SANITY_CP_AUTOCORR_RESTORE_GATE: BLOCKED_IVERILOG_UNAVAILABLE"
        echo "  iverilog not found in PATH."
        exit 1
    fi

    VVP="${LOG_DIR}/p3_24a.vvp"

    echo "=== [1] iverilog: compile ==="
    iverilog -g2012 \
             -o "${VVP}" \
             "${RTL_SRCS[@]}" \
             "${TB_SRC}" \
             2>&1 | tee "${LOG_DIR}/p3_24a_compile.log"
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        gate_out "SANITY_CP_AUTOCORR_RESTORE_GATE: BLOCKED_COMPILE_ERROR"
        exit 1
    fi
    echo "  Compile OK: ${VVP}"

    echo ""
    echo "=== [2] vvp: simulate ==="
    vvp "${VVP}" 2>&1 | tee "${SIM_LOG}"

else
    echo "ERROR: Unknown simulator '${SIM_TOOL}'." >&2
    gate_out "SANITY_CP_AUTOCORR_RESTORE_GATE: BLOCKED_UNKNOWN_SIM"
    exit 1
fi

# --------------------------------------------------------------------------
# Gate evaluation
# --------------------------------------------------------------------------
echo ""
echo "--- Gate evaluation ---"

if grep -qE "^SANITY_CP_AUTOCORR_RESTORE_GATE: PASS$" "${SIM_LOG}" 2>/dev/null; then
    gate_out "SANITY_CP_AUTOCORR_RESTORE_GATE: PASS"
    echo "  All 8 regression checks passed."
    echo ""
    grep -E "^  C[0-9]" "${SIM_LOG}" 2>/dev/null || true
    exit 0
elif grep -qE "^SANITY_CP_AUTOCORR_RESTORE_GATE: FAIL$" "${SIM_LOG}" 2>/dev/null; then
    gate_out "SANITY_CP_AUTOCORR_RESTORE_GATE: FAIL"
    grep -E "^  (C[0-9]|REASON)" "${SIM_LOG}" 2>/dev/null | head -20 || true
    exit 1
elif grep -qE "^WDG: TIMEOUT" "${SIM_LOG}" 2>/dev/null; then
    gate_out "SANITY_CP_AUTOCORR_RESTORE_GATE: FAIL"
    echo "  Simulation timed out (watchdog 200000 cycles)."
    grep -E "^WDG:" "${SIM_LOG}" | head -5 || true
    exit 1
else
    gate_out "SANITY_CP_AUTOCORR_RESTORE_GATE: FAIL"
    echo "  No gate line found in simulation log."
    echo "  See: ${SIM_LOG}"
    exit 1
fi

echo ""
echo "========================================================================"
echo "Logs:"
echo "  Gate : ${GATE_LOG}"
echo "  Sim  : ${SIM_LOG}"
echo "========================================================================"
