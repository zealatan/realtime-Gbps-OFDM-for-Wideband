@echo off
REM =============================================================================
REM run_step28c_export_xsa_with_bitstream.bat
REM Step 28C: Export XSA with embedded bitstream (Vivado 2022.2, Windows)
REM
REM Run from repository root:
REM   cd C:\RTL_SYNC
REM   .\scripts\windows\run_step28c_export_xsa_with_bitstream.bat
REM
REM Prerequisites:
REM   - Vivado 2022.2 installed at C:\Xilinx\Vivado\2022.2\
REM   - Step 27 block design project exists:
REM       vivado\step27_zcu102_bd\step27_zcu102_bd.xpr
REM     If not, run:
REM       .\scripts\windows\run_step27_create_zcu102_bd_no_ila.bat
REM
REM Key difference from Step 28:
REM   impl_1 is launched with -to_step write_bitstream so that
REM   write_hw_platform -include_bit can locate the run-managed BIT file.
REM
REM Output:
REM   outputs\step28\sync_phase1_bd_wrapper_with_bit.xsa
REM =============================================================================

setlocal enabledelayedexpansion

REM ---------------------------------------------------------------------------
REM Vivado path
REM ---------------------------------------------------------------------------
set VIVADO_BAT=C:\Xilinx\Vivado\2022.2\bin\vivado.bat

if not exist "%VIVADO_BAT%" (
    echo ERROR: Vivado 2022.2 not found at %VIVADO_BAT%
    echo        Install Vivado 2022.2 or update the path in this script.
    exit /b 1
)
echo INFO: Vivado found: %VIVADO_BAT%

REM ---------------------------------------------------------------------------
REM Verify Step 27 project exists
REM ---------------------------------------------------------------------------
set PROJ=vivado\step27_zcu102_bd\step27_zcu102_bd.xpr

if not exist "%PROJ%" (
    echo ERROR: Step 27 project not found: %PROJ%
    echo        Run Step 27 first:
    echo        .\scripts\windows\run_step27_create_zcu102_bd_no_ila.bat
    exit /b 1
)
echo INFO: Step 27 project found: %PROJ%

REM ---------------------------------------------------------------------------
REM Create output directories
REM ---------------------------------------------------------------------------
if not exist "reports\step28c" mkdir "reports\step28c"
if not exist "outputs\step28"  mkdir "outputs\step28"
echo INFO: Output directories ready.

REM ---------------------------------------------------------------------------
REM Run Vivado batch
REM ---------------------------------------------------------------------------
set TCL_SCRIPT=scripts\vivado\step28c_export_xsa_with_bitstream.tcl
set LOG_FILE=reports\step28c\step28c_export_xsa_with_bitstream.log
set JOU_FILE=reports\step28c\step28c_export_xsa_with_bitstream.jou

echo.
echo ================================================================
echo Step 28C: Export XSA with embedded bitstream
echo Tcl:      %TCL_SCRIPT%
echo Log:      %LOG_FILE%
echo ================================================================
echo.

call "%VIVADO_BAT%" -mode batch ^
    -source "%TCL_SCRIPT%" ^
    -log    "%LOG_FILE%" ^
    -journal "%JOU_FILE%"

set VIVADO_RC=%ERRORLEVEL%

echo.
if %VIVADO_RC% neq 0 (
    echo Vivado exited with code %VIVADO_RC% -- check log:
    echo   %LOG_FILE%
) else (
    echo Vivado batch run complete.
)

REM ---------------------------------------------------------------------------
REM Check for embedded-bitstream XSA
REM ---------------------------------------------------------------------------
set XSA_WITH_BIT=outputs\step28\sync_phase1_bd_wrapper_with_bit.xsa

echo.
if exist "%XSA_WITH_BIT%" (
    echo STEP 28C RESULT: PASS
    echo XSA with embedded bitstream:
    echo   %XSA_WITH_BIT%
    echo.
    echo Recommended Vitis step:
    echo   Open Vitis 2022.2
    echo   File -^> New -^> Platform Project
    echo   XSA: C:\RTL_SYNC\%XSA_WITH_BIT%
    echo   OS: standalone, Processor: psu_cortexa53_0
) else (
    echo STEP 28C RESULT: FAIL
    echo XSA not found: %XSA_WITH_BIT%
    echo Check the Vivado log for the root cause:
    echo   %LOG_FILE%
    echo.
    echo Common causes:
    echo   - write_hw_platform -include_bit failed even with -to_step write_bitstream
    echo   - Timing violation (WNS ^< 0)
    echo   - Synthesis or implementation error
    exit /b 1
)

REM ---------------------------------------------------------------------------
REM Copy instructions for WSL
REM ---------------------------------------------------------------------------
echo.
echo To copy results to WSL:
echo   cp /mnt/c/RTL_SYNC/outputs/step28/sync_phase1_bd_wrapper_with_bit.xsa ^
echo      /home/zealatan/RTL_SYNC/outputs/step28/
echo   cp /mnt/c/RTL_SYNC/reports/step28c/*.rpt ^
echo      /home/zealatan/RTL_SYNC/reports/step28c/
echo   cp /mnt/c/RTL_SYNC/reports/step28c/step28c_export_xsa_with_bitstream.log ^
echo      /home/zealatan/RTL_SYNC/reports/step28c/

endlocal
exit /b 0
