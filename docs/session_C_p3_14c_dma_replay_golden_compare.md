# Session C / P3-14C: Full DMA Replay Golden Compare

## Result

```
OFFICIAL_GATE: PASS
  0/576 IQ sample mismatches (tolerance ±1 LSB)
  Replay buffer + integer CFO correction numerically verified sample-by-sample.
```

---

## Pipeline Under Test

```
S_AXIS stimulus (704 samples)
  → frac_cfo_frame_corrector_top  (fractional CFO correction)
  → iq_replay_buffer_576          (capture 576 samples)
  → integer NCO (nco_phase_gen)   (generates cos/sin at step_word phase)
  → complex_rotator               (multiplies replay × exp(-j·n·ω₀))
  → M_AXIS output stream
```

The test proves the complete DMA replay + integer CFO correction path is
numerically correct from input IQ through fractional correction, replay
capture, NCO rotation, and final M_AXIS output.

---

## Files Generated

| File | Description |
|---|---|
| `tb/session_C_p3_14c_dma_replay_golden_tb.sv` | Full DMA replay TB: drives AXI-Lite + S_AXIS, captures M_AXIS output |
| `scripts/compare_session_C_p3_14c_dma_replay_golden.py` | Python 3-stage golden compare: structural, TLAST, IQ sample-by-sample |
| `scripts/run_session_C_p3_14c_dma_replay_golden_compare.sh` | Compile + simulate + compare runner, emits SANITY_GATE / OFFICIAL_GATE |
| `sim_out/session_C_p3_14c/rtl_m_axis_iq.txt` | 576-line decimal IQ capture from M_AXIS |
| `sim_out/session_C_p3_14c/rtl_frac_iq.txt` | 576-line decimal frac-corrected IQ (pre-NCO) |
| `sim_out/session_C_p3_14c/rtl_status.txt` | key=value status: INT_CFO_APPLIED, INT_CFO_STEP_WORD, counts |

---

## Reference Model Assumptions

### NCO Phase Formula

```
step_word = (-meyr_int_cfo) << 24    [from phase3_sync_top.v]
phase at sample n = n * step_word    [32-bit unsigned wrap]
ROM index = phase[31:24]             [upper 8 bits, 0–255]
```

### Rotator (complex_rotator.v, CONJ_B=1)

```
r_out = r_in * exp(-j·θ)
I_out = (I_in * cos + Q_in * sin) >> 15   (Python floor = Verilog [30:15])
Q_out = (Q_in * cos - I_in * sin) >> 15
```

### IQ Packing

```
tdata[15:0]  = I (in-phase)
tdata[31:16] = Q (quadrature)
```

---

## Fixed-Point Tolerance

| Condition | Tolerance |
|---|---|
| step_word = 0 (identity rotation) | 0 LSB (bit-exact) |
| step_word ≠ 0 | ±1 LSB per component |

The ±1 LSB tolerance covers floating-point rounding in the Python ROM model
vs the RTL's Q1.15 ROM lookup.

---

## Sign Convention (Verified)

- `int_cfo_index = 256` → Meyr peak at subcarrier +1 → `meyr_int_cfo = +1`
- `step_word = (-1) << 24 = 0xFF000000` (unsigned 32-bit)
- NCO rotates by `-1` subcarrier per sample = corrects +1 subcarrier offset
- Python model matches exactly at all 576 sample positions

---

## Bugs Found and Fixed

### Bug 1 — TB never sent TLAST

**Symptom:** `m_axis_out_count=0`, watchdog fires immediately.

**Root cause:** `s_axis_tlast` was hardcoded to 0 in the stimulus loop.
`iq_frame_buffer` terminates capture only on `tlast` or buffer full (4096 entries).
With 704 samples and no tlast, `capture_done` never fired, stalling the FSM in `S_FILL`.

**Fix:** `s_axis_tlast = (i == STIM_DEPTH - 1) ? 1'b1 : 1'b0`

### Bug 2 — Watchdog too short

**Symptom:** Simulation terminated before pipeline completed.

**Root cause:** `meyr_integer_cfo_core` performs 65,536 MACs; total pipeline
is ~110K cycles. Original watchdog was 100K.

**Fix:** Increased watchdog to 150K cycles.

### Bug 3 — Integer NCO stale pipeline (phase3_sync_axis_dma_wrapper.v)

**Symptom:** SANITY_GATE PASS but 573/576 IQ mismatches. RTL output for
sample `n` used the rotation intended for sample `n-1`.

**Root cause (two-part):**

1. The NCO ran with `step_word=0` for ~110K cycles before `dut_int_cfo_valid`
   fired, achieving `sincos_valid=1` early. The old enable logic
   `!sincos_valid | (replay_rd_valid & replay_rd_ready)` gave `enable=0`
   when the new step_word arrived, so the pipeline was not refreshed.

2. `nco_phase_gen` has an output register (`sin_out_r <= sin_pipe[LATENCY-1]`)
   that adds one extra cycle beyond the LATENCY-stage shift register.
   Effective total latency = `LATENCY + 1 = 16` cycles.

**Fix (rtl/phase3_sync_axis_dma_wrapper.v):**

Added a warmup counter `int_nco_wu_cnt` that forces `enable=1` for
`CORDIC_LATENCY + 1 = 16` cycles after `dut_int_cfo_valid`, flushing the
stale step_word=0 values and priming the pipeline with the correct phase
sequence. Replay starts when `wu_cnt==1` (the last warmup edge), so the
first sample handshake occurs exactly when `sin_out_r` holds the n=0
rotation (identity).

```verilog
reg [4:0] int_nco_wu_cnt;
always @(posedge aclk) begin
    if (!dut_aresetn)           int_nco_wu_cnt <= 5'd0;
    else if (dut_int_cfo_valid) int_nco_wu_cnt <= NCO_WU_CYCLES[4:0];  // 16
    else if (int_nco_wu_cnt > 5'd0)
                                int_nco_wu_cnt <= int_nco_wu_cnt - 5'd1;
end
wire int_nco_wu_active = (int_nco_wu_cnt > 5'd0);
wire replay_start_w    = (int_nco_wu_cnt == 5'd1);
wire int_nco_enable    = int_nco_wu_active | !int_nco_sincos_valid
                         | (replay_rd_valid & replay_rd_ready);
```

---

## Sample Compare Result

```
INT_CFO_STEP_WORD = 0xFF000000  (step = −1 subcarrier, corrects +1 CFO)
INT_CFO_INDEX     = 256
Tolerance:    1 LSB
Max I error:  0
Max Q error:  0
Mismatches:   0 / 576
```

First 4 samples (frac → ref → rtl):
```
n=0: frac=(     0,     0)  ref=(     0,     0)  rtl=(     0,     0)
n=1: frac=( -1422,   722)  ref=( -1440,   686)  rtl=( -1440,   686)
n=2: frac=( -1422,   722)  ref=( -1456,   651)  rtl=( -1456,   651)
n=3: frac=( -1485,   854)  ref=( -1544,   742)  rtl=( -1544,   742)
```

---

## Remaining Risks

| Risk | Notes |
|---|---|
| Single CFO offset tested (int_cfo=+1, step_word=0xFF000000) | Other offsets not swept in this session |
| frac_iq captured from a debug tap, not output of corrector | Verified structurally but sign assumption not independently confirmed |
| Stimulus uses fixed peak (TARGET_PEAK=3000) | Dynamic SNR range not tested |
| Meyr peak index 256 = one subcarrier offset only | ±12 subcarrier range not verified here |

---

## Gate Summary

| Gate | Result |
|---|---|
| SANITY_GATE | PASS (6/6 structural checks) |
| OFFICIAL_GATE | **PASS** (0/576 IQ mismatches, ±1 LSB tolerance) |
