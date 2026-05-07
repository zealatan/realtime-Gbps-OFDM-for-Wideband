# Step 22 Prompt — Phase-1 Synthesis-Readiness and ZCU102 OOC Vivado Check

## Active WSL workspace

```
/home/zealatan/RTL_SYNC
```

## Windows mirror workspace

```
C:\RTL_SYNC
```

## Workspace guard

Before modifying any file, run:

```
pwd
git rev-parse --show-toplevel
```

You must be inside:

```
/home/zealatan/RTL_SYNC
```

Do not modify files under:

- `/home/zealatan/AI_ORC/messi/VIVADO_MIN_EXAMPLE`
- `/mnt/c/`
- `C:\`
- any Windows mirror path

This is a WSL RTL/documentation/script-preparation step.

## Important environment policy

WSL is used for:
- RTL editing
- testbench editing
- Vivado xsim simulation
- documentation
- prompt archive
- script generation

Windows is used for:
- actual Vivado synthesis
- implementation
- bitstream generation
- Vitis firmware
- ZCU102 board bring-up

Vivado license and Vivado 2022.2 are available on Windows.

Confirmed Windows Vivado command:
```
C:\Xilinx\Vivado\2022.2\bin\vivado.bat -version
```

The Windows workspace is:
```
C:\RTL_SYNC
```

Do not attempt implementation or bitstream generation in this step.

## Project context

This project implements an AI-assisted RTL design and verification flow for an OFDM synchronizer subsystem.

Roadmap:
- Phase 1 = Functional FPGA synchronizer.
- Phase 2 = 1 sample/clock streaming synchronizer.
- Phase 3 = multi-sample/clock parallel synchronizer.

The current design belongs to Phase 1.

Phase 1 does not require a continuous 1 sample/clock streaming architecture. The current design is a frame-buffered, FSM-controlled synchronizer intended for functional FPGA bring-up and debug visibility.

## Completed steps

**Step 20 — frac_cfo_frame_corrector_top integration**
- Current top: `rtl/frac_cfo_frame_corrector_top.v`
- Current testbench: `tb/frac_cfo_frame_corrector_top_tb.sv`
- Step 20 result: PASS = 39, FAIL = 0, CI gate = PASSED

**Step 21 — Randomized Verification Campaign for frac_cfo_frame_corrector_top**
- Step 21 result: PASS = 176, FAIL = 0, Randomized trials = 30, CI gate = PASSED, RTL modified = No
- Step 21 verified: R1–R8 all PASS

## Deferred

- `int_cfo_estimator.v` is deferred.
- Do not implement int_cfo_estimator.v in this step.
- Do not add integer CFO, FFT, PSS, IFFT, or full OFDM RX.

## Step 22 goal

Perform Phase-1 synthesis-readiness check for `rtl/frac_cfo_frame_corrector_top.v`.

The goal is to determine whether the Step 21-verified fractional-CFO frame synchronizer top is synthesizable and suitable for Phase-1 FPGA bring-up on ZCU102.

This step should prepare scripts and documentation in WSL, and provide a Windows Vivado execution flow.

## Target board

- Board: ZCU102
- Part: xczu9eg-ffvb1156-2-e
- Vivado version: 2022.2 on Windows

## Top module

`frac_cfo_frame_corrector_top`

## Clock port

- Port: `aclk` (not `clk`)
- Clock: `create_clock -period 10.000 [get_ports aclk]`
- Target: 100 MHz

## Allowed files to create or modify

- `scripts/step22_synth_check.tcl`
- `scripts/windows/run_step22_zcu102_ooc_synth.bat`
- `scripts/windows/README.md`
- `docs/step22_synthesis_readiness_report.md`
- `reports/step22_synth_utilization.rpt` (if generated or copied back)
- `reports/step22_timing_summary.rpt` (if generated or copied back)
- `reports/step22_drc.rpt` (if generated or copied back)
- `reports/step22_synth_messages.log` (if generated or copied back)
- `ai_context/current_status.md`
- `md_files/22_synthesis_readiness_prompt.md` (or _v2 if needed)
- `md_files/README.md` (if needed)

You may create `scripts/windows/` and `reports/`.

## Required tasks

### Task 1 — Create Vivado TCL synthesis script

Create `scripts/step22_synth_check.tcl`. Must:
- Create temporary/in-memory Vivado project
- Target ZCU102 part: `xczu9eg-ffvb1156-2-e`
- Read all RTL sources required by `frac_cfo_frame_corrector_top`
- Set top module to `frac_cfo_frame_corrector_top`
- Create 100 MHz clock on `aclk` via `create_clock -period 10.000 [get_ports aclk]`
- Run synthesis only (OOC or project mode)
- Generate reports under `reports/`
- Exit with non-zero on failure

### Task 2 — Create Windows batch runner

Create `scripts/windows/run_step22_zcu102_ooc_synth.bat`. Must:
- Call `C:\Xilinx\Vivado\2022.2\bin\vivado.bat` in batch mode
- Run the TCL script
- Save console output to `reports/step22_synth_messages.log`
- Return non-zero if Vivado fails

### Task 3 — Create scripts/windows/README.md

Document WSL/Windows split, Step 22 batch command, and constraints.

### Task 4 — RTL synthesis-readiness audit

Audit all RTL files for: `real`, `shortreal`, `$sin/$cos/$atan/$atan2/$sqrt/$ln`, `$display` in RTL, delay statements, `force/release`, file I/O, latch risk, combinational loop risk, multi-driven nets, non-reset registers.

### Task 5 — Do not run Windows Vivado from WSL

Prepare scripts. State that Windows execution is required.

### Task 6 — Documentation

Create `docs/step22_synthesis_readiness_report.md`.

### Task 7 — Update ai_context/current_status.md

Add Step 22 status (prepared, pending Windows execution).

## Important constraints

Do not implement: int_cfo_estimator.v, integer CFO, FFT, PSS, IFFT, AXI-Lite wrapper, DMA, bitstream, implementation, Vitis, Phase 2.
