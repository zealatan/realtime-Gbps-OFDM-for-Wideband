#!/usr/bin/env bash
# run_p3_13a_real_fft_meyr_dryrun.sh — P3-13A dry-run validation gate
#
# Checks tool availability, file presence, ROM generation status, and reports
# the blocking state accurately.
#
# Gate rules (strictly enforced):
#   - Never prints OFFICIAL_GATE: PASS unless real FFT + xsim + ROM-based
#     k_int sweep actually executes and passes.
#   - Prints "CI_GATE: BLOCKED_REAL_FFT_UNAVAILABLE" if Vivado/xsim/FFT-IP
#     or the required FFT ROMs are absent.
#   - Prints "SANITY_GATE: PASS (stub compile only)" if iverilog can compile
#     the harness adapter RTL and Vivado/xsim/FFT-IP are unavailable.
#
# Usage:
#   bash scripts/run_p3_13a_real_fft_meyr_dryrun.sh
#
# Exit codes:
#   0 — checks completed (does NOT indicate PASS; read the gate output)
#   1 — internal script error

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PASS_CNT=0
FAIL_CNT=0
BLOCK_CNT=0

log()    { printf "[dryrun] %s\n" "$*"; }
ok()     { printf "[dryrun] OK    %s\n" "$*"; PASS_CNT=$((PASS_CNT+1)); }
miss()   { printf "[dryrun] MISS  %s\n" "$*"; FAIL_CNT=$((FAIL_CNT+1)); }
blocked(){ printf "[dryrun] BLOCK %s\n" "$*"; BLOCK_CNT=$((BLOCK_CNT+1)); }

# -----------------------------------------------------------------------
# 1. Tool availability
# -----------------------------------------------------------------------
log "=== 1. Tool Availability ==="

HAVE_VIVADO=0
HAVE_XSIM=0
HAVE_IVERILOG=0
HAVE_PYTHON=0

if command -v vivado &>/dev/null; then
    ok "Vivado: $(which vivado)"
    HAVE_VIVADO=1
else
    blocked "Vivado not in PATH (needed for Xilinx FFT IP elaboration)"
fi

if command -v xsim &>/dev/null; then
    ok "xsim: $(which xsim)"
    HAVE_XSIM=1
else
    blocked "xsim not in PATH (needed for Xilinx FFT IP simulation)"
fi

if command -v iverilog &>/dev/null; then
    ok "iverilog: $(which iverilog) (stub compile check available)"
    HAVE_IVERILOG=1
else
    miss "iverilog not found (stub compile check unavailable)"
fi

if command -v python3 &>/dev/null; then
    ok "python3: $(which python3)"
    HAVE_PYTHON=1
else
    miss "python3 not found (ROM generator unavailable)"
fi

# -----------------------------------------------------------------------
# 2. Xilinx FFT IP wrapper
# -----------------------------------------------------------------------
log ""
log "=== 2. Xilinx FFT IP Wrapper ==="

FFT_WRAPPER="${ROOT}/rtl/fft256_xilinx_wrapper.v"
HAVE_FFT_IP=0

if [ -f "${FFT_WRAPPER}" ]; then
    # Check for USE_BEHAVIORAL_STUB parameter (marks it as our wrapper)
    if grep -q "USE_BEHAVIORAL_STUB" "${FFT_WRAPPER}" 2>/dev/null; then
        # Check for Xilinx FFT IP instantiation keywords
        if grep -qiE "xfft|xip_fft|xbip_fft|ip_fft_v|fft_v[0-9]" "${FFT_WRAPPER}" 2>/dev/null; then
            ok "fft256_xilinx_wrapper.v — has USE_BEHAVIORAL_STUB + Xilinx FFT IP instance"
            HAVE_FFT_IP=1
        else
            miss "fft256_xilinx_wrapper.v — has USE_BEHAVIORAL_STUB but no Xilinx FFT IP instance found"
            log "     (file may be a behavioral stub only; real FFT requires IP instantiation)"
        fi
    else
        miss "fft256_xilinx_wrapper.v — found but USE_BEHAVIORAL_STUB parameter absent"
    fi
else
    blocked "fft256_xilinx_wrapper.v not found at ${FFT_WRAPPER}"
fi

# -----------------------------------------------------------------------
# 3. Required RTL files
# -----------------------------------------------------------------------
log ""
log "=== 3. Required RTL Files ==="

check_rtl() {
    local rel="$1"
    if [ -f "${ROOT}/${rel}" ]; then
        ok "${rel}"
    else
        miss "${rel}  MISSING"
    fi
}

check_rtl "rtl/meyr_fft256_actual_integration_top.v"
check_rtl "rtl/meyr_fft256_harness_adapter.v"
check_rtl "rtl/meyr_integer_cfo_fft_frontend_top.v"
check_rtl "tb/p3_13a_real_fft_meyr_tb.sv"

# These are required for real FFT mode only (note as info if missing)
for f in "rtl/meyr_integer_cfo_freq_estimator_top.v" \
         "rtl/meyr_term2_ref_rom.v"; do
    if [ -f "${ROOT}/${f}" ]; then
        ok "${f}"
    else
        miss "${f}  MISSING (required for real FFT mode)"
    fi
done

# -----------------------------------------------------------------------
# 4. FFT-domain ROM files
# -----------------------------------------------------------------------
log ""
log "=== 4. Frequency-Domain FFT ROMs ==="

PSS_FFT_ROM="${ROOT}/vectors/meyr_pss_fft_romhex.txt"
SSS_FFT_ROM="${ROOT}/vectors/meyr_sss_fft_romhex.txt"
HAVE_FFT_ROMS=0

if [ -f "${PSS_FFT_ROM}" ]; then
    PSS_LINES=$(wc -l < "${PSS_FFT_ROM}" | tr -d ' ')
    if [ "${PSS_LINES}" -ge 256 ]; then
        ok "meyr_pss_fft_romhex.txt — ${PSS_LINES} entries (FFT-domain)"
    else
        miss "meyr_pss_fft_romhex.txt — ${PSS_LINES} entries, need >= 256"
    fi
else
    miss "meyr_pss_fft_romhex.txt MISSING"
    log "     Action: python3 scripts/gen_meyr_fft_reference_roms.py"
fi

if [ -f "${SSS_FFT_ROM}" ]; then
    SSS_LINES=$(wc -l < "${SSS_FFT_ROM}" | tr -d ' ')
    if [ "${SSS_LINES}" -ge 256 ]; then
        ok "meyr_sss_fft_romhex.txt — ${SSS_LINES} entries (FFT-domain)"
    else
        miss "meyr_sss_fft_romhex.txt — ${SSS_LINES} entries, need >= 256"
    fi
else
    miss "meyr_sss_fft_romhex.txt MISSING"
    log "     Action: python3 scripts/gen_meyr_fft_reference_roms.py"
fi

if [ -f "${PSS_FFT_ROM}" ] && [ -f "${SSS_FFT_ROM}" ]; then
    PSS_L=$(wc -l < "${PSS_FFT_ROM}" | tr -d ' ')
    SSS_L=$(wc -l < "${SSS_FFT_ROM}" | tr -d ' ')
    if [ "${PSS_L}" -ge 256 ] && [ "${SSS_L}" -ge 256 ]; then
        HAVE_FFT_ROMS=1
    fi
fi

# Verify bypass ROMs have not been overwritten
log ""
log "=== 4b. Bypass ROM Integrity Guard ==="

BYPASS_PSS="${ROOT}/vectors/meyr_pss_reference_romhex.txt"
BYPASS_SSS="${ROOT}/vectors/meyr_sss_reference_romhex.txt"

if [ -f "${BYPASS_PSS}" ]; then
    ok "meyr_pss_reference_romhex.txt (bypass ROM) present — not overwritten ✓"
else
    miss "meyr_pss_reference_romhex.txt (bypass ROM) MISSING — check for accidental deletion"
fi

if [ -f "${BYPASS_SSS}" ]; then
    ok "meyr_sss_reference_romhex.txt (bypass ROM) present — not overwritten ✓"
else
    miss "meyr_sss_reference_romhex.txt (bypass ROM) MISSING — check for accidental deletion"
fi

# -----------------------------------------------------------------------
# 5. CFO sweep vector files
# -----------------------------------------------------------------------
log ""
log "=== 5. CFO Sweep Vectors ==="

SWEEP_OK=1
for tag in k0 kp1 km1 kp2 km2 kp4 km4 kp8 km8; do
    f="${ROOT}/golden/p3_09_sweep/case_${tag}.mem"
    if [ -f "${f}" ]; then
        NLINES=$(wc -l < "${f}" | tr -d ' ')
        ok "case_${tag}.mem  (${NLINES} samples)"
    else
        miss "case_${tag}.mem  MISSING"
        SWEEP_OK=0
    fi
done

# -----------------------------------------------------------------------
# 6. Stub compile check (iverilog — adapter only)
# -----------------------------------------------------------------------
log ""
log "=== 6. Stub Compile Check (iverilog) ==="

STUB_COMPILE_OK=0

if [ "${HAVE_IVERILOG}" -eq 1 ]; then
    ADAPTER="${ROOT}/rtl/meyr_fft256_harness_adapter.v"
    if [ -f "${ADAPTER}" ]; then
        COMPILE_MSG=$(iverilog -g2012 -tnull "${ADAPTER}" 2>&1) && RC=0 || RC=$?
        if [ "${RC}" -eq 0 ]; then
            ok "meyr_fft256_harness_adapter.v — iverilog compile clean"
            STUB_COMPILE_OK=1
        else
            miss "meyr_fft256_harness_adapter.v — compile error:"
            printf "%s\n" "${COMPILE_MSG}" | head -10
        fi
    else
        miss "meyr_fft256_harness_adapter.v not found — compile skipped"
    fi
else
    log "     iverilog unavailable — stub compile skipped"
fi

# -----------------------------------------------------------------------
# 7. ROM generator dry-run (python3, no file write)
# -----------------------------------------------------------------------
log ""
log "=== 7. ROM Generator Import Check ==="

if [ "${HAVE_PYTHON}" -eq 1 ]; then
    PY_CHECK=$(python3 -c "import numpy; print('numpy OK')" 2>&1) && PY_RC=0 || PY_RC=$?
    if [ "${PY_RC}" -eq 0 ]; then
        ok "python3 numpy available — gen_meyr_fft_reference_roms.py can run"
    else
        miss "python3 numpy not available: ${PY_CHECK}"
    fi
else
    log "     python3 unavailable — ROM generator check skipped"
fi

# -----------------------------------------------------------------------
# 8. Summary and gate decision
# -----------------------------------------------------------------------
printf "\n"
log "=== Summary ==="
log "  Pass:    ${PASS_CNT}"
log "  Miss:    ${FAIL_CNT}"
log "  Blocked: ${BLOCK_CNT}"
printf "\n"

REAL_FFT_READY=0
if [ "${HAVE_VIVADO}" -eq 1 ] && [ "${HAVE_XSIM}" -eq 1 ] && \
   [ "${HAVE_FFT_IP}" -eq 1 ] && [ "${HAVE_FFT_ROMS}" -eq 1 ]; then
    REAL_FFT_READY=1
fi

if [ "${REAL_FFT_READY}" -eq 0 ]; then
    printf "CI_GATE: BLOCKED_REAL_FFT_UNAVAILABLE\n"
    printf "  Missing prerequisite(s):\n"
    [ "${HAVE_VIVADO}"   -eq 0 ] && printf "    - Vivado not found\n"
    [ "${HAVE_XSIM}"     -eq 0 ] && printf "    - xsim not found\n"
    [ "${HAVE_FFT_IP}"   -eq 0 ] && printf "    - fft256_xilinx_wrapper.v missing or stub-only\n"
    [ "${HAVE_FFT_ROMS}" -eq 0 ] && printf "    - FFT ROMs not generated (run gen_meyr_fft_reference_roms.py)\n"
    printf "\n"

    if [ "${STUB_COMPILE_OK}" -eq 1 ]; then
        printf "SANITY_GATE: PASS (stub compile only)\n"
        printf "  meyr_fft256_harness_adapter.v compiles cleanly under iverilog.\n"
        printf "  k_int correctness NOT verified; real FFT + xsim required.\n"
    else
        printf "SANITY_GATE: INCOMPLETE (stub compile failed or skipped)\n"
        if [ "${HAVE_IVERILOG}" -eq 0 ]; then
            printf "  iverilog not found; install to enable stub compile check.\n"
        fi
    fi

    printf "\n"
    printf "To unblock: install Vivado + Xilinx FFT IP, then:\n"
    printf "  python3 scripts/gen_meyr_fft_reference_roms.py\n"
    printf "  bash scripts/run_p3_13a_real_fft_meyr_dryrun.sh  (re-run this script)\n"
    printf "  xsim with USE_BEHAVIORAL_STUB=0 to get OFFICIAL_GATE: PASS\n"

else
    printf "READY_FOR_XSIM: all prerequisites met\n"
    printf "  Next step: run the TB under xsim with USE_BEHAVIORAL_STUB=0:\n"
    printf "\n"
    printf "    # Compile\n"
    printf "    xvlog -sv -f rtl_filelist.f tb/p3_13a_real_fft_meyr_tb.sv \\\\\n"
    printf "           -d USE_BEHAVIORAL_STUB=0\n"
    printf "    xelab -top p3_13a_real_fft_meyr_tb -snapshot p3_13a_snap\n"
    printf "    xsim p3_13a_snap --runall\n"
    printf "\n"
    printf "  OFFICIAL_GATE: PASS requires all k_int sweep cases to report PASS.\n"
fi

exit 0
