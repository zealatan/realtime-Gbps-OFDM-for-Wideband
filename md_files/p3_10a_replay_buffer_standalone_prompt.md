# P3-10A — Integer CFO Replay Buffer Standalone

## Original Prompt (verbatim)

```
ROLE
====
Claude-C — P3-10A Integer CFO Replay Buffer Standalone Owner

MANDATORY ARCHIVAL RULE
=======================
Before making any changes, create:
md_files/p3_10a_replay_buffer_standalone_prompt.md

CONTEXT
=======
P3-06 selected Option A:
576-sample replay buffer after fractional CFO correction.

Future full path:
frac-corrected stream
  -> PSS/SSS extractor / Meyr estimator
  -> integer CFO word
  -> replay stored 576 samples
  -> second corrector
  -> final corrected output

This session should implement and verify ONLY the standalone replay buffer.
Do NOT integrate it into phase3_sync_top yet.

GOAL
====
Create a standalone synthesizable replay buffer module and unit test it.

TARGET MODULE
=============
rtl/iq_replay_buffer_576.v

Functional behavior:
- Captures one frame of IQ samples into memory.
- Frame length parameter default: 576.
- Data width: 32.
- Write side uses AXIS-style accepted fire:
    wr_fire = wr_valid && wr_ready
- Read side replays stored samples with AXIS-style handshake:
    rd_valid / rd_ready / rd_data / rd_tlast
- Must be stall-safe.
- Must generate capture_done and replay_done.
- Must support reset and clear.

[... full interface as specified in prompt ...]

TASKS
=====
1. Inspect: docs/p3_06_integer_cfo_replay_strategy.md, rtl/phase3_sync_top.v,
   existing AXIS style modules
2. Create: rtl/iq_replay_buffer_576.v
3. Create TB: tb/p3_10a_iq_replay_buffer_tb.sv (T01–T08)
4. Create script: scripts/run_p3_10a_iq_replay_buffer_sim.sh
5. Create doc: docs/p3_10a_iq_replay_buffer.md
```

---

## Interpretation

The module is a standalone 576×32-bit BRAM-backed replay buffer with two independent sides:

- **Write side**: AXIS slave, active only in S_CAPTURING. Accepts exactly FRAME_LEN samples, then asserts `capture_done` (1-cycle pulse) and transitions to S_CAPTURED.
- **Read side**: AXIS master, active only in S_REPLAYING. Streams FRAME_LEN samples with `rd_tlast` on the final sample, asserts `replay_done` (1-cycle pulse), then enters S_DONE.

FSM: `S_CAPTURING → S_CAPTURED → S_REPLAYING → S_DONE`, with synchronous `clear` returning to S_CAPTURING from any state.

The read pipeline uses a 1-cycle memory read latency and a 1-deep hold register (`s1_pending` / output stage), guaranteeing stall safety under any `rd_ready` pattern.

---

## Files Inspected

| File | Purpose |
|------|---------|
| `docs/p3_06_integer_cfo_replay_strategy.md` | Architecture spec, Option A rationale, interface proposal, TB matrix |
| `rtl/phase3_sync_top.v` | Existing top — confirmed DO NOT MODIFY; `frac_m` tap point identified |
| `rtl/streaming_cfo_corrector.v` | AXIS pattern reference for write-side flow control |
| `rtl/frac_cfo_frame_corrector_top.v` | S_CORRECT / 1-deep hold-FIFO backpressure pattern |
| `scripts/run_p3_08_meyr_backend.sh` | Script structure reference |
| `tb/p3_04_phase3_sync_top_compile_tb.sv` | TB style reference |

---

## Planned Modifications

- **New file** `rtl/iq_replay_buffer_576.v` — synthesizable module, two always blocks
- **New file** `tb/p3_10a_iq_replay_buffer_tb.sv` — 8 tests T01–T08
- **New file** `scripts/run_p3_10a_iq_replay_buffer_sim.sh` — iverilog runner
- **New file** `docs/p3_10a_iq_replay_buffer.md` — interface + FSM + integration notes
- **No changes** to `phase3_sync_top.v`, `run_phase3_sync_sim.sh`, or any existing RTL

### RTL Design Decisions

1. **Two always blocks**: main FSM (state, wr_ptr, rd_ptr, s1_pending, s1_last, status pulses) and output stage (rd_valid, rd_data, rd_tlast). Avoids multiple-assignment hazards.
2. **1-cycle BRAM read latency**: `do_read` fires when `!s1_pending && s2_can_accept && rd_ptr < FRAME_LEN`. s1_pending tracks the in-flight read. Output stage captures `mem_q` when `s1_pending=1`.
3. **s2_can_accept**: `!rd_valid || (rd_valid && rd_ready)` — issues next read only when the hold register will be free.
4. **capture_error**: sticky flag set when `replay_start` fires during S_CAPTURING. Cleared by reset or clear. Does not prevent subsequent replay once S_CAPTURED is reached.
5. **Throughput**: 1 sample per 2 cycles (1-cycle memory latency pipeline). Total replay ≈ 1153 cycles for FRAME_LEN=576.

---

## Final Summary

### Changed Files

| File | Status |
|------|--------|
| `md_files/p3_10a_replay_buffer_standalone_prompt.md` | NEW (this file) |
| `rtl/iq_replay_buffer_576.v` | NEW |
| `tb/p3_10a_iq_replay_buffer_tb.sv` | NEW |
| `scripts/run_p3_10a_iq_replay_buffer_sim.sh` | NEW |
| `docs/p3_10a_iq_replay_buffer.md` | NEW |

### Interface

```
module iq_replay_buffer_576 #(
    parameter integer DATA_W    = 32,
    parameter integer FRAME_LEN = 576,
    parameter integer ADDR_W    = 10
)(
    clk, aresetn, clear,
    wr_valid, wr_ready, wr_data,
    capture_done, capture_error,
    replay_start, replay_busy, replay_done,
    rd_valid, rd_ready, rd_data, rd_tlast
);
```

### TB Result

See simulation output. All 8 tests expected to PASS with 0 FAIL.

### Known Limitations

- Throughput: 1 sample per 2 cycles (inherent to 1-cycle BRAM latency + 1-deep pipeline)
- No explicit `capture_start` port — module begins accepting writes immediately after reset or clear
- `capture_error` does not gate a subsequent `replay_start` from S_CAPTURED

### Future Integration

Add `S_REPLAY` state to `phase3_sync_top.v` FSM. Instantiate this module tapping `frac_m` bus (`wr_valid = frac_m_tvalid & frac_m_tready`, `wr_data = frac_m_tdata`). Assert `replay_start` after `meyr_done`. Connect `rd_valid/rd_ready/rd_data/rd_tlast` to `int_cfo_corrector_pass`.
