#!/usr/bin/env bash
# run_p3_25b_real_fft_ip_validation.sh — P3-25B Real Xilinx FFT IP Validation
#
# Validates the frozen production hierarchy using the real Xilinx xfft_v9_1 IP
# via native Linux Vivado 2022.2 xsim (no Windows cmd.exe required).
#
# DUT: meyr_integer_cfo_fft_frontend_top (USE_BEHAVIORAL_STUB=0)
#   ├─ fft256_dual_symbol_frontend
#   │   └─ fft256_xilinx_wrapper → fft256_xilinx (xfft_v9_1)
#   └─ meyr_integer_cfo_freq_estimator_top → meyr_integer_cfo_core → peak_detector
#
# Pass criteria: all 9 k_int sweep cases (k=0,±1,±2,±4,±8):
#   peak_index = 255 + k_int
#   int_cfo    = k_int
#
# Gate output:
#   OFFICIAL_GATE: PASS  — all 9 cases pass (real Xilinx FFT IP)
#   OFFICIAL_GATE: FAIL  — ≥1 case failed
#   OFFICIAL_GATE: BLOCKED_*
#
# USAGE:
#   bash scripts/run_p3_25b_real_fft_ip_validation.sh [--log-dir DIR] [--vivado-dir DIR]
#
# EXIT CODES:
#   0  OFFICIAL_GATE: PASS
#   1  FAIL or BLOCKED

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOG_DIR="${ROOT}/sim_out/p3_25b"
VIVADO_DIR="/home/zealatan/Downloads/Vivado/2022.2"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --log-dir)    shift; LOG_DIR="$1"    ;;
        --vivado-dir) shift; VIVADO_DIR="$1" ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
    shift
done

mkdir -p "${LOG_DIR}"

GATE_LOG="${LOG_DIR}/p3_25b_real_fft_gate.txt"
COMPILE_LOG="${LOG_DIR}/p3_25b_compile.log"
SIM_LOG="${LOG_DIR}/p3_25b_sim.log"

gate_out() {
    local msg="$1"
    echo ""
    echo "========================================================================"
    echo "${msg}"
    echo "========================================================================"
    echo "${msg}" > "${GATE_LOG}"
}

# ---------------------------------------------------------------------------
echo "========================================================================"
echo " P3-25B Real Xilinx FFT IP Validation"
echo " Date      : $(date '+%Y-%m-%d %H:%M:%S')"
echo " Project   : ${ROOT}"
echo " Log dir   : ${LOG_DIR}"
echo " Vivado    : ${VIVADO_DIR}"
echo "========================================================================"
echo ""

# ---------------------------------------------------------------------------
# Tool check
# ---------------------------------------------------------------------------
export PATH="${VIVADO_DIR}/bin:${PATH}"
if ! command -v xvhdl &>/dev/null || ! command -v xvlog &>/dev/null || \
   ! command -v xelab &>/dev/null || ! command -v xsim  &>/dev/null; then
    gate_out "OFFICIAL_GATE: BLOCKED_XSIM_UNAVAILABLE"
    echo "  Vivado tools not found. Check --vivado-dir."
    exit 1
fi

XSIM_VER=$(xsim --version 2>&1 | head -1)
echo "  Simulator: ${XSIM_VER}"
echo ""

# ---------------------------------------------------------------------------
# Pre-flight: required files
# ---------------------------------------------------------------------------
echo "--- Pre-flight: required files ---"
BLOCKED=0
for f in \
    "${ROOT}/rtl/DUT/peak_detector.v" \
    "${ROOT}/rtl/DUT/meyr_pss_sss_product_gen.v" \
    "${ROOT}/rtl/DUT/meyr_integer_cfo_core.v" \
    "${ROOT}/rtl/DUT/meyr_integer_cfo_freq_estimator_top.v" \
    "${ROOT}/rtl/DUT/fft256_xilinx_wrapper.v" \
    "${ROOT}/rtl/DUT/fft256_dual_symbol_frontend.v" \
    "${ROOT}/rtl/DUT/meyr_integer_cfo_fft_frontend_top.v" \
    "${ROOT}/ip/fft256_xilinx/sim/fft256_xilinx_r8.vhd" \
    "${ROOT}/tb/p3_25b_real_fft_ip_tb.sv" \
    "${ROOT}/vectors/meyr_pss_fft_romhex.txt" \
    "${ROOT}/vectors/meyr_sss_fft_romhex.txt"; do
    if [[ -f "$f" ]]; then
        echo "  [OK]   $(basename "$f")"
    else
        echo "  [MISS] $f"
        BLOCKED=1
    fi
done
for tag in k0 kp1 km1 kp2 km2 kp4 km4 kp8 km8; do
    f="${ROOT}/golden/p3_09_sweep/case_${tag}.mem"
    if [[ -f "$f" ]]; then
        echo "  [OK]   $(basename "$f")"
    else
        echo "  [MISS] $f"; BLOCKED=1
    fi
done
if [[ "${BLOCKED}" -eq 1 ]]; then
    gate_out "OFFICIAL_GATE: BLOCKED_MISSING_FILES"
    exit 1
fi
echo "  All required files present."
echo ""

# ---------------------------------------------------------------------------
# Build area — xelab/xsim run from BUILD; data symlinks mirror ROOT layout
# so $readmemh relative paths resolve correctly.
# ---------------------------------------------------------------------------
BUILD="${LOG_DIR}/xsim_build"
rm -rf "${BUILD}" && mkdir -p "${BUILD}"

VIVADO_DATA="${VIVADO_DIR}/data"

# Create local xsim.ini with absolute paths
sed "s|\$RDI_DATADIR|${VIVADO_DATA}|g" \
    "${VIVADO_DATA}/xsim/xsim.ini" > "${BUILD}/xsim.ini"

# Symlink data directories so $readmemh relative paths work from BUILD dir
ln -sfn "${ROOT}/golden"  "${BUILD}/golden"
ln -sfn "${ROOT}/vectors" "${BUILD}/vectors"

# ---------------------------------------------------------------------------
echo "=== [V1] Compile VHDL (fft256_xilinx_r8.vhd → xil_defaultlib) ==="
(cd "${BUILD}" && \
xvhdl --nolog --initfile "${BUILD}/xsim.ini" \
    -work xil_defaultlib \
    "${ROOT}/ip/fft256_xilinx/sim/fft256_xilinx_r8.vhd" \
) 2>&1 | tee "${COMPILE_LOG}"
if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    gate_out "OFFICIAL_GATE: BLOCKED_COMPILE_ERROR"
    echo "  VHDL compile failed. See ${COMPILE_LOG}"
    exit 1
fi
echo "  VHDL compile: OK"
echo ""

# ---------------------------------------------------------------------------
echo "=== [V2] Compile Verilog DUT + TB ==="
(cd "${BUILD}" && \
xvlog --nolog --sv \
    "${ROOT}/rtl/DUT/peak_detector.v" \
    "${ROOT}/rtl/DUT/meyr_pss_sss_product_gen.v" \
    "${ROOT}/rtl/DUT/meyr_integer_cfo_core.v" \
    "${ROOT}/rtl/DUT/meyr_integer_cfo_freq_estimator_top.v" \
    "${ROOT}/rtl/DUT/fft256_xilinx_wrapper.v" \
    "${ROOT}/rtl/DUT/fft256_dual_symbol_frontend.v" \
    "${ROOT}/rtl/DUT/meyr_integer_cfo_fft_frontend_top.v" \
    "${ROOT}/tb/p3_25b_real_fft_ip_tb.sv" \
) 2>&1 | tee -a "${COMPILE_LOG}"
if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    gate_out "OFFICIAL_GATE: BLOCKED_COMPILE_ERROR"
    echo "  Verilog compile failed. See ${COMPILE_LOG}"
    exit 1
fi
echo "  Verilog compile: OK"
echo ""

# ---------------------------------------------------------------------------
echo "=== [V3] Elaborate ==="
ELAB_LOG="${LOG_DIR}/p3_25b_elab.log"
(cd "${BUILD}" && \
xelab --nolog --initfile "${BUILD}/xsim.ini" \
    -L work -L xil_defaultlib -L xfft_v9_1_8 \
    --snapshot p3_25b_snap \
    work.p3_25b_real_fft_ip_tb \
) 2>&1 | tee "${ELAB_LOG}"
if [[ ${PIPESTATUS[0]} -ne 0 ]] || ! grep -q "Built simulation snapshot" "${ELAB_LOG}"; then
    gate_out "OFFICIAL_GATE: BLOCKED_ELAB_ERROR"
    echo "  Elaboration failed. See ${ELAB_LOG}"
    exit 1
fi
echo "  Elaborate: OK"
echo ""

# ---------------------------------------------------------------------------
echo "=== [V4] Simulate ==="
(cd "${BUILD}" && \
xsim --nolog p3_25b_snap \
    --runall \
    --onerror quit \
) 2>&1 | tee "${SIM_LOG}"
SIM_EXIT=${PIPESTATUS[0]}
echo ""

# ---------------------------------------------------------------------------
# Parse result
# ---------------------------------------------------------------------------
if grep -q "OFFICIAL_GATE: PASS" "${SIM_LOG}"; then
    GATE_RESULT="OFFICIAL_GATE: PASS (real Xilinx FFT IP, Vivado xsim — $(date '+%Y-%m-%d'))"
elif grep -q "OFFICIAL_GATE: FAIL" "${SIM_LOG}"; then
    GATE_RESULT="OFFICIAL_GATE: FAIL"
elif [[ "${SIM_EXIT}" -ne 0 ]]; then
    GATE_RESULT="OFFICIAL_GATE: BLOCKED_SIM_ERROR"
else
    GATE_RESULT="OFFICIAL_GATE: FAIL (no gate line found)"
fi

gate_out "${GATE_RESULT}"
echo "  Sim log:  ${SIM_LOG}"
echo "  Gate log: ${GATE_LOG}"

if [[ "${GATE_RESULT}" == *"PASS"* ]]; then
    exit 0
else
    exit 1
fi
