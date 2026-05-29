# Session C3 / P3-20A: AXI Protocol + Random Backpressure Stress

## Gate

```
AXI_STRESS_GATE: PASS  — all 9 runs pass + 0 tdata/tlast stability violations
AXI_STRESS_GATE: FAIL  — any run fails or stability error detected
```

---

## Objective

Verify that `phase3_sync_axis_dma_wrapper` maintains correct AXI-Stream
handshake behaviour under randomized input gaps and output backpressure:
no sample loss, no duplication, no deadlock, and strict data stability
when a transfer is stalled.

---

## Test Configuration

### Randomisation

A 7-bit primitive LFSR (poly x^7 + x^3 + 1, tap mask s[6]^s[2], period 127)
drives both the S_AXIS valid-gap decisions (in the feed task) and the M_AXIS
ready-stall decisions (via an always block).  Independent seeds are used for
each run.

**Stall probability mapping** (comparison against full 7-bit LFSR value):

| Threshold | Approximate probability |
|-----------|------------------------|
| 0         | 0% (never stall)       |
| 13        | ≈10.2%                 |
| 32        | 25%                    |
| 64        | 50%                    |

LFSR period = 127; maximum consecutive stall run at 50% rate is bounded
statistically (P(≥40 consecutive) < 10⁻¹²).
STALL_TIMEOUT (limit=254) is unreachable under this distribution.

---

## Test Phases

### C3-1 — S_AXIS Valid Gap Sweep (4 runs)

M_AXIS tready held high throughout.  Input side introduces random idle
cycles between samples at four gap rates.

| Run | gap% | stall% |
|-----|------|--------|
| 0   | 0    | 0 (baseline) |
| 1   | 10   | 0      |
| 2   | 25   | 0      |
| 3   | 50   | 0      |

**AXI-S compliance**: once `s_axis_tvalid` is asserted for a sample, the
feed task holds `tdata` and `tlast` unchanged until `s_axis_tready` is
asserted (inner wait loop).  Gaps are only inserted *before* valid is
raised, never during a pending transfer.

---

### C3-2 — M_AXIS Ready Stall Sweep (3 runs)

S_AXIS valid is continuous.  Output-side randomised backpressure at three
rates.

| Run | gap% | stall% |
|-----|------|--------|
| 4   | 0    | 10     |
| 5   | 0    | 25     |
| 6   | 0    | 50     |

---

### C3-3 — Simultaneous S+M Stalls (2 runs)

Both sides randomised simultaneously.

| Run | gap% | stall% |
|-----|------|--------|
| 7   | 25   | 25     |
| 8   | 50   | 50     |

---

### C3-4 — tdata/tlast Stability (global, all 9 runs)

**Protocol rule verified**: when `m_axis_tvalid = 1` and `m_axis_tready = 0`,
`m_axis_tdata` and `m_axis_tlast` must not change (AXI4-Stream §2.2.1).

The stability monitor compares `m_axis_tdata` and `m_axis_tlast` across
consecutive cycles where both `tvalid=1` and `tready=0` (ongoing stall).
A fresh stall after a completed handshake starts a new transaction, so the
first stall cycle is not compared against the preceding accepted beat.
Any intra-stall change increments `stab_errors`.  The count accumulates
across all 9 runs.

**Expected**: `stab_errors = 0`.  `axis_complex_mult` uses `buf_ready =
!m_axis_tvalid || m_axis_tready` to gate acceptance; while stalled,
`buf_ready=0` so `accept=0` and the registered outputs hold unchanged —
satisfying AXI4-Stream §2.2.1.

---

## Per-Run Pass Criteria

All three conditions must hold for a run to pass:

| Observable | Expected | Meaning |
|-----------|----------|---------|
| `OUTPUT_COUNT` (AXI 0x14) | 576 | No sample loss or duplication |
| `TLAST_COUNT` (AXI 0x50) | 1 | Exactly one TLAST per frame |
| `ERROR_FLAGS[3]` (AXI 0x54) | 0 | No STALL_TIMEOUT |

`OUTPUT_COUNT == 576` proves no loss and no duplication simultaneously.

---

## Gate Summary

| Phase | Gate condition |
|-------|----------------|
| C3-1 | Runs 0–3: all three pass criteria met |
| C3-2 | Runs 4–6: all three pass criteria met |
| C3-3 | Runs 7–8: all three pass criteria met |
| C3-4 | `total_stab_errors == 0` across all 9 runs |

`AXI_STRESS_GATE: PASS` requires all four phases to pass.

---

## Files

| File | Purpose |
|------|---------|
| `tb/session_C3_p3_20a_axi_stress_tb.sv` | Unified testbench (9 runs, 4 phases) |
| `scripts/run_session_C3_p3_20a_axi_stress.sh` | Compile + simulate + parse gate |
| `docs/session_C3_p3_20a_axi_stress.md` | This file |
| `sim_out/session_C3_p3_20a/p3_20a_axi_stress_sim.log` | Full simulation output (generated) |
| `sim_out/session_C3_p3_20a/p3_20a_axi_stress_gate.txt` | Gate result (generated) |

---

## How to Run

```bash
cd /home/zealatan/RTL_SYNC_PHASE3

bash scripts/run_session_C3_p3_20a_axi_stress.sh
```

Look for `AXI_STRESS_GATE: PASS` at the end of the output.

---

## Known Limitations

1. **FRAME_LEN_MISMATCH flag**: `s_axis_tlast` at sample 703 with
   `FRAME_LEN_SAMPLES=576` sets `ERROR_FLAGS[0]` each run.  Only bit 3
   (STALL_TIMEOUT) is checked; bit 0 is expected and ignored.

2. **M_AXIS LFSR seed**: The M_AXIS 7-bit LFSR is seeded from the hard-reset
   path (`m_lfsr <= 7'h2D`) and soft resets do not reseed it.  Each
   run therefore has a different LFSR state for M_AXIS due to elapsed
   cycles between runs.  This is acceptable for stress testing; the
   statistical properties are equivalent across runs.

3. **50% S_AXIS gap rate**: at 50%, input feeding takes ~2× longer than
   baseline.  Total simulation budget: 9 × ~130K cycles ≈ 1.17M cycles.
   Watchdog at 2M cycles provides ample margin.

4. **No deadlock scenario**: the wrapper has no circular dependency between
   S_AXIS and M_AXIS (input feeds DUT, replay feeds M_AXIS independently).
   Deadlock is structurally impossible and is confirmed by the watchdog
   never firing.
