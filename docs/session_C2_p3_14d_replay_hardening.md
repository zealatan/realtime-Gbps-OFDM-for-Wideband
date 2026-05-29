# Session C2 / P3-14D: Replay Correction Hardening

## Gate

```
REPLAY_HARDENING_GATE: PASS  — all four phases pass
REPLAY_HARDENING_GATE: FAIL  — any phase fails
```

---

## Objective

Stress-test the `phase3_sync_axis_dma_wrapper` replay path under four
orthogonal conditions: M_AXIS backpressure, integer CFO variety, multi-frame
consecutive operation, and NCO phase arithmetic correctness.

---

## Test Phases

### C2-1 — Replay Backpressure

**Stimulus**: `golden/phase3_iq_stimulus.mem` (704 samples, k_int=+1 natural).

**Backpressure pattern**: deterministic 5-ready / 3-not-ready cycle on
`m_axis_tready`.  Maximum stall burst = 3 cycles, well below
`STALL_TIMEOUT = 254` consecutive stall cycles.

**Checks**:

| Observable | Expected | Meaning |
|-----------|----------|---------|
| `OUTPUT_COUNT` (AXI 0x14) | 576 | No sample loss, no duplication |
| `TLAST_COUNT` (AXI 0x50) | 1 | Exactly one TLAST per replay |
| `ERROR_FLAGS[3]` (AXI 0x54) | 0 | No STALL_TIMEOUT |

`OUTPUT_COUNT == 576` simultaneously proves no loss and no duplication:
the replay buffer is a fixed-depth FIFO, so 576 accepted outputs means
every captured sample was replayed exactly once.

---

### C2-2 — Integer CFO Sweep Replay

**13 step_word cases**:

| k_int | step_word (32-bit NCO step) | Formula |
|-------|----------------------------|---------|
| 0     | `0x00000000` | `-0 × 2^24` |
| +1    | `0xFF000000` | `-1 × 2^24` |
| −1    | `0x01000000` | `+1 × 2^24` |
| +2    | `0xFE000000` | `-2 × 2^24` |
| −2    | `0x02000000` | `+2 × 2^24` |
| +4    | `0xFC000000` | `-4 × 2^24` |
| −4    | `0x04000000` | `+4 × 2^24` |
| +8    | `0xF8000000` | `-8 × 2^24` |
| −8    | `0x08000000` | `+8 × 2^24` |
| +12   | `0xF4000000` | `-12 × 2^24` |
| −12   | `0x0C000000` | `+12 × 2^24` |
| +16   | `0xF0000000` | `-16 × 2^24` |
| −16   | `0x10000000` | `+16 × 2^24` |

Step-word formula: `step = (-k_int × 2^24) & 0xFFFFFFFF`  
This is consistent with `N_FFT = NSC = 256 = 2^32 / 2^24`.

**Mechanism**: for each case, the TB uses `force u_dut.dut_int_cfo_word`
to override the Meyr estimator output before the NCO latches it on
`dut_int_cfo_valid`. The force is released after replay completes.

**Per-case checks** (all three must pass):

| Observable | Expected |
|-----------|----------|
| `OUTPUT_COUNT` | 576 |
| `INT_CFO_APPLIED` (AXI 0x44) | 1 |
| `TLAST_COUNT` (AXI 0x50) | 1 |

**Gate**: all 13 cases must pass.

---

### C2-3 — Replay Restart (4 Consecutive Frames)

**Protocol**: single soft reset at start, then 4 back-to-back frames with
no additional reset between them.  After each frame's replay completes,
`replay_done` pulses, `start_armed_r` is set, and `start_r` fires on the
next cycle.  The DUT re-arms and is ready for the next frame's input.

**output_count accumulation**: the wrapper accumulates `output_count` without
per-frame reset (cleared only by `dut_aresetn`).  Expected absolute values:

| Frame | Expected `OUTPUT_COUNT` |
|-------|------------------------|
| 0     | 576                    |
| 1     | 1152                   |
| 2     | 1728                   |
| 3     | 2304                   |

**Check**: all four absolute counts must match exactly.

---

### C2-4 — Rotator Stability

Two sub-checks:

**Phase continuity** — On every `replay_rd_valid & replay_rd_ready`
handshake (replay buffer output), the NCO phase accumulator
`int_nco_phase_acc` must advance by exactly the natural step_word computed
by Meyr for the golden stimulus.

After NCO warmup (CORDIC_LATENCY + 1 = 16 cycles), `int_nco_enable` fires
only on replay handshakes, so consecutive `phase_acc` readings differ by
exactly `step_word`.  The monitor checks this for all ≥ 576 replay beats
and reports any deviations as errors.

Two-pass approach to determine the expected step_word:
1. Run one frame to learn the natural Meyr step_word (read AXI INT_CFO_EST).
2. Soft reset, run a second frame with the monitor active.

**Phase reset** — After a soft reset, `dut_aresetn` goes low for 1 cycle,
resetting `int_nco_phase_acc` to 0 inside `nco_phase_gen`.  The TB reads
`int_nco_phase_acc` 5 cycles after the soft reset completes (before any
new `dut_int_cfo_valid` fires) and verifies it is `32'h00000000`.

---

## Gate Summary

| Phase | Gate condition |
|-------|----------------|
| C2-1  | `output_count=576` AND `tlast_count=1` AND `STALL_TIMEOUT=0` |
| C2-2  | All 13 k_int cases: `output_count=576` AND `INT_CFO_APPLIED=1` AND `tlast_count=1` |
| C2-3  | Absolute output counts: 576, 1152, 1728, 2304 |
| C2-4  | Phase continuity errors = 0 (≥576 samples) AND phase_reset = 0 |

`REPLAY_HARDENING_GATE: PASS` requires all four phases to pass.

---

## Files

| File | Purpose |
|------|---------|
| `tb/session_C2_p3_14d_replay_hardening_tb.sv` | Unified testbench (all 4 phases) |
| `scripts/run_session_C2_p3_14d_replay_hardening.sh` | Compile + simulate + parse gate |
| `docs/session_C2_p3_14d_replay_hardening.md` | This file |
| `golden/phase3_iq_stimulus.mem` | Input stimulus (704 samples) |
| `sim_out/session_C2_p3_14d/p3_14d_replay_sim.log` | Full simulation output (generated) |
| `sim_out/session_C2_p3_14d/p3_14d_replay_gate.txt` | Gate result (generated) |

---

## How to Run

```bash
cd /home/zealatan/RTL_SYNC_PHASE3

# Full run:
bash scripts/run_session_C2_p3_14d_replay_hardening.sh

# Alternate simulator:
bash scripts/run_session_C2_p3_14d_replay_hardening.sh --sim xsim
```

Look for `REPLAY_HARDENING_GATE: PASS` at the end of the output and in
`sim_out/session_C2_p3_14d/p3_14d_replay_gate.txt`.

---

## Simulation Baseline (clean single-frame, Session E)

| Observable | Value |
|-----------|-------|
| frame_index | 41 |
| output_count (per frame) | 576 |
| int_cfo_applied | 1 |
| tlast_count (per frame) | 1 |
| total_cycles (single frame) | ~103168 |

Expected total cycles for this session: ~1.5M cycles (4 C2-2 frame setup
cycles + 4 C2-3 frames + 2 C2-4 passes + overhead).  Watchdog at 3M cycles.

---

## Known Limitations

1. **FRAME_LEN_MISMATCH**: `s_axis_tlast` is sent at sample 703 (last of 704).
   With `FRAME_LEN_SAMPLES = 576` (default), `in_frame_cnt = 127` when TLAST
   arrives, not 575.  `ERROR_FLAGS[0]` is set each frame.  This is expected;
   the flag is not checked in C2 and does not affect pipeline operation.

2. **Single-cycle soft reset**: the soft reset via AXI CONTROL bit 1 asserts
   `dut_aresetn = 0` for exactly one clock cycle.  Deep CORDIC pipeline stages
   may retain stale values, but all state machines and counters reset
   correctly on the first active-low edge.

3. **force semantics**: `force u_dut.dut_int_cfo_word = value` is evaluated
   once (not continuously) in iverilog.  The forced value persists until
   `release` is issued.  The NCO latches the step_word on `dut_int_cfo_valid`,
   which fires at the natural Meyr-completion time regardless of the force.

4. **C2-4 two-pass**: the expected step_word is read from INT_CFO_EST after
   pass 1.  If Meyr produces a different result than k_int=+1 (e.g., due to
   pipeline state) the phase check in pass 2 will still use the actual
   step_word, making it self-consistent.

5. **FFT bypass stub**: `fft256_dual_symbol_frontend` passes time-domain
   samples unchanged.  Integer CFO accuracy for sweep cases is therefore
   irrelevant — the test only checks replay pipeline behavior (count, TLAST,
   INT_CFO_APPLIED), not CFO correction quality.
