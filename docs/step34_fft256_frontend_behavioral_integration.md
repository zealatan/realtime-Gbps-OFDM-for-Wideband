# Step 34 — FFT256 Frontend Wrapper and Behavioral FFT Integration

## Objective

Connect a synthesizable FFT256 dual-symbol frontend to the Meyr integer CFO estimator
(`meyr_integer_cfo_freq_estimator_top`).  Validate the complete pipeline — PSS/SSS
time-domain input → FFT → bin pairing → integer CFO estimation — through simulation.

## Relationship to Steps 30–33

| Step | Deliverable |
|------|-------------|
| 30   | Meyr integer CFO architecture and core algorithm spec |
| 31   | `meyr_integer_cfo_core.v` (511-lag correlator, synthetic PRNG term2 ROM) |
| 32   | `meyr_pss_sss_product_gen.v`, `meyr_integer_cfo_freq_estimator_top.v` (product generator, estimator top) |
| 33   | Audit — real mU/goldU unavailable (Outcome C); template generator ready |
| 34   | FFT frontend interface, behavioral DFT model, top-level integration, T1–T12 testbench |

## Why No Xilinx FFT IP

Vivado FFT IP (v9.1) requires:
- A license (not confirmed available in this environment)
- IP generation/synthesis steps that add board dependency
- AXI4-Stream handshake that differs from the simple streaming interface here

Step 34 defers the production FFT to a later step.  The frontend uses a placeholder
S_COMPUTE stage (buffer bypass) so that the interface, FSM, and bin-pairing logic can
be verified immediately in simulation.

## FFT Bin Order Convention

Natural order (same as most FFT IP defaults):

```
k = 0          : DC
k = 1..127     : positive frequencies
k = 128..255   : negative frequencies
```

No fftshift is applied.  The Meyr estimator indexes directly into natural-order bins.

## DFT Scaling Convention

Unnormalized (used in `fft256_behavioral_model.sv`):

```
X[k]_I = Σ_{n=0}^{N-1} ( x_i[n]·cos(2π·k·n/N) + x_q[n]·sin(2π·k·n/N) )
X[k]_Q = Σ_{n=0}^{N-1} (-x_i[n]·sin(2π·k·n/N) + x_q[n]·cos(2π·k·n/N) )
```

Amplitude of X[k] for a unit-amplitude pure-tone input = N = 256.  DC test:
all-ones in_i → X[0]_I = 256, X[0]_Q = 0, all other bins ≈ 0.

## Frontend Interface (`fft256_dual_symbol_frontend`)

| Signal | Direction | Description |
|--------|-----------|-------------|
| `s_valid/s_ready` | input/output | Time-domain input handshake |
| `s_symbol_sel` | input | 0 = PSS, 1 = SSS |
| `s_index[7:0]` | input | Sample index 0..FFT_LEN-1 |
| `s_i/s_q` | input | IQ sample |
| `m_valid/m_ready` | output/input | Frequency-domain output handshake |
| `m_symbol_sel` | output | 0 = PSS_FFT, 1 = SSS_FFT |
| `m_index[7:0]` | output | Bin index 0..FFT_LEN-1 |
| `m_i/m_q` | output | IQ bin value |

**State machine**: S_IDLE → S_FILL (accept 256 PSS + 256 SSS samples) →
S_COMPUTE (FFT placeholder: buffer bypass) → S_STREAM_PSS (stream 256 PSS bins) →
S_STREAM_SSS (stream 256 SSS bins) → S_DONE.

**FFT placeholder (S_COMPUTE)**: copies `pss_buf → fft_pss` and `sss_buf → fft_sss`
in a single clocked for-loop (256 parallel NBA assignments).  Replace S_COMPUTE with
an FFT IP instantiation for production.

## Behavioral DFT Model (`fft256_behavioral_model`)

Simulation-only module guarded by `// synthesis translate_off`.  Uses `$cos`/`$sin`
real arithmetic to compute the unnormalized DFT.  Results are round-to-nearest,
saturated to IQ_WIDTH bits.

Triggered on `posedge compute`; results available after one delta step.  Used in T2
only (standalone DFT DC validation).

## Estimator Integration (`meyr_integer_cfo_fft_frontend_top`)

Top-level module connecting the frontend to the estimator:

1. **S_FILL_PSS**: Accept PSS FFT bins from `fft256_dual_symbol_frontend`.  SSS bins
   are stalled (`fft_m_ready = !fft_m_symbol_sel || !fft_m_valid`).  After 256 PSS bins
   are stored in `pss_fft_buf`, transition to S_START_EST.

2. **S_START_EST**: Pulse `est_start` for one cycle to arm the estimator.

3. **S_STREAM_SSS**: Stream SSS bins from the frontend to the estimator.  Each SSS bin
   is paired with the buffered PSS bin at the same index (`pss_fft_buf[fft_m_index]`).
   Backpressure: `fft_m_ready = est_s_ready`.

4. **S_WAIT_EST**: Wait for `est_done`; capture `int_cfo`, `peak_index`, `peak_score`.

5. **S_DONE**: Pulse `done` for one cycle; return to S_IDLE.

## Synthetic term2 ROM Limitation

The Meyr correlator (`meyr_integer_cfo_core.v`) uses a synthetic XOR-shift32 PRNG
term2 ROM (seed `32'hCAFE_B0BB`).  Real mU/goldU sequences from the transmitter
are unavailable in this repository (Step 33 Outcome C).

The testbench mirrors the same PRNG sequence to build shift test vectors, so the
correlation peak is correctly reproduced despite the synthetic data.  When real
mU/goldU become available, replace the ROM contents and re-run the Step 32 + Step 34
regression.

## Testbench Scenarios (T1–T12)

| Test | Description | Checks |
|------|-------------|--------|
| T1 | reset_defaults | busy=0, done=0, error=0 after reset |
| T2 | fft_model_single_bin (DC) | X[0]_I=256, X[0]_Q=0, X[1]_I=0 |
| T3 | zero_cfo (shift=0) | peak_index=255, int_cfo=0, peak_score>0 |
| T4 | positive_shift +1 | peak_index=256, int_cfo=+1 |
| T5 | negative_shift −1 | peak_index=254, int_cfo=−1 |
| T6 | positive_shift +3 | peak_index=258, int_cfo=+3 |
| T7 | negative_shift −4 | peak_index=251, int_cfo=−4 |
| T8 | positive_shift +8 | peak_index=263, int_cfo=+8 |
| T9 | negative_shift −8 | peak_index=247, int_cfo=−8 |
| T10 | restart_two_frames | two consecutive runs: shift=0 then shift=+3 |
| T11 | start_while_busy | error asserted when start pulses during busy |
| T12 | index_alignment | shift +2 (peak=257) and −2 (peak=253) |

**Bypass mode** (T3–T12): frequency-domain vectors are injected as "time-domain" input.
`PSS_freq[k] = term2_prng[k − shift_s]`, `SSS_freq[k] = 1 + j0`.  The frontend's
S_COMPUTE bypass copies these unchanged, so the estimator receives correct bin values.

## Simulation Command

```bash
bash scripts/run_meyr_integer_cfo_fft_frontend_top_sim.sh
```

## Simulation Result

See `logs/meyr_integer_cfo_fft_frontend_top_xsim.log` after running the script.

## Debug Note — SSS Bin Alignment Fix (Step 34)

**Root cause**: `fft256_dual_symbol_frontend` S_STREAM_SSS used unconditional NBA
`m_index <= stream_ptr` every cycle.  When the first handshake fired, stream_ptr
advanced but the NBA committed the PRE-advance value, so m_index stayed at the
old value for one extra cycle.  This caused SSS bin 0 to be presented twice and
SSS bin 255 to be skipped, shifting the correlation peak by ±8 depending on
whether the stale PSS→SSS transition cycle spuriously advanced stream_ptr.

**Fix applied to `rtl/fft256_dual_symbol_frontend.v` S_STREAM_SSS**:

1. Guard advance with `if (m_ready && m_symbol_sel)` — prevents the stale
   first cycle (m_symbol_sel still 0 from S_STREAM_PSS) from spuriously
   advancing stream_ptr.

2. Look-ahead NBA in the advance branch — when stream_ptr increments, override
   m_index/m_i/m_q with the NEXT value so the last NBA wins and the consumer
   sees the correct next bin immediately:
   ```verilog
   stream_ptr <= stream_ptr + 8'd1;
   m_index    <= stream_ptr + 8'd1;
   m_i        <= fft_sss_i[stream_ptr + 8'd1];
   m_q        <= fft_sss_q[stream_ptr + 8'd1];
   ```

The stale first cycle still delivers PSS bin 255 to the top's PSS buffer
(m_index=255, m_symbol_sel=0 at start of S_STREAM_SSS) — this is intentional
and correct.  The fix preserves that behavior.

**Other invariants confirmed correct**:
- Natural FFT bin order preserved (no fftshift).
- Behavioral DFT model is simulation-only (synthesis translate_off guards).
- Synthetic term2 PRNG fallback still used; real mU/goldU still pending.
- Xilinx FFT IP not integrated (S_COMPUTE is a buffer bypass placeholder).

## Known Limitations

1. FFT is a placeholder (buffer bypass).  True time-domain → FFT → estimator path
   requires a production FFT IP (e.g., Xilinx FFT v9.1).
2. term2 ROM is synthetic PRNG.  Real mU/goldU are unavailable (Step 33 Outcome C).
3. Board integration not included.
4. `fft256_behavioral_model` is simulation-only; not synthesizable.

## Next Steps

- Step 35: Integrate Xilinx FFT IP (AXI4-Stream) into `fft256_dual_symbol_frontend`
  to replace S_COMPUTE placeholder.
- Separately: supply `data/mu_goldu.json`, run `scripts/generate_meyr_term2_rom.py`,
  update term2 ROM in `meyr_integer_cfo_core.v`, re-run regression.
