Step 29A Prompt — Vitis Baremetal Known-Vector Control App Preparation

Before executing this step, save this full prompt to:

md_files/29a_vitis_baremetal_known_vector_app_prompt.md

If that file already exists, save this prompt as:

md_files/29a_vitis_baremetal_known_vector_app_prompt_v2.md

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

This is a WSL code/documentation preparation step for the Vitis bring-up phase.

Do not require ZCU102 board connection in this step.
Do not program FPGA in this step.
Do not run Vitis hardware execution in this step.
Do not modify RTL.

Step 29A goal:

Prepare a Vitis baremetal C control application for the Step 28 hardware platform.

The application will later be used on ZCU102 to:

1. write known IQ samples into the wrapper input memory window
2. configure the synchronizer
3. start the run
4. poll STATUS.done_sticky
5. read counters and output memory
6. print results over UART

Board execution is deferred to Step 29B.

Project context:

This project implements an AI-assisted RTL/FPGA development flow for an OFDM synchronizer subsystem.

Phase 1 = Functional FPGA synchronizer
Phase 2 = 1 sample/clock streaming synchronizer
Phase 3 = multi-sample/clock parallel synchronizer

The current design is Phase 1.

Completed steps:

Step 27 — ZCU102 block design without ILA
Result:
- local IP packaging PASS
- validate_bd_design PASS
- HDL wrapper generated
- address map wrapper_0 = 0xA0000000, range 64 KB
- ILA not used
- DMA not used

Step 28 — Vivado build
Result:
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

Important Step 28 note:

write_hw_platform -include_bit failed, but write_hw_platform without embedded bitstream succeeded.

Therefore current artifacts are:

Bitstream:
outputs/step28/sync_phase1_bd_wrapper.bit

XSA:
outputs/step28/sync_phase1_bd_wrapper.xsa

The XSA may not contain the bitstream internally.

Step 29A should document that Step 29B may need to program the bitstream separately.

Target hardware/software:

Board: ZCU102
Vivado/Vitis: 2022.2
Processor: Zynq UltraScale+ MPSoC Cortex-A53
Application type: baremetal standalone C
Execution target later: JTAG + UART
Custom IP base address: 0xA0000000

Custom IP memory map:

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

Known Step 26 test vector behavior:

The Step 26 testbench used a simple known-vector case:

- 8 quiet samples
- 20 active samples
- INPUT_LEN = 28
- expected INPUT_COUNT = 28
- expected OUTPUT_COUNT = 20
- done_sticky should assert

Use this same simple pattern for the first Vitis known-vector test.

Do not add:
- ILA
- VIO
- DMA
- FFT
- integer CFO
- Linux/PetaLinux
- FreeRTOS
- networking
- SD card boot
- RF/ADC interface
- Phase 2 streaming redesign

Do not modify RTL.

Allowed files to create or modify:

sw/step29a_vitis_known_vector/src/main.c
sw/step29a_vitis_known_vector/README.md
sw/step29a_vitis_known_vector/register_map.h
sw/step29a_vitis_known_vector/known_vector.h
docs/step29a_vitis_baremetal_known_vector_app.md
ai_context/current_status.md
md_files/29a_vitis_baremetal_known_vector_app_prompt.md, or _v2 if needed
md_files/README.md, if needed
scripts/windows/README.md, if needed

Optional files:

scripts/vitis/step29a_create_vitis_workspace.tcl
scripts/windows/run_step29a_create_vitis_workspace.bat

Only create Vitis automation scripts if the commands are reliable for Vitis 2022.2.
If uncertain, prefer clear manual Vitis GUI instructions and C source files rather than fragile scripts.

Required task 1 — Create register map header

Create:

sw/step29a_vitis_known_vector/register_map.h

This header must define:

SYNC_BASE_ADDR = 0xA0000000

Register offsets:

CONTROL
STATUS
CFG_CFO_STEP
CFG_TIMING_OFFSET
CFG_FRAME_LEN
INPUT_LEN
OUTPUT_MAX_LEN
INPUT_COUNT
OUTPUT_COUNT
DEBUG_STATE
ERROR_STATUS

Memory offsets:

INPUT_MEM_BASE = 0x1000
OUTPUT_MEM_BASE = 0x2000

Use Xilinx baremetal style:

#include "xil_io.h"
#include "xil_types.h"

Preferred accessors:

static inline void sync_write32(u32 offset, u32 value)
static inline u32 sync_read32(u32 offset)

Address expression:

SYNC_BASE_ADDR + offset

Control/status bit definitions:

CONTROL register:
bit 0 = enable
bit 1 = start_pulse
bit 2 = soft_reset
bit 3 = clr_status

STATUS register:
bit 0 = busy
bit 1 = done_sticky
bit 2 = error_sticky

If exact bit definitions are uncertain, inspect:

rtl/frac_cfo_sync_bram_test_wrapper.v
rtl/frac_cfo_sync_control_s_axi.v

and document the verified mapping.

Required task 2 — Create known vector header

Create:

sw/step29a_vitis_known_vector/known_vector.h

Define a small known vector matching the Step 26 style:

- 8 quiet samples
- 20 active samples
- total 28 samples

Each sample is 32-bit packed IQ.

Packed IQ format:

upper 16 bits = signed I
lower 16 bits = signed Q

If Step 26 testbench uses a specific known value, inspect it and mirror it.

If not, use:

quiet sample = 0x00000000
active sample = I=1000, Q=0 packed as 0x03E80000

Define:

KNOWN_INPUT_LEN = 28
KNOWN_OUTPUT_MAX_LEN = 64
KNOWN_EXPECTED_INPUT_COUNT = 28
KNOWN_EXPECTED_OUTPUT_COUNT = 20
KNOWN_EXPECTED_MIN_OUTPUT_COUNT = 1

Do not overclaim exact output sample values unless the RTL/testbench explicitly defines them.

Required task 3 — Create main.c

Create:

sw/step29a_vitis_known_vector/src/main.c

The application must:

1. include:
   - xil_printf.h
   - xil_io.h
   - xil_types.h
   - sleep.h or xil_sleep.h if available
   - register_map.h
   - known_vector.h

2. print a banner:

"Step 29A/29B: frac CFO sync known-vector test"

3. print base address and register map summary.

4. perform soft reset:
   - write CONTROL.soft_reset = 1
   - small delay
   - clear soft_reset

5. clear status:
   - write CONTROL.clr_status = 1
   - small delay
   - clear clr_status

6. write config registers:
   - CFG_CFO_STEP
   - CFG_TIMING_OFFSET
   - CFG_FRAME_LEN
   - INPUT_LEN
   - OUTPUT_MAX_LEN

Use defaults:
CFG_CFO_STEP = 0
CFG_TIMING_OFFSET = 0
CFG_FRAME_LEN = KNOWN_INPUT_LEN
INPUT_LEN = KNOWN_INPUT_LEN
OUTPUT_MAX_LEN = KNOWN_OUTPUT_MAX_LEN

7. write known_vector samples into input memory window:

for i in 0..KNOWN_INPUT_LEN-1:
    sync_write32(INPUT_MEM_BASE + 4*i, known_input[i])

8. zero the first KNOWN_OUTPUT_MAX_LEN words of output memory window before run.

9. enable wrapper:
   CONTROL.enable = 1

10. start:
   pulse CONTROL.start_pulse while enable remains set

11. poll STATUS until:
   - done_sticky set, or
   - error_sticky set, or
   - timeout

Use a timeout counter.

Print periodic debug lines every N polls:
- STATUS
- INPUT_COUNT
- OUTPUT_COUNT
- DEBUG_STATE
- ERROR_STATUS

12. after completion, read:
   - STATUS
   - INPUT_COUNT
   - OUTPUT_COUNT
   - DEBUG_STATE
   - ERROR_STATUS

13. pass/fail criteria:

PASS if:
- done_sticky == 1
- error_sticky == 0
- INPUT_COUNT == KNOWN_EXPECTED_INPUT_COUNT
- OUTPUT_COUNT >= KNOWN_EXPECTED_MIN_OUTPUT_COUNT

Also print whether OUTPUT_COUNT equals KNOWN_EXPECTED_OUTPUT_COUNT, but do not make exact equality mandatory unless documentation confirms it is robust.

14. read first N output samples from output memory:
N = min(OUTPUT_COUNT, 16)

Print each as:
index, hex word, signed I, signed Q

15. print final line:

RESULT: PASS

or

RESULT: FAIL

16. return 0 on pass, nonzero on fail.

Important:

The C code should be buildable in Vitis standalone BSP.
Avoid dynamic memory.
Avoid printf floating point.
Use xil_printf.
Use u32/u16/s16 types.

Required task 4 — Create README

Create:

sw/step29a_vitis_known_vector/README.md

The README must explain:

1. Step 29A purpose
2. Required artifacts from Step 28:
   - outputs/step28/sync_phase1_bd_wrapper.xsa
   - outputs/step28/sync_phase1_bd_wrapper.bit
3. Board requirement:
   - code creation/build does not require board
   - execution requires ZCU102 connected by JTAG/UART
4. How to create Vitis platform manually:
   - open Vitis 2022.2
   - create workspace
   - import/create platform from XSA
   - create standalone application for Cortex-A53
   - use Hello World or Empty Application
   - replace main.c and add headers
5. How to program FPGA:
   - if XSA does not include bitstream, program outputs/step28/sync_phase1_bd_wrapper.bit separately
6. UART setup:
   - likely 115200 baud
   - identify COM port in Windows Device Manager
7. Expected UART output:
   - banner
   - base address
   - poll lines
   - input/output counters
   - first output samples
   - RESULT: PASS/FAIL
8. Known limitations:
   - no ILA
   - no DMA
   - known-vector only
   - not throughput test
   - not Phase 2
9. Recommended Step 29B:
   - connect ZCU102
   - program FPGA
   - run app
   - capture UART log

Required task 5 — Create Step 29A documentation

Create:

docs/step29a_vitis_baremetal_known_vector_app.md

Include:

1. Step 29A goal
2. Relationship to Step 28
3. XSA and bitstream paths
4. Hardware address map
5. Register bit assumptions
6. Known-vector design
7. C application flow
8. Build/run assumptions
9. Board requirements for Step 29B
10. Expected output
11. Pass/fail criteria
12. Limitations
13. Recommended Step 29B

Required task 6 — Update current status

Update:

ai_context/current_status.md

Add Step 29A status.

If only source/docs are prepared and Vitis has not been run, state:

Step 29A status: Prepared, pending Vitis workspace creation/build.

Include:
- prompt archive path
- files created
- XSA path
- bitstream path
- base address
- known-vector length
- whether board is needed
- recommended next action

Recommended next action:

Step 29B — Create/open Vitis 2022.2 workspace, import XSA, build baremetal app, connect ZCU102, program bitstream, run app, capture UART output.

Optional task — Vitis automation script

If reliable, create:

scripts/vitis/step29a_create_vitis_workspace.tcl
scripts/windows/run_step29a_create_vitis_workspace.bat

But only if you are confident with Vitis 2022.2 command-line workflow.

If not confident, do not create fragile scripts. Instead, document manual Vitis GUI steps clearly.

Do not fake Vitis build results.

Final report format:

Step 29A preparation complete.

Prompt archive:
- saved prompt path:

Files changed:
- ...

Created software:
- register map:
- known vector:
- main app:
- README:

Target:
- board:
- processor:
- base address:
- XSA:
- bitstream:

Execution:
- Vitis workspace:
- app build:
- board run:
- UART capture:

Board required now:
- Yes/No

RTL modified:
- Yes/No

Recommended Step 29B:
- ...

Important constraints:

Do not modify RTL.
Do not run board execution.
Do not program FPGA.
Do not add ILA.
Do not add DMA.
Do not add Linux/PetaLinux.
Do not start Phase 2.
Keep this step focused on preparing the Vitis baremetal known-vector control application.
