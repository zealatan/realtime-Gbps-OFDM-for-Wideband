# P3-05C — Full RTL Golden Compare Status

**Version:** 1.0  
**Date:** 2026-05-27  
**Status:** CI_GATE PASS

---

## Overview

First full end-to-end RTL-vs-golden comparison for Phase 3. DUT is `phase3_sync_top`
instantiating the complete synchronization chain: frame detection → timing/frac CFO →
slot start → PSS/SSS extraction → Meyr integer CFO estimation.

---

## Simulation Environment

| Item | Value |
|---|---|
| Simulator | Icarus Verilog 11.0 (iverilog + vvp) |
| Command | `bash scripts/run_phase3_sync_sim.sh --sim iverilog` |
| IQ stimulus | `golden/phase3_iq_stimulus.f32` (704 samples, amplitude ~3000, EPS_FRAC=0.05) |
| Threshold | 40,000 (matched to C golden_dump threshold for amplitude-3000 stimulus) |
| Timeout | 2,000,000 cycles |
| Cycles to DONE | 105,321 |

---

## Comparison Results

| Check | Golden | RTL | Delta | Tolerance | Result |
|---|---|---|---|---|---|
| DETECTION_STATUS | 1 | 1 | — | exact | **PASS** |
| frameStart | 41 | 41 | 0 | ±1 sample | **PASS** |
| peakIndex | 23 | 23 | 0 | ±1 sample | **PASS** |
| slotStartIndex | 64 | 64 | 0 | ±1 sample | **PASS** |
| frac CFO | 0.049999990 | 0.049987793 | 0.8 Q15 LSB | 1% or ±2 LSB | **PASS** |
| PSS_START | 32 | 32 | 0 | exact | **PASS** |
| SSS_START | 320 | 320 | 0 | exact | **PASS** |
| Integer CFO word | — | −16777216 | — | informational | INFO |

**Overall: CI_GATE PASS**

---

## Issues Found and Resolved

### Issue 1: Missing module `meyr_pss_sss_product_gen`

`rtl/meyr_pss_sss_product_gen.v` was present but absent from `run_phase3_sync_sim.sh`'s
`RTL_SRCS` array. The module is required by `meyr_integer_cfo_freq_estimator_top`.
Added to compile list.

### Issue 2: iverilog `-sv` flag

iverilog 11 parses `-sv` as `-s v` (set top module to "v"), not as a SystemVerilog mode
flag. The correct flag is `-g2012` alone. Removed `-sv` from the compile command.

### Issue 3: Multi-line string literal in TB

`tb/phase3_sync_reference_compare_tb.sv` had a `$fdisplay` call whose format string was
split across three lines (implicit string concatenation). iverilog does not support this.
Joined into a single-line string.

### Issue 4: THRESHOLD_VAL calibration

TB had `THRESHOLD_VAL = 40,000 × 256 = 10,240,000`, calibrated for full-scale Q1.15
signals. The test stimulus uses integer amplitude ~3000, giving energy_acc ≈ 71M per
25-sample window, while thresh_mult = 256M → frame detection always failed (error=1).

The fix: `THRESHOLD_VAL = 40,000` — the same value as the C golden_dump's threshold,
which is valid because both C and RTL compute the same integer-amplitude energy:
`energy_acc = sum(I_int² + Q_int²) over window_len samples`.

The RTL frame_detector's default `THRESHOLD = 10,240,000` is intended for
full-scale radio signals where the ADC produces values near ±32768.

### Issue 5: Frac CFO sign convention

`compare_golden_rtl.py` was written assuming `RTL_word = −FRAC_CFO_OFFSET × 2 × 32768`,
based on the expectation that the RTL uses the negated atan2 convention.

Simulation showed RTL outputs +3276 for FRAC_CFO_OFFSET = +0.05. The correct
relationship is:
```
RTL_word = +FRAC_CFO_OFFSET × 2 × 32768
```

This is because `frac_cfo_estimator.v`'s `cordic_atan2` receives the autocorrelation
values in the forward product convention (not the conjugated convention used in the C
golden_dump). The sign difference cancels out physically: both represent the same
positive 0.05-subcarrier-spacing CFO.

---

## Files Modified

| File | Change |
|---|---|
| `tb/phase3_sync_reference_compare_tb.sv` | THRESHOLD_VAL 10,240,000 → 40,000; single-line $fdisplay string |
| `scripts/run_phase3_sync_sim.sh` | Added `meyr_pss_sss_product_gen.v`; removed `-sv` from iverilog command |
| `scripts/compare_golden_rtl.py` | Flipped sign in `expected_q15` and `rtl_offset`; updated comment |

---

## Known Caveats

| Caveat | Notes |
|---|---|
| THRESHOLD_VAL = 40,000 in TB | Correct for amplitude-3000 stimulus; not appropriate for full-scale ADC data. For real signals, use the module default (10,240,000) or scale appropriately. |
| Integer CFO = −16,777,216 | This is −2²⁴, which decodes to ≈1 subcarrier bin. No golden reference available; informational only. |
| VCD file large | `sim_out/phase3_sim.vcd` will be large due to full hierarchy dump over 105k cycles. |
| xsim path | For Vivado-enabled hosts, `--sim xsim` still works; meyr_pss_sss_product_gen.v is now in the xvlog source list. |
