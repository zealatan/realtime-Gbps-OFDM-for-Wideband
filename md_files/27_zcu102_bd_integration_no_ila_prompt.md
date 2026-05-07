Step 27 Prompt — ZCU102 Vivado Block Design Integration Without ILA

Before executing this step, save this full prompt to:

md_files/27_zcu102_bd_integration_no_ila_prompt.md

If that file already exists, save this prompt as:

md_files/27_zcu102_bd_integration_no_ila_prompt_v2.md

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

This step is a WSL script/documentation preparation step plus Windows Vivado execution handoff.

Do not run implementation or bitstream generation in WSL.

Important environment policy:

WSL is used for:

RTL editing
testbench editing
xsim simulation
documentation
prompt archive
script generation

Windows is used for:

Vivado synthesis
Vivado block design execution
implementation
bitstream generation
XSA export
Vitis firmware
ZCU102 board bring-up

Windows Vivado is confirmed:

C:\Xilinx\Vivado\2022.2\bin\vivado.bat

Windows workspace:

C:\RTL_SYNC

Project context:

This project implements an AI-assisted RTL design and verification flow for an OFDM synchronizer subsystem.

Roadmap:

Phase 1 = Functional FPGA synchronizer.
Phase 2 = 1 sample/clock streaming synchronizer.
Phase 3 = multi-sample/clock parallel synchronizer.

The current design belongs to Phase 1.

Completed steps:

Step 20 — frac_cfo_frame_corrector_top integration
Step 21 — randomized verification, PASS = 176, FAIL = 0
Step 22 — ZCU102 OOC synthesis with temporary CORDIC/NCO stubs, PASS
Step 23 — synthesizable CORDIC/NCO replacement, integration PASS = 176
Step 24 — no-stub ZCU102 OOC synthesis, PASS
Step 25 — AXI-Lite + AXI-Stream debug/config wrapper, PASS = 23
Step 26 — BRAM preload/readback wrapper, PASS = 23

Current top for Vivado system integration:

rtl/frac_cfo_sync_bram_test_wrapper.v

Step 26 wrapper summary:

The wrapper exposes one AXI-Lite slave interface and internally contains:

control/status registers
input memory window
output memory window
stream source FSM
frac_cfo_sync_axi_stream_wrapper
frac_cfo_frame_corrector_top
stream sink FSM

Step 26 memory map:

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

Input memory window:

0x1000 to 0x1FFF

Output memory window:

0x2000 to 0x2FFF

Step 27 goal:

Create a minimal ZCU102 Vivado Block Design that connects the Zynq UltraScale+ MPSoC PS to rtl/frac_cfo_sync_bram_test_wrapper.v through AXI.

This step should prepare a reproducible Windows Vivado Tcl flow.

No ILA in this step.

The user explicitly decided that ILA is not needed yet.

Target:

Board = ZCU102
Part = xczu9eg-ffvb1156-2-e
Vivado = Windows Vivado 2022.2
Clock target = 100 MHz if possible through PS FCLK
Main wrapper module = frac_cfo_sync_bram_test_wrapper

Step 27 minimal architecture:

Zynq UltraScale+ MPSoC PS
-> M_AXI_HPM master
-> AXI SmartConnect or AXI Interconnect
-> frac_cfo_sync_bram_test_wrapper AXI-Lite slave

Clock/reset:

Use PS FCLK or equivalent BD clock source for aclk.
Use Processor System Reset or equivalent reset synchronizer for aresetn.
Connect wrapper aclk and AXI clock to the same clock domain.
Connect wrapper aresetn correctly as active-low reset.

Do not add:

ILA
VIO
DMA
FFT
integer CFO
int_cfo_estimator.v
RF/ADC interface
AXI DMA
AXI BRAM Controller unless truly required
Block Memory Generator unless truly required
Vitis application
bitstream generation
board programming
Phase 2 redesign

Important:

The Step 26 wrapper already contains inferred memories and an AXI-Lite memory/register map.
Therefore, do not add external AXI BRAM Controller or Block Memory Generator unless Vivado integration proves it is needed.

The goal is to memory-map the Step 26 wrapper directly into the Zynq PS address space.

Allowed files to create or modify:

scripts/vivado/step27_create_zcu102_bd_no_ila.tcl
scripts/windows/run_step27_create_zcu102_bd_no_ila.bat
scripts/windows/README.md
docs/step27_zcu102_bd_integration_no_ila.md
ai_context/current_status.md
md_files/27_zcu102_bd_integration_no_ila_prompt.md, or _v2 if needed
md_files/README.md, if needed

You may create:

scripts/vivado/
vivado/step27_zcu102_bd/
reports/step27/

Do not modify by default:

rtl/frac_cfo_sync_bram_test_wrapper.v
rtl/frac_cfo_sync_axi_stream_wrapper.v
rtl/frac_cfo_sync_control_s_axi.v
rtl/frac_cfo_frame_corrector_top.v
any lower-level synchronizer RTL
testbenches
existing simulation scripts
unrelated RTL/testbench files

If RTL modification is absolutely necessary for Vivado BD integration, first document:

exact Vivado error
file and line number
root cause
why it blocks block design integration
minimal patch required
impact on Step 26 simulation behavior

Then apply only the minimal fix and rerun:

scripts/run_frac_cfo_sync_bram_test_wrapper_sim.sh
scripts/run_frac_cfo_sync_axi_stream_wrapper_sim.sh
scripts/run_frac_cfo_frame_corrector_top_sim.sh

Preferred outcome:

RTL modified = No.

Required task 1 — Create Vivado BD Tcl script

Create:

scripts/vivado/step27_create_zcu102_bd_no_ila.tcl

The Tcl script should be intended for Windows Vivado execution from:

C:\RTL_SYNC

The script must:

Create a Vivado project under:

vivado/step27_zcu102_bd/

Use target part:

xczu9eg-ffvb1156-2-e

Add all RTL sources required by frac_cfo_sync_bram_test_wrapper.

Include at least:

rtl/frac_cfo_sync_bram_test_wrapper.v
rtl/frac_cfo_sync_axi_stream_wrapper.v
rtl/frac_cfo_sync_control_s_axi.v
rtl/frac_cfo_frame_corrector_top.v
rtl/cordic_atan2.v
rtl/nco_phase_gen.v
all lower-level RTL dependencies
Create a block design named:

sync_phase1_bd

Add Zynq UltraScale+ MPSoC PS IP.

Use Vivado-supported VLNV wildcard if possible:

xilinx.com:ip:zynq_ultra_ps_e:*

Apply ZCU102 board automation if available.

If board files are unavailable, configure the PS minimally in Tcl and document the limitation.

Enable at least one PS AXI master interface suitable for controlling PL AXI slaves.

Preferred:

M_AXI_HPM0_FPD or equivalent
Create AXI SmartConnect or AXI Interconnect.

Preferred:

SmartConnect if available
Add frac_cfo_sync_bram_test_wrapper as a BD module.

Use:

create_bd_cell -type module -reference frac_cfo_sync_bram_test_wrapper

or equivalent.

Connect:

PS AXI master -> SmartConnect/Interconnect -> wrapper AXI-Lite slave

Connect clock:

PS FCLK -> SmartConnect clock -> wrapper aclk -> AXI clock

Connect reset:

PS reset / proc_sys_reset -> SmartConnect reset -> wrapper aresetn

Assign address map.

Give wrapper a base address such as:

0xA0000000

Address range should cover at least:

0x0000 to 0x2FFF

Recommended range:

64 KB

Validate block design.

Run:

validate_bd_design

Save block design.
Create HDL wrapper for the BD.
Set generated HDL wrapper as top if appropriate.
Generate block design output products if needed.
Do not run implementation.
Optional: run synthesis only if the script is stable and fast.

If synthesis is included, generate reports under:

reports/step27/

But do not run implementation or bitstream generation.

Required task 2 — Create Windows batch runner

Create:

scripts/windows/run_step27_create_zcu102_bd_no_ila.bat

The batch file must:

Be intended for Windows execution from:

C:\RTL_SYNC

Call:

C:\Xilinx\Vivado\2022.2\bin\vivado.bat

Run Vivado batch mode with:

scripts/vivado/step27_create_zcu102_bd_no_ila.tcl

Save console output to:

reports/step27/step27_create_bd.log

Return non-zero if Vivado fails.

Expected Windows command:

cd C:\RTL_SYNC
scripts\windows\run_step27_create_zcu102_bd_no_ila.bat

Required task 3 — Documentation

Create:

docs/step27_zcu102_bd_integration_no_ila.md

The document must include:

Step 27 goal
Phase 1 context
Step 26 wrapper summary
Why ILA is intentionally omitted
ZCU102 target information
Vivado project location
Block design architecture
Xilinx IP used
Custom RTL module used
Clock/reset strategy
AXI address map
Tcl script description
Windows batch command
Execution status
Known limitations
Recommended Step 28

If Windows execution has not been run from this Claude session, clearly state:

Execution status: Prepared, pending Windows Vivado run.

Do not fake validation or synthesis results.

Required task 4 — Update current status

Update:

ai_context/current_status.md

Add Step 27 status.

If only scripts are prepared and Windows Vivado has not been run yet, use:

Step 27 status: Prepared, pending Windows Vivado execution.

Include:

prompt archive path
files created
target board
target part
Vivado project path
block design name
Xilinx IP list
ILA omitted intentionally
Windows batch command
whether validate_bd_design has actually run
recommended user action

Recommended user action:

Run on Windows:

cd C:\RTL_SYNC
scripts\windows\run_step27_create_zcu102_bd_no_ila.bat

Recommended Step 28:

Step 28 — Windows Vivado synthesis/implementation/bitstream/XSA export for the Step 27 block design.

Purpose:

Run the generated ZCU102 BD through synthesis, implementation, bitstream generation, and hardware platform export.

Required task 5 — Optional pre-check

Optionally check that Step 26 simulation still passes:

scripts/run_frac_cfo_sync_bram_test_wrapper_sim.sh

Expected:

PASS = 23
FAIL = 0
CI gate = PASSED

Do not spend excessive time on unrelated regression unless changes were made to RTL.

Final report format:

Step 27 preparation complete.

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
Vivado:
BD name:
project path:

Architecture:

PS:
AXI interconnect:
custom wrapper:
ILA:
DMA:
external BRAM IP:

Address map:

wrapper base:
wrapper range:

Scripts prepared:

Vivado Tcl:
Windows batch:

Execution:

Windows Vivado run status:
validate_bd_design:
synthesis:
bitstream:

RTL modified:

Yes/No

Recommended Windows command:

...

Recommended Step 28:

...

Important constraints:

Do not add ILA.
Do not add VIO.
Do not add DMA.
Do not add FFT.
Do not add integer CFO.
Do not implement int_cfo_estimator.v.
Do not create Vitis firmware.
Do not program board.
Do not run bitstream generation in this step.
Do not start Phase 2.
Keep this step focused only on minimal ZCU102 Vivado block design integration without ILA.
