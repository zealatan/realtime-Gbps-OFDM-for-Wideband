# Step 29A/29B — frac CFO Sync Known-Vector Test (Vitis Baremetal)

## Purpose

Baremetal C application for the ZCU102 Phase 1 bring-up.
Tests `frac_cfo_sync_bram_test_wrapper` via AXI-Lite memory-mapped access from the Cortex-A53 APU.

Does not require ILA, DMA, Linux, or networking.

---

## Required Artifacts from Step 28

| File | Location |
|------|----------|
| XSA (hardware platform) | `outputs/step28/sync_phase1_bd_wrapper.xsa` |
| Bitstream | `outputs/step28/sync_phase1_bd_wrapper.bit` |

**Note:** The Step 28 XSA may not contain the embedded bitstream
(Step 28 `write_hw_platform -include_bit` failed; the XSA was generated without it).
You will need to program the bitstream separately — see FPGA Programming below.

---

## Software Files

| File | Description |
|------|-------------|
| `src/main.c` | Main application — known-vector test driver |
| `register_map.h` | Register offsets, bit masks, accessors |
| `known_vector.h` | 28-sample test stimulus (8 quiet + 20 active) |

---

## Board Connection Required?

| Task | Board required? |
|------|----------------|
| Create Vitis workspace | No |
| Build application | No |
| Program FPGA | Yes (ZCU102 + JTAG cable) |
| Run and capture UART | Yes (ZCU102 + UART cable + terminal) |

Board execution is Step 29B.

---

## Creating the Vitis Workspace (Manual GUI Steps)

### Step 1: Open Vitis 2022.2

Launch Vitis 2022.2 from the Windows Start menu or:
```
C:\Xilinx\Vitis\2022.2\bin\vitis.bat
```
Choose a workspace directory, e.g. `C:\RTL_SYNC\vitis\step29`.

### Step 2: Create Hardware Platform from XSA

1. In Vitis: **File → New → Platform Project**
2. Project name: `sync_phase1_platform`
3. Click **Next**
4. Select **Create from hardware specification (XSA)**
5. Browse to: `C:\RTL_SYNC\outputs\step28\sync_phase1_bd_wrapper.xsa`
6. Operating system: **standalone**
7. Processor: **psu_cortexa53_0**  (Cortex-A53 APU, core 0)
8. Click **Finish**
9. Vitis builds the BSP. Wait for completion.

### Step 3: Create Application Project

1. **File → New → Application Project**
2. Platform: `sync_phase1_platform`
3. Project name: `known_vector_test`
4. Processor: `psu_cortexa53_0`
5. OS: `standalone`
6. Language: **C**
7. Template: **Hello World** (or Empty Application)
8. Click **Finish**

### Step 4: Add Source Files

1. In the Explorer panel, navigate to `known_vector_test/src/`
2. Delete `helloworld.c` (or `main.c` from template) if present
3. Copy the following files from `C:\RTL_SYNC\sw\step29a_vitis_known_vector\`:
   - `src/main.c`           → `known_vector_test/src/main.c`
   - `register_map.h`       → `known_vector_test/src/register_map.h`
   - `known_vector.h`       → `known_vector_test/src/known_vector.h`

   In Vitis: right-click `src` folder → **Import Sources** → browse to each file.

### Step 5: Build

1. Right-click `known_vector_test` → **Build Project**
2. Check the Console for errors. Expect:
   ```
   Finished building: known_vector_test.elf
   ```
3. ELF is at: `known_vector_test/Debug/known_vector_test.elf`

---

## FPGA Programming

### If XSA does not contain embedded bitstream:

1. Open Vivado 2022.2 (Hardware Manager can also be done from Vitis)
2. **Open Hardware Manager → Open Target → Auto Connect**
3. Right-click the device → **Program Device**
4. Bitstream file: `C:\RTL_SYNC\outputs\step28\sync_phase1_bd_wrapper.bit`
5. Click **Program**

### Alternative via Vitis:

1. In Vitis, right-click `known_vector_test` → **Run As → Launch on Hardware (Single Application Debug)**
2. Vitis may prompt to program the FPGA if the XSA contains the bitstream.
3. If it does not, program via Vivado Hardware Manager first.

---

## UART Setup

1. Connect ZCU102 UART (usually Micro-USB J83 / Silicon Labs CP2108 → 4 virtual COM ports)
2. Open a terminal (PuTTY, TeraTerm, or Windows Terminal with serial):
   - **Baud rate: 115200**
   - Data bits: 8, Stop bits: 1, Parity: None, Flow control: None
3. Identify the correct COM port in Windows Device Manager under **Ports (COM & LPT)**:
   - Look for "Silicon Labs Quad CP2108" — use the **first** COM port (Interface 0)

---

## Running the Application

### Via Vitis Debug:

1. Right-click `known_vector_test` → **Run As → Launch on Hardware (Single Application Debug)**
2. Vitis uploads the ELF and starts execution.
3. Watch UART terminal for output.

### Via XSCT (command-line):

```tcl
connect
targets -set -filter {name =~ "Cortex-A53*#0"}
rst -processor
dow C:/RTL_SYNC/vitis/step29/known_vector_test/Debug/known_vector_test.elf
con
```

---

## Expected UART Output

```
========================================
Step 29A/29B: frac CFO sync known-vector test
Board:   ZCU102
IP base: 0xA0000000
Vector:  8 quiet + 20 active = 28 samples
========================================

[1] Soft reset...
[2] Clear status...
    STATUS after clear = 0x00000000
[3] Loading 28 samples into input memory...
    Done. quiet[0]=0x00000000 active[8]=0x00000064
[4] Clearing output memory (64 words)...
[5] Writing configuration registers...
    INPUT_LEN=28  OUTPUT_MAX_LEN=64  FRAME_LEN=28
[6] Enabling wrapper...
[6] Pulsing start...
[7] Polling STATUS...
  poll=0  STS=0x05  IC=0  OC=0  DBG=2  ERR=0x0
  ...
  done_sticky asserted after NNNN polls

[8] Final register state:
  STATUS=0x000000xx  ERR=0x00000000
    done_sticky
  INPUT_COUNT  = 28  (expected 28)
  OUTPUT_COUNT = 20  (expected ~20)
  DEBUG_STATE  = 4

[9] Evaluating result...
  INFO: OUTPUT_COUNT matches expected (20)

[10] First 20 output samples:
  idx   hex_word   I(dec)   Q(dec)
    0   0x........   .....   .....
    ...

========================================
RESULT: PASS
========================================
```

---

## Pass/Fail Criteria

| Check | Pass condition |
|-------|---------------|
| done_sticky | Must be set |
| frame_error | Must be 0 |
| ERROR_STATUS | Must be 0 |
| INPUT_COUNT | Must equal 28 |
| OUTPUT_COUNT | Must be ≥ 1 |
| OUTPUT_COUNT exact | ~20 expected; informational only |

---

## Known Limitations

- No ILA — observability is through STATUS, INPUT_COUNT, OUTPUT_COUNT, DEBUG_STATE registers only
- No DMA — samples transferred word-by-word via AXI-Lite reads/writes (slow but correct for bring-up)
- Known-vector only — not a real-time throughput test
- Not Phase 2 — no streaming redesign in this step
- Frame detection depends on Step 28 synthesis + RTL parameters matching the testbench
- The exact OUTPUT_COUNT may differ from simulation if frame_index or peak_lag differs in hardware

---

## Recommended Step 29B

1. Connect ZCU102 via JTAG (digilent_plugin or native Vivado cable drivers)
2. Connect UART (115200 baud)
3. Program bitstream via Vivado Hardware Manager or Vitis
4. Run known_vector_test.elf via Vitis or XSCT
5. Capture UART log
6. Report: INPUT_COUNT, OUTPUT_COUNT, RESULT PASS/FAIL
7. Copy log to `reports/step29b/step29b_uart_log.txt`
