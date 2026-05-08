# Step 29B — ZCU102 Vitis Bring-Up and UART Known-Vector Test

## Goal

Execute the Phase 1 known-vector test on physical ZCU102 hardware.
Program the FPGA with the Step 28 bitstream, build and run the Step 29A Vitis baremetal
application, and capture the UART output.

Board execution is **required** for this step.

---

## Required Artifacts

| Artifact | Path | Status |
|----------|------|--------|
| FPGA bitstream | `outputs/step28/sync_phase1_bd_wrapper.bit` | GENERATED (Step 28) |
| Hardware platform XSA | `outputs/step28/sync_phase1_bd_wrapper.xsa` | GENERATED (Step 28) |
| Main C application | `sw/step29a_vitis_known_vector/src/main.c` | PREPARED (Step 29A) |
| Register map header | `sw/step29a_vitis_known_vector/register_map.h` | PREPARED (Step 29A) |
| Known vector header | `sw/step29a_vitis_known_vector/known_vector.h` | PREPARED (Step 29A) |

**Note on XSA:** `write_hw_platform -include_bit` failed in Step 28.
The XSA does not contain the embedded bitstream. The bitstream must be programmed
separately via Vivado Hardware Manager before running the application.

---

## Required Hardware

| Item | Notes |
|------|-------|
| ZCU102 Rev 1.0 | Part `xczu9eg-ffvb1156-2-e` |
| Power supply | 12V DC barrel connector |
| JTAG cable | USB Micro-B to JTAG (Digilent plug or native Vivado cable driver) |
| UART cable | Micro-USB J83 (Silicon Labs CP2108 USB-to-quad-UART) |
| Windows PC | Vivado 2022.2 + Vitis 2022.2 installed |
| UART terminal | PuTTY, TeraTerm, or Windows Terminal with serial support |

---

## Step 1 — Board Physical Setup

### 1a. Boot Mode

Set ZCU102 SW6 to **JTAG boot mode** so the PS does not attempt to boot from SD card
or QSPI. JTAG mode allows Vitis/Vivado to download the ELF and start execution.

SW6 positions for JTAG boot mode (ZCU102 Rev 1.0):

```
SW6[4:1] = 0000  (all switches to the JTAG/OFF position)
```

Verify on the ZCU102 schematic or UG1182 (ZCU102 Evaluation Board User Guide).

### 1b. Cable Connections

1. Connect JTAG cable from PC USB to ZCU102 J2 (USB Micro-B JTAG/UART combo)
   **or** connect a Digilent cable to J55 (14-pin JTAG).
2. Connect UART cable from PC USB to ZCU102 J83 (USB Micro-B UART).
3. Connect 12V power supply to ZCU102 J52.

### 1c. Power On

Move ZCU102 power switch SW1 to ON. The DONE LED (DS3) should illuminate green
after a few seconds (this indicates the PS is alive; the PL is not yet programmed).

---

## Step 2 — UART Terminal Setup

1. Open Windows Device Manager → **Ports (COM & LPT)**.
2. Find **Silicon Labs Quad CP2108 USB to UART Bridge** — it exposes 4 COM ports.
3. Use the **first (lowest-numbered) COM port** — this is Interface 0, which is the
   primary PS UART0 used by the baremetal standalone BSP.
4. Open your terminal application and configure:

| Setting | Value |
|---------|-------|
| Baud rate | **115200** |
| Data bits | 8 |
| Stop bits | 1 |
| Parity | None |
| Flow control | None |

Keep the terminal window open throughout the run.

---

## Step 3 — Program the FPGA Bitstream

Because the XSA does not contain the embedded bitstream, program the PL separately
using Vivado Hardware Manager **before** launching the Vitis application.

### Method A — Vivado Hardware Manager (recommended)

1. Open Vivado 2022.2.
2. Click **Open Hardware Manager** → **Open Target** → **Auto Connect**.
3. Vivado should detect `xczu9eg_0` under `localhost`.
4. Right-click the device → **Program Device**.
5. Bitstream file: `C:\RTL_SYNC\outputs\step28\sync_phase1_bd_wrapper.bit`
6. Debug probes file: leave blank (no ILA).
7. Click **Program**.
8. Wait for the **DONE LED (DS3)** on ZCU102 to turn green — PL programming is complete.

### Method B — Vitis Integrated Programming

If Vitis is configured to also program the PL (common when the XSA includes the
bitstream), it may attempt this automatically. Since the XSA here does **not** include
the bitstream, use Method A first, then proceed to Vitis for the ELF.

---

## Step 4 — Create Vitis Platform and Application

Perform these steps in Vitis 2022.2 on Windows.

### 4a. Open Vitis and Create Workspace

1. Launch Vitis 2022.2.
2. When prompted for a workspace, set: `C:\RTL_SYNC\vitis\step29`
3. Click **Launch**.

### 4b. Create Hardware Platform from XSA

1. **File → New → Platform Project**
2. Project name: `sync_phase1_platform`
3. Click **Next**
4. Select **Create from hardware specification (XSA)**
5. XSA file: `C:\RTL_SYNC\outputs\step28\sync_phase1_bd_wrapper.xsa`
6. Operating system: **standalone**
7. Processor: **psu_cortexa53_0** (Cortex-A53 APU, core 0)
8. Click **Finish**
9. Wait for BSP build to complete (Console shows `Build Finished`).

### 4c. Create Application Project

1. **File → New → Application Project**
2. Platform: `sync_phase1_platform`
3. Project name: `known_vector_test`
4. Processor: `psu_cortexa53_0`
5. OS: `standalone`
6. Language: **C**
7. Template: **Hello World** (or Empty Application)
8. Click **Finish**

### 4d. Add Source Files

1. In the Explorer panel, navigate to `known_vector_test/src/`
2. Delete the template `helloworld.c` (or any existing `main.c`).
3. In Vitis: right-click `src` → **Import Sources** → add each file:
   - `C:\RTL_SYNC\sw\step29a_vitis_known_vector\src\main.c`
   - `C:\RTL_SYNC\sw\step29a_vitis_known_vector\register_map.h`
   - `C:\RTL_SYNC\sw\step29a_vitis_known_vector\known_vector.h`

   Alternatively, use Windows Explorer to copy those files directly into the
   `C:\RTL_SYNC\vitis\step29\known_vector_test\src\` folder, then refresh in Vitis.

### 4e. Build the Application

1. Right-click `known_vector_test` → **Build Project**
2. Monitor the Console. A successful build ends with:
   ```
   Finished building: known_vector_test.elf
   ```
3. ELF location: `C:\RTL_SYNC\vitis\step29\known_vector_test\Debug\known_vector_test.elf`

---

## Step 5 — Run the Application

The FPGA must already be programmed (Step 3) before launching the ELF.

### Method A — Vitis Debug Launch

1. Right-click `known_vector_test` → **Run As → Launch on Hardware (Single Application Debug)**
2. Vitis uploads the ELF to the Cortex-A53 and starts execution.
3. Monitor the UART terminal for output.

### Method B — XSCT Command-Line

Open a terminal and run XSCT (`C:\Xilinx\Vitis\2022.2\bin\xsct.bat`):

```tcl
connect
targets -set -filter {name =~ "Cortex-A53*#0"}
rst -processor
dow {C:/RTL_SYNC/vitis/step29/known_vector_test/Debug/known_vector_test.elf}
con
```

Watch the UART terminal for output.

---

## Step 6 — Capture UART Output

When the application finishes, it prints a final line:
```
RESULT: PASS
```
or
```
RESULT: FAIL
```

**Immediately copy the full UART terminal text** and save it to:

```
C:\RTL_SYNC\reports\step29b\step29b_uart_log.txt
```

Then copy to WSL:

```bash
cp /mnt/c/RTL_SYNC/reports/step29b/step29b_uart_log.txt \
   /home/zealatan/RTL_SYNC/reports/step29b/step29b_uart_log.txt
```

---

## Expected UART Output (Successful Run)

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

[10] First 16 output samples:
  idx   hex_word   I(dec)   Q(dec)
    0   0x........   .....   .....
    ...

========================================
RESULT: PASS
========================================
```

---

## Pass/Fail Criteria

| Check | Condition | Hard/Soft |
|-------|-----------|-----------|
| `done_sticky` | Must be 1 | Hard fail |
| `frame_error_sticky` (STATUS bit 8) | Must be 0 | Hard fail |
| `ERROR_STATUS` | Must be 0 | Hard fail |
| `INPUT_COUNT` | Must equal 28 | Hard fail |
| `OUTPUT_COUNT` | Must be ≥ 1 | Hard fail |
| `OUTPUT_COUNT` exact | ~20 expected | Informational only |

---

## Register Map Summary (for manual debug)

Base address: **0xA0000000**

| Offset | Register |
|--------|----------|
| 0x0000 | CONTROL |
| 0x0004 | STATUS |
| 0x0008 | CFG_CFO_STEP |
| 0x000C | CFG_TIMING_OFFSET |
| 0x0010 | CFG_FRAME_LEN |
| 0x0014 | INPUT_LEN |
| 0x0018 | OUTPUT_MAX_LEN |
| 0x001C | INPUT_COUNT |
| 0x0020 | OUTPUT_COUNT |
| 0x0024 | DEBUG_STATE |
| 0x0028 | ERROR_STATUS |
| 0x1000 | Input memory window (1024 × 32-bit) |
| 0x2000 | Output memory window (1024 × 32-bit) |

### CONTROL Bits (write)

| Bit | Name | Notes |
|-----|------|-------|
| 0 | start_pulse | Auto-clears next clock |
| 1 | soft_reset | Auto-clears next clock |
| 2 | clr_status | Auto-clears next clock |
| 3 | enable | Sticky — must be 1 when start_pulse fires |

### STATUS Bits (read)

| Bit | Name |
|-----|------|
| 0 | dut_busy |
| 1 | done_sticky |
| 2 | running |
| 3 | input_done |
| 4 | output_done |
| 5 | input_underflow_sticky |
| 6 | output_overflow_sticky |
| 8 | frame_error_sticky |

---

## Debug Checklist — If Result Is FAIL

Work through these checks in order.

**If UART shows no output:**
- Confirm UART terminal is on the correct COM port (lowest-numbered Interface 0 of the CP2108).
- Confirm baud rate is exactly 115200.
- Confirm the ELF was loaded and the processor started (`con` in XSCT, or Vitis Run launch).
- Confirm ZCU102 power is on and DONE LED is green.

**If application hangs in poll loop:**
- STATUS never sets `done_sticky` (bit 1).
- Check CONTROL write sequence: enable (bit 3) must be set **before** start_pulse (bit 0).
  The application sets `CTRL_ENABLE` then `CTRL_ENABLE | CTRL_START_PULSE` — do not set
  only `CTRL_START_PULSE` without enable.
- Check that the bitstream was programmed **before** the ELF launched.
- Read `DEBUG_STATE` from the poll debug lines — FSM state 2 is running source/sink;
  state 4 is DONE. If it stays at 0 (IDLE), the start pulse may not have registered.

**If `frame_error_sticky` (STATUS bit 8) is set:**
- The DUT searched all input samples and found no synchronization frame.
- Verify the known vector was written correctly: `quiet[0]=0x00000000`, `active[8]=0x00000064`.
- Verify `INPUT_LEN=28` was written before start.
- Verify `CFG_FRAME_LEN=28` was written (DUT uses this as the CP detection length).

**If `INPUT_COUNT` ≠ 28:**
- The stream source FSM did not complete correctly.
- Check `ERROR_STATUS` for `input_underflow` (bit 0).
- Verify `INPUT_LEN` register was written before start.

**If `OUTPUT_COUNT` = 0:**
- The DUT ran but produced no output samples — frame detection may have failed internally.
- Check `frame_error_sticky`.
- `OUTPUT_COUNT` = 0 with `done_sticky` = 1 may indicate the frame was found at a position
  where no samples fit the output window — unusual for this known vector.

**If `done_sticky` is not set after timeout:**
- The application printed `TIMEOUT reached`.
- The POLL_TIMEOUT_COUNT in `main.c` is set to 2,000,000 iterations.
- At 100 MHz clock, the DUT should complete in well under 1 ms for 28 samples.
- If timeout is reached, the PL may not be responding to AXI-Lite — re-check bitstream programming.

---

## Artifacts to Save

After a successful run, save:

| File | Description |
|------|-------------|
| `reports/step29b/step29b_uart_log.txt` | Full UART terminal capture |

Optional additional artifacts:

| File | Description |
|------|-------------|
| `reports/step29b/step29b_result.md` | Short summary: INPUT_COUNT, OUTPUT_COUNT, RESULT |
| `reports/step29b/step29b_vivado_hw_session.log` | Vivado Hardware Manager console log if available |

---

## Execution Status

| Task | Status |
|------|--------|
| FPGA programmed | NOT RUN |
| Vitis platform created | NOT RUN |
| Application built | NOT RUN |
| Application run on ZCU102 | NOT RUN |
| UART output captured | NOT RUN |
| Result classified | NOT RUN |

**Board required:** Yes

**RTL modified:** No

---

## Recommended Step 30

After Step 29B UART capture and PASS confirmation:

- If RESULT is PASS: document hardware correlation between simulation (Step 21 PASS=176) and
  hardware. Consider Step 30 = ILA integration for deeper in-hardware debug visibility, or
  Step 30 = Phase 2 streaming redesign per the project roadmap.

- If RESULT is FAIL: use the debug checklist above and the UART register dump to diagnose.
  Do not start Phase 2 until Phase 1 hardware is verified.
