@echo off
REM run_xsim_fft_ip_gate.bat
REM Windows launcher for the FFT IP xsim gate.
REM Calls the Linux/WSL flow via wsl.exe.
REM
REM Requires:
REM   - Windows Subsystem for Linux (WSL2) with Ubuntu/Debian
REM   - Vivado 2022.2 installed inside WSL at:
REM       /home/zealatan/Downloads/Vivado/2022.2
REM   - Project checked out at the same WSL path as on Linux
REM
REM Usage:
REM   run_xsim_fft_ip_gate.bat
REM
REM Gate output (inside WSL):
REM   ~/RTL_SYNC_PHASE4/vivado_xsim/reports/xsim_fft_ip_gate.txt
REM   ~/RTL_SYNC_PHASE4/vivado_xsim/reports/xsim_fft_ip_gate.html

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
echo  RTL_SYNC_PHASE4 — FFT IP xsim Gate (Windows WSL launcher)
echo  Project WSL path : %PROJ_ROOT_WSL%
echo  Vivado WSL path  : %VIVADO_DIR_WSL%
echo ========================================================================
echo.

REM -- Build the WSL command -------------------------------------------------
set WSL_CMD=bash -c "source %VIVADO_DIR_WSL%/settings64.sh ^&^& cd %PROJ_ROOT_WSL% ^&^& python3 vivado_xsim/scripts/gen_fft_reference.py ^&^& vivado -mode batch -source vivado_xsim/tcl/run_xsim_fft_ip_gate.tcl 2^>^&1 ^| tee vivado_xsim/logs/windows_run.log ^&^& python3 vivado_xsim/scripts/check_fft_ip_outputs.py"

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
) else (
    echo  Gate result: FAIL or BLOCKED — check WSL log
    echo  Log: %PROJ_ROOT_WSL%/vivado_xsim/logs/windows_run.log
)
echo ========================================================================

exit /b %EXIT_CODE%
