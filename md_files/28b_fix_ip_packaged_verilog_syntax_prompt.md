Step 28B Fix Prompt — Make Packaged RTL Verilog-Compatible for Vivado IP Synthesis

Before executing this step, save this full prompt to:

md_files/28b_fix_ip_packaged_verilog_syntax_prompt.md

Active workspace:

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
/mnt/c/
C:\
/home/zealatan/AI_ORC/messi/VIVADO_MIN_EXAMPLE

Problem observed during Windows Step 28 execution:

Step 27 completed:
- Vivado BD generated
- local IP packaging succeeded
- validate_bd_design passed
- HDL wrapper generated

Step 28 failed during synthesis:

Failed run:
sync_phase1_bd_wrapper_0_0_synth_1

Vivado error:

ERROR: [Synth 8-2716] syntax error near ''' 
[c:/RTL_SYNC/vivado/step27_zcu102_bd/step27_zcu102_bd.gen/sources_1/bd/sync_phase1_bd/ipshared/.../src/cp_autocorr_core.v:97]

Earlier Step 27 IP packaging also showed syntax warnings near ''' in:
- cp_autocorr_core.v
- timing_sync_top.v
- frac_cfo_frame_corrector_top.v

Interpretation:

This is not a functional RTL algorithm failure.
This is a Vivado IP packaging / file parsing issue.
The local IP package is being synthesized as Verilog, and some RTL files contain SystemVerilog-style syntax that Vivado's packaged IP synthesis parser rejects.

Goal:

Patch the RTL syntax minimally so all files used by the packaged local IP are Verilog-compatible under Vivado IP synthesis.

Do not change functionality.

Do not redesign the synchronizer.

Do not add ILA.
Do not add DMA.
Do not add FFT.
Do not add integer CFO.
Do not modify the architecture.

Primary files to inspect:

rtl/cp_autocorr_core.v
rtl/timing_sync_top.v
rtl/frac_cfo_frame_corrector_top.v

Search for SystemVerilog constructs that may break when parsed as Verilog inside packaged IP, especially around the lines flagged by Vivado:

- cp_autocorr_core.v around line 97
- timing_sync_top.v around lines 132 and 155
- frac_cfo_frame_corrector_top.v around lines 176, 320, 393, 400, 409, 432

Look for constructs such as:

- signed casts using '(...)
- type casts
- logic-specific syntax if present
- SystemVerilog-only part-select/cast forms
- unsized or nested casts that generate syntax near apostrophe
- any construct that xvlog -sv accepts but Vivado packaged IP Verilog synthesis rejects

Patch style:

Prefer explicit Verilog-2001 expressions.

Examples:

Instead of SystemVerilog cast syntax:
signed'(expr)
some_type'(expr)

Use Verilog-style:
$signed(expr)

Instead of width/type casts:
WIDTH'(expr)

Use explicit wire/reg with assigned truncation/sign extension, or explicit concatenation.

If a signed value is needed:
- declare an intermediate signed wire/reg
- assign using $signed(...)
- keep width explicit

Do not change arithmetic intent.

After patching, run these WSL regressions:

1. scripts/run_frac_cfo_sync_bram_test_wrapper_sim.sh
Expected:
PASS = 23
FAIL = 0
CI GATE = PASSED

2. scripts/run_frac_cfo_sync_axi_stream_wrapper_sim.sh
Expected:
PASS = 23
FAIL = 0
CI GATE = PASSED

3. scripts/run_frac_cfo_frame_corrector_top_sim.sh
Expected:
PASS = 176
FAIL = 0
CI GATE = PASSED

If xvlog is not in PATH, document that regression could not run and do not fake results.

Then update Step 27/28 docs:

Update:
docs/step28_zcu102_bitstream_xsa_export.md

Add section:
Step 28B synthesis failure and RTL syntax compatibility fix

Include:
- original Vivado error
- affected file/line
- root cause
- exact syntax pattern fixed
- functionality unchanged
- required Windows re-run sequence

Update:
docs/step27_zcu102_bd_integration_no_ila.md

Add note:
Local IP packaging succeeded but packaged IP synthesis requires Verilog-compatible RTL syntax.

Update:
ai_context/current_status.md

Add:
Step 28B status: RTL syntax compatibility patch prepared, pending Windows rerun.

Allowed files to modify:

rtl/cp_autocorr_core.v
rtl/timing_sync_top.v
rtl/frac_cfo_frame_corrector_top.v
docs/step28_zcu102_bitstream_xsa_export.md
docs/step27_zcu102_bd_integration_no_ila.md
ai_context/current_status.md
md_files/28b_fix_ip_packaged_verilog_syntax_prompt.md
md_files/README.md, if needed

Do not modify:
Step 25 wrapper unless needed
Step 26 wrapper unless needed
Step 27 BD script unless needed
Step 28 build script unless needed

If Step 27 or Step 28 scripts must be changed, document why.

Final report format:

Step 28B fix complete.

Prompt archive:
- saved prompt path:

Root cause:
- ...

Files changed:
- ...

Syntax patterns fixed:
- ...

Regression:
- BRAM wrapper:
- AXI stream wrapper:
- frame corrector top:

RTL functionality changed:
- Yes/No

Recommended Windows rerun:

cd C:\RTL_SYNC
git fetch origin
git reset --hard origin/main
git clean -fd
.\scripts\windows\run_step27_create_zcu102_bd_no_ila.bat
.\scripts\windows\run_step28_build_bitstream_xsa.bat

Expected:
- Step 27 regenerate project
- Step 28 synthesis should pass beyond previous cp_autocorr_core.v:97 error
