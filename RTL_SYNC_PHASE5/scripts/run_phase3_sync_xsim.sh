#!/usr/bin/env bash
# run_phase3_sync_xsim.sh — OFFICIAL Phase 3 Vivado xsim CI runner
#
# This is the authoritative CI gate for Phase 3 synchronizer verification.
# Only a PASS from this script counts as official sign-off.
#
# iverilog is available as a quick sanity check via:
#   ./scripts/run_phase3_sync_sim.sh --sim iverilog
# iverilog results are NOT official CI sign-off.
#
# Usage:
#   ./scripts/run_phase3_sync_xsim.sh [--iq <iq_float32.f32>]
#
# Optional environment variables:
#   VIVADO_SETTINGS_FILE  — path to Vivado settings64.sh
#                           (auto-detected if xsim already in PATH or if
#                            Vivado is installed in standard locations)
#
# If Vivado/xsim is not found, the script exits with:
#   CI_GATE: BLOCKED_XSIM_UNAVAILABLE
# and prints exact instructions to unblock.
#
# Output files (same as run_phase3_sync_sim.sh, consumed by compare_golden_rtl.py):
#   sim_out/rtl_results.txt
#   sim_out/sim_log.txt
#   sim_out/xelab_log.txt
#   logs/phase3_sync_rtl_dump.csv
#   golden/phase3_golden_values.txt
#
# DUT: rtl/phase3_sync_top.v (and 30-file compile order below)
# TB:  tb/phase3_sync_reference_compare_tb.sv

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${SCRIPT_DIR}/.."

# --------------------------------------------------------------------------
# Argument parsing
# --------------------------------------------------------------------------
IQ_FILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --iq)   IQ_FILE="$2"; shift 2 ;;
        *)      echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

# --------------------------------------------------------------------------
# Step 0: Discover Vivado / xsim
# --------------------------------------------------------------------------
echo "=== [0] Checking for Vivado xsim ==="

if ! command -v xsim &>/dev/null; then
    VIVADO_FOUND=""

    # Check explicit env var first
    if [[ -n "${VIVADO_SETTINGS_FILE:-}" && -f "${VIVADO_SETTINGS_FILE}" ]]; then
        # shellcheck disable=SC1090
        source "${VIVADO_SETTINGS_FILE}"
        VIVADO_FOUND="${VIVADO_SETTINGS_FILE}"
    else
        # Try common Vivado installation directories
        for search_base in /opt/Xilinx /tools/Xilinx /EDA/Xilinx /home/Xilinx /usr/local/Xilinx; do
            if [[ -d "${search_base}/Vivado" ]]; then
                candidate=$(ls -1d "${search_base}/Vivado/"*"/settings64.sh" 2>/dev/null \
                            | sort -V | tail -1)
                if [[ -n "${candidate}" && -f "${candidate}" ]]; then
                    # shellcheck disable=SC1090
                    source "${candidate}"
                    VIVADO_FOUND="${candidate}"
                    break
                fi
            fi
        done
    fi

    if ! command -v xsim &>/dev/null; then
        echo ""
        echo "=============================="
        echo "CI_GATE: BLOCKED_XSIM_UNAVAILABLE"
        echo "=============================="
        echo ""
        echo "  xsim (Vivado) was not found in PATH and could not be auto-discovered."
        echo ""
        echo "  Searched for settings64.sh in:"
        echo "    /opt/Xilinx/Vivado/    /tools/Xilinx/Vivado/"
        echo "    /EDA/Xilinx/Vivado/    /home/Xilinx/Vivado/"
        echo "    /usr/local/Xilinx/Vivado/"
        echo ""
        echo "  To unblock — choose ONE of:"
        echo ""
        echo "    Option A: source Vivado settings manually, then re-run"
        echo "      source /path/to/Vivado/YYYY.N/settings64.sh"
        echo "      bash scripts/run_phase3_sync_xsim.sh"
        echo ""
        echo "    Option B: set VIVADO_SETTINGS_FILE env var"
        echo "      export VIVADO_SETTINGS_FILE=/path/to/Vivado/YYYY.N/settings64.sh"
        echo "      bash scripts/run_phase3_sync_xsim.sh"
        echo ""
        echo "    Option C: install Vivado (2019.1 or later)"
        echo "      https://www.xilinx.com/support/download.html"
        echo ""
        echo "  For a quick local sanity check using iverilog (NOT official sign-off):"
        echo "    bash scripts/run_phase3_sync_sim.sh --sim iverilog"
        echo ""
        exit 1
    fi

    echo "  [OK] Sourced Vivado settings: ${VIVADO_FOUND}"
else
    echo "  [OK] xsim found in PATH: $(command -v xsim)"
fi

# --------------------------------------------------------------------------
# Directory setup
# --------------------------------------------------------------------------
mkdir -p "${ROOT}/golden"
mkdir -p "${ROOT}/sim_out"
mkdir -p "${ROOT}/logs"

cd "${ROOT}"

# --------------------------------------------------------------------------
# Step a: Build golden_dump
# --------------------------------------------------------------------------
echo ""
echo "=== [a] Building golden_dump ==="
if [[ ! -f "${SCRIPT_DIR}/golden_dump.c" ]]; then
    echo "ERROR: scripts/golden_dump.c not found." >&2
    exit 1
fi

gcc -O2 -Wall \
    "${SCRIPT_DIR}/golden_dump.c" \
    -lm \
    -o "${SCRIPT_DIR}/golden_dump"
echo "  Built: scripts/golden_dump"

# --------------------------------------------------------------------------
# Step b: IQ stimulus check + run golden dump
# --------------------------------------------------------------------------
echo ""
echo "=== [b] Running golden dump ==="
if [[ -z "${IQ_FILE}" ]]; then
    IQ_FILE="${ROOT}/golden/phase3_iq_stimulus.f32"
    if [[ ! -f "${IQ_FILE}" ]]; then
        echo "  Auto-generating IQ stimulus (scripts/gen_phase3_iq_stimulus.py)..."
        python3 "${SCRIPT_DIR}/gen_phase3_iq_stimulus.py"
    fi
fi
echo "  Using IQ file: ${IQ_FILE}"

"${SCRIPT_DIR}/golden_dump" \
    "${IQ_FILE}" \
    "${ROOT}/golden/phase3_golden_values.txt" \
    "${ROOT}/golden/phase3_autocorr_full.txt"
echo "  Golden values → golden/phase3_golden_values.txt"

# --------------------------------------------------------------------------
# Step c: Convert float32 IQ to Q15 hex for RTL testbench
# --------------------------------------------------------------------------
echo ""
echo "=== [c] Converting IQ to Q15 hex ==="
IQ_FILE_ABS="$(realpath "${IQ_FILE}")"
export IQ_FILE_ABS ROOT

python3 << 'PYEOF'
import struct, os, sys

iq_file = os.environ["IQ_FILE_ABS"]
root    = os.environ["ROOT"]

with open(iq_file, "rb") as f:
    raw = f.read()

n_floats = len(raw) // 4
if n_floats % 2 != 0:
    n_floats -= 1
floats = struct.unpack(f"<{n_floats}f", raw[:n_floats*4])
n_samples = n_floats // 2

def to_q15(v):
    vi = int(round(float(v)))
    return max(-32768, min(32767, vi)) & 0xFFFF

hex_lines = []
for i in range(n_samples):
    i16 = to_q15(floats[2*i])
    q16 = to_q15(floats[2*i + 1])
    hex_lines.append(f"{q16:04X}{i16:04X}")

out_path = os.path.join(root, "golden", "phase3_iq_stimulus_q15.hex")
with open(out_path, "w") as f:
    f.write("\n".join(hex_lines) + "\n")

print(f"  Written {n_samples} IQ pairs → {out_path}")
PYEOF

# --------------------------------------------------------------------------
# Step d: RTL source list (identical to run_phase3_sync_sim.sh)
# --------------------------------------------------------------------------
echo ""
echo "=== [d] Compiling RTL + TB with xvlog ==="

# --------------------------------------------------------------------------
# Production DUT source list — single source of truth.
# --------------------------------------------------------------------------
FILELIST="${ROOT}/scripts/phase3_dut_filelist.f"
mapfile -t DUT_SRCS < <(grep -v '^#' "${FILELIST}" | grep -v '^[[:space:]]*$' | sed "s|^|${ROOT}/|")

TB_SRC="${ROOT}/tb/phase3_sync_reference_compare_tb.sv"

# Compile Verilog sources
xvlog -d SIMULATION \
    -i "${ROOT}/rtl" \
    "${DUT_SRCS[@]}" \
    2>&1 | tee "${ROOT}/sim_out/xvlog_rtl_log.txt"

if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    echo "ERROR: xvlog (RTL sources) failed — see sim_out/xvlog_rtl_log.txt" >&2
    echo ""
    echo "=============================="
    echo "CI_GATE: FAIL  (xvlog RTL compile error)"
    echo "=============================="
    exit 1
fi

# Compile SystemVerilog testbench
xvlog --sv -d SIMULATION \
    -i "${ROOT}/rtl" \
    "${TB_SRC}" \
    2>&1 | tee "${ROOT}/sim_out/xvlog_tb_log.txt"

if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    echo "ERROR: xvlog (testbench) failed — see sim_out/xvlog_tb_log.txt" >&2
    echo ""
    echo "=============================="
    echo "CI_GATE: FAIL  (xvlog TB compile error)"
    echo "=============================="
    exit 1
fi

echo "  [OK] xvlog compile complete"

# --------------------------------------------------------------------------
# Step e: Elaborate
# --------------------------------------------------------------------------
echo ""
echo "=== [e] Elaborating with xelab ==="
xelab -debug typical \
    -top phase3_sync_reference_compare_tb \
    -snapshot phase3_snap \
    2>&1 | tee "${ROOT}/sim_out/xelab_log.txt"

if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    echo "ERROR: xelab failed — see sim_out/xelab_log.txt" >&2
    echo ""
    echo "=============================="
    echo "CI_GATE: FAIL  (xelab elaboration error)"
    echo "=============================="
    exit 1
fi
echo "  [OK] xelab elaborate complete — snapshot: phase3_snap"

# --------------------------------------------------------------------------
# Step f: Simulate
# --------------------------------------------------------------------------
echo ""
echo "=== [f] Simulating with xsim ==="
xsim phase3_snap \
    --runall \
    --log "${ROOT}/sim_out/sim_log.txt"

SIM_EXIT=${PIPESTATUS[0]:-$?}
echo "  Simulation log     → sim_out/sim_log.txt"
echo "  RTL results        → sim_out/rtl_results.txt"
echo "  RTL CSV trace      → logs/phase3_sync_rtl_dump.csv"

if [[ ${SIM_EXIT} -ne 0 ]]; then
    echo "WARNING: xsim exited with code ${SIM_EXIT} (may indicate $finish or assertion)" >&2
fi

# --------------------------------------------------------------------------
# Step g: Compare golden vs RTL
# --------------------------------------------------------------------------
echo ""
echo "=== [g] Comparing golden vs RTL ==="

if [[ ! -f "${SCRIPT_DIR}/compare_golden_rtl.py" ]]; then
    echo "ERROR: scripts/compare_golden_rtl.py not found." >&2
    exit 1
fi

COMPARE_EXIT=0
python3 "${SCRIPT_DIR}/compare_golden_rtl.py" \
    "${ROOT}/golden/phase3_golden_values.txt" \
    "${ROOT}/sim_out/rtl_results.txt" || COMPARE_EXIT=$?

# --------------------------------------------------------------------------
# Step h: CI GATE
# --------------------------------------------------------------------------
echo ""
echo "=============================="
if [[ ${COMPARE_EXIT} -eq 0 ]]; then
    echo "CI_GATE: PASS  (Vivado xsim)"
else
    echo "CI_GATE: FAIL  (compare_golden_rtl.py exited ${COMPARE_EXIT})"
    echo ""
    echo "  Review:"
    echo "    sim_out/rtl_results.txt"
    echo "    golden/phase3_golden_values.txt"
    echo "    logs/phase3_sync_rtl_dump.csv"
    echo "    sim_out/sim_log.txt"
    echo "    sim_out/xelab_log.txt"
fi
echo "=============================="
echo ""

exit ${COMPARE_EXIT}
