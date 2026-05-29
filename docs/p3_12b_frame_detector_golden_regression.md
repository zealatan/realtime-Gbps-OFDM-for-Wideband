# P3-12B: Frame Detector Golden Regression

## Summary

Validates the new modular `frame_detector` (P3-12A) through the full
`phase3_sync_top` integration path against the Phase3 golden expected values.

**Result: SANITY_GATE PASS (iverilog) — 7/7 checks passed**

---

## Scripts and Testbenches Used

| Item | Path |
|------|------|
| Runner script | `scripts/run_p3_12b_frame_detector_golden_regression.sh` |
| Testbench | `tb/p3_12b_frame_detector_golden_regression_tb.sv` |
| IQ stimulus | `golden/phase3_iq_stimulus_q15.hex` (704 IQ pairs, Q15 hex) |
| Simulation log | `logs/p3_12b_sim.log` |

---

## Source List (Confirmed)

### Phase2 Legacy (math primitives)
```
rtl/phase2_legacy/complex_mult.v
rtl/phase2_legacy/complex_to_mag.v
rtl/phase2_legacy/delay_sample.v
rtl/phase2_legacy/delayT.v
rtl/phase2_legacy/moving_avg_optimized.v
rtl/phase2_legacy/ram_2port.v
```
Note: `rtl/phase2_legacy/sample_power_sq.v` intentionally excluded — module name
conflicts with the new `rtl/sample_power_sq.v` (P3-12A). Nothing in the actual
compile path instantiates the legacy version.

### RTL modules (production path)
```
rtl/unit_test/and2.v
rtl/unit_test/cp_autocorr_core.v
rtl/unit_test/timing_metric_core.v
rtl/timing_sync_top.v          ← lives at rtl/, NOT unit_test/
rtl/frac_cfo_estimator.v
rtl/timing_frac_cfo_top.v
rtl/iq_frame_buffer.v
rtl/frac_cfo_corrector_top.v
rtl/fft256_dual_symbol_frontend.v
rtl/meyr_term2_ref_rom.v
rtl/meyr_integer_cfo_fft_frontend_top.v
rtl/axis_complex_mult.v
rtl/complex_mult_iq.v
rtl/complex_rotator.v
rtl/cordic_atan2.v
rtl/nco_phase_gen.v
rtl/peak_detector.v
rtl/meyr_integer_cfo_core.v
rtl/meyr_pss_sss_product_gen.v
rtl/meyr_integer_cfo_freq_estimator_top.v
rtl/pss_sss_symbol_extractor.v
rtl/slot_start_controller.v
rtl/sample_power_sq.v          ← P3-12A (combinatorial, DATA_WIDTH/POWER_WIDTH)
rtl/sliding_window_sum.v       ← P3-12A
rtl/frame_detect_fsm.v         ← P3-12A
rtl/frame_detector.v           ← P3-12A (thin wrapper replacing monolithic)
rtl/frac_cfo_frame_corrector_top.v
rtl/phase3_sync_top.v
```

---

## Old Detector Dependency Check

`scripts/run_p3_12b_frame_detector_golden_regression.sh` verifies that
`run_phase3_sync_sim.sh` does NOT reference `unit_test/frame_detector.v`.

`rtl/unit_test/frame_detector.v` is NOT in the production compile path. ✓

---

## Golden Checks and Observed Values

| Check | Description | Expected | Observed | Result |
|-------|-------------|----------|----------|--------|
| C1 | `frame_start_valid` observed | 1 | 1 | PASS |
| C2 | `frame_index` | 41 ±1 | 41 | PASS |
| C3 | `frame_start_valid` pulse | observed | observed | PASS |
| C4 | `slot_start == frame_index + peak_lag` | 64 ±1 | 64 (41+23) | PASS |
| C4b | `slot_start` absolute | 64 ±1 | 64 | PASS |
| C5 | `done` asserted | asserted | @cycle 105325 | PASS |
| C6 | `error_code == 0` | 0 | 0 | PASS |

**7 PASS  0 FAIL**

Simulation completed at cycle 105325 with no timeout.

---

## Simulation Results

```
[TB] @37314 frame_start_valid: index=41
[TB] @38490 slot_start_valid: slot=64
[TB] @105325 DONE: error=0 error_code=0

--- P3-12B: 7 PASS  0 FAIL ---
CI GATE: PASSED
```

---

## Mismatch Diagnosis

No mismatch. The modular frame_detector produces identical golden results
to the previous monolithic version:
- `frame_index = 41` (exact match)
- `peak_lag = 23`
- `slot_start = 64 = 41 + 23` (exact match)

---

## Source List Fix Applied

**Root cause of initial compile failure:** Both `run_p3_12b_frame_detector_golden_regression.sh`
and `run_phase3_sync_sim.sh` referenced 8 files under `rtl/unit_test/` that only exist
in this repo at `rtl/` directly:

```
rtl/unit_test/timing_sync_top.v          → rtl/timing_sync_top.v
rtl/unit_test/frac_cfo_estimator.v        → rtl/frac_cfo_estimator.v
rtl/unit_test/timing_frac_cfo_top.v       → rtl/timing_frac_cfo_top.v
rtl/unit_test/iq_frame_buffer.v           → rtl/iq_frame_buffer.v
rtl/unit_test/frac_cfo_corrector_top.v    → rtl/frac_cfo_corrector_top.v
rtl/unit_test/fft256_dual_symbol_frontend.v → rtl/fft256_dual_symbol_frontend.v
rtl/unit_test/meyr_term2_ref_rom.v        → rtl/meyr_term2_ref_rom.v
rtl/unit_test/meyr_integer_cfo_fft_frontend_top.v → rtl/meyr_integer_cfo_fft_frontend_top.v
```

iverilog exits 0 on missing files but silently drops the modules, producing a partial
VVP with only 10 of 37 modules compiled. The TB and most RTL were absent from the
compiled object. Fixed in both scripts.

---

## Remaining Risks

1. **CI_GATE official status requires xsim (Vivado).** The SANITY_GATE run here used
   iverilog which has known differences from Xilinx xsim (bit-width inference, X-prop,
   SystemVerilog coverage).

2. **IQ stimulus is 704 samples** (shorter than MAX_IQ=65536). The `$readmemh` warning
   is benign — uninitialized entries are never accessed because `done` asserts before
   the stream exhausts.

3. **The `frac_cfo_estimator` and downstream CFO correction stages** are present in the
   compile path but their outputs are not checked by this testbench. Only the
   frame_detector path (C1-C4) is exercised here.

---

## Recommended Next Step

Run under Vivado xsim for official CI_GATE closure:
```bash
./scripts/run_p3_12b_frame_detector_golden_regression.sh --sim xsim
```
