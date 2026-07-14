# Continuous Multi-Slot Streaming Rework Plan (Phase B)
Date: 2026-06-23. Goal: make the OFDM RX sync DUT process continuous back-to-back
multi-slot input (currently 1 slot then stops: TLAST stuck=1, ~16Msps/8.8% duty,
FRAME_LEN_MISMATCH @187.5MHz).

## Architecture (traced)
- Downstream (slot_frontend→sync_capture→meyr) is FREE-RUNNING (auto re-arm).
- Upstream (iq_frame_buffer + frac_cfo_frame_corrector_top) is ONE-SHOT
  store-and-forward: s_axis_tready=busy; deaf during frac+meyr (~15us).
- phase3_sync_top FSM (line 252-298): S_IDLE->S_RUN->S_DONE, needs `start` pulse;
  S_RUN waits for meyr_cfo_valid (line 283).
- wrapper re-arm FSM (394-414): re-arms on dut_done; STOPS on dut_done&&dut_error.

## Blockers
1. Re-arm/alignment: after slot1, capture restarts at arbitrary phase of the
   looping stim -> misaligned window -> frac_frame_error or no valid meyr.
2. wrapper:403 `dut_done && dut_error -> start_armed_r=0` stops on any error.
3. FRAME_LEN_MISMATCH (wrapper:331): in_frame_cnt!=4031 at accepted tlast because
   tready is gapped + stim=4160 != int_frame_len=4032.
NOTE: B[k] ROM is BAKED on the board (int-CFO=82 non-zero proves it) -> the
agent's "ROM all-zero" point is N/A for the board; it's only a SIM concern (TB
patches it via hierarchical $readmemh).

## Staged plan (sim-verify each before the ~45min board rebuild)
- L1 frame-len: stim->4032 OR relax wrapper:331 mismatch check. (low)
- L2 re-arm: fix the 1-cycle start_r/S_IDLE race + reconsider error-stop (403)
  for continuous. (low)
- S4: verify reduced-duty continuous in sim (multi-slot TB, TLAST>=3, ERR=0,
  ~50% duty). GREEN-LIGHT for rebuild.
- H1 (later, high-risk): ping-pong double-buffer to decouple acquisition from
  processing -> sustained zero-drop / full duty. meyr stays untouched (it's
  pipelined + keeps up in throughput; latency only delays the est by 1 slot).

## Realistic near-term: L1+L2 = continuous re-arm at ~50% duty (ISS-24 limited).
Full zero-drop = H1 (separate phase).

## Verify path: extend tb/p5_d_continuous_wrapper_tb.sv to drive >=3 back-to-back
## 4032 frames; run scripts/run_p5_d_continuous_wrapper.sh (~9min, xfft).

## UPDATE 2026-06-23 — sim debug findings (multi-slot reproduce)
- Built drive_multi() harness in p5_d_continuous_wrapper_tb (continuous N-frame,
  backpressured). Drove fc_kp0 x3 back-to-back.
- RESULT: DUT STALLS after ~1 frame. in_count stuck at ~4160, drive_multi hangs
  (s_axis_tready never re-opens). MULTISLOT print never reached (run_case stuck in
  drive_multi). Confirms: the DUT does NOT sustain continuous; tready stays low
  after the first slot's capture (deaf during processing + no clean re-arm).
- GEOMETRY: buffer DEPTH=4096 (iq_frame_buffer.v ADDR_WIDTH=12), stim=4160,
  FRAME_LEN=4032 — all different. 4096 fills before the 4160 tlast -> 64-beat tail
  leaks. BUT driving 4096-beat frames did NOT fix it (still stalls ~4160). So the
  geometry is a contributor but NOT the root; the root is the one-shot
  capture->process->rearm with s_axis_tready=busy (iq_frame_buffer.v:74) going
  DEAF during the multi-us frac+meyr processing.
- Wrapper re-arm STOPS on error: phase3_sync_axis_dma_wrapper.v:403
  `dut_done && dut_error -> start_armed_r=0`. A continuous misaligned slot can
  error -> re-arm disabled -> permanent stall.
- CONCLUSION: continuous multi-slot REQUIRES the H1 architectural rework
  (decouple acquisition from processing = ping-pong / streaming front-end so
  s_axis_tready never drops), NOT a quick geometry/re-arm tweak. H1 is high-risk,
  multi-iteration (rework frac_cfo_frame_corrector_top FSM 375-502 + dual
  iq_frame_buffer). The meyr stays untouched (pipelined, keeps up).
- Single-slot sync works @187.5MHz; this is purely the continuous front-end.
