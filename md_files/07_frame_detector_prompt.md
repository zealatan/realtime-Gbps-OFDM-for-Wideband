# Step 7 — Implement and Verify `frame_detector.v`

You are working inside:

`/home/zealatan/RTL_SYNC`

## Goal

Implement and verify `frame_detector.v`, the RTL replacement for the C reference function:

`frame_detector()`

This module performs coarse frame detection using energy thresholding.

It is part of the full RTL replacement of the C `synchronization()` function.

---

## Context

Use these existing documents:

- `docs/step1_sync_workspace_audit.md`
- `docs/step2_full_sync_scope_from_receiver_c.md`
- `docs/step3_fixedpoint_spec.md`
- `docs/step4_rtl_architecture_spec.md`
- `docs/step5_peak_detector.md`
- `docs/step6_iq_frame_buffer.md`
- `ai_context/current_status.md`

Known decisions from previous steps:

- Full target: RTL replacement of C `synchronization()`
- Architecture: buffer-then-process
- I/Q format: Q1.15
- AXI-Stream/input packing: `sample[15:0] = I`, `sample[31:16] = Q`
- `DATA_WIDTH = 32`
- `INDEX_WIDTH = 9` or larger if needed
- `NSC = 256`
- `CP_LEN = 32`
- Energy detector window length = 25
- Energy threshold = 40000 in the C reference
- Consecutive hit count = 10
- Saturation is used broadly, but this module may use sufficiently wide arithmetic to avoid overflow

Vivado/SystemVerilog caveats from Step 6:

- Use SystemVerilog-style hex literals such as `32'hF0F0_F0F0`, not C-style `0xF0F0_F0F0`
- Be careful with output dynamic arrays in tasks; allocate them with `new[n]` before writing

---

## Important prompt backup requirement

Before doing the main task, save this full prompt text into:

- `md_files/07_frame_detector_prompt.md`

If `md_files/` does not exist, create it.

The saved prompt file must contain this full instruction text, not only a summary.

---

## RTL module to create

Create:

- `rtl/frame_detector.v`

Do not modify any existing RTL files.

---

## Module purpose

The module scans IQ samples from a random-access frame buffer and detects the approximate start of a frame based on moving-window energy.

It should be designed to read samples from `iq_frame_buffer.v` in later integration.

For this step, implement the detector as a standalone module with a simple read-request/read-response interface.

---

## Required parameters

Use these defaults unless the previous spec strongly suggests better values:

```verilog
parameter integer DATA_WIDTH      = 32;
parameter integer ADDR_WIDTH      = 12;
parameter integer INDEX_WIDTH     = 12;
parameter integer POWER_WIDTH     = 33;
parameter integer ENERGY_WIDTH    = 40;
parameter integer WINDOW_LEN      = 25;
parameter integer HIT_COUNT       = 10;
parameter integer THRESHOLD       = 40000;
```

[Prompt saved — remainder of user message was cut off at this point]
