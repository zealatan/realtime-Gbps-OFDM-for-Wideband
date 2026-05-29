# Session D / P3-15A — Full C Golden Equivalence Plan

## 1. C Reference Asset Discovery

### Authoritative C reference file
`ref/receiver.c` — full radio receiver (requires libiio, fftw3, AD9361 hardware).
Not usable standalone for golden generation.

`scripts/golden_dump.c` — **authoritative standalone golden extractor**.
Re-implements `ref/signal_processing_common.c: synchronization()` Steps 1–3 exactly,
with no external library dependencies. Produces `golden/phase3_golden_values.txt`.
Build: `gcc -O2 -Wall scripts/golden_dump.c -lm -o scripts/golden_dump`

### Existing golden vectors

| File | Status | Contents |
|------|--------|----------|
| `golden/phase3_golden_values.txt` | **Available** | DETECTION_STATUS, FRAME_START, PEAK_INDEX_AUTO, SLOT_START_INDEX, FRAC_CFO_OFFSET, PSS_START, SSS_START, PSS/SSS_SAMPLE_COUNT, INTEGER_CFO_WORD, MEYR_PEAK_INDEX |
| `golden/phase3_iq_stimulus.f32` | **Available** | 704 IQ float32 samples (NSC=256, CP_LEN=32, eps_frac=0.05, k_int=0) |
| `golden/phase3_iq_stimulus.mem` | **Available** | Same as .f32, hex Q15 packed {Q[15:0], I[15:0]} for RTL $readmemh |
| `golden/phase3_iq_stimulus_meta.json` | **Available** | Stimulus parameters and expected values |
| `golden/phase3_iq_stimulus_q15.hex` | **Available** | Same as .mem (alternate format) |
| `golden/phase3_autocorr_full.txt` | **Available** | Full CP autocorrelation sweep (256 lags) |
| `golden/p3_09_sweep/case_k*.mem` | **Available** | Integer CFO sweep stimuli (k=0, ±1, ±2, ±4, ±8) |
| `golden/meyr_reference_debug.json` | **Available** | Meyr estimator debug (DFT-based) |
| `golden/meyr_fft_reference_debug.json` | **Available** | Meyr estimator with FFT frontend |

### Existing RTL result files

| File | Status | Session |
|------|--------|---------|
| `sim_out/rtl_results.txt` | **Available** | A/12C — phase3_sync_top debug probes |
| `sim_out/session_C_p3_14c/rtl_status.txt` | **Available** | C/14C — AXI-Lite register reads |
| `sim_out/session_C_p3_14c/rtl_m_axis_iq.txt` | **Available** | C/14C — 576 M_AXIS IQ samples |
| `sim_out/session_C_p3_14c/rtl_frac_iq.txt` | **Available** | C/14C — frac-corrected stream tap |

### Existing comparison scripts

| Script | Scope |
|--------|-------|
| `scripts/compare_golden_rtl.py` | Phase3_sync_top scalars (Steps 1–4) vs C golden |
| `scripts/compare_p3_09_integer_cfo_sweep.py` | Integer CFO k-sweep results |
| `scripts/compare_session_C_p3_14c_dma_replay_golden.py` | Session C M_AXIS sample comparison |

### Outputs that still need to be generated

| Observable | Status | Required from |
|------------|--------|---------------|
| M_AXIS golden IQ (post-NCO correction) | **MISSING** | Session C (to provide C-model IQ) |
| Real Xilinx FFT Meyr result | **MISSING** | Session B (xsim-only) |
| Sample-exact IQ with non-zero k_int | **MISSING** | Session B/C combined |

---

## 2. Known Value Summary (k_int = 0, eps_frac = +0.05)

| Observable | C Reference | RTL (Session A/12C) | Match |
|------------|-------------|---------------------|-------|
| frame_found | 1 | 1 | PASS |
| frame_index | 41 | 41 | PASS |
| peak_lag | 23 | 23 | PASS |
| slot_start_index | 64 | 64 | PASS |
| frac_cfo_offset | +0.05 | Q15=3276 (≈0.04998) | PASS (1% tol) |
| int_cfo_valid | 1 | 1 | PASS |
| meyr_peak_index | 255 | 255 | PASS |
| int_cfo_est_bins | 0 | 0 | PASS |
| int_cfo_applied | N/A (C) | 1 | RTL only |
| M_AXIS length | N/A (C) | 576 | RTL only |
| M_AXIS tlast_idx | N/A (C) | 575 | RTL only |

---

## 3. Framework Architecture

```
scripts/export_c_reference_phase3_golden.py
    └─► golden/session_D_p3_15a/c_reference_observables.json

tb/session_D_p3_15a_phase3_observable_dump_tb.sv  (iverilog/xsim)
    ├─► sim_out/session_D_p3_15a/rtl_observables.txt
    ├─► sim_out/session_D_p3_15a/rtl_m_axis_iq.txt
    └─► sim_out/session_D_p3_15a/rtl_m_axis_meta.txt

scripts/normalize_rtl_phase3_outputs.py
    └─► sim_out/session_D_p3_15a/rtl_observables.json

scripts/compare_full_phase3_against_c_reference.py
    ├─ golden/session_D_p3_15a/c_reference_observables.json
    ├─ sim_out/session_D_p3_15a/rtl_observables.json
    └─► reports/session_D_p3_15a/equivalence_comparison_result.txt

scripts/run_session_D_p3_15a_full_c_golden_equivalence.sh
    └─► all of the above in sequence
```

---

## 4. Staged Comparison Design

| Stage | Fields compared | Gate behavior |
|-------|-----------------|---------------|
| 0 | File/schema availability | FAIL stops comparison |
| 1 | frame_found, frac_cfo_valid, int_cfo_valid | FAIL/BLOCKED/PASS |
| 2 | frame_index (±1), peak_lag (±1), slot_start_index (±1) | FAIL/PASS |
| 3 | frac_cfo Q1.15 word (1% tol), int_cfo_index (±1), int_cfo_est_bins (exact), int_cfo_applied | FAIL/BLOCKED/PASS |
| 4 | m_axis.length, m_axis.tlast_index | **BLOCKED** (no C M_AXIS) |
| 5 | sample-by-sample IQ (±1 LSB) | **BLOCKED** (no C M_AXIS) |

**Current expected gate:** `EQUIV_GATE: PARTIAL_PASS_BLOCKED`
— Stages 0–3 pass; Stages 4–5 blocked on C M_AXIS golden.

---

## 5. Sign Convention Notes

### Fractional CFO
- **C side:** `FRAC_CFO_OFFSET = atan2(P_Q, P_I) / (2π)` → positive for +eps_frac
- **RTL Q1.15 word:** `word = +offset × 2 × 32768` (same sign as C, verified P3-05C)
- **Tolerance:** `max(|expected| × 1%, 2 LSB)` applied in Q1.15 domain

### Integer CFO
- **C side:** `INTEGER_CFO_WORD = 0` = integer CFO offset in subcarrier bins (0 = no offset)
- **RTL NCO step word:** `step_word = (-k_int) << 24` (from phase3_sync_top.v)
- **Bins from NCO word:** `k_int = -(step_word >> 24)` (arithmetic right shift)
- **Known discrepancy (P3-14C):** AXI-Lite register shows `0xFF000000` for zero-offset stimulus; hierarchical probe shows 0. Investigation deferred to Session B/C.

### M_AXIS IQ packing
- **tdata[15:0]  = I** (in-phase, lower 16 bits)
- **tdata[31:16] = Q** (quadrature, upper 16 bits)

---

## 6. Required Producer-Side Outputs from Sessions B/C

For Stage 4 and Stage 5 to unblock:

### From Session B (real FFT Meyr integration)
- Confirmed Meyr peak index via Xilinx FFT (xsim) for k_int sweep
- Meyr peak index for non-zero k_int cases
- Golden NCO step word convention validation

### From Session C (DMA replay / integer CFO correction)
- C software model IQ output (NCO-corrected, 576 samples) as golden reference
  - Format: one `I Q` pair per line, signed 16-bit values
  - Path convention: `golden/session_D_p3_15a/c_m_axis_iq_golden.txt`
- Confirmation that Python NCO model (compare_session_C_p3_14c.py) bit-exactly matches RTL
- Resolution of AXI-Lite INT_CFO_WORD_AXI vs probe value discrepancy
