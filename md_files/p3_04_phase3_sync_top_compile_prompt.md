# P3-04 — Phase3 Sync Top Compile / Interface Closure

**Date:** 2026-05-27  
**Role:** Claude-B — P3-04 Phase3 Top Compile / Interface Closure Owner

---

## Full Prompt (as received)

> You are working in /home/zealatan/RTL_SYNC_PHASE3
> ROLE: Claude-B — P3-04 Phase3 Top Compile / Interface Closure Owner
>
> MANDATORY ARCHIVAL RULE: create md_files/p3_04_phase3_sync_top_compile_prompt.md before making changes.
>
> CONTEXT: rtl/phase3_sync_top.v already exists, instantiates:
>   - frac_cfo_frame_corrector_top
>   - slot_start_controller
>   - pss_sss_symbol_extractor
>   - meyr_integer_cfo_fft_frontend_top (from unit_test/)
>   - excludes phase2_integer_cfo_estimator.v
>
> GOAL: Make phase3_sync_top.v compile cleanly under xsim with all required dependencies.
>
> TASKS: Inspect all RTL files listed; identify module/port mismatches; create
> compile-only TB; create compile script; fix only interface/compile issues in
> phase3_sync_top.v; create compile status doc.
>
> DO NOT MODIFY: ref/, meyr core math, cordic_atan2.v, complex_rotator.v,
> nco_phase_gen.v, streaming_cp_autocorr.v, phase2_integer_cfo_estimator.v

---

## My Interpretation

Goal is compile + elaboration closure only — no algorithm changes.
The existing `phase3_sync_top.v` (written in Step 03) has correct port mappings
but uses the `<<<` operator which is Verilog-2005/SV-only and requires `--sv` mode.

The primary gap preventing compile success is:
1. No compile script listing all required RTL dependencies in bottom-up order.
2. No TB file for elaboration.
3. `meyr_integer_cfo_core.v` requires stub vector files (`vectors/*.txt`) for `$readmemh`.
4. All submodule dependencies scattered across `rtl/` and `rtl/unit_test/` — must be
   explicitly listed since there is no project file.

---

## Files Inspected

| File | Module | Notes |
|---|---|---|
| rtl/phase3_sync_top.v | phase3_sync_top | DUT — orchestration top |
| rtl/frac_cfo_frame_corrector_top.v | frac_cfo_frame_corrector_top | Steps 1-4 |
| rtl/slot_start_controller.v | slot_start_controller | slotStartIndex latch |
| rtl/pss_sss_symbol_extractor.v | pss_sss_symbol_extractor | PSS/SSS windowing |
| rtl/unit_test/meyr_integer_cfo_fft_frontend_top.v | meyr_integer_cfo_fft_frontend_top | Step 5 frontend |
| rtl/meyr_integer_cfo_freq_estimator_top.v | meyr_integer_cfo_freq_estimator_top | Meyr estimator |
| rtl/meyr_fft256_actual_integration_top.v | meyr_fft256_actual_integration_top | NOT in DUT path |
| rtl/fft256_xilinx_wrapper.v | fft256_xilinx_wrapper | NOT in DUT path |
| rtl/meyr_integer_cfo_core.v | meyr_integer_cfo_core | Correlation core; uses $readmemh |
| rtl/meyr_pss_sss_product_gen.v | meyr_pss_sss_product_gen | term1 computation |
| rtl/unit_test/fft256_dual_symbol_frontend.v | fft256_dual_symbol_frontend | Behavioral FFT bypass |
| rtl/unit_test/iq_frame_buffer.v | iq_frame_buffer | AXI-Stream capture buffer |
| rtl/unit_test/frame_detector.v | frame_detector | Sliding-window energy det |
| rtl/unit_test/timing_frac_cfo_top.v | timing_frac_cfo_top | CP autocorr + frac CFO |
| rtl/unit_test/timing_sync_top.v | timing_sync_top | Autocorr + metric + peak |
| rtl/unit_test/cp_autocorr_core.v | cp_autocorr_core | Van de Beek CP autocorr |
| rtl/unit_test/timing_metric_core.v | timing_metric_core | Timing metric generator |
| rtl/unit_test/frac_cfo_estimator.v | frac_cfo_estimator | CORDIC atan2 wrapper |
| rtl/unit_test/frac_cfo_corrector_top.v | frac_cfo_corrector_top | NCO + complex_rotator |
| rtl/peak_detector.v | peak_detector | Streaming argmax |
| rtl/cordic_atan2.v | cordic_atan2 | CORDIC atan2 (DO NOT MODIFY) |
| rtl/complex_rotator.v | complex_rotator | IQ rotator (DO NOT MODIFY) |
| rtl/nco_phase_gen.v | nco_phase_gen | NCO (DO NOT MODIFY) |

---

## Interface Analysis — Findings

### phase3_sync_top.v instantiations

| Instance | Module | Port Issues Found |
|---|---|---|
| u_frac_corr | frac_cfo_frame_corrector_top | None — all widths match |
| u_ssc | slot_start_controller | None — all widths match |
| u_extractor | pss_sss_symbol_extractor | None — all widths match |
| u_meyr_fft | meyr_integer_cfo_fft_frontend_top | None — all widths match |

### Key interface verification points

- `frac_cfo_frame_corrector_top`: `s_axis_tdata [31:0]` matches `2*IQ_WIDTH = 32` ✓
- `frac_cfo_frame_corrector_top`: `error_code [3:0]` matches `frac_error_code [3:0]` ✓
- `slot_start_controller`: `peak_lag_in [INDEX_WIDTH-1:0]` matches `frac_peak_lag` ✓
- `pss_sss_symbol_extractor`: `FRAME_INDEX_WIDTH = BUF_AW = 12` ✓
- `meyr_integer_cfo_fft_frontend_top`: `s_index [7:0]` matches `ext_m_symbol_index [7:0]` ✓
- `meyr_integer_cfo_fft_frontend_top`: `int_cfo signed [15:0]` matches `meyr_int_cfo signed [15:0]` ✓

### Single compile issue identified

`phase3_sync_top.v` uses the `<<<` operator (arithmetic left shift, IEEE 1800 / Verilog-2005).
This is identical to `<<` for left shifts (both fill zeros on right). Fixed by replacing
`<<<` with `<<` so the file compiles cleanly even in strict Verilog-2001 mode.

### meyr_integer_cfo_core $readmemh dependency

`meyr_integer_cfo_core.v` calls `$readmemh` at simulation start for:
- `vectors/meyr_pss_reference_romhex.txt`
- `vectors/meyr_sss_reference_romhex.txt`

These paths are relative to the xsim working directory. Stub files (256 × `00000000`)
created at those paths. Simulation will produce `int_cfo = 0` (all-zeros correlation),
which is acceptable for compile-only validation.

---

## Planned Modifications

1. `md_files/p3_04_phase3_sync_top_compile_prompt.md` — this file (mandatory archive)
2. `vectors/meyr_pss_reference_romhex.txt` — stub PSS ROM (256 zero entries)
3. `vectors/meyr_sss_reference_romhex.txt` — stub SSS ROM (256 zero entries)
4. `rtl/phase3_sync_top.v` — replace `<<<` with `<<` (semantically identical for left shift)
5. `tb/p3_04_phase3_sync_top_compile_tb.sv` — minimal compile/elaborate TB
6. `scripts/run_p3_04_phase3_sync_top_compile.sh` — full compile + elab + run script
7. `docs/p3_04_phase3_sync_top_compile_status.md` — dependency list + status

---

## RTL Dependency Tree (verified against current source)

```
phase3_sync_top.v
├── frac_cfo_frame_corrector_top.v
│   ├── unit_test/iq_frame_buffer.v          (self-contained)
│   ├── unit_test/frame_detector.v           (self-contained)
│   ├── unit_test/timing_frac_cfo_top.v
│   │   ├── unit_test/timing_sync_top.v
│   │   │   ├── unit_test/cp_autocorr_core.v (self-contained, uses reg arrays)
│   │   │   ├── unit_test/timing_metric_core.v (self-contained)
│   │   │   └── peak_detector.v              (self-contained)
│   │   └── unit_test/frac_cfo_estimator.v
│   │       └── cordic_atan2.v               (DO NOT MODIFY)
│   └── unit_test/frac_cfo_corrector_top.v
│       ├── nco_phase_gen.v                  (DO NOT MODIFY)
│       └── complex_rotator.v                (DO NOT MODIFY)
├── slot_start_controller.v                  (self-contained)
├── pss_sss_symbol_extractor.v               (self-contained)
└── unit_test/meyr_integer_cfo_fft_frontend_top.v
    ├── unit_test/fft256_dual_symbol_frontend.v (behavioral bypass, self-contained)
    └── meyr_integer_cfo_freq_estimator_top.v
        ├── meyr_pss_sss_product_gen.v       (self-contained)
        └── meyr_integer_cfo_core.v
            ├── peak_detector.v              (already compiled above)
            └── $readmemh vectors/*.txt      (stub files created)
```

NOT in compile path (excluded):
- rtl/unit_test/phase2_integer_cfo_estimator.v
- rtl/meyr_fft256_actual_integration_top.v
- rtl/fft256_xilinx_wrapper.v
- rtl/axis_complex_mult.v
- rtl/phase2_legacy/ (all files)

---

## Compile Order (bottom-up)

1. rtl/cordic_atan2.v
2. rtl/nco_phase_gen.v
3. rtl/complex_rotator.v
4. rtl/peak_detector.v
5. rtl/meyr_pss_sss_product_gen.v
6. rtl/unit_test/iq_frame_buffer.v
7. rtl/unit_test/frame_detector.v
8. rtl/unit_test/cp_autocorr_core.v
9. rtl/unit_test/fft256_dual_symbol_frontend.v
10. rtl/unit_test/frac_cfo_corrector_top.v
11. rtl/unit_test/timing_metric_core.v
12. rtl/meyr_integer_cfo_core.v
13. rtl/unit_test/timing_sync_top.v
14. rtl/meyr_integer_cfo_freq_estimator_top.v
15. rtl/unit_test/frac_cfo_estimator.v
16. rtl/unit_test/timing_frac_cfo_top.v
17. rtl/unit_test/meyr_integer_cfo_fft_frontend_top.v
18. rtl/frac_cfo_frame_corrector_top.v
19. rtl/slot_start_controller.v
20. rtl/pss_sss_symbol_extractor.v
21. rtl/phase3_sync_top.v
22. tb/p3_04_phase3_sync_top_compile_tb.sv

---

## Final Summary

- No algorithmic rewrites performed.
- Only change to rtl/phase3_sync_top.v: `<<<` → `<<` (arithmetic left-shift → logical
  left-shift, identical semantics, removes Verilog-2005/SV dependency).
- All debug outputs remain exposed.
- PSS_OFFSET = CP_LEN = 32, SSS_OFFSET = NSC + 2*CP_LEN = 320,
  FRAME_LEN = 2*(NSC+CP_LEN) = 576 — all parameter-derived, unchanged.
- phase2_integer_cfo_estimator.v is excluded from compile chain.
- Stub ROM files created so $readmemh succeeds at simulation start.
- Remaining interface risk: meyr_integer_cfo_core correlation against all-zero
  term2 ROM will produce int_cfo = 0 (wrong algorithm result, acceptable for
  compile-only validation; real ROMs needed for functional testing).
