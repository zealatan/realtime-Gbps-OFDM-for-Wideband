@echo off
REM ============================================================================
REM run_step27_create_zcu102_bd_no_ila.bat
REM Step 27: ZCU102 Vivado Block Design — frac_cfo_sync_bram_test_wrapper
REM No ILA | No DMA | No implementation | No bitstream
REM ============================================================================
REM  Run from Windows PowerShell or CMD in C:\RTL_SYNC:
REM    cd C:\RTL_SYNC
REM    scripts\windows\run_step27_create_zcu102_bd_no_ila.bat
REM
REM  Prerequisites:
REM    - Vivado 2022.2 installed at C:\Xilinx\Vivado\2022.2
REM    - C:\RTL_SYNC mirrors the WSL workspace /home/zealatan/RTL_SYNC
REM    - Must be run on Windows (NOT from WSL)
REM    - RTL from Step 26 is in place:
REM        rtl\frac_cfo_sync_bram_test_wrapper.v
REM        rtl\frac_cfo_frame_corrector_top.v
REM        rtl\cordic_atan2.v  (synthesizable, no $atan2/real)
REM        rtl\nco_phase_gen.v (synthesizable, no $sin/$cos/real)
REM
REM  Output:
REM    vivado\step27_zcu102_bd\  — Vivado project
REM    reports\step27\step27_create_bd.log — console log
REM    reports\step27\step27_create_bd.jou — journal
REM ============================================================================

echo ============================================================
echo Step 27: ZCU102 Block Design (No ILA)
echo Target:  frac_cfo_sync_bram_test_wrapper
echo Part:    xczu9eg-ffvb1156-2-e
echo Vivado:  2022.2
echo BD name: sync_phase1_bd
echo ============================================================

REM Verify we are in C:\RTL_SYNC
if not exist "scripts\vivado\step27_create_zcu102_bd_no_ila.tcl" (
    echo ERROR: scripts\vivado\step27_create_zcu102_bd_no_ila.tcl not found.
    echo Make sure you are running from C:\RTL_SYNC
    exit /b 1
)

REM Verify Vivado is present
if not exist "C:\Xilinx\Vivado\2022.2\bin\vivado.bat" (
    echo ERROR: Vivado not found at C:\Xilinx\Vivado\2022.2\bin\vivado.bat
    echo Install Vivado 2022.2 or update the path in this batch file.
    exit /b 1
)

REM Verify required RTL files
if not exist "rtl\frac_cfo_sync_bram_test_wrapper.v" (
    echo ERROR: rtl\frac_cfo_sync_bram_test_wrapper.v not found.
    exit /b 1
)
if not exist "rtl\frac_cfo_frame_corrector_top.v" (
    echo ERROR: rtl\frac_cfo_frame_corrector_top.v not found.
    exit /b 1
)
if not exist "rtl\cordic_atan2.v" (
    echo ERROR: rtl\cordic_atan2.v not found.
    exit /b 1
)
if not exist "rtl\nco_phase_gen.v" (
    echo ERROR: rtl\nco_phase_gen.v not found.
    exit /b 1
)

REM Guard: refuse if script references synth_stubs (safety check)
findstr /i "synth_stubs" scripts\vivado\step27_create_zcu102_bd_no_ila.tcl >nul 2>&1
if %ERRORLEVEL% == 0 (
    echo ERROR: Tcl script references synth_stubs. Step 27 must use real RTL only.
    exit /b 1
)

REM Create reports directory
if not exist "reports\step27" mkdir reports\step27

REM Create vivado project directory (Tcl will also mkdir, belt-and-suspenders)
if not exist "vivado\step27_zcu102_bd" mkdir vivado\step27_zcu102_bd

echo INFO: Starting Vivado batch mode...
echo INFO: Log: reports\step27\step27_create_bd.log
echo.

C:\Xilinx\Vivado\2022.2\bin\vivado.bat ^
    -mode batch ^
    -source scripts\vivado\step27_create_zcu102_bd_no_ila.tcl ^
    -log     reports\step27\step27_create_bd.log ^
    -journal reports\step27\step27_create_bd.jou

set VIVADO_RC=%ERRORLEVEL%

echo.
echo ============================================================
if %VIVADO_RC% == 0 (
    echo Step 27 block design: COMPLETED
    echo.
    echo Outputs:
    echo   vivado\step27_zcu102_bd\step27_zcu102_bd.xpr  -- Vivado project
    echo   reports\step27\step27_create_bd.log           -- Console log
    echo.
    echo Open project in Vivado GUI to inspect the block design:
    echo   C:\Xilinx\Vivado\2022.2\bin\vivado.bat vivado\step27_zcu102_bd\step27_zcu102_bd.xpr
) else (
    echo Step 27 block design: FAILED  (Vivado exit code = %VIVADO_RC%^)
    echo Check reports\step27\step27_create_bd.log for errors.
    echo.
    echo Common causes:
    echo   - Board files not installed (non-fatal, PS auto-configured manually)
    echo   - AXI interface inference failed for frac_cfo_sync_bram_test_wrapper
    echo   - SmartConnect / PS AXI port name mismatch for Vivado 2022.2
    echo   - IP catalog not up to date (run Tools > Manage IP > Update IP Catalog)
)
echo ============================================================
echo.
echo NOTE: This script must be run on Windows.
echo       Vivado license is Windows-only. Do NOT run from WSL.
echo.
echo To copy reports back to WSL after a successful run:
echo   From WSL:
echo     cp /mnt/c/RTL_SYNC/reports/step27/step27_create_bd.log \
echo        /home/zealatan/RTL_SYNC/reports/step27/
echo.
echo Recommended Step 28 (after Step 27 succeeds):
echo   Run synthesis + implementation + bitstream + XSA export
echo   using scripts\windows\run_step28_synth_impl_bitstream.bat (TBD)

exit /b %VIVADO_RC%
