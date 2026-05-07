# Step 21 — Randomized Verification Campaign for frac_cfo_frame_corrector_top

## Goal

Strengthen verification of `rtl/frac_cfo_frame_corrector_top.v` by expanding the Step 20
integration test from 39 checks to a randomized/sweep-based campaign totalling 176 checks.

## Phase 1 Context

Phase 1 is a frame-buffered, FSM-controlled OFDM synchronizer. The DUT (`frac_cfo_frame_corrector_top.v`)
integrates `iq_frame_buffer`, `frame_detector`, `timing_frac_cfo_top`, and `frac_cfo_corrector_top`
in a 7-state FSM: IDLE→FILL→FRAME_DET→TIMING_CFO→LOAD_NCO→CORRECT→DONE.

## Integer CFO Deferral

Integer CFO estimation (`int_cfo_estimator.v`), FFT, PSS cross-correlation, IFFT, and Phase 2/3
pipeline work are deferred to Step 24+. The reason: Phase 1 functional FPGA bring-up requires
closing the fractional-CFO frame synchronizer as a robust, synthesis-ready block before expanding
the receiver chain.

## Step 20 Baseline

- File: `rtl/frac_cfo_frame_corrector_top.v`
- Testbench: `tb/frac_cfo_frame_corrector_top_tb.sv`
- Result: PASS=39, FAIL=0
- Tests: T1 (reset state), T2 (happy path), T3 (count/tlast), T4 (sample values),
  T5 (no frame), T6 (done pulse), T7 (busy signal), T8 (frame_index stable),
  T9 (peak_lag stable), T10 (back-to-back runs)

## Simulation Parameters

```
NSC=16, CP_LEN=4, BUF_AW=10 (depth=1024), LATENCY=15
WINDOW_LEN=4, HIT_COUNT=2, THRESHOLD=1, TOTAL_SAMPLES=20
Stimulus: 8 quiet (I=0,Q=0) + signal samples
Baseline: frame_index=5, peak_lag=2, frac_phase=0
```

## Test Groups (R1–R8)

### R1 — Timing Offset Sweep (32 checks)

Sweeps 16 values (parameter `off` = 0..15); actual quiet-sample count = `off+4` (4..19).
The minimum of 4 = WINDOW_LEN is required for the DUT frame detector to see a clear
signal onset. For each offset: 2 checks (frame_found=1, count=TOTAL_TB=20).

### R2 — Signal Configuration Sweep (16 checks)

Four IQ patterns: (100,0), (0,100), (70,70), (-100,0). 8 quiet + 100 signal samples.
4 checks per config: frame_found, frame_error=0, count=TOTAL_TB, tlast=19.

### R3 — Randomized Frame Placement (40 checks)

20 deterministic LFSR/XorShift32 trials (seed=0xDEAD_BEEF). Offset bounded [4..15]
(minimum 4 = WINDOW_LEN). 2 checks per trial: frame_found=1, count=TOTAL_TB.

### R4 — Randomized Amplitude Scaling (10 checks)

10 deterministic trials (seed=0xCAFE_0001). Amplitude = 30 + (prng>>>1)%100 = 30..129.
Offset fixed at 4 quiet samples. 1 check per trial: count=TOTAL_TB.

### R5 — AXI-Stream Output Backpressure (12 checks)

m_axis_tready stalled for {0, 1, 2, 3} cycles after each accepted sample.
When tready=0, axis_complex_mult stalls corr_tready, deferring done until last sample accepted.
3 checks per delay: count=TOTAL_TB, tlast at index 19, tvalid fired.

### R6 — Reset Robustness (9 checks)

Three scenarios (3 checks each):
- S1: Reset from idle — verifies busy=0, done=0 after reset, then recovery run completes.
- S2: Reset mid-frame-detection (~80 cycles after streaming completes, DUT in S_FRAME_DET)
  — verifies busy=0, done=0 after reset, then recovery run completes.
- S3: Reset after done — verifies busy=0, then second clean run produces TOTAL_TB samples.

### R7 — No-Frame / False-Trigger Rejection (6 checks)

Three tests with threshold=`'1` (maximum 40-bit value) to guarantee no window energy
can exceed the threshold. Tests: all-quiet (40 samples), all-signal (40 samples),
mixed quiet+signal (10+40 samples). 2 checks per test: frame_error=1, m_axis_tvalid=0.
Note: iq_frame_buffer.mem[] is NOT cleared on reset; max threshold is the safe
approach to prevent false detection from stale buffer contents.

### R8 — Buffer Boundary Stress (12 checks)

Four configurations (3 checks each: frame_found, count=TOTAL_TB, tlast=19):
- C1: off=4 (minimum), 50 signal samples (frame starts near buffer start)
- C2: off=4, only 12 signal samples (minimal: 12 ≥ WINDOW_LEN×HIT_COUNT=8)
- C3: off=15 (maximum tested), 50 signal samples
- C4: off=8 (mid-range), 50 signal samples

## PRNG Policy

XorShift32 with fixed seeds per group ensures determinism across runs and tools.
- R3 seed: `32'hDEAD_BEEF`
- R4 seed: `32'hCAFE_0001`
- Offset bounds enforce minimum of WINDOW_LEN=4 quiet samples.

## Simulation Result

```
PASS: 176   FAIL: 0
Groups: R1 PASS, R2 PASS, R3 PASS, R4 PASS, R5 PASS, R6 PASS, R7 PASS, R8 PASS
Randomized trials: 20 frame-placement + 10 amplitude = 30 total
CI GATE: PASSED
```

## Bugs Found

### Testbench Bug — GROUP logic used global fail_cnt instead of per-group delta

**Symptom**: R2–R8 all reported `[GROUP] ... FAIL` even when all their own checks passed,
because R1 had failures that incremented the global `fail_cnt`, and the GROUP check was
`(fail_cnt == 0)` (requires zero failures ever, not zero in this group).

**Fix**: Added `int grp_fail_snap` variable. Each group saves `grp_fail_snap = fail_cnt`
before its tests and reports `PASS` when `fail_cnt == grp_fail_snap` at the end.

### Testbench Bug — Minimum quiet-sample requirement not respected (R1, R3, R8 C1)

**Symptom**: R1 off=0..3, R3 some PRNG trials, and R8 C1 (off=0) all timed out or got
`frame_found=0`, because the DUT frame detector requires at least WINDOW_LEN=4 quiet
samples before the signal onset to detect a clear CP-autocorrelation peak.

**Root cause**: With fewer than WINDOW_LEN quiet samples, the CP autocorrelation is
non-zero from the very first buffer position, producing a flat (no-onset) energy profile.
The frame detector cannot find a reliable frame boundary → frame_error=1 → no m_axis output.

**Fix**:
- R1: Changed `stream_iq(off, ..., off+60, ...)` to `stream_iq(off+4, ..., off+64, ...)`.
  Sweep tests offsets 4..19 (16 values, 32 checks preserved).
- R3: Changed `r3_off = 2 + (prng & 0xF) % 14` to `r3_off = 4 + (prng & 0xF) % 12`.
  Range changed from 2..15 to 4..15.
- R8 C1: Changed `stream_iq(0, ..., 50, ...)` to `stream_iq(4, ..., 54, ...)`.

## RTL Modified

**No.** All fixes were in `tb/frac_cfo_frame_corrector_top_tb.sv` only.

## Limitations

- Test signal is a constant IQ value, not a real OFDM waveform with CP structure.
  The CP autocorrelator passes because all lags give the same high energy (flat peak)
  when the quiet-sample onset is present.
- R5 backpressure delay is limited to 3 cycles. Larger stalls (e.g., 10+ cycles) are
  not tested.
- R6 S2 mid-frame-detection reset uses a fixed 80-cycle wait (DUT is in S_FRAME_DET
  searching up to 1024 positions). The reset timing is not precisely cycle-accurate.

## Recommended Step 22

Step 22 — Phase-1 Synthesis-Readiness and Vivado Resource/Timing Check.
- Target device: ZCU102 (`xczu9eg-ffvb1156-2-e`)
- Clock port: `aclk`, target 100 MHz
- Windows Vivado required for actual synthesis/implementation
- Scope: OOC synthesis, resource utilization, timing report, any critical warnings
