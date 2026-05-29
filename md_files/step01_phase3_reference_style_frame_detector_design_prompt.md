# Step 01 — Phase 3 Reference-Style Frame Detector Design Prompt (Archive)

## Full Original Prompt

> You are working in /home/zealatan/RTL_SYNC_PHASE3.
>
> Mandatory archival rule: Before making or proposing RTL changes, create a markdown
> prompt/archive file under /home/zealatan/RTL_SYNC_PHASE3/md_files/ with a
> step-numbered filename step01_phase3_reference_style_frame_detector_design_prompt.md.
>
> Project context: This workspace has ref/ (C reference OFDM receiver) and rtl/
> (Verilog RTL implementation). Important files include ref/receiver.c,
> ref/signal_processing_common.c, ref/auxiliary.c, rtl/phase2_streaming_sync_top.v,
> rtl/streaming_cp_autocorr.v, rtl/streaming_timing_metric.v,
> rtl/streaming_peak_detector.v, rtl/streaming_frac_cfo_estimator.v,
> rtl/streaming_cfo_corrector.v, rtl/frac_cfo_frame_corrector_top.v,
> rtl/pss_sss_symbol_extractor.v, rtl/meyr_integer_cfo_freq_estimator_top.v.
>
> Do NOT treat rtl/phase2_integer_cfo_estimator.v as production top.
>
> Goal: Analyze the C reference synchronizer, especially synchronization() and
> its helper functions, then update the RTL architecture plan so Phase 3 follows
> the reference-style frame-boundary-aware synchronizer.
>
> Expected reference behavior:
>   1. frame_detector() finds coarse frameStart
>   2. VanDeBeekAutoCorrelation() searches around frameStart
>   3. peakIndexAuto is selected
>   4. slotStartIndex = frameStart + peakIndexAuto
>   5. fractional CFO estimated from selected autocorrelation phase
>   6. fractional CFO correction starts from slotStartIndex
>   7. PSS/SSS extraction and Meyr integer CFO use slotStartIndex
>
> Task: Inspect ref/receiver.c, identify the exact synchronization sequence,
> inspect current RTL top-level, determine what is implemented vs missing,
> propose a clean RTL design change, implement only the minimal new RTL module(s)
> needed for frameStart/slotStartIndex orchestration, and produce the required outputs.

---

## Interpretation

The prompt asks for a complete architectural audit of the C reference synchronizer
against the current RTL, followed by minimal new RTL additions.

Key insight: `frac_cfo_frame_corrector_top.v` already implements most of the
reference flow internally. The gaps are at the Phase 3 orchestration level —
specifically the `slotStartIndex` handoff to `pss_sss_symbol_extractor` and
`meyr_integer_cfo_freq_estimator_top`, and the integer CFO correction pass.

---

## Files Inspected

### Reference C Files
- `ref/receiver.c` — complete: `synchronization()`, `frame_detector()`,
  `VanDeBeekAutoCorrelation()`, `auto_corr()`, `find_max_index()`,
  `carrierFreqOffsetEstMeyr()`, `apply_carrier_freq_offset()`

### RTL Files
- `rtl/phase2_streaming_sync_top.v` — Phase 2 streaming synchronizer (no frame boundary)
- `rtl/streaming_cp_autocorr.v` — sliding-window CP autocorrelation
- `rtl/streaming_peak_detector.v` — window-based peak detector
- `rtl/streaming_frac_cfo_estimator.v` — CORDIC atan2 for frac CFO
- `rtl/frac_cfo_frame_corrector_top.v` — **key module**: frame-buffer + frame_detector +
  timing_frac_cfo_top + frac_cfo_corrector FSM; computes slot_start = frame_index + peak_lag
- `rtl/pss_sss_symbol_extractor.v` — PSS/SSS window extractor (needs slotStartIndex)
- `rtl/meyr_integer_cfo_freq_estimator_top.v` — Meyr integer CFO estimator
- `rtl/unit_test/frame_detector.v` — energy-based frame detector (exact C match)
- `rtl/unit_test/timing_frac_cfo_top.v` — CP timing sync + CORDIC frac CFO

---

## Allowed Modifications

- Add new RTL modules under `rtl/`
- Modify `rtl/phase2_streaming_sync_top.v` only if necessary
- Add docs under `docs/`
- Add md archive under `md_files/`

## Do NOT Modify

- `ref/` files
- `meyr_*` core files
- `cordic_atan2.v`, `complex_rotator.v`, `nco_phase_gen.v`
- `streaming_cp_autocorr.v` (unless clear interface bug)
- `phase2_integer_cfo_estimator.v`

---

## Planned Files to Create

1. `md_files/step01_phase3_reference_style_frame_detector_design_prompt.md` (this file)
2. `docs/phase3_reference_synchronizer_architecture.md`
3. `docs/phase3_rtl_gap_analysis.md`
4. `rtl/slot_start_controller.v` — new: latches slotStartIndex, outputs PSS/SSS offsets

---

## Final Expected Outputs

1. Documented synchronization() reference flow
2. Gap analysis between C reference and current RTL
3. `slot_start_controller.v` — minimal orchestration glue
4. Summary of what is complete and what remains
5. `phase2_integer_cfo_estimator.v` excluded from production path (documented)
