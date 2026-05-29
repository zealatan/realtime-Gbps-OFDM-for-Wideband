# Step 04 — Phase3 sync_top Verification Environment Update

**Date:** 2026-05-27  
**Session:** Update verification to target rtl/phase3_sync_top.v

---

## Full Prompt (as received)

> Update the verification environment so it can test the new Phase3 top module:
>   rtl/phase3_sync_top.v
>
> Tasks:
> 1. Inspect current verification files
> 2. Update tb/phase3_sync_reference_compare_tb.sv → targets phase3_sync_top.v
> 3. Capture ports: frame_start_valid, frame_start_index, peak_valid, peak_index,
>    slot_start_valid, slot_start_index, frac_cfo_valid, frac_cfo_word, pss_start,
>    sss_start, integer_cfo_valid, integer_cfo_word, done, error_code
> 4. Update RTL output dump format to match compare_golden_rtl.py
> 5. Update scripts/run_phase3_sync_sim.sh for correct RTL file list
> 6. Add missing compile dependencies
> 7. Do not fake PASS — report clearly if RTL top is incomplete

---

## My Interpretation

`rtl/phase3_sync_top.v` does not exist at the time of this session. The verification
environment must be updated to:
- Define the expected interface of phase3_sync_top.v (port contract)
- Write the testbench targeting that interface (even if DUT is absent)
- Make the run script detect the missing file and report it explicitly
- Add a stub phase3_sync_top.v so the full flow compiles and produces explicit FAILs
- Update compare_golden_rtl.py to check all required signal groups
- Document which RTL is missing/incomplete in docs/phase3_sync_top_verification_status.md

---

## Files Inspected

| File | Purpose |
|---|---|
| tb/phase3_sync_reference_compare_tb.sv | Old testbench targeting phase2_streaming_sync_top |
| scripts/run_phase3_sync_sim.sh | Old runner with wrong RTL file list |
| scripts/compare_golden_rtl.py | Existing comparison (missing phase3 signal groups) |
| rtl/frac_cfo_frame_corrector_top.v | Steps 1–3 integrated: frame_det → timing → frac CFO → correct |
| rtl/unit_test/frame_timing_sync_top.v | Steps 1–2 only (frame_det → timing) |
| rtl/unit_test/timing_frac_cfo_top.v | Steps 2–3 timing+frac CFO |
| rtl/meyr_integer_cfo_freq_estimator_top.v | Step 4: Meyr integer CFO |
| rtl/slot_start_controller.v | Latches slot_start, provides pss/sss offsets |
| rtl/pss_sss_symbol_extractor.v | PSS/SSS window extractor |
| ref/signal_processing_common.c | C synchronization() flow |

---

## Planned Modifications

1. **md_files/step04_phase3_sync_top_verification_prompt.md** — this file (mandatory)
2. **rtl/phase3_sync_top.v** — new stub file with correct port list, empty internals
3. **tb/phase3_sync_reference_compare_tb.sv** — rewrites: targets phase3_sync_top.v,
   captures all 14 required output signals
4. **scripts/run_phase3_sync_sim.sh** — updated RTL file list for phase3_sync_top chain
5. **scripts/compare_golden_rtl.py** — adds checks for frame_start, peak, slot_start, integer_cfo
6. **docs/phase3_sync_top_verification_status.md** — status and gap report

---

## Expected phase3_sync_top.v Interface

Derived from required testbench capture signals and existing submodule port lists:

```
Inputs:
  aclk, aresetn
  s_axis_tdata [31:0], s_axis_tvalid, s_axis_tready, s_axis_tlast
  start

Outputs:
  done, busy, error_code [3:0]
  frame_start_valid, frame_start_index [BUF_AW-1:0]   (from frame_detector)
  peak_valid, peak_index [INDEX_WIDTH-1:0]              (from timing_frac_cfo_top)
  slot_start_valid, slot_start_index [BUF_AW-1:0]      (from slot_start_controller)
  frac_cfo_valid, frac_cfo_word [PHASE_WIDTH-1:0]      (from timing_frac_cfo_top)
  pss_start [BUF_AW-1:0], sss_start [BUF_AW-1:0]      (constants from slot_start_controller)
  integer_cfo_valid, integer_cfo_word signed [15:0]    (from meyr_integer_cfo_freq_estimator_top)
```

---

## C-to-RTL Signal Mapping (for compare_golden_rtl.py)

| Golden Key | C Variable | RTL Port | Comparison |
|---|---|---|---|
| FRAME_START | frameStart | frame_start_index (at frame_start_valid) | ±0 when buf addr == sample index |
| PEAK_INDEX_AUTO | peakIndexAuto | peak_index (at peak_valid) | ±CP_LEN=32 |
| SLOT_START_INDEX | slotStartIndex | slot_start_index (at slot_start_valid) | ±CP_LEN=32 |
| FRAC_CFO_OFFSET | fracfreqOffset | frac_cfo_word (at frac_cfo_valid) | ±2 Q1.15 LSB |
| INTEGER_CFO | carrierFreqOffsetInt | integer_cfo_word (at integer_cfo_valid) | ±1 subcarrier bin |

---

## RTL Dependency Chain for Compile

```
phase3_sync_top.v
├── frac_cfo_frame_corrector_top.v
│   ├── unit_test/iq_frame_buffer.v
│   ├── unit_test/frame_detector.v
│   ├── unit_test/timing_frac_cfo_top.v
│   │   ├── unit_test/timing_sync_top.v
│   │   │   ├── unit_test/cp_autocorr_core.v
│   │   │   │   └── phase2_legacy/ram_2port.v
│   │   │   ├── unit_test/timing_metric_core.v
│   │   │   └── peak_detector.v
│   │   └── unit_test/frac_cfo_estimator.v
│   │       └── cordic_atan2.v
│   ├── unit_test/frac_cfo_corrector_top.v
│   │   ├── nco_phase_gen.v
│   │   └── complex_rotator.v
│   └── axis_complex_mult.v (or complex_mult_iq.v)
├── slot_start_controller.v
├── pss_sss_symbol_extractor.v
└── meyr_integer_cfo_freq_estimator_top.v
    ├── meyr_pss_sss_product_gen.v
    ├── meyr_integer_cfo_core.v
    └── unit_test/meyr_term2_ref_rom.v
```

Excluded: rtl/unit_test/phase2_integer_cfo_estimator.v (unit-test standalone, never in production)

---

## Final Summary

- phase3_sync_top.v created as stub (correct ports, no datapath connections)
- Testbench: targets phase3_sync_top.v, captures all 14 required signals
- Run script: updated file list, pre-flight check for missing files
- Compare script: extended with frame_start, peak, slot_start, integer_cfo checks
- Status doc: lists which submodules are unconnected in stub, what RTL design session must do
- Stub will compile and simulate but produce all-zero outputs → all comparisons FAIL explicitly
