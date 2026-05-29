# P3-10A — iq_replay_buffer_576

## 1. Overview

`rtl/iq_replay_buffer_576.v` is a standalone synthesizable replay buffer that captures exactly `FRAME_LEN` IQ samples from an AXIS-style write port into block RAM, then streams all stored samples to an AXIS-style read port on a one-shot replay request. It is the on-chip storage component required for the Option A integer CFO correction path selected in P3-06.

---

## 2. Interface

```verilog
module iq_replay_buffer_576 #(
    parameter integer DATA_W    = 32,   // IQ sample width {Q[31:16], I[15:0]}
    parameter integer FRAME_LEN = 576,  // 2*(NSC+CP_LEN): NSC=256, CP_LEN=32
    parameter integer ADDR_W    = 10    // 2^10 = 1024 >= 576 (BRAM18E2 depth)
)(
    input  wire              clk,
    input  wire              aresetn,    // active-low async reset
    input  wire              clear,      // sync clear: any state → S_CAPTURING

    // Write side (AXIS slave — capture)
    input  wire              wr_valid,
    output wire              wr_ready,   // asserted only in S_CAPTURING
    input  wire [DATA_W-1:0] wr_data,

    // Capture status
    output reg               capture_done,   // 1-cycle pulse: FRAME_LEN samples stored
    output reg               capture_error,  // sticky: premature replay_start detected

    // Replay control
    input  wire              replay_start,   // 1-cycle pulse to begin replay
    output reg               replay_busy,    // high throughout S_REPLAYING
    output reg               replay_done,    // 1-cycle pulse: last sample consumed

    // Read side (AXIS master — replay output)
    output reg               rd_valid,
    input  wire              rd_ready,
    output reg  [DATA_W-1:0] rd_data,
    output reg               rd_tlast        // asserts on sample index FRAME_LEN-1
);
```

### Signal summary

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| `clk` | in | 1 | System clock |
| `aresetn` | in | 1 | Async active-low reset |
| `clear` | in | 1 | Sync return to S_CAPTURING |
| `wr_valid` | in | 1 | Write data valid |
| `wr_ready` | out | 1 | Write accepted (= state==S_CAPTURING) |
| `wr_data` | in | 32 | Write data {Q[31:16], I[15:0]} |
| `capture_done` | out | 1 | 1-cycle pulse: FRAME_LEN writes completed |
| `capture_error` | out | 1 | Sticky: replay_start during S_CAPTURING |
| `replay_start` | in | 1 | 1-cycle pulse: start replay (S_CAPTURED only) |
| `replay_busy` | out | 1 | Asserted throughout S_REPLAYING |
| `replay_done` | out | 1 | 1-cycle pulse: last sample consumed by downstream |
| `rd_valid` | out | 1 | AXIS valid |
| `rd_ready` | in | 1 | AXIS ready from consumer |
| `rd_data` | out | 32 | AXIS data |
| `rd_tlast` | out | 1 | AXIS last: high on sample index FRAME_LEN-1 |

---

## 3. FSM

```
         aresetn=0 or clear
         ┌─────────────────────────────────────────────┐
         ▼                                             │
   ┌─────────────┐  FRAME_LEN wr_fires   ┌────────────┴──────┐
   │ S_CAPTURING │ ────────────────────► │    S_CAPTURED     │
   └─────────────┘  + capture_done pulse └───────────────────┘
         │ replay_start                         │ replay_start
         │ → capture_error=1 (stay)             ▼
         │                             ┌───────────────────┐
         │                             │   S_REPLAYING     │
         │                             │   replay_busy=1   │
         │                             └───────────────────┘
         │                                       │ last sample consumed
         │                                       │ + replay_done pulse
         │                                       ▼
         │                             ┌───────────────────┐
         └──────────────────────────── │      S_DONE       │
                  (via clear)          └───────────────────┘
```

### State descriptions

| State | `wr_ready` | `replay_busy` | Description |
|-------|-----------|--------------|-------------|
| `S_CAPTURING` | 1 | 0 | Accepting writes; counter 0..FRAME_LEN-1 |
| `S_CAPTURED`  | 0 | 0 | Capture complete; waiting for `replay_start` |
| `S_REPLAYING` | 0 | 1 | Streaming stored samples to rd_* output |
| `S_DONE`      | 0 | 0 | Replay complete; waiting for `clear` |

---

## 4. Memory Behavior

- RAM type: `(* ram_style = "block" *)` — infers one Xilinx BRAM18E2 in simple dual-port mode (write port for capture, read port for replay).
- Depth: 2^ADDR_W = 1024 entries (576 used).
- Width: DATA_W = 32 bits.
- **Write**: synchronous on `wr_fire = wr_valid & wr_ready`. Address = `wr_ptr` (0..575), auto-incremented.
- **Read**: 1-cycle registered latency via `mem_q` register. Address = `rd_ptr` (0..575) at the cycle `do_read` fires.

### Read pipeline detail

```
Cycle T:   do_read=1 → issue address rd_ptr to memory → s1_pending=1, rd_ptr++
Cycle T+1: mem_q = mem[rd_ptr_T] (stable)
           s1_pending=1 → output stage: rd_data<=mem_q, rd_valid<=1, rd_tlast<=s1_last
           Main FSM: s1_pending<=0
Cycle T+2: rd_valid=1; rd_ready=1 → sample consumed
```

The `do_read` signal is asserted only when:
- State is `S_REPLAYING`
- No read is in flight (`!s1_pending`)
- Output stage has room (`s2_can_accept = !rd_valid | (rd_valid & rd_ready)`)
- More samples remain (`rd_ptr < FRAME_LEN`)

---

## 5. Stall Safety

The 1-deep output hold register (`rd_valid/rd_data/rd_tlast`) ensures no sample is lost under any `rd_ready` pattern:

- When `rd_ready=0`: `s2_can_accept=0` → no new read issued → `rd_valid` stable
- When `rd_ready=1` while `rd_valid=1`: sample consumed AND new read issued simultaneously → pipeline stays full
- Minimum throughput: 1 sample per 2 clock cycles (1 BRAM read latency + 1 hold register)
- Total replay duration: ≈ 1,153 clock cycles for FRAME_LEN=576

`rd_tlast` is generated internally from `s1_last` (set when `rd_ptr == FRAME_LEN-1` at read issue time) and propagated into the output hold register. It fires exactly on the final sample regardless of backpressure.

---

## 6. Error Conditions

| Signal | Condition | Cleared by |
|--------|-----------|------------|
| `capture_error` | `replay_start` asserted during `S_CAPTURING` | reset or `clear` |

`capture_error` is sticky (informational). It does **not** prevent replay once `S_CAPTURED` is reached. If `replay_start` fires on the same cycle as the 576th write (the boundary), `capture_error` is set but `capture_done` also fires; the module enters `S_CAPTURED` normally and replay proceeds on the next `replay_start`.

---

## 7. Testbench (T01–T08)

File: `tb/p3_10a_iq_replay_buffer_tb.sv`

| ID | Name | Pass criterion |
|----|------|----------------|
| T01 | Reset defaults | `wr_ready=1`, all other outputs=0 |
| T02 | Capture 576 samples | `fires==576`, `capture_done=1` after last fire, `wr_ready` goes 0 |
| T03 | Replay 576 samples, tlast on last | `rx_count==576`, `rd_tlast` only on idx 575, data matches |
| T04 | Backpressure during replay | 50-cycle stall at idx 100; same pass criteria as T03 |
| T05 | Clear mid-capture | Clear at sample 100; fresh 576-sample capture completes |
| T06 | Premature `replay_start` | `capture_error=1`, replay not started; capture still completes; full replay succeeds |
| T07 | Two back-to-back with clear | Both capture+replay cycles pass; second uses different data |
| T08 | Randomized `rd_ready` stalls | ~50% stall rate; all 576 samples received, data intact |

---

## 8. Synthesis Resource Estimate (Xilinx Artix/Kintex/Zynq)

| Resource | Count | Notes |
|----------|-------|-------|
| BRAM18E2 | 1 | 576×32b = 18,432b < BRAM18 capacity |
| LUT (FSM, counters) | ~60–80 | 2-bit state, 10-bit write/read ptrs, comparators |
| FF | ~70 | state, ptrs, pipeline regs, output regs |
| DSP | 0 | No arithmetic beyond counters |

---

## 9. Simulation Environment

- Simulator: iverilog 11.0 (`/usr/bin/iverilog -g2012`)
- Run: `bash scripts/run_p3_10a_iq_replay_buffer_sim.sh`
- Output: per-test PASS/FAIL, CI_GATE summary

---

## 10. Future Integration Notes

When integrating into `phase3_sync_top.v`:

1. Add `S_REPLAY` state after `S_RUN` (between `meyr_done` and `S_DONE`).
2. Instantiate `iq_replay_buffer_576` at top level. Connect:
   - `wr_valid = frac_m_tvalid & frac_m_tready`  (passive tap, no backpressure)
   - `wr_data  = frac_m_tdata`
   - `clear    = frac_start_r`  (reset write pointer on each new frame)
   - `replay_start` = 1-cycle pulse when entering `S_REPLAY`
3. Instantiate `int_cfo_corrector_pass` (second NCO+rotator). Connect replay buffer output → corrector input.
4. Feed `int_cfo_step_word_r` → corrector step word.
5. Add top-level ports: `replay_busy`, `replay_done`, `m_int_cfo_tdata/tvalid/tready/tlast`.

The write side tap is purely observational — the `frac_m` stream to `pss_sss_symbol_extractor` is unchanged.

---

## 11. Known Limitations

- **No concurrent capture+replay**: write and replay are mutually exclusive (different FSM states). This is by design; the replay happens after the entire frame is captured and the Meyr estimator has completed (~130K cycles).
- **Single-shot per clear**: after `S_DONE`, a `clear` is required before the next capture. No auto-wrap.
- **1 sample/2 cycle throughput**: limited by BRAM read latency pipeline. Not a bottleneck given the ~130K cycle Meyr latency overhead.
- **No timeout watchdog**: `replay_start` ignored unless in `S_CAPTURED`. An external watchdog (in `phase3_sync_top`) should guard against `meyr_done` never firing.
