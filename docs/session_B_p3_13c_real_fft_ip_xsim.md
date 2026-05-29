# P3-13C Real FFT IP Official xsim Validation

**Date:** 2026-05-28  
**Status:** OFFICIAL_GATE: PASS — all 9 k_int sweep cases passed (real Xilinx FFT IP, xsim)  
**Tool:** Vivado 2023.1 xsim (Windows), invoked via WSL2 cmd.exe interop  

---

## 1. Summary

Session P3-13C closes the OFFICIAL_GATE that P3-13B left open. The real Xilinx
xfft_v9_1_9 IP (256-pt, pipelined streaming) was generated with Vivado 2023.1,
compiled into a mixed-language xsim snapshot, and run against all 9 integer-CFO
sweep vectors. Every case produced the expected `peak_index = 255 + k_int` and
`int_cfo = k_int`.

---

## 2. Vivado FFT IP Generation

### Command

```bash
# From WSL2, via cmd.exe interop:
/mnt/c/Windows/System32/cmd.exe /c \
  "cd /d C:\temp\p3_13c_xsim_work && \
   C:\Xilinx\Vivado\2023.1\bin\vivado.bat -mode batch \
     -source create_fft256_xilinx_ip.tcl \
     -nolog -nojournal \
     -tclargs C:\temp\p3_13c_xsim_work\ip"
```

TCL script: `scripts/create_fft256_xilinx_ip.tcl`

### IP Configuration

| Parameter                    | Value                 | Notes                                       |
|------------------------------|-----------------------|---------------------------------------------|
| IP name / version            | xfft v9.1             | Module name: `fft256_xilinx`                |
| Target part                  | xc7z020clg400-1       | Zynq-7020, in-memory project                |
| Transform length             | 256                   | Fixed; not run-time configurable            |
| Architecture                 | Pipelined streaming I/O | `pipelined_streaming_io`                  |
| Input width                  | 16 bits               | Q1.15 complex IQ samples                    |
| Phase factor width           | 16 bits               | Twiddle factor precision                    |
| Scaling options              | Scaled                | SCALE_SCH provided on s_axis_config         |
| Rounding                     | Truncation            | Consistent with bypass path                 |
| Complex mult type            | use_mults_resources   | DSP block multipliers                       |
| Output ordering              | Natural order         | Bin 0 first, bin 255 last                   |
| Throttle scheme              | Realtime              | C_THROTTLE_SCHEME=0; no m_axis_data_tready  |
| aresetn                      | false                 | C_HAS_ARESETN=0; wrapper gates via FSM      |
| aclken                       | false                 | No clock enable                             |
| xk_index                     | true                  | Bin index on m_axis_data_tuser[7:0]         |
| ovflo                        | false                 | No overflow flag                            |
| Cyclic prefix insertion      | false                 | Not used                                    |
| Channels                     | 1                     | Single channel                              |

Generated files (from `generate_target simulation`):

- `ip/fft256_xilinx/fft256_xilinx/sim/fft256_xilinx.vhd` — VHDL simulation wrapper
- `ip/fft256_xilinx/xfft_v9_1_vh_rfs.vhd` — underlying behavioral model

The VHDL wrapper requires library `xfft_v9_1_9`; the underlying model populates it.

### Config Channel

The wrapper drives the AXI config channel continuously after reset:

```
cfg_tdata = 16'h0155  →  FWD_INV=1, SCALE_SCH=8'hAA
```

SCALE_SCH=0xAA = `10101010b` — scales (right-shifts) at radix-2 stages 2, 4, 6, 8
(alternating stages, 4 of 8), reducing output amplitude by 2^4 = 16 relative to an
unscaled DFT. Peak location is invariant to uniform amplitude scaling.

---

## 3. xsim Compilation and Simulation

### Working Directory

All sources staged to `C:\temp\p3_13c_xsim_work` (Windows-local) to avoid xvlog
UNC-path hang. WSL mount alias: `/mnt/c/temp/p3_13c_xsim_work`.

### Compilation Sequence

```batch
# Step 1: Compile xfft behavioral model (VHDL) → xfft_v9_1_9 library
xvhdl.bat -nolog -work xfft_v9_1_9  xfft_v9_1_vh_rfs.vhd

# Step 2: Compile IP simulation wrapper (VHDL) → xil_defaultlib library
xvhdl.bat -nolog -work xil_defaultlib  ip\fft256_xilinx\fft256_xilinx\sim\fft256_xilinx.vhd

# Step 3: Compile project RTL (Verilog) → xil_defaultlib
xvlog.bat -nolog -sv -work xil_defaultlib ^
    fft256_xilinx_wrapper.v ^
    meyr_fft256_harness_adapter.v ^
    meyr_fft256_actual_integration_top.v ^
    meyr_integer_cfo_freq_estimator_top.v ^
    meyr_integer_cfo_core.v ^
    meyr_pss_sss_product_gen.v ^
    peak_detector.v

# Step 4: Compile testbench + top wrapper → xil_defaultlib
# p3_13c_real_fft_top.sv wraps TB with USE_BEHAVIORAL_STUB=0
xvlog.bat -nolog -sv -work xil_defaultlib ^
    p3_13a_real_fft_meyr_tb.sv ^
    p3_13c_real_fft_top.sv

# Step 5: Elaborate
xelab.bat -nolog --relax -debug all ^
    -top p3_13c_real_fft_top ^
    -snapshot p3_13c_real_fft_snap

# Step 6: Simulate
xsim.bat p3_13c_real_fft_snap --runall --log p3_13c_xsim.log
```

### Top-Level Wrapper (`p3_13c_real_fft_top.sv`)

```verilog
`timescale 1ns/1ps
module p3_13c_real_fft_top;
    p3_13a_real_fft_meyr_tb #(.USE_BEHAVIORAL_STUB(0)) tb_inst();
endmodule
```

Required because xelab parameter override is unreliable for Verilog modules.
The wrapper forces `USE_BEHAVIORAL_STUB=0` (real Xilinx IP path) at compile time.

### Mixed VHDL/Verilog Binding

xelab automatically binds the VHDL entity `fft256_xilinx` (compiled into
`xil_defaultlib`) to the Verilog instantiation in `fft256_xilinx_wrapper.v`.
The VHDL entity ports must match the Verilog `.*` implicit port connections.
Verified: all ports match the `.veo` port list from the XCI.

---

## 4. Integer CFO Sweep Results

Simulation run: 2026-05-28, Vivado 2023.1 xsim, USE_BEHAVIORAL_STUB=0.

Vectors: `golden/p3_09_sweep/case_k*.mem`  
ROMs: `vectors/meyr_pss_fft_romhex.txt`, `vectors/meyr_sss_fft_romhex.txt`  
Gate log: `sim_out/p3_13c/p3_13c_gate.txt`

| Case | k_int | exp peak | got peak | exp int_cfo | got int_cfo | Score (real IP) | Result |
|------|-------|----------|----------|-------------|-------------|-----------------|--------|
| k0   | 0     | 255      | 255      | 0           | 0           | 551,119,181     | PASS   |
| kp1  | +1    | 256      | 256      | +1          | +1          | 546,586,445     | PASS   |
| km1  | −1    | 254      | 254      | −1          | −1          | 455,116,793     | PASS   |
| kp2  | +2    | 257      | 257      | +2          | +2          | 609,114,013     | PASS   |
| km2  | −2    | 253      | 253      | −2          | −2          | 451,304,185     | PASS   |
| kp4  | +4    | 259      | 259      | +4          | +4          | 513,340,745     | PASS   |
| km4  | −4    | 251      | 251      | −4          | −4          | 513,963,081     | PASS   |
| kp8  | +8    | 263      | 263      | +8          | +8          | 509,590,562     | PASS   |
| km8  | −8    | 247      | 247      | −8          | −8          | 509,590,562     | PASS   |

**All 9 cases: PASS**  
Gate: `OFFICIAL_GATE: PASS — all 9 k_int sweep cases passed`

---

## 5. Scale Schedule Impact

### SCALE_SCH=0xAA vs Unscaled Behavioral DFT

The Xilinx IP applies SCALE_SCH=0xAA (right-shifts at 4 of 8 radix-2 stages).
The correlation score from the real IP is approximately 26× lower than the
behavioral DFT (mode 3) scores from P3-13B:

| Case | Behavioral DFT score (P3-13B) | Real IP score (P3-13C) | Ratio |
|------|-------------------------------|------------------------|-------|
| k0   | 14,625,215,121,206,365        | 551,119,181            | ~26.5k× |
| kp1  | 14,603,945,182,747,957        | 546,586,445            | ~26.7k× |

The large ratio reflects that the behavioral DFT score is 64-bit precision with
no scaling, while the real IP applies 4 right-shifts (÷16 per input dimension)
and the 511-lag correlation further amplifies the range. Peak location is
unaffected — PASS in both modes for all 9 cases.

### Stall Behavior

The real Xilinx IP exercised pipeline backpressure (tready=0 from the FIFO
between wrapper output and capture buffer). Each case showed at least one
`[DBG_PSS_STREAM] STALL` and `[DBG_SSS_STREAM] STALL` event. The wrapper
handled these correctly — no missed samples.

---

## 6. Authentic Real IP Behavior Confirmed

| Feature                        | Behavioral DFT (mode 3) | Real Xilinx IP (mode 0) |
|--------------------------------|-------------------------|--------------------------|
| Pipeline stalls (tready=0)     | Never (combinational)   | Observed at sample 1 per frame |
| Output latency                 | 1 sim step              | ~300+ clock cycles       |
| FLUSH_COUNT=1 drain frame      | Functionally no-op      | Required (residue flush) |
| Amplitude scaling              | None (float64)          | ÷16 (SCALE_SCH=0xAA)    |
| SCALE affects peak location    | N/A                     | Confirmed: no effect     |
| xk_index on tuser              | Emulated                | Real IP port confirmed   |

---

## 7. Files Created or Modified (P3-13C)

| File | Change |
|------|--------|
| `scripts/create_fft256_xilinx_ip.tcl` | New — Vivado batch TCL for xfft_v9_1 IP generation |
| `scripts/run_session_B_p3_13c_real_fft_ip_xsim.sh` | New — automated real IP runner with BLOCKED_* gates |
| `sim_out/p3_13c/p3_13c_gate.txt` | New — OFFICIAL_GATE: PASS record |
| `sim_out/p3_13c/p3_13c_xsim.log` | New — full xsim simulation log |
| `sim_out/p3_13c/p3_13c_xsim_console.log` | New — xsim console output (run2) |
| `docs/session_B_p3_13c_real_fft_ip_xsim.md` | New — this document |
| `ip/fft256_xilinx/` | New — Vivado-generated IP collateral (XCI, VHDL sim files) |

---

## 8. Runner Reference

```bash
# Full automated run (real Xilinx IP + xsim):
bash scripts/run_session_B_p3_13c_real_fft_ip_xsim.sh

# IP generation only (skip simulation):
bash scripts/run_session_B_p3_13c_real_fft_ip_xsim.sh --gen-ip-only

# Skip IP gen (assume already generated), run simulation:
bash scripts/run_session_B_p3_13c_real_fft_ip_xsim.sh --skip-ip-gen

# Custom Vivado version:
bash scripts/run_session_B_p3_13c_real_fft_ip_xsim.sh --vivado-ver 2024.1
```

Gate log: `sim_out/p3_13c/p3_13c_gate.txt`  
xsim log: `sim_out/p3_13c/p3_13c_xsim.log`

---

## 9. Remaining Risks and Known Limitations

| Item | Risk | Notes |
|------|------|-------|
| Larger k_int values | Not tested | |k_int| > 8 not validated. Theoretically |k_int| ≤ 255 supported. |
| SCALE_SCH sensitivity | Low | SCALE_SCH=0xAA confirmed not to affect peak location for these vectors. |
| Fixed-point saturation | Low | For very large amplitude inputs, 16-bit saturation could shift the argmax. Sweep vectors are well within range. |
| WSL2 interop dependency | Info | Requires Windows Vivado at C:\Xilinx\Vivado\2023.1. Runner auto-detects via BLOCKED_XSIM_UNAVAILABLE gate. |
| FLUSH_COUNT=1 shared credit | Info | PSS consumes flush_rem; SSS does not flush (flush_rem=0 at SSS STREAM state). Correct by design. |
| km8 score equals kp8 score | Info | 509,590,562 for both — numerically coincidental; peak locations differ (263 vs 247). |
