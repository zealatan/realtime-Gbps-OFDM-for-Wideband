Step 28C Prompt — Export XSA With Embedded Bitstream

Before executing this step, save this full prompt to:

md_files/28c_export_xsa_with_embedded_bitstream_prompt.md

If that file already exists, save this prompt as:

md_files/28c_export_xsa_with_embedded_bitstream_prompt_v2.md

At the end, include the saved prompt path in the final report.

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

This step prepares a new Vivado batch flow to export an XSA that includes the bitstream.

Do not modify RTL.
Do not add ILA.
Do not add DMA.
Do not add Linux/PetaLinux.
Do not start Phase 2.
Do not modify the Step 27 block design architecture.

Context:

Step 27 completed:
- ZCU102 block design created
- PS -> SmartConnect -> frac_cfo_sync_bram_test_wrapper
- Address base = 0xA0000000, range = 64 KB
- validate_bd_design PASS
- HDL wrapper generated
- Top = sync_phase1_bd_wrapper

Step 28 completed:
- synthesis PASS
- implementation PASS
- route PASS
- timing PASS
- WNS = +0.891 ns
- WHS = +0.010 ns
- bitstream generated:
  outputs/step28/sync_phase1_bd_wrapper.bit
- XSA generated:
  outputs/step28/sync_phase1_bd_wrapper.xsa

Important Step 28 issue:

The existing XSA was exported without embedded bitstream because:

write_hw_platform -include_bit

failed with:

Unable to get BIT file from implementation run.
Please ensure implementation has been run all the way through Bitstream generation.

The script then fell back to:

write_hw_platform -fixed -force

which created an XSA without embedded bitstream.

Step 28C goal:

Create a new script that runs the implementation flow all the way through the write_bitstream step using Vivado run infrastructure:

launch_runs impl_1 -to_step write_bitstream

Then export an XSA with embedded bitstream:

write_hw_platform -fixed -include_bit -force

Expected new output:

outputs/step28/sync_phase1_bd_wrapper_with_bit.xsa

Do not delete or overwrite the existing files:

outputs/step28/sync_phase1_bd_wrapper.bit
outputs/step28/sync_phase1_bd_wrapper.xsa

The new embedded-bitstream XSA must be additional.

Required files to create or modify:

scripts/vivado/step28c_export_xsa_with_bitstream.tcl
scripts/windows/run_step28c_export_xsa_with_bitstream.bat
docs/step28c_export_xsa_with_embedded_bitstream.md
ai_context/current_status.md
md_files/28c_export_xsa_with_embedded_bitstream_prompt.md, or _v2 if needed
scripts/windows/README.md, if useful

Allowed output directories:

reports/step28c/
outputs/step28/

Required task 1 — Create Vivado Tcl script

Create:

scripts/vivado/step28c_export_xsa_with_bitstream.tcl

The script must:

1. Define:

PROJ_FILE = vivado/step27_zcu102_bd/step27_zcu102_bd.xpr
BD_TOP = sync_phase1_bd_wrapper
RPTS = reports/step28c
OUT = outputs/step28
XSA_WITH_BIT = outputs/step28/sync_phase1_bd_wrapper_with_bit.xsa

2. Check that Step 27 project exists.

If not found, print:

ERROR: Step 27 project not found.
Run Step 27 first.

and exit 1.

3. Open the Step 27 Vivado project.

4. Check top module.

Expected top:

sync_phase1_bd_wrapper

If top is not this, try to set it.

5. Reset implementation/synthesis runs safely.

Use:

catch {reset_run impl_1}
catch {reset_run synth_1}

6. Launch synthesis:

launch_runs synth_1 -jobs 4
wait_on_run synth_1

Check:
- PROGRESS == 100%
- STATUS does not contain fail

If failed, exit 1.

7. Generate synthesis reports:

reports/step28c/step28c_synth_utilization.rpt
reports/step28c/step28c_synth_timing_summary.rpt

8. Launch implementation to bitstream stage:

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

This is the key difference from Step 28.

Check:
- PROGRESS == 100%
- STATUS does not contain fail

Accept statuses such as:
- write_bitstream Complete!
- route_design Complete!
only if the run has actually produced a bitstream file under the impl_1 run directory.

Robustly search for bitstream files under:

vivado/step27_zcu102_bd/step27_zcu102_bd.runs/impl_1/

Expected possible file:

sync_phase1_bd_wrapper.bit

If no bitstream file exists in the run directory, print error and exit 1.

9. Open implemented run:

open_run impl_1

10. Generate implementation reports:

reports/step28c/step28c_impl_utilization.rpt
reports/step28c/step28c_timing_summary.rpt
reports/step28c/step28c_drc.rpt
reports/step28c/step28c_power.rpt

11. Check timing:

Use get_timing_paths for setup and hold.

Print:
- WNS
- WHS

If setup slack < 0 or hold slack < 0, print TIMING CHECK: FAIL and exit 1.

Otherwise print:

TIMING CHECK: PASS

12. Export XSA with embedded bitstream:

write_hw_platform -fixed -include_bit -force -file $XSA_WITH_BIT

If this fails, do not fall back to no-bit XSA.

This step is specifically for embedded-bitstream XSA.

On failure, print:

ERROR: Embedded-bitstream XSA export failed.

and exit 1.

13. Verify output exists:

outputs/step28/sync_phase1_bd_wrapper_with_bit.xsa

If not exists, exit 1.

14. Print final summary:

Step 28C COMPLETE.
XSA with embedded bitstream:
outputs/step28/sync_phase1_bd_wrapper_with_bit.xsa

Recommended Vitis platform input:
outputs/step28/sync_phase1_bd_wrapper_with_bit.xsa

Required task 2 — Create Windows batch runner

Create:

scripts/windows/run_step28c_export_xsa_with_bitstream.bat

It must:

1. Run from repository root C:\RTL_SYNC.

2. Check that Vivado exists:

C:\Xilinx\Vivado\2022.2\bin\vivado.bat

3. Check that Step 27 project exists:

vivado\step27_zcu102_bd\step27_zcu102_bd.xpr

If not found, print:

ERROR: Step 27 project not found.
Run .\scripts\windows\run_step27_create_zcu102_bd_no_ila.bat first.

4. Create:

reports\step28c
outputs\step28

5. Run:

vivado.bat -mode batch -source scripts\vivado\step28c_export_xsa_with_bitstream.tcl -log reports\step28c\step28c_export_xsa_with_bitstream.log -journal reports\step28c\step28c_export_xsa_with_bitstream.jou

6. At the end, check that:

outputs\step28\sync_phase1_bd_wrapper_with_bit.xsa

exists.

If exists, print:

STEP 28C RESULT: PASS

If not, print:

STEP 28C RESULT: FAIL

Required task 3 — Create documentation

Create:

docs/step28c_export_xsa_with_embedded_bitstream.md

Include:

1. Motivation
2. Step 28 issue:
   - write_hw_platform -include_bit failed
   - fallback XSA did not include bitstream
3. Step 28C fix:
   - run impl_1 to write_bitstream using launch_runs impl_1 -to_step write_bitstream
   - then call write_hw_platform -include_bit
4. Input:
   - Step 27 project
5. Output:
   - outputs/step28/sync_phase1_bd_wrapper_with_bit.xsa
6. Difference from previous Step 28:
   - no fallback to no-bit XSA
   - fails if embedded XSA cannot be generated
7. How to run on Windows:

cd C:\RTL_SYNC
.\scripts\windows\run_step28c_export_xsa_with_bitstream.bat

8. Expected Vitis usage:
   - use sync_phase1_bd_wrapper_with_bit.xsa as platform input
   - Vitis should be able to program FPGA more conveniently
9. Known limitations:
   - still no ILA
   - still no DMA
   - still Phase 1 known-vector bring-up design
10. Recommended next action:
   - import new XSA into Vitis
   - rebuild known-vector app
   - run on ZCU102
   - capture UART log

Required task 4 — Update current status

Update:

ai_context/current_status.md

Add Step 28C status.

If only scripts/docs are prepared and Windows Vivado has not yet run, say:

Step 28C status: Prepared, pending Windows Vivado execution.

If the script is run successfully in the same session and output XSA exists, say:

Step 28C status: COMPLETE.

Include:
- prompt archive path
- Tcl path
- batch path
- output XSA path
- whether RTL was modified
- recommended next action

Required task 5 — Update scripts/windows README if useful

Update:

scripts/windows/README.md

Add Step 28C command:

cd C:\RTL_SYNC
.\scripts\windows\run_step28c_export_xsa_with_bitstream.bat

Explain that Step 27 project must exist first.

Required task 6 — Do not fake execution

If the Windows batch was not run, final report must say:

Execution:
- Windows Vivado: NOT RUN
- XSA with embedded bitstream: NOT GENERATED

If the batch was run, report the actual result and file path.

Final report format:

Step 28C preparation complete.

Prompt archive:
- saved prompt path:

Files changed:
- ...

Purpose:
- ...

Input:
- Step 27 project:

Output target:
- embedded XSA:

Execution:
- Windows Vivado:
- synthesis:
- implementation to write_bitstream:
- timing:
- embedded XSA export:

RTL modified:
- Yes/No

Recommended Windows command:
cd C:\RTL_SYNC
.\scripts\windows\run_step28c_export_xsa_with_bitstream.bat

Recommended next action:
- Use outputs/step28/sync_phase1_bd_wrapper_with_bit.xsa in Vitis.
