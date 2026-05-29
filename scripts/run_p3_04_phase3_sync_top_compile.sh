#!/usr/bin/env bash
# run_p3_04_phase3_sync_top_compile.sh
#
# Compile, elaborate, and simulate phase3_sync_top under xsim.
# Writes log to logs/p3_04_phase3_sync_top_compile.log.
# Prints CI GATE: PASSED / FAILED on stdout.
#
# Usage:
#   bash scripts/run_p3_04_phase3_sync_top_compile.sh [--vivado-bin /path/to/Vivado/2023.x/bin]
#
# Must be run from the project root or called from any directory (script
# sets its own working directory to project root automatically).

set -e

# ---------------------------------------------------------------------------
# Resolve paths
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

LOG_FILE="$PROJECT_DIR/logs/p3_04_phase3_sync_top_compile.log"
WORK_DIR="$PROJECT_DIR/xsim_work"
SNAP="p3_04_phase3_sync_top_snap"

mkdir -p logs "$WORK_DIR"

# ---------------------------------------------------------------------------
# Optional Vivado bin path override
# ---------------------------------------------------------------------------
VIVADO_BIN=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --vivado-bin) VIVADO_BIN="$2"; shift 2 ;;
        *) shift ;;
    esac
done

if [[ -n "$VIVADO_BIN" ]]; then
    export PATH="$VIVADO_BIN:$PATH"
fi

# ---------------------------------------------------------------------------
# Tool availability check
# ---------------------------------------------------------------------------
if ! command -v xvlog &>/dev/null; then
    echo "ERROR: xvlog not found in PATH. Install Vivado and source settings64.sh." | tee -a "$LOG_FILE"
    echo "CI GATE: FAILED (tool not found)"
    exit 1
fi

echo "=== P3-04 Phase3 sync_top compile run ===" | tee "$LOG_FILE"
date | tee -a "$LOG_FILE"
echo "Project root: $PROJECT_DIR" | tee -a "$LOG_FILE"

# ---------------------------------------------------------------------------
# Stub ROM files — meyr_integer_cfo_core $readmemh requires these at sim start.
# The files must exist relative to the xsim working directory.  We run xsim
# from $PROJECT_DIR so the paths vectors/*.txt resolve correctly.
# ---------------------------------------------------------------------------
mkdir -p vectors
for ROM in vectors/meyr_pss_reference_romhex.txt vectors/meyr_sss_reference_romhex.txt; do
    if [[ ! -f "$ROM" ]]; then
        echo "Creating stub ROM: $ROM" | tee -a "$LOG_FILE"
        python3 -c "print('00000000\n' * 255 + '00000000')" > "$ROM"
    fi
done

# ---------------------------------------------------------------------------
# RTL compile list — bottom-up dependency order
# (see docs/p3_04_phase3_sync_top_compile_status.md for hierarchy)
# ---------------------------------------------------------------------------
RTL_FILES=(
    # Leaves: DO NOT MODIFY modules
    rtl/cordic_atan2.v
    rtl/nco_phase_gen.v
    rtl/complex_rotator.v

    # Leaf utilities
    rtl/peak_detector.v
    rtl/meyr_pss_sss_product_gen.v
    rtl/unit_test/and2.v
    rtl/unit_test/cp_autocorr_core.v

    # Level-2: modules in rtl/ (not unit_test/)
    rtl/iq_frame_buffer.v
    rtl/fft256_dual_symbol_frontend.v
    rtl/frac_cfo_corrector_top.v

    # P3-12A modular frame_detector submodules
    rtl/sample_power_sq.v
    rtl/sliding_window_sum.v
    rtl/frame_detect_fsm.v
    rtl/frame_detector.v

    # Level-3
    rtl/unit_test/timing_metric_core.v
    rtl/meyr_integer_cfo_core.v

    # Level-4
    rtl/timing_sync_top.v
    rtl/meyr_integer_cfo_freq_estimator_top.v

    # Level-5
    rtl/frac_cfo_estimator.v

    # Level-6
    rtl/timing_frac_cfo_top.v
    rtl/meyr_integer_cfo_fft_frontend_top.v
    rtl/meyr_term2_ref_rom.v

    # Level-7
    rtl/frac_cfo_frame_corrector_top.v

    # DUT components
    rtl/slot_start_controller.v
    rtl/pss_sss_symbol_extractor.v

    # DUT top
    rtl/phase3_sync_top.v
)

# ---------------------------------------------------------------------------
# Verify all source files exist
# ---------------------------------------------------------------------------
MISSING=0
for f in "${RTL_FILES[@]}"; do
    if [[ ! -f "$f" ]]; then
        echo "MISSING: $f" | tee -a "$LOG_FILE"
        MISSING=1
    fi
done
if [[ ! -f tb/p3_04_phase3_sync_top_compile_tb.sv ]]; then
    echo "MISSING: tb/p3_04_phase3_sync_top_compile_tb.sv" | tee -a "$LOG_FILE"
    MISSING=1
fi
if [[ $MISSING -ne 0 ]]; then
    echo "CI GATE: FAILED (missing source files)" | tee -a "$LOG_FILE"
    exit 1
fi

# ---------------------------------------------------------------------------
# Step 1: compile RTL
# ---------------------------------------------------------------------------
echo "" | tee -a "$LOG_FILE"
echo "--- Step 1: xvlog (RTL) ---" | tee -a "$LOG_FILE"

XVLOG_RC=0
for f in "${RTL_FILES[@]}"; do
    echo "  compiling $f" | tee -a "$LOG_FILE"
    xvlog --sv --work work --log /dev/null "$f" >> "$LOG_FILE" 2>&1 || XVLOG_RC=1
done

# ---------------------------------------------------------------------------
# Step 2: compile testbench
# ---------------------------------------------------------------------------
echo "" | tee -a "$LOG_FILE"
echo "--- Step 2: xvlog (TB) ---" | tee -a "$LOG_FILE"
echo "  compiling tb/p3_04_phase3_sync_top_compile_tb.sv" | tee -a "$LOG_FILE"
xvlog --sv --work work --log /dev/null \
    tb/p3_04_phase3_sync_top_compile_tb.sv >> "$LOG_FILE" 2>&1 || XVLOG_RC=1

if [[ $XVLOG_RC -ne 0 ]]; then
    # Count ERROR lines for a summary
    ERR_COUNT=$(grep -c "^ERROR:" "$LOG_FILE" 2>/dev/null || true)
    echo "" | tee -a "$LOG_FILE"
    echo "xvlog FAILED ($ERR_COUNT ERROR lines in log)" | tee -a "$LOG_FILE"
    echo "CI GATE: FAILED (compile errors)" | tee -a "$LOG_FILE"
    exit 1
fi
echo "xvlog OK" | tee -a "$LOG_FILE"

# ---------------------------------------------------------------------------
# Step 3: elaborate
# ---------------------------------------------------------------------------
echo "" | tee -a "$LOG_FILE"
echo "--- Step 3: xelab ---" | tee -a "$LOG_FILE"
xelab --debug typical \
      work.p3_04_phase3_sync_top_compile_tb \
      --snapshot "$SNAP" \
      --log /dev/null \
      >> "$LOG_FILE" 2>&1
XELAB_RC=$?

if [[ $XELAB_RC -ne 0 ]]; then
    ERR_COUNT=$(grep -c "ERROR:" "$LOG_FILE" 2>/dev/null || true)
    echo "xelab FAILED ($ERR_COUNT ERROR lines)" | tee -a "$LOG_FILE"
    echo "CI GATE: FAILED (elaboration errors)" | tee -a "$LOG_FILE"
    exit 1
fi
echo "xelab OK" | tee -a "$LOG_FILE"

# ---------------------------------------------------------------------------
# Step 4: simulate
# ---------------------------------------------------------------------------
echo "" | tee -a "$LOG_FILE"
echo "--- Step 4: xsim ---" | tee -a "$LOG_FILE"

# Inline TCL: run 20 us (covers 1000 cycles at 10 ns) then exit
TCL_CMD="run 20us; exit"

xsim "$SNAP" --tclbatch <(echo "$TCL_CMD") \
     --log /dev/null \
     >> "$LOG_FILE" 2>&1
XSIM_RC=$?

# Check for FATAL/FAIL indicators in log
if grep -q "FATAL\|COMPILE_TB FAIL" "$LOG_FILE"; then
    echo "xsim run reported FATAL error" | tee -a "$LOG_FILE"
    echo "CI GATE: FAILED (simulation fatal)" | tee -a "$LOG_FILE"
    exit 1
fi

if [[ $XSIM_RC -ne 0 ]]; then
    echo "xsim exited with code $XSIM_RC" | tee -a "$LOG_FILE"
    echo "CI GATE: FAILED (xsim non-zero exit)" | tee -a "$LOG_FILE"
    exit 1
fi

echo "xsim OK" | tee -a "$LOG_FILE"

# ---------------------------------------------------------------------------
# Final result
# ---------------------------------------------------------------------------
echo "" | tee -a "$LOG_FILE"
echo "Log: $LOG_FILE" | tee -a "$LOG_FILE"
echo "CI GATE: PASSED" | tee -a "$LOG_FILE"
