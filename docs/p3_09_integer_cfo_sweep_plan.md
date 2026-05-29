# P3-09 — Integer CFO Sweep Verification Plan

**Version:** 1.0  
**Date:** 2026-05-28  
**Status:** INFRASTRUCTURE READY — Execution blocked on real FFT integration

---

## Objective

Verify that the Meyr integer CFO estimator correctly identifies integer CFO offsets
across a representative sweep of k_int values by comparing RTL simulation output
against analytically expected peak indices and step words.

---

## Sweep Parameters

| Parameter | Value |
|-----------|-------|
| Sweep values | k_int ∈ {-8, -4, -2, -1, 0, +1, +2, +4, +8} |
| NSC | 256 |
| CP_LEN | 32 |
| SEED | 0xC0FFEE |
| EPS_FRAC | 0.05 |
| Amplitude | 3000 (per component, Q15) |
| THRESHOLD_VAL (TB) | 40000 |

---

## Step-Word Convention

```
CENTER          = NSC − 1 = 255
NSC_LOG2        = log2(NSC) = 8
INT_CFO_SHIFT   = 32 − NSC_LOG2 = 24
int_cfo (s16)   = peak_index − CENTER
integer_cfo_word (s32) = (−int_cfo) << INT_CFO_SHIFT = −k_int × 16777216
```

---

## Test Matrix

| Case | k_int | Stimulus file | Expected peak_index | Expected int_cfo | Expected integer_cfo_word |
|------|-------|---------------|---------------------|------------------|---------------------------|
| km8  |    -8 | case_km8.mem  |                 247 |               -8 |              +134217728   |
| km4  |    -4 | case_km4.mem  |                 251 |               -4 |               +67108864   |
| km2  |    -2 | case_km2.mem  |                 253 |               -2 |               +33554432   |
| km1  |    -1 | case_km1.mem  |                 254 |               -1 |               +16777216   |
| k0   |     0 | case_k0.mem   |                 255 |                0 |                       0   |
| kp1  |    +1 | case_kp1.mem  |                 256 |               +1 |               -16777216   |
| kp2  |    +2 | case_kp2.mem  |                 257 |               +2 |               -33554432   |
| kp4  |    +4 | case_kp4.mem  |                 259 |               +4 |               -67108864   |
| kp8  |    +8 | case_kp8.mem  |                 263 |               +8 |              -134217728   |

Peak index is bounded by the 9-bit INDEX_WIDTH (0..511). All values above are within range.

---

## Expected Front-End Outputs (Same for All Cases)

Integer CFO rotation does NOT perturb the VanDeBeek autocorrelator or frame detector:
- `exp(j·2π·k_int·(m+k)/NSC) × exp(−j·2π·k_int·(m+k+NSC)/NSC) = exp(−j·2π·k_int) = 1`

Therefore all k_int cases share the same front-end result:

| Field | Expected |
|-------|----------|
| DETECTION_STATUS | 1 |
| frameStart | 41 |
| peakIndex (autocorr) | 23 |
| slotStartIndex | 64 |
| frac CFO word (Q1.15) | ≈ 3276 |
| PSS_START | 32 |
| SSS_START | 320 |
| PSS_SAMPLE_COUNT | 256 |
| SSS_SAMPLE_COUNT | 256 |

---

## Pass / Fail Criteria

A case is **PASS** if ALL of the following hold:

| Check | Condition | Tolerance |
|-------|-----------|-----------|
| detection | DETECTION_STATUS == 1 | exact |
| timeout | RTL_DONE == 1 within 2M cycles | exact |
| false_valid | RTL_ERROR_CODE == 0 | exact |
| meyr_peak_index | RTL_MEYR_PEAK_INDEX == 255 + k_int | ±1 |
| integer_cfo_estimate | int_cfo (derived from word) == k_int | exact |
| integer_cfo_word | RTL_INTEGER_CFO_WORD == −k_int × 16777216 | exact |

Derivation: `int_cfo_from_word = −RTL_INTEGER_CFO_WORD / 16777216` (arithmetic right shift 24).

---

## Limitations While FFT Is Bypass / Injected

**CRITICAL:** The current `fft256_dual_symbol_frontend.v` is a bypass stub that copies
time-domain buffers unchanged to the FFT output buffers.

In bypass mode, the Meyr core computes:
```
term1[j] = PSS_td_shifted[j] × conj(SSS_td_shifted[j])
         = PSS_td_ref[j] × exp(j·2π·k_int·j/NSC) × conj(SSS_td_ref[j]) × exp(−j·2π·k_int·j/NSC)
         = PSS_td_ref[j] × conj(SSS_td_ref[j])     ← k_int cancels
         = term1_ref[j]
```

The correlation peak is always at lag=255 regardless of k_int.

**Consequence:**
- k_int=0 case: passes with bypass FFT (verified in P3-08, CI_GATE PASS)
- k_int≠0 cases: will give peak=255, int_cfo=0 — WRONG answer for the sweep goal

**Requirement for k_int≠0:** Replace `fft256_dual_symbol_frontend.v` S_COMPUTE state
with a real FFT (e.g., Xilinx FFT IP via `meyr_fft256_actual_integration_top.v`) and
replace the reference ROM with frequency-domain cross-products derived from the
Zadoff-Chu PSS and Gold-code SSS reference sequences.

---

## Dependencies

| Dependency | Status | Owner |
|------------|--------|-------|
| P3-08 Meyr backend (k_int=0 baseline) | **DONE — CI_GATE PASS** | P3-08 session |
| Sweep vector generator | **DONE — skeleton** | P3-09 session |
| Real FFT backend (fft256_dual_symbol_frontend) | **BLOCKED** | future session |
| Frequency-domain reference ROM | **BLOCKED** (requires real FFT) | future session |

---

## Estimated ROM Strategy for Real FFT Path

When real FFT is available:
```
PSS_fft[j]  = DFT(PSS_td_ref)[j]   (256-point FFT of PSS OFDM symbol)
SSS_fft[j]  = DFT(SSS_td_ref)[j]   (256-point FFT of SSS OFDM symbol)
term1_fft[j] = PSS_fft[j] × conj(SSS_fft[j])

PSS_rom[j]   = term1_fft[j]  normalized to Q1.15
SSS_rom_I[j] = +32767  (sign = +1, same convention as P3-08 bypass ROM)
```

The correlation then peaks at `lag = k_int`, i.e., `peak_index = 255 + k_int`. ✓

---

## Output Files

All sweep artifacts live under `golden/p3_09_sweep/`:

```
golden/p3_09_sweep/
├── manifest.json           — expected values for all 9 cases
├── case_km8.mem            — IQ stimulus, k_int = -8
├── case_km4.mem            — IQ stimulus, k_int = -4
├── case_km2.mem            — IQ stimulus, k_int = -2
├── case_km1.mem            — IQ stimulus, k_int = -1
├── case_k0.mem             — IQ stimulus, k_int =  0
├── case_kp1.mem            — IQ stimulus, k_int = +1
├── case_kp2.mem            — IQ stimulus, k_int = +2
├── case_kp4.mem            — IQ stimulus, k_int = +4
└── case_kp8.mem            — IQ stimulus, k_int = +8
```

Simulation results (written by runner after real FFT is ready):
```
sim_out/p3_09_sweep/
└── case_{tag}_results.txt  — RTL key=value file per case
```
