Step 29B Prompt — ZCU102 Vitis Bring-Up and UART Known-Vector Test

Before executing this step, save this full prompt to:

md_files/29b_zcu102_vitis_bringup_uart_test_prompt.md

If that file already exists, save this prompt as:

md_files/29b_zcu102_vitis_bringup_uart_test_prompt_v2.md

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

This step is for preparing and documenting the actual ZCU102 Vitis bring-up flow.

Board execution may be performed manually on Windows by the user.

Do not modify RTL.
Do not add ILA.
Do not add DMA.
Do not add Linux/PetaLinux.
Do not start Phase 2.

Project status:

Step 28 completed:
- Vivado synthesis PASS
- implementation PASS
- route PASS
- timing PASS
- WNS = +0.891 ns
- WHS = +0.010 ns
- bitstream generated:
  outputs/step28/sync_phase1_bd_wrapper.bit
- XSA generated:
  outputs/step28/sync_phase1_bd_wrapper.xsa

Important:
The XSA may not include the bitstream internally.
Program the bitstream separately if needed.

Step 29A completed:
- sw/step29a_vitis_known_vector/register_map.h
- sw/step29a_vitis_known_vector/known_vector.h
- sw/step29a_vitis_known_vector/src/main.c
- sw/step29a_vitis_known_vector/README.md

Verified register mapping from RTL:

Base address:
0xA0000000

CONTROL:
bit[0] = start_pulse
bit[3] = enable

STATUS:
bit[1] = done_sticky
bit[8] = frame_error

Known vector:
- 8 quiet samples = 0x00000000
- 20 active samples = 0x00000064
- total INPUT_LEN = 28

Step 29B goal:

Prepare a practical ZCU102 bring-up guide and scripts/checklists for:

1. Connect ZCU102 via USB JTAG and USB UART.
2. Program FPGA with:
   outputs/step28/sync_phase1_bd_wrapper.bit
3. Create/import Vitis 2022.2 platform using:
   outputs/step28/sync_phase1_bd_wrapper.xsa
4. Create baremetal standalone application for psu_cortexa53_0.
5. Add Step 29A C source/header files.
6. Build application.
7. Run application on ZCU102.
8. Capture UART output.
9. Save UART log to:
   reports/step29b/step29b_uart_log.txt
10. Classify result as PASS/FAIL.

Required files to create or modify:

docs/step29b_zcu102_vitis_bringup_uart_test.md
reports/step29b/README.md
ai_context/current_status.md
md_files/29b_zcu102_vitis_bringup_uart_test_prompt.md, or _v2 if needed
sw/step29a_vitis_known_vector/README.md, if useful
scripts/windows/README.md, if useful

Optional files:

scripts/windows/run_step29b_notes_only.bat

Only create scripts if they are safe and do not assume board-specific COM ports or Vitis workspace paths.

Do not create fragile Vitis automation unless very confident.

Required task 1 — Create Step 29B documentation

Create:

docs/step29b_zcu102_vitis_bringup_uart_test.md

Required task 2 — Create reports directory note

Create:

reports/step29b/README.md

Required task 3 — Update Step 29A README if useful

Update:

sw/step29a_vitis_known_vector/README.md

Add a short Step 29B execution checklist if it is not already clear.

Required task 4 — Update current status

Update:

ai_context/current_status.md

Required task 5 — Do not fake execution

Do not claim board was programmed, Vitis build passed, or app ran unless it actually happened.

Final report format:

Step 29B preparation complete.

Prompt archive:
- saved prompt path:

Files changed:
- ...

Required hardware:
- ZCU102, power supply, USB JTAG, USB UART, Windows PC with Vivado/Vitis 2022.2

Artifacts required:
- bitstream: outputs/step28/sync_phase1_bd_wrapper.bit
- XSA: outputs/step28/sync_phase1_bd_wrapper.xsa
- software: sw/step29a_vitis_known_vector/

Execution status:
- FPGA programmed: NOT RUN
- Vitis platform: NOT RUN
- app build: NOT RUN
- board run: NOT RUN
- UART capture: NOT RUN

Board required: Yes

RTL modified: No

Recommended manual action: Connect ZCU102, program bitstream, build/run Vitis app, save UART log.
