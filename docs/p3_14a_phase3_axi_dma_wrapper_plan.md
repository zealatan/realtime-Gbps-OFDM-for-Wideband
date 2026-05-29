# P3-14A Phase3 AXI-Lite / AXI-Stream DMA Wrapper Plan

**Task:** P3-14A  
**Date:** 2026-05-28

---

## 1. System Overview

```
PS (ARM Cortex-A9 / Vitis)
  │
  ├─── AXI-Lite M (ZYNQ GP0) ──► phase3_axi_lite_regs (control/status)
  │                                     │ enable, soft_reset, bypass, frame_len, ...
  │                                     ▼
  ├─── S_AXI_HP0 DMA ──────────► phase3_sync_axis_dma_wrapper
  │    (S_AXIS: raw IQ in)              │
  └─── S_AXI_HP1 DMA ◄─────────── M_AXIS (corrected IQ out, bypass only in P3-14A)
                                        │
                                        ▼
                                  phase3_sync_top
                                   ├── frac_cfo_frame_corrector_top
                                   ├── slot_start_controller
                                   ├── pss_sss_symbol_extractor
                                   └── meyr_integer_cfo_fft_frontend_top
```

**Phase3 DUT note:** `phase3_sync_top` is a start/done module, not a streaming producer.
It accepts an IQ stream input but does not emit a corrected output stream at the top ports.
M_AXIS in this wrapper is **S_AXIS passthrough (bypass)** until the integer CFO replay
buffer and second corrector are connected in a future step.

---

## 2. Phase3 Register Map

**ADDR_WIDTH = 7** (byte-addressed, 0x00–0x7F; all registers at 4-byte-aligned addresses)  
**VERSION constant = `32'h00316001`** (Phase3 / AXI-Lite / rev 1)  
**DATA_WIDTH = 32**

### 2.1 Complete Map

| Addr | Name               | Width  | Access    | Description                                              |
|------|--------------------|--------|-----------|----------------------------------------------------------|
| 0x00 | VERSION            | [31:0] | R         | Constant 0x00316001                                      |
| 0x04 | CONTROL            | [1:0]  | R/W + W1S | [0]=enable, [1]=soft_reset_pulse(W1S, reads 0)           |
| 0x08 | STATUS             | [7:0]  | R + W1C   | [0]=busy(live), [1]=done_seen(W1C), [2]=error_seen(W1C), [7:4]=last_error_code |
| 0x0C | FRAME_LEN_SAMPLES  | [11:0] | R/W       | Output TLAST period, default 576 (FRAME_LEN=2×(256+32)) |
| 0x10 | INPUT_COUNT        | [31:0] | R         | S_AXIS accepted beat counter                             |
| 0x14 | OUTPUT_COUNT       | [31:0] | R         | M_AXIS produced beat counter                             |
| 0x18 | FRAME_START_VALID  | [0]    | R/clear   | Sticky; read clears; set by dbg_frame_start_valid        |
| 0x1C | FRAME_START_INDEX  | [11:0] | R         | Latched from dbg_frame_start_index (or snapshot)         |
| 0x20 | PEAK_INDEX         | [8:0]  | R         | Latched from dbg_peak_index (or snapshot)                |
| 0x24 | SLOT_START_INDEX   | [11:0] | R         | Latched from dbg_slot_start_index (or snapshot)          |
| 0x28 | FRAC_CFO_VALID     | [0]    | R/clear   | Sticky; read clears; set by dbg_frac_cfo_valid           |
| 0x2C | FRAC_CFO_PHASE     | [31:0] | R         | Q1.15 frac CFO word, sign-extended 16→32 (or snapshot)  |
| 0x30 | PSS_DONE           | [0]    | R/clear   | Sticky; TODO: not wired to phase3_sync_top yet           |
| 0x34 | SSS_DONE           | [0]    | R/clear   | Sticky; TODO: not wired to phase3_sync_top yet           |
| 0x38 | INT_CFO_VALID      | [0]    | R/clear   | Sticky; read clears; set by dbg_integer_cfo_valid; **triggers snapshot** |
| 0x3C | INT_CFO_EST        | [31:0] | R         | 32-bit NCO step word from dbg_integer_cfo_word (or snapshot) |
| 0x40 | INT_CFO_INDEX      | [8:0]  | R         | Meyr peak index; TODO: not wired (peak_index tied off in phase3_sync_top) |
| 0x44 | INT_CFO_APPLIED    | [0]    | R         | Sticky; set when replay+corrector applied; TODO: not wired |
| 0x48 | RESET_STATUS       | [1:0]  | R + W1C   | [0]=RESET_DONE(sticky W1C), [1]=PIPELINE_IDLE(live)      |
| 0x4C | DEBUG_CONTROL      | [3:0]  | R/W       | [0]=BYPASS_ENABLE, [1]=FORCE_TLAST, [2]=COUNTER_CLEAR, [3]=DEBUG_MODE |
| 0x50 | TLAST_COUNT        | [31:0] | R         | M_AXIS TLAST fires since last COUNTER_CLEAR               |
| 0x54 | ERROR_FLAGS        | [3:0]  | R + W1C   | [0]=FRAME_LEN_MISMATCH, [1]=TLAST_TIMEOUT, [2]=RESET_WHILE_ACTIVE, [3]=STALL_TIMEOUT |

Total: 22 registers. All others: SLVERR.

### 2.2 Write-Permitted Register Set

RESP_OKAY is returned for writes to: CONTROL, STATUS, FRAME_LEN_SAMPLES, RESET_STATUS, DEBUG_CONTROL, ERROR_FLAGS.
All other addresses return RESP_SLVERR on write.

---

## 3. Snapshot Protocol

**Trigger:** SW reads INT_CFO_VALID (0x38) while `int_cfo_valid_latch = 1`.

**Effect:**
- `snapshot_valid` latches to 1.
- All 5 phase3_sync_top result registers are frozen simultaneously:
  - `snap_frame_start_index`
  - `snap_peak_index`
  - `snap_slot_start_index`
  - `snap_frac_cfo_phase`
  - `snap_int_cfo_est`

**While `snapshot_valid = 1`:**
- Reads of 0x1C, 0x20, 0x24, 0x2C, 0x3C return snapshot values.
- Snapshot invalidates on next trigger or on reset.

**Rationale:** All Phase3 sync results are derived from the same frame synchronization event.
Freezing them atomically on INT_CFO_VALID ensures SW reads a consistent set.

---

## 4. Signal Mapping: phase3_sync_top → Register Inputs

### 4.1 Available ports (direct wiring)

| phase3_sync_top port        | Width  | Register module input     | Target register(s)              |
|-----------------------------|--------|---------------------------|---------------------------------|
| busy                        | 1      | busy_i                    | STATUS[0] (live)                |
| done                        | 1      | done_pulse_i              | STATUS[1] done_seen latch       |
| error                       | 1      | error_i                   | STATUS[2] error_seen (on done)  |
| error_code                  | [3:0]  | error_code_i              | STATUS[7:4] last_error_code     |
| dbg_frame_start_valid       | 1      | frame_start_valid_i       | 0x18 FRAME_START_VALID latch    |
| dbg_frame_start_index       | [11:0] | frame_start_index_i       | 0x1C latched / snapshot         |
| dbg_peak_index              | [8:0]  | peak_index_i              | 0x20 latched / snapshot         |
| dbg_slot_start_valid        | 1      | slot_start_valid_i        | (latch trigger for 0x24)        |
| dbg_slot_start_index        | [11:0] | slot_start_index_i        | 0x24 latched / snapshot         |
| dbg_frac_cfo_valid          | 1      | frac_cfo_valid_i          | 0x28 FRAC_CFO_VALID latch       |
| dbg_frac_cfo_word           | [15:0] | frac_cfo_phase_i          | 0x2C sign-extended / snapshot   |
| dbg_integer_cfo_valid       | 1      | int_cfo_valid_i           | 0x38 INT_CFO_VALID, snapshot    |
| dbg_integer_cfo_word        | [31:0] | int_cfo_est_i             | 0x3C / snapshot                 |

Note: `dbg_frame_start_valid`, `dbg_peak_valid`, and `dbg_frac_cfo_valid` are all the same
signal (`frac_frac_phase_valid`) in phase3_sync_top. The register module receives a single
`frame_start_valid_i` that latches all three simultaneously.

### 4.2 TODO (not yet exposed by phase3_sync_top)

| Register          | Missing port                  | Unblock path                               |
|-------------------|-------------------------------|--------------------------------------------|
| PSS_DONE (0x30)   | PSS extraction done signal    | Expose from pss_sss_symbol_extractor done  |
| SSS_DONE (0x34)   | SSS extraction done signal    | Same; separate PSS/SSS done ports needed   |
| INT_CFO_INDEX     | peak_index from meyr_integer  | Connect peak_index in u_meyr_fft inst.     |
| INT_CFO_APPLIED   | replay+corrector done pulse   | P3-10B replay buffer + second corrector    |

---

## 5. Wrapper Architecture

### 5.1 Module Hierarchy

```
phase3_sync_axis_dma_wrapper
  ├── phase3_axi_lite_regs     (AXI-Lite register bank)
  └── phase3_sync_top          (Algorithm DUT — NOT modified)
```

### 5.2 Enable / Bypass Gating

| int_enable | int_bypass_en | S_AXIS → DUT | M_AXIS source   |
|------------|---------------|--------------|-----------------|
| 0          | x             | blocked      | disabled (0)    |
| 1          | 0             | flowing      | TODO (0 for now)|
| 1          | 1             | blocked      | S_AXIS passthru |

### 5.3 Auto-Rearm Start Logic

The wrapper drives `start` to `phase3_sync_top`:
- After `dut_aresetn` rising edge: `start_armed = 1`
- After `done` with no error: `start_armed = 1` (re-arm for next frame)
- After error (`done && error`): `start_armed = 0` (stop until soft_reset)
- When `int_enable && start_armed && !busy`: pulse `start`, clear `start_armed`

### 5.4 TLAST Generation

Counter-based M_AXIS TLAST identical to Phase2:
- `out_frame_cnt` counts M_AXIS accepted beats
- TLAST fires when `out_frame_cnt >= frame_len_samples_o - 1`
- `FORCE_TLAST` (sticky latch from DEBUG_CONTROL[1]) fires immediately on next beat
- `COUNTER_CLEAR` (DEBUG_CONTROL[2]) clears `out_frame_cnt` and `tlast_count`

### 5.5 Soft Reset

```
dut_aresetn = aresetn && !soft_reset_r
soft_reset_r <= int_soft_reset   // one-cycle pipeline
reset_done_w = dut_aresetn && !dut_aresetn_prev   // rising edge
```

### 5.6 Error Detection (Wrapper-Level)

Same four flags as Phase2, fed to `error_set_i`:
- `FRAME_LEN_MISMATCH`: s_tlast at wrong in_frame_cnt position
- `TLAST_TIMEOUT`: 8190 consecutive output beats without TLAST
- `RESET_WHILE_ACTIVE`: dut_aresetn fell while output_count > 0
- `STALL_TIMEOUT`: m_valid high, m_ready low for > 254 cycles

---

## 6. Runtime Configuration Ports of phase3_sync_top

`phase3_sync_top` has three runtime config inputs that are **constant-tied** in this
wrapper (future: expose via AXI-Lite registers):

| Port             | Width | Tied to                        |
|------------------|-------|--------------------------------|
| threshold_in     | 40    | THRESHOLD parameter (default 10_240_000) |
| window_len_in    | 7     | WINDOW_LEN parameter (default 25)        |
| hit_count_in     | 4     | HIT_COUNT parameter (default 10)         |

---

## 7. Files Created

| File                                  | Status   |
|---------------------------------------|----------|
| docs/p3_14a_phase2_axi_lite_regs_analysis.md | Created |
| docs/p3_14a_phase3_axi_dma_wrapper_plan.md   | This file |
| rtl/phase3_axi_lite_regs.v            | Created  |
| rtl/phase3_sync_axis_dma_wrapper.v    | Created  |
| tb/phase3_axi_dma_wrapper_smoke_tb.sv | Created  |
| scripts/run_p3_14a_axi_dma_wrapper_smoke.sh  | Created  |

---

## 8. Open Integration Points

1. **M_AXIS corrected stream:** Currently passthrough only. When P3-10B (replay buffer)
   connects the second frac_cfo_corrector, the wrapper's M_AXIS should carry the int-CFO-
   corrected IQ stream. INT_CFO_APPLIED register will track this.

2. **PSS_DONE / SSS_DONE:** Requires exposing done signals from `pss_sss_symbol_extractor`
   in `phase3_sync_top`. Minor phase3_sync_top change needed.

3. **INT_CFO_INDEX:** `u_meyr_fft.peak_index` is tied to () in phase3_sync_top. Expose
   as a top-level port to populate 0x40.

4. **threshold_in / window_len_in / hit_count_in:** Add 3 AXI-Lite R/W registers to allow
   runtime tuning of the frame detector without re-synthesizing.

5. **Snapshot scope:** Current snapshot only covers sync result registers. Could be extended
   to include STATUS and input/output counts for a full frame-consistent snapshot.

---

## 9. Recommended Next Step

- **P3-14B:** After smoke compile passes, wire INT_CFO_INDEX by exposing `u_meyr_fft.peak_index`
  as a top-level debug port in phase3_sync_top (single-line change, safe).
- **P3-10B:** Connect iq_replay_buffer_576 + second frac_cfo_corrector_top as outlined in
  P3-06 spec. Update wrapper M_AXIS and INT_CFO_APPLIED register.
- **Vitis:** Import phase3_sync_axis_dma_wrapper as a Vivado IP; connect to Zynq GP0
  AXI-Lite and HP0/HP1 DMA.
