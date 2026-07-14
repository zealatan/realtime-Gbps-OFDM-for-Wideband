# Multi-Frame Continuous-Streaming Sign-Off — Full OFDM RX

**Question:** Does the complete RX (`rx_full_chain_top`: sync → FFT → CE → EQ →
16-QAM demod) stream CONTINUOUSLY over MULTIPLE frames without dropping/
corrupting samples? Single-frame BER=0 is proven (gate `RX_FULL_CHAIN_GATE: PASS`,
also on ZCU216 silicon). This pins the OPEN multi-frame question.

**DUT:** `rtl/rx_full_chain_top.v` — UNMODIFIED. Test vehicle only:
`tb/rx_full_chain_multiframe_tb.sv` + `scripts/run_rx_multiframe.sh`.
**Sim:** Vivado 2021.1 xsim, real Xilinx xfft 9.1 IPs, part `xczu9eg-ffvb1156-2-e`.

**Method:** loop the proven single golden frame
(`golden/rx_downstream/tx_slot_iq.hex`, 4160-sample INPUT_PERIOD) N=5 times
BACK-TO-BACK (no idle, no reset). Every frame is byte-identical ⇒ each frame's
expected demod is the SAME 10608-bit golden vector. Per-frame BER vs
`golden/rx_downstream/tx_bits.txt`. Two source modes.

---

## SIM RESULT — per-frame BER, N=5 looped identical golden frames

| Frame | mode (a) backpressure-honoring | mode (b) free-running |
|---|---|---|
| 0 | LOCK, **0** err — **PASS** | LOCK, **0** err — **PASS** |
| 1 | LOCK, 364 err (3.4%) — FAIL | LOCK, 351 err (3.3%) — FAIL |
| 2 | LOCK, 405 err (3.8%) — FAIL | LOCK, 423 err (4.0%) — FAIL |
| 3 | **no lock, 0 bits** — FAIL | **no lock, 0 bits** — FAIL |
| 4 | **no lock, 0 bits** — FAIL | **no lock, 0 bits** — FAIL |
| **in / drop** | in=20800 / **drop=0** | in=20792 / **drop=8** |
| **GATE** | FAIL ok=1/5 | FAIL ok=1/5 |

`lock_pulses=3` in both modes (only 3 frames ever lock; only frame 0 demods clean).

### Verdict: the receiver does NOT stream continuously. Only frame 0 is BER=0.

Two coupled failures, BOTH inside `phase3_sync_axis_dma_wrapper`'s continuous
path (NOT in the verified downstream FFT/CE/EQ/demod, NOT the meyr estimator):

1. **Per-slot integer-CFO correction corrupts slots 1+.** Frames 1–2 lock and
   produce all 10608 bits but with ~3–4% BER — the wrapper's int-CFO
   rotator/NCO (`u_int_nco` + `u_int_rot`) de-rotates slot k using slot k−1's
   estimate; its phase origin is not aligned to the FFT/symbol boundary the
   downstream uses, so it injects a residual per-subcarrier error into every
   slot after the first. (Frame 0 sees step_word=0 → identity → clean.)
2. **Multi-slot re-arm hard-stalls after 3 locks.** Frames 3–4 never lock and
   produce 0 bits even though ALL 20800 input samples were accepted (drop=0 in
   mode a). This is a re-arm/setup-latency limit, not an input-drop.

---

## Source-contract dependency (Bug B at the input)

Both modes give nearly identical full-chain results because the downstream FFT
front-end rarely back-pressures the sync M_AXIS, so the per-slot capture
"deaf window" the free-running source could exploit is small here — only **8**
beats dropped (vs **653** when the bare sync DUT is hammered free-running:
`vivado_xsim/logs/p5_drop_build/sim.log`). The contrast at the sync-DUT level
(unchanged finding, confirming the prior analysis) is sharp:

| Source | `iq_capture_pingpong` per-buffer length | sync locks (3 frames) |
|---|---|---|
| backpressure-honoring | exactly 4160 every buffer (clean) | **3/3** (`p5_rearm_build`) |
| free-running | 4156, then 3511 (mis-bounded by drops) | recovers to 3/3 but mis-aligned (`p5_drop_build`) |

So input-drop (Bug B) IS real and IS source-contract-dependent, but in the FULL
chain it is NOT the dominant multi-frame failure — the wrapper int-CFO/re-arm
bugs dominate and break streaming even with a perfectly backpressuring source.

---

## Board (`11_full_rx_loopback` / `rx_full_board_top`) — does it stream cleanly?

**The on-board `dut_player.v` STRICTLY honors `s_axis_tready` (= source mode a).**
It has a registered AXIS holding register and advances `raddr`/`out_count` only
when `load_slot = (!out_tvalid_r) || m_axis_tready` — a stalled DUT can never
cause a dropped or duplicated beat (RTL header + l.110/154). The BD wires
`dut_player.m_axis → DUT.s_axis` as a **direct AXIS interface, no FIFO/DMA**
(`digital_loopback_bd.tcl` l.235). So the board would behave like sim mode (a):
the player stalls in the deaf window instead of dropping ⇒ NO input-drop on
the board, but it would hit the SAME wrapper int-CFO/re-arm wall (frames 1+
corrupted, stall after ~3) — multi-frame BER would NOT be 0.

**Board has never measured multi-frame BER.** The firmware `run_digital_loopback`
runs the player ONE-SHOT for the BER-clean single-frame capture (it explicitly
notes loop mode "caused frame-boundary artifacts: err_frame_mismatch + a bogus
meyr int-CFO from the FFT window spanning back-to-back frames"). The continuous
path (`#ifdef STREAM_TEST`, `LOOP_LOOP_EN` ctrl[29]) only snapshots
sample/slot/tlast counters — measured `tvalid%=100 tready%=86 accepted%=86,
eff_Msps~162, err=CLEAN` (throughput / no-drop confirmed, player stalls cleanly)
— it does NOT capture demod bits, and `dut_capture` DEPTH=4096 holds only one
frame's 2652 nibbles. The board therefore confirms clean STREAMING THROUGHPUT
(no drops, player honors tready) but has NOT and cannot (single-shot capture)
demonstrate multi-frame BER=0.

---

## Fix recommendation (cost) — to make the chain stream BER=0

Root cause is in `phase3_sync_axis_dma_wrapper`, two items:

- **(A) int-CFO rotator phase origin** — re-anchor the `nco_phase_gen`
  `phase_reset` to the OFDM-symbol / FFT boundary the downstream consumes (or
  load step_word with the alignment offset). Until fixed, only k=0 frame 0 is
  clean. *Cost: localized fix in the wrapper NCO/rotator + re-run the gate;
  no downstream change.* (Workaround for streaming-only validation: drive the
  int-CFO rotator step_word=0 / bypass so every slot is identity — frames 1+
  then test the re-arm path without the rotator corruption.)
- **(B) multi-slot re-arm depth** — the chain sustains only ~3 in-flight slots
  (2 ping-pong capture buffers + 1 in processing) before re-arm stalls. The
  per-slot frac-corrector SETUP latency (~778 cyc) exceeds the per-slot input
  slack (INPUT_PERIOD 4160 − FRAME_LEN 4032 = 128 cyc), so buffers back up.
  Fixes, increasing cost: (1) ensure the source back-pressures (already true on
  board — bounds drops but does NOT lift the stall); (2) **add a 3rd/Nth
  ping-pong capture buffer** in `iq_capture_pingpong` (CAP_AW already 13/8192-
  deep; +1 buffer ≈ +1 BRAM, +occupancy/pointer logic — modest) to absorb the
  setup-latency backlog; (3) **overlap the per-slot S_FRAME_DET / S_TIMING_CFO /
  S_LOAD_NCO setup** with the next capture so SETUP no longer serializes behind
  each slot (larger FSM rework). (2) is the best cost/benefit for sustaining N
  frames; (A) is independently required for BER=0 on slots 1+.

**Do NOT** modify the frozen sync DUT / downstream modules as part of *this*
test — the fixes above are the recommended next work, scoped to the wrapper.
