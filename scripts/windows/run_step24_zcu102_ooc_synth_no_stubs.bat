@echo off
REM ============================================================================
REM run_step24_zcu102_ooc_synth_no_stubs.bat
REM Step 24 OOC Synthesis for ZCU102 — real CORDIC/NCO RTL, no stubs
REM ============================================================================
REM  Run from Windows PowerShell or CMD in C:\RTL_SYNC:
REM    cd C:\RTL_SYNC
REM    scripts\windows\run_step24_zcu102_ooc_synth_no_stubs.bat
REM
REM  Prerequisites:
REM    - Vivado 2022.2 installed at C:\Xilinx\Vivado\2022.2
REM    - C:\RTL_SYNC mirrors the WSL workspace /home/zealatan/RTL_SYNC
REM    - Must be run on Windows (NOT from WSL)
REM    - Step 23 RTL is in place:
REM        rtl/cordic_atan2.v  (synthesizable CORDIC pipeline, no $atan2/real)
REM        rtl/nco_phase_gen.v (synthesizable ROM NCO, no $sin/$cos/real)
REM ============================================================================

echo ============================================================
echo Step 24: ZCU102 OOC Synthesis — No Stubs
echo Target:  frac_cfo_frame_corrector_top
echo Part:    xczu9eg-ffvb1156-2-e
echo Vivado:  2022.2
echo Stubs:   NONE (real rtl/cordic_atan2.v + rtl/nco_phase_gen.v)
echo ============================================================

REM Verify we are in C:\RTL_SYNC
if not exist "scripts\step24_synth_check_no_stubs.tcl" (
    echo ERROR: scripts\step24_synth_check_no_stubs.tcl not found.
    echo Make sure you are running from C:\RTL_SYNC
    exit /b 1
)

REM Verify Vivado exists
if not exist "C:\Xilinx\Vivado\2022.2\bin\vivado.bat" (
    echo ERROR: Vivado not found at C:\Xilinx\Vivado\2022.2\bin\vivado.bat
    echo Install Vivado 2022.2 or update the path in this batch file.
    exit /b 1
)

REM Verify real RTL is present (not stubs)
if not exist "rtl\cordic_atan2.v" (
    echo ERROR: rtl\cordic_atan2.v not found.
    exit /b 1
)
if not exist "rtl\nco_phase_gen.v" (
    echo ERROR: rtl\nco_phase_gen.v not found.
    exit /b 1
)

REM Refuse to continue if the script accidentally references stubs
findstr /i "synth_stubs" scripts\step24_synth_check_no_stubs.tcl >nul 2>&1
if %ERRORLEVEL% == 0 (
    echo ERROR: scripts\step24_synth_check_no_stubs.tcl references synth_stubs.
    echo This script must use real RTL only. Fix the TCL script.
    exit /b 1
)

REM Create reports directory if needed
if not exist "reports" mkdir reports

echo INFO: Starting Vivado synthesis in batch mode (no stubs)...
echo INFO: Console output will be saved to reports\step24_synth_messages.log
echo.

C:\Xilinx\Vivado\2022.2\bin\vivado.bat ^
    -mode batch ^
    -source scripts\step24_synth_check_no_stubs.tcl ^
    -log    reports\step24_synth_messages.log ^
    -journal reports\step24_synth.jou

set VIVADO_RC=%ERRORLEVEL%

echo.
echo ============================================================
if %VIVADO_RC% == 0 (
    echo Step 24 synthesis: COMPLETED ^(no stubs^)
    echo Reports written to reports\
    echo   step24_synth_utilization.rpt
    echo   step24_timing_summary.rpt
    echo   step24_drc.rpt
    echo   step24_synth_messages.log
) else (
    echo Step 24 synthesis: FAILED  ^(Vivado exit code = %VIVADO_RC%^)
    echo Check reports\step24_synth_messages.log for errors.
)
echo ============================================================
echo.
echo NOTE: This script must be run on Windows.
echo       Do not run from WSL - Vivado license is Windows-only.
echo.
echo To copy reports back to WSL after a successful run:
echo   From WSL: cp /mnt/c/RTL_SYNC/reports/step24_*.rpt /home/zealatan/RTL_SYNC/reports/
echo             cp /mnt/c/RTL_SYNC/reports/step24_synth_messages.log /home/zealatan/RTL_SYNC/reports/

exit /b %VIVADO_RC%
