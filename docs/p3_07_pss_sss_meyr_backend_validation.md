# P3-07 — PSS/SSS Extraction + FFT/Meyr Backend Validation

**Version:** 1.0  
**Date:** 2026-05-28  
**Status:** CI_GATE PASS (8 checks) — Integer CFO blocked (informational)

---

## Overview

Backend audit of the PSS/SSS extraction and Meyr integer CFO path following the
passing P3-05C front-end synchronizer. Adds sample-level observability for the
extractor and captures the Meyr peak index.

---

## Simulation Environment

| Item | Value |
|---|---|
| Simulator | Icarus Verilog 11.0 (iverilog + vvp) |
| DUT | phase3_sync_top |
| IQ stimulus | golden/phase3_iq_stimulus.f32 (704 samples, amplitude ~3000) |
| Cycles to DONE | 105,321 |

---

## Comparison Results

| Check | Golden | RTL | Delta | Tolerance | Result |
|---|---|---|---|---|---|
| DETECTION_STATUS | 1 | 1 | — | exact | **PASS** |
| frameStart | 41 | 41 | 0 | ±1 | **PASS** |
| peakIndex | 23 | 23 | 0 | ±1 | **PASS** |
| slotStartIndex | 64 | 64 | 0 | ±1 | **PASS** |
| frac CFO | 0.049999 | 0.049988 | 0.8 LSB | 1% or ±2 LSB | **PASS** |
| PSS_START | 32 | 32 | 0 | exact | **PASS** |
| SSS_START | 320 | 320 | 0 | exact | **PASS** |
| PSS_SAMPLE_COUNT | 256 | 256 | 0 | exact | **PASS** |
| SSS_SAMPLE_COUNT | 256 | 256 | 0 | exact | **PASS** |
| Integer CFO word | — | −16777216 | — | informational | INFO |
| Meyr peak index | — | 0 | — | informational | INFO |

**Overall: CI_GATE PASS**

---

## Backend Audit Findings

### 1. PSS/SSS Extraction: PASS

`pss_sss_symbol_extractor` correctly extracts:
- PSS window: frame indices [32..287] — 256 samples at correct offset
- SSS window: frame indices [320..575] — 256 samples at correct offset

Confirmed by sample counting via hierarchy access (`u_dut.ext_m_tvalid/ready/tdata`).

Observed timing (from `$display` trace):
```
@37399 PSS first sample: I=672  Q=374
@37909 PSS window done: 256 samples
@37975 SSS first sample: I=1516  Q=954
@38485 SSS window done: 256 samples
```

PSS spans 510 cycles for 256 samples — matches 2 cycles/sample (pss_fft_start index
skip overhead from the extractor FSM counting from frame sample 0).

### 2. FFT Frontend: BLOCKED (bypass stub)

`fft256_dual_symbol_frontend.v` S_COMPUTE state copies time-domain input buffers
unchanged to the "FFT output" buffers — no computation. Comment in source:
```
// FFT PLACEHOLDER: copy time-domain buffers to FFT output buffers
```

The meyr estimator therefore receives time-domain samples as if they were
frequency-domain bins.

### 3. Reference ROMs: BLOCKED (all zeros)

`vectors/meyr_pss_reference_romhex.txt` and `vectors/meyr_sss_reference_romhex.txt`
both contain 256 lines of `00000000`. With zero term2:
- All correlation scores = 0 for every lag
- Argmax defaults to first non-decreasing index → peak_index = 0
- int_cfo depends on how the estimator interprets peak_index=0

Observed: `RTL_MEYR_PEAK_INDEX 0`, `RTL_INTEGER_CFO_WORD -16777216` (= -2^24).

### 4. Integer CFO: BLOCKED

Two independent blockers, either of which alone would invalidate the estimate:
1. FFT is bypass — estimator receives time-domain data as frequency bins
2. ROM is all zeros — correlation always zero, argmax meaningless

The step word -16777216 = -2^24 decodes as approximately 1 subcarrier bin of
integer CFO offset, but this value has no physical meaning given the two blockers.

### 5. meyr_fft256_actual_integration_top: NOT in sim path

`rtl/meyr_fft256_actual_integration_top.v` exists and wraps `fft256_xilinx_wrapper`
with proper PSS/SSS buffering, FFT streaming, and flush logic. It is NOT
instantiated in `phase3_sync_top.v`. Wiring it in requires `USE_BEHAVIORAL_STUB=1`
for simulation (Xilinx IP not available).

---

## Files Modified

| File | Change |
|---|---|
| `tb/phase3_sync_reference_compare_tb.sv` | PSS/SSS hierarchy monitoring; meyr peak capture; 11 new rtl_results.txt fields |
| `scripts/golden_dump.c` | Added PSS_SAMPLE_COUNT + SSS_SAMPLE_COUNT fields |
| `scripts/compare_golden_rtl.py` | Added Check 7 (PSS count) and Check 8 (SSS count) |
| `docs/p3_07_pss_sss_meyr_backend_validation.md` | This file |
| `md_files/p3_07_pss_sss_meyr_backend_validation_prompt.md` | Mandatory archive |

---

## ROM Replacement Plan (to unblock integer CFO)

1. **Generate real PSS/SSS reference sequences** using a Python script:
   - PSS: Zadoff-Chu sequence with root u=25 (NR primary synchronization)
   - SSS: BPSK-modulated Gold code (LTE/NR secondary synchronization)
   - term2[j] = {sign(SSS_I[j]) × PSS_Q[j], sign(SSS_I[j]) × PSS_I[j]} packed as Q1.15

2. **Populate `vectors/meyr_pss_reference_romhex.txt`** (256 lines, 8-digit hex)

3. **Replace stub FFT** with either:
   - A Python DFT that pre-computes frequency-domain stimulus and injects it through the
     existing bypass path (no RTL change needed)
   - Or wire `meyr_fft256_actual_integration_top` with `USE_BEHAVIORAL_STUB=1`

4. **Verify** `integer_cfo_word = 0` for INT_CFO=0 stimulus (peak should land at
   index 255 for zero-CFO correlation, depending on ZC root convention).

---

## Known Caveats

| Caveat | Notes |
|---|---|
| THRESHOLD_VAL = 40,000 in TB | For amplitude-3000 stimulus only; real signals need ~10,240,000 |
| Integer CFO informational | Step word -16,777,216 is an artifact of all-zero ROM, not a real estimate |
| Meyr peak index 0 | All-zero correlation → argmax returns first index; meaningless |
| VCD size | sim_out/phase3_sim.vcd grows to ~200 MB over 105k cycles |
