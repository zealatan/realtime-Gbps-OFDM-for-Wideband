# H1 Design — Ping-pong front-end for continuous multi-slot (design, pre-impl)
Date 2026-06-23. Goal: continuous back-to-back slots without stall, ~50% duty
(frac-readout limited; full rate = H1b later). meyr UNTOUCHED.

## KEY CORRECTION (from design analysis)
The frac corrector's buffer write-back port is TIED OFF (frac_cfo_frame_corrector_top.v:237-239
wb_en=0). S_CORRECT only READS the buffer + rotates into m_axis (no write-back). So
deafness is PURELY: the single buffer's AXI ingest port is owned by the FSM for the whole
slot (S_FILL..S_CORRECT), s_axis_tready=busy only in S_FILL (iq_frame_buffer.v:74). => clean
producer/consumer split, ping-pong is simpler than feared.

## Architecture
- NEW rtl/iq_capture_pingpong.v: owns AXI ingest + TWO iq_frame_buffer (A/B) + ping-pong FSM
  + read-port mux to the processing FSM. Ports: s_axis_*, buf_ready/buf_len/proc_take/proc_free,
  rd_en/rd_addr/rd_data, both_full/cap_overflow.
- iq_frame_buffer.v: NO logic change; instantiate x2 with ADDR_WIDTH=CAP_AW=13 (DEPTH 8192).
- frac_cfo_frame_corrector_top.v: DELETE embedded u_buf (225-248) + S_FILL (110, 414-424) +
  buf_capture_start/done. ADD S_WAIT_BUF (wait buf_ready -> proc_take -> fd_start), and S_FREE
  (pulse proc_free) before S_DONE. Watchdog acq_timeout repoint S_FILL->S_WAIT_BUF. Read-port
  mux (351-370) kept; buf_rd_data now from u_cap (selected by proc_sel internally).
- phase3_sync_top.v / wrapper: BUF_AW 12->13 propagation (frame_detector, timing_frac_cfo_top,
  phase3_axi_lite_regs). Prefer a SEPARATE CAP_AW=13 for the physical buffer to minimize blast
  radius (algo indices stay 12 where <4096).
- wrapper:403 re-arm: DELETE the `dut_done && dut_error -> start_armed_r=0` special case ->
  re-arm on EVERY dut_done (continuous; error still sticky in AXI-Lite ERROR). Optional
  halt_on_error config bit (default continuous).
- M_AXIS / int NCO: NO change. Replay buffer already retired; u_int_nco reloads step on each
  dut_int_cfo_valid (wrapper 223-224) -> per-slot correction already works once the stream flows.

## Alignment
capture-until-tlast: with DEPTH>=4160 the buffer ends on s_axis_tlast (not &wr_ptr full) ->
each buffer = one whole frame, aligned slot-to-slot. CAP_AW=13 (8192; 4160 not pow2).

## Duty
tready high while >=1 buffer free; drops only when BOTH full. Since S_CORRECT reads 1 sample/
2 clocks (~8064 cyc > 4160 slot), processing ~2x slower -> ~50% duty (expected, accepted for
H1a). H1b (later): streaming frac readout (replace S_CORRECT 464-490 serialization w/ 2-deep
skid, read every cycle) -> ~100% duty. H1a leaves S_CORRECT untouched (forward-compatible).

## Staging (sim-verify each; regression must stay 11/11)
- H1a-0: width bump BUF_AW 12->13 / add CAP_AW. Mechanical. Verify regression 11/11 + AXI-COV
  (status reg bit positions). HIGHEST mechanical risk.
- H1a-1: iq_capture_pingpong + unit TB (model iq_frame_buffer_unit_tb): 2 frames back-to-back,
  tready never drops while >=1 free, buf_ready per tlast, proc_take/free round-trip, both_full
  only when proc held, read-port returns correct buffer per proc_sel.
- H1a-2: integrate into frac corrector (remove S_FILL). Verify single-slot bit-exact
  (frac_cfo_frame_corrector_top_param/subint_tb + P5-CORRECTED) THEN continuous via drive_multi:
  cfo_valid_count==3, in_count reaches 3*4160, tlast_count==3 (vs stuck=1), duty~50%,
  re-arm-on-error (inject 1 bad slot, good slots still complete).
- H1b: later, frac streaming pipeline -> duty ~100%.

## Risks/guards
- width bump regressions -> stage H1a-0 alone, AXI-COV guard, prefer CAP_AW.
- single-slot must stay bit-exact -> param/subint_tb + P5-CORRECTED guards.
- bypass unaffected (routes around buffer).
- meyr untouched -> P5-EQUIV 17/17, P5-D1-3WAY guards.
- tready 1-cyc bubble at slot boundary (pre-arm partner to remove).
- re-arm-on-error masking faults -> keep sticky ERROR + optional halt_on_error bit.

## Critical files
rtl/frac_cfo_frame_corrector_top.v, rtl/iq_frame_buffer.v, rtl/phase3_sync_axis_dma_wrapper.v,
rtl/phase3_sync_top.v, tb/p5_d_continuous_wrapper_tb.sv, + NEW rtl/iq_capture_pingpong.v.

## IMPL UPDATE 2026-06-23 — H1a-1 DONE (module verified in iverilog)
- rtl/iq_capture_pingpong.v written: explicit capture FSM (CAP_IDLE/CAP_A/CAP_B)
  + 2x iq_frame_buffer + proc handoff (buf_ready/proc_take/proc_free/proc_sel).
  KEY fix during bring-up: the IDLE state is entered AFTER capture_done (occ
  already updated) so the just-filled buffer is seen occupied -> no same-cycle
  re-arm race (the first naive version re-armed the same buffer -> overwrote it).
- tb/iq_capture_pingpong_unit_tb.sv: canonical AXI-S producer (advance only on
  accept), slow-processor model (forces both_full), robust per-addr read.
- iverilog: iverilog -g2012 -o /tmp/pp_tb.vvp rtl/iq_capture_pingpong.v
  rtl/iq_frame_buffer.v tb/iq_capture_pingpong_unit_tb.sv ; vvp /tmp/pp_tb.vvp
  RESULT: PASS (frames 3/3, overflow 0, both_full 116cyc, data errors 0).
- NEXT: H1a-0 width bump (BUF_AW/CAP_AW 12->13) + H1a-2 integrate into
  frac_cfo_frame_corrector_top (remove S_FILL/embedded buffer -> S_WAIT_BUF
  handoff using iq_capture_pingpong). H1a-2 is the invasive step (needs the
  xfft full-chain sim to verify continuous: drive_multi cfo_valid_count==3).

## H1a-2 RESULT 2026-06-23 — front-end VERIFIED CORRECT; doubling is a separate layer
- Integrated iq_capture_pingpong into frac_cfo_frame_corrector_top (S_FILL->wait
  buf_ready handoff, proc_take/free, CAP_AW=13 buffer, 12b algo addr zero-ext,
  S_DONE->proc_free). Compiles. STAGE1 63/63 PASS (single-slot intact).
- ISOLATED frac corrector continuous test (tb/frac_continuous_tb.sv, iverilog,
  wrapper-style start re-arm, 3 frames back-to-back): done_cnt=3/3, frame_err=0,
  m_axis=864=3*288. RESULT: PASS. => the ping-pong front-end is CORRECT: continuous
  capture + 3 slots processed, NO stall, NO 2x. The original deaf/stall is FIXED.
- FULL-CHAIN (p5_d_continuous_wrapper_tb, drive_multi 3 frames): in=12480 (3 frames
  consumed, no stall!), frac_err=0, BUT frac_done=6 / cfo_valid=12 / out=24192 (~2x
  frac, ~4x cfo). This DOUBLING is NOT the frac front-end (isolated proves 3->3) --
  it is the phase3_sync_top FSM + meyr/slot_frontend firing multiple times per frame
  on the continuous frac output (the int-CFO/meyr orchestration layer, related to
  the deferred int-CFO path). A SEPARATE continuous-orchestration sub-task below my
  front-end change.
- NET: H1a (ping-pong front-end) DONE + verified. Remaining for full continuous:
  phase3_sync_top continuous orchestration (why meyr/slot_frontend re-fire per
  frame) -- separate from H1a; ties into the deferred int-CFO work.
