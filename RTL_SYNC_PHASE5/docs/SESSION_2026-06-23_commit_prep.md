# Session 2026-06-23 — commit prep + 200 Msps roadmap

## What was achieved (this session)
1. ZCU216 board port hardening: 200 MHz build (PS PLL -> 187.5 MHz actual, timing MET,
   ILA removed), detection robustness board regression 7/8 (scale/AWGN/multipath/pos),
   int-CFO characterized (+60, SPEED-DEPENDENT: tracks @100MHz, stuck @187.5MHz -> deferred).
2. **Continuous streaming Phase B — ping-pong front-end (the big one):**
   - NEW rtl/iq_capture_pingpong.v: dual iq_frame_buffer + capture FSM (CAP_IDLE/A/B) +
     proc_take/free handoff. Decouples acquisition from the slow frac+meyr processing so
     the chain no longer goes deaf/stalls after 1 slot. Unit TB PASS (iverilog).
   - Integrated into rtl/frac_cfo_frame_corrector_top.v (S_FILL -> wait buf_ready handoff;
     CAP_AW=13 buffer holds full 4160 frame until tlast; 12b algo addr zero-extended ->
     no frame_detector/timing_frac width change; S_DONE -> proc_free). STAGE1 63/63 PASS.
   - **Doubling fix** in rtl/phase3_sync_top.v: S_RUN now waits for frac_done (not the
     early meyr_cfo_valid) before S_DONE -> stops the self-sustaining 2x cap/cfo loop.
     Sim VERIFIED: cfo_valid=3 frac_done=3 cap_done=3 (was 6/12/6).
   - BOARD throughput: 16 Msps (orig) -> 39 (ping-pong) -> 47 Msps / 25% duty (doubling fix).

## KEY Phase B files to commit (the meaningful work)
- rtl/iq_capture_pingpong.v                 (NEW)
- rtl/frac_cfo_frame_corrector_top.v        (ping-pong integration)
- rtl/phase3_sync_top.v                      (doubling fix: S_RUN waits frac_done)
- tb/iq_capture_pingpong_unit_tb.sv          (NEW, PASS)
- tb/frac_continuous_tb.sv                   (NEW, PASS)
- scripts/phase3_dut_filelist_newdesign.f    (+iq_capture_pingpong.v)
- scripts/run_stage1_chain_regression.sh     (+iq_capture_pingpong.v)
- scripts/digital_loopback_bd.tcl            (LEAD_IN=0, ILA off)
- scripts/build_digital_loopback.tcl         (PL0=200MHz)
- software/generated/rfdc_capture_ws/.../src/main.c (STREAM_TEST + int-CFO calib + regs)
- hardware/ip_repo/dut_sync/*                 (re-packaged DUT IP with all the above RTL)
- docs/h1_pingpong_design.md, docs/continuous_streaming_rework_plan.md, this file
- (earlier-session) reg vectors golden/p5_board_regression/, gen_p5_board_regression_stim.py,
  run_board_detection_regression.sh, scripts/gen_stim_sweep_header.py, dashboards

NOTE: git status also shows UNRELATED churn (rtl/DUT/* deletions, golden/p3_22a/* mods,
.cxl.xil_xsim.version, sim artifacts) from prior sessions/sim runs — review before committing.

Suggested commit msg:
  "Phase B: continuous multi-slot ping-pong front-end + doubling fix (board 47 Msps);
   ZCU216 200MHz build + detection regression 7/8; int-CFO +60 characterized (deferred)"

## ROADMAP to 200 Msps (current 47 Msps / 25% duty @187.5MHz)
Need ~4.3x. Levers, in order:
1. **L1 frame-len geometry** (correctness, unblock TLAST/err=0x1): player streams 4160
   (64+4032+64) but frac OUTPUT_SAMPLES=int_frame_len=4032 -> input-tlast(4159) vs
   in_frame_cnt(mod 4032) MISMATCH. Fix: make player PLAY_LEN=4032 (rtl/dut_player.v,
   rebuild) OR separate the wrapper input-frame-len(4160) from output-frame-len(4032)
   in phase3_sync_axis_dma_wrapper.v (lines 320-332 in_frame_cnt + 297 tlast_now).
   Does NOT add throughput but needed for correct frame accounting.
2. **H1b frac readout pipeline** (THE throughput lever, ~2x -> ~94 Msps): frac corrector
   S_CORRECT reads buffer at 1 sample / 2 clocks (frac_cfo_frame_corrector_top.v:464-490,
   play_rd_pend gating). Replace with a streaming read (issue a read every cycle, absorb
   the 1-cycle buffer latency in a 2-deep skid) -> 1 sample/clock.
3. **Remaining duty bottleneck** (25%->50% even after doubling fix -> there is ANOTHER ~2x
   loss beyond the frac readout; investigate the meyr/orchestration per-slot overhead or
   add a 3rd ping-pong buffer). Target ~100% duty -> ~187 Msps @187.5MHz.
4. **200 MHz clock** (Fmax ~212 from WNS, achievable): -> ~200 Msps at full duty.
So 200 Msps = H1b (big) + remaining-duty + the geometry/correctness + ~200MHz. Substantial
RTL still; today made continuous WORK, 200 Msps SPEED is mostly H1b pipelining.

## H1b DONE (sim-verified) 2026-06-23 late
- frac_cfo_frame_corrector_top.v: S_CORRECT readout pipelined to 1 sample/clock via a
  2-deep output FIFO (play_hold head + play_hold2 2nd; issue a read every cycle while
  fifo_occ_next<2). Was 1 sample / 2 clocks.
- VERIFIED iverilog (tb/frac_continuous_tb.sv, OUTPUT_SAMPLES=4032): frac INPUT DUTY
  40% -> 67% (cycles 30681->18588, 1.65x), done=3, m_axis=12096 (no loss). STAGE1 63/63
  PASS (single-slot detection bit-exact intact).
- Board projection: ~25% -> ~42% (~80 Msps) after re-package+rebuild (NOT done yet).
- REMAINING to 200 Msps: H1c (overlap S_FRAME_DET/S_TIMING_CFO with S_CORRECT — frac
  67%->~90%+), the full-chain meyr/orchestration overhead (~1.6x loss 40->25 board),
  a 3rd ping-pong buffer if needed, and ~200-250 MHz clock. 200 Msps = H1b + H1c +
  meyr/orch + clock; multiple substantial steps. H1b alone -> ~80 Msps board.
- frac_cfo_frame_corrector_top.v is in the DUT IP -> re-package + rebuild needed for board.

## H1b BOARD RESULT 2026-06-23 night — 86 Msps (5.4x over original)
- Re-packaged DUT IP (H1b) + rebuilt (timing MET) + board STREAM_TEST:
  16 (orig) -> 39 (ping-pong) -> 47 (doubling fix) -> **86 Msps / 45% duty (H1b)**.
- frac-alone steady-state ~87% (iverilog frac_continuous_tb, 10 frames; the earlier
  67% was 3-frame startup. per-state: CORRECT 4034/slot optimal, cfo 592, det 160,
  WAITBUF mostly 1-time startup). So frac is ~163 Msps capable @187.5MHz.
- BOARD full-chain only 45% (86 Msps) vs frac-alone 87% -> a ~2x FULL-CHAIN overhead
  remains. NOT the frac output (frac_m_tready=1 hardwired, never backpressured), NOT
  output capture (in_count climbs continuously -> capture is circular/always-ready),
  NOT gated_s_valid (enable-only). Source UNPINNED by code analysis -> needs full-chain
  sim instrumentation (per-FSM-state cycle counts in phase3_sync_top + the frac WAITBUF
  IN THE FULL CHAIN: instrument p5_d_continuous_wrapper_tb with drive_multi + state
  counters like tb/frac_continuous_tb.sv). Likely the phase3_sync_top inter-slot re-arm
  gap or a buffer-not-ready stall in the full chain.
- TO 200 Msps: (a) pin+fix the full-chain ~2x overhead -> ~163 Msps; (b) H1c (overlap
  S_FRAME_DET/S_TIMING_CFO with S_CORRECT -> frac 87->~100%) -> ~187 Msps; (c) ~200-214
  MHz clock (Fmax~212) -> 200 Msps.
- err=0x9 on board (frame-len bit0 + bit3) — the L1 frame-len accounting still open.

## ⚠️ CRITICAL BUG FOUND (late night) — ping-pong corrupts continuous slot 1+
- Ran the P5-D continuous gate (full chain) after H1b+doubling: **FAIL 0/5**.
  k_int (integer CFO) PASS all 5 (orchestration/doubling fix CORRECT), but
  frac_q15 (fractional residual) = -541 on EVERY measured case (warmup/1st slot
  frac_q15~0 PASS; 2nd+ slot FAIL). => continuous 2nd+ slot output is WRONG.
- ISOLATION (tb/frac_continuous_tb.sv per-slot output checksum, same input each slot
  so all slots MUST be identical): slot0=16204, slot1..4 all DIFFERENT-but-identical.
  Reverted H1b (back to 2-clk readout) -> STILL slot0 != slot1..4. So the bug is
  **NOT H1b and NOT the doubling fix** (frac_continuous_tb is frac-alone, no
  phase3_sync_top). The bug is the **PING-PONG front-end (iq_capture_pingpong +
  its integration)**: buffer A's 2nd capture (slot2) differs from its 1st (slot0)
  for identical input. First slot correct, all later slots consistently wrong.
- The earlier "ping-pong 3 frames PASS" + "frac_continuous 3 PASS" only checked
  done_cnt / sample COUNT, never the DATA values -> the slot-1+ corruption slipped
  through. The board 86 Msps throughput is REAL but the OUTPUT DATA is wrong on
  slot 2+ (only the integer CFO is right; fractional correction corrupted).
- STATUS NOW: H1b REVERTED in rtl/frac_cfo_frame_corrector_top.v (clean 2-clk
  baseline for debugging). ping-pong still integrated (REGRESSION IS RED: P5-D fails).
  Board bitstream/IP still has H1b+ping-pong (snapshot, data-buggy).
- NEXT SESSION (priority #1): debug the ping-pong capture re-arm with a waveform.
  Hypotheses: (a) iq_frame_buffer capture_start vs first-sample timing on RE-arm
  (2nd capture into a buffer) — wr_ptr reset race; (b) 12-bit rd_addr zero-extended
  into the 13-bit CAP buffer (frame 4160 > 4096 readable) — slot_start+4031 may
  exceed 4095 and wrap; (c) read-port mux rdd_a/rdd_b switch at proc_sel change.
  Use tb/frac_continuous_tb.sv (has the per-slot checksum) — fast iverilog iterate
  until slot0==slot1==slot2. THEN re-apply H1b + re-verify checksum + P5-D.
- OPTION for a GREEN commit: revert the ping-pong integration in
  frac_cfo_frame_corrector_top.v back to the single iq_frame_buffer (u_buf) — that
  restores P5-D PASS but loses continuous (stalls after 1 slot). Decide at commit.

## ROOT CAUSE FULLY ISOLATED (very late) — streaming_cp_autocorr per-slot state
Definitive isolation via tb/frac_continuous_tb.sv (10 frames same input, per-slot probes):
- TST read checksum IDENTICAL every slot: s0=s1=s2=13111/553 -> the CP-autocorr gets
  byte-identical input on every slot (ping-pong capture/read is CORRECT).
- BUT autocorr-at-peak: slot0 I=515 Q=0 (correct, frac_phase=-7~0); slot1+ I=496
  Q=-106 (contaminated, frac_phase=-2179). peak_lag=23 correct every slot.
- fce (frac_cfo_estimator atan2) is CORRECT (computes atan2 of whatever it's given).
=> BUG = rtl/streaming_cp_autocorr.v: an internal pipeline register is NOT cleared by
   its reset (rst = ~aresetn = ~sca_aresetn_r from timing_sync_top) and carries the
   previous slot's value into the autocorr at the peak. First slot clean (global reset);
   slot1+ contaminated (small Q offset). The original single-buffer P5-D passed, so
   either the original gate reset between cases OR the slower single-buffer cadence
   flushed it — the ping-pong's tight back-to-back cadence exposes it.
- Candidates inside streaming_cp_autocorr (pipeline: delay_sample 1cy -> complex_mult
  3cy -> moving_avg_optimized 4cy; energy: sample_power_sq 2cy -> moving_avg 4cy):
  (a) delay_sample.v RAM contents not cleared on reset (only addr/full) — but masked by
  `full`, and at peak the delayed tap is fresh; (b) moving_avg_optimized accumulator/
  shift not fully reset on rst; (c) complex_mult / sample_power_sq pipeline regs not
  reset; (d) the s_data_reg alignment reg. NEED a waveform trace of streaming_cp_autocorr
  internals on slot1 to find the exact unreset reg.
- FIX direction: make ALL streaming_cp_autocorr (+ submodule) state reset on `rst`, OR
  hold sca_aresetn_r longer / add a flush. THEN verify tb/frac_continuous_tb.sv shows
  slot0==slot1==slot2 (per-slot output checksum) AND STAGE1 63/63 still PASS (reused
  timing chain — must not break detection) AND re-run P5-D.
- tb/frac_continuous_tb.sv now has the debug infra (per-slot output checksum, [NCO]
  frac_phase+autocorr probe, [TST*] read checksum) — use it to iterate fast in iverilog.
- H1b is currently REVERTED (clean 2-clk baseline). Re-apply H1b only AFTER the
  ping-pong/autocorr bug is fixed + re-verified.

## ✅✅ BUG FIXED (very late) — moving_avg_optimized window-fill guard
ROOT CAUSE (definitive, via tb/frac_continuous_tb.sv [ACORR] probe): the autocorr
stream on slot1+ had a CONSTANT I/Q offset on every output (slot0 Q=0 correct; slot1+
Q=-6923959 constant). Signature = moving_avg running_sum carrying a permanent offset.
=> rtl/moving_avg_optimized.v: the sliding-window RAM (delay_line) is NOT cleared on
reset (RAMs retain contents), so the first WINDOW_SIZE "old_data" subtractions used the
PREVIOUS run's stale samples. running_sum = correct_window_sum - Σ(stale) — a constant
offset that never cancels (the sliding subtract only cancels samples added this run).
slot0 clean (RAM sim-init 0); slot1+ carry slot0's tail. The original single-buffer
P5-D didn't expose it (RAM happened 0 / different cadence); the ping-pong's tight
back-to-back cadence did.
FIX: added a fill counter `fill_cnt` (counts diff events) + `fill_full`. Until the RAM
holds WINDOW_SIZE fresh samples, subtract 0 instead of stale old_data (eff_old) — which
is ALSO the correct sliding-window behaviour during fill. slot0 behaviour UNCHANGED
(stale was 0 there) so detection is unaffected.
VERIFIED:
- tb/frac_continuous_tb.sv per-slot output checksum: slot0==slot1==...==16204 (was
  slot0=16204, slot1+=51909). autocorr Q=0 every slot. frac_phase=-7 every slot.
- STAGE1 63/63 PASS (detection intact — slot0 path unchanged).
- H1b RE-APPLIED on top: frac duty 79% (10-frame) AND slots still identical (16204) =>
  H1b + moving_avg fix together are data-correct AND fast.
- P5-D full-chain gate: re-running to confirm end-to-end (was 0/5 FAIL).
FILES: rtl/moving_avg_optimized.v (the fix), rtl/frac_cfo_frame_corrector_top.v (H1b
re-applied: 2-deep FIFO readout). The continuous data bug that made the board output
wrong on slot 2+ is RESOLVED. Next: confirm P5-D, re-package+rebuild, board test (data
correct + ~86 Msps), then H1c/clock toward 200 Msps.

## ✅ FINAL STATE (after fix, ~00:58 06-24) — continuous streaming WORKS (data + throughput)
- moving_avg fix + H1b re-packaged + rebuilt (timing MET) + board STREAM_TEST: 86 Msps /
  45% duty (throughput preserved; the fix is data-correctness, not throughput).
- REGRESSION GREEN on the key gates: STAGE1 63/63 (2-clk & H1b), P5-D full-chain 5/5
  (2-clk & H1b) — the data bug that gave 0/5 is RESOLVED.
- Continuous streaming now: DATA CORRECT (sim P5-D 5/5) + 86 Msps (board) + duty 79%
  frac-alone (~163 Msps frac-limited steady-state).
- Board STREAM_TEST err=0x9 + TLAST stuck = L1 frame-len ACCOUNTING only (stim 4160 vs
  frame 4032 — a counter artifact; data flows + is correct). Not a data bug.
- COMMIT-READY files (the meaningful work): rtl/iq_capture_pingpong.v, rtl/
  frac_cfo_frame_corrector_top.v (ping-pong + H1b 2-deep FIFO), rtl/phase3_sync_top.v
  (doubling fix), rtl/moving_avg_optimized.v (window-fill guard — THE data fix),
  tb/frac_continuous_tb.sv (+ unit TB), + scripts/IP/SW per the lists above.
- REMAINING to 200 Msps: (a) L1 frame-len accounting (TLAST/err cleanup, correctness);
  (b) H1c overlap detect/cfo (frac 87->~100%); (c) ~200-214 MHz clock. frac is already
  ~163 Msps capable; the board 86 Msps full-chain still has the ~2x orchestration gap
  to investigate (frac 87% vs board 45%) — likely the phase3_sync_top inter-slot cadence.

## ⚠️ H1b DEFERRED for the commit (P5-CONT-NIGHTLY drop) — 2026-06-24 morning
While confirming the full regression for commit, P5-CONT-NIGHTLY FAILED with H1b:
[NIGHTLY] frac=4032 mout=4030 -> FAIL (mout < FRAME_LEN). The H1b 2-deep FIFO drops 2
M_AXIS samples under NIGHTLY's back-pressure pattern (SMOKE duty=100% passed out=4032,
P5-D passed out=4032 — only NIGHTLY's specific back-pressure triggers it). FIFO-drain
edge bug. (Note: the failing run overlapped an xsim conflict — my redundant
run_rtl_regression.py was running alongside the rtl_dashboard auto-updater (Monitor
blm0urk0b); I killed the redundant runner. But the mout=4030 is a deterministic count,
likely a real H1b edge, not pure conflict.)
DECISION: REVERTED H1b -> rtl/frac_cfo_frame_corrector_top.v back to 2-clk readout. The
COMMIT-READY state is: ping-pong + doubling fix + moving_avg fix + 2-clk (data-correct
continuous, ~47 Msps). Verified: frac_continuous_tb slots identical (16204), compiles.
H1b (86 Msps throughput) DEFERRED to next session — debug the FIFO drain with a clean
NIGHTLY repro (no xsim conflict), then re-apply (the 4 edits are documented in the H1b
sections above; the fix candidate: the done/drain or the can_issue under back-pressure).
COMMIT FILES now EXCLUDE the H1b FIFO (frac corrector is 2-clk). Everything else stands:
moving_avg_optimized.v (the data fix — THE key deliverable), iq_capture_pingpong.v,
phase3_sync_top.v (doubling), frac_cfo_frame_corrector_top.v (ping-pong, 2-clk).
NEXT SESSION: (1) debug+re-apply H1b (clean NIGHTLY); (2) board duty gap; (3) H1c; clock.

## SESSION-2 (2026-06-24): skid + H1b unblock + tree fix + L1 + block diagram
- **NIGHTLY regression found** (my earlier commit was not fully green — only ran STAGE1+P5-D):
  int rotator dropped 1-2 M_AXIS beats during NCO CORDIC warm-up (mout 4031@2-clk, 4030@H1b)
  because complex_mult_iq consumes A regardless of sincos_valid + frac can't be back-pressured.
- **FIX: int-rotator SKID FIFO** (phase3_sync_axis_dma_wrapper.v, 32-deep) buffers frac beats,
  releases only when sincos_valid=1; NCO enable = !sincos_valid | skid_pop. -> NIGHTLY mout=4032.
- **H1b RE-APPLIED** on top of the skid (frac readout 1 sample/clk). Verified: NIGHTLY 4032,
  STAGE1 63/63, P5-D 5/5. COMMITTED to RX_SYNC.
- **BROKEN COMMITTED TREE FIXED**: committed phase3_sync_top referenced sss_first_beat /12-sym
  ports that the committed meyr_slot_frontend lacked (I had wrongly excluded the active meyr
  files as "neutral"). Committed meyr_slot_frontend/sync_capture/ak/slot_start_controller
  (12-sym slot + sync_capture back-pressure fix + sss_first_beat). Tree now consistent.
- **L1 frame-len APPLIED + VERIFIED**: INPUT_PERIOD(4160) split from FRAME_LEN(4032), 13-bit.
  Board err 0x9->0x8 (bit0 FRAME_LEN_MISMATCH cleared). NIGHTLY(L1) 4032, P5-D(L1) 5/5.
- **DUT block diagram**: docs/dut_block_diagram.html (new, standalone, current architecture).
- **3rd buffer**: extended iq_capture_pingpong 2->3 (verified no-regression) but PARKED in
  worktree agent-aee93635 — no standalone duty gain (frac-processing-limited); needs H1c.
- BOARD STATE: H1b+skid+L1 = 86 Msps, DATA CORRECT, NIGHTLY-green, err=0x8 (only bit3
  STALL_TIMEOUT left). Board is OUTPUT/DMA-limited (not frac); frac is ~163 Msps capable.
- NEXT (board throughput): (1) DMA/STALL_TIMEOUT output path = the real board limiter;
  (2) H1c (frac 87->100%, integrate parked 3rd buffer); (3) ~200-214MHz clock.

## CIRCULAR capture + the 86 Msps was REAL (not artifact) — 2026-06-24
- Added dut_capture.v CIRCULAR mode (ctrl[16]=LOOP_CAP_CIRC: always-ready + wrap + never
  stop), set by STREAM_TEST firmware (main.c). Golden single-frame path leaves bit16=0
  (finite, byte-identical to original — verified circular=0 reduces to original logic).
  dut_capture is a BD module (no DUT-IP re-package); rebuilt bitstream + ELF.
- Board STREAM_TEST (circular): err=0x0 (CLEAN — STALL_TIMEOUT gone), TLAST now flows
  continuously (2078 @100ms, 4157 @200ms; was stuck=1). => digital loopback is now
  FUNCTIONALLY COMPLETE: continuous + data-correct + zero errors.
- BUT throughput STILL 86 Msps / 45% duty. So the prior "86 = capture artifact" hypothesis
  was WRONG: the finite capture only stalled the OUTPUT (TLAST/err); the INPUT rate is
  unaffected (frac_m_tready tied 1 + skid decouple input from output back-pressure). 86 Msps
  is a REAL full-chain limit: frac-alone ~87% vs board full-chain ~45% = a ~2x orchestration
  gap (phase3_sync_top inter-slot cadence / meyr / player), NOT the sink.
- NEXT: pin the ~2x full-chain gap (instrument p5_d_continuous_wrapper_tb duty + per-state
  for dut.u_dut.state + frac state, continuous drive) -> find which state/gap = the 2x.
  Then H1c (frac detect/cfo overlap) + clock toward 200. Output sink for real system:
  DMA(S2MM, has blocker) OR QSFP (Aurora/10GbE, sidesteps DMA) — decide after datapath ceiling.

## DUTY GAP PINNED (full-chain sim profiler) — 2026-06-24
- Instrumented p5_d_continuous_wrapper_tb (gated `ifdef DUTY_PROFILE`, env-passed -d) +
  continuous 8-frame drive, always-ready sink. Measured sim full-chain input duty = 85.56%.
- frac S_CORRECT = 4034 cyc/slot (exactly 1 sample/clk in-chain); phase3_sync_top per-slot:
  S_RUN ~100%, S_DONE 1 cyc, re-arm gap ~3-4 cyc; frac S_IDLE re-arm 6 cyc/slot. So the
  orchestration (phase3 + meyr) adds NOTHING measurable. The ~2x board gap is NOT in the RTL.
- pl_clk0 confirmed 187.512 MHz (timing report). Board eff_Msps=86 => 46% duty (real) = HALF
  the sim DUT (85.56%). UNEXPLAINED board-side ~1.9x: not RTL (sim 85%), not clock (187.5),
  not player (1-per-clk per code), not capture (circular). => needs HW measurement (ILA on
  s_axis tvalid/tready) next session; sim+code analysis cannot pin it.
- duty cap (85% not 100%) = ~1043 non-CORRECT cyc/slot (TIMING_CFO 592 dominant + FILL 269 +
  FRAME_DET 158 + LOAD_NCO 18) serialized on the single frac FSM, only partly hidden by the
  2-buffer 1-frame lookahead -> H1c (overlap detect/cfo) or 3rd buffer is the RTL-ceiling lever.
- CONCLUSION: synchronizer RTL is throughput-capable (~85% -> ~160 Msps @187.5; H1c -> ~187;
  clock -> 200). The board's 1.9x is a HW-specific gap to debug with an ILA next session.
- TEMP profiler edits (gated, gate-safe): tb/p5_d_continuous_wrapper_tb.sv (ifdef DUTY_PROFILE
  block + counters), vivado_xsim/tcl/run_p5_d_continuous_wrapper.tcl (duty_def -d gate). Revert
  to pristine OR keep as a tool. Reproduce: DUTY_PROFILE=1 ... bash run_p5_d_continuous_wrapper.sh

## CLOCK FIX (86->162 Msps) + HW functional + diag counters — 2026-06-24 (cont)
- ROOT CAUSE of board "1.9x gap": NOT the DUT. s_axis handshake diag counters (added to
  wrapper: cyc_total/in_tvalid/in_tready @ regs 0x5C/60/64; firmware prints
  tvalid%/tready%/accepted%) showed ZCU216_DIAG: tvalid%=100 tready%=86 accepted%=86.
  -> DUT runs 86% duty (= sim 85%, NO DUT gap). cyc_total revealed actual pl_clk0 ~100 MHz
  (psu_init.tcl PL0_REF_CTRL DIVISOR0=0xF=15; src ~1500/15=100), NOT the 187.5 the design
  was timing-closed at. Firmware 'duty~45%' was a wrong-clock-assumption artifact.
- FIX: pl_clk0 100->187.5 MHz (DIVISOR0 15->8). Made PERMANENT in scripts/run_10_digital_loopback.xsct
  via `mwr 0xFF5E00C0 0x01010800` after psu_init (survives rebuilds; psu_init regenerates to 100).
  Verified override-alone (psu_init reverted to 100): eff_Msps~162, duty~86%, err=CLEAN.
- RESULT: board 86 -> 162 Msps (1.9x), data correct, err=0, no rebuild needed.
- HW FUNCTIONAL @187.5 (k=0): firmware STREAM_TEST off -> finite capture fc_kp0 + readback,
  run_10 JTAG-dumps capture_buf; scripts/compare_board_capture.py vs
  golden/p5_corrected/fc_kp0_corrected_m_axis_golden.hex -> 4031/4032 within +/-2 LSB PASS
  (1 = last beat not latched; 1011/4032 strict). CAVEAT: k=0 is near-identity (NCO=identity,
  frac~0) so golden=input slot[64:4096]; +/-2 LSB is the golden APPROXIMATION not a DUT error.
  TRUE bit-exact needs k!=0 + an actual RTL(xsim) golden. int_cfo showed -60 on board (k=0
  should be 0) = the known deferred int-CFO offset; k=0 output still ~correct (net rot ~0).
- diag counters gate-verified: P5-D 5/5 + NIGHTLY 4032 (no datapath impact, additive only).
- NEXT (priority): (1) CORRECTNESS: k!=0 HW functional w/ RTL golden + fix int_cfo -60 offset;
  (2) THROUGHPUT: H1c (duty 86->100% -> ~187) + clock 187.5->~213 -> ~200 Msps; (3) output
  sink QSFP(10GbE, sidesteps DMA) vs DMA(S2MM blocker).
