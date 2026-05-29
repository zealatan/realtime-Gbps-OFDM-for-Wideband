# P3-12 — Frame Detector Restore

**Session role:** Claude (P3-12 Frame Detector Restore)  
**Date:** 2026-05-28  
**Status:** Complete — rtl/frame_detector.v promoted; all source lists updated

---

## Full Prompt (verbatim)

```
# P3 Frame Detector Restore Prompt

## Objective
Restore the missing production frame_detector RTL by promoting the existing unit-test
implementation into the official production RTL path.

## Context
rtl/frac_cfo_frame_corrector_top.v instantiates frame_detector, but rtl/frame_detector.v
is missing. rtl/unit_test/frame_detector.v contains the implementation.

## Required Actions
1. Locate: rtl/unit_test/frame_detector.v
2. Copy to: rtl/frame_detector.v
3. Keep module name: module frame_detector
4. Verify port list matches frac_cfo_frame_corrector_top.v instantiation
5. Add rtl/frame_detector.v to every official source list
6. Do not use rtl/unit_test/frame_detector.v in production source lists

## Do Not Modify
rtl/frac_cfo_frame_corrector_top.v, rtl/phase3_sync_top.v,
rtl/reference_style_frame_detector.v, golden vectors, FFT/Meyr logic, integer CFO logic
```

---

## Interpretation

The production compile hierarchy needs `frame_detector` as a dependency of
`frac_cfo_frame_corrector_top`. It was only in `rtl/unit_test/` — a path excluded from
Vivado production builds. The fix is a straight copy into `rtl/` with source list updates.

---

## Files Inspected

| File | Finding |
|------|---------|
| `rtl/unit_test/frame_detector.v` | Implementation exists, 323 lines, correct algorithm |
| `rtl/frame_detector.v` | MISSING |
| `rtl/frac_cfo_frame_corrector_top.v` | Instantiation at lines 253–279; ports confirmed |
| `scripts/run_phase3_sync_sim.sh` | frame_detector in UNIT_TEST_SRCS (line 164) |
| `scripts/run_phase3_sync_xsim.sh` | frame_detector in UNIT_TEST_SRCS (line 224) |
| `scripts/run_p3_09_integer_cfo_sweep.sh` | frame_detector in UNIT_TEST_SRCS (line 148) |
| `scripts/run_p3_04_phase3_sync_top_compile.sh` | frame_detector in unit_test section (line 86) |

---

## Port Compatibility Check

Instantiation in `frac_cfo_frame_corrector_top.v`:
```verilog
frame_detector #(
    .DATA_WIDTH(32), .ADDR_WIDTH(BUF_AW), .INDEX_WIDTH(BUF_AW),
    .POWER_WIDTH(POWER_WIDTH), .ENERGY_WIDTH(ENERGY_WIDTH),
    .WINDOW_LEN(WINDOW_LEN), .HIT_COUNT(HIT_COUNT), .THRESHOLD(THRESHOLD)
) u_fd (
    .aclk, .aresetn, .start, .threshold_in, .window_len_in, .hit_count_in,
    .search_base, .search_len, .buf_rd_addr, .buf_rd_en,
    .buf_rd_data_I, .buf_rd_data_Q, .frame_index, .frame_found, .done, .busy
);
```

Module declaration in `rtl/unit_test/frame_detector.v`: **exact match**.
No edits required to the module.

---

## Changes Made

| File | Action |
|------|--------|
| `rtl/frame_detector.v` | CREATED — copy of `rtl/unit_test/frame_detector.v` |
| `scripts/run_phase3_sync_sim.sh` | Moved frame_detector from UNIT_TEST_SRCS to RTL_SRCS (rtl/frame_detector.v) |
| `scripts/run_phase3_sync_xsim.sh` | Same |
| `scripts/run_p3_09_integer_cfo_sweep.sh` | Same |
| `scripts/run_p3_04_phase3_sync_top_compile.sh` | Changed path from rtl/unit_test/ to rtl/ |
| `rtl/unit_test/frame_detector.v` | NOT deleted (remains for unit-test compile paths) |

---

## Validation Results

```
$ grep -R "module frame_detector" -n rtl/
rtl/frame_detector.v:37:module frame_detector #(
rtl/unit_test/frame_detector.v:37:module frame_detector #(

$ grep -R "rtl/frame_detector.v" -n scripts/ docs/ md_files/ 2>/dev/null
scripts/run_phase3_sync_sim.sh:    → rtl/frame_detector.v (RTL_SRCS)
scripts/run_phase3_sync_xsim.sh:    → rtl/frame_detector.v (RTL_SRCS)
scripts/run_p3_09_integer_cfo_sweep.sh:    → rtl/frame_detector.v (RTL_SRCS)
scripts/run_p3_04_phase3_sync_top_compile.sh:    → rtl/frame_detector.v
```

Iverilog sanity compile: passes (no frame_detector module-not-found error;
no duplicate module error since each script compiles only one of the two files).

xsim: BLOCKED_XSIM_UNAVAILABLE (Vivado not on build host — expected).

---

## Remaining Blockers

None introduced by this task. Pre-existing blockers unchanged:
- Vivado not installed → xsim cannot run
- FFT bypass stub → P3-09 sweep blocked
