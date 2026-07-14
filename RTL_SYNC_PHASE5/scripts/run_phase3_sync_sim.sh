#!/usr/bin/env bash
# run_phase3_sync_sim.sh — Phase 3 end-to-end simulation runner
#
# DUT: rtl/phase3_sync_top.v (instantiates frac_cfo_frame_corrector_top,
#      slot_start_controller, pss_sss_symbol_extractor,
#      meyr_integer_cfo_fft_frontend_top)
#
# Usage:
#   ./scripts/run_phase3_sync_sim.sh --iq <iq_float32.f32> [--sim xsim|iverilog]
#
# Prerequisites:
#   xsim (default): Vivado xvlog/xelab/xsim in PATH
#   iverilog:       iverilog + vvp in PATH
#   python3, gcc, make
#
# Steps:
#   a) Build golden_dump from scripts/golden_dump.c
#   b) Run golden_dump → golden/phase3_golden_values.txt
#   c) Convert float32 IQ → Q15 hex for RTL testbench
#   d) Compile RTL and TB
#   e) Run simulator
#   f) Compare golden vs RTL output
#   g) Print CI GATE result
#
# EXCLUDED from compilation:
#   rtl/unit_test/phase2_integer_cfo_estimator.v  (unit-test only, never in production)
#   rtl/fft256_xilinx_wrapper.v                   (Xilinx IP, not in phase3_sync_top hierarchy)
#   rtl/unit_test/cordic_atan2_xilinx_wrapper.v   (same)
#   rtl/unit_test/nco_phase_gen_xilinx_wrapper.v  (same)
#   All FPGA/DMA/AXI-Lite/board wrapper files

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${SCRIPT_DIR}/.."

# --------------------------------------------------------------------------
# Argument parsing
# --------------------------------------------------------------------------
IQ_FILE=""
SIM_TOOL="xsim"   # default: Xilinx xsim

while [[ $# -gt 0 ]]; do
    case "$1" in
        --iq)   IQ_FILE="$2"; shift 2 ;;
        --sim)  SIM_TOOL="$2"; shift 2 ;;
        *)      echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

# --------------------------------------------------------------------------
# Directory setup
# --------------------------------------------------------------------------
mkdir -p "${ROOT}/golden"
mkdir -p "${ROOT}/sim_out"
mkdir -p "${ROOT}/logs"

# Run everything from project root so TB file paths resolve correctly
cd "${ROOT}"

# --------------------------------------------------------------------------
# Step a: Build golden_dump
# --------------------------------------------------------------------------
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
    n_floats -= 1  # drop odd trailing byte
floats = struct.unpack(f"<{n_floats}f", raw[:n_floats*4])
n_samples = n_floats // 2

def to_q15(v):
    # Input is integer-scale float (same magnitude as int16, not normalised to [-1,1]).
    # Clamp directly to int16 range rather than assuming a [-1,1] domain.
    vi = int(round(float(v)))
    return max(-32768, min(32767, vi)) & 0xFFFF

hex_lines = []
for i in range(n_samples):
    i16 = to_q15(floats[2*i])
    q16 = to_q15(floats[2*i + 1])
    # Pack as {Q[31:16], I[15:0]} matching DUT s_axis_tdata convention
    hex_lines.append(f"{q16:04X}{i16:04X}")

out_path = os.path.join(root, "golden", "phase3_iq_stimulus_q15.hex")
with open(out_path, "w") as f:
    f.write("\n".join(hex_lines) + "\n")

print(f"  Written {n_samples} IQ pairs → {out_path}")
PYEOF

# --------------------------------------------------------------------------
# Step d: RTL source list
# --------------------------------------------------------------------------
echo "=== [d] Compiling RTL + TB ==="

# --------------------------------------------------------------------------
# Production DUT source list — single source of truth.
# --------------------------------------------------------------------------
FILELIST="${ROOT}/scripts/phase3_dut_filelist.f"
mapfile -t DUT_SRCS < <(grep -v '^#' "${FILELIST}" | grep -v '^[[:space:]]*$' | sed "s|^|${ROOT}/|")

TB_SRC="${ROOT}/tb/phase3_sync_reference_compare_tb.sv"

# --------------------------------------------------------------------------
# Step e: Run simulation
# --------------------------------------------------------------------------
echo "=== [e] Running simulation (${SIM_TOOL}) ==="

if [[ "${SIM_TOOL}" == "xsim" ]]; then
    # xvlog: compile all Verilog sources (plain Verilog)
    xvlog -d SIMULATION \
        -i "${ROOT}/rtl" \
        "${DUT_SRCS[@]}"

    # xvlog --sv: compile SystemVerilog testbench separately
    xvlog --sv -d SIMULATION \
        -i "${ROOT}/rtl" \
        "${TB_SRC}"

    # xelab: elaborate
    xelab -debug typical \
        -top phase3_sync_reference_compare_tb \
        -snapshot phase3_snap \
        2>&1 | tee "${ROOT}/sim_out/xelab_log.txt"

    # xsim: simulate
    xsim phase3_snap \
        --runall \
        --log "${ROOT}/sim_out/sim_log.txt"

elif [[ "${SIM_TOOL}" == "iverilog" ]]; then
    # Note: iverilog 11 uses -g2012 for SystemVerilog; do NOT use -sv (parsed as -s v)
    iverilog -g2012 \
        -I "${ROOT}/rtl" \
        -o "${ROOT}/sim_out/phase3_sim.vvp" \
        "${DUT_SRCS[@]}" \
        "${TB_SRC}"

    vvp "${ROOT}/sim_out/phase3_sim.vvp" | tee "${ROOT}/sim_out/sim_log.txt"

else
    echo "ERROR: Unknown simulator '${SIM_TOOL}'. Use xsim or iverilog." >&2
    exit 1
fi

echo "  Simulation log     → sim_out/sim_log.txt"
echo "  RTL results        → sim_out/rtl_results.txt"
echo "  RTL CSV trace      → logs/phase3_sync_rtl_dump.csv"

# --------------------------------------------------------------------------
# Step f: Compare golden vs RTL
# --------------------------------------------------------------------------
echo "=== [f] Comparing golden vs RTL ==="

if [[ ! -f "${SCRIPT_DIR}/compare_golden_rtl.py" ]]; then
    echo "ERROR: scripts/compare_golden_rtl.py not found." >&2
    exit 1
fi

COMPARE_EXIT=0
python3 "${SCRIPT_DIR}/compare_golden_rtl.py" \
    "${ROOT}/golden/phase3_golden_values.txt" \
    "${ROOT}/sim_out/rtl_results.txt" || COMPARE_EXIT=$?

# --------------------------------------------------------------------------
# Step g: CI GATE
# --------------------------------------------------------------------------
echo ""
echo "=============================="
if [[ ${COMPARE_EXIT} -eq 0 ]]; then
    echo "CI_GATE: PASS"
else
    echo "CI_GATE: FAIL  (compare_golden_rtl.py exited ${COMPARE_EXIT})"
    echo "  Review:"
    echo "    sim_out/rtl_results.txt"
    echo "    golden/phase3_golden_values.txt"
    echo "    logs/phase3_sync_rtl_dump.csv"
    echo "    sim_out/sim_log.txt"
fi
echo "=============================="
echo ""

exit ${COMPARE_EXIT}
