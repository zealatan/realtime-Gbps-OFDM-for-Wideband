# Session I / P3-20A — AXI Backpressure Stress Result

**Date:** 2026-05-28  
**Gate:** `SANITY_AXI_GATE: PASS (iverilog)` — 37/37 checks pass, 0 AXI violations  
**Official xsim gate:** pending xsim availability

---

## Quick Summary

`phase3_sync_axis_dma_wrapper` correctly handles all tested AXI4-Stream backpressure
scenarios. No sample loss, no deadlock, no protocol violations across S_AXIS input
stalls (up to 1/2), M_AXIS output stalls (up to 1/2), and M_AXIS burst stalls (up to
32 cycles at replay start).

---

## Test Matrix

### I1: S_AXIS Input Backpressure (M_AXIS tready=1)

| TC | Pattern | C1 (count=576) | C2 (TLAST@575) | C3 (INT_CFO=1) |
|----|---------|----------------|----------------|----------------|
| TC1 | Baseline (no stall) | PASS | PASS | PASS |
| TC2 | 1/10 (every 10th) | PASS | PASS | PASS |
| TC3 | 1/4 (every 4th) | PASS | PASS | PASS |
| TC4 | 1/2 (every 2nd) | PASS | PASS | PASS |

### I2: M_AXIS Output Backpressure (S_AXIS tvalid steady)

| TC | Pattern | C1 (count=576) | C2 (TLAST@575) | C3 (INT_CFO=1) |
|----|---------|----------------|----------------|----------------|
| TC5 | 1/10 (every 10th) | PASS | PASS | PASS |
| TC6 | 1/4 (every 4th) | PASS | PASS | PASS |
| TC7 | 1/2 (every 2nd) | PASS | PASS | PASS |

### I3: M_AXIS Burst Stall at Replay Start

| TC | Burst length | C1 (count=576) | C2 (TLAST@575) | C3 (INT_CFO=1) |
|----|--------------|----------------|----------------|----------------|
| TC8 | 1 cycle | PASS | PASS | PASS |
| TC9 | 4 cycles | PASS | PASS | PASS |
| TC10 | 8 cycles | PASS | PASS | PASS |
| TC11 | 16 cycles | PASS | PASS | PASS |
| TC12 | 32 cycles | PASS | PASS | PASS |

### I4: AXI4-Stream Protocol Assertions

| Assertion | Violations |
|-----------|-----------|
| I4a: tdata stable while stalled | 0 |
| I4b: tlast stable while stalled | 0 |
| I4c: tvalid not deasserted while tready=0 | 0 |

---

## Gate Result

```
SANITY_AXI_GATE: PASS (iverilog)
```

- Simulator: iverilog (official xsim gate pending)
- 37/37 checks PASS
- 0 AXI protocol violations
- 0 watchdog hits (no deadlock)

---

## TB Design Notes

### Deterministic stall patterns

S_AXIS stalls: `if (s_stall > 0 && lc_i > 0 && (lc_i % s_stall) == 0)` — inserts one idle
cycle every `s_stall`-th sample. M_AXIS stalls: `bp_m_cycle_cnt % bp_m_stall_prob == 0` —
deasserts tready every `bp_m_stall_prob`-th clock cycle. Seed-independent and reproducible.

### NBA for backpressure driver

`m_axis_tready` updated via non-blocking assignments in the BP always block. This ensures
all always blocks at posedge T see the stable T-1 value from BP's NBA, consistent with
how the DUT sees tready. Using blocking assignments caused the DUT (source files compiled
before the TB) to see the "wrong" tready at stall cycles, producing phantom handshakes
(576 actual + 288 phantom = 864 counted for 1/4 stall) and deadlocks (1/2 stall).

### Negedge I4 monitor

`always @(negedge aclk)` samples all posedge NBA outputs after they settle, eliminating
race conditions from non-deterministic ordering of concurrent always blocks at posedge.

### Count snapshot at while exit

`lc_tc_m_count` captured immediately when the M_AXIS while-loop exits, before the 20-cycle
pipeline drain and AXI reads. Prevents post-frame pipeline drain beats from inflating the
reported count.

---

## Framework Files

| File | Purpose |
|------|---------|
| `tb/session_I_p3_20a_axi_backpressure_stress_tb.sv` | 530-line AXI BP stress TB |
| `scripts/run_session_I_p3_20a_axi_backpressure_stress.sh` | Session runner |
| `sim_out/session_I_p3_20a/session_I_p3_20a_sim.log` | Simulation log |
| `reports/session_I_p3_20a/axi_backpressure_stress_result.txt` | Gate report |
| `docs/session_I_p3_20a_axi_backpressure_stress.md` | This file |
| `md_files/session_I_p3_20a_axi_backpressure_stress_prompt.md` | Session prompt archive |
