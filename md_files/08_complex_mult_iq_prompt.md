# Step 8 — Implement and Verify `complex_mult_iq.v`

You are working inside:

`/home/zealatan/RTL_SYNC`

## Goal

Implement and verify `complex_mult_iq.v`, a wrapper around the existing `axis_complex_mult.v`.

This wrapper adapts the existing complex multiplier to the OFDM synchronizer's I/Q packing convention.

This is required before implementing `cp_autocorr_core.v`.

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
- `ai_context/current_status.md`

Use this existing RTL as the wrapped primitive:

- `rtl/axis_complex_mult.v`

Known decisions from previous steps:

- Full target: RTL replacement of C `synchronization()`
- Architecture: buffer-then-process
- I/Q format: Q1.15
- Project-wide sample packing convention:

```text
sample[15:0]  = I
sample[31:16] = Q
```

[Prompt saved — remainder of user message was cut off at this point]
