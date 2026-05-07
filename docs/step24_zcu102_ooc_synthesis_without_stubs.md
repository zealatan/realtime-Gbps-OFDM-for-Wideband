# Step 24 — ZCU102 OOC Synthesis Without CORDIC/NCO Stubs

## Goal

Re-run ZCU102 out-of-context (OOC) synthesis using the synthesizable RTL modules
produced in Step 23, confirming that the full `frac_cfo_frame_corrector_top` hierarchy
synthesizes on `xczu9eg-ffvb1156-2-e` with no blackboxes.

## Phase 1 Context

Phase 1 is a frame-buffered, FSM-controlled OFDM synchronizer — not a 1-sample/clock
streaming pipeline. The design integrates:
- `iq_frame_buffer` — AXI-Stream fill + random-access read
- `frame_detector` — sliding-window energy detection
- `timing_frac_cfo_top` — CP autocorrelation + CORDIC atan2 for frac CFO estimation
- `frac_cfo_corrector_top` — NCO + complex rotator for frac CFO removal

FSM: IDLE → FILL → FRAME_DET → TIMING_CFO → LOAD_NCO → CORRECT → DONE

## Step 22 Summary (Stub-Based Synthesis)

Step 22 OOC synthesis on `xczu9eg-ffvb1156-2-e` passed, but used synthesis stubs:

| Stub file | Replaced module | Reason |
|-----------|----------------|--------|
| `scripts/synth_stubs/cordic_atan2_stub.v` | `rtl/cordic_atan2.v` | Had `real`, `$atan2` |
| `scripts/synth_stubs/nco_phase_gen_stub.v` | `rtl/nco_phase_gen.v` | Had `real`, `$sin`, `$cos` |

The stubs were port-only black-boxes, so Step 22 could not validate the CORDIC/NCO logic.

## Step 23 Summary (Synthesizable CORDIC/NCO)

Step 23 replaced both simulation-only modules with synthesizable RTL:

| Module | Implementation | Synthesis-safe |
|--------|---------------|---------------|
| `rtl/cordic_atan2.v` | 15-stage CORDIC vectoring pipeline, 35-bit x/y, 18-bit z | Yes |
| `rtl/nco_phase_gen.v` | 256-entry sin/cos ROM (`initial` block → LUTRAM) + pipeline | Yes |

Simulation results after Step 23:
- `cordic_atan2_tb`: PASS=38, FAIL=0
- `nco_phase_gen_tb`: PASS=33, FAIL=0
- Integration `frac_cfo_frame_corrector_top_tb`: PASS=176, FAIL=0, CI GATE: PASSED

## Why No-Stub Synthesis Is Required

Step 22 synthesis validated only 13 of 15 hierarchy levels. The stub-based results
(utilization, timing) did not account for the CORDIC pipeline registers or NCO ROM.
Step 24 is necessary to:
1. Confirm the synthesizable CORDIC/NCO RTL is accepted by Vivado 2022.2 without errors.
2. Obtain accurate LUT/FF/BRAM/DSP utilization including the CORDIC pipeline.
3. Verify timing closure at 100 MHz with the full logic included.
4. Confirm zero blackboxes in the synthesized netlist.

## Target

| Item | Value |
|------|-------|
| Board | ZCU102 |
| Part | `xczu9eg-ffvb1156-2-e` |
| Vivado version | 2022.2 (Windows) |
| Top module | `frac_cfo_frame_corrector_top` |
| Clock port | `aclk` |
| Clock target | 100 MHz (10.000 ns period) |

## WSL / Windows Environment Split

| Task | Environment |
|------|-------------|
| RTL / testbench editing | WSL `/home/zealatan/RTL_SYNC` |
| xsim simulation | WSL |
| Script generation | WSL |
| Vivado synthesis | **Windows** `C:\RTL_SYNC` |
| Implementation / bitstream | **Windows** (Step 25+) |

## Module Hierarchy

```
frac_cfo_frame_corrector_top          (top)
├── iq_frame_buffer
├── frame_detector
├── timing_frac_cfo_top
│   ├── timing_sync_top
│   │   ├── cp_autocorr_core
│   │   ├── timing_metric_core
│   │   └── peak_detector
│   └── frac_cfo_estimator
│       └── cordic_atan2              ← Step 23 synthesizable RTL (CORDIC pipeline)
└── frac_cfo_corrector_top
    ├── nco_phase_gen                 ← Step 23 synthesizable RTL (ROM NCO)
    └── complex_rotator
        └── complex_mult_iq
            └── axis_complex_mult
```

## Real RTL Source List

All 15 files are real RTL — no stubs:

| File | Notes |
|------|-------|
| `rtl/axis_complex_mult.v` | Complex multiplier |
| `rtl/complex_mult_iq.v` | I/Q wrapper |
| `rtl/complex_rotator.v` | Rotator |
| `rtl/iq_frame_buffer.v` | Frame buffer |
| `rtl/frame_detector.v` | Sliding-window energy detector |
| `rtl/cp_autocorr_core.v` | CP autocorrelation |
| `rtl/timing_metric_core.v` | Timing metric |
| `rtl/peak_detector.v` | Peak detector |
| `rtl/cordic_atan2.v` | **Step 23 synthesizable CORDIC** (no `real`/`$atan2`) |
| `rtl/frac_cfo_estimator.v` | Frac CFO estimator |
| `rtl/nco_phase_gen.v` | **Step 23 synthesizable NCO ROM** (no `real`/`$sin`/`$cos`) |
| `rtl/frac_cfo_corrector_top.v` | CFO corrector |
| `rtl/timing_sync_top.v` | Timing sync top |
| `rtl/timing_frac_cfo_top.v` | Timing + frac CFO top |
| `rtl/frac_cfo_frame_corrector_top.v` | Top-level DUT |

**Synthesis stubs NOT used:**
- `scripts/synth_stubs/cordic_atan2_stub.v` — NOT loaded
- `scripts/synth_stubs/nco_phase_gen_stub.v` — NOT loaded

## Vivado TCL Script

File: `scripts/step24_synth_check_no_stubs.tcl`

Key actions:
- `create_project synth_step24 ./build/step24_synth -part xczu9eg-ffvb1156-2-e -force`
- Reads all 15 real RTL sources (no stubs)
- `synth_design -top frac_cfo_frame_corrector_top -part xczu9eg-ffvb1156-2-e -mode out_of_context`
- `create_clock -period 10.000 [get_ports aclk]`
- `report_utilization -file reports/step24_synth_utilization.rpt`
- `report_timing_summary -file reports/step24_timing_summary.rpt`
- `report_drc -file reports/step24_drc.rpt`
- Blackbox check: `get_cells -hierarchical -filter {BLACK_BOX == 1}`
- `exit 0` on success; Vivado exits non-zero on synthesis failure

## Windows Batch Runner

File: `scripts/windows/run_step24_zcu102_ooc_synth_no_stubs.bat`

Run from Windows CMD or PowerShell:
```bat
cd C:\RTL_SYNC
scripts\windows\run_step24_zcu102_ooc_synth_no_stubs.bat
```

The batch file:
- Calls `C:\Xilinx\Vivado\2022.2\bin\vivado.bat -mode batch`
- Guards: checks for TCL script, Vivado binary, real RTL files
- Guards: refuses to run if TCL references `synth_stubs`
- Logs console output to `reports\step24_synth_messages.log`
- Returns non-zero exit code if Vivado fails

Copy reports back to WSL after the run:
```bash
cp /mnt/c/RTL_SYNC/reports/step24_*.rpt /home/zealatan/RTL_SYNC/reports/
cp /mnt/c/RTL_SYNC/reports/step24_synth_messages.log /home/zealatan/RTL_SYNC/reports/
```

## Synthesis Execution Status

**Prepared, pending Windows Vivado run.**

Windows execution has not been performed from this Claude session.
Actual synthesis must be run on Windows using the batch file above.

Reports listed below will be populated after Windows execution:

| Report file | Status |
|------------|--------|
| `reports/step24_synth_utilization.rpt` | Not yet generated |
| `reports/step24_timing_summary.rpt` | Not yet generated |
| `reports/step24_drc.rpt` | Not yet generated |
| `reports/step24_synth_messages.log` | Not yet generated |

## Expected Synthesis Outcome

With real CORDIC and NCO RTL:

- **Expected result**: synthesis completes with no critical errors; no blackboxes
- **CORDIC pipeline**: 15 pipeline stages × (35-bit x + 35-bit y + 18-bit z + 1-bit v) = ~90 FFs per stage = ~1350 FFs; some LUT logic for adders/MUX
- **NCO ROM**: 256 × 2 × 16-bit = 8 Kbits, likely maps to distributed RAM (LUTRAM) or small BRAM slice
- **Expected WNS**: positive (CORDIC is a regular pipeline; UltraScale+ at 100 MHz expected to pass)
- **Expected DRC**: clean (no undriven outputs now that stubs are gone)
- **Blackboxes**: 0

## Utilization Summary

Not yet available. Populate after Windows Vivado run.

```
LUT:     TBD
FF:      TBD  (includes ~1350 FFs for CORDIC pipeline)
BRAM:    TBD  (NCO ROM likely LUTRAM, not BRAM)
DSP:     TBD  (axis_complex_mult uses DSP48 blocks)
```

## Timing Summary

Not yet available. Populate after Windows Vivado run.

```
WNS:              TBD
TNS:              TBD
Unconstrained:    TBD (OOC mode; some I/O paths expected unconstrained)
100 MHz pass:     TBD
```

## DRC Summary

Not yet available. Populate after Windows Vivado run.

## Blackbox Status

Not yet available. Expected: 0 blackboxes (all modules are real synthesizable RTL).

## FPGA-Readiness Conclusion

| Aspect | Status |
|--------|--------|
| RTL compilation (xsim) | PASS (Step 23: 176 integration checks, 0 failures) |
| CORDIC synthesizable | PASS (Step 23: 38 unit checks, 0 failures) |
| NCO synthesizable | PASS (Step 23: 33 unit checks, 0 failures) |
| No blackboxes in hierarchy | PENDING Windows run |
| Timing (100 MHz) | PENDING Windows run |
| DRC | PENDING Windows run |
| Board bring-up ready | PENDING Step 24 Windows synthesis pass |

## Constraints

- **Do NOT run bitstream generation in Step 24.** Synthesis only.
- **Do NOT run implementation in Step 24.** Synthesis only.
- **Do NOT run Vitis in Step 24.**
- int_cfo_estimator.v is deferred to Step 26+.

## Recommended Step 25

**If Step 24 synthesis passes** (no blackboxes, positive WNS):
→ Step 25 = AXI-Lite + AXI-Stream debug/config wrapper for Phase-1 FPGA bring-up
  (ILA probes, VIO controls, JTAG register access for `frame_found`, `frac_phase`, `threshold_in`)

**If Step 24 synthesis fails** (unexpected RTL blocker):
→ Step 25 = Fix synthesis blocker while preserving Step 23 simulation (PASS=176)
