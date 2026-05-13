# Step 36A — Xilinx FFT256 IP Generation and Interface Audit

## Objective

Prepare scripts, documentation, and a wrapper RTL skeleton for the Xilinx FFT256
IP (xfft v9.1) that will replace the Step 34 behavioral placeholder in the Meyr
integer CFO estimator path.

This step does **not** integrate the FFT IP into the full receiver.
It produces auditable Tcl scripts, a stable wrapper interface, and the documentation
needed to execute the IP generation and property audit in Windows Vivado.

---

## Relationship to Step 34

Step 34 (`docs/step34_fft256_frontend_behavioral_integration.md`) validated the
Meyr integer CFO pipeline — PSS/SSS input → FFT frontend → bin pairing → estimator
— using a **bypass placeholder** in `fft256_dual_symbol_frontend.v` (S_COMPUTE
copies input buffers unchanged to output buffers without computing any FFT).

The Step 34 testbench worked around this by injecting **frequency-domain vectors**
as the time-domain input, so the bypass produced the expected estimator inputs.
This confirmed the interface and FSM are correct, but it did not verify a real
time-domain → FFT path.

**Step 36A** addresses the missing production FFT block:

| Step | FFT status |
|------|-----------|
| 34   | Bypass placeholder (buffer copy); behavioral DFT model for unit test only |
| 36A  | Wrapper skeleton + Tcl scripts prepared; actual XCI pending |
| 37+  | Actual XCI integrated; full time-domain → FFT → estimator verified |

---

## Why Production FFT IP Is Needed

The Meyr integer CFO estimator computes:

```
term1[j] = PSS_FFT[j] * conj(SSS_FFT[j])
```

where `PSS_FFT[j]` and `SSS_FFT[j]` are the **frequency-domain** bins of the
PSS and SSS symbols.  Producing correct bins from time-domain input requires a
real 256-point DFT/FFT, not a passthrough copy.

Until a production FFT is integrated, the project can only simulate with
pre-computed or synthetically constructed frequency-domain vectors.

---

## Current Step 34 Behavioral/Frontend Limitation

- `fft256_dual_symbol_frontend.v` S_COMPUTE: 256 parallel NBA copy assignments.
  Takes one clock cycle; produces bin k = time-domain sample k (no frequency transform).
- `fft256_behavioral_model.sv`: simulation-only DFT model (`synthesis translate_off`).
  Used only for T2 (standalone DC bin check).  Not used in the full pipeline.
- The Step 34 testbench (T3–T12) works because frequency-domain test vectors are
  injected as time-domain input.  The bypass then forwards them unchanged.

This limitation means **Step 34 PASS does not validate the time-domain → FFT path**.

---

## Proposed Xilinx FFT256 IP Role

The Xilinx xfft IP (v9.1, pipelined streaming) will replace S_COMPUTE in
`fft256_dual_symbol_frontend.v` (or sit inside `fft256_xilinx_wrapper.v`, which
future Step 37 will connect to the dual-symbol frontend).

Data path:
```
[time-domain samples 16-bit IQ, 256 per symbol]
         |
         v
 fft256_xilinx_wrapper
   |  fft256_xilinx (Xilinx xfft v9.1)
   |  256-point forward FFT, natural order output
         |
         v
[frequency-domain bins 0..255, 16-bit IQ, k=0 DC]
         |
         v
 meyr_integer_cfo_fft_frontend_top
   |  PSS FFT bins buffered
   |  SSS FFT bins paired with PSS bins
         |
         v
 meyr_integer_cfo_freq_estimator_top
         |
         v
 int_cfo / peak_index / peak_score
```

---

## Intended FFT Configuration

| Parameter | Target value | Notes |
|-----------|-------------|-------|
| Transform length | 256 | Fixed for PSS/SSS |
| Transform direction | Forward FFT | FWD_INV=1 |
| Input data format | Fixed-point, signed | Xilinx default |
| Input I/Q width | 16 bits each | IQ_WIDTH=16 |
| Input tdata packing | {Q[15:0], I[15:0]} | 32-bit tdata |
| Output ordering | Natural order | k=0=DC, no fftshift |
| Output I/Q width | 16 bits (TBC) | May grow; verify from XCI |
| Output tdata packing | {Im[15:0], Re[15:0]} | 32-bit tdata (TBC) |
| Phase factor width | 16 (TBC) | Verify from property dump |
| Scaling | Scaled mode | Conservative; avoids overflow |
| Rounding | Convergent rounding | Reduces bias vs truncation |
| Throttle scheme | Realtime | No backpressure stalls |
| Implementation | Pipelined streaming | Best throughput |
| ACLKEN | Disabled | Not needed |
| xk_index (tuser) | Enabled if available | Carries bin index in tuser |
| Interface | AXI4-Stream | Standard |

**Scaling schedule (SCALE_SCH)**:
- For 256-point FFT: 8 stages of butterfly → 8-bit field.
- `0xAA` = `10101010b` → scale by 1/2 at odd stages (conservative).
- Actual schedule to tune based on PSS/SSS signal amplitude.
- Verify against IP documentation after generating XCI.

---

## Tcl Scripts Created

### `scripts/probe_fft256_ip_properties.tcl`

**Purpose**: Run this script first in Windows Vivado.

- Creates a temporary xfft IP instance with no configuration applied.
- Dumps all available properties to `reports/fft256_ip_properties.txt`.
- Dumps CONFIG.* properties only to `reports/fft256_ip_config_summary.txt`.
- Checks which target property names exist in this Vivado version.
- Writes `reports/fft256_ip_property_audit.txt` (YES/NO existence per target key).
- Removes the temporary IP after probing.

Run as:
```tcl
source scripts/probe_fft256_ip_properties.tcl
```

### `scripts/create_fft256_ip.tcl`

**Purpose**: Run after probe confirms correct property names.

- Creates the `fft256_xilinx` IP instance under `ip/fft256_xilinx/`.
- Dumps all properties before and after configuration.
- Applies the intended configuration (transform_length=256, input_width=16,
  output_ordering=natural_order, scaling_options=scaled, etc.).
- Calls `generate_target all` to produce XCI and output products.
- Prints a checklist of next steps.

Run as:
```tcl
source scripts/create_fft256_ip.tcl
```

**STATUS**: PRELIMINARY.  Property names marked with TODO must be verified
by running `probe_fft256_ip_properties.tcl` first.

---

## Expected Xilinx FFT AXI-Stream Interface

Based on xfft v9.1 documentation (verify from generated XCI):

### Input data channel

| Signal | Direction | Width | Notes |
|--------|-----------|-------|-------|
| `s_axis_data_tdata` | in | 32 | `{Q[15:0], I[15:0]}` |
| `s_axis_data_tvalid` | in | 1 | |
| `s_axis_data_tready` | out | 1 | Backpressure from IP |
| `s_axis_data_tlast` | in | 1 | Assert with sample 255 |

### Configuration channel

| Signal | Direction | Width | Notes |
|--------|-----------|-------|-------|
| `s_axis_config_tdata` | in | 9+ | `{SCALE_SCH[7:0], FWD_INV[0]}` |
| `s_axis_config_tvalid` | in | 1 | Drive before/with first sample |
| `s_axis_config_tready` | out | 1 | IP accepts config |

Config data bit layout (xfft v9.1 default — verify from XCI):
- Bit 0: FWD_INV (1 = forward FFT)
- Bits 8:1: SCALE_SCH (scaling schedule, 2 bits per stage, 8 stages for N=256)

### Output data channel

| Signal | Direction | Width | Notes |
|--------|-----------|-------|-------|
| `m_axis_data_tdata` | out | 32 | `{Im[15:0], Re[15:0]}` |
| `m_axis_data_tvalid` | out | 1 | |
| `m_axis_data_tready` | in | 1 | Consumer backpressure |
| `m_axis_data_tlast` | out | 1 | Asserted with bin 255 |
| `m_axis_data_tuser` | out | 9 | Bin index (xk_index) |

### Status channel

| Signal | Direction | Width | Notes |
|--------|-----------|-------|-------|
| `m_axis_status_tdata` | out | 8 | Overflow flags per stage |
| `m_axis_status_tvalid` | out | 1 | Valid with status data |

### Event outputs

| Signal | Meaning |
|--------|---------|
| `event_frame_started` | FFT frame started (first sample accepted) |
| `event_tlast_unexpected` | tlast received before expected sample count |
| `event_tlast_missing` | tlast not received at expected sample count |
| `event_data_in_channel_halt` | Input data channel stalled |
| `event_data_out_channel_halt` | Output data channel stalled |
| `event_status_channel_halt` | Status channel stalled |

---

## Configuration Channel Notes

The Xilinx FFT IP requires the configuration channel to be driven before or
concurrently with the first data sample of each frame.

In `fft256_xilinx_wrapper.v`, the config data is a static constant:
```verilog
localparam [8:0] CFG_DATA = {8'hAA, 1'b1};  // FWD=1, SCALE_SCH=0xAA
```

The production instantiation (Step 37) must determine whether to:
- Drive `s_axis_config_tvalid=1` continuously (Realtime mode), or
- Pulse `s_axis_config_tvalid=1` once per frame (Non-realtime mode).

Verify from the XCI configuration and the IP reference guide.

---

## Output Bin Order Audit Plan

After actual IP generation (Step 37), verify natural order with:

**Test A**: Single tone at k=5 (positive frequency)
- Input: `x[n] = cos(2π·5·n/256) + j·sin(2π·5·n/256)` for n=0..255
- Expected output: peak at bin k=5, all other bins near zero

**Test B**: Single tone at k=252 (= −4 in natural order)
- Input: `x[n] = cos(2π·252·n/256) + j·sin(2π·252·n/256)`
- Expected output: peak at bin k=252

Bin convention without fftshift:
```
k=0       DC
k=1..127  positive frequencies
k=128..255 negative frequencies (k=252 = freq -4)
```

---

## Scaling and Width Audit Plan

1. Run IP with unit-amplitude single-tone input (`|x[n]| = 1.0`).
2. Check output bin amplitude at the tone bin.
3. For scaled mode: expected output amplitude ≈ N/2^(number_of_scaled_stages).
4. Confirm no overflow flags in `m_axis_status_tdata`.
5. Adjust SCALE_SCH if overflow is observed.

Output width: the Xilinx FFT IP may output more bits than the input to preserve
precision (e.g., 24-bit or 32-bit output for 16-bit input).  Confirm from XCI
and update `FFT_OUT_WIDTH` in `fft256_xilinx_wrapper.v` accordingly.

---

## Latency and Event Signal Audit Plan

1. Count clocks from `s_axis_data_tvalid[0]` (first sample accepted) to
   `m_axis_data_tvalid[0]` (first bin valid).
2. Confirm bin order: first output bin should be k=0 (DC) for natural order.
3. Confirm `m_axis_data_tlast` asserted with bin k=255.
4. Monitor `event_frame_started` — should pulse when first sample is accepted.
5. Confirm `event_tlast_unexpected/missing` remain 0 under correct frame driving.

---

## Wrapper Interface (`fft256_xilinx_wrapper`)

File: `rtl/fft256_xilinx_wrapper.v`

The wrapper provides a simplified AXI4-Stream interface hiding vendor IP details:

```verilog
module fft256_xilinx_wrapper #(
    parameter integer FFT_LEN             = 256,
    parameter integer IQ_WIDTH            = 16,
    parameter integer FFT_OUT_WIDTH       = 16,
    parameter integer USE_BEHAVIORAL_STUB = 1
)(
    input  wire        aclk, aresetn, start,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire [31:0] s_axis_tdata,
    input  wire        s_axis_tlast,
    output wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    output wire [31:0] m_axis_tdata,
    output wire        m_axis_tlast,
    output wire        busy, done, error,
    output wire        event_frame_started, event_tlast_unexpected,
                       event_tlast_missing, event_data_in_channel_halt,
                       event_data_out_channel_halt, event_status_channel_halt
);
```

**Mapping to Step 34 frontend interface**:

The Step 34 `fft256_dual_symbol_frontend` uses a custom interface with
`s_symbol_sel`, `s_index`, `s_i`, `s_q` signals.  The wrapper uses a flat
AXI4-Stream tdata bus `{Q[15:0], I[15:0]}`.  Future Step 37 will implement a
bridge module connecting both.  The wrapper does not directly replace the Step 34
frontend module in this step.

**USE_BEHAVIORAL_STUB=1** (compile-only passthrough):
- `s_axis_tready` = `m_axis_tready`
- `m_axis_tvalid` = `s_axis_tvalid`
- `m_axis_tdata`  = `{16'b0, s_axis_tdata[15:0]}` (I only, Q=0)
- `m_axis_tlast`  = `s_axis_tlast`
- All event outputs = 0
- NOT an FFT — print warning in simulation

**USE_BEHAVIORAL_STUB=0** (production TODO):
- All outputs held to 0 / s_axis_tready=0 pending IP instantiation.
- Contains fully commented TODO block for xfft instantiation.

---

## What Was Run in WSL (Step 36A)

- File inspection: `rtl/fft256_dual_symbol_frontend.v`, `rtl/meyr_integer_cfo_fft_frontend_top.v`
- Script inspection: existing Tcl scripts and sim run scripts
- Search for FFT/IP references across the codebase
- Created all files listed below
- Did **not** run Vivado (no license check performed; not required for this step)
- Did **not** generate any `.xci` file
- Did **not** run stub simulation (Vivado xsim may be available; run manually if needed)

---

## What Must Be Run in Windows Vivado

To complete the IP generation audit:

```
1. Open Vivado 2022.2.

2. Run the property probe script:
     source scripts/probe_fft256_ip_properties.tcl

3. Inspect generated reports:
     reports/fft256_ip_versions.txt
     reports/fft256_ip_properties.txt
     reports/fft256_ip_config_summary.txt
     reports/fft256_ip_property_audit.txt

4. Verify property names in reports/fft256_ip_property_audit.txt:
     Check YES/NO for each target CONFIG.* name.
     Update scripts/create_fft256_ip.tcl with correct names if needed.

5. Run the IP creation script:
     source scripts/create_fft256_ip.tcl

6. Confirm XCI was generated:
     ip/fft256_xilinx/fft256_xilinx.xci  (or similar path)

7. Copy/save the following and commit or report back:
     ip/fft256_xilinx/fft256_xilinx.xci
     ip/fft256_xilinx/*_inst.v           (instantiation template)
     reports/fft256_ip_properties.txt
     reports/fft256_ip_config_summary.txt
     reports/fft256_ip_property_audit.txt
     reports/fft256_ip_config_summary.txt (post-configuration)
     reports/fft256_ip_generation.log     (if generated)

8. Note from the XCI or the instantiation template:
     - Exact port names (especially m_axis_data_tdata packing)
     - Pipeline latency (clocks from first input to first output)
     - Config channel handshake requirements
     - Output data width

9. Report any Tcl errors back into the project.
```

**These steps have NOT been run.  Status: pending Windows Vivado execution.**

---

## Files Expected From Actual IP Generation

After running `scripts/create_fft256_ip.tcl` in Vivado:

```
ip/fft256_xilinx/
  fft256_xilinx.xci                 — IP configuration
  fft256_xilinx.v                   — Synthesis stub (may be auto-generated)
  fft256_xilinx_sim_netlist.v       — Simulation model
  fft256_xilinx_inst.v              — Instantiation template (port reference)
  *.xdc                             — IP constraints

reports/
  fft256_ip_versions.txt
  fft256_ip_properties.txt
  fft256_ip_config_summary.txt
  fft256_ip_property_audit.txt
  fft256_ip_properties_raw.txt      (pre-config)
```

---

## What Should Be Committed to Git

**Commit in Step 36A** (preparation scripts and documentation):
- `md_files/36A_fft256_xilinx_ip_audit_prompt.md`
- `scripts/create_fft256_ip.tcl`
- `scripts/probe_fft256_ip_properties.tcl`
- `rtl/fft256_xilinx_wrapper.v`
- `docs/step36A_fft256_xilinx_ip_audit.md`
- `tb/fft256_xilinx_wrapper_stub_tb.sv`
- `scripts/run_fft256_xilinx_wrapper_stub_sim.sh`

**Commit in Step 37** (after actual IP generation):
- `ip/fft256_xilinx/fft256_xilinx.xci`
- `reports/fft256_ip_properties.txt`
- `reports/fft256_ip_config_summary.txt`
- Updated `rtl/fft256_xilinx_wrapper.v` (USE_BEHAVIORAL_STUB=0 block with real instantiation)

Do **not** commit large IP output products (`*_sim_netlist.v`, large
implementation files) unless the project policy requires them.  The XCI is
sufficient to regenerate output products in any compatible Vivado installation.

---

## Known Limitations

1. **Actual Xilinx FFT XCI not generated in Step 36A.**
   All Tcl scripts are PRELIMINARY and require Windows Vivado execution.
   Property names in `create_fft256_ip.tcl` are based on xfft v9.1 documentation
   and must be verified with `probe_fft256_ip_properties.tcl`.

2. **Property names require `report_property` confirmation.**
   CONFIG.* key names differ between Vivado versions.  The `probe` script
   generates `reports/fft256_ip_property_audit.txt` to resolve this.

3. **No full receiver integration in Step 36A.**
   `fft256_xilinx_wrapper.v` is not connected to `meyr_integer_cfo_fft_frontend_top.v`
   or `fft256_dual_symbol_frontend.v` in this step.

4. **No board validation in Step 36A.**
   No bitstream generated.  No UART/COM port test.  ZCU102 board not modified.

5. **Step 34 behavioral FFT/bypass remains the verified simulation path.**
   Until Step 37 integrates and validates the actual Xilinx FFT IP, the Step 34
   tests (bypass + frequency-domain injection) remain the CI-validated path.

6. **Scaling and output width pending confirmation.**
   `FFT_OUT_WIDTH=16` in the wrapper is a placeholder.  The Xilinx FFT IP may
   produce wider output (e.g., 24-bit or 32-bit).  Verify from XCI.

7. **Config channel handshake behavior TBD.**
   Whether the IP requires a one-shot or persistent config drive depends on the
   `throttle_scheme` setting.  Verify from XCI and IP reference guide.

8. **Stub simulation run status: pending.**
   Script `run_fft256_xilinx_wrapper_stub_sim.sh` is ready but not yet executed.
   Run manually: `bash scripts/run_fft256_xilinx_wrapper_stub_sim.sh`

---

## Next Steps

1. **Immediate (Windows Vivado)**:
   - Run `scripts/probe_fft256_ip_properties.tcl` — dump all xfft properties.
   - Run `scripts/create_fft256_ip.tcl` — generate `ip/fft256_xilinx/fft256_xilinx.xci`.
   - Commit reports and XCI.

2. **Step 36A follow-up (WSL)**:
   - Run `bash scripts/run_fft256_xilinx_wrapper_stub_sim.sh` — verify stub compile.

3. **Step 37 — FFT256 Standalone Wrapper Simulation**:
   - Instantiate `fft256_xilinx` in `rtl/fft256_xilinx_wrapper.v` (USE_BEHAVIORAL_STUB=0).
   - Write a correctness testbench: single-tone inputs, verify output bin peak location.
   - Validate: tone at k=5 → peak at bin 5; tone at k=252 → peak at bin 252.
   - Confirm latency, output width, tlast alignment.

4. **Step 38+ — Full Integration**:
   - Connect `fft256_xilinx_wrapper` to `fft256_dual_symbol_frontend` (bridge module).
   - Re-run Meyr estimator regression with real time-domain → FFT path.
   - Replace Step 34 bypass placeholder with production FFT path.
   - Board integration and UART validation.
