@echo off
setlocal enabledelayedexpansion

REM ========================================================================
REM Step 28C Windows runner
REM
REM Purpose:
REM   Run Vivado batch script that rebuilds implementation to write_bitstream
REM   and exports XSA with embedded bitstream.
REM
REM Important fixes:
REM   1. Deletes stale XSA before run.
REM   2. Checks Vivado exit code.
REM   3. Fails if XSA was not newly generated.
REM   4. Does not print PASS after Vivado failure.
REM ========================================================================

set ROOT=C:\RTL_SYNC
set VIVADO_BAT=C:\Xilinx\Vivado\2022.2\bin\vivado.bat

set TCL=scripts\vivado\step28c_export_xsa_with_bitstream.tcl
set LOG=reports\step28c\step28c_export_xsa_with_bitstream.log
set PROJ=vivado\step27_zcu102_bd\step27_zcu102_bd.xpr
set XSA=outputs\step28\sync_phase1_bd_wrapper_with_bit.xsa

cd /d %ROOT%
if errorlevel 1 (
    echo ERROR: Could not cd to %ROOT%
    exit /b 1
)

echo ================================================================
echo Step 28C: Export XSA with embedded bitstream
echo Root:     %ROOT%
echo Tcl:      %TCL%
echo Log:      %LOG%
echo XSA:      %XSA%
echo ================================================================
echo.

REM ------------------------------------------------------------------------
REM Check Vivado
REM ------------------------------------------------------------------------
if not exist "%VIVADO_BAT%" (
    echo ERROR: Vivado not found:
    echo   %VIVADO_BAT%
    echo.
    echo Edit VIVADO_BAT in this BAT file if Vivado is installed elsewhere.
    exit /b 1
)

echo INFO: Vivado found:
echo   %VIVADO_BAT%

REM ------------------------------------------------------------------------
REM Check project
REM ------------------------------------------------------------------------
if not exist "%PROJ%" (
    echo ERROR: Step 27 project not found:
    echo   %PROJ%
    echo.
    echo Run Step 27 first:
    echo   .\scripts\windows\run_step27_create_zcu102_bd_no_ila.bat
    exit /b 1
)

echo INFO: Step 27 project found:
echo   %PROJ%

REM ------------------------------------------------------------------------
REM Check Tcl
REM ------------------------------------------------------------------------
if not exist "%TCL%" (
    echo ERROR: Tcl script not found:
    echo   %TCL%
    exit /b 1
)

echo INFO: Tcl script found:
echo   %TCL%

REM ------------------------------------------------------------------------
REM Prepare directories
REM ------------------------------------------------------------------------
if not exist reports mkdir reports
if not exist reports\step28c mkdir reports\step28c
if not exist outputs mkdir outputs
if not exist outputs\step28 mkdir outputs\step28

echo INFO: Output directories ready.
echo.

REM ------------------------------------------------------------------------
REM Remove stale XSA before run
REM ------------------------------------------------------------------------
if exist "%XSA%" (
    echo INFO: Removing stale XSA before run:
    echo   %XSA%
    del /f /q "%XSA%"
    if exist "%XSA%" (
        echo ERROR: Failed to remove stale XSA:
        echo   %XSA%
        exit /b 1
    )
)

REM ------------------------------------------------------------------------
REM Run Vivado
REM ------------------------------------------------------------------------
echo ================================================================
echo Running Vivado batch...
echo ================================================================
echo.

"%VIVADO_BAT%" -mode batch -source "%TCL%" -log "%LOG%"

set VIVADO_EXIT=%ERRORLEVEL%

echo.
echo ================================================================
echo Vivado finished with exit code: %VIVADO_EXIT%
echo ================================================================
echo.

if not "%VIVADO_EXIT%"=="0" (
    echo STEP 28C RESULT: FAIL
    echo.
    echo Vivado exited with non-zero code.
    echo Check log:
    echo   %LOG%
    echo.
    echo Useful debug commands:
    echo   Get-Content .\%LOG% -Tail 200
    echo   Get-Content .\vivado\step27_zcu102_bd\step27_zcu102_bd.runs\synth_1\runme.log -Tail 200
    echo   Get-Content .\vivado\step27_zcu102_bd\step27_zcu102_bd.runs\impl_1\runme.log -Tail 200
    exit /b 1
)

REM ------------------------------------------------------------------------
REM Verify XSA was generated
REM ------------------------------------------------------------------------
if not exist "%XSA%" (
    echo STEP 28C RESULT: FAIL
    echo.
    echo Vivado returned success but XSA was not generated:
    echo   %XSA%
    echo.
    echo Check log:
    echo   %LOG%
    exit /b 1
)

REM ------------------------------------------------------------------------
REM Optional: print file size
REM ------------------------------------------------------------------------
for %%F in ("%XSA%") do (
    set XSA_SIZE=%%~zF
)

echo STEP 28C RESULT: PASS
echo.
echo XSA with embedded bitstream:
echo   %XSA%
echo.
echo XSA size:
echo   %XSA_SIZE% bytes
echo.
echo Recommended Vitis step:
echo   Open Vitis 2022.2
echo   File -^> New -^> Platform Project
echo   XSA:
echo     C:\RTL_SYNC\outputs\step28\sync_phase1_bd_wrapper_with_bit.xsa
echo   OS:
echo     standalone
echo   Processor:
echo     psu_cortexa53_0
echo.
echo Done.

exit /b 0