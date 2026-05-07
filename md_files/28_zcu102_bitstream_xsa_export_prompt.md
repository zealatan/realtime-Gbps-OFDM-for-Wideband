Step 28 Prompt — ZCU102 Synthesis, Implementation, Bitstream, and XSA Export

Before executing this step, save this full prompt to:

md_files/28_zcu102_bitstream_xsa_export_prompt.md

If that file already exists, save this prompt as:

md_files/28_zcu102_bitstream_xsa_export_prompt_v2.md

At the end of the task, include the saved prompt path in the final report.

Active WSL workspace:

/home/zealatan/RTL_SYNC

Windows mirror workspace:

C:\RTL_SYNC

Workspace guard:

Before modifying any file, run:

pwd
git rev-parse --show-toplevel

You must be inside:

/home/zealatan/RTL_SYNC

Do not modify files under:

/home/zealatan/AI_ORC/messi/VIVADO_MIN_EXAMPLE
/mnt/c/
C:\
any Windows mirror path

This is a WSL script/documentation preparation step plus Windows Vivado execution handoff step.

Actual synthesis, implementation, bitstream generation, and XSA export are performed on Windows Vivado.

Do not run Vivado implementation or bitstream generation from WSL.

Project context:

This project implements an AI-assisted RTL/FPGA development flow for an OFDM synchronizer subsystem.

The current design belongs to Phase 1:

Phase 1 = Functional FPGA synchronizer
Phase 2 = 1 sample/clock streaming synchronizer
Phase 3 = multi-sample/clock parallel synchronizer

Phase 1 goal:

Bring up a frame-buffered, FSM-controlled OFDM synchronizer on ZCU102 using known-vector testing.

Completed steps:

Step 20 — frac_cfo_frame_corrector_top integration
Result: PASS = 39, FAIL = 0

Step 21 — randomized verification campaign
Result: PASS = 176, FAIL = 0

Step 22 — ZCU102 OOC synthesis with temporary CORDIC/NCO stubs
Result: synthesis passed with stubs

Step 23 — synthesizable CORDIC/NCO replacement
Result:
cordic_atan2_tb: PASS = 38, FAIL = 0
nco_phase_gen_tb: PASS = 33, FAIL = 0
frac_cfo_frame_corrector_top_tb: PASS = 176, FAIL = 0

Step 24 — ZCU102 OOC synthesis without stubs
Result:
errors = 0
critical warnings = 0
blackboxes = 0
timing met at 100 MHz
WNS approximately +4.092 ns
DSP48E2 = 17
BRAM = 1 tile / RAMB18 x2

Step 25 — AXI-Lite + AXI-Stream debug/config wrapper
Result:
wrapper testbench: PASS = 23, FAIL = 0
existing top regression: PASS = 176, FAIL = 0

Step 26 — BRAM preload/readback wrapper
Result:
BRAM wrapper: PASS = 23, FAIL = 0
Step 25 regression: PASS = 23, FAIL = 0
existing top regression: PASS = 176, FAIL = 0

Step 27 — ZCU102 Vivado Block Design Integration Without ILA
Result:
local IP packaging: PASS
IP VLNV: zealatan.local:user:frac_cfo_sync_bram_test_wrapper:1.0
BD name: sync_phase1_bd
BD top: sync_phase1_bd_wrapper
ZCU102 board part loaded: PASS
Zynq UltraScale+ PS added: PASS
SmartConnect added: PASS
Processor System Reset added: PASS
wrapper_0 IP added: PASS
PS M_AXI_HPM0_FPD -> SmartConnect -> wrapper_0/s_axi connected: PASS
Address map: wrapper_0 at 0xA0000000, range 64 KB
validate_bd_design: PASS
HDL wrapper generated: PASS
Output products generated: PASS
ILA: not used
DMA: not used
External BRAM IP: not used

Vivado project created at:

C:\RTL_SYNC\vivado\step27_zcu102_bd\step27_zcu102_bd.xpr

Step 28 goal:

Run the Step 27 Vivado Block Design through:

1. Synthesis
2. Implementation
3. Timing report
4. Bitstream generation
5. Hardware platform export, XSA

This is the first full Vivado build for the Phase-1 FPGA known-vector test system.

Target:

Board = ZCU102
Part = xczu9eg-ffvb1156-2-e
Vivado = Windows Vivado 2022.2
Project = vivado/step27_zcu102_bd/step27_zcu102_bd.xpr
BD = sync_phase1_bd
Top = sync_phase1_bd_wrapper
Clock = PS FCLK0 / pl_clk0, nominal 100 MHz
Custom IP base address = 0xA0000000
Custom IP range = 64 KB

Important constraints:

Do not add ILA.
Do not add VIO.
Do not add DMA.
Do not add FFT.
Do not add integer CFO.
Do not implement int_cfo_estimator.v.
Do not create Vitis firmware in this step.
Do not program the board in this step.
Do not start Phase 2.
Do not modify RTL unless absolutely necessary.

This step is only for:

Vivado synthesis
implementation
bitstream generation
XSA export
report collection
documentation

Allowed files to create or modify:

scripts/vivado/step28_build_bitstream_xsa.tcl
scripts/windows/run_step28_build_bitstream_xsa.bat
docs/step28_zcu102_bitstream_xsa_export.md
reports/step28/
outputs/step28/
ai_context/current_status.md
md_files/28_zcu102_bitstream_xsa_export_prompt.md, or _v2 if needed
md_files/README.md, if needed
scripts/windows/README.md, if needed

Expected output files after Windows execution:

outputs/step28/sync_phase1_bd_wrapper.bit
outputs/step28/sync_phase1_bd_wrapper.xsa
reports/step28/step28_build.log
reports/step28/step28_synth_utilization.rpt
reports/step28/step28_synth_timing_summary.rpt
reports/step28/step28_impl_utilization.rpt
reports/step28/step28_timing_summary.rpt
reports/step28/step28_drc.rpt
reports/step28/step28_power.rpt, optional

Do not commit generated Vivado build directories unless specifically required.

Do not commit:

vivado/step27_zcu102_bd/
.Xil/
*.runs/
*.cache/
*.gen/
*.ip_user_files/

Generated bitstream and XSA may be kept under outputs/step28/ if reasonably sized and useful.
If large, document their path but do not commit them.

Do not modify by default:

rtl/*.v
tb/*.sv
existing simulation scripts
existing Step 27 Tcl unless necessary

If RTL or Step 27 project script modification is absolutely necessary, first document:

1. exact Vivado error
2. file and line number
3. root cause
4. why it blocks build
5. minimal patch required
6. impact on Step 26/27 behavior

Then apply only the minimal fix and rerun relevant simulation/regression if RTL changed.

Preferred outcome:

RTL modified = No

Required task 1 — Create Vivado build Tcl

Create:

scripts/vivado/step28_build_bitstream_xsa.tcl

This Tcl script must be intended for Windows Vivado execution from:

C:\RTL_SYNC

The script must:

1. Open the Step 27 Vivado project:

vivado/step27_zcu102_bd/step27_zcu102_bd.xpr

2. Confirm top is:

sync_phase1_bd_wrapper

3. Reset prior synthesis/implementation runs if needed.

4. Launch synthesis.

5. Wait for synthesis completion.

6. Open synthesized design.

7. Generate synthesis reports:

reports/step28/step28_synth_utilization.rpt
reports/step28/step28_synth_timing_summary.rpt

8. Launch implementation.

9. Wait for implementation completion.

10. Open implemented design.

11. Generate implementation reports:

reports/step28/step28_impl_utilization.rpt
reports/step28/step28_timing_summary.rpt
reports/step28/step28_drc.rpt
reports/step28/step28_power.rpt

12. Check timing.

The Tcl should clearly print:

TIMING CHECK: PASS

only if timing is met.

If timing fails, print:

TIMING CHECK: FAIL

and exit non-zero.

13. Write bitstream.

Output:

outputs/step28/sync_phase1_bd_wrapper.bit

14. Export hardware platform XSA.

Use Vivado 2022.2-compatible command.

Preferred:

write_hw_platform -fixed -include_bit -force -file outputs/step28/sync_phase1_bd_wrapper.xsa

If -include_bit is not supported or causes issues, use the correct Vivado 2022.2 syntax and document it.

15. Print final summary:

Step 28 build complete.
Bitstream:
XSA:
Timing:

16. Exit non-zero on synthesis/implementation/bitstream/XSA failure.

Required task 2 — Create Windows batch runner

Create:

scripts/windows/run_step28_build_bitstream_xsa.bat

The batch file must:

1. Be intended for Windows execution from:

C:\RTL_SYNC

2. Call:

C:\Xilinx\Vivado\2022.2\bin\vivado.bat

3. Run Vivado batch mode with:

scripts/vivado/step28_build_bitstream_xsa.tcl

4. Save console output to:

reports/step28/step28_build.log

5. Return non-zero if Vivado fails.

Expected Windows command:

cd C:\RTL_SYNC
.\scripts\windows\run_step28_build_bitstream_xsa.bat

Required task 3 — Documentation

Create:

docs/step28_zcu102_bitstream_xsa_export.md

Document:

1. Step 28 goal
2. Phase 1 context
3. Step 27 BD summary
4. Build target
5. Vivado project path
6. Build Tcl script
7. Windows batch command
8. Synthesis result
9. Implementation result
10. Timing result
11. Utilization summary
12. DRC summary
13. Bitstream output path
14. XSA output path
15. Known warnings
16. Whether ILA/DMA are absent by design
17. Recommended Step 29

If Windows Vivado build has not yet been run from this Claude session, clearly state:

Execution status: Prepared, pending Windows Vivado run.

Do not fake build, timing, bitstream, or XSA results.

Required task 4 — Update current status

Update:

ai_context/current_status.md

Add Step 28 status.

If only scripts are prepared and Windows Vivado has not been run yet, use:

Step 28 status: Prepared, pending Windows Vivado execution.

Include:

- prompt archive path
- files created
- Vivado project path
- BD top
- target board/part
- Windows batch command
- expected bitstream path
- expected XSA path
- whether synthesis has actually run
- whether implementation has actually run
- whether bitstream has actually been generated
- whether XSA has actually been exported
- recommended user action

Recommended user action:

cd C:\RTL_SYNC
.\scripts\windows\run_step28_build_bitstream_xsa.bat

Required task 5 — Optional pre-check

Optionally check that Step 26 simulation still passes:

scripts/run_frac_cfo_sync_bram_test_wrapper_sim.sh

Expected:

PASS = 23
FAIL = 0
CI gate = PASSED

Do not spend excessive time rerunning unrelated regressions unless any RTL changed.

Recommended Step 29 if Step 28 succeeds:

Step 29 — Vitis baremetal control application for known-vector test

Purpose:

Create a Vitis baremetal C application that:

1. writes known IQ samples into the input memory window
2. programs CFG_CFO_STEP, CFG_TIMING_OFFSET, CFG_FRAME_LEN
3. writes INPUT_LEN and OUTPUT_MAX_LEN
4. enables the wrapper
5. writes start_pulse
6. polls STATUS.done_sticky
7. reads INPUT_COUNT and OUTPUT_COUNT
8. reads output memory window
9. prints results over UART
10. optionally compares a small expected subset

Address base:

0xA0000000

Register offsets:

0x0000 CONTROL
0x0004 STATUS
0x0008 CFG_CFO_STEP
0x000C CFG_TIMING_OFFSET
0x0010 CFG_FRAME_LEN
0x0014 INPUT_LEN
0x0018 OUTPUT_MAX_LEN
0x001C INPUT_COUNT
0x0020 OUTPUT_COUNT
0x0024 DEBUG_STATE
0x0028 ERROR_STATUS
0x1000 input memory window
0x2000 output memory window

Final report format:

Step 28 preparation complete.

Prompt archive:
- saved prompt path:

Files changed:
- ...

Workspace:
- WSL workspace:
- Windows workspace:

Target:
- board:
- part:
- Vivado:
- project:
- top:

Scripts prepared:
- Vivado Tcl:
- Windows batch:

Expected outputs:
- bitstream:
- XSA:
- reports:

Execution:
- Windows Vivado run status:
- synthesis:
- implementation:
- timing:
- bitstream:
- XSA export:

RTL modified:
- Yes/No

Recommended Windows command:
- ...

Recommended Step 29:
- ...

If Windows build was actually run, use:

Step 28 complete.

and include:

Synthesis:
- PASS/FAIL

Implementation:
- PASS/FAIL

Timing:
- WNS:
- TNS:
- WHS:
- THS:
- timing met: Yes/No

Utilization:
- LUT:
- FF:
- BRAM:
- DSP:

DRC:
- errors:
- critical warnings:
- warnings:

Generated artifacts:
- bitstream:
- XSA:

Recommended Step 29:
- ...

Important constraints:

Do not add ILA.
Do not add VIO.
Do not add DMA.
Do not add FFT.
Do not add integer CFO.
Do not implement int_cfo_estimator.v.
Do not create Vitis firmware in this step.
Do not program board in this step.
Do not start Phase 2.
Keep this step focused only on Vivado synthesis, implementation, bitstream generation, XSA export, and reporting.
