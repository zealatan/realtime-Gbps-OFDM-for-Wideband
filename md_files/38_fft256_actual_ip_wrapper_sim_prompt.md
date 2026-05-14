# Step 38 — Actual Xilinx FFT256 Wrapper Integration and Standalone Simulation

## Branch

step38_fft256_actual_ip_wrapper_sim

## Status

CI GATE: PASSED — 26 PASS / 0 FAIL (2026-05-14)

## Goal

Replace behavioral FFT stub path with actual Xilinx xfft_v9_1_8 IP and verify
through standalone simulation.

## What Was Done

1. Created `ip/fft256_xilinx/fft256_xilinx/fft256_xilinx.v`:
   - Hand-written Verilog simulation wrapper matching Vivado-generated output
   - Instantiates `xfft_v9_1_8` (VHDL entity from Vivado installation)
   - All generics taken from XCI model_parameters
   - Replace with Vivado-generated file once full IP generation available

2. Updated `rtl/fft256_xilinx_wrapper.v`:
   - Implemented `USE_BEHAVIORAL_STUB=0` production path
   - Preserved stub mode unchanged
   - Drives config channel: FWD_INV=1, SCALE_SCH=0xAA (16'h0155)
   - Exposes `m_axis_tuser` (xk_index) as wrapper output port

3. Created `tb/fft256_xilinx_wrapper_actual_tb.sv`:
   - 12 tests: reset, impulse, DC, 3 single-tone, natural order, xk_index,
     tlast, backpressure, latency, multiple frames
   - Blocking assignments for AXI-S driving (avoids double-handshake)
   - xk_index=0 synchronization for frame-boundary aligned capture
   - 2 warmup frames to prime pipeline

4. Created `scripts/run_fft256_xilinx_wrapper_actual_sim.sh`:
   - Step 1: xvhdl compiles xfft_v9_1_vh_rfs.vhd (DRM-protected, decrypted)
   - Step 2: xvlog compiles Verilog wrapper + RTL + TB
   - Step 3: xelab elaborates mixed-language design
   - Step 4: xsim runs simulation

## Key Observations

- Pipeline latency: **624 clock cycles** (2.44 × N for N=256)
- IQ packing: tdata[15:0]=Re, tdata[31:16]=Im (both input and output)
- xk_index: m_axis_tuser[7:0], 0..255 in natural order
- Config: 16'h0155 — FWD_INV=1 at bit[0], SCALE_SCH=0xAA at bits[8:1]
- Realtime throttle: no m_axis_data_tready on IP output
- event_data_in_channel_halt fires during inter-frame gaps (expected behavior)
  but IP still produces valid output for accepted data

## Known Limitations

- Realtime throttle: no output backpressure (m_tready not connected to IP)
- No aresetn: IP has no reset port (C_HAS_ARESETN=0)
- fft256_xilinx.v is hand-written: replace with Vivado-generated once available
- Simulation only: no synthesis/board validation this step

## Test Results

```
T1  reset_defaults        PASS
T2  impulse_input         PASS  flat spectrum 3.1% variation
T3  DC_constant           PASS  bin0 dominant, ratio=255x
T4  single_tone_bin1      PASS  peak at bin 1, ratio=127x
T5  single_tone_bin4      PASS  peak at bin 4, ratio=127x
T6  single_tone_bin16     PASS  peak at bin 16, ratio=138x
T7  natural_order_check   PASS  xk_index 0..255 verified
T8  xk_index_check        PASS  monotonic +1, starts 0, ends 255
T9  tlast_propagation     PASS  tlast at bin 255 only
T10 backpressure          PASS  no deadlock (limitation documented)
T11 pipeline_latency      PASS  624 cycles measured
T12 multiple_frames       PASS  3 frames × 256 bins each

TOTAL: 26 PASS / 0 FAIL
CI GATE: PASSED
```
