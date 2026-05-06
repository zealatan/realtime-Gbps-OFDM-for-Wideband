# Step 3 — Fixed-Point and Interface Specification

You are working inside:

`/home/zealatan/RTL_SYNC`

## Goal

Create a fixed-point and interface specification for the full RTL replacement of the C `synchronization()` function.

This step is specification-only.

Do not implement RTL.
Do not create Verilog/SystemVerilog files.
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
- `ai_context/current_status.md`

Known constants from Step 2:

- `NSC = 256`
- `CP_LEN = 32`
- energy detector window length = 25
- energy threshold = 40000
- consecutive hit count = 10
- PSS/SSS FFT size = 256
- Meyr correlation FFT size = 512

---

## Important prompt backup requirement

Before doing the main task, save this full prompt text into:

- `md_files/03_fixed_point_interface_spec_prompt.md`

If `md_files/` does not exist, create it.

The saved prompt file must contain this full instruction text, not only a summary.

---

## Tasks

Create a full fixed-point and interface specification document.

The document must cover the following items.

---

## 1. Global fixed-point parameters

Define recommended values for:

- `DATA_WIDTH`
- `SAMPLE_FRAC_BITS`
- `POWER_WIDTH`
- `PRODUCT_WIDTH`
- `ACC_WIDTH`
- `METRIC_WIDTH`
- `PHASE_WIDTH`
- `CORDIC_PHASE_WIDTH`
- `NCO_PHASE_WIDTH`
- `ROTATOR_COEFF_WIDTH`
- `FFT_DATA_WIDTH`
- `FFT_TWIDDLE_WIDTH`
- `MEYR_ACC_WIDTH`
- `INDEX_WIDTH`
- `AXIS_TDATA_WIDTH`
- `AXIL_DATA_WIDTH`
- `AXIL_ADDR_WIDTH`

For each parameter, explain:

- recommended value
- reason
- affected RTL blocks
- overflow risk

---

## 2. AXI-Stream IQ sample format

Use this baseline input format:

```text
s_axis_tdata[15:0]  = signed I
s_axis_tdata[31:16] = signed Q
```
