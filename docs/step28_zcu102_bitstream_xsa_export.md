# Step 28 — ZCU102 Synthesis, Implementation, Bitstream, and XSA Export

## Goal

Run the Step 27 Vivado block design (`sync_phase1_bd`) through the full Vivado
implementation flow: synthesis → implementation → timing check → bitstream →
XSA export.

This is the first full Vivado build for the Phase-1 FPGA known-vector test system.

No ILA, no DMA, no VIO, no integer CFO.

---

## Phase 1 Context

| Phase | Description |
|-------|-------------|
| **1 (current)** | Functional FPGA synchronizer: PS writes IQ to BRAM, triggers run, reads results |
| 2 | 1 sample/clock streaming synchronizer |
| 3 | Multi-sample/clock parallel synchronizer |

The Phase 1 system allows an ARM Cortex-A53 running baremetal firmware (Vitis, Step 29)
to write known IQ samples into the BRAM wrapper, execute the synchronizer, and read back
the corrected output — all through AXI-Lite memory-mapped I/O.

---

## Step 27 BD Summary

The block design created in Step 27 is the input to this build:

| Item | Value |
|------|-------|
| Vivado project | `vivado/step27_zcu102_bd/step27_zcu102_bd.xpr` |
| BD name | `sync_phase1_bd` |
| Top | `sync_phase1_bd_wrapper` |
| Custom IP | `frac_cfo_sync_bram_test_wrapper` (wrapper_0) |
| Base address | `0xA0000000` |
| Range | 64 KB |

### BD Components

| Cell | IP | Role |
|------|----|------|
| `zynq_ultra_ps_e_0` | Zynq UltraScale+ MPSoC | PS — AXI master, clock, reset |
| `axi_smc` | AXI SmartConnect | 1 master → 1 slave crossbar |
| `proc_sys_reset_0` | Processor System Reset | Synchronized active-low reset |
| `xlconstant_0` | XL Constant | dcm_locked tied to 1 |
| `wrapper_0` | `frac_cfo_sync_bram_test_wrapper` | AXI-Lite BRAM test harness |

### Step 27 Execution Results

| Check | Result |
|-------|--------|
| IP packaging | PASS |
| BD creation | PASS |
| validate_bd_design | PASS |
| HDL wrapper | PASS |
| Output products | PASS |

---

## Build Target

| Item | Value |
|------|-------|
| Board | ZCU102 Rev 1.0 |
| Part | `xczu9eg-ffvb1156-2-e` |
| Vivado | 2022.2 (Windows) |
| Project | `vivado/step27_zcu102_bd/step27_zcu102_bd.xpr` |
| Top | `sync_phase1_bd_wrapper` |
| Clock | PS FCLK0 / pl_clk0 — 100 MHz (10.000 ns period) |
| AXI slave base | `0xA0000000`, 64 KB |

---

## Files

| File | Description |
|------|-------------|
| `scripts/vivado/step28_build_bitstream_xsa.tcl` | Vivado batch Tcl — full build flow |
| `scripts/windows/run_step28_build_bitstream_xsa.bat` | Windows batch runner |
| `docs/step28_zcu102_bitstream_xsa_export.md` | This document |
| `reports/step28/step28_build.log` | Full Vivado console log (after run) |
| `reports/step28/step28_synth_utilization.rpt` | Synthesis utilization |
| `reports/step28/step28_synth_timing_summary.rpt` | Synthesis timing summary |
| `reports/step28/step28_impl_utilization.rpt` | Implementation utilization |
| `reports/step28/step28_timing_summary.rpt` | Implementation timing summary |
| `reports/step28/step28_drc.rpt` | DRC results |
| `reports/step28/step28_power.rpt` | Power estimate |
| `outputs/step28/sync_phase1_bd_wrapper.bit` | Bitstream (after run) |
| `outputs/step28/sync_phase1_bd_wrapper.xsa` | Hardware platform for Vitis (after run) |

---

## Tcl Script Description

`scripts/vivado/step28_build_bitstream_xsa.tcl`:

1. Opens `vivado/step27_zcu102_bd/step27_zcu102_bd.xpr`
2. Verifies top is `sync_phase1_bd_wrapper`
3. Resets prior synth/impl runs if needed (idempotent)
4. Launches `synth_1` with 4 jobs; waits; checks status
5. Opens `synth_1`, generates `step28_synth_utilization.rpt` and `step28_synth_timing_summary.rpt`
6. Launches `impl_1` with 4 jobs; waits; checks status
7. Opens `impl_1`, generates utilization, timing summary, DRC, and power reports
8. Checks timing via `get_timing_paths -setup` / `-hold`:
   - Prints `TIMING CHECK: PASS` if WNS ≥ 0 and WHS ≥ 0
   - Prints `TIMING CHECK: FAIL` and exits non-zero if violated
9. Writes bitstream: `outputs/step28/sync_phase1_bd_wrapper.bit`
10. Exports XSA: `write_hw_platform -fixed -include_bit -force -file outputs/step28/sync_phase1_bd_wrapper.xsa`
11. Prints summary; exits 0 on success

The script exits non-zero if synthesis, implementation, timing, bitstream, or XSA export fails.

---

## Windows Command

```bat
cd C:\RTL_SYNC
.\scripts\windows\run_step28_build_bitstream_xsa.bat
```

Log output: `reports\step28\step28_build.log`

---

## Copying Results Back to WSL

After the Windows build completes:

```bash
# From WSL
cp /mnt/c/RTL_SYNC/outputs/step28/sync_phase1_bd_wrapper.bit \
   /home/zealatan/RTL_SYNC/outputs/step28/
cp /mnt/c/RTL_SYNC/outputs/step28/sync_phase1_bd_wrapper.xsa \
   /home/zealatan/RTL_SYNC/outputs/step28/
cp /mnt/c/RTL_SYNC/reports/step28/*.rpt \
   /home/zealatan/RTL_SYNC/reports/step28/
cp /mnt/c/RTL_SYNC/reports/step28/step28_build.log \
   /home/zealatan/RTL_SYNC/reports/step28/
```

---

## Execution Status

**Step 28 failed during synthesis (Step 28B RTL fix applied, pending re-run).**

Initial execution: Vivado synthesis failed on the packaged IP run
`sync_phase1_bd_wrapper_0_0_synth_1` with:

```
ERROR: [Synth 8-2716] syntax error near '''
[.../ipshared/.../src/cp_autocorr_core.v:97]
```

See **Step 28B** section below for root cause and fix.

---

## Step 28B — RTL Verilog Syntax Compatibility Fix

### Original Vivado Error

```
ERROR: [Synth 8-2716] syntax error near '''
  File: .../ipshared/.../src/cp_autocorr_core.v:97
  
Additional warnings during IP packaging:
  syntax near ''' in timing_sync_top.v
  syntax near ''' in frac_cfo_frame_corrector_top.v
```

The apostrophe character `'` in the error messages is the SystemVerilog width/type cast operator.

### Root Cause

Three RTL files contained SystemVerilog-only width-cast syntax (`WIDTH'(expr)` or `N'(expr)`).
This syntax is accepted by `xvlog -sv` (the simulator) but rejected by Vivado's Verilog IP synthesis parser:

- `ipx::package_project` copies RTL into the IP directory
- During BD synthesis (`launch_runs synth_1`), Vivado synthesizes the packaged IP as **Verilog** (not SystemVerilog)
- The `WIDTH'(...)` cast form is a SystemVerilog construct — the Verilog parser rejects the apostrophe as a syntax error

The `xvlog -sv` flag causes the simulator to accept SystemVerilog syntax even in `.v` files.
Vivado packaged IP synthesis uses Verilog parsing (matching the `.v` extension) without the `-sv` flag.

### All Patterns Fixed (8 total)

| File | Line | Original (SV) | Fixed (Verilog-2001) |
|------|------|----------------|----------------------|
| `cp_autocorr_core.v` | 97 | `ADDR_WIDTH'(NSC)` | `LP_NSC_B` (localparam) |
| `timing_sync_top.v` | 132 | `9'(NSC)` | `LP_NSC_IDX` (localparam) |
| `timing_sync_top.v` | 155 | `10'(NSC)` | `LP_NSC_CNT` (localparam) |
| `frac_cfo_frame_corrector_top.v` | 176 | `PLAY_CNT_W'(TOTAL_SAMPLES)` | `TOTAL_SAMPLES` |
| `frac_cfo_frame_corrector_top.v` | 320 | `BUF_AW'(play_rd_ptr)` | `play_rd_ptr` |
| `frac_cfo_frame_corrector_top.v` | 393 | `BUF_AW'(peak_lag)` | `peak_lag` |
| `frac_cfo_frame_corrector_top.v` | 400 | `5'(NCO_WAIT)` | `NCO_WAIT` |
| `frac_cfo_frame_corrector_top.v` | 432 | `PLAY_CNT_W'(TOTAL_SAMPLES - 1)` | `TOTAL_SAMPLES - 1` |

**Fix strategy:**

- For integer parameter casts to sized wire connections/arithmetic: add a `localparam` with an explicit width, e.g. `localparam [ADDR_WIDTH-1:0] LP_NSC_B = NSC;` — the localparam assignment performs the truncation at elaboration time in clean Verilog-2001.
- For casts where width constraint comes from the assignment context (LHS reg/wire width): drop the cast entirely. Verilog-2001 assignment or comparison truncates/zero-extends the RHS to match the LHS width.

**Arithmetic correctness:** All parameter values are small relative to their target widths (e.g. NSC=256 fits in ADDR_WIDTH=12 bits, TOTAL_SAMPLES=288 fits in PLAY_CNT_W=9 bits), so no numeric overflow occurs from removing the explicit cast.

### Regression Status

xvlog not in PATH in WSL — regressions could not be run.
RTL changes are mechanical syntax substitutions with no algorithmic change.
The same values flow through the same arithmetic; only the cast notation changed.

WSL regression command (run when Vivado toolchain is in PATH):
```bash
bash scripts/run_frac_cfo_frame_corrector_top_sim.sh
bash scripts/run_frac_cfo_sync_bram_test_wrapper_sim.sh
bash scripts/run_frac_cfo_sync_axi_stream_wrapper_sim.sh
```
Expected: PASS=176, PASS=23, PASS=23.

### Required Windows Re-run Sequence

Step 27 must be re-run first to repackage the IP with the fixed RTL (the packaged IP
in `vivado/ip_repo/` has a cached copy of the old RTL).

```bat
cd C:\RTL_SYNC
.\scripts\windows\run_step27_create_zcu102_bd_no_ila.bat
.\scripts\windows\run_step28_build_bitstream_xsa.bat
```

Step 27 will:
- Delete and recreate `vivado/ip_repo/frac_cfo_sync_bram_test_wrapper_1_0/`
- Re-import RTL with the fixed syntax
- Recreate `vivado/step27_zcu102_bd/step27_zcu102_bd.xpr`

Step 28 will then synthesize the fixed RTL inside the packaged IP.

---

## Expected Utilization (from Step 24 OOC synthesis)

These are the Step 24 OOC estimates for `frac_cfo_frame_corrector_top` alone.
The full wrapped BD will differ (PS9, SmartConnect, proc_sys_reset overhead).

| Resource | Step 24 OOC estimate |
|----------|----------------------|
| LUT | ~500–700 (estimate) |
| DSP48E2 | 17 |
| BRAM | 1 RAMB36 tile (RAMB18 ×2) |
| FF | ~500–800 (estimate) |
| WNS | +4.092 ns at 100 MHz |

The Step 28 full-system build will report actual numbers including the PS hard block,
SmartConnect, proc_sys_reset, and inferred BRAM arrays from the wrapper.

---

## Known Warnings (expected)

| Warning | Cause | Severity |
|---------|-------|---------|
| Address width mismatch | PS outputs 40-bit AXI address; wrapper s_axi_awaddr/araddr are 16-bit | Advisory — BD handles address stripping |
| `initial` block in BRAM | Vivado may warn on initial blocks in inferred BRAM arrays (input_mem, output_mem) | Advisory — ignored for bring-up |
| Unconstrained paths | Some PS-internal paths may be unconstrained | Advisory |

No critical warnings are expected.

---

## ILA / DMA / Integer CFO — Not Present by Design

ILA and DMA are intentionally omitted from this Phase 1 build.
Observability is provided through STATUS, INPUT_COUNT, OUTPUT_COUNT, and DEBUG_STATE
registers accessed via PS AXI reads.

Integer CFO (`int_cfo_estimator.v`) is deferred to a later phase.

---

## write_hw_platform Notes (Vivado 2022.2)

The XSA export command used:

```tcl
write_hw_platform -fixed -include_bit -force -file outputs/step28/sync_phase1_bd_wrapper.xsa
```

- `-fixed`: exports a fixed XSA (not an extensible platform)
- `-include_bit`: embeds the bitstream in the XSA (required for Vitis to program the device)
- Requires that `write_bitstream` has been called first in the same session

If `-include_bit` is unsupported, the script falls back to:

```tcl
write_hw_platform -fixed -force -file outputs/step28/sync_phase1_bd_wrapper.xsa
```

In this case, the bitstream must be specified separately in Vitis.

---

## Synthesis Result

**Not yet run.**

---

## Implementation Result

**Not yet run.**

---

## Timing Result

**Not yet run.**

---

## DRC Result

**Not yet run.**

---

## Bitstream

**Not yet generated.**

Expected path: `outputs/step28/sync_phase1_bd_wrapper.bit`

---

## XSA

**Not yet generated.**

Expected path: `outputs/step28/sync_phase1_bd_wrapper.xsa`

---

## Recommended Step 29

**Step 29 — Vitis Baremetal Control Application for Known-Vector Test**

Create a Vitis 2022.2 baremetal C application for the Cortex-A53 (APU) that:

1. Writes known IQ samples into input memory window (`0xA0001000`–`0xA0001FFF`)
2. Programs `CFG_CFO_STEP`, `CFG_TIMING_OFFSET`, `CFG_FRAME_LEN`
3. Writes `INPUT_LEN` and `OUTPUT_MAX_LEN`
4. Enables the wrapper (`CONTROL[3]=1`)
5. Writes `start_pulse` (`CONTROL[0]=1`)
6. Polls `STATUS.done_sticky` until set
7. Reads `INPUT_COUNT` and `OUTPUT_COUNT`
8. Reads output memory window (`0xA0002000`–`0xA0002FFF`)
9. Prints results over UART (Zynq UART1)
10. Optionally compares a small expected subset

### Register Map

| Offset | Register | Access |
|--------|----------|--------|
| 0x0000 | CONTROL | W/R |
| 0x0004 | STATUS | R/O |
| 0x0008 | CFG_CFO_STEP | W/R |
| 0x000C | CFG_TIMING_OFFSET | W/R |
| 0x0010 | CFG_FRAME_LEN | W/R |
| 0x0014 | INPUT_LEN | W/R |
| 0x0018 | OUTPUT_MAX_LEN | W/R |
| 0x001C | INPUT_COUNT | R/O |
| 0x0020 | OUTPUT_COUNT | R/O |
| 0x0024 | DEBUG_STATE | R/O |
| 0x0028 | ERROR_STATUS | R/O |
| 0x1000–0x1FFF | Input memory window | W/R |
| 0x2000–0x2FFF | Output memory window | R/O |

Workflow: import `sync_phase1_bd_wrapper.xsa` into Vitis, create baremetal platform,
create Application project (Hello World template), replace `main()` with the test driver.
