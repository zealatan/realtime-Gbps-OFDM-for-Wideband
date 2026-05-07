# Step 22 — Phase-1 Synthesis-Readiness Report

## Goal

Determine whether `rtl/frac_cfo_frame_corrector_top.v` (the Step 21-verified
fractional-CFO frame synchronizer top) is synthesizable and suitable for
Phase-1 FPGA bring-up on ZCU102, and prepare all necessary synthesis scripts.

## Phase 1 Context

Phase 1 is a frame-buffered, FSM-controlled OFDM synchronizer. It is NOT a
1-sample/clock streaming pipeline. The design integrates:
- `iq_frame_buffer` — AXI-Stream fill + random-access read
- `frame_detector` — sliding-window energy detection
- `timing_frac_cfo_top` — CP autocorrelation + CORDIC atan2 for frac CFO estimation
- `frac_cfo_corrector_top` — NCO + complex rotator for frac CFO removal

FSM state machine: IDLE → FILL → FRAME_DET → TIMING_CFO → LOAD_NCO → CORRECT → DONE

## Step 20 Summary

- File: `rtl/frac_cfo_frame_corrector_top.v`
- Testbench: `tb/frac_cfo_frame_corrector_top_tb.sv`
- Result: PASS=39, FAIL=0, CI GATE: PASSED

## Step 21 Summary

Randomized verification campaign: R1–R8, 30 randomized trials.
Result: PASS=176, FAIL=0, CI GATE: PASSED. RTL modified: No.

## Integer CFO Deferral

`int_cfo_estimator.v`, FFT, PSS cross-correlation, IFFT, and Phase 2/3 pipeline
work are deferred to Step 24+. Phase 1 focus: close the fractional-CFO
synchronizer as a synthesis-ready FPGA block before expanding the receiver chain.

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
| Implementation / bitstream | **Windows** (Step 23+) |

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
│       └── cordic_atan2              ← CORDIC IP placeholder
└── frac_cfo_corrector_top
    ├── nco_phase_gen                 ← CORDIC IP placeholder
    └── complex_rotator
        └── complex_mult_iq
            └── axis_complex_mult
```

## RTL Synthesis-Readiness Audit

| File | Finding | Synthesizable? | Severity | Recommendation |
|------|---------|---------------|----------|----------------|
| `rtl/cordic_atan2.v` | Uses `real`, `$itor`, `$atan2`, `$rtoi` in `always @(*)`. Explicitly marked "simulation only." | **No** (as-is) | **BLOCKER** | Replace with Xilinx `cordic_v6_0` IP (translate mode, 16-bit phase output). OOC check uses `scripts/synth_stubs/cordic_atan2_stub.v`. |
| `rtl/nco_phase_gen.v` | Uses `real`, `$itor`, `$sin`, `$cos`, `$rtoi` in `always @(*)`. Explicitly marked "simulation only." | **No** (as-is) | **BLOCKER** | Replace with Xilinx `cordic_v6_0` IP (rotate/sincos mode) + synthesizable phase accumulator. OOC check uses `scripts/synth_stubs/nco_phase_gen_stub.v`. |
| `rtl/frac_cfo_estimator.v` | No `real`/system-function issues. Instantiates `cordic_atan2`. | Yes (with stub) | INFO | Blocked only by `cordic_atan2` dependency. |
| `rtl/frac_cfo_corrector_top.v` | No `real`/system-function issues. Instantiates `nco_phase_gen`. | Yes (with stub) | INFO | Blocked only by `nco_phase_gen` dependency. |
| `rtl/axis_complex_mult.v` | Uses `real` as a wire name (not the `real` data type). Synthesizable. | Yes | INFO | No action. Wire name `a_real` / `b_real` / `out_real` is synthesizable. |
| `rtl/complex_mult_iq.v` | No synthesis issues. Uses `real` only in comments. | Yes | INFO | No action. |
| `rtl/complex_rotator.v` | No synthesis issues. | Yes | INFO | No action. |
| `rtl/iq_frame_buffer.v` | No synthesis issues. | Yes | INFO | No action. |
| `rtl/frame_detector.v` | No synthesis issues. | Yes | INFO | No action. |
| `rtl/cp_autocorr_core.v` | No synthesis issues. | Yes | INFO | No action. |
| `rtl/timing_metric_core.v` | No synthesis issues. | Yes | INFO | No action. |
| `rtl/peak_detector.v` | No synthesis issues. | Yes | INFO | No action. |
| `rtl/timing_sync_top.v` | No synthesis issues. | Yes | INFO | No action. |
| `rtl/timing_frac_cfo_top.v` | No synthesis issues. | Yes | INFO | No action. |
| `rtl/frac_cfo_frame_corrector_top.v` | No synthesis issues. `$clog2` and `$signed` are synthesizable. | Yes | INFO | No action. |

**Summary:** 2 BLOCKER files (behavioral CORDIC models). All other RTL is synthesizable.
No latches, no combinational loops, no multi-driven nets, no force/release, no file I/O
found in non-stub RTL.

## Synthesis Strategy — OOC Check with Stubs

Since `cordic_atan2.v` and `nco_phase_gen.v` are not synthesizable as-is, the Step 22
OOC synthesis substitutes synthesizable port-only stubs:

| Behavioral model | Synthesis stub |
|-----------------|---------------|
| `rtl/cordic_atan2.v` | `scripts/synth_stubs/cordic_atan2_stub.v` |
| `rtl/nco_phase_gen.v` | `scripts/synth_stubs/nco_phase_gen_stub.v` |

The stubs have identical port signatures to the originals. All other RTL is read as-is.
This allows the synthesis check to validate the entire design hierarchy except the
two CORDIC placeholders.

## Vivado TCL Script

File: `scripts/step22_synth_check.tcl`

- Creates in-memory Vivado project
- Targets `xczu9eg-ffvb1156-2-e`
- Reads 13 synthesizable RTL sources + 2 stubs
- Sets top to `frac_cfo_frame_corrector_top`
- `create_clock -period 10.000 [get_ports aclk]`
- `synth_design -mode out_of_context`
- Generates 4 reports under `reports/`
- Prints WNS and timing pass/fail summary
- Exits non-zero on synthesis failure

## Windows Batch Runner

File: `scripts/windows/run_step22_zcu102_ooc_synth.bat`

```bat
cd C:\RTL_SYNC
scripts\windows\run_step22_zcu102_ooc_synth.bat
```

Calls `C:\Xilinx\Vivado\2022.2\bin\vivado.bat -mode batch` with the TCL script.
Saves console log to `reports/step22_synth_messages.log`.
Returns non-zero exit code if Vivado fails.

## Synthesis Execution Status

**Prepared, pending Windows Vivado run.**

Windows execution has not been performed from this Claude session.
Actual synthesis must be run on Windows using the batch file above.

Reports listed below will be populated after Windows execution:

| Report file | Status |
|------------|--------|
| `reports/step22_synth_utilization.rpt` | Not yet generated |
| `reports/step22_timing_summary.rpt` | Not yet generated |
| `reports/step22_drc.rpt` | Not yet generated |
| `reports/step22_synth_messages.log` | Not yet generated |

## Expected Synthesis Outcome

With the CORDIC stubs in place:

- **Expected result**: synthesis completes with warnings for the black-box stubs
- **Expected WNS**: likely positive (the non-CORDIC logic is simple FSM + registers + DSP
  multiplies in axis_complex_mult; 100 MHz on UltraScale+ is easily achievable)
- **Expected DRC**: possible SNTY-4 or similar warnings for undriven stub outputs
- **Expected utilization**: moderate LUT/FF for FSM + buffers; BRAM or distributed RAM
  for `iq_frame_buffer` and `cp_autocorr_core` result arrays; DSP blocks for multipliers

## Utilization Summary

Not yet available. Populate after Windows Vivado run.

```
LUT:     TBD
FF:      TBD
BRAM:    TBD
DSP:     TBD
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

## FPGA-Readiness Conclusion

| Aspect | Status |
|--------|--------|
| RTL compilation (xsim) | PASS (Step 21: 176 checks, 0 failures) |
| Synthesizable RTL (excluding CORDIC stubs) | PASS (audit clean) |
| CORDIC modules | REQUIRES IP REPLACEMENT |
| Timing (100 MHz) | PENDING Windows run |
| DRC | PENDING Windows run |
| Board bring-up ready | NO — CORDIC IP must be substituted first |

## Remaining Blockers

1. **CORDIC IP replacement** (required before production synthesis):
   - `cordic_atan2.v` → Vivado IP Catalog: CORDIC v6.0, Translate mode, 16-bit phase output,
     AXI4-Stream interface, LATENCY=15
   - `nco_phase_gen.v` → Vivado IP Catalog: CORDIC v6.0, Rotate mode (sin/cos), 16-bit
     coefficient output, AXI4-Stream interface, wrapped with phase accumulator registers

2. **Timing closure** — verify after Windows synthesis run; UltraScale+ at 100 MHz is
   expected to pass given the logic complexity.

## Recommended Step 23

**If Step 22 synthesis passes** (only expected CORDIC stub warnings, positive WNS):
→ Step 23 = CORDIC IP integration: replace `cordic_atan2.v` and `nco_phase_gen.v`
  simulation models with `cordic_v6_0` Vivado IP instances, re-run Step 21 xsim
  to verify behavior is unchanged, then re-run Step 22 synthesis for full (non-stub) pass.

**If Step 22 synthesis fails** (unexpected RTL blocker beyond CORDIC stubs):
→ Step 23 = Fix synthesis blocker while preserving Step 21 simulation (PASS=176).

After CORDIC IP integration and synthesis closure:
→ Step 24 = AXI-Lite debug/config wrapper for Phase-1 FPGA bring-up (ILA, VIO, JTAG)
→ Step 25+ = int_cfo_estimator.v and remaining synchronizer chain
