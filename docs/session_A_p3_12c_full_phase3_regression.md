# Session A / P3-12C: Full Phase3 Regression Closure

## Summary

Validates the complete `phase3_sync_top` pipeline with the P3-12A modular
`frame_detector` against all known-good golden values.

**Result: SANITY_GATE PASS (iverilog) — 10/10 checks passed**

---

## Source-List Audit

### Audit scope

All Phase3 run scripts were audited for stale `rtl/unit_test/` source paths.
In this repository, 8 modules that earlier scripts incorrectly listed under
`rtl/unit_test/` actually reside directly at `rtl/`:

| Stale path | Correct path |
|---|---|
| `rtl/unit_test/timing_sync_top.v` | `rtl/timing_sync_top.v` |
| `rtl/unit_test/frac_cfo_estimator.v` | `rtl/frac_cfo_estimator.v` |
| `rtl/unit_test/timing_frac_cfo_top.v` | `rtl/timing_frac_cfo_top.v` |
| `rtl/unit_test/iq_frame_buffer.v` | `rtl/iq_frame_buffer.v` |
| `rtl/unit_test/frac_cfo_corrector_top.v` | `rtl/frac_cfo_corrector_top.v` |
| `rtl/unit_test/fft256_dual_symbol_frontend.v` | `rtl/fft256_dual_symbol_frontend.v` |
| `rtl/unit_test/meyr_term2_ref_rom.v` | `rtl/meyr_term2_ref_rom.v` |
| `rtl/unit_test/meyr_integer_cfo_fft_frontend_top.v` | `rtl/meyr_integer_cfo_fft_frontend_top.v` |

Files that legitimately live in `rtl/unit_test/`:
- `and2.v`
- `cp_autocorr_core.v`
- `timing_metric_core.v`

### Scripts fixed

| Script | Fix |
|---|---|
| `scripts/run_phase3_sync_sim.sh` | Fixed in P3-12B |
| `scripts/run_p3_12b_frame_detector_golden_regression.sh` | Fixed in P3-12B |
| `scripts/run_phase3_sync_xsim.sh` | Fixed in P3-12C |
| `scripts/run_p3_09_integer_cfo_sweep.sh` | Fixed in P3-12C |
| `scripts/run_p3_04_phase3_sync_top_compile.sh` | Fixed in P3-12C |
| `scripts/run_p3_14a_axi_dma_wrapper_smoke.sh` | Fixed in P3-12C |
| `scripts/run_p3_13a_real_fft_meyr_dryrun.sh` | Fixed in P3-12C |
| `scripts/run_p3_14b_dma_replay.sh` | Already correct |
| `scripts/run_session_A_p3_12c_full_phase3_regression.sh` | New — correct from creation |

### Legacy `sample_power_sq` exclusion

`rtl/phase2_legacy/sample_power_sq.v` is excluded from all production compile
paths (also fixed in `run_phase3_sync_xsim.sh`, `run_p3_09_integer_cfo_sweep.sh`,
`run_p3_14a_axi_dma_wrapper_smoke.sh`). The legacy module has an incompatible
streaming interface (`IQ_WIDTH`/`OUT_WIDTH` params, registered output) vs the new
P3-12A `sample_power_sq.v` (`DATA_WIDTH`/`POWER_WIDTH` params, combinatorial).

---

## Old Detector Dependency Check

`rtl/unit_test/frame_detector.v` is NOT referenced in any production compile path.

The runner script verifies this explicitly:
```bash
grep -qE "unit_test/frame_detector" run_phase3_sync_sim.sh  → NO MATCH → OK
```

The production path uses only:
```
rtl/sample_power_sq.v    ← P3-12A (combinatorial I²+Q²)
rtl/sliding_window_sum.v ← P3-12A (ring-buffer accumulator)
rtl/frame_detect_fsm.v   ← P3-12A (Case1/Case2 FSM)
rtl/frame_detector.v     ← P3-12A (thin wrapper)
```

---

## Testbench and Runner

| Item | Path |
|---|---|
| Runner | `scripts/run_session_A_p3_12c_full_phase3_regression.sh` |
| Testbench | `tb/session_A_p3_12c_full_phase3_regression_tb.sv` |
| IQ stimulus | `golden/phase3_iq_stimulus_q15.hex` (704 pairs) |
| Compile log | `logs/p3_12c_compile.log` |
| Sim log | `logs/p3_12c_sim.log` |

---

## Checks and Results

| Check | Description | Expected | Observed | Result |
|---|---|---|---|---|
| C1 | `frame_found == 1` | 1 | 1 | PASS |
| C2 | `frame_index` | 41 ±1 | 41 | PASS |
| C3 | `peak_lag` | 23 ±1 | 23 | PASS |
| C4 | `slot_start_index` | 64 ±1 | 64 | PASS |
| C5 | `slot_start == frame_index + peak_lag` | 64 ±1 | 64 (41+23) | PASS |
| C6 | `done` asserted | asserted | @cycle 105325 | PASS |
| C7 | `error_code == 0` | 0 | 0 | PASS |
| C8 | Modular FSM hierarchy probe | asserted | @cycle 4258 | PASS |
| C9 | `slot_start_valid` (PSS/SSS windows computed) | observed | @cycle 38490 | PASS |
| C10 | `integer_cfo_valid` (Meyr pipeline done) | observed | @cycle 105324 | PASS |

**10 PASS  0 FAIL**

### Check C8 detail

`u_dut.u_frac_corr.u_fd.u_fsm.frame_found` was monitored via hierarchical
path access. It fired at cycle 4258, confirming the modular `frame_detect_fsm`
submodule is live in the simulation. If the old monolithic `unit_test/frame_detector.v`
were used, this hierarchy path would not exist and elaboration would fail.

### Check C9 detail

`dbg_slot_start_valid` firing at cycle 38490 proves:
1. `frac_cfo_frame_corrector_top` produced corrected IQ output
2. `slot_start_controller` computed `slot_start = frame_index + peak_lag`
3. PSS/SSS FFT window indices were computed and propagated

### Check C10 detail

`dbg_integer_cfo_valid` firing at cycle 105324 (1 cycle before `done`) proves:
1. `pss_sss_symbol_extractor` extracted PSS and SSS symbols
2. `meyr_integer_cfo_fft_frontend_top` completed the FFT + correlation sequence
3. The full Phase3 pipeline ran to completion without error

---

## Simulation Results

```
[TB] @4258 modular_fsm_frame_found asserted
[TB] @37314 frame_start_valid: index=41
[TB] @37314 peak_valid: peak_lag=23
[TB] @38490 slot_start_valid: slot=64
[TB] @105324 integer_cfo_valid: word=0x00000000
[TB] @105325 DONE: error=0 error_code=0

--- P3-12C: 10 PASS  0 FAIL ---
CI GATE: PASSED

SANITY_GATE: PASS (iverilog)
CI_GATE: BLOCKED_XSIM_UNAVAILABLE
```

---

## Mismatch Diagnosis

No mismatch. All 10 checks passed on first run. The modular frame_detector
produces identical output to the P3-12B result:
- `frame_index = 41` (exact match)
- `peak_lag = 23` (exact match)
- `slot_start = 64` (exact match, = 41 + 23)
- Full pipeline completes in 105326 cycles with no error

---

## Remaining Risks

1. **xsim official gate pending.** iverilog passes are SANITY_GATE only.
   Run `--sim xsim` when Vivado is available for CI_GATE PASS.

2. **Integer CFO word = 0x00000000.** The `fft256_dual_symbol_frontend` is a
   behavioral stub that passes time-domain samples directly. This means the
   `meyr_integer_cfo_fft_frontend_top` receives un-FFT'd data → peak always
   at index 255 (time-domain self-correlation), `int_cfo = 0`. This is a known
   limitation documented in P3-09 and P3-11. It does not affect C1–C10 which
   test pipeline structure, not CFO accuracy.

3. **Tolerance windows are ±1 sample.** The golden values for this stimulus are
   exact (41, 23, 64). Future stimuli with different SNR or timing may need
   wider tolerances.

---

## Recommended Next Steps

```bash
# Official CI_GATE when Vivado available:
./scripts/run_session_A_p3_12c_full_phase3_regression.sh --sim xsim

# Full Phase3 golden compare (P3-05C successor):
./scripts/run_phase3_sync_sim.sh --sim iverilog

# Integer CFO real FFT integration (P3-11/P3-13):
# Replace fft256_dual_symbol_frontend stub with real 256-pt FFT
```
