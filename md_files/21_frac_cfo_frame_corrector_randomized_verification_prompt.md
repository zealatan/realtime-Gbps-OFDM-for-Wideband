# Step 21 Prompt — Randomized Verification Campaign for frac_cfo_frame_corrector_top

## Active Workspace

```
/home/zealatan/RTL_SYNC
```

## Workspace Guard

Before modifying any file, run:

```
pwd
git rev-parse --show-toplevel
```

You must be inside `/home/zealatan/RTL_SYNC`.

Do not modify files under `/home/zealatan/AI_ORC/messi/VIVADO_MIN_EXAMPLE`, `/mnt/c/`, `C:\`, or any Windows mirror path.

This is a WSL RTL/xsim/documentation step only. Do not run Windows Vivado synthesis, implementation, bitstream generation, or Vitis.

## Project Context

Phase 1 = Functional FPGA synchronizer. Phase 2 = 1 sample/clock streaming synchronizer. Phase 3 = multi-sample/clock parallel synchronizer. The current design belongs to Phase 1 (frame-buffered, FSM-controlled synchronizer).

## Latest Completed Step

Step 20 — `frac_cfo_frame_corrector_top.v`
- Current top: `rtl/frac_cfo_frame_corrector_top.v`
- Current testbench: `tb/frac_cfo_frame_corrector_top_tb.sv`
- Current script: `scripts/run_frac_cfo_frame_corrector_top_sim.sh`
- Step 20 result: PASS = 39, FAIL = 0, CI gate = PASSED

## Roadmap Correction

The old Step 21 plan (`int_cfo_estimator.v`) is **deferred**. Do not implement int_cfo_estimator, integer CFO, FFT, PSS cross-correlation, IFFT, or expand to full OFDM RX.

Revised Step 21 = Randomized Verification Campaign for `frac_cfo_frame_corrector_top`.

Reason: Phase 1 goal is to close the fractional-CFO frame synchronizer as a robust functional FPGA-ready block before adding integer CFO or FFT-based functionality.

## Step 21 Goal

Strengthen verification of `rtl/frac_cfo_frame_corrector_top.v`. Expand the Step 20 integration test from 39 checks to a randomized/sweep-based campaign.

**Target result:** PASS = 176, FAIL = 0, CI gate = PASSED.

## Allowed Files to Modify

- `tb/frac_cfo_frame_corrector_top_tb.sv`
- `scripts/run_frac_cfo_frame_corrector_top_sim.sh`
- `docs/step21_frac_cfo_frame_corrector_randomized_verification.md`
- `ai_context/current_status.md`
- `md_files/21_frac_cfo_frame_corrector_randomized_verification_prompt.md` (or `_v2` if needed)

Do not modify: `rtl/frac_cfo_frame_corrector_top.v`, lower-level RTL modules, unrelated files.

## Required Verification Groups

### R1 — Timing Offset Sweep

Sweep `cfg_timing_offset` from 0 to 15. Verify correct output behavior at each offset.
Print: `[GROUP] R1 timing offset sweep PASS`

### R2 — Fractional CFO Sweep

Sweep `cfg_cfo_step` through: `0x0000`, `0x4000`, `0x8000`, `0xC000`.
Print: `[GROUP] R2 fractional CFO sweep PASS`

### R3 — Randomized Frame Placement

20 deterministic LFSR/XorShift32 trials (fixed seed). Bounded frame placement offset.
Print: `[RANDOM] frame_placement_trials = 20` / `[GROUP] R3 randomized frame placement PASS`

### R4 — Randomized Amplitude Scaling

10 deterministic randomized amplitude scaling trials. CFO=0 identity/near-identity check.
Print: `[RANDOM] amplitude_trials = 10` / `[GROUP] R4 randomized amplitude scaling PASS`

### R5 — AXI-Stream Output Backpressure

`m_axis_tready` delay = {0, 1, 2, 3} cycles. Verify: tvalid legal, no sample lost, tlast aligned, data stable during valid && !ready.
Print: `[GROUP] R5 AXI backpressure PASS`

### R6 — Reset Robustness

Scenarios: reset before frame, reset during active processing, reset after output. Verify: no stale output, DUT returns to safe state, next frame processes correctly.
Print: `[GROUP] R6 reset robustness PASS`

### R7 — No-Frame / False-Trigger Rejection

Feed inputs that should not trigger a frame. Verify no valid output, no false completion.
Print: `[GROUP] R7 no-frame rejection PASS`

### R8 — Buffer Boundary Stress

Cases: frame_len=1, frame_len=10, offset=15, mid-range nominal. Verify: no wrap bug, no stale samples, no early tlast, no hang.
Print: `[GROUP] R8 buffer boundary stress PASS`

## Testbench Requirements

- Preserve all Step 20 tests (do not remove existing checks)
- Add helper tasks as needed: `run_frame`, `receive_output`, `receive_output_with_backpressure`, `reset_dut`, `program_config`, `check_output_count`, `check_no_output`, `check_stable_during_backpressure`
- If existing helper tasks have bugs, fix testbench only and document the bug
- Known bug classes: stale samples in DUT buffer after `run_frame`; sampling m_tlast after NBA cleared it; output count before handshake; random trial not clearing state between runs

## Script Requirements

Update `scripts/run_frac_cfo_frame_corrector_top_sim.sh` if needed. Must: run xsim, save log under `logs/frac_cfo_frame_corrector_top_xsim.log`, return non-zero on failure or if log contains [FAIL]/FATAL/ERROR, print CI GATE PASSED only when clean.

## Documentation Requirements

Create `docs/step21_frac_cfo_frame_corrector_randomized_verification.md` covering: goal, Phase 1 context, integer CFO deferral reason, Step 20 baseline, R1–R8 descriptions, LFSR policy, simulation result, bugs found, RTL modified, limitations, recommended Step 22.

Update `ai_context/current_status.md` with Step 21 completion summary.

## Recommended Step 22

Step 22 — Phase-1 Synthesis-Readiness and Vivado Resource/Timing Check. Target: ZCU102 (`xczu9eg-ffvb1156-2-e`), clock port `aclk` (not `clk`). Windows Vivado required for actual synthesis.

## Final Report Format

Step 21 complete. Prompt archive: ... Files changed: ... Test groups (R1–R8): PASS/FAIL. Simulation result: PASS/FAIL/trials/CI GATE. Bugs found (RTL/testbench). RTL modified: Yes/No. Recommended Step 22: ...

## Important Constraints

Do not implement int_cfo_estimator, integer CFO, FFT, PSS, IFFT, AXI-Lite wrapper, DMA, synthesis scripts. Do not run Windows Vivado. Do not start Phase 2. Keep this step focused only on randomized verification of `frac_cfo_frame_corrector_top`.
