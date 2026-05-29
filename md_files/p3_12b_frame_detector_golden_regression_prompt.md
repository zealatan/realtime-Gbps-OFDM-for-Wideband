# Claude Code Prompt — P3-12B Frame Detector Golden Regression

## Working Directory
`/home/zealatan/RTL_SYNC_PHASE3`

## Mandatory Archival Rule
Before making any code change, save this prompt verbatim to:

`md_files/p3_12b_frame_detector_golden_regression_prompt.md`

Create `md_files/` if it does not exist.

---

# Context

P3-12A completed modular frame detector refactor:

```text
rtl/frame_detector.v
├─ sample_power_sq
├─ sliding_window_sum
└─ frame_detect_fsm
```

Module-level results:

```text
sliding_window_sum_tb      PASS
frame_detect_fsm_tb        PASS
frame_detector_system_tb   PASS
SANITY_GATE: PASS 63/63 under iverilog
```

Now we must verify that the new modular `frame_detector.v` still matches the existing Phase3 golden behavior.

Important expected legacy/golden result:

```text
frame_found = 1
frame_index = 41
```

This must be checked through the existing Phase3 integration path, not only through isolated unit tests.

---

# Objective

Run and repair the Phase3 regression so the new modular frame detector is validated against the existing golden replay / P3-05C style expectation.

Primary target:

```text
frame_found = 1
frame_index = 41
```

Secondary target:

```text
slot_start_index remains consistent with frame_index + peak_lag
```

---

# Allowed Modifications

You may create/modify:

```text
scripts/run_p3_12b_frame_detector_golden_regression.sh
tb/p3_12b_frame_detector_golden_regression_tb.sv
docs/p3_12b_frame_detector_golden_regression.md
md_files/p3_12b_frame_detector_golden_regression_prompt.md
```

You may minimally modify existing script source lists to include:

```text
rtl/frame_detector.v
rtl/frame_detect_fsm.v
rtl/sliding_window_sum.v
rtl/sample_power_sq.v
```

Only if they are missing.

---

# Do NOT Modify

Do not modify unless absolutely necessary:

```text
rtl/phase3_sync_top.v
rtl/frac_cfo_frame_corrector_top.v
rtl/frame_detector.v
rtl/frame_detect_fsm.v
rtl/sliding_window_sum.v
rtl/meyr_*.v
rtl/fft256_dual_symbol_frontend.v
vectors/*
golden/*
```

If a mismatch is found, first document it. Do not patch algorithm RTL blindly.

---

# Tasks

## 1. Inspect existing regression scripts

Find existing Phase3 regression scripts, especially anything related to:

```text
P3-05C
frame detector
phase3_sync_top
golden compare
run_phase3_sync
```

Identify which one previously checked:

```text
frame_index = 41
frame_found = 1
```

Document the script and TB used.

---

## 2. Ensure modular detector files are in source list

Confirm the compile includes:

```text
rtl/sample_power_sq.v
rtl/sliding_window_sum.v
rtl/frame_detect_fsm.v
rtl/frame_detector.v
```

Do not allow production compile to depend on:

```text
rtl/unit_test/frame_detector.v
```

or any obsolete detector file.

---

## 3. Create P3-12B regression wrapper script

Create:

```text
scripts/run_p3_12b_frame_detector_golden_regression.sh
```

Behavior:

```text
--sim xsim      official if Vivado available
--sim iverilog  sanity only
```

Rules:

```text
iverilog may print SANITY_GATE only
xsim may print CI_GATE only
```

If xsim unavailable:

```text
CI_GATE: BLOCKED_XSIM_UNAVAILABLE
```

---

## 4. Create or reuse integration TB

Either reuse the existing P3-05C / Phase3 golden TB, or create:

```text
tb/p3_12b_frame_detector_golden_regression_tb.sv
```

Required checks:

```text
C1 frame_found == 1
C2 frame_index == 41
C3 frame_start_valid pulse observed
C4 slot_start_index == frame_index + peak_lag
C5 done eventually asserts
C6 no fatal/error flag
```

If exact signal names differ, map to the actual debug outputs in `phase3_sync_top.v` and `frac_cfo_frame_corrector_top.v`.

---

## 5. Diagnose mismatch if any

If frame_index is not 41, determine whether mismatch is due to:

```text
off-by-one window_start_index
threshold equality: > vs >= or < vs <=
search_base/search_len
buffer read latency
2-cycle wrapper pipeline lag
Case2 skip behavior
sample_power_sq I/Q packing
```

Do not patch unless the cause is obvious and localized.

If patched, document the exact reason.

---

## 6. Documentation

Create:

```text
docs/p3_12b_frame_detector_golden_regression.md
```

Include:

```text
- scripts/TBs used
- source list confirmation
- old detector dependency check
- observed frame_index
- observed frame_found
- slot_start relation
- pass/fail result
- any mismatch diagnosis
- remaining risks
```

---

# Pass Criteria

Complete only if:

```text
1. production source list uses modular frame_detector path
2. old/unit_test frame_detector is not used
3. regression checks frame_found
4. regression checks frame_index == 41
5. slot_start relation is checked
6. runner exists
7. docs exist
```

Official closure only if:

```text
CI_GATE: PASS under Vivado xsim
```

If only iverilog is available:

```text
SANITY_GATE: PASS
CI_GATE: BLOCKED_XSIM_UNAVAILABLE
```

---

# Final Response Format

Return:

```text
P3-12B Final Status

1. Changed Files
2. Regression Source List
3. Old Detector Dependency Check
4. Golden Checks
5. Simulation Results
6. Mismatch Diagnosis, if any
7. Remaining Risks
8. Recommended Next Step
```
