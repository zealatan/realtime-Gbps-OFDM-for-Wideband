# L1 frame-len accounting fix (board err=0x9, TLAST stuck) — design

## Root cause (confirmed)
Board build = 4160-period player into a 4032-frame wrapper. The wrapper has TWO
4032-based counters that both go wrong:
- dut_player.v: PLAY_LEN=4160, TLAST_IDX=4159 (64 pre + 4032 slot + 64 post), loops gap-free.
- wrapper in_frame_cnt (lines ~320-328) counts input beats mod int_frame_len(4032);
  at the player's tlast (idx 4159) in_frame_cnt = 4159-4032 = 127 != 4031
  -> err_frame_mismatch (lines 331-332) -> ERROR_FLAGS bit0 (FRAME_LEN_MISMATCH).
- ERROR_FLAGS bit3 = STALL_TIMEOUT (phase3_axi_lite_regs.v:33-34), NOT frame-len:
  stall_cnt trips at 254 when m_axis_tvalid && !m_axis_tready (DMA/capture backpressure).
  => 0x9 = bit0 + bit3.
- TLAST_COUNT stuck at 1: out_frame_cnt/tlast (lines 282-313) counts M_AXIS beats mod
  4032; with the run stalling (and FSM gated on dut_done), it advances once then freezes.

Key insight: input accounting must track the player's 4160 period; M_AXIS TLAST must stay
keyed to the true corrected-slot 4032 (the 128 pad samples are dropped inside the DUT).
One int_frame_len register cannot satisfy both.

## RECOMMENDED: Option A — split INPUT_PERIOD(4160) from FRAME_LEN_SAMPLES(4032)
1. phase3_axi_lite_regs.v: add R/W reg ADDR_INPUT_PERIOD=7'h58, 12-bit, default 4160
   (mirror frame_len_samples_o: output input_period_o[11:0]; reset 12'd4160; decode/write
   like write_ok_frame; read case like ADDR_FRAME_LEN; add to is_valid_addr + bresp OKAY).
2. phase3_sync_axis_dma_wrapper.v: wire int_input_period[11:0] from u_regs; use it INSTEAD
   of int_frame_len ONLY in the input counter + mismatch (lines 325 wrap, 332 compare).
   Leave out_frame_cnt/tlast_now (297-313) on int_frame_len=4032.
3. main.c: write 4160 to 0x58 alongside the 4032 write to 0x0C (line ~432).
- Needs bitstream rebuild (small, low timing risk). Correct on BOTH counters; preserves
  detector lead-in (64 pre-zeros still flow).

## REJECT Option B (SW-only, FRAME_LEN=4160): int_frame_len is 12-bit -> 4160 truncates to
   64; also breaks M_AXIS TLAST (waits for 4160 output beats that never arrive). Not viable.

## Option C (alt, rebuild): reset in_frame_cnt on the player's s_axis_tlast; flag mismatch
   only if tlast arrives with in_frame_cnt < NSC (catch truncated frames, self-adapt to
   any period). Leaves out_frame_cnt on 4032. Weaker explicit guard than A.

## NOTE: bit3 STALL_TIMEOUT is a SEPARATE M_AXIS/DMA-readiness issue. After Option A,
re-read ERROR_FLAGS; if bit3 persists, the corrected-output consumer (dut_capture/DMA)
is throttling M_AXIS past the 254-cycle watchdog — investigate separately. (Firmware
already W1C-acks ERROR_FLAGS by writing 0xFFFFFFFF to 0x54.)

Files: phase3_sync_axis_dma_wrapper.v (320-332, 282-313, 354-365, u_regs ~419-474),
phase3_axi_lite_regs.v (ADDR_FRAME_LEN=0x0C@122, frame_len default@471, free 0x58+),
hardware/rtl/dut_player.v (36-38,168-176), scripts/digital_loopback_bd.tcl (189-193),
software/.../main.c (83,84,432, STREAM_TEST 463-565).

## ⚠️ CORRECTION (parallel-agent review): use 13-bit, not 12-bit
int_input_period / in_frame_cnt must be **>=13 bits** — 4160 = 0x1040 does NOT fit in
12 bits (truncates to 64, silently reintroducing the bug). Widen input_period_o (reg),
the read-mux slice, int_input_period (wire), and in_frame_cnt register+comparators to 13b
(or 16b). Apply-ready patch (exact old->new per file) was produced; ADDR_INPUT_PERIOD=0x58
is free (ADDR_WIDTH=7). Also: AXI-COV gate sweeps the reg set -> add the 22nd register to
its expected list or P5-AXI-COV will fail. Bitstream rebuild required (small, low timing risk).
