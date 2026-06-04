# Claude Code Prompt — P3-24A Restore Production CP Autocorrelator Path

## Working Directory

`/home/zealatan/RTL_SYNC_PHASE3`

## Important Current RTL Location

The production DUT RTL files are currently under:

```text
/home/zealatan/RTL_SYNC_PHASE3/rtl/DUT
```

Do NOT assume the old flat `rtl/` path is the production source directory.

Current production files include:

```text
rtl/DUT/streaming_cp_autocorr.v
rtl/DUT/timing_frac_cfo_top.v
rtl/DUT/timing_metric_core.v
rtl/DUT/frac_cfo_frame_corrector_top.v
rtl/DUT/phase3_sync_top.v
rtl/DUT/phase3_sync_axis_dma_wrapper.v
```

---

# Context

A structural issue was found:

The current `timing_frac_cfo_top` / Phase3 DUT path may still be using or expecting the old/simple `cp_autocorr_core` style module from earlier unit-test work.

This is wrong for production.

The production CP autocorrelation block must use:

```text
rtl/DUT/streaming_cp_autocorr.v
```

---

# Objective

Audit, compare, and restore the production timing path so that the Phase3 DUT uses:

```text
streaming_cp_autocorr.v
```

instead of any obsolete/unit-test CP autocorrelation implementation.

Target path:

```text
phase3_sync_axis_dma_wrapper
→ phase3_sync_top
→ frac_cfo_frame_corrector_top
→ timing_frac_cfo_top
→ streaming_cp_autocorr
```

No production dependency on:

```text
rtl/unit_test/cp_autocorr_core.v
cp_autocorr_core.v
```

---

# Mandatory Archival Rule

Before making code changes, save this prompt verbatim to:

```text
md_files/p3_24a_restore_streaming_cp_autocorr_prompt.md
```

---

# Allowed Modifications

You may modify/create:

```text
rtl/DUT/timing_frac_cfo_top.v
rtl/DUT/frac_cfo_frame_corrector_top.v
rtl/DUT/phase3_sync_top.v              only if required for signal plumbing
scripts/run_p3_24a_cp_autocorr_restore.sh
tb/p3_24a_cp_autocorr_restore_tb.sv
docs/p3_24a_cp_autocorr_restore.md
md_files/p3_24a_restore_streaming_cp_autocorr_prompt.md
```

You may update compile source lists / runner scripts that incorrectly point to old paths.

---

# Do NOT Modify

Do not modify unless a clearly documented bug is found:

```text
rtl/DUT/streaming_cp_autocorr.v
rtl/DUT/frame_detector.v
rtl/DUT/frame_detect_fsm.v
rtl/DUT/sliding_window_sum.v
rtl/DUT/sample_power_sq.v
rtl/DUT/meyr_*.v
rtl/DUT/fft256_*.v
rtl/DUT/phase3_axi_lite_regs.v
rtl/DUT/phase3_sync_axis_dma_wrapper.v
```

Do not change golden vectors.

Do not silently relax test tolerances.

---

# Tasks

## 1. Audit Current CP Autocorr Dependency

Search:

```bash
grep -R "cp_autocorr_core\|streaming_cp_autocorr" -n rtl tb scripts docs
```

Report:

```text
- Which module is instantiated by timing_frac_cfo_top
- Which source files compile cp_autocorr_core
- Which source files compile streaming_cp_autocorr
- Whether production scripts still reference rtl/unit_test/cp_autocorr_core.v
```

Production path must not depend on unit-test CP autocorr.

---

## 2. Inspect streaming_cp_autocorr Interface

Open:

```text
rtl/DUT/streaming_cp_autocorr.v
```

Document:

```text
- input ports
- output ports
- latency
- valid/done semantics
- expected CP_LEN / NSC / window behavior
- output correlation format
```

Compare against what `timing_frac_cfo_top.v` expects.

---

## 3. Integrate streaming_cp_autocorr

Preferred final structure:

```verilog
streaming_cp_autocorr u_cp_autocorr (...);
```

inside:

```text
rtl/DUT/timing_frac_cfo_top.v
```

If port mismatch is too large, create a small adapter, but name it clearly and document it:

```text
rtl/DUT/cp_autocorr_streaming_adapter.v
```

Do not mix old and new CP autocorr in production.

---

## 4. Regression Expectations

After replacement, rerun key known checks.

Expected values:

```text
frame_found = 1
frame_index ≈ 41
peak_lag ≈ 23
slot_start ≈ 64
frac_cfo_valid = 1
integer_cfo_valid = 1
output_count = 576
tlast at 575
```

If values shift due to true streaming CP autocorr latency, document the exact reason.

---

## 5. Create Focused Restoration TB

Create:

```text
tb/p3_24a_cp_autocorr_restore_tb.sv
```

Verify:

```text
C1 frame_found
C2 frame_index near expected
C3 peak_lag near expected
C4 slot_start near expected
C5 frac_cfo_valid
C6 integer_cfo_valid
C7 output_count == 576
C8 tlast at 575
C9 no old cp_autocorr_core dependency in compile log/source list
```

---

## 6. Runner

Create:

```text
scripts/run_p3_24a_cp_autocorr_restore.sh
```

The runner must compile production DUT files from:

```text
rtl/DUT/
```

Gate output:

```text
SANITY_CP_AUTOCORR_RESTORE_GATE: PASS
SANITY_CP_AUTOCORR_RESTORE_GATE: FAIL
```

If xsim is unavailable, do not claim official CI PASS.

---

## 7. Documentation

Create:

```text
docs/p3_24a_cp_autocorr_restore.md
```

Include:

```text
- current bug summary
- old dependency found
- new streaming_cp_autocorr interface
- integration method
- changed files
- regression result
- remaining risks
```

---

# Pass Criteria

Complete only if:

```text
1. Production timing path uses rtl/DUT/streaming_cp_autocorr.v
2. Production source list no longer uses old/unit_test cp_autocorr_core for Phase3 DUT
3. Focused TB passes
4. Known frame/slot/CFO/output checks pass or any shift is documented
5. Runner exists
6. Documentation exists
7. No unrelated FFT/Meyr/replay/frame_detector RTL was modified
```

---

# Final Response Format

```text
P3-24A Final Status

1. Changed Files
2. CP Autocorr Dependency Audit
3. streaming_cp_autocorr Interface Summary
4. Integration Method
5. Regression Results
6. Gate Result
7. Remaining Risks
8. Recommended Next Step
```
