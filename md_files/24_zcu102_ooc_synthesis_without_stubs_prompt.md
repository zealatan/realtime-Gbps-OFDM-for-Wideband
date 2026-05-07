# Step 24 Prompt — ZCU102 OOC Synthesis Without CORDIC/NCO Stubs

Before executing this step, save this full prompt to:

md_files/24_zcu102_ooc_synthesis_without_stubs_prompt.md

If that file already exists, save this prompt as:

md_files/24_zcu102_ooc_synthesis_without_stubs_prompt_v2.md

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

This is a WSL documentation/script-preparation step plus optional Windows execution handoff step.
Do not run implementation or bitstream generation in this step.

Project context:

This project implements an AI-assisted RTL design and verification flow for an OFDM synchronizer subsystem.

Roadmap:

Phase 1 = Functional FPGA synchronizer.
Phase 2 = 1 sample/clock streaming synchronizer.
Phase 3 = multi-sample/clock parallel synchronizer.

The current design belongs to Phase 1.

Phase 1 does not require a continuous 1 sample/clock streaming architecture.
The current design is a frame-buffered, FSM-controlled synchronizer intended for functional FPGA bring-up and debug visibility.

Completed steps:

Step 20 — frac_cfo_frame_corrector_top integration

Result:

PASS = 39
FAIL = 0
CI gate = PASSED

Step 21 — Randomized Verification Campaign for frac_cfo_frame_corrector_top

Result:

PASS = 176
FAIL = 0
Randomized trials = 30
CI gate = PASSED
RTL modified = No at that step

Step 22 — ZCU102 OOC Synthesis With Temporary CORDIC/NCO Stubs

Result:

Windows Vivado 2022.2 OOC synthesis on ZCU102 target passed using synthesis stubs.

Target:

Board = ZCU102
Part = xczu9eg-ffvb1156-2-e
Top = frac_cfo_frame_corrector_top
Clock port = aclk
Clock target = 100 MHz

Step 22 finding:

The hierarchy excluding behavioral CORDIC/NCO synthesized successfully on ZCU102.
However, Step 22 used synthesis stubs for:

scripts/synth_stubs/cordic_atan2_stub.v
scripts/synth_stubs/nco_phase_gen_stub.v

Step 23 — Replace Simulation-Only CORDIC/NCO with Synthesizable RTL

Result:

rtl/cordic_atan2.v was rewritten as a synthesizable 15-stage CORDIC vectoring pipeline.
rtl/nco_phase_gen.v is synthesizable ROM-based RTL.

Module simulation results:

cordic_atan2_tb: PASS = 38, FAIL = 0
nco_phase_gen_tb: PASS = 33, FAIL = 0

Integration simulation result:

frac_cfo_frame_corrector_top: PASS = 176, FAIL = 0, CI gate = PASSED

Important:

The Step 22 synthesis stubs are no longer supposed to be needed.

Step 24 goal:

Re-run ZCU102 OOC synthesis using the real RTL implementations:

rtl/cordic_atan2.v
rtl/nco_phase_gen.v

Do not use:

scripts/synth_stubs/cordic_atan2_stub.v
scripts/synth_stubs/nco_phase_gen_stub.v

The goal is to confirm that the full real RTL hierarchy synthesizes on ZCU102 without blackboxes.

Target:

Board = ZCU102
Part = xczu9eg-ffvb1156-2-e
Top = frac_cfo_frame_corrector_top
Clock port = aclk
Clock target = 100 MHz
Clock period = 10.000 ns
Vivado = Windows Vivado 2022.2

Important:

Use aclk, not clk.
Do not create bitstream.
Do not run implementation.
Do not run Vitis.
Do not add AXI-Lite.
Do not add DMA.
Do not add BRAM preload/readback wrapper.
Do not add FFT.
Do not add integer CFO.
Do not implement int_cfo_estimator.v.
Do not start Phase 2.

Allowed files to create or modify:

scripts/step24_synth_check_no_stubs.tcl
scripts/windows/run_step24_zcu102_ooc_synth_no_stubs.bat
docs/step24_zcu102_ooc_synthesis_without_stubs.md
reports/step24_synth_utilization.rpt, if generated or copied back later
reports/step24_timing_summary.rpt, if generated or copied back later
reports/step24_drc.rpt, if generated or copied back later
reports/step24_synth_messages.log, if generated or copied back later
ai_context/current_status.md
md_files/24_zcu102_ooc_synthesis_without_stubs_prompt.md, or _v2 if needed
md_files/README.md, if needed

You may create reports/ if missing.

Do not modify by default:

rtl/frac_cfo_frame_corrector_top.v
rtl/cordic_atan2.v
rtl/nco_phase_gen.v
other RTL modules
testbenches
scripts/step22_synth_check.tcl
scripts/synth_stubs/
unrelated files

If RTL modification is absolutely necessary due to a real synthesis blocker, first document:

exact synthesis error or warning
file and line number
root cause
why it blocks synthesis
minimal patch required
impact on Step 23 module and integration simulations

Then apply only the minimal fix and rerun:

scripts/run_cordic_atan2_sim.sh
scripts/run_nco_phase_gen_sim.sh
scripts/run_frac_cfo_frame_corrector_top_sim.sh

Required task 1 — Create no-stub Vivado TCL script

Create:

scripts/step24_synth_check_no_stubs.tcl

The TCL script must:

Create a temporary or in-memory Vivado project.
Target part xczu9eg-ffvb1156-2-e.
Read all real RTL sources required by frac_cfo_frame_corrector_top.
Include rtl/cordic_atan2.v.
Include rtl/nco_phase_gen.v.
Do not read scripts/synth_stubs/*.v.
Set top module to frac_cfo_frame_corrector_top.
Create 100 MHz clock on aclk.

Use:

create_clock -period 10.000 [get_ports aclk]

Do not use clk.

Run synth_design only.
Generate reports:

reports/step24_synth_utilization.rpt
reports/step24_timing_summary.rpt
reports/step24_drc.rpt
reports/step24_synth_messages.log

Check/report whether blackboxes remain.

At minimum, the TCL should report blackboxes using commands such as:

report_blackbox
or equivalent Vivado commands if available.

If report_blackbox is unavailable, use another method such as inspecting blackbox cells or reporting cell usage and document the limitation.

Exit non-zero if synthesis fails.

The TCL should be executable from Windows Vivado in C:\RTL_SYNC using relative paths.

Required task 2 — Create Windows batch runner

Create:

scripts/windows/run_step24_zcu102_ooc_synth_no_stubs.bat

The batch file must:

Be intended for Windows execution from C:\RTL_SYNC.
Call:

C:\Xilinx\Vivado\2022.2\bin\vivado.bat

Run Vivado in batch mode with:

scripts/step24_synth_check_no_stubs.tcl

Save console output to:

reports/step24_synth_messages.log

if possible.

Return non-zero if Vivado fails.
Print a clear final status.

Expected Windows command:

cd C:\RTL_SYNC
scripts\windows\run_step24_zcu102_ooc_synth_no_stubs.bat

Required task 3 — Documentation

Create:

docs/step24_zcu102_ooc_synthesis_without_stubs.md

The document must include:

Step 24 goal
Phase 1 context
Step 22 stub-based synthesis summary
Step 23 synthesizable CORDIC/NCO summary
Why no-stub synthesis is required
Target board and part
Clock port and target clock
WSL/Windows execution split
TCL script description
Windows batch runner description
Real RTL source list
Explicit statement that synth_stubs are not used
Synthesis execution status
Utilization summary, if reports are available
Timing summary, if reports are available
DRC summary, if reports are available
Blackbox status, if available
FPGA-readiness conclusion
Recommended Step 25

If Windows synthesis has not yet been run from this session, clearly state:

Synthesis execution status: Prepared, pending Windows Vivado run.

Do not report fake utilization/timing numbers.

Required task 4 — Update current status

Update:

ai_context/current_status.md

Add Step 24 status.

If only scripts are prepared and Windows synthesis has not been run yet, use:

Step 24 status: Prepared, pending Windows Vivado execution.

Include:

prompt archive path
files created
target board
target part
clock port
Windows batch command
whether reports are available
whether synthesis has actually run
whether stubs are used
recommended user action

Recommended user action if not run:

Run on Windows:

cd C:\RTL_SYNC
scripts\windows\run_step24_zcu102_ooc_synth_no_stubs.bat

Recommended Step 25 if synthesis passes:

Step 25 — AXI-Lite + AXI-Stream debug/config wrapper.

Recommended Step 25 if synthesis fails:

Step 25 — Fix no-stub synthesis blocker while preserving Step 23 simulation behavior.

Required task 5 — Optional sanity simulation

Before or after creating synthesis scripts, optionally re-run:

scripts/run_cordic_atan2_sim.sh
scripts/run_nco_phase_gen_sim.sh
scripts/run_frac_cfo_frame_corrector_top_sim.sh

Expected:

cordic_atan2_tb PASS = 38, FAIL = 0
nco_phase_gen_tb PASS = 33, FAIL = 0
frac_cfo_frame_corrector_top PASS = 176, FAIL = 0

If runtime is too long, at least verify current logs or document that simulation was not rerun.

Final report format:

Step 24 preparation complete.

Prompt archive:

saved prompt path: ...

Files changed:

...

Workspace:

WSL workspace:
Windows workspace:

Target:

board:
part:
top:
clock port:
clock target:

Scripts prepared:

TCL:
Windows batch:

Stub usage:

uses scripts/synth_stubs: Yes/No
real rtl/cordic_atan2.v included: Yes/No
real rtl/nco_phase_gen.v included: Yes/No

Simulation sanity:

cordic_atan2:
nco_phase_gen:
frac_cfo_frame_corrector_top:

Windows execution:

status: Not run from this session / Run completed
command to run:
cd C:\RTL_SYNC
scripts\windows\run_step24_zcu102_ooc_synth_no_stubs.bat

Synthesis result:

PASSED/FAILED/NOT RUN
first blocking error, if any:
critical warnings:
DRC issues:
blackboxes remaining:

Timing:

WNS:
TNS:
unconstrained paths:
timing pass at 100 MHz:

Utilization:

LUT:
FF:
BRAM:
DSP:

RTL modified:

Yes/No
If yes, explain exactly why.

Recommended next action:

...

Important constraints:

Do not add AXI-Lite.
Do not add DMA.
Do not add BRAM preload/readback wrapper.
Do not add FFT.
Do not add integer CFO.
Do not implement int_cfo_estimator.v.
Do not create bitstream.
Do not run implementation.
Do not run Vitis.
Do not start Phase 2.
Keep this step focused only on no-stub ZCU102 OOC synthesis readiness.
