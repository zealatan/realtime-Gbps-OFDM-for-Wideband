# Step 03 — Phase 3 Sync Top Integration Prompt (Archive)

## Full Original Prompt

Create Phase3 orchestration RTL top connecting:
frac_cfo_frame_corrector_top, slot_start_controller, pss_sss_symbol_extractor,
fft256_xilinx_wrapper (×2 for PSS/SSS), meyr_integer_cfo_freq_estimator_top,
optional integer CFO corrector connection point.
Primary output: rtl/phase3_sync_top.v with full debug/verification outputs.
Parameterize all offsets from NSC and CP_LEN — no hardcoded 32/320/576.
Excluded: phase2_integer_cfo_estimator.v.

## Interpretation

frac_cfo_frame_corrector_top already integrates Steps 1-4 internally.
meyr_integer_cfo_fft_frontend_top (unit_test/) wraps FFT dual-symbol frontend +
Meyr estimator in one module — use it instead of raw fft256_xilinx_wrapper.
All three sub-modules started simultaneously on top start; extractor/Meyr wait for
data since frac_corrector takes thousands of cycles to complete.
Integer CFO corrector: expose step word as output port (replay buffer is future work).

## Files Inspected

- rtl/frac_cfo_frame_corrector_top.v
- rtl/slot_start_controller.v
- rtl/pss_sss_symbol_extractor.v
- rtl/fft256_xilinx_wrapper.v
- rtl/meyr_integer_cfo_freq_estimator_top.v
- rtl/streaming_cfo_corrector.v
- rtl/unit_test/meyr_integer_cfo_fft_frontend_top.v
- rtl/unit_test/fft256_dual_symbol_frontend.v
- rtl/unit_test/frac_cfo_corrector_top.v

## Planned Modifications

- Create rtl/phase3_sync_top.v
- Create docs/phase3_sync_top_integration.md
- Create this archive

## Architecture Decisions

Stream path: s_axis → frac_cfo_frame_corrector_top (OUTPUT_SAMPLES=FRAME_LEN=2*(NSC+CP_LEN))
  → pss_sss_symbol_extractor (PSS@CP_LEN, SSS@2*CP_LEN+NSC)
  → meyr_integer_cfo_fft_frontend_top → int_cfo → step_word

FSM: S_IDLE (start→pulse 3 subs) → S_RUN (wait meyr_done or frac_frame_error) → S_DONE

Integer CFO step word: step = -int_cfo * 2^(32-log2(NSC)), NSC must be power of 2.

## Final Summary

Delivered: rtl/phase3_sync_top.v, docs/phase3_sync_top_integration.md.
Limitation: integer CFO correction requires a replay buffer (future work).
phase2_integer_cfo_estimator.v excluded from all instantiations.
