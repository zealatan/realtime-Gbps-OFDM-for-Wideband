@echo off
REM ============================================================================
REM run_step28_build_bitstream_xsa.bat
REM Step 28: ZCU102 Synthesis, Implementation, Bitstream, and XSA Export
REM
REM Run from C:\RTL_SYNC:
REM   cd C:\RTL_SYNC
REM   .\scripts\windows\run_step28_build_bitstream_xsa.bat
REM
REM Prereq: Step 27 project must exist at:
REM   vivado\step27_zcu102_bd\step27_zcu102_bd.xpr
REM
REM Outputs:
REM   outputs\step28\sync_phase1_bd_wrapper.bit
REM   outputs\step28\sync_phase1_bd_wrapper.xsa
REM   reports\step28\step28_build.log
REM ============================================================================

setlocal enabledelayedexpansion

set VIVADO=C:\Xilinx\Vivado\2022.2\bin\vivado.bat
set TCL_SCRIPT=scripts\vivado\step28_build_bitstream_xsa.tcl
set RPTS=reports\step28
set OUT=outputs\step28
set LOG=%RPTS%\step28_build.log
set JOU=%RPTS%\step28_build.jou

REM ---- Preflight checks -------------------------------------------------------

if not exist "%VIVADO%" (
    echo ERROR: Vivado not found at %VIVADO%
    echo        Install Vivado 2022.2 or update the VIVADO variable in this batch file.
    exit /b 1
)

if not exist "%TCL_SCRIPT%" (
    echo ERROR: Tcl script not found: %TCL_SCRIPT%
    echo        Ensure you are running from C:\RTL_SYNC
    exit /b 1
)

if not exist "vivado\step27_zcu102_bd\step27_zcu102_bd.xpr" (
    echo ERROR: Step 27 project not found: vivado\step27_zcu102_bd\step27_zcu102_bd.xpr
    echo        Run run_step27_create_zcu102_bd_no_ila.bat first.
    exit /b 1
)

REM ---- Create output directories -----------------------------------------------

if not exist "%RPTS%" mkdir "%RPTS%"
if not exist "%OUT%"  mkdir "%OUT%"

REM ---- Run Vivado --------------------------------------------------------------

echo ============================================================
echo Step 28: ZCU102 Synthesis + Implementation + Bitstream + XSA
echo Vivado:  %VIVADO%
echo Tcl:     %TCL_SCRIPT%
echo Log:     %LOG%
echo ============================================================
echo.

"%VIVADO%" -mode batch ^
    -source %TCL_SCRIPT% ^
    -log    %LOG% ^
    -journal %JOU%

set VIVADO_EXIT=%ERRORLEVEL%

echo.
if %VIVADO_EXIT% neq 0 (
    echo ============================================================
    echo Step 28 FAILED  (Vivado exit code %VIVADO_EXIT%)
    echo Check log: %LOG%
    echo ============================================================
    exit /b %VIVADO_EXIT%
)

echo ============================================================
echo Step 28 COMPLETE.
echo.
echo Bitstream: %OUT%\sync_phase1_bd_wrapper.bit
echo XSA:       %OUT%\sync_phase1_bd_wrapper.xsa
echo Log:       %LOG%
echo.
echo Copy outputs back to WSL:
echo   cp /mnt/c/RTL_SYNC/outputs/step28/sync_phase1_bd_wrapper.bit ^
echo      /home/zealatan/RTL_SYNC/outputs/step28/
echo   cp /mnt/c/RTL_SYNC/outputs/step28/sync_phase1_bd_wrapper.xsa ^
echo      /home/zealatan/RTL_SYNC/outputs/step28/
echo   cp /mnt/c/RTL_SYNC/reports/step28/*.rpt ^
echo      /home/zealatan/RTL_SYNC/reports/step28/
echo   cp /mnt/c/RTL_SYNC/reports/step28/step28_build.log ^
echo      /home/zealatan/RTL_SYNC/reports/step28/
echo ============================================================

endlocal
exit /b 0
