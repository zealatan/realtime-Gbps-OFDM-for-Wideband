# Session L / P3-23A — Multi-Frame and Reset Stress

**Date:** 2026-05-29  
**Gate:** `SANITY_STRESS_GATE: PASS` (iverilog)  
**Checks:** 23/23 PASS  
**Simulator:** iverilog  
**Simulation cycles:** ~1.24M total (L1 ~1.03M, L2 ~105K, L3 ~105K, L4 ~105K)

---

## Summary

All four stress scenarios passed on first run. The DUT (`phase3_sync_axis_dma_wrapper`)
demonstrates no deadlock across 10 consecutive frames, correct recovery from soft reset
at two different pipeline stages, and clean behaviour under mid-stimulus enable toggling.

---

## Test Results

### L1 — Multi-Frame Back-to-Back (10 frames)

| Check | Expected | Got | Result |
|-------|----------|-----|--------|
| L1_beat_count | 5760 | 5760 | PASS |
| L1_tlast_count | 10 | 10 | PASS |
| L1_last_tlast_position | beat 5759 | beat 5759 | PASS |
| L1_reg_out_count | 0x00001680 | 0x00001680 | PASS |
| L1_reg_tlast_count | 0x0000000a | 0x0000000a | PASS |
| L1_no_error | 0 | 0 | PASS |

**Key observation:** TLAST fires at beat 575, 1151, 1727, … 5759 — exactly frame_len−1
within every frame. The wrapper's auto-rearm fires within 3 cycles of each `replay_done`,
producing zero deadlock cycles between frames.

### L2 — Soft Reset During Frame Acquisition (after 300 of 704 samples)

Soft reset issued at cycle 1,031,378. DUT re-armed by cycle 1,031,395 (17 cycles).

| Check | Expected | Got | Result |
|-------|----------|-----|--------|
| L2_recovery_beat_count | 576 | 576 | PASS |
| L2_recovery_tlast_count | 1 | 1 | PASS |
| L2_recovery_tlast_position | beat +575 | beat +575 | PASS |
| L2_reg_out_count_post_reset | 576 (0x240) | 576 | PASS |
| L2_int_cfo_applied | 1 | 1 | PASS |
| L2_no_error | 0 | 0 | PASS |

**Key observation:** After soft reset, `output_count` in the DUT was cleared to 0 (confirms
`dut_aresetn` pulsed low). The full recovery frame completed with `int_cfo_applied=1`,
demonstrating that the frame detector, Meyr estimator, replay buffer, and NCO all
re-initialised cleanly.

### L3 — Soft Reset During Replay Correction (after 50 M_AXIS beats)

Soft reset issued at cycle 1,135,246 (50 beats into replay). Beat baseline re-established
at m_total_beats=6336 after reset settled.

| Check | Expected | Got | Result |
|-------|----------|-----|--------|
| L3_recovery_beat_count | 576 | 576 | PASS |
| L3_recovery_tlast_count | 1 | 1 | PASS |
| L3_recovery_tlast_position | beat +575 | beat +575 | PASS |
| L3_reg_out_count_post_reset | 576 (0x240) | 576 | PASS |
| L3_int_cfo_applied | 1 | 1 | PASS |
| L3_no_error | 0 | 0 | PASS |

**Key observation:** Soft reset during replay cleanly terminates the in-flight replay.
The replay buffer (driven by `dut_aresetn`) stops output, the NCO warmup counter resets,
and the next full frame processes without any stale replay data.

### L4 — Enable Toggle During Stimulus (samples 100 and 350, 20-cycle pause each)

Enable toggled off at cycles 1,238,539 and 1,238,820 (20-cycle pause each).

| Check | Expected | Got | Result |
|-------|----------|-----|--------|
| L4_beat_count | 576 | 576 | PASS |
| L4_tlast_count | 1 | 1 | PASS |
| L4_tlast_position | beat +575 | beat +575 | PASS |
| L4_int_cfo_applied | 1 | 1 | PASS |
| L4_no_error | 0 | 0 | PASS |

**Key observation:** Two 20-cycle pauses with `enable=0` mid-stimulus neither corrupt the
frame detector's sliding window state nor lose samples (the TB's `while (!s_axis_tready)`
stalls until `s_axis_tready` reasserts after re-enable). The complete 704-sample frame was
reconstructed and processed correctly.

---

## Timing Summary

| Test | Cycles used | Completion cycle |
|------|-------------|-----------------|
| L1 (10 frames) | ~1,031,000 | ~1,031,000 |
| L2 (reset at acqn) | ~105,000 | ~1,136,000 |
| L3 (reset at replay) | ~105,000 | ~1,241,000 |
| L4 (enable toggle) | ~105,000 | ~1,346,000 |

Total simulation: ~1.35M cycles (well within 2.5M watchdog).

---

## Protocol Confirmed

The soft-reset sequence (write `ADDR_CONTROL[1]=1`) pulses `dut_aresetn` low for exactly
one clock cycle. After deassert:
1. `reset_done_w` fires (rising edge of `dut_aresetn`)
2. `start_armed_r` sets to 1 on the next posedge
3. `start_r` fires on the following posedge (when `enable=1 && !dut_busy`)
4. The DUT is ready to accept new samples within ~3 cycles of reset deassert

The AXI-Lite `enable` bit (CONTROL[0]) survives soft reset — the TB confirms that no
re-write of enable is needed after a soft reset for the DUT to restart automatically.

---

## Files

| File | Purpose |
|------|---------|
| `tb/session_L_p3_23a_stress_tb.sv` | Stress testbench (L1–L4) |
| `scripts/run_session_L_p3_23a_stress.sh` | Compile + simulate + gate runner |
| `sim_out/session_L_p3_23a/session_L_p3_23a.vvp` | Compiled simulation binary |
| `logs/session_L_p3_23a_sim.log` | Full simulation log |
| `reports/session_L_p3_23a/stress_gate.txt` | Gate result record |
| `docs/session_L_p3_23a_stress.md` | This document |

No RTL was modified.
