Step 27B Fix Prompt — Package BRAM Test Wrapper as Local Vivado IP for BD Integration

Active workspace:

/home/zealatan/RTL_SYNC

Windows workspace:

C:\RTL_SYNC

Problem observed during Windows Vivado Step 27 execution:

The script scripts/vivado/step27_create_zcu102_bd_no_ila.tcl failed at:

create_bd_cell -type module -reference frac_cfo_sync_bram_test_wrapper wrapper_0

Vivado error:

Reference 'frac_cfo_sync_bram_test_wrapper' contains top file 'C:/RTL_SYNC/rtl/frac_cfo_sync_bram_test_wrapper.v' of type SystemVerilog. This type is not allowed as the top file in the reference.

Unable to resolve module-source based on inputs: frac_cfo_sync_bram_test_wrapper.

Interpretation:

This is not an RTL synthesis failure.
This is a Vivado Block Design module-reference integration limitation.
Vivado BD does not accept this SystemVerilog file as a direct module reference in create_bd_cell -type module.

Task:

Patch Step 27 Vivado integration flow so that frac_cfo_sync_bram_test_wrapper is packaged as a local Vivado IP and instantiated in the block design as an IP cell, not as a raw module reference.

Do not modify RTL unless absolutely necessary.

Preferred solution:

1. Create or update:

scripts/vivado/step27_create_zcu102_bd_no_ila.tcl

2. Add a local IP packaging step before create_bd_design or before BD instantiation.

Package the RTL hierarchy with top module:

frac_cfo_sync_bram_test_wrapper

as a local IP under a generated local IP directory, for example:

vivado/ip_repo/frac_cfo_sync_bram_test_wrapper_1_0

3. Add all required RTL sources to the IP package:

rtl/frac_cfo_sync_bram_test_wrapper.v
rtl/frac_cfo_sync_axi_stream_wrapper.v
rtl/frac_cfo_sync_control_s_axi.v
rtl/frac_cfo_frame_corrector_top.v
rtl/cordic_atan2.v
rtl/nco_phase_gen.v
all lower-level dependencies

4. Package the custom IP using Vivado ipx commands.

Suggested approach:

- create_project for packaging or use current project
- ipx::package_project
- set IP metadata:
  vendor = user.org or zealatan.local
  library = user
  name = frac_cfo_sync_bram_test_wrapper
  version = 1.0
- infer AXI-Lite bus interface from s_axi_* ports if possible
- infer clock/reset association:
  aclk
  aresetn
- save_core
- add the generated ip_repo path to current_project ip_repo_paths
- update_ip_catalog

5. In the block design, instantiate the packaged IP with:

create_bd_cell -type ip -vlnv <vendor>:<library>:frac_cfo_sync_bram_test_wrapper:1.0 wrapper_0

instead of:

create_bd_cell -type module -reference frac_cfo_sync_bram_test_wrapper wrapper_0

6. Keep the same architecture:

Zynq UltraScale+ PS
-> AXI SmartConnect
-> wrapper_0 AXI-Lite slave

No ILA.
No DMA.
No external BRAM IP.
No bitstream.
No implementation.
No Vitis.

7. Keep address map:

wrapper_0 base = 0xA0000000
range = 64 KB

8. Validate block design.

Run:

validate_bd_design

9. Generate HDL wrapper if validation passes.

10. Update docs/step27_zcu102_bd_integration_no_ila.md with:

- original failure
- root cause
- fix: package custom RTL as local IP
- no RTL modified
- new execution status
- Windows command

11. Update ai_context/current_status.md with Step 27B fix status.

12. Preserve prompt archive policy. Save this prompt as:

md_files/27b_package_wrapper_as_local_ip_prompt.md

if missing.

Allowed files to modify:

scripts/vivado/step27_create_zcu102_bd_no_ila.tcl
scripts/windows/run_step27_create_zcu102_bd_no_ila.bat, only if needed
docs/step27_zcu102_bd_integration_no_ila.md
ai_context/current_status.md
md_files/27b_package_wrapper_as_local_ip_prompt.md
md_files/README.md, if needed

Do not modify:

rtl/*.v
tb/*.sv
existing simulation scripts
Step 26 wrapper RTL

Final report format:

Step 27B fix complete.

Prompt archive:
- saved prompt path:

Files changed:
- ...

Failure fixed:
- original error:
- root cause:
- fix:

Vivado integration approach:
- raw module reference: removed/kept?
- packaged local IP: yes/no
- IP repo path:
- IP VLNV:

Windows execution:
- status:
- command:
  cd C:\RTL_SYNC
  .\scripts\windows\run_step27_create_zcu102_bd_no_ila.bat

RTL modified:
- Yes/No

Recommended next action:
- Run Windows Step 27 again and report validate_bd_design result.
