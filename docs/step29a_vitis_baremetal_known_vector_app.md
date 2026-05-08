# Step 29A — Vitis Baremetal Known-Vector Control Application

## Goal

Prepare a Vitis 2022.2 baremetal C application for the ZCU102 Phase 1 FPGA bring-up.
The application tests `frac_cfo_sync_bram_test_wrapper` via direct AXI-Lite access from
the Cortex-A53 APU.

Board execution (programming + UART capture) is deferred to Step 29B.

No ILA, DMA, Linux, or networking.

---

## Phase 1 Context

| Phase | Description |
|-------|-------------|
| **1 (current)** | Functional FPGA synchronizer: PS writes IQ to BRAM, triggers run, reads results |
| 2 | 1 sample/clock streaming synchronizer |
| 3 | Multi-sample/clock parallel synchronizer |

---

## Relationship to Step 28

Step 28 produced the hardware platform artifacts:

| Artifact | Path |
|----------|------|
| Bitstream | `outputs/step28/sync_phase1_bd_wrapper.bit` |
| XSA (hardware platform) | `outputs/step28/sync_phase1_bd_wrapper.xsa` |

**Note on XSA bitstream embedding:** `write_hw_platform -include_bit` failed in Step 28.
The XSA was generated without the embedded bitstream using `write_hw_platform -fixed -force`.
Step 29B must program the bitstream separately before running the application.

---

## Hardware Address Map

| Region | Address | Width | Access |
|--------|---------|-------|--------|
| wrapper_0 AXI-Lite slave | 0xA0000000 | 64 KB | R/W |
| Input memory window | 0xA0001000–0xA0001FFF | 1024 × 32-bit | R/W |
| Output memory window | 0xA0002000–0xA0002FFF | 1024 × 32-bit | R/O |

### Register Offsets

| Offset | Register | Access | Notes |
|--------|----------|--------|-------|
| 0x0000 | CONTROL | W/R | See bit table below |
| 0x0004 | STATUS | R/O | See bit table below |
| 0x0008 | CFG_CFO_STEP | W/R | NCO step word |
| 0x000C | CFG_TIMING_OFFSET | W/R | Timing offset (unused for basic test) |
| 0x0010 | CFG_FRAME_LEN | W/R | Frame length config |
| 0x0014 | INPUT_LEN | W/R | Number of input samples to stream |
| 0x0018 | OUTPUT_MAX_LEN | W/R | Output capture limit |
| 0x001C | INPUT_COUNT | R/O | Samples streamed to DUT |
| 0x0020 | OUTPUT_COUNT | R/O | Samples captured to output_mem |
| 0x0024 | DEBUG_STATE | R/O | FSM state code |
| 0x0028 | ERROR_STATUS | R/O | Error sticky flags |

### CONTROL Register Bit Fields (verified from `rtl/frac_cfo_sync_bram_test_wrapper.v` line 272–277)

| Bit | Name | Type | Description |
|-----|------|------|-------------|
| 0 | start_pulse | auto-clear | Triggers DUT start; auto-clears next clock |
| 1 | soft_reset | auto-clear | Resets DUT + clears sticky flags |
| 2 | clr_status | auto-clear | Clears sticky flags only |
| 3 | enable | sticky | Must be 1 for start_pulse to launch DUT |

### STATUS Register Bit Fields (verified from RTL lines 346–357)

| Bit | Name | Description |
|-----|------|-------------|
| 0 | dut_busy | DUT (frac_cfo_frame_corrector_top) busy |
| 1 | done_sticky | Set when DUT completes; clear by clr_status |
| 2 | running | Stream source/sink active |
| 3 | input_done | Source FSM reached SRC_DONE |
| 4 | output_done | Sink FSM reached SNK_DONE |
| 5 | input_underflow_sticky | Source exhausted before INPUT_LEN |
| 6 | output_overflow_sticky | output_mem full before DUT finished |
| 7 | done_sticky (dup) | Same as bit 1 |
| 8 | frame_error_sticky | DUT: no frame found |

### IQ Packing Convention

```
tdata[15: 0] = I (real, Q1.15 signed)  — lower 16 bits
tdata[31:16] = Q (imaginary, Q1.15 signed) — upper 16 bits

Packed word = ((u32)(s16)Q << 16) | (u32)(u16)I
```

---

## Known-Vector Design

Mirrors Step 26 testbench T7 (`load_known_vector(8, 20)`):

| Parameter | Value |
|-----------|-------|
| Quiet samples | 8 (I=0, Q=0 → 0x00000000) |
| Active samples | 20 (I=100, Q=0 → 0x00000064) |
| Total INPUT_LEN | 28 |
| OUTPUT_MAX_LEN | 64 |
| CFG_CFO_STEP | 0 |
| CFG_TIMING_OFFSET | 0 |
| CFG_FRAME_LEN | 28 |

**Expected results (from Step 26 simulation):**

| Register | Expected |
|----------|----------|
| INPUT_COUNT | 28 (hard requirement) |
| OUTPUT_COUNT | ~20 (informational; depends on frame detection in synthesized design) |
| done_sticky | 1 (hard requirement) |
| frame_error | 0 (hard requirement) |
| ERROR_STATUS | 0 (hard requirement) |

---

## C Application Flow

```
main()
 │
 ├─[1] Soft reset (CONTROL = CTRL_SOFT_RESET; wait; clear)
 │
 ├─[2] Clear status (CONTROL = CTRL_CLR_STATUS; wait; clear)
 │
 ├─[3] Write 28 known samples to input memory window
 │       for i in 0..27: sync_mem_write(INPUT_MEM_BASE, i, known_input[i])
 │
 ├─[4] Zero 64 words of output memory window
 │
 ├─[5] Write config registers
 │       CFG_CFO_STEP=0, CFG_TIMING_OFFSET=0, CFG_FRAME_LEN=28
 │       INPUT_LEN=28, OUTPUT_MAX_LEN=64
 │
 ├─[6] Enable + start
 │       CONTROL = CTRL_ENABLE
 │       CONTROL = CTRL_ENABLE | CTRL_START_PULSE
 │
 ├─[7] Poll STATUS until done_sticky || frame_error || timeout
 │       Print debug line every 200,000 polls
 │
 ├─[8] Read final STATUS, ERROR_STATUS, INPUT_COUNT, OUTPUT_COUNT, DEBUG_STATE
 │
 ├─[9] Evaluate pass/fail
 │       FAIL if: !done_sticky || frame_error || error_status!=0
 │             || INPUT_COUNT!=28 || OUTPUT_COUNT<1
 │
 ├─[10] Print first min(OUTPUT_COUNT, 16) output samples
 │        Index, hex word, decoded I, decoded Q
 │
 └─[11] Print "RESULT: PASS" or "RESULT: FAIL"; return 0 or 1
```

---

## Software Files

| File | Description |
|------|-------------|
| `sw/step29a_vitis_known_vector/src/main.c` | Main application |
| `sw/step29a_vitis_known_vector/register_map.h` | Register map, bit defs, accessors |
| `sw/step29a_vitis_known_vector/known_vector.h` | Test stimulus array |
| `sw/step29a_vitis_known_vector/README.md` | Vitis GUI steps + UART setup |

---

## Vitis Build Assumptions

- Vitis 2022.2, standalone BSP, psu_cortexa53_0
- BSP provides: `xil_printf.h`, `xil_io.h`, `xil_types.h`, `sleep.h`
- No dynamic memory (`malloc`/`free` not used)
- No floating-point printf (xil_printf used throughout)
- Baremetal only — no FreeRTOS, no Linux

---

## Board Requirements for Step 29B

| Requirement | Notes |
|-------------|-------|
| ZCU102 Rev 1.0 | Part xczu9eg-ffvb1156-2-e |
| Vivado/Vitis 2022.2 | Windows |
| JTAG cable | USB to JTAG (Digilent or compatible) |
| UART cable | Micro-USB J83 on ZCU102 (Silicon Labs CP2108) |
| UART baud | 115200, 8N1, no flow control |
| Power supply | ZCU102 12V DC |

---

## Expected UART Output (successful run)

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
  done_sticky asserted after NNNN polls

[8] Final register state:
  STATUS=0x00000082  ERR=0x00000000
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
| done_sticky | Must be 1 | Hard fail |
| frame_error | Must be 0 | Hard fail |
| ERROR_STATUS | Must be 0 | Hard fail |
| INPUT_COUNT | Must equal 28 | Hard fail |
| OUTPUT_COUNT | Must be ≥ 1 | Hard fail |
| OUTPUT_COUNT exact | ~20 expected | Informational only |

---

## Limitations

- No ILA — observability through STATUS, INPUT_COUNT, OUTPUT_COUNT, DEBUG_STATE only
- No DMA — word-by-word AXI-Lite transfers (sufficient for 28-sample known-vector)
- Known-vector only — not a real-time throughput test
- Phase 1 only — no Phase 2 streaming redesign
- Frame detection result depends on synthesis: exact OUTPUT_COUNT may differ from simulation
- XSA does not contain embedded bitstream — must program separately in Step 29B

---

## Execution Status

**Prepared — pending Vitis workspace creation and ZCU102 board bring-up (Step 29B).**

---

## Recommended Step 29B

1. Connect ZCU102 (JTAG + UART)
2. Power on ZCU102
3. Program bitstream via Vivado Hardware Manager: `outputs/step28/sync_phase1_bd_wrapper.bit`
4. Open Vitis 2022.2, import XSA, build `known_vector_test.elf`
5. Launch on hardware via Vitis or XSCT
6. Capture UART terminal output (115200 baud)
7. Report: `INPUT_COUNT`, `OUTPUT_COUNT`, `RESULT: PASS/FAIL`
8. Copy log to `reports/step29b/step29b_uart_log.txt`
