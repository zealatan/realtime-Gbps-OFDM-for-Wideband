# P3-24D: Source List Unification

**Gate:** `SOURCE_UNIFICATION_GATE: PASS`

## Summary

All production simulation scripts now draw their DUT RTL from a single canonical file list at `scripts/phase3_dut_filelist.f`. No production script references `rtl/phase2_legacy/`, `rtl/unit_test/`, or bare `rtl/*.v` DUT files.

## Problem

20 simulation scripts each maintained their own copy of the DUT compile list, mixing three stale source trees:

| Old tree | Files | Status |
|---|---|---|
| `rtl/phase2_legacy/` | complex_mult, delay_sample, delayT, complex_to_mag, moving_avg_optimized, ram_2port | Superseded by `rtl/DUT/` |
| `rtl/unit_test/` | and2, cp_autocorr_core, timing_metric_core | Do not exist; cp_autocorr_core replaced by streaming_cp_autocorr |
| bare `rtl/*.v` | timing_sync_top, frac_cfo_estimator, timing_frac_cfo_top, … (28 files) | Superseded by `rtl/DUT/` |

The old lists also included `meyr_term2_ref_rom.v` and `axis_complex_mult.v`, which do not exist and are not needed.

## Solution

### `scripts/phase3_dut_filelist.f`

Single source of truth: 35 files, all from `rtl/DUT/`, ordered by dependency depth (primitives → sub-blocks → hierarchy → top-level).

Usage in scripts:

```bash
FILELIST="${ROOT}/scripts/phase3_dut_filelist.f"
mapfile -t DUT_SRCS < <(grep -v '^#' "${FILELIST}" | grep -v '^[[:space:]]*$' | sed "s|^|${ROOT}/|")
# Then: iverilog ... "${DUT_SRCS[@]}" "${TB_SRC}"
#   or: xvlog --nolog -sv "${DUT_SRCS[@]}" "${TB_SRC}"
```

### Scripts patched (20)

| Script | Change |
|---|---|
| run_phase3_sync_sim.sh | LEGACY/UNIT_TEST/RTL_SRCS → FILELIST/DUT_SRCS |
| run_phase3_sync_xsim.sh | ALL_VERILOG_SRCS → DUT_SRCS |
| run_p3_04_phase3_sync_top_compile.sh | RTL_FILES → DUT_SRCS |
| run_p3_09_integer_cfo_sweep.sh | FFT_SRC path fixed; LEGACY/UNIT_TEST/RTL_SRCS → DUT_SRCS |
| run_p3_12b_frame_detector_golden_regression.sh | LEGACY/UNIT_TEST/RTL_SRCS → DUT_SRCS; audit paths updated to rtl/DUT/ |
| run_p3_14a_axi_dma_wrapper_smoke.sh | LEGACY/UNIT_TEST/RTL_SRCS → DUT_SRCS |
| run_p3_14b_dma_replay.sh | LEGACY/UNIT_TEST/RTL_SRCS → DUT_SRCS |
| run_session_A_p3_12c_full_phase3_regression.sh | LEGACY/UNIT_TEST/RTL_SRCS → DUT_SRCS; audit paths updated |
| run_session_C_p3_14c_dma_replay_golden_compare.sh | LEGACY/UNIT_TEST/RTL_SRCS → DUT_SRCS |
| run_session_C2_p3_14d_replay_hardening.sh | LEGACY/UNIT_TEST/RTL_SRCS → DUT_SRCS |
| run_session_C3_p3_20a_axi_stress.sh | LEGACY/UNIT_TEST/RTL_SRCS → DUT_SRCS |
| run_session_C4_p3_20b_axi_soak.sh | LEGACY/UNIT_TEST/RTL_SRCS → DUT_SRCS |
| run_session_D_p3_15a_full_c_golden_equivalence.sh | LEGACY/UNIT_TEST/RTL_SRCS → DUT_SRCS |
| run_session_D3_p3_15c_equiv_robustness.sh | LEGACY/UNIT_TEST/RTL_SRCS → DUT_SRCS |
| run_session_D4_p3_15d_regression.sh | LEGACY/UNIT_TEST/RTL_SRCS → DUT_SRCS |
| run_session_E_p3_16a_full_end_to_end_phase3.sh | LEGACY/UNIT_TEST/RTL_SRCS → DUT_SRCS |
| run_session_I_p3_20a_axi_backpressure_stress.sh | LEGACY/UNIT_TEST/RTL_SRCS → DUT_SRCS |
| run_session_J_p3_21a_cfo_coverage.sh | J2/J3 LEGACY/UNIT_TEST/RTL_SRCS → DUT_SRCS; J1_RTL_SRCS untouched |
| run_session_K_p3_22a_channel_robustness.sh | LEGACY/UNIT_TEST/RTL_SRCS → DUT_SRCS |
| run_session_L_p3_23a_stress.sh | LEGACY/UNIT_TEST/RTL_SRCS → DUT_SRCS |

### Scripts intentionally unchanged

| Script | Reason |
|---|---|
| run_p3_24a_cp_autocorr_restore.sh | Already used DUT_DIR=rtl/DUT correctly |
| run_p3_02_reference_style_frame_detector_sim.sh | Unit test only; uses rtl/phase2_legacy intentionally |
| run_p3_11_real_fft_meyr_dryrun_xsim.sh | Dry-run pre-flight checker; different structure |

## Compile Validation Results

| Test | Result |
|---|---|
| P3-24A (SANITY_CP_AUTOCORR_RESTORE_GATE) | PASS (8/8) |
| Session E (INTEGRATION_GATE) | PASS (8/8) |
| Session D / p3_15a (SANITY_EQUIV_GATE) | PASS |
| Session K (CHANNEL_GATE) | PASS |
| Session L (SANITY_STRESS_GATE) | PASS |
| Session I, C2, C3, C4, D3 | Compile OK |
| Session A, J, p3_04, p3_12b, p3_14a, p3_14b, p3_09 | Compile OK |

Session D4 reports 85/100 pass — pre-existing failures unrelated to this change (randomized equivalence sweep, CFO/slot edge cases).

## Remaining Legacy References

`rtl/unit_test/` references remaining in comments only:

- `run_phase3_sync_sim.sh`, `run_p3_14a_axi_dma_wrapper_smoke.sh`, `run_p3_14b_dma_replay.sh` — comment-only mentions of `cordic_atan2_xilinx_wrapper.v` and `nco_phase_gen_xilinx_wrapper.v` (Xilinx IP stubs, not needed)

These are documentation notes only and do not affect compilation.

## Gate

```
SOURCE_UNIFICATION_GATE: PASS
```

No production script references `rtl/phase2_legacy/`, `rtl/unit_test/`, or stale `rtl/*.v` DUT paths for compilation. All 20 patched scripts compile against `rtl/DUT/` exclusively via `scripts/phase3_dut_filelist.f`.
