# Step 20: frac_cfo_frame_corrector_top

## Goal
Integrate iq_frame_buffer + frame_detector + timing_frac_cfo_top + frac_cfo_corrector_top into a
single top-level module that: captures IQ samples, detects the frame boundary, estimates the
fractional CFO, corrects it via NCO + complex_rotator, and streams corrected samples out via
AXI-Stream.

## Key Design Decisions

### Direct sub-module instantiation (not wrapping frame_timing_sync_top)
frame_timing_sync_top (Step 19) wraps iq_frame_buffer internally without exposing its read port.
Since CLAUDE.md prohibits modifying existing RTL, Step 20 directly instantiates all primitives and
shares one iq_frame_buffer, muxing its read port across frame_detector, timing_frac_cfo_top, and
the playback FSM.

### FSM states
S_IDLE → S_FILL → S_FRAME_DET → S_TIMING_CFO → S_LOAD_NCO → S_CORRECT → S_DONE

### NCO loading sequence
load_step (nco_cnt=0) → phase_reset (nco_cnt=1) → enable (nco_cnt≥2) → wait LATENCY+2=17 clocks
→ enter S_CORRECT. Ensures sincos_valid is asserted before first buffer read is issued.

### NCO step word
step_word = {(-frac_phase_r), 16'h0000}  — sign-extend Q1.15 frac_phase to 32-bit step register.

### 1-deep hold FIFO for buffer playback
Because iq_frame_buffer has 1-cycle registered read latency, a play_rd_pend / play_hold_* state
machine absorbs the latency. A new read is only issued when the hold slot is free (or about to be
consumed), preventing bubbles without over-reading.

### slot_start address
slot_start = frame_index + peak_lag (mod 2^BUF_AW). TOTAL_SAMPLES = NSC + CP_LEN samples are
streamed starting from slot_start.

## Parameters
NSC=256, CP_LEN=32, BUF_AW=12, ACC_WIDTH=40, METRIC_WIDTH=32, INDEX_WIDTH=9,
RESULT_WIDTH=32, PHASE_WIDTH=16, POWER_WIDTH=33, ENERGY_WIDTH=40, WINDOW_LEN=25,
HIT_COUNT=10, THRESHOLD=10240000, NCO_PHASE_WIDTH=32, LATENCY=15

## Simulation result
PASS: 39   FAIL: 0   CI GATE: PASSED   (10 test groups, 39 checks)
