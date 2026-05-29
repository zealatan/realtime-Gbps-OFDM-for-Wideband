#!/usr/bin/env bash
# run_p3_14a_axi_dma_wrapper_smoke.sh — P3-14A AXI/DMA wrapper smoke test
#
# DUT: rtl/phase3_sync_axis_dma_wrapper.v
#      (wraps phase3_axi_lite_regs + phase3_sync_top)
# TB:  tb/phase3_axi_dma_wrapper_smoke_tb.sv
#
# Smoke checks (not full system validation):
#   1. Compile cleanly (all RTL + new wrapper files)
#   2. Simulate: reset, VERSION read, CONTROL write, AXIS handshake not X
#   3. Print SANITY_GATE: PASS on success
#
# Usage:
#   ./scripts/run_p3_14a_axi_dma_wrapper_smoke.sh [--sim xsim|iverilog]
#
# Default: iverilog (xsim preferred but typically unavailable on dev host)
#
# IMPORTANT: SANITY_GATE: PASS means compile/interface smoke only.
# Official system PASS requires xsim + full golden compare.
#
# Excluded from compile (same as run_phase3_sync_sim.sh exclusion policy):
#   rtl/unit_test/phase2_integer_cfo_estimator.v  (unit-test only)
#   rtl/fft256_xilinx_wrapper.v                   (Xilinx IP)
#   rtl/unit_test/cordic_atan2_xilinx_wrapper.v
#   rtl/unit_test/nco_phase_gen_xilinx_wrapper.v
#   rtl/phase2_sync_axis_dma_wrapper.v             (Phase2 wrapper)
#   rtl/phase2_streaming_sync_top.v                (Phase2 core)
#   rtl/phase2_axi_lite_regs.v                     (Phase2 regs — not needed in compile)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${SCRIPT_DIR}/.."

# --------------------------------------------------------------------------
# Argument parsing
# --------------------------------------------------------------------------
SIM_TOOL="iverilog"  # default: iverilog (xsim preferred if available)

while [[ $# -gt 0 ]]; do
    case "$1" in
        --sim) SIM_TOOL="$2"; shift 2 ;;
        *)     echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

# --------------------------------------------------------------------------
# Directory setup
# --------------------------------------------------------------------------
mkdir -p "${ROOT}/logs"
mkdir -p "${ROOT}/sim_out"

cd "${ROOT}"

echo "=== P3-14A AXI/DMA Wrapper Smoke Test ==="
echo "    Simulator: ${SIM_TOOL}"
echo ""

# --------------------------------------------------------------------------
# RTL source list
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
    "${ROOT}/rtl/timing_sync_top.v"
    "${ROOT}/rtl/frac_cfo_estimator.v"
    "${ROOT}/rtl/timing_frac_cfo_top.v"
    "${ROOT}/rtl/iq_frame_buffer.v"
    "${ROOT}/rtl/frac_cfo_corrector_top.v"
    "${ROOT}/rtl/fft256_dual_symbol_frontend.v"
    "${ROOT}/rtl/meyr_term2_ref_rom.v"
    "${ROOT}/rtl/meyr_integer_cfo_fft_frontend_top.v"
)

RTL_SRCS=(
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
    # P3-14A new files
    "${ROOT}/rtl/phase3_axi_lite_regs.v"
    "${ROOT}/rtl/phase3_sync_axis_dma_wrapper.v"
)

TB_SRC="${ROOT}/tb/phase3_axi_dma_wrapper_smoke_tb.sv"

ALL_SRCS=( "${LEGACY_SRCS[@]}" "${UNIT_TEST_SRCS[@]}" "${RTL_SRCS[@]}" )

# --------------------------------------------------------------------------
# Check that required stub ROM files exist (needed by meyr_integer_cfo_core)
# --------------------------------------------------------------------------
echo "=== [pre] Checking ROM stub files ==="
for f in "${ROOT}/vectors/meyr_pss_reference_romhex.txt" \
          "${ROOT}/vectors/meyr_sss_reference_romhex.txt"; do
    if [[ ! -f "$f" ]]; then
        echo "  WARNING: ROM stub missing: $f"
        echo "           Creating 256-line zero stub..."
        python3 -c "print('\n'.join(['00000000']*256))" > "$f"
    fi
done
echo "  ROM stubs OK"

# --------------------------------------------------------------------------
# Check source files exist
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
    echo "ERROR: $MISSING source file(s) missing. Cannot compile." >&2
    exit 1
fi
echo "  All source files present"

# --------------------------------------------------------------------------
# Compile and simulate
# --------------------------------------------------------------------------

if [[ "${SIM_TOOL}" == "xsim" ]]; then
    echo "=== [1] xvlog: compile Verilog ==="
    if ! command -v xvlog &>/dev/null; then
        echo "BLOCKED_XSIM_UNAVAILABLE: xvlog not found in PATH."
        echo "  Install Vivado and source settings64.sh, then re-run."
        echo "  Alternatively: run with --sim iverilog for sanity compile."
        exit 1
    fi

    xvlog --nolog -sv "${ALL_SRCS[@]}" "${TB_SRC}"

    echo "=== [2] xelab ==="
    xelab --nolog -debug typical \
          phase3_axi_dma_wrapper_smoke_tb \
          -snapshot p3_14a_smoke_snap \
          --include "${ROOT}/vectors"

    echo "=== [3] xsim ==="
    xsim --nolog p3_14a_smoke_snap \
         --runall \
         --log "${ROOT}/logs/p3_14a_smoke_xsim.log"

    echo ""
    echo "--- Smoke simulation log ---"
    grep -E "PASS|FAIL|SANITY_GATE|Check|ERROR" \
         "${ROOT}/logs/p3_14a_smoke_xsim.log" || true
    echo ""

elif [[ "${SIM_TOOL}" == "iverilog" ]]; then
    echo "=== [1] iverilog: compile ==="
    if ! command -v iverilog &>/dev/null; then
        echo "BLOCKED_IVERILOG_UNAVAILABLE: iverilog not found in PATH." >&2
        exit 1
    fi

    iverilog -g2012 \
             -I "${ROOT}/vectors" \
             -o "${ROOT}/sim_out/p3_14a_smoke.vvp" \
             "${ALL_SRCS[@]}" \
             "${TB_SRC}"

    echo "  Compile: OK"
    echo ""
    echo "=== [2] vvp: simulate ==="

    cd "${ROOT}"
    vvp "${ROOT}/sim_out/p3_14a_smoke.vvp" \
        2>&1 | tee "${ROOT}/logs/p3_14a_smoke_iverilog.log"

    echo ""
    echo "--- Smoke simulation summary ---"
    grep -E "PASS|FAIL|SANITY_GATE" \
         "${ROOT}/logs/p3_14a_smoke_iverilog.log" || true
    echo ""

else
    echo "ERROR: Unknown simulator '${SIM_TOOL}'. Use xsim or iverilog." >&2
    exit 1
fi

# --------------------------------------------------------------------------
# Check for SANITY_GATE: PASS in log
# --------------------------------------------------------------------------
LOG_FILE=""
if [[ "${SIM_TOOL}" == "xsim" ]];     then LOG_FILE="${ROOT}/logs/p3_14a_smoke_xsim.log"; fi
if [[ "${SIM_TOOL}" == "iverilog" ]]; then LOG_FILE="${ROOT}/logs/p3_14a_smoke_iverilog.log"; fi

if grep -q "SANITY_GATE: PASS" "${LOG_FILE}" 2>/dev/null; then
    echo "=== RESULT ==="
    echo "SANITY_GATE: PASS"
    echo ""
    echo "Note: This is a compile/interface smoke test only."
    echo "      Official system PASS requires xsim + full golden compare."
    exit 0
else
    echo "=== RESULT ==="
    echo "SANITY_GATE: FAIL  (SANITY_GATE: PASS not found in simulation log)"
    echo "See: ${LOG_FILE}"
    exit 1
fi
