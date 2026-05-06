# Step 10 — Implement and Verify `timing_metric_core.v`

You are working inside:

`/home/zealatan/RTL_SYNC`

## Goal

Implement and verify `timing_metric_core.v`, the RTL timing metric generator used after CP auto-correlation.

This module consumes the output of `cp_autocorr_core.v`:

- `corr_i`
- `corr_q`
- `energy`
- `result_index`

and generates a non-negative timing metric suitable for `peak_detector.v`.

This module corresponds to the metric-generation part inside the C reference function:

`VanDeBeekAutoCorrelation()`

This is part of the full RTL replacement of the C `synchronization()` function.

---

## Context

Use these existing documents:

- `docs/step4_rtl_architecture_spec.md` (section 4.4)
- `ai_context/current_status.md`

Known decisions from previous steps:

- Full target: RTL replacement of C `synchronization()`
- Architecture: buffer-then-process
- I/Q format: Q1.15
- `NSC = 256`
- `CP_LEN = 32`
- `ACC_WIDTH = 40`
- `METRIC_WIDTH = 32`
- Internal module `done` signals are 1-cycle pulses
- Arithmetic should use wide enough internal intermediates
- Do not implement peak detection in this step
- Do not modify `cp_autocorr_core.v` or `peak_detector.v`

## RTL module to create

Create:

- `rtl/timing_metric_core.v`

Do not modify existing RTL files.

## Module purpose

The module converts CP auto-correlation results into an unsigned metric stream.

For each lag m in [0, num_lags-1]:

```
M[m] = 2 * |P[m]| - E[m]
```

where |P[m]| is the magnitude of the complex autocorrelation, approximated as:

```
|P| ≈ max(|I|, |Q|) + (min >> 2) + (min >> 3)
```

(alpha-max + beta-min, coefficient 3/8 = 1/4 + 1/8)

## Interface (from step4_rtl_architecture_spec.md §4.4)

```
Parameters: NSC=256, METRIC_WIDTH=32, ACC_WIDTH=40

Inputs:
  aclk, aresetn
  start            (1-clock pulse)
  num_lags [8:0]   (number of lags to compute; latched on start)
  result_autocorr_I [31:0] signed
  result_autocorr_Q [31:0] signed
  result_norm_E     [31:0] unsigned

Outputs:
  result_rd_addr [8:0]       (drives cp_autocorr_core result RAM)
  metric_out [METRIC_WIDTH-1:0]
  metric_valid
  metric_last
  done, busy
```

[Prompt was cut off at this point — remainder reconstructed from spec]
