# Session F2 / P3-17B: Board DMA Replay Validation

**Date:** 2026-05-28  
**Status:** BOARD_GATE: BLOCKED — bitstream not yet generated  
**Hardware:** Zynq ZC7020 (xc7z020clg400-1), AXI DMA + AXI-Lite  
**DUT:** `phase3_sync_axis_dma_wrapper` (P3-14B RTL)

---

## 1. Objective

Full DMA replay validation of the Phase3 synchronization pipeline on real Zynq
hardware.  The test drives the golden IQ stimulus over AXI DMA, monitors the
Phase3 AXI-Lite register bank, and verifies that frame detection, fractional
CFO correction, Meyr integer CFO estimation, and replay-buffer integer CFO
correction all produce the expected observable outputs on silicon.

This session follows the P3-17A smoke test (which confirmed AXI-Lite and DMA
infrastructure works) and adds tight algorithm-level tolerance checks with
structured failure classification.

---

## 2. Checks (17 total)

### Class R — Reset

| ID | Description | Expected |
|----|-------------|----------|
| R0 | Soft reset → RESET_DONE latch observed | RESET_DONE=1 within timeout |
| R1 | ERROR_FLAGS == 0 after reset | 0x00000000 |

### Class A — AXI-Lite

| ID | Description | Expected |
|----|-------------|----------|
| A0 | VERSION readable and correct | 0x00316001 |
| A1 | CONTROL enable bit R/W | Write 1, read back 1 |
| A2 | STATUS bus responds | Any value (bus-alive check) |
| A3 | FRAME_LEN_SAMPLES R/W | Write 576, read back 576 |

### Class D — DMA

| ID | Description | Expected |
|----|-------------|----------|
| D0 | DMA init (XAxiDma_CfgInitialize) | XST_SUCCESS |
| D1 | DMA RX channel starts | XST_SUCCESS |
| D2 | DMA TX channel starts | XST_SUCCESS |
| D3 | Both DMA channels complete without deadlock | No poll timeout |

### Class T — Timing (beat counts)

| ID | Description | Expected |
|----|-------------|----------|
| T0 | INPUT_COUNT == 704 | Exact match |
| T1 | OUTPUT_COUNT == 576 | Exact match |
| T2 | TLAST_COUNT >= 1 | ≥ 1 |

### Class G — Algorithm observables

| ID | Description | Expected | Source |
|----|-------------|----------|--------|
| G0 | INT_CFO_VALID observed (snapshot triggered) | 1 within 500 ms | — |
| G1 | INT_CFO_APPLIED == 1 (replay completed) | 1 | P3-16A |
| G2 | FRAME_START_INDEX in [40, 42] | 41 ± 1 | P3-16A |
| G3 | PEAK_INDEX (CP peak lag) in [22, 24] | 23 ± 1 | P3-16A |
| G4 | SLOT_START_INDEX in [63, 65] | 64 ± 1 | P3-16A |
| G5 | Output buffer contains nonzero samples | At least 1 nonzero | P3-16A |

---

## 3. BOARD_GATE Definition

| Gate output | Condition |
|-------------|-----------|
| `BOARD_GATE: PASS` | All 17 checks pass |
| `BOARD_GATE: PARTIAL_PASS` | Classes R, A, D, T pass; class G fails (algorithm out of tolerance) |
| `BOARD_GATE: FAIL_AXI` | Class A check(s) failed |
| `BOARD_GATE: FAIL_DMA` | Class D check(s) failed (start error) |
| `BOARD_GATE: FAIL_DEADLOCK` | DMA started but RX or TX never completed |
| `BOARD_GATE: FAIL_RESET` | R0 or R1 failed |
| `BOARD_GATE: FAIL_TIMING` | T0/T1/T2 failed (beat count mismatch) |
| `BOARD_GATE: BLOCKED` | Hardware prerequisites missing (no bitstream) |

Multiple failure classes may be active simultaneously; all are printed in the
failure class summary line before the gate output.

---

## 4. Failure Classification Guide

| Class | Likely root causes |
|-------|--------------------|
| **AXI-Lite** | Wrong `SYNC_BASEADDR`, bitstream not programmed, PS-PL clock mismatch, wrong board |
| **DMA** | Wrong `DMA_BASEADDR`, DMA device ID ≠ 0, AXI interconnect missing, BSP config |
| **Deadlock** | S_AXIS backpressure stall (M_AXIS not ready), FIFO overflow, FSM stuck in reset |
| **Timing** | `FRAME_LEN` register not written before enable, TLAST generation error, DMA length misconfigured |
| **Reset** | Clock domain crossing issues, async reset not synchronized, ERROR_FLAGS from prior run |
| **Algorithm** | Wrong THRESHOLD value for amplitude=3000 stimulus (needs 40000 not 10240000), FFT path mismatch |

---

## 5. Simulation Baseline

All algorithm tolerance bands are derived from the P3-16A INTEGRATION_GATE: PASS
simulation (iverilog 11.0, 2026-05-28):

| Observable | Simulation | Hardware tolerance | Notes |
|------------|------------|-------------------|-------|
| FRAME_START_INDEX | 40 | 40–42 (±1) | frame_index=41 with ±1 tol |
| PEAK_INDEX | 23 | 22–24 (±1) | VanDeBeek CP autocorr peak |
| SLOT_START_INDEX | 63 | 63–65 (±1) | = frame_index + peak_lag |
| FRAC_CFO_PHASE | 3278 | informational | Q1.15 word, ≈ +0.05 frac CFO |
| INT_CFO_VALID | observed | required | triggers snapshot |
| INT_CFO_EST | 0xFF000000 | informational | NCO step = −2^24 for k_int=0 |
| INT_CFO_INDEX | 256 | informational | 255+1 bypass-FFT ±1 offset |
| INT_CFO_APPLIED | 1 | exact | replay + rotation done |
| OUTPUT_COUNT | 576 | exact | |
| TLAST_COUNT | 1 | ≥ 1 | |

---

## 6. Hardware Prerequisites

### 6.1 Bitstream

A Phase3 bitstream does not yet exist.  To generate one:

1. Open Vivado (tested config: 2023.1, part xc7z020clg400-1).
2. Create a block design with:
   - Zynq PS (ZC7020 preset)
   - `phase3_sync_axis_dma_wrapper` as an AXI-Lite slave
   - Xilinx AXI DMA v7.x connected to `phase3_sync_axis_dma_wrapper` S_AXIS / M_AXIS
3. Run synthesis, implementation, generate bitstream.
4. Export hardware (`.xsa`) with bitstream included.

> **Note:** The `THRESHOLD` parameter in `phase3_sync_top` is fixed at synthesis
> time.  For the golden amplitude=3000 stimulus used here, set `THRESHOLD=40000`.
> The production value (for full-amplitude signals) is 10240000.

### 6.2 Base Addresses

Update the two `#define` lines in
`vitis/session_F2_p3_17b_board_dma_validation.c` to match the Vivado
**Address Editor** output:

```c
#define SYNC_BASEADDR   0x43C00000U   /* phase3_sync_axis_dma_wrapper AXI-Lite */
#define DMA_BASEADDR    0x40400000U   /* Xilinx AXI DMA                         */
```

The values above are typical for AXI GP0 on Zynq-7000; confirm against your
block design.

### 6.3 DMA Device ID

If the AXI DMA is not the first DMA in the system, change:

```c
dma_cfg = XAxiDma_LookupConfig(0);   /* 0 = first DMA in xparameters.h */
```

Check `xparameters.h` (generated by Vitis from the XSA) for the correct
`XPAR_AXIDMA_*_DEVICE_ID`.

---

## 7. Build and Run

### Windows (with Vitis installed)

```bat
cd RTL_SYNC_PHASE3

rem First run: program bitstream then validate
scripts\windows\run_session_F2_p3_17b_board_dma_validation.bat --program

rem Subsequent runs (bitstream already loaded)
scripts\windows\run_session_F2_p3_17b_board_dma_validation.bat

rem Build ELF only without connecting to board
scripts\windows\run_session_F2_p3_17b_board_dma_validation.bat --build-only

rem Extend timeout to 120 s if pipeline takes longer
scripts\windows\run_session_F2_p3_17b_board_dma_validation.bat --timeout 120000
```

### Expected terminal output (PASS)

```
========================================================
P3-17B Board DMA Replay Validation
  SYNC_BASEADDR = 0x43C00000
  DMA_BASEADDR  = 0x40400000
========================================================

--- [Reset] ---
  [ 0] R0: soft reset → RESET_DONE observed            PASS
  [ 1] R1: ERROR_FLAGS clear after reset               PASS

--- [AXI-Lite] ---
  VERSION = 0x00316001 (expect 0x00316001)
  [ 2] A0: VERSION == 0x00316001                       PASS
  [ 3] A1: CONTROL enable bit R/W                      PASS
  [ 4] A2: STATUS bus responds (readable)              PASS
  FRAME_LEN = 576 (expect 576)
  [ 5] A3: FRAME_LEN_SAMPLES R/W (576)                 PASS

--- [DMA] ---
  [ 6] D0: DMA init (XAxiDma_CfgInitialize)            PASS
  [ 7] D1: DMA RX channel start                        PASS
  [ 8] D2: DMA TX channel start                        PASS

--- [DMA completion] ---
  [ 9] D3: DMA completes without deadlock              PASS

--- [Timing / beat counts] ---
  INPUT_COUNT  = 704 (expect 704)
  [10] T0: INPUT_COUNT == 704 (STIM_LEN)               PASS
  OUTPUT_COUNT = 576 (expect 576)
  [11] T1: OUTPUT_COUNT == 576 (FRAME_LEN)             PASS
  TLAST_COUNT  = 1 (expect >= 1)
  [12] T2: TLAST_COUNT >= 1                            PASS

--- [Algorithm observables] ---
  INT_CFO_EST     = 0xFF000000 (expect 0xFF000000 for k_int=0)
  INT_CFO_INDEX   = 256 (expect 255-256)
  INT_CFO_APPLIED = 1 (expect 1)
  FRAME_START_IDX = 40 (expect 40-42)
  PEAK_INDEX      = 23 (expect 22-24, peak lag)
  SLOT_START_IDX  = 63 (expect 63-65)
  FRAC_CFO_PHASE  = 3278 Q1.15 (expect ~3277-3278)
  [13] G0: INT_CFO_VALID observed (snapshot triggered)  PASS
  [14] G1: INT_CFO_APPLIED == 1 (replay completed)      PASS
  [15] G2: FRAME_START_INDEX in [40, 42]                PASS
  [16] G3: PEAK_INDEX (lag) in [22, 24]                 PASS
  [17] G4: SLOT_START_INDEX in [63, 65]                 PASS
  [18] G5: output buffer contains nonzero samples       PASS

========================================================
Summary
  Checks passed: 17 / 17
========================================================
BOARD_GATE: PASS
```

---

## 8. Register Map Reference

| Offset | Name | Access | Notes |
|--------|------|--------|-------|
| 0x00 | VERSION | R | Constant 0x00316001 |
| 0x04 | CONTROL | R/W | bit0=enable, bit1=soft_reset (W1S) |
| 0x08 | STATUS | R/W1C | bit0=busy, bit1=done_seen, bit2=error_seen |
| 0x0C | FRAME_LEN_SAMPLES | R/W | [11:0] default 576 |
| 0x10 | INPUT_COUNT | R | S_AXIS accepted beats |
| 0x14 | OUTPUT_COUNT | R | M_AXIS accepted beats |
| 0x18 | FRAME_START_VALID | R/clr | Sticky; read clears |
| 0x1C | FRAME_START_INDEX | R | Latched on FRAME_START_VALID |
| 0x20 | PEAK_INDEX | R | VanDeBeek CP peak lag |
| 0x24 | SLOT_START_INDEX | R | = FRAME_START_INDEX + PEAK_INDEX |
| 0x28 | FRAC_CFO_VALID | R/clr | Sticky; read clears |
| 0x2C | FRAC_CFO_PHASE | R | Q1.15 frac CFO word, sign-extended 16→32 |
| 0x38 | INT_CFO_VALID | R/clr | Sticky; read clears; **triggers snapshot** |
| 0x3C | INT_CFO_EST | R | 32-bit NCO step word (snapshot) |
| 0x40 | INT_CFO_INDEX | R | Meyr peak index (snapshot) |
| 0x44 | INT_CFO_APPLIED | R | 1 after replay + rotation done |
| 0x48 | RESET_STATUS | R/W1C | bit0=RESET_DONE, bit1=PIPELINE_IDLE |
| 0x50 | TLAST_COUNT | R | Output TLAST count |
| 0x54 | ERROR_FLAGS | R/W1C | [3:0] sticky error flags |

### Snapshot protocol

Reading `INT_CFO_VALID` (0x38) while the latch holds 1 simultaneously freezes
`FRAME_START_INDEX`, `PEAK_INDEX`, `SLOT_START_INDEX`, `FRAC_CFO_PHASE`, and
`INT_CFO_EST` into shadow registers.  All subsequent reads of those offsets
return the frozen snapshot values until the latch is cleared.

---

## 9. IQ Stimulus

The embedded `iq_stim[]` array is a verbatim copy of
`golden/phase3_iq_stimulus.mem` (generated by
`scripts/gen_phase3_iq_stimulus.py`):

| Field | Value |
|-------|-------|
| Total samples | 704 × 32-bit words |
| Transfer size | 2816 bytes |
| Structure | [zeros×64] [CP1+S1=288] [CP2+S2=288] [zeros×64] |
| Amplitude | 3000 per component (I and Q) |
| Word format | bits[31:16]=Q, bits[15:0]=I (signed 16-bit each) |
| Non-zero range | indices 64–639 |

---

## 10. Known Limitations

| Limitation | Notes |
|------------|-------|
| Bitstream not yet generated | Synthesis + implementation from Phase3 RTL required |
| THRESHOLD synthesis-time fixed | Must resynthesize with THRESHOLD=40000 for amplitude=3000 stimulus |
| Bypass FFT on hardware | `fft256_dual_symbol_frontend` is a time-domain bypass; INT_CFO_INDEX ≈ 255/256 for k_int=0 input only |
| DMA_BASEADDR placeholder | Confirm against xparameters.h generated by Vitis from the XSA |
| Windows-only bat runner | xsct is Windows-native on Vivado 2023.1; Linux Vitis users can adapt the TCL script manually |
| One frame only | After 576-beat replay the DUT re-arms but finds no IQ input; TLAST_COUNT expected to stay at 1 |

---

## 11. Relationship to Prior Sessions

| Session | Gate | Scope |
|---------|------|-------|
| P3-14C (Session C) | OFFICIAL_GATE: PASS | DMA replay golden compare (iverilog) |
| P3-15A (Session D) | FULL_C_GOLDEN_GATE: PASS | Full C-reference equivalence (iverilog) |
| P3-13C (Session B) | OFFICIAL_GATE: PASS | Real Xilinx FFT IP xsim sweep |
| P3-16A (Session E) | INTEGRATION_GATE: PASS | End-to-end Phase3 regression (iverilog) |
| **P3-17A (Session F)** | **SMOKE_GATE: BLOCKED** | Board smoke (AXI-Lite + DMA infra) |
| **P3-17B (Session F2)** | **BOARD_GATE: BLOCKED** | **This session — full board DMA replay** |

P3-17B requires P3-17A SMOKE_GATE: PASS as a prerequisite.

---

## 12. Files Created (P3-17B)

| File | Description |
|------|-------------|
| `vitis/session_F2_p3_17b_board_dma_validation.c` | Vitis standalone C validation (17 checks, failure classification) |
| `scripts/windows/run_session_F2_p3_17b_board_dma_validation.bat` | Windows xsct build + run script |
| `docs/session_F2_p3_17b_board_dma_validation.md` | This document |
