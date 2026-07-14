@echo off
REM run_xsim_full_sync_real_fft_gate.bat
REM Windows launcher for XIP-004 FULL_SYNC_REAL_IP_GATE.
REM Calls the Linux/WSL Vivado xsim flow.
REM
REM Requires:
REM   - Windows Subsystem for Linux (WSL2) with Ubuntu/Debian
REM   - Vivado 2022.2 installed inside WSL at:
REM       /home/zealatan/Downloads/Vivado/2022.2
REM   - Project at: /home/zealatan/RTL_SYNC_PHASE4
REM
REM Gate output (inside WSL):
REM   ~/RTL_SYNC_PHASE4/vivado_xsim/reports/xsim_full_sync_gate.txt
REM   ~/RTL_SYNC_PHASE4/vivado_xsim/logs/xsim_full_sync_sim.log

setlocal

REM -- Configurable paths ----------------------------------------------------
set WSL_DISTRO=
set PROJ_ROOT_WSL=/home/zealatan/RTL_SYNC_PHASE4
set VIVADO_DIR_WSL=/home/zealatan/Downloads/Vivado/2022.2

REM -- Check WSL availability ------------------------------------------------
where wsl.exe >nul 2>&1
if errorlevel 1 (
    echo [ERROR] wsl.exe not found. Install WSL2 from Microsoft Store.
    echo Gate result: BLOCKED_WINDOWS_VIVADO_REQUIRED
    exit /b 1
)

echo ========================================================================
echo  RTL_SYNC_PHASE4 — XIP-004 FULL_SYNC_REAL_IP_GATE (Windows WSL launcher)
echo  Project WSL path : %PROJ_ROOT_WSL%
echo  Vivado WSL path  : %VIVADO_DIR_WSL%
echo ========================================================================
echo.

REM -- WSL command: source Vivado, cd to project, run TCL via vivado batch ---
set WSL_CMD=bash -c "source %VIVADO_DIR_WSL%/settings64.sh ^&^& cd %PROJ_ROOT_WSL% ^&^& vivado -mode batch -source vivado_xsim/tcl/run_xsim_full_sync_real_fft_gate.tcl 2^>^&1 ^| tee vivado_xsim/logs/xsim_full_sync_windows_run.log"

if defined WSL_DISTRO (
    wsl.exe -d %WSL_DISTRO% %WSL_CMD%
) else (
    wsl.exe %WSL_CMD%
)

set EXIT_CODE=%errorlevel%

echo.
echo ========================================================================
if %EXIT_CODE% equ 0 (
    echo  Gate result: PASS_VIVADO_XSIM_REAL_IP
    echo  Details: %PROJ_ROOT_WSL%/vivado_xsim/reports/xsim_full_sync_gate.txt
) else (
    echo  Gate result: FAIL or BLOCKED
    echo  Sim log: %PROJ_ROOT_WSL%/vivado_xsim/logs/xsim_full_sync_sim.log
    echo  Compile: %PROJ_ROOT_WSL%/vivado_xsim/logs/xsim_full_sync_compile.log
)
echo ========================================================================

exit /b %EXIT_CODE%
