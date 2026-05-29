#!/usr/bin/env bash
# run_session_B_p3_13c_real_fft_ip_xsim.sh — P3-13C Official Xilinx xsim Runner
#
# DESCRIPTION
#   Runs the real Xilinx FFT IP k_int sweep using Vivado xsim (Vivado 2023.1
#   installed on Windows, invoked via WSL2 cmd.exe interop).
#
#   Source files live on the WSL2 filesystem.  All compilation and simulation
#   execute in a Windows-local working directory (default: C:\temp\p3_13c_xsim_work)
#   to avoid cmd.exe UNC-path limitations.
#
# GATE OUTPUT (exactly one of these is emitted):
#   OFFICIAL_GATE: PASS             all 9 k_int sweep cases pass, real Xilinx IP
#   OFFICIAL_GATE: FAIL             simulation ran but ≥1 case failed
#   OFFICIAL_GATE: BLOCKED_XSIM_UNAVAILABLE    Vivado/xsim not found
#   OFFICIAL_GATE: BLOCKED_FFT_IP_MISSING      IP not generated; run create IP step
#   OFFICIAL_GATE: BLOCKED_COMPILE_ERROR       xvlog/xelab failed
#   OFFICIAL_GATE: BLOCKED_SIM_ERROR           xsim terminated abnormally
#
# NEVER prints OFFICIAL_GATE: PASS from the behavioral DFT fallback.
#
# PREREQUISITES
#   1. Vivado 2023.1 at C:\Xilinx\Vivado\2023.1 (accessible as WSL /mnt/c/...)
#   2. FFT IP generated:
#        bash scripts/run_session_B_p3_13c_real_fft_ip_xsim.sh --gen-ip-only
#      OR run Vivado manually:
#        cd C:\temp\p3_13c_xsim_work
#        C:\Xilinx\Vivado\2023.1\bin\vivado.bat -mode batch \
#          -source create_fft256_xilinx_ip.tcl -nolog -nojournal \
#          -tclargs C:\temp\p3_13c_xsim_work\ip
#   3. vectors/ and golden/p3_09_sweep/ present in project root.
#
# USAGE
#   bash scripts/run_session_B_p3_13c_real_fft_ip_xsim.sh [OPTIONS]
#
#   Options:
#     --gen-ip-only      Run Vivado IP generation only, then exit (no simulation)
#     --skip-ip-gen      Skip IP generation even if ip/ is missing (assume present)
#     --win-work DIR     Override Windows work directory (default: C:\temp\p3_13c_xsim_work)
#     --log-dir DIR      Override WSL log directory (default: sim_out/p3_13c)
#     --vivado-ver VER   Override Vivado version (default: 2023.1)
#
# EXIT CODES
#   0  — OFFICIAL_GATE: PASS
#   1  — OFFICIAL_GATE: FAIL or BLOCKED_*

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
GEN_IP_ONLY=0
SKIP_IP_GEN=0
WIN_WORK_WIN="C:\\temp\\p3_13c_xsim_work"
WIN_WORK_WSL="/mnt/c/temp/p3_13c_xsim_work"
LOG_DIR="${ROOT}/sim_out/p3_13c"
VIVADO_VER="2023.1"
VIVADO_BAT_WIN="C:\\Xilinx\\Vivado\\${VIVADO_VER}\\bin\\vivado.bat"
XVLOG_BAT_WIN="C:\\Xilinx\\Vivado\\${VIVADO_VER}\\bin\\xvlog.bat"
XVHDL_BAT_WIN="C:\\Xilinx\\Vivado\\${VIVADO_VER}\\bin\\xvhdl.bat"
XELAB_BAT_WIN="C:\\Xilinx\\Vivado\\${VIVADO_VER}\\bin\\xelab.bat"
XSIM_BAT_WIN="C:\\Xilinx\\Vivado\\${VIVADO_VER}\\bin\\xsim.bat"
CMD_EXE="/mnt/c/Windows/System32/cmd.exe"
SNAP_NAME="p3_13c_real_fft_snap"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --gen-ip-only)   GEN_IP_ONLY=1 ;;
        --skip-ip-gen)   SKIP_IP_GEN=1 ;;
        --win-work)      shift; WIN_WORK_WIN="$1"; WIN_WORK_WSL="/mnt/${1//\\/\//}" ;;
        --log-dir)       shift; LOG_DIR="$1" ;;
        --vivado-ver)    shift; VIVADO_VER="$1" ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
    shift
done

mkdir -p "${LOG_DIR}"
GATE_LOG="${LOG_DIR}/p3_13c_gate.txt"
SIM_LOG="${LOG_DIR}/p3_13c_xsim_console.log"
COMPILE_LOG="${LOG_DIR}/p3_13c_compile.log"

gate_out() {
    local msg="$1"
    echo ""
    echo "========================================================================"
    echo "${msg}"
    echo "========================================================================"
    echo "${msg}" > "${GATE_LOG}"
}

# ---------------------------------------------------------------------------
# 1. Tool availability check
# ---------------------------------------------------------------------------
echo "========================================================================"
echo "P3-13C Real Xilinx FFT IP xsim Runner"
echo "  Date       : $(date '+%Y-%m-%d %H:%M:%S')"
echo "  Project    : ${ROOT}"
echo "  Win work   : ${WIN_WORK_WIN}"
echo "  Vivado ver : ${VIVADO_VER}"
echo "========================================================================"

VIVADO_WSL="/mnt/c/Xilinx/Vivado/${VIVADO_VER}"
if [[ ! -d "${VIVADO_WSL}" ]]; then
    gate_out "OFFICIAL_GATE: BLOCKED_XSIM_UNAVAILABLE"
    echo "  Vivado ${VIVADO_VER} not found at ${VIVADO_WSL}"
    echo "  Install Vivado and configure WIN_WORK accordingly."
    exit 1
fi

if [[ ! -f "${CMD_EXE}" ]]; then
    gate_out "OFFICIAL_GATE: BLOCKED_XSIM_UNAVAILABLE"
    echo "  cmd.exe not found at ${CMD_EXE} (WSL2 interop required)"
    exit 1
fi

echo ""
echo "  [OK] Vivado found: ${VIVADO_WSL}"
echo "  [OK] cmd.exe found: ${CMD_EXE}"

# ---------------------------------------------------------------------------
# Helper: run a Windows cmd.exe batch command from the work directory
# ---------------------------------------------------------------------------
run_win() {
    local desc="$1"
    local cmd="$2"
    echo ""
    echo "--- ${desc} ---"
    echo "  cmd: ${cmd}"
    "${CMD_EXE}" /c "cd /d ${WIN_WORK_WIN} && ${cmd}" 2>&1
    return $?
}

# ---------------------------------------------------------------------------
# 2. Required file check (WSL side)
# ---------------------------------------------------------------------------
echo ""
echo "--- Required WSL source files ---"
BLOCKED=0
for f in \
    "rtl/fft256_xilinx_wrapper.v" \
    "rtl/meyr_fft256_harness_adapter.v" \
    "rtl/meyr_fft256_actual_integration_top.v" \
    "rtl/meyr_integer_cfo_freq_estimator_top.v" \
    "rtl/meyr_integer_cfo_core.v" \
    "rtl/meyr_pss_sss_product_gen.v" \
    "rtl/peak_detector.v" \
    "tb/p3_13a_real_fft_meyr_tb.sv" \
    "vectors/meyr_pss_fft_romhex.txt" \
    "vectors/meyr_sss_fft_romhex.txt"; do
    if [[ -f "${ROOT}/${f}" ]]; then
        echo "  [OK]   ${f}"
    else
        echo "  [MISS] ${f} — MISSING"
        BLOCKED=1
    fi
done
for tag in k0 kp1 km1 kp2 km2 kp4 km4 kp8 km8; do
    f="golden/p3_09_sweep/case_${tag}.mem"
    if [[ -f "${ROOT}/${f}" ]]; then
        echo "  [OK]   ${f}"
    else
        echo "  [MISS] ${f} — MISSING"; BLOCKED=1
    fi
done
if [[ "${BLOCKED}" -eq 1 ]]; then
    gate_out "OFFICIAL_GATE: BLOCKED_FFT_IP_MISSING"
    echo "  Missing source files (see above)"
    exit 1
fi

# ---------------------------------------------------------------------------
# 3. Stage source files to Windows work directory
# ---------------------------------------------------------------------------
echo ""
echo "--- Staging files to Windows work dir ---"
mkdir -p "${WIN_WORK_WSL}"
mkdir -p "${WIN_WORK_WSL}/golden/p3_09_sweep"
mkdir -p "${WIN_WORK_WSL}/vectors"
mkdir -p "${WIN_WORK_WSL}/ip"

# RTL and TB sources
for f in \
    "rtl/fft256_xilinx_wrapper.v" \
    "rtl/meyr_fft256_harness_adapter.v" \
    "rtl/meyr_fft256_actual_integration_top.v" \
    "rtl/meyr_integer_cfo_freq_estimator_top.v" \
    "rtl/meyr_integer_cfo_core.v" \
    "rtl/meyr_pss_sss_product_gen.v" \
    "rtl/peak_detector.v" \
    "tb/p3_13a_real_fft_meyr_tb.sv"; do
    cp "${ROOT}/${f}" "${WIN_WORK_WSL}/"
    echo "  staged: $(basename ${f})"
done

# ROM and sweep vectors (relative paths used by $readmemh in simulation)
cp "${ROOT}/vectors/meyr_pss_fft_romhex.txt"  "${WIN_WORK_WSL}/vectors/"
cp "${ROOT}/vectors/meyr_sss_fft_romhex.txt"  "${WIN_WORK_WSL}/vectors/"
for tag in k0 kp1 km1 kp2 km2 kp4 km4 kp8 km8; do
    cp "${ROOT}/golden/p3_09_sweep/case_${tag}.mem" "${WIN_WORK_WSL}/golden/p3_09_sweep/"
done
echo "  staged: ROMs + sweep vectors"

# TCL script for IP generation
cp "${ROOT}/scripts/create_fft256_xilinx_ip.tcl" "${WIN_WORK_WSL}/"
echo "  staged: create_fft256_xilinx_ip.tcl"

# ---------------------------------------------------------------------------
# 4. Create thin SystemVerilog wrapper to override USE_BEHAVIORAL_STUB=0
#    (xelab parameter override is unreliable for Verilog; wrapper is robust)
# ---------------------------------------------------------------------------
cat > "${WIN_WORK_WSL}/p3_13c_real_fft_top.sv" << 'VWRAP'
`timescale 1ns/1ps
// Thin wrapper: forces USE_BEHAVIORAL_STUB=0 for xsim run.
// Only the parameter default is changed; all DUT logic is in p3_13a_real_fft_meyr_tb.
module p3_13c_real_fft_top;
    p3_13a_real_fft_meyr_tb #(.USE_BEHAVIORAL_STUB(0)) tb_inst();
endmodule
VWRAP
echo "  staged: p3_13c_real_fft_top.sv (USE_BEHAVIORAL_STUB=0 wrapper)"

# ---------------------------------------------------------------------------
# 5. FFT IP generation (skip if already exists)
# ---------------------------------------------------------------------------
IP_SIM_DIR="${WIN_WORK_WSL}/ip/fft256_xilinx/sim"
IP_XCI="${WIN_WORK_WSL}/ip/fft256_xilinx/fft256_xilinx.xci"

echo ""
echo "--- FFT IP status ---"
if [[ -d "${IP_SIM_DIR}" ]] && [[ -n "$(ls ${IP_SIM_DIR}/*.v 2>/dev/null)" ]]; then
    echo "  [OK] IP simulation files already present: ${IP_SIM_DIR}"
elif [[ "${SKIP_IP_GEN}" -eq 1 ]]; then
    gate_out "OFFICIAL_GATE: BLOCKED_FFT_IP_MISSING"
    echo "  --skip-ip-gen set but IP sim files not found at ${IP_SIM_DIR}"
    echo "  Run without --skip-ip-gen to generate the IP first."
    exit 1
else
    echo "  IP simulation files not found — running Vivado generate_target..."
    echo "  (This takes ~5-15 minutes on first run.)"
    echo ""
    VIVADO_CMD="${VIVADO_BAT_WIN} -mode batch -source create_fft256_xilinx_ip.tcl -nolog -nojournal -tclargs ${WIN_WORK_WIN}\\ip"
    run_win "Vivado IP generation" "${VIVADO_CMD}" 2>&1 | tee "${LOG_DIR}/p3_13c_vivado_ip_gen.log"
    VIVGEN_RC=${PIPESTATUS[0]}
    if [[ ${VIVGEN_RC} -ne 0 ]]; then
        gate_out "OFFICIAL_GATE: BLOCKED_FFT_IP_MISSING"
        echo "  Vivado IP generation failed (rc=${VIVGEN_RC})"
        echo "  See ${LOG_DIR}/p3_13c_vivado_ip_gen.log"
        exit 1
    fi
fi

# Confirm IP sim files now exist
if [[ ! -d "${IP_SIM_DIR}" ]]; then
    gate_out "OFFICIAL_GATE: BLOCKED_FFT_IP_MISSING"
    echo "  Expected IP sim dir not found: ${IP_SIM_DIR}"
    echo "  Run: vivado.bat -mode batch -source create_fft256_xilinx_ip.tcl"
    echo "       -tclargs ${WIN_WORK_WIN}\\ip"
    exit 1
fi

# Collect IP simulation files
IP_VLOG_FILES=$(find "${IP_SIM_DIR}" -name "*.v" 2>/dev/null | sort)
IP_VHDL_FILES=$(find "${IP_SIM_DIR}" -name "*.vhd" -o -name "*.vhdl" 2>/dev/null | sort)
IP_VLOG_BASE=$(find "${IP_SIM_DIR}" -name "*.v" -exec basename {} \; 2>/dev/null | sort | tr '\n' ' ')
IP_VHDL_BASE=$(find "${IP_SIM_DIR}" -name "*.vhd" -exec basename {} \; 2>/dev/null | sort | tr '\n' ' ')

echo "  IP Verilog sim files : ${IP_VLOG_BASE}"
echo "  IP VHDL sim files    : ${IP_VHDL_BASE}"

# Stage IP sim files to Windows work dir (flat)
for f in $IP_VHDL_FILES $IP_VLOG_FILES; do
    cp "$f" "${WIN_WORK_WSL}/" 2>/dev/null && echo "  staged IP: $(basename $f)"
done

if [[ "${GEN_IP_ONLY}" -eq 1 ]]; then
    echo ""
    echo "  --gen-ip-only: IP generation complete. Re-run without --gen-ip-only to simulate."
    exit 0
fi

# ---------------------------------------------------------------------------
# 6. Compile — VHDL first (xfft behavioral model), then Verilog + SV
# ---------------------------------------------------------------------------
echo ""
echo "--- Step 1: Compile VHDL IP model (xvhdl) ---"

# Build Windows-side VHDL file list (flat copy in WIN_WORK_WIN)
WIN_VHDL_FILES=""
for f in $IP_VHDL_FILES; do
    WIN_VHDL_FILES="${WIN_VHDL_FILES} $(basename $f)"
done

if [[ -n "${WIN_VHDL_FILES}" ]]; then
    XVHDL_CMD="${XVHDL_BAT_WIN} -nolog -work xil_defaultlib ${WIN_VHDL_FILES}"
    run_win "xvhdl (VHDL IP model)" "${XVHDL_CMD}" 2>&1 | tee -a "${COMPILE_LOG}"
    XVHDL_RC=${PIPESTATUS[0]}
    if [[ ${XVHDL_RC} -ne 0 ]]; then
        gate_out "OFFICIAL_GATE: BLOCKED_COMPILE_ERROR"
        echo "  xvhdl failed (rc=${XVHDL_RC}). See ${COMPILE_LOG}"
        exit 1
    fi
else
    echo "  No VHDL IP files found — IP may be Verilog-only."
fi

echo ""
echo "--- Step 2: Compile Verilog IP wrapper + project RTL (xvlog) ---"

# Build Verilog source list
WIN_VLOG_RTL="fft256_xilinx_wrapper.v meyr_fft256_harness_adapter.v meyr_fft256_actual_integration_top.v meyr_integer_cfo_freq_estimator_top.v meyr_integer_cfo_core.v meyr_pss_sss_product_gen.v peak_detector.v"

# Add any Verilog IP wrapper files
WIN_VLOG_IP="${IP_VLOG_BASE}"

# Testbench (SystemVerilog) — compiled separately
WIN_TB_SV="p3_13a_real_fft_meyr_tb.sv p3_13c_real_fft_top.sv"

# Compile Verilog: IP wrapper + RTL
if [[ -n "${WIN_VLOG_IP}" ]]; then
    XVLOG_IP_CMD="${XVLOG_BAT_WIN} -nolog -sv -work xil_defaultlib ${WIN_VLOG_IP}"
    run_win "xvlog (IP Verilog)" "${XVLOG_IP_CMD}" 2>&1 | tee -a "${COMPILE_LOG}"
    XVLOG_IP_RC=${PIPESTATUS[0]}
    if [[ ${XVLOG_IP_RC} -ne 0 ]]; then
        gate_out "OFFICIAL_GATE: BLOCKED_COMPILE_ERROR"
        echo "  xvlog IP compile failed (rc=${XVLOG_IP_RC}). See ${COMPILE_LOG}"
        exit 1
    fi
fi

XVLOG_RTL_CMD="${XVLOG_BAT_WIN} -nolog -sv -work xil_defaultlib ${WIN_VLOG_RTL}"
run_win "xvlog (RTL)" "${XVLOG_RTL_CMD}" 2>&1 | tee -a "${COMPILE_LOG}"
XVLOG_RTL_RC=${PIPESTATUS[0]}
if [[ ${XVLOG_RTL_RC} -ne 0 ]]; then
    gate_out "OFFICIAL_GATE: BLOCKED_COMPILE_ERROR"
    echo "  xvlog RTL compile failed (rc=${XVLOG_RTL_RC}). See ${COMPILE_LOG}"
    exit 1
fi

XVLOG_TB_CMD="${XVLOG_BAT_WIN} -nolog -sv -work xil_defaultlib ${WIN_TB_SV}"
run_win "xvlog (testbench + wrapper)" "${XVLOG_TB_CMD}" 2>&1 | tee -a "${COMPILE_LOG}"
XVLOG_TB_RC=${PIPESTATUS[0]}
if [[ ${XVLOG_TB_RC} -ne 0 ]]; then
    gate_out "OFFICIAL_GATE: BLOCKED_COMPILE_ERROR"
    echo "  xvlog TB compile failed (rc=${XVLOG_TB_RC}). See ${COMPILE_LOG}"
    exit 1
fi

# ---------------------------------------------------------------------------
# 7. Elaborate
# ---------------------------------------------------------------------------
echo ""
echo "--- Step 3: Elaborate (xelab) ---"

XELAB_CMD="${XELAB_BAT_WIN} -nolog --debug all -snapshot ${SNAP_NAME} xil_defaultlib.p3_13c_real_fft_top"
run_win "xelab" "${XELAB_CMD}" 2>&1 | tee "${LOG_DIR}/p3_13c_xelab.log"
XELAB_RC=${PIPESTATUS[0]}
if [[ ${XELAB_RC} -ne 0 ]]; then
    gate_out "OFFICIAL_GATE: BLOCKED_COMPILE_ERROR"
    echo "  xelab failed (rc=${XELAB_RC}). See ${LOG_DIR}/p3_13c_xelab.log"
    exit 1
fi

# ---------------------------------------------------------------------------
# 8. Simulate
# ---------------------------------------------------------------------------
echo ""
echo "--- Step 4: Simulate (xsim --runall) ---"

# Windows path for xsim log (relative to WIN_WORK_WIN)
WIN_SIM_LOG="p3_13c_xsim.log"
WSL_SIM_LOG="${WIN_WORK_WSL}/${WIN_SIM_LOG}"

XSIM_CMD="${XSIM_BAT_WIN} ${SNAP_NAME} --runall --log ${WIN_SIM_LOG}"
run_win "xsim" "${XSIM_CMD}" 2>&1 | tee -a "${SIM_LOG}"
XSIM_RC=${PIPESTATUS[0]}

# Also save the xsim log from the Windows work dir
if [[ -f "${WSL_SIM_LOG}" ]]; then
    cp "${WSL_SIM_LOG}" "${SIM_LOG}"
    echo "  xsim log saved: ${SIM_LOG}"
fi

if [[ ${XSIM_RC} -ne 0 ]]; then
    echo "  xsim exited with non-zero rc=${XSIM_RC} (timeout or error)"
fi

# ---------------------------------------------------------------------------
# 9. Gate evaluation
# ---------------------------------------------------------------------------
echo ""
echo "--- Gate evaluation ---"

# Check for OFFICIAL_GATE: PASS in xsim console output
if grep -q "OFFICIAL_GATE: PASS" "${SIM_LOG}" 2>/dev/null || \
   grep -q "OFFICIAL_GATE: PASS" "${WIN_WORK_WSL}/p3_13c_xsim.log" 2>/dev/null; then
    gate_out "OFFICIAL_GATE: PASS"
    echo "  All 9 k_int sweep cases passed under real Xilinx FFT IP + xsim."
    echo ""
    grep -E '^\[TB\] PASS' "${SIM_LOG}" 2>/dev/null || \
    grep -E '^\[TB\] PASS' "${WIN_WORK_WSL}/p3_13c_xsim.log" 2>/dev/null || true
    exit 0
elif grep -q "OFFICIAL_GATE: FAIL" "${SIM_LOG}" 2>/dev/null; then
    gate_out "OFFICIAL_GATE: FAIL"
    echo "  Simulation ran but case(s) failed."
    grep -E '^\[TB\] (PASS|FAIL)' "${SIM_LOG}" 2>/dev/null || true
    exit 1
else
    gate_out "OFFICIAL_GATE: BLOCKED_SIM_ERROR"
    echo "  xsim did not produce a gate result string."
    echo "  Check ${SIM_LOG} for simulation errors."
    exit 1
fi
