# Step 5 — Implement and Verify Reusable `peak_detector.v`

You are working inside:

`/home/zealatan/RTL_SYNC`

## Goal

Implement and verify a reusable peak detector RTL primitive for the full RTL replacement of the C `synchronization()` function.

This is the first RTL implementation step after the architecture/specification steps.

The peak detector will be reused in at least two places:

1. CP auto-correlation timing peak detection
2. Meyr integer CFO correlation peak detection

The module must be generic, deterministic, and easy to reuse.

---

## Context

Use these existing documents:

- `docs/step1_sync_workspace_audit.md`
- `docs/step2_full_sync_scope_from_receiver_c.md`
- `docs/step3_fixedpoint_spec.md`
- `docs/step4_rtl_architecture_spec.md`
- `ai_context/current_status.md`

Known decisions from previous steps:

- Full target: RTL replacement of C `synchronization()`
- Architecture: buffer-then-process
- I/Q format: Q1.15
- `INDEX_WIDTH = 9`, enough for 0..511
- `METRIC_WIDTH` should follow the Step 3 fixed-point spec
- Saturation is used broadly, but the peak detector itself should not modify metric values
- Tie-break rule must be deterministic

---

## Important prompt backup requirement

Before doing the main task, save this full prompt text into:

- `md_files/05_peak_detector_prompt.md`

If `md_files/` does not exist, create it.

The saved prompt file must contain this full instruction text, not only a summary.

---

## RTL module to create

Create:

- `rtl/peak_detector.v`

Do not modify any existing RTL files.

---

## Module purpose

The module scans a sequence of metric values and reports the maximum metric and its index.

It must support:

- configurable metric width
- configurable index width
- configurable maximum sample count
- unsigned metric comparison by default
- deterministic tie-break behavior
- start/done control
- valid-gated metric input
- error reporting for invalid configuration or overflow condition

---

## Required parameters

Use these parameters unless Step 3/Step 4 strongly suggests better values:

```verilog
parameter integer METRIC_WIDTH = 64;
parameter integer INDEX_WIDTH  = 9;
parameter integer COUNT_WIDTH  = 10;
```
