# Phase 3 RTL Gap Analysis

## 1. Reference Flow vs RTL Status

### Step 1 — frame_detector (energy-based frame start)

| Item               | C Reference           | RTL Status                                              |
|--------------------|-----------------------|---------------------------------------------------------|
| Algorithm          | `frame_detector()`    | `frame_detector` in `rtl/unit_test/frame_detector.v`   |
| Integration        | Called from `synchronization()` | Instantiated in `frac_cfo_frame_corrector_top` |
| Parameters         | wndLen=25, threshold=40000, hits=10 | Parameterized via WINDOW_LEN, THRESHOLD, HIT_COUNT |
| **Status**         |                       | **COMPLETE** — exact C match documented in module header |

### Step 2 — VanDeBeekAutoCorrelation (CP timing sync)

| Item               | C Reference           | RTL Status                                              |
|--------------------|-----------------------|---------------------------------------------------------|
| Algorithm          | `VanDeBeekAutoCorrelation()` + `auto_corr()` | `timing_frac_cfo_top` → `timing_sync_top` → `cp_autocorr_core` |
| Peak selection     | `find_max_index(normalizedValue_2, NSC)` | `timing_metric_core` + peak latch in `timing_sync_top` |
| Output             | `peakIndexAuto`       | `peak_lag` (INDEX_WIDTH=9 bits)                         |
| Integration        | Called from `synchronization()` | Inside `timing_frac_cfo_top`, used in `frac_cfo_frame_corrector_top` |
| **Status**         |                       | **COMPLETE**                                            |

### Step 3 — slotStartIndex computation

| Item               | C Reference           | RTL Status                                              |
|--------------------|-----------------------|---------------------------------------------------------|
| Formula            | `slotStartIndex = frameStart + peakIndexAuto` | `slot_start_r <= frame_index_r + peak_lag` in `frac_cfo_frame_corrector_top.v:443` |
| Exposed as output  | Returned from `synchronization()` | `frame_index` + `peak_lag` exposed on ports; their sum is `slot_start_r` (internal reg) |
| **Status**         |                       | **COMPLETE** internally; **PARTIAL** externally — `slot_start_r` not directly output as a port |

**Gap 3a**: `slot_start_r` is an internal register. Phase 3 downstream modules
(`pss_sss_symbol_extractor`) need to know the slot start. Proposed fix: add
`slot_start` output port to `frac_cfo_frame_corrector_top` or use
`slot_start_controller.v` to reconstitute it from `frame_index + peak_lag`.

### Step 4 — Fractional CFO estimation and correction

| Item               | C Reference           | RTL Status                                              |
|--------------------|-----------------------|---------------------------------------------------------|
| atan2              | `atan2(Q[peak], I[peak]) / 2π` | CORDIC in `frac_cfo_estimator` → `timing_frac_cfo_top` |
| Correction         | `apply_carrier_freq_offset()` from `slotStartIndex` | `frac_cfo_corrector_top` in `frac_cfo_frame_corrector_top`; plays back from `slot_start_r` |
| Output stream      | In-place modification of `rxI/rxQ` | `m_axis_*` AXI-Stream, TOTAL_SAMPLES from `slot_start_r` |
| **Status**         |                       | **COMPLETE** for one symbol (TOTAL_SAMPLES=NSC+CP_LEN=288 default) |

**Gap 4a**: Default `OUTPUT_SAMPLES = NSC+CP_LEN = 288`. Meyr requires
`2*(NSC+CP_LEN) = 576` samples. The parameter must be set to `576` in Phase 3.

### Step 5 — PSS/SSS symbol extraction

| Item               | C Reference           | RTL Status                                              |
|--------------------|-----------------------|---------------------------------------------------------|
| PSS window         | `rxI + slotStartIndex + CP_LEN` | `pss_sss_symbol_extractor` needs `pss_fft_start` input |
| SSS window         | `rxI + slotStartIndex + 2*CP_LEN + NSC` | `pss_sss_symbol_extractor` needs `sss_fft_start` input |
| Source stream      | In-place `rxI/rxQ` array | `m_axis_*` output of `frac_cfo_frame_corrector_top` |
| **Status**         |                       | **PARTIAL** — module exists; needs Phase 3 top wiring  |

**Gap 5a**: `pss_sss_symbol_extractor` is not wired to `frac_cfo_frame_corrector_top`'s
output. A Phase 3 top module must connect them.

**Gap 5b**: Relative to the corrected output stream, the fixed offsets are:
- `pss_fft_start = CP_LEN = 32`
- `sss_fft_start = 2*CP_LEN + NSC = 320`
- `frame_len = 2*(NSC+CP_LEN) = 576`

These are constants, derivable from parameters. `slot_start_controller.v`
provides them as outputs.

### Step 6 — Meyr integer CFO estimation

| Item               | C Reference           | RTL Status                                              |
|--------------------|-----------------------|---------------------------------------------------------|
| PSS FFT            | `fft_without_rearrange()` | `meyr_integer_cfo_fft_frontend_top` (in phase2_legacy) |
| SSS FFT            | same                  | same                                                    |
| term1 = PSS×conj(SSS) | inner loop         | `meyr_pss_sss_product_gen`                              |
| cross-correlation  | `fft_correlation_Meyr()` | `meyr_integer_cfo_core`                              |
| Top integration    | `carrierFreqOffsetEstMeyr()` | `meyr_integer_cfo_freq_estimator_top`           |
| **Status**         |                       | **COMPLETE** — module exists; needs Phase 3 top wiring |

### Step 7 — Integer CFO correction

| Item               | C Reference           | RTL Status                                              |
|--------------------|-----------------------|---------------------------------------------------------|
| Correction         | `apply_carrier_freq_offset(-intCFO * fs/NSC, ...)` from `slotStartIndex` | **MISSING** at Phase 3 level |
| Available blocks   | —                     | `frac_cfo_corrector_top` (reusable, parameterized NCO + rotator) |
| **Status**         |                       | **NOT IMPLEMENTED** — integer CFO correction pass not wired in Phase 3 top |

---

## 2. Excluded Module

`rtl/phase2_integer_cfo_estimator.v` — **excluded from production path**.

This was a standalone unit-test file for prototyping an alternative integer CFO
estimation approach. It does not implement the Meyr algorithm and is not
architecturally connected to the reference flow. It must not appear in any
Phase 3 synthesis or simulation fileset.

---

## 3. Summary of Gaps

| Gap ID | Description                                               | Severity   | Fix                                       |
|--------|-----------------------------------------------------------|------------|-------------------------------------------|
| Gap 3a | `slot_start_r` not exposed as external port               | Medium     | `slot_start_controller.v` reconstructs it |
| Gap 4a | `OUTPUT_SAMPLES` defaults to 288; Meyr needs 576          | High       | Set `OUTPUT_SAMPLES=576` in Phase 3 top   |
| Gap 5a | `pss_sss_symbol_extractor` not wired in Phase 3 top       | High       | Phase 3 top module needed                 |
| Gap 5b | PSS/SSS start addresses not computed from slot context    | Medium     | `slot_start_controller.v` provides these  |
| Gap 6a | Meyr estimator not wired in Phase 3 top                   | High       | Phase 3 top module needed                 |
| Gap 7a | Integer CFO correction pass missing at Phase 3 level      | High       | `frac_cfo_corrector_top` can be reused    |
| Gap 7b | No Phase 3 top-level FSM sequencing all steps             | Critical   | New `phase3_sync_top.v` needed            |

---

## 4. What Is Complete

The following are fully implemented and verified (matching C reference):

1. `frame_detector` — energy-based frame start, exact C algorithm match
2. `timing_frac_cfo_top` — CP autocorr + Van de Beek metric + CORDIC frac CFO
3. `frac_cfo_frame_corrector_top` — frame-buffer FSM, integrates 1+2+frac correction,
   computes `slot_start = frame_index + peak_lag`, outputs corrected IQ stream
4. `pss_sss_symbol_extractor` — PSS/SSS window extractor (standalone, interface correct)
5. `meyr_integer_cfo_freq_estimator_top` — Meyr algorithm (standalone, interface correct)
6. `slot_start_controller` — **new in this step**, latches slot start, provides PSS/SSS offsets

---

## 5. What Remains (Phase 3 Work Items)

| Priority | Item                                                              |
|----------|-------------------------------------------------------------------|
| P0       | `phase3_sync_top.v` — top-level FSM connecting all steps         |
| P0       | Wire `frac_cfo_frame_corrector_top` output to `pss_sss_symbol_extractor` |
| P0       | Wire `meyr_integer_cfo_freq_estimator_top` after PSS/SSS FFTs    |
| P0       | Integer CFO correction: instantiate `frac_cfo_corrector_top` with int_cfo step word |
| P1       | Set `OUTPUT_SAMPLES=576` when instantiating `frac_cfo_frame_corrector_top` |
| P1       | FFT256 instances for PSS and SSS (already have `fft256_xilinx_wrapper.v`) |
| P2       | Simulation testbench for Phase 3 end-to-end flow                  |
| P2       | AXI-Lite register interface for Phase 3 status/config             |
