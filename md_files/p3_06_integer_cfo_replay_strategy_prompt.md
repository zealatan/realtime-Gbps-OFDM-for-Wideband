# P3-06 — Integer CFO Replay Strategy Prompt (Archive)

## Full Original Prompt

ROLE: Claude-D — P3-06 Integer CFO Replay Strategy Spec Owner

CONTEXT:
phase3_sync_top.v currently estimates integer CFO and exposes:
  dbg_integer_cfo_valid / dbg_integer_cfo_word
But full integer CFO correction is not implemented.
Known remaining gap: integer CFO correction requires replaying the corrected
576-sample frame after integer CFO estimate becomes available.

GOAL: Create an architecture/spec document only. Do NOT implement RTL.

TASKS:
1. Inspect:
   rtl/phase3_sync_top.v, rtl/streaming_cfo_corrector.v, rtl/nco_phase_gen.v,
   rtl/complex_rotator.v, rtl/frac_cfo_frame_corrector_top.v,
   rtl/pss_sss_symbol_extractor.v, rtl/meyr_integer_cfo_freq_estimator_top.v
2. Create: docs/p3_06_integer_cfo_replay_strategy.md
3. Analyze Option A (576-sample replay buffer), Option B (DMA/host replay),
   Option C (delayed streaming with large FIFO). For each: required buffer size,
   latency, AXIS backpressure, TLAST behavior, debug/status impact,
   synthesis/resource impact, compatibility, verification plan.
4. Recommend one option for next implementation.
5. Define future interface proposal (int_cfo_apply_enable, int_cfo_step_word,
   replay_start, replay_busy, replay_done, replay_error, output frame AXIS).
6. Define future TB matrix T01–T07.

PASS CRITERIA: doc exists, no RTL modified, recommended architecture clear,
risks and next implementation step explicit.
DO NOT MODIFY: rtl/, tb/, scripts/, ref/, production logic.

---

## Interpretation

The core gap is that after meyr_done fires, the 32-bit NCO step word for integer
CFO correction is stable in int_cfo_step_word_r, but there is no path to apply it.
The frac-corrected 576-sample frame has already been streamed through the extractor
and consumed — it no longer exists in any buffer. To apply integer CFO correction
a second pass over those 576 frac-corrected samples is required.

Three viable approaches exist, differing in where the second pass data comes from:
  A: SRAM replay buffer tapping the frac-corrected stream (internal, deterministic)
  B: Host re-feeds the raw IQ input after learning int_cfo (external, high latency)
  C: Large FIFO holds the frac-corrected output until meyr_done (internal, impractical)

Option A is clearly best: bounded 576-sample buffer, no host software dependency,
no extra FIFO depth proportional to Meyr latency.

---

## Files Inspected

- rtl/phase3_sync_top.v           — orchestration FSM, S_IDLE→S_RUN→S_DONE
- rtl/streaming_cfo_corrector.v   — wraps frac_cfo_corrector_top, Q1.15 frac_phase→step
- rtl/nco_phase_gen.v             — 256-entry sin/cos ROM, 32b accumulator, LATENCY=15
- rtl/complex_rotator.v           — complex_mult_iq CONJ_B=1 wrapper
- rtl/frac_cfo_frame_corrector_top.v — S_FILL/FRAME_DET/TIMING_CFO/LOAD_NCO/CORRECT/DONE
                                       internal iq_frame_buffer (BUF_AW=12 = 4096 depth)
                                       output TOTAL_SAMPLES=FRAME_LEN=576 when called
                                       from phase3_sync_top
- rtl/pss_sss_symbol_extractor.v  — single-pass streaming: PSS@[CP_LEN..CP_LEN+NSC-1],
                                     SSS@[2*CP_LEN+NSC..FRAME_LEN-1]; backpressure via hold
- rtl/meyr_integer_cfo_freq_estimator_top.v — S_IDLE→S_RECV(256 pairs)→S_START_CORE
                                              →S_STREAM→S_WAIT_CORE→S_DONE;
                                              correlation: 511 lags × 256 accums ~130K cycles

Key measured parameters (NSC=256, CP_LEN=32):
  FRAME_LEN        = 2*(256+32)     = 576 samples
  INT_CFO_SHIFT    = 32 - 8         = 24 bits
  step_word format = -int_cfo <<< 24 (32-bit signed, 2's complement)
  NCO warm-up      = CORDIC_LATENCY = 15 cycles
  S_CORRECT throughput = 1 sample per 2 clocks (buffer read + hold pipeline)
  Replay time      ≈ 576 × 2        = 1152 cycles

Critical tap point: frac_m_tdata/tvalid/tready bus between
frac_cfo_frame_corrector_top and pss_sss_symbol_extractor.
A write fire occurs when frac_m_tvalid && frac_m_tready.

---

## Planned Modifications

- Create md_files/p3_06_integer_cfo_replay_strategy_prompt.md (this file)
- Create docs/p3_06_integer_cfo_replay_strategy.md
- No RTL files modified

---

## Final Summary

Delivered:
  docs/p3_06_integer_cfo_replay_strategy.md — full architecture/spec
  md_files/p3_06_integer_cfo_replay_strategy_prompt.md — this archive

Recommendation: Option A (576-sample replay buffer).
Options B and C rejected (B: external latency/host dependency; C: FIFO impractical
at ~130K+ sample depth due to Meyr correlation latency).
Next implementation step: new iq_replay_buffer_576 module + second frac_cfo_corrector_top
instance instantiated in phase3_sync_top, with S_REPLAY state added to top FSM.
No existing RTL files modified in this step.
