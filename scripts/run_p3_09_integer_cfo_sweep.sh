#!/usr/bin/env bash
# run_p3_09_integer_cfo_sweep.sh — P3-09 integer CFO sweep runner
#
# Usage:
#   bash scripts/run_p3_09_integer_cfo_sweep.sh [--sim xsim|iverilog]
#
# IMPORTANT: xsim (Vivado) is the OFFICIAL CI simulator.
#   --sim iverilog  is available as a quick local sanity check ONLY.
#   iverilog results are NOT official CI sign-off.
#
# NOTE: This sweep is currently BLOCKED by Guard 2 (bypass FFT stub active).
#   The FFT backend must be replaced before k_int≠0 cases can be validated.
#   See docs/p3_09x_phase3_audit_report.md for the unblock path.
#
# Behaviour:
#   1. Guard: verify P3-08 baseline (k_int=0) passed.
#      If not, exit with BLOCKED message — no fake PASS.
#   2. Guard: verify real FFT backend is present.
#      If bypass FFT stub is still active, exit with BLOCKED message.
#      (k_int=0 works with bypass, but k_int≠0 cannot give correct results.)
#   3. Generate sweep stimulus vectors (if not already present).
#   4. Run simulation for each k_int case, capture RTL results.
#   5. Run compare_p3_09_integer_cfo_sweep.py and print summary.
#
# DO NOT MODIFY RTL files.
# DO NOT remove BLOCKED guards to force a fake PASS.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

SIM="xsim"
while [[ $# -gt 0 ]]; do
    case $1 in
        --sim) SIM="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

SWEEP_DIR="golden/p3_09_sweep"
SIM_OUT_DIR="sim_out/p3_09_sweep"
MANIFEST="$SWEEP_DIR/manifest.json"
FFT_SRC="rtl/unit_test/fft256_dual_symbol_frontend.v"

echo "=========================================="
echo "P3-09 Integer CFO Sweep Runner"
echo "  Simulator  : $SIM"
echo "  Date       : $(date '+%Y-%m-%d %H:%M')"
echo "=========================================="

# ---------------------------------------------------------------------------
# GUARD 1: P3-08 baseline validated
# ---------------------------------------------------------------------------
echo ""
echo "--- Guard 1: P3-08 baseline ---"

P3_08_SENTINEL="golden/meyr_reference_debug.json"
if [[ ! -f "$P3_08_SENTINEL" ]]; then
    echo ""
    echo "  BLOCKED: P3-08 Meyr backend not yet validated."
    echo "  Missing: $P3_08_SENTINEL"
    echo ""
    echo "  Action required:"
    echo "    1. Complete P3-08 (run scripts/run_p3_08_meyr_backend.sh)"
    echo "    2. Verify CI_GATE PASS for k_int=0 (meyr_peak_index=255, integer_cfo_word=0)"
    echo "    3. Re-run this script."
    echo ""
    exit 1
fi
echo "  [OK] P3-08 sentinel found: $P3_08_SENTINEL"

# ---------------------------------------------------------------------------
# GUARD 2: Real FFT backend must be present
# ---------------------------------------------------------------------------
echo ""
echo "--- Guard 2: FFT backend check ---"

if [[ ! -f "$FFT_SRC" ]]; then
    echo "  [WARN] Cannot locate $FFT_SRC to check bypass status."
else
    if grep -q "FFT PLACEHOLDER" "$FFT_SRC"; then
        echo ""
        echo "  BLOCKED: fft256_dual_symbol_frontend.v is still the bypass stub."
        echo "  (Found string 'FFT PLACEHOLDER' in $FFT_SRC)"
        echo ""
        echo "  Reason: With bypass FFT, integer CFO phase cancels in the"
        echo "  PSS_td × conj(SSS_td) cross-product.  All k_int cases will"
        echo "  produce peak_index=255 and int_cfo=0 regardless of the actual"
        echo "  CFO offset.  Running the sweep now would produce FAIL for k_int≠0,"
        echo "  and PASS for k_int=0 only (already validated in P3-08)."
        echo ""
        echo "  Action required:"
        echo "    1. Replace S_COMPUTE in fft256_dual_symbol_frontend.v with"
        echo "       a real 256-point FFT (e.g. meyr_fft256_actual_integration_top.v)."
        echo "    2. Regenerate reference ROMs using frequency-domain PSS/SSS"
        echo "       cross-products (DFT of reference sequences)."
        echo "    3. Re-run this script."
        echo ""
        exit 1
    fi
fi
echo "  [OK] FFT backend appears to be non-stub (no 'FFT PLACEHOLDER' marker found)."

# ---------------------------------------------------------------------------
# STEP 1: Generate sweep vectors (idempotent)
# ---------------------------------------------------------------------------
echo ""
echo "--- Step 1: Generate sweep vectors ---"

if [[ -f "$MANIFEST" ]]; then
    echo "  [SKIP] Manifest already exists: $MANIFEST"
    echo "         Delete $SWEEP_DIR/ and rerun to regenerate."
else
    python3 scripts/gen_phase3_integer_cfo_sweep_vectors.py
fi

# ---------------------------------------------------------------------------
# STEP 2: Run simulation for each case
# ---------------------------------------------------------------------------
echo ""
echo "--- Step 2: Simulate all sweep cases ---"
mkdir -p "$SIM_OUT_DIR"
mkdir -p "logs"

# Source list (matches run_phase3_sync_sim.sh exactly)
# Each case links its per-case stimulus to the canonical TB path.
# The TB reads: golden/phase3_iq_stimulus_q15.hex

LEGACY_SRCS=(
    "rtl/phase2_legacy/complex_mult.v"
    "rtl/phase2_legacy/complex_to_mag.v"
    "rtl/phase2_legacy/delay_sample.v"
    "rtl/phase2_legacy/delayT.v"
    "rtl/phase2_legacy/moving_avg_optimized.v"
    "rtl/phase2_legacy/ram_2port.v"
)

UNIT_TEST_SRCS=(
    "rtl/unit_test/and2.v"
    "rtl/unit_test/cp_autocorr_core.v"
    "rtl/unit_test/timing_metric_core.v"
    "rtl/timing_sync_top.v"
    "rtl/frac_cfo_estimator.v"
    "rtl/timing_frac_cfo_top.v"
    "rtl/iq_frame_buffer.v"
    "rtl/frac_cfo_corrector_top.v"
    "rtl/fft256_dual_symbol_frontend.v"
    "rtl/meyr_term2_ref_rom.v"
    "rtl/meyr_integer_cfo_fft_frontend_top.v"
)

RTL_SRCS=(
    "rtl/axis_complex_mult.v"
    "rtl/complex_mult_iq.v"
    "rtl/complex_rotator.v"
    "rtl/cordic_atan2.v"
    "rtl/nco_phase_gen.v"
    "rtl/peak_detector.v"
    "rtl/meyr_integer_cfo_core.v"
    "rtl/meyr_pss_sss_product_gen.v"
    "rtl/meyr_integer_cfo_freq_estimator_top.v"
    "rtl/pss_sss_symbol_extractor.v"
    "rtl/slot_start_controller.v"
    "rtl/sample_power_sq.v"
    "rtl/sliding_window_sum.v"
    "rtl/frame_detect_fsm.v"
    "rtl/frame_detector.v"
    "rtl/frac_cfo_frame_corrector_top.v"
    "rtl/phase3_sync_top.v"
)

TB_SRC="tb/phase3_sync_reference_compare_tb.sv"

ALL_VERILOG_SRCS=( "${LEGACY_SRCS[@]}" "${UNIT_TEST_SRCS[@]}" "${RTL_SRCS[@]}" )

COMPILED_BIN="sim_out/p3_09_sweep_sim"

# Compile once (all cases share the same RTL)
echo "  Compiling RTL + TB..."
if [[ "$SIM" == "iverilog" ]]; then
    iverilog -g2012 \
        -I rtl \
        -o "$COMPILED_BIN" \
        "${ALL_VERILOG_SRCS[@]}" \
        "$TB_SRC" || {
        echo "  [ERROR] Compilation failed — check RTL source list."
        exit 1
    }
    echo "  [OK] Compiled: $COMPILED_BIN"
elif [[ "$SIM" == "xsim" ]]; then
    # Check xsim availability
    if ! command -v xsim &>/dev/null; then
        echo ""
        echo "  BLOCKED_XSIM_UNAVAILABLE"
        echo "  xsim not found in PATH. Source Vivado settings or use --sim iverilog."
        echo "  For official CI: bash scripts/run_phase3_sync_xsim.sh"
        exit 1
    fi
    xvlog -d SIMULATION \
        -i rtl \
        "${ALL_VERILOG_SRCS[@]}" \
        2>&1 | tee "sim_out/p3_09_xvlog_rtl.txt"
    xvlog --sv -d SIMULATION \
        -i rtl \
        "$TB_SRC" \
        2>&1 | tee "sim_out/p3_09_xvlog_tb.txt"
    xelab -debug typical \
        -top phase3_sync_reference_compare_tb \
        -snapshot p3_09_sweep_snap \
        2>&1 | tee "sim_out/p3_09_xelab.txt"
    echo "  [OK] xsim compile+elaborate complete (snapshot: p3_09_sweep_snap)"
else
    echo "  [ERROR] Unknown simulator: $SIM"
    exit 1
fi

# Run each case
SWEEP_K_INT=(-8 -4 -2 -1 0 1 2 4 8)
SWEEP_TAGS=(km8 km4 km2 km1 k0 kp1 kp2 kp4 kp8)

for i in "${!SWEEP_K_INT[@]}"; do
    k="${SWEEP_K_INT[$i]}"
    tag="${SWEEP_TAGS[$i]}"
    case_mem="$SWEEP_DIR/case_${tag}.mem"
    results_out="$SIM_OUT_DIR/case_${tag}_results.txt"

    echo ""
    echo "  >> Case $tag  (k_int=$k)"

    if [[ ! -f "$case_mem" ]]; then
        echo "     [SKIP] Stimulus file not found: $case_mem"
        continue
    fi

    # Link case stimulus to the path the TB reads
    ln -sf "$(pwd)/$case_mem" "golden/phase3_iq_stimulus_q15.hex"

    # Run simulation; capture rtl_results.txt
    if [[ "$SIM" == "iverilog" ]]; then
        vvp "$COMPILED_BIN" > "logs/p3_09_sim_${tag}.log" 2>&1 || true
    elif [[ "$SIM" == "xsim" ]]; then
        xsim p3_09_sweep_snap --runall \
            --log "logs/p3_09_sim_${tag}.log" 2>&1 || true
    fi

    # Move per-case results
    if [[ -f "sim_out/rtl_results.txt" ]]; then
        cp "sim_out/rtl_results.txt" "$results_out"
        echo "     [OK] Results: $results_out"
    else
        echo "     [WARN] sim_out/rtl_results.txt not written — simulation may have failed."
        echo "            See logs/p3_09_sim_${tag}.log"
    fi
done

# Restore canonical k_int=0 stimulus link
if [[ -f "$SWEEP_DIR/case_k0.mem" ]]; then
    ln -sf "$(pwd)/$SWEEP_DIR/case_k0.mem" "golden/phase3_iq_stimulus_q15.hex"
fi

# ---------------------------------------------------------------------------
# STEP 3: Compare all cases
# ---------------------------------------------------------------------------
echo ""
echo "--- Step 3: Compare sweep results ---"
python3 scripts/compare_p3_09_integer_cfo_sweep.py "$MANIFEST" "$SIM_OUT_DIR"

echo ""
echo "[P3-09] Sweep run complete."
