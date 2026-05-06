# Step 4 — Full RTL Architecture and Module Boundary Specification

You are working inside:

`/home/zealatan/RTL_SYNC`

## Goal

Create the full RTL architecture and module boundary specification for the complete RTL replacement of the C `synchronization()` function.

This step is architecture/specification-only.

Do not implement RTL.
Do not create Verilog/SystemVerilog RTL files.
Do not modify existing RTL, testbenches, or scripts.

Final RTL target:

`ofdm_synchronizer_top.v`

The full synchronizer must eventually implement:

- frame detection
- CP auto-correlation timing
- fractional CFO estimation
- fractional CFO correction
- PSS/SSS symbol extraction
- PSS/SSS FFT
- Meyr integer CFO estimation
- integer CFO correction

Use these existing documents:

- `docs/step1_sync_workspace_audit.md`
- `docs/step2_full_sync_scope_from_receiver_c.md`
- `docs/step3_fixedpoint_spec.md`
- `ai_context/current_status.md`

Known constants and decisions from Step 3:

- `NSC = 256`
- `CP_LEN = 32`
- I/Q format = Q1.15
- AXI-Stream input packing: `s_axis_tdata[15:0] = I`, `s_axis_tdata[31:16] = Q`
- `DATA_WIDTH = 32`
- `ACC_WIDTH = 40`
- `INDEX_WIDTH = 9`
- `NCO_PHASE_WIDTH = 32`
- `PHASE_WIDTH = 16`
- `CORDIC_PHASE_WIDTH = 16`
- Xilinx CORDIC IP v6.0 is preferred
- CORDIC atan2 latency = 15 cycles
- CORDIC sincos/NCO rotation latency = 15 cycles
- Saturation is used everywhere except the NCO phase accumulator, which intentionally wraps
- Existing `axis_complex_mult.v` has a packing/naming conflict; use a wrapper named `complex_mult_iq.v`
- First full architecture should be buffer-then-process, not pure streaming
- PSS/SSS FFT size = 256
- Meyr correlation FFT size = 512

---

## Important prompt backup requirement

Before doing the main task, save this full prompt text into:

- `md_files/04_full_rtl_architecture_prompt.md`

If `md_files/` does not exist, create it.

The saved prompt file must contain this full instruction text, not only a summary.

---

## Tasks

Create a full architecture and module boundary specification.

The output document must cover the following.

---

## 1. Architecture overview

Define the complete high-level architecture for:

`ofdm_synchronizer_top.v`

The architecture should use a buffer-then-process strategy for the first full implementation.

Explain why buffer-then-process is safer than pure streaming for this project.

The top-level pipeline should include:

```text
AXI-Stream IQ input
→ input frame buffer
→ frame detector
→ CP auto-correlation timing estimator
→ fractional CFO estimator
→ fractional CFO correction
→ PSS/SSS symbol extractor
→ 256-point FFT wrapper
→ Meyr integer CFO estimator using 512-point correlation
→ integer CFO correction
→ AXI-Stream corrected IQ output
→ AXI-Lite status/config registers
```
