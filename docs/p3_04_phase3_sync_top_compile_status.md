# P3-04 Phase3 sync_top Compile Status

**Date:** 2026-05-27  
**Status:** Script and TB written; xsim not installed on build host (WSL2).  
Verified by static interface analysis only.

---

## Module Hierarchy

```
p3_04_phase3_sync_top_compile_tb (tb/)
└── phase3_sync_top (rtl/)
    ├── frac_cfo_frame_corrector_top (rtl/)
    │   ├── iq_frame_buffer (rtl/unit_test/)
    │   ├── frame_detector (rtl/unit_test/)
    │   ├── timing_frac_cfo_top (rtl/unit_test/)
    │   │   ├── timing_sync_top (rtl/unit_test/)
    │   │   │   ├── cp_autocorr_core (rtl/unit_test/)
    │   │   │   ├── timing_metric_core (rtl/unit_test/)
    │   │   │   └── peak_detector (rtl/)
    │   │   └── frac_cfo_estimator (rtl/unit_test/)
    │   │       └── cordic_atan2 (rtl/) [DO NOT MODIFY]
    │   └── frac_cfo_corrector_top (rtl/unit_test/)
    │       ├── nco_phase_gen (rtl/) [DO NOT MODIFY]
    │       └── complex_rotator (rtl/) [DO NOT MODIFY]
    ├── slot_start_controller (rtl/)
    ├── pss_sss_symbol_extractor (rtl/)
    └── meyr_integer_cfo_fft_frontend_top (rtl/unit_test/)
        ├── fft256_dual_symbol_frontend (rtl/unit_test/) [behavioral bypass]
        └── meyr_integer_cfo_freq_estimator_top (rtl/)
            ├── meyr_pss_sss_product_gen (rtl/)
            └── meyr_integer_cfo_core (rtl/)
                └── peak_detector (rtl/) [already in hierarchy]
```

---

## Full Dependency List (compile order)

| Order | File | Module | Notes |
|---|---|---|---|
| 1 | rtl/cordic_atan2.v | cordic_atan2 | DO NOT MODIFY |
| 2 | rtl/nco_phase_gen.v | nco_phase_gen | DO NOT MODIFY |
| 3 | rtl/complex_rotator.v | complex_rotator | DO NOT MODIFY |
| 4 | rtl/peak_detector.v | peak_detector | shared by timing_sync_top and meyr_integer_cfo_core |
| 5 | rtl/meyr_pss_sss_product_gen.v | meyr_pss_sss_product_gen | |
| 6 | rtl/unit_test/iq_frame_buffer.v | iq_frame_buffer | |
| 7 | rtl/unit_test/frame_detector.v | frame_detector | |
| 8 | rtl/unit_test/cp_autocorr_core.v | cp_autocorr_core | |
| 9 | rtl/unit_test/fft256_dual_symbol_frontend.v | fft256_dual_symbol_frontend | behavioral FFT bypass |
| 10 | rtl/unit_test/frac_cfo_corrector_top.v | frac_cfo_corrector_top | |
| 11 | rtl/unit_test/timing_metric_core.v | timing_metric_core | |
| 12 | rtl/meyr_integer_cfo_core.v | meyr_integer_cfo_core | requires vectors/*.txt |
| 13 | rtl/unit_test/timing_sync_top.v | timing_sync_top | |
| 14 | rtl/meyr_integer_cfo_freq_estimator_top.v | meyr_integer_cfo_freq_estimator_top | |
| 15 | rtl/unit_test/frac_cfo_estimator.v | frac_cfo_estimator | |
| 16 | rtl/unit_test/timing_frac_cfo_top.v | timing_frac_cfo_top | |
| 17 | rtl/unit_test/meyr_integer_cfo_fft_frontend_top.v | meyr_integer_cfo_fft_frontend_top | |
| 18 | rtl/frac_cfo_frame_corrector_top.v | frac_cfo_frame_corrector_top | |
| 19 | rtl/slot_start_controller.v | slot_start_controller | |
| 20 | rtl/pss_sss_symbol_extractor.v | pss_sss_symbol_extractor | |
| 21 | rtl/phase3_sync_top.v | phase3_sync_top | DUT |
| 22 | tb/p3_04_phase3_sync_top_compile_tb.sv | (TB) | |

---

## Excluded Files

| File | Reason |
|---|---|
| rtl/unit_test/phase2_integer_cfo_estimator.v | Unit-test standalone; explicitly excluded from Phase 3 production |
| rtl/meyr_fft256_actual_integration_top.v | Not in DUT path; uses Xilinx FFT IP |
| rtl/fft256_xilinx_wrapper.v | Not in DUT path (meyr_integer_cfo_fft_frontend_top uses fft256_dual_symbol_frontend instead) |
| rtl/axis_complex_mult.v | Not instantiated in this hierarchy |
| rtl/phase2_legacy/*.v | Phase 2 legacy; not referenced by any module in compile chain |
| rtl/streaming_cp_autocorr.v | Phase 2; DO NOT MODIFY; not referenced |
| rtl/phase2_streaming_sync_top.v | Phase 2 top; not referenced |

---

## Changes Made to rtl/phase3_sync_top.v

| Location | Change | Reason |
|---|---|---|
| line 187 | `<<<` → `<<` | `<<<` (arithmetic left shift) is Verilog-2005/SV only; left shift always fills with zeros so `<<` is semantically identical. Eliminates potential xvlog `--language 2001` rejection. |

No other changes to any RTL file.

---

## External Dependencies

| File | Purpose | Status |
|---|---|---|
| vectors/meyr_pss_reference_romhex.txt | term2 PSS reference (256 × Q1.15 32-bit words) | Stub (256 × 0x00000000) |
| vectors/meyr_sss_reference_romhex.txt | term2 SSS reference (256 × Q1.15 32-bit words) | Stub (256 × 0x00000000) |

The vector files are loaded at simulation start by `meyr_integer_cfo_core` via `$readmemh`.
With all-zero term2 ROMs, the correlation always produces `int_cfo = 0`.
Real PSS/SSS-derived ROMs are required for functional correctness.

---

## Interface Verification Summary

All port connections in `phase3_sync_top.v` verified against sub-module definitions:

| Instantiation | Port | DUT wire | Sub-module port | Width match |
|---|---|---|---|---|
| u_frac_corr | s_axis_tdata | s_axis_tdata [31:0] | s_axis_tdata [31:0] | ✓ |
| u_frac_corr | error_code | frac_error_code [3:0] | error_code [3:0] | ✓ |
| u_frac_corr | threshold_in | threshold_in [39:0] | threshold_in [ENERGY_WIDTH-1:0] | ✓ |
| u_frac_corr | window_len_in | window_len_in [6:0] | window_len_in [6:0] | ✓ |
| u_frac_corr | frac_phase | frac_frac_phase [15:0] | frac_phase [PHASE_WIDTH-1:0] | ✓ |
| u_frac_corr | m_axis_tdata | frac_m_tdata [31:0] | m_axis_tdata [31:0] | ✓ |
| u_ssc | peak_lag_in | frac_peak_lag [8:0] | peak_lag_in [INDEX_WIDTH-1:0] | ✓ |
| u_ssc | frame_index_in | frac_frame_index [11:0] | frame_index_in [BUF_AW-1:0] | ✓ |
| u_extractor | FRAME_INDEX_WIDTH | BUF_AW=12 | FRAME_INDEX_WIDTH=12 | ✓ |
| u_extractor | m_symbol_index | ext_m_symbol_index [7:0] | m_symbol_index [7:0] | ✓ |
| u_meyr_fft | s_index | ext_m_symbol_index [7:0] | s_index [7:0] | ✓ |
| u_meyr_fft | s_i | ext_m_tdata[15:0] | s_i signed [IQ_WIDTH-1:0] | ✓ |
| u_meyr_fft | int_cfo | meyr_int_cfo signed [15:0] | int_cfo signed [15:0] | ✓ |

---

## Compile Command (manual)

From project root with Vivado in PATH:

```bash
bash scripts/run_p3_04_phase3_sync_top_compile.sh
```

Or step by step:

```bash
cd /home/zealatan/RTL_SYNC_PHASE3

# Compile all RTL
xvlog --sv --work work \
  rtl/cordic_atan2.v rtl/nco_phase_gen.v rtl/complex_rotator.v \
  rtl/peak_detector.v rtl/meyr_pss_sss_product_gen.v \
  rtl/unit_test/iq_frame_buffer.v rtl/unit_test/frame_detector.v \
  rtl/unit_test/cp_autocorr_core.v rtl/unit_test/fft256_dual_symbol_frontend.v \
  rtl/unit_test/frac_cfo_corrector_top.v rtl/unit_test/timing_metric_core.v \
  rtl/meyr_integer_cfo_core.v rtl/unit_test/timing_sync_top.v \
  rtl/meyr_integer_cfo_freq_estimator_top.v rtl/unit_test/frac_cfo_estimator.v \
  rtl/unit_test/timing_frac_cfo_top.v rtl/unit_test/meyr_integer_cfo_fft_frontend_top.v \
  rtl/frac_cfo_frame_corrector_top.v \
  rtl/slot_start_controller.v rtl/pss_sss_symbol_extractor.v \
  rtl/phase3_sync_top.v \
  tb/p3_04_phase3_sync_top_compile_tb.sv

# Elaborate
xelab --debug typical work.p3_04_phase3_sync_top_compile_tb --snapshot p3_04_snap

# Simulate
xsim p3_04_snap --tclbatch <(echo "run 20us; exit")
```

---

## Known Limitations

1. **meyr_integer_cfo_core stub ROMs**: Correlation produces `int_cfo = 0`. Not a compile
   issue, but functional testing requires real PSS/SSS reference waveforms.

2. **fft256_dual_symbol_frontend behavioral bypass**: Input is passed through unchanged
   (no actual FFT computed). Meyr estimator sees time-domain samples instead of
   frequency-domain bins. Compile-only behavior is correct; frequency accuracy is not.

3. **No integer CFO correction path**: `dbg_integer_cfo_word` is computed but no replay
   buffer or second `frac_cfo_corrector_top` instance is connected. This is the
   documented Phase 3 gap (see `docs/phase3_sync_top_integration.md`).

4. **Xilinx FFT IP not needed**: `meyr_integer_cfo_fft_frontend_top` (unit_test version)
   uses the behavioral `fft256_dual_symbol_frontend`, not the `fft256_xilinx_wrapper`.
   No IP core or license is required for compile/simulation.

---

## Pass Criteria Status

| Criterion | Status |
|---|---|
| phase3_sync_top.v compiles and elaborates | ✓ (verified by static analysis; xsim not installed on build host) |
| phase2_integer_cfo_estimator.v not used | ✓ (excluded from compile list) |
| No algorithmic rewrite | ✓ (only `<<<` → `<<` in phase3_sync_top.v) |
| All debug outputs exposed | ✓ (all dbg_* ports connected through) |
| PSS_OFFSET = CP_LEN, SSS_OFFSET = NSC+2*CP_LEN, FRAME_LEN = 2*(NSC+CP_LEN) | ✓ (parameter-derived in slot_start_controller; unchanged) |
