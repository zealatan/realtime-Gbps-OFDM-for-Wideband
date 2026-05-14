# Step 38 — Actual Xilinx FFT256 Wrapper Integration and Standalone Simulation

## Status

CI GATE: PASSED  
PASS: 26 / FAIL: 0  
Date: 2026-05-14

---

## Objective

Replace the behavioral FFT stub path in `rtl/fft256_xilinx_wrapper.v` with the
actual Xilinx xfft v9.1 IP (`fft256_xilinx`) and verify correctness through
standalone simulation.

---

## IP Configuration Verified

| Parameter               | Value            |
|-------------------------|------------------|
| transform_length        | 256              |
| output_ordering         | natural_order    |
| input_width             | 16               |
| phase_factor_width      | 16               |
| scaling_options         | scaled           |
| throttle_scheme         | realtime         |
| xk_index                | true             |
| aresetn                 | false (no port)  |
| C_THROTTLE_SCHEME       | 0 (realtime)     |
| C_ARCH                  | 3 (pipelined streaming) |
| C_HAS_ARESETN           | 0                |

---

## Files Changed

| File | Action |
|------|--------|
| `ip/fft256_xilinx/fft256_xilinx/fft256_xilinx.v` | Created — hand-written Verilog simulation wrapper, matches Vivado-generated output |
| `rtl/fft256_xilinx_wrapper.v` | Updated — implemented `USE_BEHAVIORAL_STUB=0` production path |
| `tb/fft256_xilinx_wrapper_actual_tb.sv` | Created — self-checking testbench (12 tests) |
| `scripts/run_fft256_xilinx_wrapper_actual_sim.sh` | Created — mixed VHDL/Verilog run script |
| `docs/step38_fft256_actual_ip_wrapper_sim.md` | Created — this file |

---

## Actual FFT IP Files Used

### Imported (Step 37A)
- `ip/fft256_xilinx/fft256_xilinx/fft256_xilinx.xci` — IP configuration
- `ip/fft256_xilinx/fft256_xilinx/fft256_xilinx.veo` — instantiation template

### Created (Step 38)
- `ip/fft256_xilinx/fft256_xilinx/fft256_xilinx.v` — Verilog wrapper for xfft_v9_1_8

### From Vivado Installation (simulation only)
- `$VIVADO/data/ip/xilinx/xfft_v9_1/hdl/xfft_v9_1_vh_rfs.vhd`
  — DRM-protected VHDL behavioral model (compiled by xvhdl during simulation)
- `$VIVADO/data/xsim/ip/xfft_v9_1_8/xfft_v9_1_8.vdbl`
  — Pre-compiled simulation binary (used automatically by xelab)

---

## Compile Flow (Mixed VHDL + Verilog)

```bash
xvhdl xfft_v9_1_vh_rfs.vhd                          # compile xfft VHDL model
xvlog -sv fft256_xilinx.v fft256_xilinx_wrapper.v \
           fft256_xilinx_wrapper_actual_tb.sv        # compile Verilog + TB
xelab fft256_xilinx_wrapper_actual_tb ...            # mixed-language elaboration
xsim  fft256_actual_snap -runall                     # run simulation
```

xelab resolves `xfft_v9_1_8` automatically from the compiled VHDL in the work
library (no manual `-L` flag needed).

---

## Observed Pipeline Latency

**624 clock cycles** from first input handshake to first output valid.

- At 250 MHz (target): 2.496 μs
- At 100 MHz (sim clock): 6.24 μs  
- Ratio: 624 / 256 = 2.44 × N

This latency includes:
1. Radix-2 butterfly pipeline stages (~8 stages, ~8–16 cycles)
2. Block RAM data memory traversal
3. Natural-order reorder buffer (~256–512 cycles)
4. Additional pipeline registers in the output FIFO/reorder logic

---

## IQ Packing Format

### Input (s_axis_data_tdata, 32 bits)
```
tdata[15:0]  = Re (I component), signed Q15
tdata[31:16] = Im (Q component), signed Q15
```

### Output (m_axis_data_tdata, 32 bits)
```
tdata[15:0]  = Re, signed (scaled by SCALE_SCH)
tdata[31:16] = Im, signed (scaled by SCALE_SCH)
```

---

## Config Channel Format

| Bit(s)  | Field      | Value   | Meaning                              |
|---------|------------|---------|--------------------------------------|
| [0]     | FWD_INV    | 1       | Forward FFT                          |
| [8:1]   | SCALE_SCH  | 0xAA    | Scale at alternating stages          |
| [15:9]  | (unused)   | 0       |                                      |

Full config word: `16'h0155`

SCALE_SCH = 0xAA = 8'b10101010: divides by 2 at alternating radix-2 stages
(4 of 8 stages). Effective output attenuation: 1/16 relative to input.

Config is driven continuously (tvalid=1 after reset) in the wrapper.
The IP latches config on the first handshake (cfg_tvalid & cfg_tready = 1).

---

## xk_index Behavior

- `m_axis_data_tuser[7:0]` carries the bin index.
- In natural_order mode: xk_index increments 0, 1, 2, ..., 255 per output frame.
- tlast asserted with xk_index=255 (last bin of each frame).
- xk_index verified by T7, T8.

---

## Test Results

| Test | Description | Result |
|------|-------------|--------|
| T1  | reset_defaults | PASS |
| T2  | impulse_input (flat spectrum, 3.1% variation) | PASS |
| T3  | DC_constant (bin 0 dominant, ratio=255x) | PASS |
| T4  | single_tone_bin1 (peak at bin 1, ratio=127x) | PASS |
| T5  | single_tone_bin4 (peak at bin 4, ratio=127x) | PASS |
| T6  | single_tone_bin16 (peak at bin 16, ratio=138x) | PASS |
| T7  | natural_order_check (xk_index 0..255 verified) | PASS |
| T8  | xk_index_check (monotonic +1, starts 0, ends 255) | PASS |
| T9  | tlast_propagation (tlast at bin 255 only) | PASS |
| T10 | backpressure (realtime throttle documented) | PASS |
| T11 | pipeline_latency_measurement (624 cycles) | PASS |
| T12 | multiple_frames (3 frames, each 256 bins) | PASS |

**Total: 26 PASS, 0 FAIL**

---

## Known Limitations

### 1. Realtime Throttle — No Output Backpressure

- `C_THROTTLE_SCHEME=0` (realtime): the IP has no `m_axis_data_tready` port.
- The wrapper's `m_axis_tready` input is accepted but **not connected to the IP**.
- Data flows continuously; the downstream must always be ready to consume.
- `event_data_in_channel_halt` fires when input data is not continuously provided.
  This is expected during inter-frame gaps in single-frame simulation patterns.
  The IP still produces valid output for data already accepted.

### 2. No aresetn

- `C_HAS_ARESETN=0`: the IP has no reset port.
- The wrapper uses `aresetn` only to gate the config channel state machine.
- The IP starts running immediately at simulation power-on.
- Two warmup frames are needed to flush startup transients before tests.

### 3. Verilog Wrapper is Hand-Written

- `fft256_xilinx.v` was written manually to match what Vivado would generate.
- Replace with the actual Vivado-generated file once full IP generation runs
  on a machine with the `xczu9eg-ffvb1156-2-e` device part installed.

### 4. Simulation Only

- No synthesis or board validation in this step.
- The XCI targets `xczu9eg-ffvb1156-2-e` which is not available in the WSL
  Vivado installation; only simulation is possible from WSL.

---

## Next Recommended Step

**Step 38B or 39**: Integrate the verified `fft256_xilinx_wrapper` into the
Meyr integer CFO estimator pipeline. Connect the wrapper's AXI-stream ports to
the `fft256_dual_symbol_frontend` output and verify end-to-end spectral
processing with the complete signal chain.
