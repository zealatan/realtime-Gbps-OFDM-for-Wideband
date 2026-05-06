# Step 17 — Implement and Verify `timing_sync_top.v`

You are working inside:

`/home/zealatan/RTL_SYNC`

## Goal

Implement and verify `timing_sync_top.v`, the integrated CP timing synchronization block.

This module integrates:

- `cp_autocorr_core.v`
- `timing_metric_core.v`
- `peak_detector.v`

It corresponds to the full RTL replacement of the C reference function:

`VanDeBeekAutoCorrelation()`

inside the larger C `synchronization()` function.

This step must not implement frame detection, fractional CFO estimation, CFO correction, FFT, or Meyr integer CFO.

---

## Context

Use these existing documents:

- `docs/step1_sync_workspace_audit.md`
- `docs/step2_full_sync_scope_from_receiver_c.md`
- `docs/step3_fixedpoint_spec.md`
- `docs/step4_rtl_architecture_spec.md`
- `docs/step5_peak_detector.md`
- `docs/step6_iq_frame_buffer.md`
- `docs/step7_frame_detector.md`
- `docs/step8_complex_mult_iq.md`
- `docs/step9_cp_autocorr_core.md`
- `docs/step10_timing_metric_core.md`
- `docs/step12_frac_cfo_estimator.md`
- `docs/step16_frac_cfo_corrector_top.md`
- `ai_context/current_status.md`

Use these existing RTL modules:

- `rtl/cp_autocorr_core.v`
- `rtl/timing_metric_core.v`
- `rtl/peak_detector.v`
- `rtl/complex_mult_iq.v`
- `rtl/axis_complex_mult.v`

Known decisions from previous steps:

- Full target: RTL replacement of C `synchronization()`
- Architecture: buffer-then-process
- I/Q format: Q1.15
- Project-wide sample packing convention: `sample[15:0] = I`, `sample[31:16] = Q`
- `NSC = 256`
- `CP_LEN = 32`
- `SEARCH_LEN = 256`
- `DATA_WIDTH = 32`
- `ACC_WIDTH = 40`
- `ENERGY_WIDTH = 40`
- `METRIC_WIDTH = 80`
- `INDEX_WIDTH = 12`
- Internal module `done` signals are 1-cycle pulses
- `peak_detector.v` uses strict `>` comparison, so first peak wins on ties
- `timing_metric_core.v` default metric mode is magnitude-squared
- `cp_autocorr_core.v` uses `complex_mult_iq.v` with `CONJ_B=1`
- `frac_cfo_estimator.v` later requires `peak_corr_i` and `peak_corr_q`

Vivado/SystemVerilog caveats from previous steps:

- Use SystemVerilog-style hex literals such as `32'hF0F0_F0F0`, not C-style `0xF0F0_F0F0`.
- Be careful with output dynamic arrays in tasks; allocate them with `new[n]` before writing.
- Add `-timescale 1ns/1ps` to `xelab` if needed.

---

## Important prompt backup requirement

Before doing the main task, save this full prompt text into:

- `md_files/17_timing_sync_top_prompt.md`

If `md_files/` does not exist, create it.

The saved prompt file must contain this full instruction text, not only a summary.

---

## RTL module to create

Create:

- `rtl/timing_sync_top.v`

Do not modify existing RTL files.

In particular:

- Do not modify `rtl/cp_autocorr_core.v`
- Do not modify `rtl/timing_metric_core.v`
- Do not modify `rtl/peak_detector.v`
- Do not modify `rtl/complex_mult_iq.v`
- Do not modify `rtl/axis_complex_mult.v`

---

## Module purpose

The module performs CP-based timing synchronization over a candidate search window.

It should:

1. start `cp_autocorr_core.v`
2. convert each correlation result into a metric using `timing_metric_core.v`
3. feed metrics into `peak_detector.v`
4. output the final timing peak index and metric
5. also latch the `corr_i`, `corr_q`, and `energy` values associated with the winning peak

The last requirement is critical because fractional CFO estimation later needs:

```text
frac_cfo = -atan2(peak_corr_q, peak_corr_i) / (2*pi)
```
