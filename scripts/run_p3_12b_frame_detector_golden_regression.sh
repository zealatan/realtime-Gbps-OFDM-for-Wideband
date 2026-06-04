#!/usr/bin/env bash
# run_p3_12b_frame_detector_golden_regression.sh
#
# P3-12B: Validates new modular frame_detector (P3-12A) against Phase3 golden.
# Verifies frame_index=41 and slot_start=64 through the full phase3_sync_top path.
#
# Usage:
#   ./scripts/run_p3_12b_frame_detector_golden_regression.sh [--sim xsim|iverilog]
#
# CI policy:
#   xsim (Xilinx)  → CI_GATE OFFICIAL
#   iverilog        → SANITY_GATE only; NEVER claim official PASS for iverilog runs

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SIM="xsim"
while [[ $# -gt 0 ]]; do
    case $1 in
        --sim) SIM="$2"; shift 2 ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

LOGS="${ROOT}/logs"
SIM_OUT="${ROOT}/sim_out"
GOLDEN="${ROOT}/golden"
mkdir -p "${LOGS}" "${SIM_OUT}" "${GOLDEN}"

cd "${ROOT}"

# ============================================================================
# Gate: xsim availability
# ============================================================================
if [[ "${SIM}" == "xsim" ]]; then
    if ! command -v xvlog &>/dev/null; then
        echo ""
        echo "CI_GATE: BLOCKED_XSIM_UNAVAILABLE"
        echo "  xvlog/xsim not found in PATH. Install Vivado and retry."
        echo "  Iverilog sanity: --sim iverilog"
        exit 2
    fi
fi

if [[ "${SIM}" == "iverilog" ]]; then
    if ! command -v iverilog &>/dev/null; then
        echo "ERROR: iverilog not found."
        exit 2
    fi
fi

# ============================================================================
# Step 1: Ensure IQ stimulus exists
# ============================================================================
echo "=== [1] IQ Stimulus ==="
if [[ ! -f "${GOLDEN}/phase3_iq_stimulus_q15.hex" ]]; then
    echo "  phase3_iq_stimulus_q15.hex missing — regenerating..."
    python3 "${SCRIPT_DIR}/gen_phase3_iq_stimulus.py"
    python3 << 'PYEOF'
import struct, os, sys
root = os.environ.get("ROOT", ".")
iq_file = os.path.join(root, "golden", "phase3_iq_stimulus.f32")
with open(iq_file, "rb") as f:
    raw = f.read()
n_floats = len(raw) // 4
if n_floats % 2: n_floats -= 1
floats = struct.unpack(f"<{n_floats}f", raw[:n_floats*4])
n = n_floats // 2
def to_q15(v):
    vi = int(round(float(v)))
    return max(-32768, min(32767, vi)) & 0xFFFF
lines = [f"{to_q15(floats[2*i+1]):04X}{to_q15(floats[2*i]):04X}" for i in range(n)]
out = os.path.join(root, "golden", "phase3_iq_stimulus_q15.hex")
with open(out, "w") as f: f.write("\n".join(lines) + "\n")
print(f"  Written {n} pairs → {out}")
PYEOF
fi
echo "  OK: golden/phase3_iq_stimulus_q15.hex"

# ============================================================================
# Step 2: Verify required RTL files
# ============================================================================
echo "=== [2] Checking modular frame_detector source files ==="
MODULAR_FILES=(
    "${ROOT}/rtl/DUT/sample_power_sq.v"
    "${ROOT}/rtl/DUT/sliding_window_sum.v"
    "${ROOT}/rtl/DUT/frame_detect_fsm.v"
    "${ROOT}/rtl/DUT/frame_detector.v"
)
MISSING=0
for f in "${MODULAR_FILES[@]}"; do
    if [[ -f "$f" ]]; then
        echo "  OK: $(basename $f)"
    else
        echo "  MISSING: $f"
        MISSING=1
    fi
done
if [[ $MISSING -ne 0 ]]; then
    echo "ERROR: Modular frame_detector files missing. Run P3-12A first."
    exit 2
fi

# Verify NOT depending on unit_test/frame_detector.v
echo "  Old detector check: unit_test/frame_detector.v in path? (must be NO)"
if grep -q "unit_test/frame_detector" "${SCRIPT_DIR}/run_phase3_sync_sim.sh" 2>/dev/null; then
    echo "  FAIL: run_phase3_sync_sim.sh still references unit_test/frame_detector.v"
    exit 2
else
    echo "  OK: unit_test/frame_detector.v NOT in source list"
fi

# ============================================================================
# Step 3: RTL source list (mirrors run_phase3_sync_sim.sh)
# ============================================================================
echo "=== [3] Building source list ==="

# --------------------------------------------------------------------------
# Production DUT source list — single source of truth.
# --------------------------------------------------------------------------
FILELIST="${ROOT}/scripts/phase3_dut_filelist.f"
mapfile -t DUT_SRCS < <(grep -v '^#' "${FILELIST}" | grep -v '^[[:space:]]*$' | sed "s|^|${ROOT}/|")

TB_SRC="${ROOT}/tb/p3_12b_frame_detector_golden_regression_tb.sv"
echo "  Total RTL sources: ${#DUT_SRCS[@]}"

# ============================================================================
# Step 4: Compile + simulate
# ============================================================================
echo "=== [4] Compile + simulate (SIM=${SIM}) ==="

if [[ "${SIM}" == "iverilog" ]]; then
    echo "  NOTE: iverilog → SANITY_GATE only"
    iverilog -g2012 \
        -I "${ROOT}/rtl" \
        -o "${SIM_OUT}/p3_12b.vvp" \
        "${DUT_SRCS[@]}" \
        "${TB_SRC}" \
        2>&1 | tee "${LOGS}/p3_12b_compile.log"
    echo "  Compile: OK"
    echo "  Simulating..."
    vvp "${SIM_OUT}/p3_12b.vvp" | tee "${LOGS}/p3_12b_sim.log"

elif [[ "${SIM}" == "xsim" ]]; then
    WORK="${SIM_OUT}/p3_12b_work"
    mkdir -p "${WORK}"
    cd "${WORK}"
    xvlog -d SIMULATION \
        -i "${ROOT}/rtl" \
        "${DUT_SRCS[@]}" \
        2>&1 | tee "${LOGS}/p3_12b_xvlog.log"
    xvlog --sv -d SIMULATION \
        -i "${ROOT}/rtl" \
        "${TB_SRC}" \
        2>&1 | tee -a "${LOGS}/p3_12b_xvlog.log"
    xelab -debug typical \
        -top p3_12b_frame_detector_golden_regression_tb \
        -snapshot p3_12b_snap \
        2>&1 | tee "${LOGS}/p3_12b_xelab.log"
    xsim p3_12b_snap --runall \
        2>&1 | tee "${LOGS}/p3_12b_sim.log"
    cd "${ROOT}"
fi

# ============================================================================
# Step 5: Gate result
# ============================================================================
LOG="${LOGS}/p3_12b_sim.log"
echo ""
echo "=== [5] P3-12B Gate ==="

if grep -q "CI GATE: PASSED" "${LOG}"; then
    if [[ "${SIM}" == "xsim" ]]; then
        echo "CI_GATE: PASS (xsim)"
    else
        echo "SANITY_GATE: PASS (iverilog)"
        echo "CI_GATE: BLOCKED_XSIM_UNAVAILABLE"
        echo "NOTE: Run with --sim xsim for official CI_GATE PASS"
    fi
    exit 0
else
    if [[ "${SIM}" == "xsim" ]]; then
        echo "CI_GATE: FAIL"
    else
        echo "SANITY_GATE: FAIL"
    fi
    echo "  Review: ${LOG}"
    exit 1
fi
