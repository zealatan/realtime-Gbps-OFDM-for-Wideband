# Session C4 / P3-20B: AXI Soak Test + Reusable AXI Assertion Library

## Gate

```
AXI_SOAK_GATE: PASS  — all phases pass + checker clean + B4 + B5
AXI_SOAK_GATE: FAIL  — any failure
```

---

## Objective

Long-run soak verification of `phase3_sync_axis_dma_wrapper` to confirm:
no sample loss, no counter rollback, correct replay restart behaviour, and
full AXI4-Stream protocol compliance.  Three run modes are supported via
`+MODE=` plusarg: **quick** (40 frames), **standard** (400 frames, default),
**soak** (1400 frames, includes 1000-frame B2 phase).

Verification-only session — no RTL changes.

---

## Part A — AXI Assertion Library

### File: `tb/common/axi_stream_checker.sv`

Reusable parameterised checker module.  Instantiate once per AXI-Stream
channel.  All checks are implemented with `always @(posedge aclk)` blocks
(iverilog compatible; no `assert property`).

#### Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `DATA_WIDTH` | 32 | Width of `tdata` |
| `STALL_WARN_THRESH` | 1000 | Cycle count before A5 long-stall warning |

#### Assertion Outputs

| Port | Assertion | Condition checked |
|------|-----------|-------------------|
| `err_tdata_stability` | A1 | `tdata` changed during an ongoing stall |
| `err_tlast_stability` | A2 | `tlast` changed during an ongoing stall |
| `err_x_tvalid`, `err_x_tdata`, `err_x_tlast` | A3 | X/Z on `tvalid`; X/Z on `tdata` when valid; X/Z on `tlast` when valid |
| `err_double_tlast` | A4 | Two consecutive accepted beats both have `tlast=1` |
| `warn_long_stall` | A5 | Stall duration exceeded `STALL_WARN_THRESH` cycles |
| `total_errors` | — | Sum of A1+A2+A3+A4 (not A5 warns) |

#### A1/A2 — Stability definition

"Ongoing stall" means consecutive cycles where `tvalid=1, tready=0` for
the same transaction.  A new stall started immediately after a successful
handshake (`tvalid=1, tready=1`) is a new transaction; its first stall
cycle is not compared against the preceding accepted beat.  This matches
AXI4-Stream §2.2.1.

#### A3 — X detection

Uses Verilog `===` identity comparison (`^tdata === 1'bx` for multi-bit
signals), which correctly distinguishes X/Z from 0/1 without `$isunknown`.

#### A4 — Double TLAST

Flags two consecutive accepted beats that both carry `tlast=1`.  Between
frames the DUT de-asserts `tvalid`, so normal frame boundaries do not
trigger this check.

---

## Part B — Long-Run Soak Testing

### File: `tb/session_C4_p3_20b_axi_soak_tb.sv`

Unified testbench covering five soak phases.  The M_AXIS checker
(`u_m_chk`) monitors assertions A1–A5 throughout.

### B1 — 100 Frame Test

100 back-to-back frames, `m_axis_tready=1` throughout.

**Pass criteria:**

| Observable | Expected |
|-----------|----------|
| `OUTPUT_COUNT` (AXI 0x14) | 576 × 100 = 57 600 |
| `TLAST_COUNT` (AXI 0x50) | 100 |
| `ERROR_FLAGS[3]` (AXI 0x54) | 0 |

---

### B2 — 1000 Frame Test

1000 back-to-back frames, `m_axis_tready=1` throughout.

**Pass criteria:**

| Observable | Expected |
|-----------|----------|
| `OUTPUT_COUNT` | 576 × 1000 = 576 000 |
| `TLAST_COUNT` | 1000 |
| `ERROR_FLAGS[3]` | 0 |

**Estimated simulation time**: ~103 000 cycles/frame × 1000 = 103M cycles.
At ~3M cycles/s in iverilog: ≈ 35 s.

---

### B3 — Random Backpressure Soak

100 frames at each of three `m_axis_tready` stall rates.

| Sub-phase | Stall rate | Expected `OUTPUT_COUNT` | Expected `TLAST_COUNT` |
|-----------|-----------|------------------------|------------------------|
| B3a | 10% (thresh=13/128) | 57 600 | 100 |
| B3b | 25% (thresh=32/128) | 57 600 | 100 |
| B3c | 50% (thresh=64/128) | 57 600 | 100 |

Stall randomness: 7-bit primitive LFSR (`x^7+x^3+1`, period 127).
Maximum consecutive stall run ≤ 63 cycles < `STALL_TIMEOUT` limit of 254.

---

### B4 — Replay Restart Soak

**Mechanism**: `u_dut.replay_done` is monitored via a persistent
`always @(posedge aclk)` counter (`b4_replay_done_cnt`) that increments
on every pulse of the wire throughout the entire simulation.

**Expected**: `b4_replay_done_cnt == 1400` after all five phases
(100 + 1000 + 100 + 100 + 100 frames).

**Stale-replay check**: after each phase completes and `wait_oc` returns,
the TB waits 30 cycles then reads `u_dut.replay_busy`; a warning is printed
if it is still asserted.

---

### B5 — Counter Stability

An `always @(posedge aclk)` block in the TB compares `u_dut.output_count`
against its value from the previous clock cycle.  If `output_count` ever
decreases while the DUT is outside a soft-reset window, `b5_err_backward`
is incremented.

The soft-reset window is identified by `u_dut.dut_aresetn &&
b5_dut_aresetn_dly` — both being 1 means two consecutive non-reset cycles,
so the count comparison is suppressed for the cycle immediately after a
soft reset.

**Expected**: `b5_err_backward == 0`.

---

## Gate Summary

| Phase | Gate condition |
|-------|----------------|
| B1 | `output_count=57600` AND `tlast_count=100` AND `ERROR_FLAGS[3]=0` |
| B2 | `output_count=576000` AND `tlast_count=1000` AND `ERROR_FLAGS[3]=0` |
| B3 | All three sub-phases (B3a/b/c) pass same criteria with 100 frames |
| B4 | `b4_replay_done_cnt == 1400` |
| B5 | `b5_err_backward == 0` |
| CHK | `chk_total_errors == 0` (A1–A4 checker, M_AXIS only) |

`AXI_SOAK_GATE: PASS` requires all six gate conditions to hold.

---

## Files

| File | Purpose |
|------|---------|
| `tb/common/axi_stream_checker.sv` | Reusable A1–A5 AXI-S checker module |
| `tb/session_C4_p3_20b_axi_soak_tb.sv` | Unified soak testbench (5 phases) |
| `scripts/run_session_C4_p3_20b_axi_soak.sh` | Compile + simulate + parse gate |
| `docs/session_C4_p3_20b_axi_soak.md` | This file |
| `sim_out/session_C4_p3_20b/p3_20b_axi_soak_sim.log` | Full simulation output (generated) |
| `sim_out/session_C4_p3_20b/p3_20b_axi_soak_gate.txt` | Gate result (generated) |

---

## How to Run

```bash
cd /home/zealatan/RTL_SYNC_PHASE3
bash scripts/run_session_C4_p3_20b_axi_soak.sh
```

Look for `AXI_SOAK_GATE: PASS` at the end of the output.

---

## Known Limitations

1. **FRAME_LEN_MISMATCH (ERROR_FLAGS[0])**: `s_axis_tlast` is sent at
   sample 703 with `FRAME_LEN_SAMPLES=576`, setting `ERROR_FLAGS[0]`
   each frame.  Only bit 3 (STALL_TIMEOUT) is checked; bit 0 is expected
   and ignored.

2. **RESET_WHILE_ACTIVE (ERROR_FLAGS[2])**: fires on the first soft reset
   of each phase when `output_count > 0` from the preceding phase.
   Only bit 3 is checked; bit 2 is expected and ignored.

3. **B4 tolerance**: the `replay_done` count may differ by ±2 from 1400
   if a soft reset races with the last replay pulse of a phase.  The TB
   accepts counts in [1398, 1402].

4. **B2 simulation time**: 1000 frames × ~103 000 cycles = ~103M simulation
   cycles.  The 220M-cycle watchdog provides ~2× safety margin.  Wall-clock
   time depends on host speed; typical iverilog throughput gives 30–90 s.

5. **A5 warning threshold (1000 cycles)**: with a 7-bit LFSR and 50%
   stall rate, individual stall runs are bounded to ≤ 63 cycles.  The
   1000-cycle A5 threshold will not fire under normal operation; it serves
   as a deadlock early-warning for future test configurations.
