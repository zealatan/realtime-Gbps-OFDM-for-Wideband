# Claude Code Prompt — Session A / P3-12C Full Phase3 Regression Closure

## Working Directory
`/home/zealatan/RTL_SYNC_PHASE3`

## Mandatory Archival Rule
Before making any code change, save this prompt verbatim to:

`md_files/session_A_p3_12c_full_phase3_regression_prompt.md`

Create `md_files/` if it does not exist.

---

# Session Naming

This is **Claude Session A**.

Session A owns:

```text
Frame detector
Phase3 top regression
C/golden frame/slot timing equivalence
source-list hygiene
official xsim closure when available
```

---

# Current Known Status

P3-12A modular frame detector refactor completed:

```text
rtl/frame_detector.v
├─ sample_power_sq
├─ sliding_window_sum
└─ frame_detect_fsm
```

P3-12B golden regression completed:

```text
frame_index observed = 41  golden=41
peak_lag    observed = 23
slot_start  observed = 64  golden=64
done asserted at cycle 105325
error_code = 0
7/7 PASS
SANITY_GATE: PASS (iverilog)
CI_GATE: BLOCKED_XSIM_UNAVAILABLE
```

Also fixed:

```text
8 wrong rtl/unit_test/ paths -> rtl/
rtl/unit_test/frame_detector.v is NOT referenced in production compile path
```

---

# Objective

Create a broader Phase3 regression closure step around the new modular frame detector.

The goal is to prove that replacing the missing/obsolete frame detector did not break downstream Phase3 behavior.

Required checks:

```text
frame_found = 1
frame_index = 41
peak_lag = 23
slot_start_index = 64
error_code = 0
PSS/SSS extractor path still reaches expected activity
Meyr path still reaches done/valid where applicable
no obsolete frame_detector dependency exists
```

---

# Allowed Modifications

You may create/modify:

```text
scripts/run_session_A_p3_12c_full_phase3_regression.sh
tb/session_A_p3_12c_full_phase3_regression_tb.sv
docs/session_A_p3_12c_full_phase3_regression.md
md_files/session_A_p3_12c_full_phase3_regression_prompt.md
```

You may minimally fix script source lists if they still reference:

```text
rtl/unit_test/*
frame_detector_reuse
old frame_detector paths
obsolete sample_power_sq path
```

---

# Do NOT Modify

Do not modify algorithm RTL unless absolutely necessary:

```text
rtl/phase3_sync_top.v
rtl/frac_cfo_frame_corrector_top.v
rtl/frame_detector.v
rtl/frame_detect_fsm.v
rtl/sliding_window_sum.v
rtl/sample_power_sq.v
rtl/meyr_*.v
rtl/fft256_dual_symbol_frontend.v
rtl/phase3_sync_axis_dma_wrapper.v
rtl/phase3_axi_lite_regs.v
```

If any mismatch appears, document first. Do not patch blindly.

---

# Tasks

## 1. Audit all Phase3 run scripts for stale source paths

Run:

```bash
grep -R "unit_test/frame_detector\|rtl/unit_test\|frame_detector_reuse" -n scripts tb rtl docs || true
```

Required production path:

```text
rtl/sample_power_sq.v
rtl/sliding_window_sum.v
rtl/frame_detect_fsm.v
rtl/frame_detector.v
```

Forbidden production dependency:

```text
rtl/unit_test/frame_detector.v
```

## 2. Build full Phase3 regression runner

Create:

```text
scripts/run_session_A_p3_12c_full_phase3_regression.sh
```

Behavior:

```text
--sim iverilog  -> SANITY_GATE only
--sim xsim      -> CI_GATE only
```

If Vivado/xsim unavailable:

```text
CI_GATE: BLOCKED_XSIM_UNAVAILABLE
```

Do not allow informational text to cause false PASS. Anchor grep patterns:

```bash
grep -qE "^CI_GATE: PASS$"
grep -qE "^SANITY_GATE: PASS"
```

## 3. Create or reuse integration TB

Create or wrap existing TB as:

```text
tb/session_A_p3_12c_full_phase3_regression_tb.sv
```

Required checks:

```text
C1 frame_found == 1
C2 frame_index == 41
C3 peak_lag == 23
C4 slot_start_index == 64
C5 slot_start_index == frame_index + peak_lag
C6 done eventually asserts
C7 error_code == 0
C8 no obsolete frame_detector instance path used
C9 PSS/SSS extraction reaches valid/done activity if exposed
C10 Meyr done/valid reaches expected state if exposed
```

If exact signals are not exposed, use hierarchy access and document the path.

## 4. Compare with P3-12B result

Confirm the new regression preserves:

```text
frame_index = 41
slot_start_index = 64
```

If mismatch occurs, diagnose:

```text
off-by-one window_start_index
threshold equality
search_base/search_len
buffer latency
sample_power_sq packing
case2 skip behavior
source-list contamination
```

## 5. Documentation

Create:

```text
docs/session_A_p3_12c_full_phase3_regression.md
```

Include:

```text
source-list audit result
old detector dependency check
checks performed
observed frame_index/peak_lag/slot_start
simulation result
xsim availability
remaining risks
```

---

# Pass Criteria

Complete if:

```text
1. runner exists
2. TB exists or documented existing TB reused
3. production source-list uses modular detector
4. no rtl/unit_test/frame_detector dependency remains
5. frame_index=41 verified
6. slot_start=64 verified
7. docs exist
```

Official closure only if:

```text
CI_GATE: PASS
```

under Vivado xsim.

---

# Final Response Format

Return:

```text
Session A / P3-12C Final Status

1. Changed Files
2. Source-List Audit
3. Old Detector Dependency Check
4. Full Phase3 Regression Checks
5. Simulation Results
6. Mismatch Diagnosis, if any
7. Remaining Risks
8. Recommended Next Step
```
