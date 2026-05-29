# P3-14A Phase2 AXI-Lite Register File Analysis

**Source:** `rtl/phase2_axi_lite_regs.v` (P2-14 / P2-18 / P2-20D / P2-20E)

---

## 1. Address Map

All registers are 32-bit, byte-addressed. `ADDR_WIDTH=7` covers 0x00–0x7F.
VERSION constant: `0x00216001` (P2 / AXI-Lite rev / build 001).

| Addr | Name               | Width  | Access   | Notes                                          |
|------|--------------------|--------|----------|------------------------------------------------|
| 0x00 | CONTROL            | [1:0]  | R/W + W1S| bit0=enable(R/W), bit1=soft_reset_pulse(W1S)  |
| 0x04 | STATUS             | [0]    | R        | bit0=nco_locked_seen (live or snapshot)        |
| 0x08 | INPUT_COUNT        | [31:0] | R        | Input AXIS handshake counter (live/snap)       |
| 0x0C | OUTPUT_COUNT       | [31:0] | R        | Output AXIS handshake counter (live/snap)      |
| 0x10 | TIMING_LOCK_COUNT  | [31:0] | R        | Rising edges of timing_lock (live/snap)        |
| 0x14 | NCO_LOCKED_SEEN    | [0]    | R        | Duplicate of STATUS bit0 (live/snap)           |
| 0x18 | LAST_LOCK_INDEX    | [31:0] | R        | Sample index of last timing lock (live/snap)   |
| 0x1C | LAST_FRAC_PHASE    | [31:0] | R        | Q1.15 frac CFO, sign-extended 16→32 (snap)    |
| 0x20 | VERSION            | [31:0] | R        | Constant 0x00216001                            |
| 0x24 | INT_CFO_VALID      | [0]    | R/clear  | Sticky; read clears; triggers snapshot         |
| 0x28 | INT_CFO_ESTIMATE   | [31:0] | R        | Q1.15 int CFO, sign-extended 16→32 (snap)     |
| 0x2C | INT_CFO_LOCK_IDX   | [8:0]  | R        | Meyr correlator peak index (live)              |
| 0x30 | RESET_STATUS       | [1:0]  | R + W1C  | bit0=RESET_DONE(sticky W1C), bit1=PIPELINE_IDLE(live)|
| 0x34 | DEBUG_CONTROL      | [3:0]  | R/W      | bit0=BYPASS_ENABLE, bit1=FORCE_TLAST(self-clr), bit2=COUNTER_CLEAR(self-clr), bit3=DEBUG_MODE|
| 0x38 | FRAME_LEN_SAMPLES  | [11:0] | R/W      | Default 288 (NSC+CP_LEN); range 1–4095        |
| 0x3C | TLAST_COUNT        | [31:0] | R        | Output TLAST fires since last COUNTER_CLEAR    |
| 0x40 | ERROR_FLAGS        | [3:0]  | R + W1C  | Sticky; W1C per bit; set by wrapper logic      |

Total: 17 registers over 17 word addresses.

---

## 2. Control Bits

| Field               | Address | Bits  | Type    | Reset | Description                                   |
|---------------------|---------|-------|---------|-------|-----------------------------------------------|
| enable              | 0x00    | [0]   | R/W     | 0     | 1=pass data to core; 0=block S_AXIS           |
| soft_reset_pulse    | 0x00    | [1]   | W1S     | 0     | Write 1 to issue soft reset; reads back 0     |
| bypass_enable       | 0x34    | [0]   | R/W     | 0     | 1=route S_AXIS directly to M_AXIS             |
| force_tlast         | 0x34    | [1]   | W1S     | 0     | Fires next output TLAST; self-clears           |
| counter_clear       | 0x34    | [2]   | W1S     | 0     | Clears out_frame_cnt + tlast_count             |
| debug_mode          | 0x34    | [3]   | R/W     | 0     | Reserved for future diagnostics               |
| frame_len_samples   | 0x38    | [11:0]| R/W     | 288   | Output frame counter period                   |

---

## 3. Status Bits

| Field             | Address | Bits | Type | Source                          |
|-------------------|---------|------|------|---------------------------------|
| nco_locked_seen   | 0x04    | [0]  | R    | sticky from wrapper (Phase2 DUT nco_locked) |
| RESET_DONE        | 0x30    | [0]  | R/W1C| sticky; set by reset_done_i pulse |
| PIPELINE_IDLE     | 0x30    | [1]  | R    | live: (input_count == output_count) |

---

## 4. Counters

| Register          | Width  | Description                               |
|-------------------|--------|-------------------------------------------|
| INPUT_COUNT       | 32-bit | S_AXIS handshake beats accepted           |
| OUTPUT_COUNT      | 32-bit | M_AXIS handshake beats produced           |
| TIMING_LOCK_COUNT | 32-bit | Timing lock events (rising edge)          |
| TLAST_COUNT       | 32-bit | Output TLAST events since last clear      |

---

## 5. Debug / Status Snapshots

**Snapshot protocol (P2-20D):**

When SW reads `INT_CFO_VALID` (0x24) while the latch holds 1:
- All 7 status registers are frozen into shadow registers **simultaneously**.
- `snapshot_valid` latches until next trigger or reset.
- While `snapshot_valid=1`, reads of 0x04–0x1C and 0x28 return **shadow** values.

**Fields frozen in snapshot:**
- snap_nco_locked_seen
- snap_input_count
- snap_output_count
- snap_timing_lock_count
- snap_last_lock_index
- snap_last_frac_phase
- snap_int_cfo_estimate

**Purpose:** Guarantees all status reads are consistent with the same synchronization event.

---

## 6. Reset Behavior

On `aresetn=0`:
- enable_o = 0 (DUT blocked)
- soft_reset_pulse_o = 0
- bypass_enable_o = 0
- force_tlast_o = 0
- counter_clear_o = 0
- debug_mode_o = 0
- frame_len_samples_o = 12'd288
- All sticky latches (int_cfo_valid_latch, reset_done_latch, snapshot_valid) = 0
- error_flags_r = 4'b0
- AXI-Lite channel registers in reset state (awready=1, wready=1, bvalid=0, rvalid=0)

---

## 7. Write-One-to-Clear (W1C) Fields

| Register     | Addr  | Bits  | Clear condition                          |
|--------------|-------|-------|------------------------------------------|
| RESET_STATUS | 0x30  | [0]   | SW writes 1 to bit0 clears RESET_DONE   |
| ERROR_FLAGS  | 0x40  | [3:0] | SW writes 1 to each bit clears that bit  |
| INT_CFO_VALID| 0x24  | [0]   | Read clears (not write); also triggers snapshot |

---

## 8. ERROR_FLAGS (0x40) — Sticky W1C

Set by wrapper logic (`error_set_i` pulse input); SW clears by writing 1 to each bit.
Set takes priority over SW clear (same cycle).

| Bit | Name                | Set condition                                           |
|-----|---------------------|---------------------------------------------------------|
| 0   | FRAME_LEN_MISMATCH  | s_tlast at unexpected beat position (in_frame_cnt mismatch) |
| 1   | TLAST_TIMEOUT       | No output TLAST for > 8190 consecutive output beats     |
| 2   | RESET_WHILE_ACTIVE  | dut_aresetn fell while output_count > 0                 |
| 3   | STALL_TIMEOUT       | m_valid high, m_ready low for > 254 cycles              |

---

## 9. Software-Visible Fields (R/W Summary)

**Writable registers** (write returns OKAY; all others return SLVERR):
- 0x00 CONTROL
- 0x30 RESET_STATUS (W1C clear only)
- 0x34 DEBUG_CONTROL
- 0x38 FRAME_LEN_SAMPLES
- 0x40 ERROR_FLAGS (W1C clear only)

**Read-only registers** (writes return SLVERR):
- All others

---

## 10. Phase2 → Phase3 Reusability Assessment

| Field                   | Reuse decision         | Notes                                          |
|-------------------------|------------------------|------------------------------------------------|
| CONTROL (enable, srst)  | **Reuse directly**     | Same semantics                                 |
| VERSION constant        | **Replace**            | Phase3 = 0x00316001                            |
| INPUT_COUNT             | **Reuse directly**     | S_AXIS input beat counter                      |
| OUTPUT_COUNT            | **Reuse directly**     | M_AXIS output beat counter                     |
| TIMING_LOCK_COUNT       | **Replace**            | Phase3 has done_count / error_count instead    |
| NCO_LOCKED_SEEN         | **Drop**               | No NCO lock concept in Phase3                  |
| LAST_LOCK_INDEX         | **Replace**            | → FRAME_START_INDEX                            |
| LAST_FRAC_PHASE         | **Replace**            | → FRAC_CFO_PHASE (same Q1.15 format)           |
| INT_CFO_VALID           | **Reuse concept**      | Same sticky/snapshot trigger pattern           |
| INT_CFO_ESTIMATE        | **Replace**            | Phase3 int_cfo is 32-bit NCO step word         |
| INT_CFO_LOCK_IDX        | **Reuse as**           | INT_CFO_INDEX (peak_index from Meyr)            |
| RESET_STATUS            | **Reuse directly**     | Same semantics                                 |
| DEBUG_CONTROL           | **Reuse directly**     | Same bypass/force_tlast/counter_clear/debug    |
| FRAME_LEN_SAMPLES       | **Reuse, new default** | Default changes 288→576 for Phase3             |
| TLAST_COUNT             | **Reuse directly**     | Same semantics                                 |
| ERROR_FLAGS             | **Reuse directly**     | Same 4-bit W1C set                             |
| Snapshot protocol       | **Reuse concept**      | Snapshot trigger = INT_CFO_VALID read-while-set|

**Phase3 additions (new registers):**
- STATUS with busy/done_seen/error_seen/last_error_code
- FRAME_START_VALID (sticky latch, not in Phase2)
- FRAME_START_INDEX, PEAK_INDEX, SLOT_START_INDEX
- FRAC_CFO_VALID + FRAC_CFO_PHASE (Phase3 separates valid/data)
- PSS_DONE, SSS_DONE (future: not yet wired to phase3_sync_top)
- INT_CFO_APPLIED (future: replay buffer not connected)
