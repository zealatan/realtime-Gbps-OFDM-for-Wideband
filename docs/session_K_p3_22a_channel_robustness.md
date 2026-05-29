# Session K / P3-22A: Channel Robustness Validation

## Gate

```
CHANNEL_GATE: PASS          — all 11 gate-required cases → CASE_PASS
CHANNEL_GATE: PARTIAL_PASS  — ≥ 8/11 required CASE_PASS; remainder documented
CHANNEL_GATE: FAIL          — < 8 gate-required cases pass
```

---

## Objective

Validate the Phase3 synchronizer pipeline robustness under realistic channel
conditions by running `phase3_sync_axis_dma_wrapper` with 15 channel-impaired
stimulus variants derived from `golden/phase3_iq_stimulus.mem`.

---

## Test Catalogue (15 cases)

### K1 — AWGN Sweep (4 cases)

| Case | SNR | Gate-required | Expected outcome |
|------|-----|---------------|-----------------|
| `awgn_snr30dB` | 30 dB | **Yes** | CASE_PASS |
| `awgn_snr20dB` | 20 dB | **Yes** | CASE_PASS (marginal: noise floor ≈ threshold) |
| `awgn_snr15dB` | 15 dB | No | CASE_FAIL expected — noise floor > threshold |
| `awgn_snr10dB` | 10 dB | No | CASE_FAIL expected — noise floor >> threshold |

**SNR definition**: measured relative to signal power over the non-zero samples
`[PRE_ZEROS=64 .. PRE_ZEROS+FRAME_LEN=640]`.  Noise is added uniformly over all 704
samples, including the zero-padded guard regions.

**Known limitation (threshold calibration)**: The frame energy detector uses a
fixed `THRESHOLD=40000`.  The noise floor energy (2σ²) exceeds this threshold
at SNR ≤ ~20 dB for the amplitude-3000 stimulus, causing the energy-based onset
detector (Case B) to see high energy throughout and fail to find the frame
boundary.  At full-scale amplitude (~32767), the equivalent threshold break-even
is ~17 dB — aligned with the real operating range.  See L-09 in the known
limitations document.

**Observable metrics per AWGN case**:
- `frame_found` — binary detection
- `frame_drift` — `frame_index − 41`
- `frac_cfo_valid`, `int_cfo_valid`, `int_cfo_applied`
- `output_count`

### K2 — Multipath Sweep (10 cases)

#### 2-tap channel: h = [1.0, 0.5], power-normalised

| Case | Delay d | max_delay/CP | Gate-required | Expected |
|------|---------|-------------|---------------|---------|
| `mp2tap_d1`  | 1  | 1/32  | **Yes** | CASE_PASS |
| `mp2tap_d4`  | 4  | 4/32  | **Yes** | CASE_PASS |
| `mp2tap_d8`  | 8  | 8/32  | **Yes** | CASE_PASS |
| `mp2tap_d16` | 16 | 16/32 | **Yes** | CASE_PASS |
| `mp2tap_d32` | 32 | 32/32 | **Yes** | CASE_PASS (delay = CP boundary) |

#### 3-tap channel: h = [1.0, 0.5, 0.25], power-normalised

| Case | Delay d | Tap delays [0,d,2d] | max_delay/CP | Gate-required | Expected |
|------|---------|---------------------|-------------|---------------|---------|
| `mp3tap_d1`  | 1  | [0, 1, 2]   | 2/32  | **Yes** | CASE_PASS |
| `mp3tap_d4`  | 4  | [0, 4, 8]   | 8/32  | **Yes** | CASE_PASS |
| `mp3tap_d8`  | 8  | [0, 8, 16]  | 16/32 | **Yes** | CASE_PASS |
| `mp3tap_d16` | 16 | [0, 16, 32] | 32/32 | **Yes** | CASE_PASS (3rd tap = CP boundary) |
| `mp3tap_d32` | 32 | [0, 32, 64] | 64/32 | No | ISI from 3rd tap (delay=64 > CP_LEN) |

**Channel model**: output[n] = Σ gains[i] × signal[n − delays[i]], power-normalised
by 1/√(Σ gains[i]²).  Tap phases are real-valued (amplitude only, no per-tap phase
rotation) — adequate for synchronization testing.

**Observable metrics per multipath case**:
- `frame_drift` = `frame_index − 41` (CP autocorrelation peak shift)
- `peak_drift`  = `peak_lag − 23` (CP autocorrelation lag shift)
- `slot_start`, `int_cfo_applied`, `output_count`

### K3 — Negative Test (1 case)

| Case | Delay | Condition | Expected |
|------|-------|-----------|---------|
| `neg_mp2tap_d33` | 33 | delay=33 > CP_LEN=32 | WARN or FAIL |

The 2-tap echo at delay=33 introduces one sample of ISI beyond the cyclic
prefix guard.  The synchronizer may still detect the frame (main path
dominates) but the ISI corrupts the OFDM subcarrier structure, making the
Meyr integer CFO estimate unreliable.  Any pipeline outcome (CASE_PASS,
CASE_PARTIAL_PASS, or CASE_FAIL) is acceptable; this case is documentation
only and does not count toward the gate.

---

## Gate-Required Cases Summary

| # | Case | Channel | Condition |
|---|------|---------|-----------|
| 1 | `awgn_snr30dB` | AWGN | SNR=30 dB |
| 2 | `awgn_snr20dB` | AWGN | SNR=20 dB |
| 3 | `mp2tap_d1`    | 2-tap | delay=1 |
| 4 | `mp2tap_d4`    | 2-tap | delay=4 |
| 5 | `mp2tap_d8`    | 2-tap | delay=8 |
| 6 | `mp2tap_d16`   | 2-tap | delay=16 |
| 7 | `mp2tap_d32`   | 2-tap | delay=32 (= CP_LEN) |
| 8 | `mp3tap_d1`    | 3-tap | delay=1 |
| 9 | `mp3tap_d4`    | 3-tap | delay=4 |
| 10 | `mp3tap_d8`   | 3-tap | delay=8 |
| 11 | `mp3tap_d16`  | 3-tap | delay=16 (3rd tap = CP_LEN) |

CHANNEL_GATE: PASS requires all 11 → CASE_PASS.

---

## Files

| File | Purpose |
|------|---------|
| `scripts/gen_p3_22a_channel_vectors.py` | Generate 15 .mem stimulus files + manifest |
| `tb/session_K_p3_22a_channel_robustness_tb.sv` | Per-case simulation testbench |
| `scripts/run_session_K_p3_22a_channel_robustness.sh` | Full runner + CHANNEL_GATE |
| `golden/p3_22a/*.mem` | Channel-impaired stimulus files (generated) |
| `golden/p3_22a/manifest.json` | Case metadata (generated) |
| `sim_out/session_K_p3_22a/p3_22a_summary.txt` | Per-case result table (generated) |
| `sim_out/session_K_p3_22a/p3_22a_channel_gate.txt` | CHANNEL_GATE result (generated) |
| `docs/session_K_p3_22a_channel_robustness.md` | This file |

---

## How to Run

```bash
cd /home/zealatan/RTL_SYNC_PHASE3

# Full run (generate vectors + all 15 simulations):
bash scripts/run_session_K_p3_22a_channel_robustness.sh

# Generate vectors only (inspect before simulating):
bash scripts/run_session_K_p3_22a_channel_robustness.sh --gen-only

# Skip vector generation (reuse existing golden/p3_22a/):
bash scripts/run_session_K_p3_22a_channel_robustness.sh --skip-gen

# Single case (debugging):
bash scripts/run_session_K_p3_22a_channel_robustness.sh --case mp2tap_d1
```

Look for `CHANNEL_GATE: PASS` at the end of the output and in
`sim_out/session_K_p3_22a/p3_22a_channel_gate.txt`.

---

## Testbench Details

**DUT**: `phase3_sync_axis_dma_wrapper` — full pipeline identical to Session E.

**Stimulus**: 704 samples, THRESHOLD_TB=40000 (calibrated for amplitude-3000 signal).

**Tolerances** (wider than Session E to accommodate channel-induced drift):

| Observable | Session E tolerance | Session K tolerance |
|-----------|---------------------|---------------------|
| frame_index | ±1 | ±5 |
| peak_lag | not checked | reported (informational) |
| output_count | == 576 | == 576 |

**Per-case output** (machine-readable, parsed by runner):
```
RESULT frame_found=N frame_idx=N frame_drift=N peak_lag=N peak_drift=N
       slot_start=N frac_valid=N int_valid=N int_applied=N
       out_count=N tlast_ok=N
CASE_PASS | CASE_PARTIAL_PASS | CASE_FAIL
```

**Watchdog**: 200000 cycles. For cases where frame detection fails, the watchdog
fires and emits `CASE_FAIL` with a diagnostic (noise-floor warning, etc.).

**Compile method**: STIM_FILE is a compile-time Verilog macro.  The runner generates
a small per-case `.vh` file (`\`define STIM_FILE "golden/p3_22a/<case>.mem"`) and
compiles it as the first source, making `$readmemh(\`STIM_FILE, ...)` in the TB
resolve to the correct path for each case.

---

## Simulation Baseline (clean stimulus, from Session E)

| Observable | Value |
|-----------|-------|
| frame_index | 41 |
| peak_lag | 23 |
| slot_start | 64 |
| frac_cfo_word | 3278 (Q1.15, eps=+0.05) |
| int_cfo_applied | 1 |
| output_count | 576 |
| total_cycles | ~103168 |

---

## Expected Results by Category

### AWGN 30 dB — Nominal channel
Noise σ ≈ 31 per component.  Noise floor ≈ 1900 << threshold=40000.
Expected: CASE_PASS with frame_drift=0, peak_drift=0.  Simulation should
match clean case within ±1 sample (statistical noise).

### AWGN 20 dB — Marginal channel
Noise σ ≈ 100 per component.  Noise floor ≈ 20000 ≈ threshold/2.
Frame detection possible but marginal.  Expected: CASE_PASS.  Minor frame_drift
(±1 to ±2) acceptable.

### AWGN 15 dB and 10 dB — Below threshold
Noise floor exceeds detection threshold.  The energy-based onset detector
(Case B in C reference) cannot distinguish signal onset from noise.
Expected: CASE_FAIL (frame not detected).  This is a documented limitation
of the fixed-threshold detector with amplitude-3000 test stimulus, not a
bug in the RTL.  At production signal levels (~32767 amplitude), the threshold
break-even is approximately 17 dB.

### 2-tap multipath, delay 1–32 — Within CP guard
Secondary echo within the cyclic prefix window (delay ≤ CP_LEN=32).
The CP autocorrelation peak may shift slightly (≤3 samples).  Frame detection,
frac CFO estimation, Meyr estimation, and replay all expected to complete.
Expected: CASE_PASS for all 5 cases.

### 3-tap multipath, delay 1–16 (max_delay ≤ CP_LEN) — Within CP guard
Similar to 2-tap.  Third tap at 2×delay ≤ 32 = CP_LEN.  Expected: CASE_PASS.

### 3-tap multipath, delay 32 (max_delay = 64 > CP_LEN) — ISI from 3rd tap
Third tap at sample 64 is 32 samples beyond the CP guard (2×CP_LEN).
Main path + second tap (at delay 32 = CP_LEN) should still allow frame
detection.  Third tap introduces ISI into the OFDM symbol.  The fft256
bypass stub does not model ISI corruption of FFT outputs.  Expected: CASE_PASS
or CASE_PARTIAL_PASS.  Not gate-required.

### Negative test, 2-tap delay 33 — 1 sample beyond CP guard
Second tap at delay 33 = CP_LEN+1.  One sample of ISI.  Main path dominates
energy; frame detection likely succeeds.  CP autocorrelation peak may shift
by ±1 sample.  Meyr CFO estimate unreliable (ISI corrupts FFT input, but
bypass stub is unaffected by ISI since it copies time-domain samples).
Expected: CASE_PASS (pipeline completes but with caveat on int_cfo accuracy).

---

## Known Limitations

1. **Fixed threshold**: `THRESHOLD=40000` is calibrated for amplitude-3000 signal.
   All AWGN tests below ~20 dB SNR will cause detection failure.  This is
   documented and not a defect in the channel-robustness infrastructure.
   Full-scale signals have ~80 dB higher energy, moving the break-even SNR to
   ~17 dB.

2. **FFT bypass stub**: `fft256_dual_symbol_frontend` passes time-domain samples
   unchanged.  For multipath cases, the ISI that would corrupt the FFT output in
   real hardware is absent from the simulation.  The Meyr integer CFO estimate
   is therefore optimistic for high-delay multipath.  Session B's real-FFT
   validation (OFFICIAL_GATE: PASS) used clean-channel stimulus only.

3. **Single-frame stimulus**: All 15 cases use one 704-sample frame.  No
   multi-frame, symbol-timing offset, or frequency-offset sweep is performed.

4. **Real-valued tap gains**: The multipath model uses real tap coefficients.
   Real hardware channels have complex tap gains (random phase per tap).  For
   synchronization testing, real gains are conservative (worst-case sum of tap
   powers; no constructive/destructive phase cancellation).

5. **Bypass-stub int_cfo unaffected by ISI**: Because `fft256_dual_symbol_frontend`
   passes time-domain samples, the Meyr cross-correlation operates on the same
   data regardless of multipath delay.  INT_CFO_INDEX and INT_CFO_EST for
   multipath cases reflect the bypass-stub result, not the true channel estimate.
