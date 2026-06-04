# P3-24B CP Autocorr Difference Audit

**Session:** B / P3-24B  
**Date:** 2026-05-31  
**Status:** AUDIT COMPLETE — adapter/patch spec ready  
**Author:** Claude Code (claude-sonnet-4-6)

---

## 1. Old Path Summary

### 1.1 Module Hierarchy

```
timing_frac_cfo_top
├── timing_sync_top            (MISSING from DUT directory)
│   ├── cp_autocorr_core       (MISSING — was in rtl/unit_test/)
│   ├── timing_metric_core     (present: rtl/DUT/timing_metric_core.v)
│   └── peak_detector          (present: rtl/DUT/peak_detector.v)
└── frac_cfo_estimator         (present: rtl/DUT/frac_cfo_estimator.v)
```

> **Note:** `timing_sync_top.v` and `cp_autocorr_core.v` are **not present** in the
> current `rtl/DUT/` directory. They are referenced by `timing_frac_cfo_top.v:82` and
> documented in `docs/phase3_rtl_gap_analysis.md` and `docs/session_G_p3_18a_phase3_architecture.md`
> as having resided in `rtl/timing_sync_top.v` and `rtl/unit_test/cp_autocorr_core.v`.
> The current production compile is broken at `timing_sync_top` instantiation.

### 1.2 Interface (cp_autocorr_core / timing_sync_top)

**Control:**
| Signal | Direction | Width | Description |
|--------|-----------|-------|-------------|
| `start` | input | 1 | 1-cycle pulse; latched |
| `base_addr` | input | BUF_AW=12 | Frame start address in iq_frame_buffer |
| `done` | output | 1 | 1-cycle pulse on completion |
| `busy` | output | 1 | High while running |
| `num_lags` | input | 9 | Number of lags to search (default NSC=256) |

**Buffer read port (request → buffer → timing_sync_top):**
| Signal | Direction | Width | Description |
|--------|-----------|-------|-------------|
| `buf_rd_addr` | output | BUF_AW | Address driven to iq_frame_buffer |
| `buf_rd_en` | output | 1 | Read enable |
| `buf_rd_data_I` | input | 16 signed | I component from buffer |
| `buf_rd_data_Q` | input | 16 signed | Q component from buffer |

**Result read port (combinatorial, zero-latency RAM — used by timing_metric_core and frac_cfo_estimator):**
| Signal | Direction | Width | Description |
|--------|-----------|-------|-------------|
| `result_rd_addr` | input | 9 | Lag index driven by downstream |
| `result_autocorr_I` | output | 32 signed | P_I at requested lag |
| `result_autocorr_Q` | output | 32 signed | P_Q at requested lag |
| `result_norm_E` | output | 32 unsigned | Normalised energy at requested lag |

**Peak outputs (stable after done):**
| Signal | Width | Description |
|--------|-------|-------------|
| `peak_lag` | 9 | Argmax lag index, 0-based |
| `peak_metric` | 32 | Metric value at peak |
| `peak_corr_i/q` | 32 signed | P_I/P_Q at peak_lag |
| `peak_energy` | 32 | Energy at peak_lag |

### 1.3 Processing Algorithm

1. **Post-fill, offline execution**: triggered by `start` pulse from
   `frac_cfo_frame_corrector_top` after `iq_frame_buffer` is fully filled.
2. **Buffer replay**: cp_autocorr_core reads NSC+CP_LEN=288 samples from iq_frame_buffer
   starting at `base_addr` = `frame_index`.
3. **Per-lag accumulation**: For each lag m ∈ [0, NSC-1], accumulates
   `P[m] = Σ_{k=0}^{CP_LEN-1} conj(r[m+k]) × r[m+k+NSC]`
   with CP_LEN=32-sample sliding window. Stores P_I, P_Q, E in an
   **internal per-lag RAM** (32 bits per entry, NSC=256 entries deep).
4. **Output scaling**: P_I, P_Q, E stored as upper 32 bits of 40-bit
   accumulator (right-shifted by 8), so each entry represents `acc >> 8`.
5. **timing_metric_core** reads all NSC result entries sequentially via
   combinatorial result_rd_addr, computing the squared Cauchy-Schwarz metric:
   ```
   sq_neg[m] = E[m]² − 4×(P_I[m]² + P_Q[m]²)
   metric_out[m] = ~sq_neg[58:27]     // inverted for MAX peak detection
   ```
6. **peak_detector** finds argmax → `peak_lag`.
7. **frac_cfo_estimator** reads `result_autocorr_I/Q` at `peak_lag` →
   CORDIC atan2 → `frac_phase`.

### 1.4 Latency

| Phase | Cycles | Notes |
|-------|--------|-------|
| cp_autocorr_core | ~32,513 | Buffer read × NSC lags, sliding window (288 samples × NSC ÷ pipeline) |
| timing_metric_core | 256 | One cycle per lag, NSC=256 lags |
| peak_detector | 256 | Scans 256 metric values |
| frac_cfo_estimator | 17 | CORDIC latency L=15 + 2 state cycles |
| **Total (TIMING+FRAC_CFO)** | **~32,789** | Per `timing_frac_cfo_top.v:29` comment |

### 1.5 Output Correlation Scaling

- `result_autocorr_I/Q` [31:0]: `P_I[m] >> 8` (40-bit accumulator, upper 32 bits)
- `result_norm_E` [31:0]: `E[m] >> 8` (same convention)
- Maximum input per sample: 16-bit × 16-bit = 32-bit product
- CP_LEN=32 samples → max accumulator = 32 × 2^31 = 2^36, fits in 40 bits
- After >>8: max = 2^28, fits in 32 bits signed

### 1.6 peak_lag Semantics

- `peak_lag` ∈ [0, NSC-1] = [0, 255], 9-bit
- Represents the lag (in samples from frame_index) where the CP correlation peaks
- `slot_start = frame_index + peak_lag` (computed in frac_cfo_frame_corrector_top:443)
- Argmax uses **strict >** (first occurrence wins ties)

### 1.7 frac_cfo Phase Convention

- `frac_phase = atan2(P_Q[peak_lag], P_I[peak_lag])` in Q1.15 encoding
- Range: `0x8000` = −π, `0x7FFF` = +π
- RTL convention: **positive** frac_phase for **positive** ε (forward product: conj(x[n-N]) × x[n])
- `step_word = +frac_phase × 256 = {{8{frac_phase[15]}}, frac_phase, 8'h00}`  
  (signed, 32-bit; drives NCO for fractional CFO removal)
- Expected: `frac_cfo_word = round(2 × ε × 32768)` per J2 test specification

---

## 2. streaming_cp_autocorr Summary

**File:** `rtl/DUT/streaming_cp_autocorr.v`

### 2.1 Interface

```verilog
module streaming_cp_autocorr #(
    parameter integer SAMPLE_W = 16,
    parameter integer NSC      = 256,
    parameter integer CP_LEN   = 32,
    parameter integer ACC_W    = 48
) (
    input  wire                    clk,
    input  wire                    aresetn,
    input  wire                    s_valid,
    input  wire [2*SAMPLE_W-1:0]   s_data,   // {Q[31:16], I[15:0]}
    output reg  signed [ACC_W-1:0] p_i,
    output reg  signed [ACC_W-1:0] p_q,
    output reg         [ACC_W-1:0] energy,
    output reg                     out_valid,
    output reg  [31:0]             sample_index
);
```

**Key differences from old interface:**
- **No start/done**: runs continuously from reset release
- **No buffer read port**: operates on live stream (`s_valid`/`s_data`)
- **No result RAM**: only the **current** sliding window is output — not per-lag storage
- **No peak outputs**: no `peak_lag`, no `peak_corr_i/q`
- **out_valid** is not a completion signal; it latches HIGH on the first strobe and stays HIGH

### 2.2 Processing Algorithm

```
Pipeline (P path):
  delay_sample (NSC=256 delay, 1-cycle latency)
  → registered current sample alignment (1cy)
  → complex_mult: conj(delayed) × current (3-cycle pipeline)
  → moving_avg_optimized × 2: CP_LEN=32-window sum (4cy)
  Total P latency: 8 cycles from first s_valid

Pipeline (E path):
  sample_power_sq: |I|²+|Q|² (2cy)
  → 2-cycle alignment delay registers
  → moving_avg_optimized: CP_LEN=32-window sum (4cy)
  Total E latency: 8 cycles (aligned with P path)
```

**Correlation formula** (mathematically identical to VanDeBeek):
```
P_I + jP_Q = Σ_{k=0}^{CP_LEN-1} conj(x[n-NSC+k]) × x[n+k]
           = Σ_{k=0}^{CP_LEN-1} conj(delayed[k]) × current[k]
```
where `n` is the current sample position and the sum slides one sample
per `s_valid` assertion.

**complex_to_mag** is instantiated for debug hierarchy preservation but
its output (`mag_out`, `mag_stb`) is **not connected to any output port**.

### 2.3 out_valid Semantics

```verilog
// out_valid: latch permanently on first strobe
if (avg_pi_stb)
    out_valid_latch <= 1'b1;
out_valid <= out_valid_latch;
```

- `out_valid` goes HIGH after the first 8-cycle pipeline drain and **never deasserts**
- This is a "data available" flag, **not** a "scan complete" flag
- `p_i/p_q/energy` update on every `avg_pi_stb` / `avg_e_stb` pulse (once per `s_valid`)

### 2.4 sample_index Counter

```verilog
if (s_valid)
    sample_index <= sample_index + 32'd1;
```

- Increments on every accepted input sample (no gating for downstream backpressure)
- Represents "how many samples have entered the module so far" — 0-based
- After reset: starts at 0; **first output valid** at `sample_index = NSC + CP_LEN + 8 - 1`
  (NSC=256 for delay fill + CP_LEN=32 for window fill + 8cy pipeline = sample 295 at first strobe)

### 2.5 Output Scaling

- `p_i`, `p_q`: **48-bit signed** — full sliding sum, no shift
  - Max value: CP_LEN × max_product = 32 × (2^15)^2 × 2 = 32 × 2^30 = 2^35 (signed)
  - Safe in 48 bits with ample headroom
- `energy`: **48-bit unsigned** — full sliding energy sum, no shift
  - Max: CP_LEN × max_power = 32 × (2^15)^2 × 2 = 32 × 2^30 = 2^35
  - Safe in 48 bits

---

## 3. Compatibility Issues

### CI-1 — Width Mismatch (BLOCKER)

| Item | Old | New | Impact |
|------|-----|-----|--------|
| P_I, P_Q | 32-bit signed | 48-bit signed | timing_metric_core `result_autocorr_I/Q` inputs are 32-bit |
| Energy | 32-bit unsigned | 48-bit unsigned | timing_metric_core `result_norm_E` input is 32-bit |
| Adapter needed | — | p_i[47:16] → 32-bit | >>16 truncation; ordering preserved; atan2 angle preserved |

The 16-bit shift preserves the relative ordering of all metric values since the same scaling is applied uniformly. The CORDIC atan2 in `frac_cfo_estimator` is scale-invariant (angle of complex number unchanged by scaling).

### CI-2 — No Result RAM (BLOCKER)

The old `timing_metric_core` reads from a **combinatorial address-indexed RAM**
(drives `result_rd_addr` ∈ [0, NSC-1] and reads `result_autocorr_I/Q/E` at that address).

`streaming_cp_autocorr` has **no internal RAM** — it only exposes the current
sliding-window output. There is no address port.

**Options:**
- **Option A (capture RAM):** Add an external lag-capture RAM that writes
  p_i[47:16]/p_q[47:16]/energy[47:16] on each `avg_pi_stb` as the stream
  passes through the frame. Then feed the RAM's read port to timing_metric_core.
- **Option B (inline argmax):** Combine the metric computation and argmax into
  the streaming path without a RAM (see §5).

### CI-3 — Interface Paradigm Incompatibility (BLOCKER)

`timing_sync_top` (old) has a **start → busy → done** FSM that can be sequenced
by `timing_frac_cfo_top`. `streaming_cp_autocorr` has **no control FSM**.

The upstream (`frac_cfo_frame_corrector_top` FSM state `S_TIMING_CFO`) expects
a done pulse to advance. Any adapter must generate a synthetic done signal when:
- NSC lags have been processed (sample_index has advanced by NSC from the lag
  window start), and
- The pipeline has fully drained (8-cycle latency).

### CI-4 — sample_index to Lag Alignment

The old path starts at `base_addr = frame_index` (an absolute buffer address).

`streaming_cp_autocorr` uses sample_index (absolute count from reset). The
mapping:

```
lag[n] = sample_index[n] - frame_index - (NSC + 8 - 1)
```

where `NSC + 8 - 1 = 263` is the pipeline fill depth before the first valid
output. The adapter must latch `frame_index` and compute the lag offset.

### CI-5 — out_valid Semantics Mismatch

Old: `done` = 1-cycle pulse after all NSC lags complete.  
New: `out_valid` = latches HIGH permanently on first window; no completion signal.

The adapter needs its own lag counter to generate the `done` equivalent.

### CI-6 — frac_cfo_estimator Result Port Incompatibility

`frac_cfo_estimator` drives `result_rd_addr` (9-bit) to select which lag's
autocorr values to feed to CORDIC. This implies a RAM at the other end.

With `streaming_cp_autocorr`, the values at `peak_lag` must be **captured and held**
as the stream passes through. The adapter must:
1. Track running argmax inline (or via Option A RAM + timing_metric_core)
2. Latch `p_i/p_q` at the argmax moment into a register
3. Feed the latched value to `frac_cfo_estimator.autocorr_I/Q`
4. Wire `frac_cfo_estimator.result_rd_addr` to nothing (or disable)

### CI-7 — IQ Convention Swap in Energy Path

`streaming_cp_autocorr:151`:
```verilog
wire [2*SAMPLE_W-1:0] s_data_swapped = {s_data[SAMPLE_W-1:0], s_data[2*SAMPLE_W-1:SAMPLE_W]};
```

This swaps `{Q, I}` to `{I, Q}` before passing to `sample_power_sq`, which
expects upper=I, lower=Q (legacy convention). The swap is **correct for energy
computation** — it computes `|I|²+|Q|²` properly.

The complex_mult path uses `s_data_reg` directly (not swapped), interpreting
`[15:0]=I, [31:16]=Q` natively. Both paths are consistent with the Phase2
IQ packing convention `{Q[31:16], I[15:0]}`.

---

## 4. Expected Regression Impact

### 4.1 peak_lag

| Scenario | Impact |
|----------|--------|
| Adapter captures all NSC lags correctly | peak_lag **identical** to old path |
| Pipeline latency off-by-one in lag counter | peak_lag ±1 → within ±1 tolerance (existing P3-15A spec) |
| Frame alignment error (frame_index mismatch) | peak_lag offset → slot_start offset → **regression** |

The streaming path uses the exact same VanDeBeek sliding-window accumulation
as cp_autocorr_core. Provided the lag counter is aligned to frame_index, the
argmax should produce the identical peak_lag as the old path.

**Risk: LOW** if lag counter implemented correctly.

### 4.2 slot_start

```
slot_start = frame_index + peak_lag
```

Propagates peak_lag directly. A ±1 error in peak_lag produces ±1 error
in slot_start. All existing regressions (P3-05C, P3-12B, P3-15A) use ±1 tolerance.

**Risk: LOW** (same as peak_lag).

### 4.3 frac_cfo_word

| Factor | Analysis |
|--------|----------|
| Scaling (48→32 via >>16) | atan2 is homogeneous of degree 0 — scaling does not change angle |
| Rounding of >>16 | 1 LSB maximum rounding error in 32-bit value; CORDIC Q1.15 output unaffected |
| Capture timing (holding p_i/p_q at peak) | If captured at exact peak, result identical to old path |
| Sign convention | streaming_cp_autocorr uses `conj(delayed) × current` (same as old path) → positive frac_phase for positive ε |

**Risk: NEGLIGIBLE** — frac_cfo_word should be bit-identical to old path given
correct peak capture. The >>16 truncation affects the 32-bit input magnitude,
not the angle.

### 4.4 Regression Matrix

| Output | Old Path | streaming_cp_autocorr (correct adapter) | Tolerance | Risk |
|--------|----------|------------------------------------------|-----------|------|
| peak_lag | argmax over 256 lags | argmax over 256 streaming outputs | ±1 sample | LOW |
| slot_start | frame_index + peak_lag | same formula | ±1 sample | LOW |
| frac_cfo_word | atan2(P_Q, P_I) at peak | same, 48-bit → 32-bit input | ±2 Q1.15 LSB | NEGLIGIBLE |
| Latency (cycles) | ~32,789 | ~NSC + 8 = 264 cycles | informational | N/A (faster) |

**Latency improvement:** streaming_cp_autocorr processes lags as they arrive
(one lag per `s_valid` cycle) → total = 264 cycles for 256 lags + 8-cycle pipeline.
This replaces the ~32,513-cycle cp_autocorr_core buffer replay.

---

## 5. Recommended Adapter / Patch

### 5.1 Recommended: Option B — Inline Streaming Argmax (no capture RAM)

Replace `timing_sync_top` with an inline adapter that tracks the argmax
**as the stream flows through**, capturing `p_i/p_q` at the peak point.

**New module: `streaming_timing_sync_adapter.v`**

```
streaming_cp_autocorr (driven by live IQ from S_AXIS or buffer replay)
  ↓ avg_pi_stb pulses (one per lag)
inline lag counter (counts from 0..NSC-1, starts when sample_index reaches
  the pipeline fill depth after frame_index)
inline metric engine (computes sq_neg per lag, no RAM needed):
  sq_neg = energy[47:16]² − 4×((p_i[47:16])² + (p_q[47:16])²)
  metric  = ~sq_neg[58:27]
inline argmax (tracks running max of metric; holds p_i/p_q at current max):
  if metric > running_max:
      running_max ← metric
      peak_lag_r  ← lag_counter
      peak_pi_r   ← p_i[47:16]   // hold for frac_cfo_estimator
      peak_pq_r   ← p_q[47:16]
done pulse when lag_counter == NSC − 1 after one more pipeline drain
```

**Interface to timing_frac_cfo_top:**
- Replace `timing_sync_top` instantiation with `streaming_timing_sync_adapter`
- Remove `buf_rd_addr/en/data` ports (no buffer read needed for autocorr)
- Provide `peak_lag`, `peak_corr_i/q` from adapter registers
- Connect `frac_cfo_estimator.autocorr_I/Q` to `peak_pi_r/peak_pq_r`
- Tie `frac_cfo_estimator.result_rd_addr` → NC (unused; frac_cfo_estimator
  ignores its own address output in this wiring)

### 5.2 Critical: lag counter alignment

The `streaming_cp_autocorr` pipeline has a fill depth of:
```
NSC + CP_LEN + 8 = 256 + 32 + 8 = 296 cycles
```
before the first `avg_pi_stb` after reset. However, the **relevant count** for
lag alignment relative to `frame_index` is:

```
first lag output arrives at:
  sample_index_at_first_stb = NSC + 8 − 1 = 263
  (NSC=256 delay fill, +8 pipeline cycles, −1 for index 0-based)

if running continuously from reset:
  lag_counter = sample_index − frame_index − 263
```

The adapter must latch `frame_index` when `tfc_start` fires and begin counting
lags from `sample_index = frame_index + 263`.

> **Important:** If `streaming_cp_autocorr` is reset and restarted per frame,
> recompute from `sample_index = 263` (since it starts from 0 after reset).

### 5.3 Signal Patch Table for timing_frac_cfo_top.v

| Old Connection | New Connection | Notes |
|----------------|----------------|-------|
| `u_tst` → `timing_sync_top` | `u_adapter` → `streaming_timing_sync_adapter` | Drop buf_rd_addr/en |
| `buf_rd_addr (tfc side)` | unused / tie 0 | No buffer read for autocorr |
| `buf_rd_data_I/Q (tfc input)` | unused | No buffer read for autocorr |
| `peak_lag` from `u_tst` | `peak_lag` from `u_adapter.peak_lag_r` | Same semantics |
| `peak_corr_i/q` from `u_tst` | NC (leave unconnected or from adapter) | frac_cfo uses adapter.peak_pi_r |
| `frac_cfo_estimator.autocorr_I/Q` | tied to `adapter.peak_pi_r/peak_pq_r` | 32-bit latched values |
| `frac_cfo_estimator.result_rd_addr` | NC | Not used in this wiring |

### 5.4 Alternative: Option A — Lag Capture RAM (if timing_metric_core must be preserved)

If `timing_metric_core.v` is to be kept unchanged:

1. Add a 256×32-bit write-once RAM alongside `streaming_cp_autocorr`
2. On each `avg_pi_stb`: write `p_i[47:16]`, `p_q[47:16]`, `energy[47:16]`
   to RAM at address `lag_counter` (same lag counter as above)
3. After NSC writes: assert done
4. Wire RAM's read port to `timing_metric_core`'s `result_rd_addr / result_autocorr_I/Q/E`

**Downside:** requires 256×32×3 = 24 Kbit of RAM (one BRAM18E2) and one extra
pipeline pass (fill + scan). Option B requires only registers.

### 5.5 Architecture Impact Summary

The shift from buffer-based (cp_autocorr_core) to streaming (streaming_cp_autocorr)
fundamentally changes the timing budget:

| Dimension | Old Path | streaming_cp_autocorr (Option B) |
|-----------|----------|----------------------------------|
| Requires buffer fill first | YES | NO (can run during S_FILL) |
| Separate S_TIMING_CFO state | YES (~32K cycles) | Optional — can overlap with S_FILL |
| Peak_lag latency after frame_index | ~32,789 cy | 264 cy (NSC + pipeline) |
| RAM resources | Internal lag RAM in cp_autocorr_core | Registers only |
| frac_cfo_estimator start | After timing_sync_top done | After lag scan done |

**If streaming_cp_autocorr runs concurrently with S_FILL:**  
The module can be started when the first IQ sample arrives, accumulating
correlations in parallel with buffer fill. By the time S_FILL completes
(at sample STIM_DEPTH=704), autocorr has been running for 704 cycles —
far more than the 264 needed. The adapter can signal done as soon as
NSC lags past frame_index are complete, eliminating S_TIMING_CFO entirely.

---

## 6. File and Symbol Cross-Reference

| File | Status | Role in old path | Role with streaming_cp_autocorr |
|------|--------|-----------------|--------------------------------|
| `rtl/DUT/streaming_cp_autocorr.v` | Present | N/A | Replaces cp_autocorr_core |
| `rtl/timing_sync_top.v` | **MISSING** | Wrapper over cp_autocorr_core + metric + peak | Replaced by adapter |
| `rtl/unit_test/cp_autocorr_core.v` | **MISSING** | Per-lag accumulator with result RAM | Replaced by streaming module |
| `rtl/DUT/timing_metric_core.v` | Present | Reads result RAM, computes sq_neg | Can be replaced by inline metric in Option B, or preserved with Option A |
| `rtl/DUT/peak_detector.v` | Present | Argmax over metric stream | Can be reused if metric stream preserved |
| `rtl/DUT/frac_cfo_estimator.v` | Present | CORDIC atan2 at peak | Reused; autocorr_I/Q source changes to held register |
| `rtl/DUT/timing_frac_cfo_top.v` | Present (broken) | Sequences timing_sync_top → frac_cfo_estimator | Needs patch per §5.3 |
| `rtl/DUT/frac_cfo_frame_corrector_top.v` | Present | Contains timing_frac_cfo_top, uses done pulse | Unmodified externally |

---

## 7. Verification Implications

### Existing golden results remain valid

All P3-05C, P3-12B, P3-15A/B/C regression results used `timing_sync_top`
(or its equivalent within the current DUT path). If the adapter is implemented
per §5.1, the expected outputs remain:

- `peak_lag = 23` (baseline stimulus)
- `slot_start = 64` (frame_index=41 + peak_lag=23)
- `frac_cfo_word ≈ 3278` (ε≈+0.05)

These should be reproduced within existing tolerances (±1, ±1, ±2 Q1.15 LSB).

### New regression check recommended

Add an explicit check after implementing the adapter:
```python
# compare_streaming_cp_autocorr_adapter.py
assert abs(rtl_peak_lag - golden_peak_lag) <= 1
assert abs(rtl_slot_start - golden_slot_start) <= 1
assert abs(rtl_frac_cfo - golden_frac_cfo) / abs(golden_frac_cfo) <= 0.01
```

### Simulation target

Adapter should be validated with:
1. `tb/p3_24b_streaming_cp_autocorr_adapter_tb.sv` — unit test with known IQ
2. Integration into `frac_cfo_frame_corrector_top` → run `run_session_A_p3_12c_full_phase3_regression.sh`
   to confirm end-to-end SANITY_GATE still PASS.
