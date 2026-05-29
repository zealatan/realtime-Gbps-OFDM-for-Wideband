# Phase 3 — Golden Compare Status (P3-05)

**Date:** 2026-05-27  
**DUT:** `rtl/phase3_sync_top.v`  
**Scope:** RTL simulation only. No FPGA, Vivado implementation, DMA, or board.

---

## Summary

This document records the state of the Phase 3 golden comparison flow after the P3-05
verification update session. All infrastructure scripts have been updated to target
`phase3_sync_top.v` instead of the legacy `phase2_streaming_sync_top.v`.

---

## Changed Files

| File | Change |
|---|---|
| `md_files/p3_05_phase3_golden_compare_prompt.md` | Mandatory archive (created) |
| `scripts/golden_dump.c` | Added PSS_START and SSS_START fields to output |
| `tb/phase3_sync_reference_compare_tb.sv` | Complete rewrite: DUT → phase3_sync_top, CSV output, new key names |
| `scripts/compare_golden_rtl.py` | Complete rewrite: new tolerances, new RTL keys, integer CFO informational |
| `scripts/run_phase3_sync_sim.sh` | Complete rewrite: correct source list, xsim support, CI GATE |
| `docs/p3_05_phase3_golden_compare_status.md` | This file (created) |

---

## Golden Dump Fields

Produced by `scripts/golden_dump.c` → `golden/phase3_golden_values.txt`:

| Key | C Source | Type |
|---|---|---|
| `DETECTION_STATUS` | frame_detector() success flag | int (0 or 1) |
| `FRAME_START` | frame_detector() return value | int (sample index) |
| `PEAK_INDEX_AUTO` | argmax(metric[0..NSC-1]) | int (lag offset) |
| `SLOT_START_INDEX` | peakIndexAuto + frameStart | int (absolute sample index) |
| `AUTOCORR_I_AT_PEAK` | P_I[peakIndexAuto] | float |
| `AUTOCORR_Q_AT_PEAK` | P_Q[peakIndexAuto] | float |
| `ENERGY_AT_PEAK` | E[peakIndexAuto] | float |
| `METRIC_AT_PEAK` | 2\|P\|−E at peak | float |
| `FRAC_CFO_OFFSET` | −atan2(P_Q, P_I)/(2π) | float ∈ [−0.5, +0.5] |
| `PSS_START` *(new)* | CP_LEN = 32 | int (constant) |
| `SSS_START` *(new)* | 2×CP_LEN + NSC = 320 | int (constant) |

---

## RTL Dump Fields

Produced by `tb/phase3_sync_reference_compare_tb.sv`:

### `logs/phase3_sync_rtl_dump.csv`

Per-event CSV trace. One row per clock cycle where at least one valid/done signal is high.

| Column | Source |
|---|---|
| `cycle` | Simulation clock count |
| `frame_start_valid` | `dbg_frame_start_valid` |
| `frame_start_index` | `dbg_frame_start_index` (BUF_AW=12 bits) |
| `peak_valid` | `dbg_peak_valid` |
| `peak_index` | `dbg_peak_index` (INDEX_WIDTH=9 bits) |
| `slot_start_valid` | `dbg_slot_start_valid` |
| `slot_start_index` | `dbg_slot_start_index` |
| `frac_cfo_valid` | `dbg_frac_cfo_valid` |
| `frac_cfo_word` | `dbg_frac_cfo_word` (Q1.15 signed, PHASE_WIDTH=16 bits) |
| `pss_start` | `dbg_pss_start` (= CP_LEN = 32, constant) |
| `sss_start` | `dbg_sss_start` (= 2×CP_LEN+NSC = 320, constant) |
| `integer_cfo_valid` | `dbg_integer_cfo_valid` |
| `integer_cfo_word` | `dbg_integer_cfo_word` (NCO step word, 32-bit signed) |
| `done` | `done_out` (phase3_sync_top FSM completion) |
| `error_code` | `error_code_out` |

### `sim_out/rtl_results.txt`

Key=value summary for `compare_golden_rtl.py`.

| Key | Description |
|---|---|
| `DETECTION_STATUS` | 1 if done fired with error_code=0 |
| `RTL_FRAME_START_INDEX` | Captured on `dbg_frame_start_valid` |
| `RTL_PEAK_INDEX` | Captured on `dbg_peak_valid` |
| `RTL_SLOT_START_INDEX` | Captured on `dbg_slot_start_valid` |
| `RTL_FRAC_CFO_WORD` | Captured on `dbg_frac_cfo_valid` (Q1.15) |
| `RTL_PSS_START` | `dbg_pss_start` value (should be 32) |
| `RTL_SSS_START` | `dbg_sss_start` value (should be 320) |
| `RTL_INTEGER_CFO_WORD` | Captured on `dbg_integer_cfo_valid` (informational) |
| `RTL_DONE` | 1 if done fired |
| `RTL_ERROR_CODE` | error_code_out at done |

---

## Comparison Tolerances

| Signal | Golden Key | RTL Key | Tolerance | PASS Blocker? |
|---|---|---|---|---|
| Frame start | `FRAME_START` | `RTL_FRAME_START_INDEX` | ±1 sample | Yes |
| Peak index | `PEAK_INDEX_AUTO` | `RTL_PEAK_INDEX` | ±1 sample | Yes |
| Slot start | `SLOT_START_INDEX` | `RTL_SLOT_START_INDEX` | ±1 sample | Yes |
| Frac CFO | `FRAC_CFO_OFFSET` | `RTL_FRAC_CFO_WORD` | 1% relative or ±2 Q1.15 LSB | Yes |
| PSS offset | `PSS_START` | `RTL_PSS_START` | Exact (constant) | Yes |
| SSS offset | `SSS_START` | `RTL_SSS_START` | Exact (constant) | Yes |
| Integer CFO | *(no golden)* | `RTL_INTEGER_CFO_WORD` | Informational | **No** |

---

## Run Command

```bash
# With a real IQ test vector:
./scripts/run_phase3_sync_sim.sh --iq golden/phase3_iq_stimulus.f32

# With explicit simulator:
./scripts/run_phase3_sync_sim.sh --iq golden/phase3_iq_stimulus.f32 --sim xsim
./scripts/run_phase3_sync_sim.sh --iq golden/phase3_iq_stimulus.f32 --sim iverilog
```

---

## RTL Source List

The run script compiles the following files (excluding `phase2_integer_cfo_estimator.v`
and all Xilinx IP wrappers):

**rtl/phase2_legacy/** — math primitives (complex_mult, ram_2port, etc.)  
**rtl/unit_test/** — cp_autocorr_core, timing_metric_core, timing_sync_top,
frac_cfo_estimator, timing_frac_cfo_top, frame_detector, iq_frame_buffer,
frac_cfo_corrector_top, fft256_dual_symbol_frontend (placeholder),
meyr_term2_ref_rom, meyr_integer_cfo_fft_frontend_top  
**rtl/** — axis_complex_mult, complex_mult_iq, complex_rotator, cordic_atan2,
nco_phase_gen, peak_detector, meyr_integer_cfo_core,
meyr_integer_cfo_freq_estimator_top, pss_sss_symbol_extractor,
slot_start_controller, frac_cfo_frame_corrector_top, **phase3_sync_top**

---

## PASS / FAIL Status

**Current status: BLOCKED — no IQ stimulus file available.**

The comparison cannot run until `golden/phase3_iq_stimulus.f32` is provided.
The script will exit with an error at Step b if this file is absent.

Once an IQ file is available:

| Check | Expected Status |
|---|---|
| frameStart ±1 | Ready to test |
| peakIndex ±1 | Ready to test |
| slotStartIndex ±1 | Ready to test |
| frac CFO 1% relative | Ready to test |
| PSS/SSS constants | Ready to test (should always pass) |
| Integer CFO | Informational; placeholder FFT produces arbitrary value |

---

## Observability Gaps

| Gap | Impact | Resolution |
|---|---|---|
| No IQ stimulus file | Cannot run any comparison | Provide `golden/phase3_iq_stimulus.f32` |
| Per-sample P_I/P_Q trace not at top ports | Cannot do per-lag autocorr comparison | Add `dbg_autocorr_*` wires to `frac_cfo_frame_corrector_top` top-level |
| FFT frontend is a bypass placeholder | Integer CFO result is not numerically correct | Replace `fft256_dual_symbol_frontend.S_COMPUTE` with real FFT IP |
| Integer CFO correction not implemented | Full synchronization pipeline incomplete | Requires replay buffer + second `frac_cfo_corrector_top` (see Phase 3 gap doc) |

---

## Excluded Files (per project rules)

- `rtl/unit_test/phase2_integer_cfo_estimator.v` — unit-test only, never in production
- `rtl/fft256_xilinx_wrapper.v` — Xilinx IP, not used in phase3_sync_top hierarchy
- `rtl/unit_test/cordic_atan2_xilinx_wrapper.v` — Xilinx IP wrapper
- `rtl/unit_test/nco_phase_gen_xilinx_wrapper.v` — Xilinx IP wrapper
- All FPGA/DMA/board/AXI-Lite wrapper files
- `rtl/phase2_streaming_sync_top.v` — replaced by phase3_sync_top
