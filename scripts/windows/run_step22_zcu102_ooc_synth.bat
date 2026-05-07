@echo off
REM ============================================================================
REM run_step22_zcu102_ooc_synth.bat — Step 22 OOC Synthesis for ZCU102
REM ============================================================================
REM  Run from Windows PowerShell or CMD in C:\RTL_SYNC:
REM    cd C:\RTL_SYNC
REM    scripts\windows\run_step22_zcu102_ooc_synth.bat
REM
REM  Prerequisites:
REM    - Vivado 2022.2 installed at C:\Xilinx\Vivado\2022.2
REM    - C:\RTL_SYNC mirrors the WSL workspace /home/zealatan/RTL_SYNC
REM    - Must be run on Windows (NOT from WSL)
REM ============================================================================

echo ============================================================
echo Step 22: Phase-1 OOC Synthesis Check for ZCU102
echo Target:  frac_cfo_frame_corrector_top
echo Part:    xczu9eg-ffvb1156-2-e
echo Vivado:  2022.2
echo ============================================================

REM Verify we are in C:\RTL_SYNC
if not exist "scripts\step22_synth_check.tcl" (
    echo ERROR: scripts\step22_synth_check.tcl not found.
    echo Make sure you are running from C:\RTL_SYNC
    exit /b 1
)

REM Verify Vivado exists
if not exist "C:\Xilinx\Vivado\2022.2\bin\vivado.bat" (
    echo ERROR: Vivado not found at C:\Xilinx\Vivado\2022.2\bin\vivado.bat
    echo Install Vivado 2022.2 or update the path in this batch file.
    exit /b 1
)

REM Create reports directory if needed
if not exist "reports" mkdir reports

echo INFO: Starting Vivado synthesis in batch mode...
echo INFO: Console output will be saved to reports\step22_synth_messages.log
echo.

C:\Xilinx\Vivado\2022.2\bin\vivado.bat ^
    -mode batch ^
    -source scripts\step22_synth_check.tcl ^
    -log    reports\step22_synth_messages.log ^
    -journal reports\step22_synth.jou

set VIVADO_RC=%ERRORLEVEL%

echo.
echo ============================================================
if %VIVADO_RC% == 0 (
    echo Step 22 synthesis: COMPLETED
    echo Reports written to reports\
    echo   step22_synth_utilization.rpt
    echo   step22_timing_summary.rpt
    echo   step22_drc.rpt
    echo   step22_clock_interaction.rpt
    echo   step22_synth_messages.log
) else (
    echo Step 22 synthesis: FAILED  (Vivado exit code = %VIVADO_RC%)
    echo Check reports\step22_synth_messages.log for errors.
)
echo ============================================================
echo.
echo NOTE: This script must be run on Windows.
echo       Do not run from WSL — Vivado license is Windows-only.
echo.
echo To copy reports back to WSL:
echo   From WSL: cp /mnt/c/RTL_SYNC/reports/step22_*.rpt /home/zealatan/RTL_SYNC/reports/

exit /b %VIVADO_RC%
