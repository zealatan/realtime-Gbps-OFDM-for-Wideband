# Step 18 — Implement and Verify `timing_frac_cfo_top.v`

You are working inside:

`/home/zealatan/RTL_SYNC`

## Goal

Implement and verify `timing_frac_cfo_top.v`, the integrated timing synchronization plus fractional CFO estimation block.

This module integrates:

- `timing_sync_top.v`
- `frac_cfo_estimator.v`

It corresponds to this C reference flow inside `synchronization()`:

```c
peakIndexAuto = VanDeBeekAutoCorrelation(...);

fracfreqOffset = -atan2(autoCorrOutQ[peakIndexAuto],
                        autoCorrOutI[peakIndexAuto]) / (2 * PI);
```

## Context

Use these existing documents:

- `docs/step3_fixedpoint_spec.md`
- `docs/step4_rtl_architecture_spec.md`
- `docs/step9_cp_autocorr_core.md`
- `docs/step10_timing_metric_core.md`
- `docs/step12_frac_cfo_estimator.md`
- `ai_context/current_status.md`

Use these existing RTL modules:

- `rtl/timing_sync_top.v`
- `rtl/frac_cfo_estimator.v`
- `rtl/cordic_atan2.v`
- `rtl/cp_autocorr_core.v`
- `rtl/timing_metric_core.v`
- `rtl/peak_detector.v`
- `rtl/complex_mult_iq.v`
- `rtl/axis_complex_mult.v`

## Important prompt backup requirement

Save this full prompt text into `md_files/18_timing_frac_cfo_top_prompt.md`.
