# P3-09 — Integer CFO Sweep Verification Prep — Session Archive

**Session role:** Claude-B — P3-09 Integer CFO Sweep Verification Prep Owner  
**Date:** 2026-05-28  
**Status:** Infrastructure created; blocked on real FFT integration for k_int≠0

---

## Full Prompt (verbatim)

```
ROLE
====
Claude-B — P3-09 Integer CFO Sweep Verification Prep Owner

MANDATORY ARCHIVAL RULE
=======================
Before making any changes, create:

md_files/p3_09_integer_cfo_sweep_prep_prompt.md

This archive must contain:
- this full prompt
- your interpretation
- files inspected
- planned modifications
- final summary

CONTEXT
=======
Current status:
- Front-end sync and fractional CFO are passing.
- PSS/SSS extraction is passing.
- P3-08 is being handled by another session and will bring up Meyr backend for integer CFO = 0.
- This session should prepare sweep verification infrastructure but should not modify Meyr RTL or phase3_sync_top.

GOAL
====
Prepare integer CFO sweep verification for future execution after P3-08 is stable.

Target sweep:
k_int = -8, -4, -2, -1, 0, +1, +2, +4, +8

Expected:
meyr_peak_index = 255 + k_int
integer_cfo_estimate = k_int
integer_cfo_word derived from k_int according to existing step-word convention

TASKS
=====
1. Inspect:
   - docs/p3_07_pss_sss_meyr_backend_validation.md
   - scripts/gen_phase3_iq_stimulus.py
   - scripts/compare_golden_rtl.py
   - tb/phase3_sync_reference_compare_tb.sv
   - docs/p3_08_meyr_backend_bringup.md if it exists
   - prior P2 integer CFO docs if available in this workspace

2. Create sweep plan doc:
   docs/p3_09_integer_cfo_sweep_plan.md

3. Create or extend generator skeleton:
   scripts/gen_phase3_integer_cfo_sweep_vectors.py

4. Create compare skeleton:
   scripts/compare_p3_09_integer_cfo_sweep.py

5. Create run script skeleton:
   scripts/run_p3_09_integer_cfo_sweep.sh

6. Create doc:
   docs/p3_09_integer_cfo_sweep_status.md

7. Do not modify production RTL.
```

---

## Interpretation

This session creates the sweep verification infrastructure for the Meyr integer CFO
estimator. P3-08 (handled separately) has already achieved PASS for k_int=0. This
session does NOT run simulations; it builds the scripts, manifest, and documentation
that will be used once P3-08 is fully stable and — crucially — once the real FFT
backend replaces the current bypass stub.

---

## Files Inspected

| File | Key Finding |
|------|-------------|
| `docs/p3_07_pss_sss_meyr_backend_validation.md` | Bypass FFT confirmed; peak=0 without ROM |
| `docs/p3_08_meyr_backend_bringup.md` | P3-08 PASS; ROM derived from time-domain cross-product; INT_CFO=0 peak=255 |
| `scripts/gen_phase3_iq_stimulus.py` | Base IQ generator; QPSK IFFT SEED=0xC0FFEE, EPS_FRAC=0.05, amplitude=3000 |
| `scripts/gen_meyr_reference_roms.py` | ROM derivation from bypass-path time-domain cross-product |
| `scripts/compare_golden_rtl.py` | Checks 0–10; Checks 9+10 are meyr_peak and integer_cfo_word |
| `tb/phase3_sync_reference_compare_tb.sv` | Captures RTL_MEYR_PEAK_INDEX via hierarchy path |
| `rtl/phase3_sync_top.v` | INT_CFO_SHIFT=24, integer_cfo_word = −int_cfo << 24 |
| `rtl/meyr_integer_cfo_core.v` | CENTER=255; int_cfo = peak_index − 255; 9-bit peak_index |
| `rtl/unit_test/fft256_dual_symbol_frontend.v` | Bypass: S_COMPUTE copies TD buffers; string "FFT PLACEHOLDER" |

---

## Critical Architectural Insight: Bypass Path Cannot Test k_int≠0

With the bypass FFT, `fft256_dual_symbol_frontend` copies time-domain samples unchanged.
The Meyr core therefore computes:

```
term1[j] = PSS_td[j] × conj(SSS_td[j])
```

When the frame has integer CFO `k_int` applied:
```
PSS_td_shifted[j] = PSS_td_ref[j] × exp(j·2π·k_int·j/NSC)
SSS_td_shifted[j] = SSS_td_ref[j] × exp(j·2π·k_int·j/NSC)

term1_shifted[j] = PSS_td_shifted[j] × conj(SSS_td_shifted[j])
                 = PSS_td_ref[j] × conj(SSS_td_ref[j])    ← CFO cancels!
                 = term1_ref[j]
```

The integer CFO phase cancels in the cross-product. The correlation peak is always
at lag=255 regardless of k_int. **Real FFT is required for any k_int≠0 test to
produce a meaningful result.**

Note: integer CFO does NOT affect the VanDeBeek autocorrelator either (the lag
`m+k` to `m+k+NSC` difference produces `exp(−j·2π·k_int)=1` for integer k_int),
so frame_start, slot_start, and frac_cfo are unchanged across k_int sweep cases.

---

## Step-Word Convention (from RTL source)

```
NSC       = 256
NSC_LOG2  = 8   ($clog2(NSC))
INT_CFO_SHIFT = 24  (= 32 − NSC_LOG2)
int_cfo   = peak_index − 255      [signed 16-bit]
integer_cfo_word = (−int_cfo) << 24   [signed 32-bit]
               = −k_int × 16777216
```

| k_int | peak_index | int_cfo (s16) | integer_cfo_word (s32) |
|-------|------------|---------------|------------------------|
|    -8 |        247 |            -8 |           +134217728   |
|    -4 |        251 |            -4 |            +67108864   |
|    -2 |        253 |            -2 |            +33554432   |
|    -1 |        254 |            -1 |            +16777216   |
|     0 |        255 |             0 |                    0   |
|    +1 |        256 |            +1 |            -16777216   |
|    +2 |        257 |            +2 |            -33554432   |
|    +4 |        259 |            +4 |            -67108864   |
|    +8 |        263 |            +8 |           -134217728   |

---

## Files Created / Modified

| File | Action |
|------|--------|
| `md_files/p3_09_integer_cfo_sweep_prep_prompt.md` | NEW — this file |
| `docs/p3_09_integer_cfo_sweep_plan.md` | NEW — test matrix + pass criteria |
| `scripts/gen_phase3_integer_cfo_sweep_vectors.py` | NEW — generator skeleton |
| `scripts/compare_p3_09_integer_cfo_sweep.py` | NEW — compare skeleton |
| `scripts/run_p3_09_integer_cfo_sweep.sh` | NEW — run skeleton (BLOCKED guard) |
| `docs/p3_09_integer_cfo_sweep_status.md` | NEW — status doc |

**No RTL modified. No production golden files overwritten.**

---

## Final Summary

- Sweep infrastructure created for k_int ∈ {-8,-4,-2,-1,0,+1,+2,+4,+8}
- Generator writes per-case .mem stimulus files and manifest.json
- Compare script reads manifest expectations, checks peak/int_cfo/timeout
- Run script guards on P3-08 baseline and bypass-FFT detection; prints BLOCKED when real FFT is absent
- No RTL modified; no fake PASS anywhere
- Blocker: bypass FFT must be replaced with real FFT before k_int≠0 cases can pass
