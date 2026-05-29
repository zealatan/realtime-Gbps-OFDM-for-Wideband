# P3-05 — Phase 3 Golden Compare Verification (Mandatory Archive)

**Role:** Claude-C — P3-05 Phase3 Golden Compare Verification Owner  
**Date:** 2026-05-27  
**Prompt number:** p3_05

---

## Full Prompt (verbatim)

```
ROLE
====
Claude-C — P3-05 Phase3 Golden Compare Verification Owner

MANDATORY ARCHIVAL RULE
=======================
Before making changes, create:

md_files/p3_05_phase3_golden_compare_prompt.md

This archive must contain:
- this full prompt
- your interpretation
- files inspected
- planned modifications
- final summary

CONTEXT
=======
Existing verification infrastructure may already exist:

scripts/golden_dump.c
scripts/compare_golden_rtl.py
scripts/run_phase3_sync_sim.sh
tb/phase3_sync_reference_compare_tb.sv
docs/phase3_reference_c_vs_rtl_verification_plan.md
docs/phase3_golden_dump_format.md

A new RTL top exists or is being compiled by another session:

rtl/phase3_sync_top.v

GOAL
====
Update the golden comparison flow so it targets phase3_sync_top.v.

This is RTL simulation only.
No FPGA/board/Vitis/DMA bring-up.

TASKS
=====
1. Inspect existing scripts and TB:
   - scripts/golden_dump.c
   - scripts/compare_golden_rtl.py
   - scripts/run_phase3_sync_sim.sh
   - tb/phase3_sync_reference_compare_tb.sv

2. Update TB to instantiate: rtl/phase3_sync_top.v

3. Capture RTL debug outputs into: logs/phase3_sync_rtl_dump.csv

Required fields:
   frame_start_valid, frame_start_index, peak_valid, peak_index,
   slot_start_valid, slot_start_index, frac_cfo_valid, frac_cfo_word,
   pss_start, sss_start, integer_cfo_valid, integer_cfo_word, done, error_code

4. Update golden dump if needed to output:
   frameStart, peakIndexAuto, slotStartIndex, autoCorrOutI_at_peak,
   autoCorrOutQ_at_peak, fracCFO, pssStart, sssStart

5. Update compare script tolerances:
   frameStart: ±1 sample
   peakIndex: ±1 sample
   slotStartIndex: ±1 sample
   frac CFO: relative error <= 1% or fixed-point equivalent tolerance
   integer CFO: do not require PASS yet unless stable; report as informational

6. Update run script
   Expected sequence: a. build golden_dump, b. run golden_dump,
   c. generate RTL input vector, d. compile RTL/TB, e. run xsim,
   f. compare golden vs RTL, g. print CI GATE

7. Create doc: docs/p3_05_phase3_golden_compare_status.md

PASS CRITERIA
=============
- TB targets phase3_sync_top.v
- phase2_integer_cfo_estimator.v excluded
- compare includes at least: frameStart, peakIndex, slotStartIndex, frac CFO
- integer CFO may be reported but not final pass blocker yet
- failure messages are explicit
- no fake PASS

DO NOT MODIFY
=============
- production RTL datapath
- ref algorithm semantics
- FPGA/board/Vitis files
- phase2_integer_cfo_estimator.v
```

---

## Interpretation

The existing verification flow (Steps 01–04) targeted `phase2_streaming_sync_top`, a legacy
Phase 2 DUT. The TB, run script, and compare script all reference that old DUT.

**phase3_sync_top.v** (written in Step 03) is the new orchestration top that connects:
1. `frac_cfo_frame_corrector_top` — Steps 1–4 of C ref (frame detect + timing + frac CFO)
2. `slot_start_controller` — latches slotStartIndex
3. `pss_sss_symbol_extractor` — PSS/SSS window extraction
4. `meyr_integer_cfo_fft_frontend_top` — Step 5 (Meyr integer CFO, behavioral FFT placeholder)

It exposes dedicated `dbg_*` outputs at the top-level port for all required signals. There is no
`timing_lock`/`lock_index`/`frac_phase_dbg` port (that was Phase 2 vocabulary); the Phase 3 equivalents
are `dbg_frame_start_valid/index`, `dbg_peak_valid/index`, `dbg_slot_start_valid/index`,
`dbg_frac_cfo_valid/word`, `dbg_pss_start`, `dbg_sss_start`, `dbg_integer_cfo_valid/word`.

---

## Files Inspected

| File | Purpose |
|---|---|
| `scripts/golden_dump.c` | C golden extractor — outputs FRAME_START, PEAK_INDEX_AUTO, SLOT_START_INDEX, AUTOCORR_I/Q_AT_PEAK, FRAC_CFO_OFFSET. Missing PSS_START, SSS_START. |
| `scripts/compare_golden_rtl.py` | Comparison script targeting Phase 2 RTL key names (RTL_LOCK_INDEX, RTL_FRAC_PHASE, etc.). Tolerances: ±32 samples for index, ±2 Q1.15 for frac. |
| `scripts/run_phase3_sync_sim.sh` | Compiles phase2_streaming_sync_top. Has duplicate Python IQ conversion block. Steps labeled 1/5–6/6. Supports iverilog (default) and xcelium. No xsim. |
| `tb/phase3_sync_reference_compare_tb.sv` | Instantiates phase2_streaming_sync_top. Captures timing_lock, lock_index, metric_dbg, frac_phase_dbg. Reads from ../golden, writes to ../sim_out. No CSV output. |
| `rtl/phase3_sync_top.v` | New Phase 3 DUT. Ports: aclk, aresetn, s_axis_tdata/tvalid/tready/tlast, threshold_in, window_len_in, hit_count_in, start, done, busy, error, error_code, dbg_* outputs. |
| `rtl/unit_test/fft256_dual_symbol_frontend.v` | Behavioral placeholder (input bypass, no Xilinx IP). Simulation-safe. |
| `rtl/unit_test/meyr_integer_cfo_fft_frontend_top.v` | Instantiates fft256_dual_symbol_frontend + meyr_integer_cfo_freq_estimator_top. |
| `rtl/meyr_integer_cfo_freq_estimator_top.v` | Instantiates meyr_integer_cfo_core (rtl/) + meyr_term2_ref_rom (unit_test/). |

---

## Planned Modifications

### 1. `scripts/golden_dump.c` (minor)
Add `PSS_START` and `SSS_START` output fields (constants: CP_LEN=32, 2*CP_LEN+NSC=320).

### 2. `tb/phase3_sync_reference_compare_tb.sv` (complete rewrite)
- DUT: `phase3_sync_top` (was `phase2_streaming_sync_top`)
- Clock port: `aclk` (was `clk`)
- New control ports: `start`, `done`, `busy`, `error`, `error_code`, `threshold_in`, `window_len_in`, `hit_count_in`
- Capture: all `dbg_*` signals
- CSV output: `logs/phase3_sync_rtl_dump.csv` (per-event trace)
- Summary: `sim_out/rtl_results.txt` (key-value for comparison script)
- Paths relative to project root (not `../`)

### 3. `scripts/compare_golden_rtl.py` (complete rewrite)
- New RTL key names: `RTL_FRAME_START_INDEX`, `RTL_PEAK_INDEX`, `RTL_SLOT_START_INDEX`,
  `RTL_FRAC_CFO_WORD`, `RTL_PSS_START`, `RTL_SSS_START`, `RTL_INTEGER_CFO_WORD`
- New tolerances: frameStart ±1, peakIndex ±1, slotStartIndex ±1,
  frac CFO relative ≤1% or ≥2 Q1.15 LSB floor
- Integer CFO: informational only (no PASS/FAIL)
- PSS/SSS: exact match (constants)

### 4. `scripts/run_phase3_sync_sim.sh` (rewrite)
- Fix duplicate Python IQ conversion block
- Add full RTL source list for phase3_sync_top hierarchy
- Exclude: `phase2_integer_cfo_estimator.v`, Xilinx wrappers, FPGA/DMA files
- Add xsim as supported simulator (default); keep iverilog
- Create `logs/` directory
- Steps a–g with CI GATE printout

### 5. `docs/p3_05_phase3_golden_compare_status.md` (new)
Status doc summarizing changes, pass criteria state, and observability gaps.

---

## RTL Source Hierarchy for Compilation

```
phase3_sync_top (rtl/)
├── frac_cfo_frame_corrector_top (rtl/)
│   ├── iq_frame_buffer (unit_test/)
│   ├── frame_detector (unit_test/)
│   ├── timing_frac_cfo_top (unit_test/)
│   │   ├── timing_sync_top (unit_test/)
│   │   │   ├── cp_autocorr_core (unit_test/)
│   │   │   │   └── [uses phase2_legacy/ math modules]
│   │   │   ├── timing_metric_core (unit_test/)
│   │   │   └── peak_detector (rtl/)
│   │   └── frac_cfo_estimator (unit_test/)
│   │       └── cordic_atan2 (rtl/)
│   └── frac_cfo_corrector_top (unit_test/)
│       ├── nco_phase_gen (rtl/)
│       └── complex_rotator (rtl/)
│           └── axis_complex_mult (rtl/)
│               └── complex_mult_iq (rtl/)
├── slot_start_controller (rtl/)
├── pss_sss_symbol_extractor (rtl/)
└── meyr_integer_cfo_fft_frontend_top (unit_test/)
    ├── fft256_dual_symbol_frontend (unit_test/) [placeholder, no IP]
    └── meyr_integer_cfo_freq_estimator_top (rtl/)
        ├── meyr_integer_cfo_core (rtl/)
        └── meyr_term2_ref_rom (unit_test/)

Explicitly EXCLUDED:
- rtl/unit_test/phase2_integer_cfo_estimator.v
- rtl/fft256_xilinx_wrapper.v (Xilinx IP, not in phase3_sync_top hierarchy)
- All FPGA/DMA/board wrappers
- rtl/phase2_streaming_sync_top.v (replaced by phase3_sync_top)
```

---

## Final Summary

**Files changed:**
1. `md_files/p3_05_phase3_golden_compare_prompt.md` — this archive (created)
2. `scripts/golden_dump.c` — added PSS_START, SSS_START fields
3. `tb/phase3_sync_reference_compare_tb.sv` — complete rewrite for phase3_sync_top
4. `scripts/compare_golden_rtl.py` — new key names, new tolerances, integer CFO informational
5. `scripts/run_phase3_sync_sim.sh` — correct source list, xsim support, logs/ dir, CI GATE
6. `docs/p3_05_phase3_golden_compare_status.md` — new status doc

**Golden dump fields:** DETECTION_STATUS, FRAME_START, PEAK_INDEX_AUTO, SLOT_START_INDEX,
AUTOCORR_I_AT_PEAK, AUTOCORR_Q_AT_PEAK, ENERGY_AT_PEAK, METRIC_AT_PEAK, FRAC_CFO_OFFSET,
PSS_START (new), SSS_START (new)

**RTL dump fields (CSV + rtl_results.txt):** cycle, frame_start_valid, frame_start_index,
peak_valid, peak_index, slot_start_valid, slot_start_index, frac_cfo_valid, frac_cfo_word,
pss_start, sss_start, integer_cfo_valid, integer_cfo_word, done, error_code

**Run command:** `./scripts/run_phase3_sync_sim.sh --iq <iq.f32> [--sim xsim|iverilog]`

**Blocking issues:** No IQ stimulus file exists yet (`golden/phase3_iq_stimulus.f32` must be
provided externally). The FFT frontend is a behavioral placeholder so Meyr integer CFO results
are INFORMATIONAL only. A real IQ test vector is required to produce a PASS/FAIL on timing indices
and frac CFO.

**Observability gaps:**
- Per-sample autocorrelation P_I/P_Q trace not exposed at phase3_sync_top top level
- Meyr FFT bins not observable (internal to placeholder frontend)
- Integer CFO result depends on placeholder FFT — not a reliable PASS signal yet
