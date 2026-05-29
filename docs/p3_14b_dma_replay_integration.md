# P3-14B: DMA Replay + Integer CFO Correction Integration

## Overview

P3-14B connects `iq_replay_buffer_576`, a second NCO+rotator stage, and the
`M_AXIS` output of `phase3_sync_axis_dma_wrapper` so the wrapper exports a
fully-corrected IQ stream (fractional CFO + integer CFO) after each frame.

---

## Pipeline Diagram

```
S_AXIS (raw IQ from DMA)
    │
    ▼   [phase3_sync_axis_dma_wrapper / phase3_sync_top]
    ├──► frac_cfo_frame_corrector_top  ─── frame detect + frac CFO correction
    │         │ frac-corrected IQ (FRAME_LEN=576 beats)
    │         ├──────────────────────────────────────────────► iq_replay_buffer_576
    │         │  (side-channel capture: wr_valid = frac_hs)       [S_CAPTURING]
    │         ▼
    │    pss_sss_symbol_extractor      ─── extract PSS + SSS windows
    │         │
    │         ▼
    │    meyr_integer_cfo_fft_frontend_top ─── Meyr FFT + correlation
    │         │  int_cfo_valid  (one-cycle pulse)
    │         │  int_cfo_word   (32-bit NCO step)
    │
    │    [On int_cfo_valid:]
    │    replay_start ──────────────────────────────────────► iq_replay_buffer_576
    │                                                             [S_REPLAYING]
    │    load_step + phase_reset ───────────────────────────► u_int_nco (nco_phase_gen)
    │
    │    [Replay phase:]
    ├◄── iq_replay_buffer_576.rd ──► complex_rotator (u_int_rot) ──► M_AXIS
    │         (576 frac-corrected                      (integer NCO
    │          samples replayed)                        rotates each sample)
    │
    ▼
M_AXIS (integer+frac corrected IQ → DMA)
```

---

## Latency Analysis

| Stage | Latency (cycles) |
|---|---|
| Frame detection | ~1000–50000 (data-dependent) |
| Frac CFO correction (buffer fill + output) | ~NSC+CP_LEN + FRAME_LEN = ~864 cycles |
| PSS/SSS extraction + Meyr FFT | ~NSC×2 + correlation = ~600+ cycles |
| Integer NCO pipeline warmup | CORDIC_LATENCY = 15 cycles |
| Replay + rotator output (at max throughput) | FRAME_LEN×2 = ~1152 cycles (BRAM 1-cycle/2-cycle read) |

Total time from `start` pulse to last M_AXIS beat: several thousand cycles.
The replay buffer throughput is limited to **1 sample per 2 cycles** (BRAM read pipeline).
The integer rotator adds 1 cycle of multiplier latency per sample (propagated through `axis_complex_mult`).

---

## AXIS Timing

### M_AXIS Output (non-bypass mode)

- `m_axis_tvalid`: asserted from the integer rotator output (`int_corr_m_tvalid`)
- `m_axis_tready`: driven by DMA; backpressure propagates back through rotator → replay buffer
- `m_axis_tlast`: counter-based; fires every `FRAME_LEN_SAMPLES` accepted beats (default 576)
- Output begins after `CORDIC_LATENCY=15` cycles from `replay_start`
- First output beat is delayed by ~2 cycles (BRAM read latency) + 15 cycles (NCO warmup)

### NCO Enable Logic

```
int_nco_enable = !int_nco_sincos_valid | (replay_rd_valid & replay_rd_ready)
```

- During warmup (first 15 cycles after `int_cfo_valid`): `sincos_valid=0` → enable=1 (free-run)
- After warmup: enable only when a replay sample is accepted → NCO phase stays aligned

---

## Replay Timing

```
Cycle 0:  int_cfo_valid fires in phase3_sync_top (meyr_done)
          → replay_start_w = 1 (direct wire)
          → load_step = 1, phase_reset = 1 to u_int_nco
          → replay buffer enters S_REPLAYING

Cycles 1–15: NCO free-runs (warmup); replay buffer backpressured
             (complex_rotator stalls A-side: sincos_valid=0 → B-side not valid)

Cycle 16+: int_nco_sincos_valid = 1; samples flow through rotator to M_AXIS
           at 1 sample per 2 cycles (BRAM throughput limited)

Cycle ~(16 + 576×2): replay_done fires
          → replay_buf_clear fires next cycle (buffer → S_CAPTURING)
          → start_armed_r set → next DUT run can begin
```

---

## Register Updates (P3-14B)

| Register | Address | P3-14A state | P3-14B state |
|---|---|---|---|
| `INT_CFO_INDEX` | `0x40` | Always 0 | Latched Meyr peak index (on `int_cfo_valid`) |
| `INT_CFO_APPLIED` | `0x44` | Always 0 | Set when `replay_busy` asserts; sticky until reset |
| `OUTPUT_COUNT` | `0x14` | Already wired | Unchanged |
| `TLAST_COUNT` | `0x50` | Already wired | Unchanged |

`INT_CFO_APPLIED` is sticky within a reset domain: it stays set from the first
replay until `dut_aresetn` goes low (soft_reset or hard reset).

---

## Bypass Mode

In bypass mode (`bypass_enable=1`):
- `S_AXIS → M_AXIS` directly (no DUT, no replay buffer, no NCO)
- Replay buffer does not capture (no `frac_hs` events since DUT is bypassed)
- `INT_CFO_APPLIED` stays 0
- Useful for DMA path isolation testing

---

## Start / Re-arm Protocol (P3-14B change)

In P3-14A, the start FSM re-armed on `dut_done && !dut_error`.
In P3-14B, re-arm is deferred to `replay_done` to prevent a new frame run from
starting while the replay buffer is still in `S_REPLAYING`. If a new `start`
fired during replay, the frac corrector would begin outputting new samples while
`wr_ready=0` (buffer not in `S_CAPTURING`), causing missed capture on the next
frame.

Timeline guarantee:
```
dut_done (end of Meyr)  → immediately after int_cfo_valid fires (1 cycle)
replay_start fires      → same cycle as int_cfo_valid
replay_done fires       → ~FRAME_LEN×2 + 16 cycles after int_cfo_valid
start re-armed          → on replay_done
replay_buf_clear        → on replay_done (buffer → S_CAPTURING)
next start fires        → on the cycle after replay_done
```

---

## File Changes Summary

| File | Change |
|---|---|
| `rtl/phase3_sync_top.v` | Added `dbg_frac_m_tdata/valid/ready/tlast` output ports; wired `dbg_meyr_peak_index` from `u_meyr_fft.peak_index` |
| `rtl/phase3_axi_lite_regs.v` | Added `int_cfo_applied_i` and `int_cfo_index_i` input ports; `int_cfo_index_r` latch; updated `ADDR_INT_CFO_I` and `ADDR_INT_CFO_A` read responses |
| `rtl/phase3_sync_axis_dma_wrapper.v` | Full P3-14B: added replay buffer, integer NCO, rotator instances; replaced `core_m_valid=0` stub; modified start re-arm to `replay_done`; added `int_cfo_applied_r`; added `replay_buf_clear` FSM |
| `tb/p3_14b_dma_replay_tb.sv` | New: 14 interface-level checks (C1–C14), SANITY_GATE |
| `scripts/run_p3_14b_dma_replay.sh` | New: compile + simulate runner, SANITY_GATE / OFFICIAL_GATE |
| `docs/p3_14b_dma_replay_integration.md` | This document |

---

## Remaining Limitations / Risks

1. **BRAM throughput**: `iq_replay_buffer_576` reads 1 sample per 2 cycles.
   For a 576-sample replay, M_AXIS output takes ~1152 cycles minimum.
   If backpressure from DMA causes stalls, replay takes longer.

2. **Single replay per frame**: The current design does one replay per frame.
   There is no mechanism to re-replay if downstream drops samples.

3. **Phase offset at replay start**: The integer NCO free-runs for 15 cycles
   during pipeline warmup, introducing a fixed phase offset at replay start.
   This is acceptable for integer CFO correction (frequency error dominates;
   initial phase is irrelevant for symbol demodulation).

4. **INT_CFO_APPLIED is sticky**: It does not reset between frames within a
   reset domain. This is intentional — it indicates the correction is ever-applied.
   Add per-frame sticky logic if needed.

5. **FRAME_LEN mismatch**: If `FRAME_LEN_SAMPLES` register is changed from
   576, the TLAST counter period changes but the replay buffer still outputs
   exactly `FRAME_LEN_LP = 2*(NSC+CP_LEN)` beats. Ensure register matches
   parameter.

6. **OFFICIAL_GATE not automated**: Full verification (correct integer CFO
   removal, output IQ quality) requires xsim with real IQ stimulus from
   `golden/phase3_iq_stimulus.mem` and comparison to golden reference.

---

## Recommended Next Step

**P3-14C**: Add a Python or C golden-compare script that:
1. Runs the full pipeline under iverilog with `golden/phase3_iq_stimulus.mem`
2. Captures M_AXIS output to a `.hex` file
3. Compares against a reference-corrected IQ file (generated by `ref/receiver.c`)
4. Declares `OFFICIAL_GATE: PASS` when SNR improvement from integer correction
   matches expectation (e.g., ≥ 10 dB improvement on test vector with known offset)
