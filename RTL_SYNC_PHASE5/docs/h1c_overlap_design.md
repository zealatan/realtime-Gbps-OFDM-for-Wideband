# H1c: overlap detect/cfo of slot N+1 with correct/output of slot N — design

## Goal
Frac corrector FSM is serial: S_FILL -> S_FRAME_DET(~160c) -> S_TIMING_CFO(~592c) ->
S_LOAD_NCO(~17c) -> S_CORRECT(~4034c) -> S_DONE. detect+cfo (~752c) are NOT overlapped
with the output -> ~87% frac duty. Overlap them with the PREVIOUS slot's S_CORRECT to
push toward ~100% (~187 Msps @187.5MHz). The ~17c NCO spin-up remains -> ~99.6%.

## Two structural problems
1. Read-port contention: S_CORRECT reads buffer(proc_sel); detect/cfo of N+1 must read the
   OTHER buffer. NEED a 2nd independent read port out of iq_capture_pingpong. GOOD NEWS:
   each iq_frame_buffer already has its own 1-clk read port (iq_frame_buffer.v:47-51) — only
   one is "live" today (muxed by proc_sel). Expose BOTH; no true-dual-port RAM needed.
2. Monolithic FSM owns one slot_start/frac_phase/peak_lag + one NCO + one playback. Split
   into FRONT (detect+cfo, reads rd2_*/front buffer) and BACK (load_nco+correct+output,
   reads rd_*/back buffer) with a handoff register + TWO in-flight buffers.

## Architecture
### iq_capture_pingpong: add 2nd read port (dual-read) + 2-owner ownership
- ADD ports: rd2_en, rd2_addr, rd2_data; front_take, front_to_back, back_free (replace
  proc_take/proc_free).
- State: front_sel/front_busy + back_sel/back_busy + claim_next (rename proc_next).
  front_take&!front_busy&buf_ready -> front_busy<=1, front_sel<=claim_next, claim_next<=~.
  front_to_back -> back_sel<=front_sel, back_busy<=1, front_busy<=0.
  back_free -> back_busy<=0, clear occ for back_sel.
- a_avail/b_avail exclude BOTH owners. buf_ready gate on !front_busy.
- INVARIANT front_sel != back_sel when both busy -> NO read arbitration. Per-buffer rd mux:
  buffer A rd_en/addr = back owns A ? rd_* : front owns A ? rd2_* : 0 (symmetric B).
  rd_data <= rdd_{back_sel}; rd2_data <= rdd_{front_sel}.

### frac corrector: split FSM
FRONT (drives rd2_*, owns u_fd + u_tfc):
  F_IDLE -> F_WAIT_BUF(front_take,fd_start) -> F_FRAME_DET -> F_TIMING_CFO -> F_HANDOFF -> F_IDLE
  F_HANDOFF: latch results to handoff regs + pulse front_to_back.
Handoff regs: ho_valid, ho_slot_start, ho_frac_phase, ho_frame_ok.
BACK (drives rd_*=playback port, owns u_corr/NCO/FIFO):
  B_IDLE(wait ho_valid; copy ho_*->slot_start_r/frac_phase_r; clear ho_valid)
  -> B_LOAD_NCO (existing nco_cnt spin-up, unchanged)
  -> B_CORRECT (existing H1b 2-deep FIFO playback, unchanged, reads rd_*)
  -> B_DONE (back_free) -> B_IDLE.
Recommendation: keep the single NCO in BACK (move S_LOAD_NCO to BACK entry) -> no dual-NCO;
leaves only ~17c per-slot gap.

### Top read mux: split into TWO combinational muxes (FRONT->rd2_*, BACK->rd_* playback).
u_tfc.base_addr <- FRONT frame_index_r; u_fd/u_tfc buf_rd_data_I/Q <- rd2_data; playback
buf_rd_data <- rd_data. (Splitting buf_rd_data consumers is essential.)

## CAPACITY: 2 buffers => only 2 in flight (front N+1, back N); capture of N+2 waits on
back_free -> input duty capped, risk of drops at 187 Msps. **A 3RD buffer (u_buf_c) is
required for true ~100%** so capture N+2 overlaps both stages. (Biggest sizing decision.)

## Risks
R1(HIGH) buffer count -> need 3rd buffer. R2(MED) ownership/occ race -> single always-block,
free-before-claim. R3(MED) single NCO leaves ~17c gap (accept). R4(MED) read-data fanout
timing (keep mux 2:1, frac path is slow ~187MHz so inside closure). R5/R6(LOW) 1 handoff
slot ok (FRONT faster); status outputs become 1 slot early -> check TBs.

## PHASED PLAN (smallest first)
P1: add rd2_* dual port to iq_capture_pingpong, keep single FSM, route u_fd/u_tfc to rd2_data
    (front_sel==back_sel in serial mode). Prove plumbing transparent. Regression 11/11.
P2: split FRONT/BACK + handoff regs + front_take/front_to_back/back_free. 2-buffer partial
    overlap (~99% processing duty, input capped). Update TB latency expectations.
P3: add 3rd buffer -> full ~100% input duty -> ~187 Msps.
P4: timing + sustained-Msps closure (P5-CONT-SMOKE/NIGHTLY/ROBUST, zero cap_overflow).

Files: frac_cfo_frame_corrector_top.v (states 108-115, mux 365-384, FSM 421-545, H1b playback
489-534), iq_capture_pingpong.v (avail/mux/handoff 84-104, control 109-173, buffers 178-226),
iq_frame_buffer.v (own rd port 47-51, no change), frame_detector.v + frame_frac_cfo_top.v
(reused; their buf_rd_* -> FRONT rd2_*).

## Board duty-gap finding (parallel-agent analysis 2026-06-24)
The ~2x board-duty gap (frac-alone ~87% vs board ~45%) is NOT a single inter-slot dead-gap.
Breakdown: (1) the COMMITTED tree is 2-clk S_CORRECT (H1b reverted) -> ~8064 cyc/slot > 2
input slots -> with 2 buffers input duty is structurally ~50% (so re-applying H1b is the
biggest lever, back to ~87%); (2) the 2-buffer ping-pong caps <100% because capture N+2
waits on back_free of N -> the 3rd buffer (this doc) lifts input duty toward 100%; (3) the
board number also includes M_AXIS/DMA back-pressure (STALL_TIMEOUT / err bit3 tripping every
slot) + 4160/4032 geometry, partly an apples-to-oranges measurement vs the iverilog TB.
RECOMMENDED ORDER: int-rotator skid -> re-apply H1b -> 3rd buffer -> L1 frame-len. Also port
the in_acc/meas_cyc + st_cyc[] duty counters from tb/frac_continuous_tb.sv into the full-chain
tb/p5_d_continuous_wrapper_tb.sv to PIN the gap with a real measurement.
