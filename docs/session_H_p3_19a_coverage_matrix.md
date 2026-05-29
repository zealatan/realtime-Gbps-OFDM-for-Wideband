# Session H / P3-19A — Verification Coverage Matrix

**Date:** 2026-05-28  
**Context:** Extends the Session A–D baseline (documented in `session_G_p3_18a_verification_matrix.md`)  
**Scope:** k_int ±12/±16, eps_frac sweep, AWGN robustness, 2-tap multipath channel

---

## 1. Coverage Dimensions

| Dimension | Baseline coverage | This session target |
|-----------|------------------|---------------------|
| Integer CFO (`k_int`) | {−8,−4,−2,−1,0,+1,+2,+4,+8} — Meyr harness only (Session B) | Add ±12, ±16 to harness; full wrapper pending real-FFT (L-01) |
| Fractional CFO (`eps_frac`) | +0.05 only (single point) | 7-point sweep: {−0.45,−0.30,−0.15, 0.00,+0.15,+0.30,+0.45} |
| AWGN noise | None (clean stimulus only) | SNR ∈ {30, 20, 15, 10 dB}; plus existing clean (∞ dB) = 5 points |
| Multipath (2-tap) | None | 3 delay × 2 gain combinations = 6 cases |

---

## 2. Pass Criteria Definitions

### 2.1 Frame Detection Success

| Metric | Pass condition | Tolerance |
|--------|---------------|-----------|
| `frame_found` | 1 | exact |
| `frame_index` | matches C reference | ±1 sample |
| `peak_lag` | matches C reference | ±1 sample |
| `slot_start_index` | = frame_index + peak_lag | ±1 sample |
| `error_code` | 0 | exact |

**AWGN note:** at SNR < ~12 dB, frame detection may fail on any single trial.
For AWGN cases the pass criterion is `frame_found=1` on each deterministic seed;
statistical pass rate analysis (multiple seeds) is out of scope for RTL simulation
and is flagged as a software-model-only task.

### 2.2 Meyr Estimator Success

| Metric | Pass condition | Notes |
|--------|---------------|-------|
| `meyr_peak_index` | 255 + k_int (Meyr harness, real FFT) | exact match required |
| `int_cfo` | k_int | exact match; derives from peak_index − 255 |
| Correlation score | > 0 (non-zero peak) | no minimum threshold defined |

**Wrapper note:** Until L-01 (FFT bypass stub) is resolved, `meyr_peak_index` in the
`phase3_sync_axis_dma_wrapper` path is always 255 or 256 (bypass artifact) regardless of k_int.
Full-wrapper Meyr accuracy tests are **blocked on L-01** and are not scheduled here.

### 2.3 Replay Continuity

| Metric | Pass condition |
|--------|---------------|
| `INT_CFO_APPLIED` | 1 (correction was applied) |
| `OUTPUT_COUNT` | 576 (full frame delivered) |
| `TLAST_COUNT` | 1 (exactly one frame boundary) |
| `replay_done` | asserted before watchdog |
| `replay_error` | 0 |

### 2.4 AXIS Stability

| Metric | Pass condition |
|--------|---------------|
| `first_tlast_idx` | 575 (TLAST at final sample) |
| IQ sample mismatch vs reference | 0/576 at ±1 LSB |
| No X-state propagation on tdata | confirmed by TB assertions |

---

## 3. Test Case Matrix

### 3.1 Integer CFO Extension — Meyr Harness (Session B style)

DUT: `meyr_fft256_actual_integration_top` | Simulator: xsim (Vivado) | Infra: **extend**

| Case | k_int | Exp peak_index | Exp int_cfo | Vector file | Status |
|------|-------|----------------|-------------|-------------|--------|
| k0 | 0 | 255 | 0 | `case_k0.mem` | Exists (Session B baseline) |
| kp1 | +1 | 256 | +1 | `case_kp1.mem` | Exists |
| km1 | −1 | 254 | −1 | `case_km1.mem` | Exists |
| kp2 | +2 | 257 | +2 | `case_kp2.mem` | Exists |
| km2 | −2 | 253 | −2 | `case_km2.mem` | Exists |
| kp4 | +4 | 259 | +4 | `case_kp4.mem` | Exists |
| km4 | −4 | 251 | −4 | `case_km4.mem` | Exists |
| kp8 | +8 | 263 | +8 | `case_kp8.mem` | Exists (Session B) |
| km8 | −8 | 247 | −8 | `case_km8.mem` | Exists (Session B) |
| **kp12** | **+12** | **267** | **+12** | `case_kp12.mem` | **New — needs gen** |
| **km12** | **−12** | **243** | **−12** | `case_km12.mem` | **New — needs gen** |
| **kp16** | **+16** | **271** | **+16** | `case_kp16.mem` | **New — needs gen** |
| **km16** | **−16** | **239** | **−16** | `case_km16.mem` | **New — needs gen** |

**Peak index arithmetic:** `peak_index = 255 + k_int`. For k_int > 0 the cross-correlation lag
exceeds 255; the 511-lag correlator in `meyr_integer_cfo_core` has valid outputs from lag 0 to
510 so ±127 is the theoretical limit. No modular wrap occurs in the correlation output.

**Infrastructure delta:** Extend `SWEEP_K_INT` in `gen_phase3_integer_cfo_sweep_vectors.py`
to include ±12, ±16 and re-run to generate the four new `.mem` files and update
`manifest.json`.

---

### 3.2 Fractional CFO Sweep — `phase3_sync_top`

DUT: `phase3_sync_top` | Simulator: iverilog (SANITY) / xsim (CI) | Infra: **new**

The VanDeBeek estimator is theoretically valid for |eps_frac| < 0.5.
Practical edge cases occur near ±0.5 where the CP autocorrelation metric wraps.

| Case | eps_frac | Exp frac_cfo_word_q15 | Frame det. pass | Frac CFO tol | Status |
|------|----------|-----------------------|-----------------|--------------|--------|
| ef_m45 | −0.45 | −14746 | required | ±1% rel | New |
| ef_m30 | −0.30 | −9830 | required | ±1% rel | New |
| ef_m15 | −0.15 | −4915 | required | ±1% rel | New |
| ef_0 | 0.00 | 0 | required | ±1% rel | New |
| ef_p15 | +0.15 | +4915 | required | ±1% rel | New |
| **ef_p05** | **+0.05** | **3277** | **PASS** (Session A) | ±1% rel | **Baseline — exists** |
| ef_p30 | +0.30 | +9830 | required | ±1% rel | New |
| ef_p45 | +0.45 | +14746 | required | ±1% rel | New |

`frac_cfo_word_q15 = round(eps_frac × 2 × 32768)`

**Pass criteria per case:**
- `frame_found = 1`
- `frame_index`, `peak_lag`, `slot_start_index` within ±1 sample of C reference
- `frac_cfo_word` within ±1% of q15 expected
- `int_cfo_valid` asserted (pipeline completes)

**Infrastructure delta:**
1. New generator `scripts/gen_phase3_eps_frac_sweep_vectors.py` producing 8 `.mem` files
   in `golden/p3_19a_eps_sweep/` and a `manifest.json`.
2. Extend `scripts/golden_dump.c` (or call with `eps_frac` argument override) to produce
   C reference golden for each eps_frac case.
3. New TB `tb/session_H_p3_19a_eps_frac_sweep_tb.sv` (parametric eps_frac loop or separate
   initial blocks per case), or reuse Session A TB with a vector-file override parameter.
4. New runner `scripts/run_session_H_p3_19a_eps_frac_sweep.sh`.
5. New compare script `scripts/compare_session_H_p3_19a_eps_frac_sweep.py`.

---

### 3.3 AWGN Robustness — `phase3_sync_top`

DUT: `phase3_sync_top` | Simulator: iverilog (SANITY) | Infra: **new**

AWGN is added to the baseband IQ after fractional CFO rotation. SNR is defined as signal
energy per sample divided by noise variance per complex sample:
`SNR_dB = 10·log10(E_s / N_0)` where E_s is per-sample RMS power of the OFDM payload.

Each case uses a fixed noise seed (`NOISE_SEED = 0xDEADBEEF`) to produce deterministic
simulation output.

| Case | SNR (dB) | Exp frame_found | Exp frac_cfo accuracy | Frame det. criterion | Status |
|------|----------|-----------------|-----------------------|---------------------|--------|
| awgn_clean | ∞ | 1 | ±1% | hard-exact | Baseline (Session A) |
| awgn_30 | 30 | 1 | ±1% | required | New |
| awgn_20 | 20 | 1 | ±1% (degraded OK) | required | New |
| awgn_15 | 15 | 1 | ±2% (relaxed) | required | New |
| awgn_10 | 10 | 1 | ±5% (relaxed) | best-effort | New |

**Pass criteria:**
- SNR ≥ 15 dB: `frame_found=1` required. Index tolerance remains ±1.
  `frac_cfo_word` tolerance relaxed to ±2% at 15 dB.
- SNR = 10 dB: `frame_found=1` is best-effort (may WARN rather than FAIL).
  frac_cfo tolerance ±5%. Failure here is informational, not a gate blocker.
- `int_cfo_valid` asserted in all passing cases (pipeline reaches completion).

**Threshold sensitivity note:** The AWGN generator must scale noise relative to the
`TARGET_PEAK=3000` stimulus amplitude. The frame detector `THRESHOLD_VAL=40000` in
testbenches is tuned for this amplitude; with AWGN the effective energy drops and
the threshold may need a case-specific `THRESHOLD_SCALE` parameter. This is a TB
concern, not an RTL concern.

**Infrastructure delta:**
1. Add AWGN injection to `scripts/gen_phase3_iq_stimulus.py`:
   - New `--noise-snr <dB>` CLI argument and `NOISE_SEED` parameter.
   - `noise_sigma = sqrt(E_s / 10^(SNR/10))` per component.
   - Output: `golden/p3_19a_awgn/case_snr<X>.mem` + `case_snr<X>_meta.json`.
2. TB: parametric `THRESHOLD_SCALE` input or per-case threshold file.
3. Runner `scripts/run_session_H_p3_19a_awgn_sweep.sh`.
4. Compare script with SNR-dependent tolerance tiers.

**Not in scope here:** Monte Carlo BER/detection-probability analysis (multiple noise
seeds). That is a software simulation task, not RTL simulation.

---

### 3.4 Multipath Channel — `phase3_sync_top`

DUT: `phase3_sync_top` | Simulator: iverilog (SANITY) | Infra: **new**

A 2-tap channel model is applied after OFDM frame construction and before Q15 quantization:
```
y[n] = x[n] + α × x[n − d]
```
where d is the delay in samples and α is the complex path gain magnitude (phase = 0).

The CP length is CP_LEN=32. As long as d ≤ CP_LEN, the cyclic prefix absorbs the delay
spread and frame detection should succeed. For d > CP_LEN, ISI corrupts the CP structure
and frame detection failure is expected.

| Case | Delay d (samples) | Gain α | d ≤ CP? | Exp frame_found | Status |
|------|-------------------|--------|---------|-----------------|--------|
| mp_clean | 0 | 0.0 | — | 1 | Baseline (Session A) |
| mp_d1_a01 | 1 | 0.1 | yes | 1 | New |
| mp_d4_a03 | 4 | 0.3 | yes | 1 | New |
| mp_d8_a05 | 8 | 0.5 | yes | 1 (may degrade) | New |
| mp_d16_a03 | 16 | 0.3 | yes | 1 | New |
| mp_d32_a01 | 32 | 0.1 | yes (boundary) | 1 (marginal) | New |
| mp_d33_a01 | 33 | 0.1 | **no** | 0 or 1 | New (expected fail case) |

**Pass criteria:**
- d ≤ CP_LEN−1 (d ≤ 31): `frame_found=1` required.
  - The CP autocorrelation metric is reduced by the multipath-induced self-interference,
    but the dominant path still produces a peak above the energy threshold.
  - Index tolerance remains ±1.
- d = CP_LEN (d = 32): marginal case; `frame_found=1` expected but may WARN.
- d > CP_LEN (d = 33): `frame_found` may be 0 or 1 depending on whether the ghost path
  disrupts the CP correlation. This case is included as a **negative test** —
  WARN if frame_found=1 with wrong index; PASS if frame_found=0.
- `frac_cfo_word` tolerance relaxed to ±5% for multipath cases (multipath biases the
  autocorrelation peak, introducing phase error in the CFO estimate).

**Infrastructure delta:**
1. New channel model function in the stimulus generator:
   - `apply_multipath(frame, delay_samples, alpha)` → `y[n] = x[n] + α × x[n−d]`
   - Output: `golden/p3_19a_multipath/case_mp_d<D>_a<A>.mem` + metadata JSON.
2. C reference golden for each case (run `golden_dump` on each multipath-distorted stimulus).
3. TB: same structure as Session H eps_frac TB; swap input stimulus file per case.
4. Runner `scripts/run_session_H_p3_19a_multipath_sweep.sh`.
5. Compare script with multipath-relaxed frac_cfo tolerance.

---

## 4. Infrastructure Requirements Summary

| Script / File | Action | Session A/B/C/D dep? | Priority |
|---------------|--------|---------------------|----------|
| `gen_phase3_integer_cfo_sweep_vectors.py` — add ±12, ±16 to `SWEEP_K_INT` | Extend | Session B runner | P1 |
| `golden/p3_09_sweep/case_k{p,m}{12,16}.mem` + `manifest.json` update | Generate | — | P1 |
| `scripts/run_session_B_p3_13c_real_fft_ip_xsim.sh` — consume new cases | Extend | Vivado/xsim | P1 |
| `scripts/gen_phase3_eps_frac_sweep_vectors.py` | New | — | P2 |
| `scripts/golden_dump.c` — accept `--eps-frac` CLI arg | Extend | — | P2 |
| `tb/session_H_p3_19a_eps_frac_sweep_tb.sv` | New | Session A TB model | P2 |
| `scripts/run_session_H_p3_19a_eps_frac_sweep.sh` | New | — | P2 |
| `scripts/compare_session_H_p3_19a_eps_frac_sweep.py` | New | Session D compare model | P2 |
| AWGN noise injection in `gen_phase3_iq_stimulus.py` | Extend | — | P3 |
| `scripts/run_session_H_p3_19a_awgn_sweep.sh` | New | — | P3 |
| Channel model function (multipath) | New | — | P4 |
| `scripts/run_session_H_p3_19a_multipath_sweep.sh` | New | — | P4 |

---

## 5. Dependency Map

```
L-01 RESOLVED (real FFT in phase3_sync_top)
    └─► k_int ±12/±16 through full wrapper
    └─► Integer CFO accuracy end-to-end for all eps_frac sweep cases

L-01 NOT REQUIRED for:
    ├─► k_int ±12/±16 Meyr harness (Session B style)   ← P1 — ready now
    ├─► eps_frac sweep through phase3_sync_top          ← P2
    ├─► AWGN through phase3_sync_top                    ← P3
    └─► Multipath through phase3_sync_top               ← P4

Session D Stage 4/5 golden (c_m_axis_iq_golden.txt)
    └─► Not required for Session H (no full wrapper IQ comparison planned here)
```

---

## 6. Meyr Estimator Range Boundary Analysis

The 511-lag cross-correlator in `meyr_integer_cfo_core` covers lags 0–510 with CENTER=255.
The usable unambiguous range is:

```
|k_int| ≤ 127   →  peak_index ∈ [128, 382]  (no edge effect)
k_int = ±128    →  peak_index = 127 or 383   (edge of correlator)
k_int = ±255    →  peak_index = 0 or 510     (theoretical maximum)
```

For this session, testing up to |k_int| = 16 is well within the unambiguous range.
Values beyond ±16 are out of scope but the infrastructure (manifest, compare script)
should be designed to accommodate future extension to ±32 or beyond.

**k_int = ±12 risk:** None. Peak at 243/267 is central in the correlator output.  
**k_int = ±16 risk:** None. Peak at 239/271 well within valid range.

---

## 7. Gate Definitions for Session H

| Test group | Pass gate name | Authority |
|------------|---------------|-----------|
| k_int ±12/±16 Meyr harness | `OFFICIAL_GATE_MEYR_EXT` | xsim (Vivado) |
| eps_frac sweep `phase3_sync_top` | `SANITY_GATE_EPS_SWEEP` | iverilog |
| eps_frac sweep `phase3_sync_top` | `CI_GATE_EPS_SWEEP` | xsim (pending) |
| AWGN `phase3_sync_top` | `SANITY_GATE_AWGN` | iverilog |
| Multipath `phase3_sync_top` | `SANITY_GATE_MP` | iverilog |

All gates follow the project policy: iverilog = SANITY only; xsim = CI or OFFICIAL.

---

## 8. Files This Session Creates

| File | Purpose |
|------|---------|
| `docs/session_H_p3_19a_coverage_matrix.md` | This document |

No RTL is modified in Session H. All changes are to test infrastructure
(`scripts/`, `golden/`, `tb/`).
