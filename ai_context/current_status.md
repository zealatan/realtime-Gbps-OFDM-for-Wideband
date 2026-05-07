# RTL_SYNC Project — Current Status

## Project Goal

Full RTL replacement of the C `synchronization()` function in `ref/receiver.c`.

This is **not** a timing-only project. The complete synchronization path is:

```text
frame detection → CP autocorrelation timing → fractional CFO estimation →
fractional CFO correction → PSS/SSS FFT → integer CFO estimation (Meyr) →
integer CFO correction
```

Final RTL top: `ofdm_synchronizer_top.v`

---

## Completed Steps

### Step 1 — Workspace Audit and DUT Ladder Analysis

Status: **COMPLETE**

- Inspected all 10 existing RTL files and classified into DUT profiles
- Built DUT ladder from Level 0 (and2.v) to Level 9 (simple_dma_add_ctrl.v)
- Confirmed all 664 simulation checks pass across all existing DUTs
- Identified `ai_context/` as empty (now populated)

### Step 2 — Full C Synchronizer Scope Extraction and RTL Architecture Mapping

Status: **COMPLETE**

- Analyzed `ref/receiver.c` (53 KB) — all synchronizer functions fully read
- Built actual C call graph rooted at `synchronization()`
- Key finding: `auto_corr_norm()` is not a separate function; normalization is
  inline in `VanDeBeekAutoCorrelation()`
- Summarized all 10 synchronizer stages (function, inputs, outputs, RTL difficulty)
- Created C-to-RTL block mapping table (14 mappings)
- Proposed `ofdm_synchronizer_top.v` hierarchy (16 RTL modules)
- Identified reuse for `axis_complex_mult.v`, `axi_lite_regfile.v`,
  `simple_dma_add_ctrl.v`, `axi_mem_model.sv`
- Defined 30-step implementation roadmap
- Listed all fixed-point and interface decisions needed in Step 3

Key constants confirmed from `pluto.h`:
- NSC = 256 (FFT size / subcarriers)
- CP_LEN = 32 (cyclic prefix samples)
- energy detection: threshold=40000, wndLen=25, run-of-10

Output document: `docs/step2_full_sync_scope_from_receiver_c.md`

---

### Step 3 — Fixed-Point and Interface Specification

Status: **COMPLETE**

Produced `docs/step3_fixedpoint_spec.md` covering:
- All 17 global fixed-point parameters with recommended values, reasoning, affected blocks, overflow risk
- AXI-Stream IQ sample format: lower 16 = I (Q1.15), upper 16 = Q (Q1.15)
- axis_complex_mult.v naming mismatch documented; complex_mult_iq.v wrapper planned
- Stage-by-stage width analysis for all 10 synchronizer stages
- CORDIC decision: Xilinx CORDIC IP v6.0 for atan2 (Stage 5) and sin/cos (Stages 6, 10)
- NCO phase accumulator: 32-bit, wraps naturally, step word encoding defined
- FFT: two instances (256-pt and 512-pt), Block Floating Point mode, no fftshift
- AXI-Lite register map: 15 registers at 0x00..0x38
- Saturation policy: all arithmetic stages saturate except NCO (intentional wrap)
- 8 known implementation hazards documented for Steps 4+

Key decisions:
- DATA_WIDTH = 32, SAMPLE_FRAC_BITS = 15 (Q1.15)
- ACC_WIDTH = 40 (covers 32-tap correlator and 25-sample energy window)
- NCO_PHASE_WIDTH = 32 (7 mHz resolution at 30.72 MSPS)
- FFT_DATA_WIDTH = 16, BFP scaling mode
- AXIL threshold reset = 10,240,000 (= C float 40000 × 256 for Q1.15 input)

Output: `docs/step3_fixedpoint_spec.md`

### Step 4 — Full RTL Architecture and Module Boundary Specification

Status: **COMPLETE**

Produced `docs/step4_rtl_architecture_spec.md` covering:
- Buffer-then-process architecture rationale (vs pure streaming)
- Full module hierarchy: 18 modules, 15 new + 3 reused/wrapped
- Top-level port list for ofdm_synchronizer_top.v (all AXI-Stream + AXI-Lite + IRQ)
- Per-module specification for all 18 modules: parameters, port lists, latency, internal storage
- sync_control_fsm: 10 states (IDLE → FILL → FRAME_DETECT → CP_AUTOCORR → FRAC_CFO_EST
  → FRAC_CFO_CORR → INT_CFO_EST → INT_CFO_CORR → DONE / ERROR)
- Inter-module handshake protocol (start/done pulses + buffer arbitration rules)
- Memory allocation: ~219 Kbit total, ~7 × BRAM36, ~56 Kbit distributed RAM
- Latency budget: ~34,000 clocks / 341 µs at 100 MHz (5× slot period, acceptable for one-shot sync)
- DSP resource estimate: ~39 DSP48, ~7 BRAM36, ~2270 LUTs — fits on XC7A100T and XC7A35T
- Build order: Steps 6–30 sequenced by dependency graph

Key architecture decisions:
- complex_mult_iq.v wrapper (zero-LUT, bit-reorder only) fixes axis_complex_mult.v convention mismatch
- CONJ_A/CONJ_B parameters on complex_mult_iq.v for conj(A)×B without extra logic
- fft_wrapper.v (512-pt): single reconfigurable instance run 3× sequentially (saves BRAM vs 3 instances)
- Shared nco_phase_gen.v + complex_rotator.v between frac and int CFO correction passes
- INT_CFO_CORR uses output_mode=1: corrected samples stream directly to m_axis_iq, no second buffer needed
- α·max + β·min approximation for timing metric magnitude (no CORDIC in timing_metric_core)
- int_cfo decoding: int_cfo = peak_index − 255 (= NSC−1)

Output: `docs/step4_rtl_architecture_spec.md`

---

### Step 5 — Implement and Verify `peak_detector.v`

Status: **COMPLETE**

Created:
- `rtl/peak_detector.v`  — parameterized unsigned argmax, 61 lines
- `tb/peak_detector_tb.sv`  — 20 test groups, 66 checks
- `scripts/run_peak_detector_sim.sh`  — Vivado xsim script for peak_detector
- `md_files/05_peak_detector_prompt.md`  — prompt backup

Key implementation decisions:
- Parameters: METRIC_WIDTH=64, INDEX_WIDTH=9, COUNT_WIDTH=10
- Strict `>` comparison → first occurrence wins on ties (deterministic)
- `start` pulse resets all internal state (count, running_max, peak_index/value)
- `done` is a 1-clock pulse; peak_index/peak_value are stable until next start
- `error` is sticky (cleared only by aresetn): set on start-while-busy or count overflow
- max_count=0 disables overflow check
- start and data processing are in separate `if` blocks (not `else if`): start on a clock
  ignores data_valid on that same clock — safe given the start/done protocol timing

Test coverage (66 PASS, 0 FAIL):
- T1: reset outputs clear
- T2: single element
- T3–T4: max at first / last index
- T5: max in the middle
- T6: all-equal → tie-break at index 0
- T7–T8: strictly increasing / decreasing
- T9: two equal maximums → first wins
- T10: done is exactly 1-clock wide; peak_index/value stable afterward
- T11: busy deasserts coincident with done
- T12: start-while-busy sets and holds error
- T13: 4 consecutive scans without gap
- T14: 256-element array (timing metric size)
- T15: 511-element array (Meyr correlation size)
- T16–T18: all-zero, single non-zero at first/last
- T19: max_count=0 disables overflow error
- T20: 30-scan PRNG smoke test

---

### Step 6 — Implement and Verify `iq_frame_buffer.v`

Status: **COMPLETE**

Created:
- `rtl/iq_frame_buffer.v` — behavioral reg-array IQ frame buffer, 122 lines
- `tb/iq_frame_buffer_tb.sv` — 15 test groups, 43 checks
- `scripts/run_iq_frame_buffer_sim.sh` — Vivado xsim script
- `md_files/06_iq_frame_buffer_prompt.md` — prompt backup

Key implementation decisions:
- Parameters: DATA_WIDTH=32, ADDR_WIDTH=12, DEPTH=4096
- AXI-Stream fill port with capture_start/busy/capture_done handshake
- Write-back port (wb_en/wb_addr/wb_data) has priority over stream fill; deasserts tready
- Random-access read port: 1-clock registered latency
- Full detection: `&wr_ptr` (correct for DEPTH=2^ADDR_WIDTH only)
- capture_done is a 1-clock pulse on tlast or full
- capture_start while busy: silently ignored
- accept = busy && s_axis_tvalid && !full && !wb_en

Test coverage (43 PASS, 0 FAIL):
- T1: reset state
- T2: single-sample fill (tlast on beat 0)
- T3: 4-sample fill, status checks
- T4: 4-sample readback (1-clock latency)
- T5: read latency exactly 1 clock, consecutive reads
- T6: fill-to-DEPTH without tlast (self-terminates on full)
- T7: tready=0 when full and not capturing
- T8: full DEPTH read-back (64/64 match)
- T9: write-back overwrites specific address
- T10: tready back-pressure while wb_en active
- T11: capture_done width is exactly 1 clock
- T12: 4 consecutive captures, independent counts
- T13: wb while idle writes correctly
- T14: capture_start while busy is ignored
- T15: PRNG smoke test (32 samples, all match)

Testbench fix: `read_n` task's dynamic array output must be sized inside the task
(`got = new[n]`); Vivado xsim initializes output-mode dynamic arrays to empty.

---

### Step 7 — Implement and Verify `frame_detector.v`

Status: **COMPLETE**

Created:
- `rtl/frame_detector.v` — sliding-window energy frame detector, ~180 lines
- `tb/frame_detector_tb.sv` — 16 test groups, 42 checks
- `scripts/run_frame_detector_sim.sh` — Vivado xsim script
- `md_files/07_frame_detector_prompt.md` — prompt backup

Key implementation decisions:
- Parameters: DATA_WIDTH=32, ADDR_WIDTH=12, POWER_WIDTH=33, ENERGY_WIDTH=40, WINDOW_LEN=25, HIT_COUNT=10
- Threshold comparison WITHOUT division: compares energy_acc (window SUM) vs threshold_in × window_len_in
  (threshold_in must be Q1.15-scaled: default 10,240,000 = C's 40000 × 256)
- Case A (initial window below threshold): scan forward counting consecutive above-threshold windows
- Case B (initial window at or above threshold): skip initial above-threshold region, then Case A
- Sliding window circular power buffer (64 entries max, register array)
- first_hit_addr latches the buffer address of the first window in each consecutive run
- 2-state pipeline per sample: S_FETCH (1 cycle) + S_PROC (1 cycle) = 2 cycles/sample
  (matches iq_frame_buffer's 1-clock registered read latency)
- found_flag blocking temporary controls state transition to avoid dual non-blocking conflict

Test coverage (42 PASS, 0 FAIL):
- T1: reset outputs clear
- T2: all below threshold → not found (Case A exhausted)
- T3: Case A, hit_count=2, frame found at index 5
- T4: Case A, hit_count=1 (immediate on first hit)
- T5: Case A, broken run resets counter; second run succeeds
- T6: Case B, skip then find frame
- T7: Case B, never drops below threshold → not found
- T8: window_len=4 multi-sample window, sliding accumulator correct
- T9: non-zero search_base, frame_index offset correctly
- T10: done is exactly 1-clock wide
- T11: busy deasserts simultaneous with done
- T12: search_len = window_len (only 1 window, no slides) → not found
- T13: search_len = window_len+1 (one slide, but mixed energy → below threshold)
- T14: back-to-back scans, frame_found resets on new start
- T15: hit_count=1, frame found immediately
- T16: PRNG smoke (5 random scans with known HI positions)

---

## Next Step

### Step 8 — Implement and Verify `complex_mult_iq.v`

Status: **COMPLETE**

Created:
- `rtl/complex_mult_iq.v` — AXI-Stream wrapper around axis_complex_mult.v, ~100 lines
- `tb/complex_mult_iq_tb.sv` — 15 test groups, 107 checks (3 DUT instances in parallel)
- `scripts/run_complex_mult_iq_sim.sh` — Vivado xsim script (requires -timescale 1ns/1ps on xelab)
- `md_files/08_complex_mult_iq_prompt.md` — prompt backup

Key implementation decisions:
- Project convention: tdata[15:0]=I (real), tdata[31:16]=Q (imaginary)
- axis_complex_mult convention: upper=real, lower=imaginary
- Wrapper swaps each input: {Q,I} → {I,Q} before axis_complex_mult; swaps output back
- CONJ_A=1: negates Q_a (tdata[31:16]) with ~q+1 before the input swap (forms conj(A)×B)
- CONJ_B=1: negates Q_b symmetrically
- Note: step4 spec has a bug in the CONJ code snippet (negates I instead of Q);
  implementation uses mathematically correct version (negate Q = upper bits of input)
- All AXI-Stream handshake (tready, tvalid, tlast) pass through axis_complex_mult unchanged
- -timescale 1ns/1ps on xelab required because axis_complex_mult.v has no timescale directive

Test coverage (107 PASS, 0 FAIL) — 3 DUT instances (CONJ_A=0/1/0, CONJ_B=0/0/1):
- T1: reset → valid=0 on all instances
- T2-T9: fundamental complex products with known I/Q combinations; golden models verified
- T10: back-pressure: output held when tready=0; a_tready deasserts
- T11: tlast passes through all instances
- T12: 3 consecutive transactions (pipeline streaming)
- T13: only A valid (B invalid) → no accept, no output
- T14: negative inputs (−0.5 × −0.5 = +0.25)
- T15: A≠B verifying asymmetry of CONJ_A vs CONJ_B

---

---

### Step 9 — Implement and Verify `cp_autocorr_core.v`

Status: **COMPLETE**

Created:
- `rtl/cp_autocorr_core.v` — 4-state MAC engine (FETCH_A, LATCH_A, FETCH_B, ACCUM), ~180 lines
- `tb/cp_autocorr_core_tb.sv` — 15 test groups, 80 checks
- `scripts/run_cp_autocorr_core_sim.sh` — Vivado xsim script
- `md_files/09_cp_autocorr_core_prompt.md` — prompt backup

Key implementation decisions:
- Buffer timing: 1-clock registered latency (same as iq_frame_buffer / frame_detector pattern)
  Address presented via NB → buffer registers at next clock → data valid one clock later.
  Each tap costs 4 cycles: FETCH_A (wait) + LATCH_A (latch A, present addr_B) + FETCH_B (wait) + ACCUM (compute).
- Total latency: 4 × CP_LEN × NSC + 1 = 32,769 clocks at defaults (~328 µs at 100 MHz)
- Inline MAC: no complex_mult_iq.v instantiated; 40-bit signed accumulators per lag
- 33-bit intermediate products to prevent overflow on sum of two 32-bit terms
- Energy: sum of 4 squared terms; max = 4×2^30 = 2^32 needs 33-bit intermediate
- Result stored in three 256×32-bit register arrays (lower 32 bits of 40-bit accumulator)
- Result read port is fully combinatorial (zero latency)
- done is 1-clock pulse; busy deasserts simultaneously with done
- start ignored while busy (safe guard)

Test coverage (80 PASS, 0 FAIL) — DUT params: NSC=16, CP_LEN=4, ADDR_WIDTH=8:
- T1: reset outputs clear
- T2: all-zero buffer → all results zero (both first and last lag checked)
- T3: single tap real-only (lag=0, tap=0 only); adjacent lag is zero
- T4: all CP_LEN taps of lag=0, real-only (verified P_I=20000, P_Q=0, E=50000)
- T5: Q-only inputs (I=0); P_I/P_Q/E correct
- T6: mixed I+Q single tap; P_I=20000, P_Q=2500, E=58125
- T7: two non-zero lags simultaneously (lag=0 and lag=5); third lag zero
- T8: done pulse width exactly 1 clock
- T9: busy deasserts with done; busy asserts immediately on start
- T10: back-to-back runs update results correctly (results not stale)
- T11: non-zero base_addr; reads happen at correct buffer offset
- T12: negative input values; P_I=10000, P_Q=-17500, E=58125
- T13: all NSC=16 lags non-zero (full sweep); golden model vs DUT at lag 0, 8, 15
- T14: result_rd_addr selects different lags post-run (lag 2, 11, 7)
- T15: PRNG smoke test (random 16-bit values, golden model verify)

---

### Step 10 — Implement and Verify `timing_metric_core.v`

Status: **COMPLETE**

Created:
- `rtl/timing_metric_core.v` — combinatorial metric stream from cp_autocorr_core results, ~152 lines
- `tb/timing_metric_core_tb.sv` — 15 test groups, 59 checks
- `scripts/run_timing_metric_core_sim.sh` — Vivado xsim script
- `md_files/10_timing_metric_core_prompt.md` — prompt backup

Key implementation decisions:
- 3-state FSM: S_IDLE → S_RUN → S_DONE
- result_rd_addr = lag (combinatorial); cp_autocorr_core read port is zero-latency
- Magnitude approximation: |P| ≈ max(|I|,|Q|) + (min>>2) + (min>>3) = max + 3/8·min (underestimates ≤3.5%)
- Sign extension: I/Q inputs sign-extended to 33 bits before abs() to handle –2^31 correctly
- metric_full = 2×mag_approx − E (34-bit wrap subtraction; M ≤ 0 always by Cauchy-Schwarz)
- metric_out = metric_full[METRIC_WIDTH-1:0]; unsigned representation maps least-negative M to largest value
- Total latency: num_lags + 1 clocks (num_lags cycles in S_RUN, 1 cycle in S_DONE)
- metric_valid = (state == S_RUN); metric_last = S_RUN && lag == num_lags_r − 1
- done is 1-clock pulse; busy deasserts simultaneously with done

Testbench fix (capture off-by-one):
- Bug: run_and_capture used @negedge → start → @negedge → deassert → @posedge, landing at lag=1
- Fix: @negedge → start → @posedge → deassert, so first sample is taken at lag=0 (S_RUN entry cycle)

Test coverage (59 PASS, 0 FAIL):
- T1: reset outputs clear
- T2: all-zero inputs → M=0 for all lags
- T3: real-only single non-zero lag (PI=20000, E=50000 → M=-10000)
- T4: mixed I+Q at lag=3 (PI=20000, PQ=2500, E=58125 → M=-16251)
- T5: num_lags=4; verified cnt=4, last=3, lag0 and lag3 values
- T6: metric_valid gating (0 before start, 1 in RUN, 0 after done)
- T7: metric_last exactly on last lag (num_lags=5, last_pos=4)
- T8: done pulse width exactly 1 clock
- T9: busy deasserts on done; asserts on start
- T10: back-to-back runs update results correctly
- T11: negative inputs → abs identical to positive equivalents
- T12: large values near 32-bit range (PI=2^30, E=2^31 → M=0)
- T13: num_lags=1 (single output, metric_last on first/only output)
- T14: all 8 lags with distinct values — full golden model check
- T15: PRNG smoke test (8 random lags, golden model verify)

---

### Step 11 — Implement and Verify `cordic_atan2.v`

Status: **COMPLETE**

Created:
- `rtl/cordic_atan2.v` — behavioral simulation model of Xilinx CORDIC IP v6.0 translate mode, ~70 lines
- `tb/cordic_atan2_tb.sv` — 13 test groups, 38 checks
- `scripts/run_cordic_atan2_sim.sh` — Vivado xsim script
- `md_files/11_cordic_atan2_prompt.md` — prompt backup (TODO)

Key implementation decisions:
- Synthesis target is Xilinx CORDIC IP v6.0 (translate/atan2 mode); this file is the simulation behavioral model
- tready=1 always (parallel fully-pipelined architecture: accepts 1 sample per clock)
- tdata packing: [INPUT_WIDTH-1:0]=I, [2*INPUT_WIDTH-1:INPUT_WIDTH]=Q (32+32=64-bit tdata)
- Phase encoding: 0x7FFF=+π, 0x8001≈-π (Q1.15, normalized to ±(2^(PW-1)−1))
- LATENCY=15 shift-register pipeline; tvalid propagates through same pipeline
- Behavioral computation: $atan2(Q,I)/π × (2^(PW-1)−1), truncated via $rtoi
- Real arithmetic in always@(*) block is simulation-only; fully synthesizable IP replaces this at build time

Test coverage (38 PASS, 0 FAIL):
- T1: reset state (tready=1, dout_valid=0)
- T2: angle=0 (I=+100000, Q=0) → 0x0000
- T3: angle=+π/2 (I=0, Q=+100000) → 0x3FFF (16383)
- T4: angle=-π/2 (I=0, Q=-100000) → 0xC001 (-16383)
- T5: angle=+π (I=-100000, Q=0) → 0x7FFF (32767)
- T6: angle=+π/4 (I=Q=+100000) → 0x1FFF (8191)
- T7: latency = exactly 15 clocks (not valid at T+14, valid at T+15)
- T8: tvalid=0 input → no valid output after LATENCY clocks
- T9: tready always 1 (before, during, after a run)
- T10: 5 back-to-back streaming samples — all 5 outputs match golden model
- T11: reset mid-stream — valid=0 during and after reset
- T12: all 4 quadrants (±π/4, ±3π/4) — exact golden model match
- T13: PRNG smoke test (8 random samples)

---

### Step 12 — Implement and Verify `frac_cfo_estimator.v`

Status: **COMPLETE**

Created:
- `rtl/frac_cfo_estimator.v` — 4-state FSM driving internal cordic_atan2 instance, ~100 lines
- `tb/frac_cfo_estimator_tb.sv` — 10 test groups, 30 checks
- `scripts/run_frac_cfo_estimator_sim.sh` — Vivado xsim script (compiles cordic_atan2 + frac_cfo_estimator)

Key implementation decisions:
- FSM states: S_IDLE, S_SEND, S_WAIT (count 0..CORD_LAT-1), S_DONE
- result_rd_addr = peak_lag_r (always combinatorial; cp_autocorr_core read is zero-latency)
- CORDIC tvalid driven combinatorially: (state == S_SEND). Cordic captures at the posedge AFTER S_SEND is entered.
- S_WAIT counts CORD_LAT=15 cycles (cnt 0..14). At cnt==14, CORDIC output reg also fires (same posedge, NB). Transition to S_DONE.
- S_DONE reads cordic_phase (stable from previous posedge NB update). Asserts frac_phase, frac_phase_valid, done.
- Total latency: CORD_LAT+2 = 17 clocks from start to frac_phase_valid
- CORD_LAT is a localparam (=15); must match cordic_atan2 LATENCY parameter
- Negation of the phase (-atan2) is deferred to NCO step-word computation (not done here)

Test coverage (30 PASS, 0 FAIL):
- T1: reset state (done=0, busy=0, frac_phase_valid=0)
- T2: angle=0 (I=+100000, Q=0) → phase=0x0000
- T3: angle=+π/2 (I=0, Q=+100000) → phase=0x3FFF (16383)
- T4: angle=-π/2 (I=0, Q=-100000) → phase=0xC001 (-16383)
- T5: angle=+π (I=-100000, Q=0) → phase=0x7FFF (32767)
- T6: peak_lag selects correct RAM entry (lags 0, 5, 10 verified)
- T7: done pulse width = exactly 1 clock
- T8: busy deasserts on done; asserts on start
- T9: back-to-back runs update result correctly
- T10: PRNG smoke test (8 random lags, golden model verify)

---

### Step 13 — Implement and Verify `nco_phase_gen.v`

Status: **COMPLETE**

Created:
- `rtl/nco_phase_gen.v` — 32-bit NCO with behavioral sin/cos pipeline, ~110 lines
- `tb/nco_phase_gen_tb.sv` — 10 test groups, 33 checks
- `scripts/run_nco_phase_gen_sim.sh` — Vivado xsim script (standalone, no submodules)

Key implementation decisions:
- `step_word_r` latched from `step_word` when `load_step=1`
- `phase_reset` synchronously clears accumulator, takes priority over `enable`
- Accumulator uses natural 32-bit unsigned wrap (modulo 2^32) — intentional, NOT saturation
- CORDIC input: phase_acc_r[31:16] (16 MSBs); encoding: 0x7FFF = +π
- CORDIC captures PRE-accumulation phase: at each posedge the pipeline sees phase_acc before the step is added
- `valid_pipe[0] = enable && !phase_reset`: ensures phase_reset cycles produce no sin/cos output
- Behavioral sin/cos: always@(*) with $sin/$cos → LATENCY-stage pipeline (synthesis replaces with Xilinx CORDIC IP)
- sincos_valid follows enable by exactly LATENCY=15 clocks
- phase_acc output is combinatorial wire from internal register (for debug / step-word programming)

Test coverage (33 PASS, 0 FAIL):
- T1: reset state (phase_acc=0, sincos_valid=0)
- T2: step_word=0, phase stays 0; sin(0)=0, cos(0)=1 (after LATENCY)
- T3: positive step_word: phase_acc increments correctly over 4 cycles
- T4: negative step_word: phase_acc decrements (two's complement wrap)
- T5: sincos_valid timing: not valid at T+LATENCY-1, valid at T+LATENCY
- T6: enable=0 gaps: phase_acc holds for 3 gap cycles, resumes on next enable
- T7: wraparound: step=0x80000001, two enables wrap 0→0x80000001→0x00000002
- T8: phase_reset mid-run clears accumulator; restart from 0
- T9: load_step latches correctly (no step loaded → no increment; after load → correct increment)
- T10: golden model sin/cos check (4 samples, step=2^28 = 22.5° increments; 0°→22.5°→45°→67.5°)

---

---

### Steps 14–19 — COMPLETE AND VERIFIED

- Step 14: `complex_mult_iq.v` (done as Step 8, 107 checks)
- Step 15: `complex_rotator.v` — COMPLETE AND VERIFIED
- Step 16: `frac_cfo_corrector_top.v` — COMPLETE AND VERIFIED
- Step 17: `timing_sync_top.v` — COMPLETE AND VERIFIED
- Step 18: `timing_frac_cfo_top.v` — COMPLETE AND VERIFIED
- Step 19: `frame_timing_sync_top.v` — COMPLETE AND VERIFIED

---

### Step 20 — Implement and Verify `frac_cfo_frame_corrector_top.v`

Status: **COMPLETE**

Created:
- `rtl/frac_cfo_frame_corrector_top.v` — full integration: capture → frame detect → timing/CFO → NCO correction → corrected AXI-Stream output
- `tb/frac_cfo_frame_corrector_top_tb.sv` — 10 test groups, 39 checks
- `scripts/run_frac_cfo_frame_corrector_top_sim.sh` — Vivado xsim script
- `md_files/20_frac_cfo_frame_corrector_top_prompt.md` — prompt backup
- `docs/step20_frac_cfo_frame_corrector_top.md` — documentation

Key implementation decisions:
- Directly instantiates sub-modules (iq_frame_buffer, frame_detector, timing_frac_cfo_top,
  frac_cfo_corrector_top) with a shared buffer; does NOT wrap frame_timing_sync_top (Step 19)
  because that module does not expose its buffer read port
- 7-state FSM: S_IDLE → S_FILL → S_FRAME_DET → S_TIMING_CFO → S_LOAD_NCO → S_CORRECT → S_DONE
- NCO loading: 17-clock wait in S_LOAD_NCO (load_step → phase_reset → enable × LATENCY+2)
- NCO step word: step = {(-frac_phase_r), 16'h0000} (Q1.15 sign-extended to 32-bit)
- 1-deep hold FIFO absorbs iq_frame_buffer 1-cycle read latency during S_CORRECT playback
- slot_start = frame_index + peak_lag; TOTAL_SAMPLES = NSC + CP_LEN samples streamed from slot_start

Known RTL quirks:
- iq_frame_buffer.mem[] register array is NOT cleared on reset — T5 uses max threshold (ENERGY_WIDTH'1)
  to guarantee frame_detector finds no frame regardless of stale buffer content
- nco_cnt reg must be declared BEFORE combinatorial wires that reference it (xvlog forward-ref rule)

Simulation result: PASS: 39   FAIL: 0   CI GATE: PASSED

---

## Repository State

- `rtl/peak_detector.v` — COMPLETE AND VERIFIED (66 checks)
- `rtl/iq_frame_buffer.v` — COMPLETE AND VERIFIED (43 checks)
- `rtl/cp_autocorr_core.v` — COMPLETE AND VERIFIED (80 checks)
- `rtl/timing_metric_core.v` — COMPLETE AND VERIFIED (59 checks)
- `rtl/cordic_atan2.v` — COMPLETE AND VERIFIED (38 checks)
- `rtl/frac_cfo_estimator.v` — COMPLETE AND VERIFIED (30 checks)
- `rtl/nco_phase_gen.v` — COMPLETE AND VERIFIED (33 checks)
- `rtl/complex_rotator.v` — COMPLETE AND VERIFIED
- `rtl/frac_cfo_corrector_top.v` — COMPLETE AND VERIFIED
- `rtl/timing_sync_top.v` — COMPLETE AND VERIFIED
- `rtl/timing_frac_cfo_top.v` — COMPLETE AND VERIFIED
- `rtl/frame_timing_sync_top.v` — COMPLETE AND VERIFIED
- `rtl/frac_cfo_frame_corrector_top.v` — COMPLETE AND VERIFIED (39 checks)
- All existing 10 DUTs and their 664 checks remain unmodified
- `ref/receiver.c` is present at `ref/receiver.c` (53267 bytes)
- `ai_context/` is populated with this file
- `docs/` contains Step 2, Step 3, Step 4, and Step 20 specification documents

## Roadmap Change — 2026-05-06

**Project focus updated to Phase 1 functional FPGA synchronizer bring-up.**

Integer CFO estimation (`int_cfo_estimator.v`) is **deferred**. The immediate priority
is hardening `frac_cfo_frame_corrector_top` through randomized verification before
advancing to synthesis and FPGA bring-up.

Revised roadmap:
- Step 21: Randomized verification campaign for `frac_cfo_frame_corrector_top`
- Step 22: Synthesis-readiness audit (Vivado OOC, ZCU102 target)
- Step 23: AXI-Lite debug/config wrapper for Phase-1 FPGA bring-up
- Step 24+: Integer CFO and remaining synchronizer chain (deferred)

---

---

### Step 21 — Randomized Verification Campaign for `frac_cfo_frame_corrector_top`

Status: **COMPLETE**

Files changed:
- `tb/frac_cfo_frame_corrector_top_tb.sv` — expanded from 39 to 176 checks (R1–R8 added)
- `docs/step21_frac_cfo_frame_corrector_randomized_verification.md` — created
- `ai_context/current_status.md` — updated

Test groups (all PASS):
- R1: Timing offset sweep, quiet-sample counts 4..19 (16 × 2 = 32 checks)
- R2: Signal config sweep (100,0), (0,100), (70,70), (-100,0) (4 × 4 = 16 checks)
- R3: Randomized frame placement, XorShift32, seed=0xDEAD_BEEF, 20 trials (20 × 2 = 40 checks)
- R4: Randomized amplitude 30..129, seed=0xCAFE_0001, 10 trials (10 × 1 = 10 checks)
- R5: AXI-Stream backpressure, delays 0/1/2/3 cycles (4 × 3 = 12 checks)
- R6: Reset robustness, 3 scenarios (3 × 3 = 9 checks)
- R7: No-frame / false-trigger rejection, max threshold (3 × 2 = 6 checks)
- R8: Buffer boundary stress, 4 configs (4 × 3 = 12 checks)

Simulation result: PASS=176, FAIL=0, CI GATE: PASSED
Randomized trials: 20 frame-placement + 10 amplitude = 30 total
CFO range tested: 0x0000..0xC000 (via CP autocorr frac_phase path)
Timing offset range: quiet 4..19 (R1) + randomized 4..15 (R3)
Backpressure patterns: 4 (delays 0..3 cycles)

Bugs found (testbench only, RTL not modified):
1. GROUP FAIL logic used `fail_cnt == 0` (global) instead of per-group delta.
   Fix: added `grp_fail_snap` variable; each group snapshots fail_cnt before its tests.
2. R1 off=0..3, R3 some trials, R8 C1 used <WINDOW_LEN=4 quiet samples → DUT got frame_error=1.
   Fix: R1 uses off+4 as quiet count (range 4..19); R3 lower bound raised to 4; R8 C1 uses off=4.

RTL modified: No.

Recommended Step 22: Phase-1 Synthesis-Readiness (Vivado OOC, xczu9eg-ffvb1156-2-e / ZCU102,
aclk 100 MHz). Windows Vivado required for actual synthesis.

---

---

### Step 22 — Phase-1 Synthesis-Readiness and Vivado Resource/Timing Check

Status: **Prepared, pending Windows Vivado execution.**

Prompt archive: `md_files/22_synthesis_readiness_prompt.md`

Files created:
- `scripts/step22_synth_check.tcl` — OOC synthesis TCL for Vivado 2022.2
- `scripts/synth_stubs/cordic_atan2_stub.v` — synthesizable port-only stub (CORDIC placeholder)
- `scripts/synth_stubs/nco_phase_gen_stub.v` — synthesizable port-only stub (CORDIC placeholder)
- `scripts/windows/run_step22_zcu102_ooc_synth.bat` — Windows batch runner
- `scripts/windows/README.md` — WSL/Windows environment guide
- `docs/step22_synthesis_readiness_report.md` — synthesis readiness audit and report

Target board: ZCU102 (`xczu9eg-ffvb1156-2-e`)
Clock port: `aclk` at 100 MHz (10.000 ns period)
Mode: OOC synthesis with CORDIC stubs

RTL audit findings:
- 2 BLOCKER modules (behavioral CORDIC simulation models):
  - `rtl/cordic_atan2.v` — uses `real`, `$atan2` — must be replaced with `cordic_v6_0` IP
  - `rtl/nco_phase_gen.v` — uses `real`, `$sin`, `$cos` — must be replaced with `cordic_v6_0` IP
- All other RTL (13 files) is synthesizable — no latches, loops, multi-driven nets found

Synthesis execution status: NOT RUN (Windows Vivado required)

RTL modified: No.

Recommended user action:
```
cd C:\RTL_SYNC
scripts\windows\run_step22_zcu102_ooc_synth.bat
```
Then copy reports back to WSL:
```bash
cp /mnt/c/RTL_SYNC/reports/step22_*.rpt /home/zealatan/RTL_SYNC/reports/
```

---

---

### Step 23 — Replace Simulation-Only CORDIC/NCO with Synthesizable RTL

Status: **COMPLETE**

Files changed:
- `rtl/cordic_atan2.v` — rewritten: 15-stage integer CORDIC vectoring pipeline (no `real`/`$atan2`)
- `rtl/nco_phase_gen.v` — rewritten: 256-entry sin/cos ROM + LATENCY-stage pipeline (no `real`/`$sin`/`$cos`)
- `tb/cordic_atan2_tb.sv` — added `PHASE_TOL=4` tolerance in `chk_phase` (integer vs float rounding)
- `tb/nco_phase_gen_tb.sv` — added `COEFF_TOL=1` tolerance in `chk_coeff` (ROM vs float rounding)
- `md_files/23_synthesizable_cordic_nco_prompt.md` — prompt archive

RTL approach:
- `cordic_atan2.v`: 35-bit signed x/y, 18-bit z; ATAN table = atan(2^-k)/π×32767 for k=0..14;
  quadrant preprocessing for I<0 and (I=0,Q<0); d_k wires (sign of y) computed combinatorially
  outside always block, not inside it (Verilog rule); 15-register pipeline, latency = 15 clocks.
- `nco_phase_gen.v`: 256-entry `initial`-block ROM (synthesizes to LUTRAM); index = phase_acc[31:24];
  NBA semantics capture pre-accumulation phase; LATENCY-stage shift register; no IP dependency.

Simulation results:
- `cordic_atan2_tb`: PASS=38, FAIL=0, CI GATE: PASSED (max observed CORDIC error = 3 LSB)
- `nco_phase_gen_tb`: PASS=33, FAIL=0, CI GATE: PASSED (max observed ROM error = 1 LSB)
- Integration `frac_cfo_frame_corrector_top_tb`: PASS=176, FAIL=0, CI GATE: PASSED

RTL synthesis-ready: Yes (no `real`, no `$sin`, no `$cos`, no `$atan2`, no `$rtoi`/`$itor`).
`scripts/synth_stubs/cordic_atan2_stub.v` and `nco_phase_gen_stub.v` no longer needed for
synthesis but remain for reference.

---

---

### Step 24 — ZCU102 OOC Synthesis Without CORDIC/NCO Stubs

Status: **Prepared, pending Windows Vivado execution.**

Files created:
- `scripts/step24_synth_check_no_stubs.tcl` — Vivado TCL; reads all 15 real RTL files, no stubs
- `scripts/windows/run_step24_zcu102_ooc_synth_no_stubs.bat` — Windows batch runner
- `docs/step24_zcu102_ooc_synthesis_without_stubs.md` — step documentation
- `md_files/24_zcu102_ooc_synthesis_without_stubs_prompt.md` — prompt archive

Target:
- Board: ZCU102, Part: `xczu9eg-ffvb1156-2-e`
- Top: `frac_cfo_frame_corrector_top`, Clock: `aclk` at 100 MHz
- Stubs used: **NONE** (real `rtl/cordic_atan2.v` and `rtl/nco_phase_gen.v` included)

Sanity simulation (rerun in Step 24 session):
- `cordic_atan2_tb`: PASS=38, FAIL=0, CI GATE: PASSED
- `nco_phase_gen_tb`: PASS=33, FAIL=0, CI GATE: PASSED
- Integration `frac_cfo_frame_corrector_top_tb`: PASS=176, FAIL=0, CI GATE: PASSED

RTL modified: No.

Recommended user action — run on Windows:
```
cd C:\RTL_SYNC
scripts\windows\run_step24_zcu102_ooc_synth_no_stubs.bat
```

Then copy reports to WSL:
```bash
cp /mnt/c/RTL_SYNC/reports/step24_*.rpt /home/zealatan/RTL_SYNC/reports/
cp /mnt/c/RTL_SYNC/reports/step24_synth_messages.log /home/zealatan/RTL_SYNC/reports/
```

Recommended Step 25 (if synthesis passes): AXI-Lite + AXI-Stream debug/config wrapper
  for Phase-1 FPGA bring-up (ILA, VIO, JTAG access to `frame_found`, `frac_phase`, `threshold_in`).
Recommended Step 25 (if synthesis fails): Fix no-stub synthesis blocker while preserving
  Step 23 simulation behavior (PASS=176).

---

---

### Step 25 — AXI-Lite + AXI-Stream Debug/Config Wrapper

Status: **COMPLETE**

Prompt archive: `md_files/25_axi_lite_stream_debug_config_wrapper_prompt.md`

Files created:
- `rtl/frac_cfo_sync_control_s_axi.v` — AXI4-Lite slave register file, 8 registers (0x00–0x1C), write FSM
- `rtl/frac_cfo_sync_axi_stream_wrapper.v` — Top-level wrapper; integrates register file + DUT
- `tb/frac_cfo_sync_axi_stream_wrapper_tb.sv` — T1–T11 test groups (23 checks)
- `scripts/run_frac_cfo_sync_axi_stream_wrapper_sim.sh` — xsim compile + run
- `docs/step25_axi_lite_stream_debug_config_wrapper.md` — step documentation

Register map (AXI-Lite, 6-bit byte address):
- 0x00 CONTROL: [2]=enable, [1]=clear_status, [0]=soft_reset_pulse
- 0x04 STATUS: [6]=out_seen, [5]=in_seen, [4]=in_frame, [3]=frm_err, [2]=frm_det, [1]=done, [0]=busy
- 0x08 CFG_CFO_STEP (stored; not yet routed to DUT)
- 0x0C CFG_TIMING_OFFSET (stored)
- 0x10 CFG_FRAME_LEN (stored)
- 0x14 SAMPLE_COUNT (R/O)
- 0x18 OUTPUT_COUNT (R/O)
- 0x1C DEBUG_STATE: {4'd0, peak_lag[8:0], frac_phase[15:0], fsm_state[2:0]}

Bugs fixed during implementation:
1. `THRESHOLD[ENERGY_WIDTH-1:0]` where ENERGY_WIDTH=40 > 32-bit integer width produces X bits in xsim.
   Fix: `{{(ENERGY_WIDTH-32){1'b0}}, THRESHOLD[31:0]}` explicit zero-extension.
2. T5 byte-strobe expected value: `4'h8` changes only bits[31:24]; result is 0xFFADBEEF not 0xFF00BEEF.
3. T10 integration: constant above-threshold signal triggers frame_detector Case B (no frame found).
   Fix: send 8 quiet + 100 active samples so Case A applies.

Simulation results:
- Wrapper TB: PASS=23, FAIL=0, CI GATE: PASSED
- Integration regression unchanged: PASS=176, FAIL=0, CI GATE: PASSED

RTL modified: No (new files only).

---

---

### Step 26 — BRAM Preload/Readback Wrapper

Status: **COMPLETE**

Prompt archive: `md_files/26_bram_preload_readback_wrapper_prompt.md`

Files created:
- `rtl/frac_cfo_sync_bram_test_wrapper.v` — AXI-Lite slave (16-bit addr), dual BRAM, stream FSMs, DUT
- `tb/frac_cfo_sync_bram_test_wrapper_tb.sv` — T1–T12 test groups (23 checks)
- `scripts/run_frac_cfo_sync_bram_test_wrapper_sim.sh` — xsim compile + run
- `docs/step26_bram_preload_readback_wrapper.md` — step documentation

Architecture: single AXI4-Lite slave (16-bit byte address)
- 0x0000–0x0028: 11 control/status/config registers
- 0x1000–0x1FFF: input_mem (1024 × 32-bit, R/W)
- 0x2000–0x2FFF: output_mem (1024 × 32-bit, R/O)
- Stream source FSM: input_mem → DUT s_axis
- Stream sink FSM: DUT m_axis → output_mem (no backpressure)
- frac_cfo_frame_corrector_top instantiated directly (Option A)

Key CONTROL bits:
- [0]=start_pulse (auto-clear), [1]=soft_reset_pulse (auto-clear)
- [2]=clr_status_pulse (auto-clear), [3]=enable (sticky)

Simulation results:
- BRAM wrapper TB: PASS=23, FAIL=0, CI GATE: PASSED
- Step 25 regression: PASS=23, FAIL=0, CI GATE: PASSED
- Step 24 regression: PASS=176, FAIL=0, CI GATE: PASSED

RTL modified: No (new files only).

---

---

### Step 27 — ZCU102 Vivado Block Design Integration (No ILA)

Status: **Prepared — pending Windows Vivado execution**

Prompt archive: `md_files/27_zcu102_bd_integration_no_ila_prompt.md`

Files created:
- `scripts/vivado/step27_create_zcu102_bd_no_ila.tcl` — Vivado Tcl: project, BD, connections, address map
- `scripts/windows/run_step27_create_zcu102_bd_no_ila.bat` — Windows batch runner
- `docs/step27_zcu102_bd_integration_no_ila.md` — step documentation
- `reports/step27/` — output directory (empty until Windows run)

Target:
- Board: ZCU102
- Part: xczu9eg-ffvb1156-2-e
- Vivado: 2022.2 (Windows only)
- BD name: sync_phase1_bd
- Vivado project: vivado/step27_zcu102_bd/

Block design architecture:
- PS (zynq_ultra_ps_e_0): M_AXI_HPM0_FPD master, pl_clk0 at 100 MHz
- AXI SmartConnect (axi_smc): 1 master in → 1 slave out
- proc_sys_reset_0: pl_resetn0 → peripheral_aresetn
- xlconstant_0: dcm_locked tied to 1
- wrapper_0 (frac_cfo_sync_bram_test_wrapper): AXI-Lite slave

Xilinx IP list:
- xilinx.com:ip:zynq_ultra_ps_e:* (PS)
- xilinx.com:ip:smartconnect:* (AXI interconnect)
- xilinx.com:ip:proc_sys_reset:* (reset synchronizer)
- xilinx.com:ip:xlconstant:* (tie dcm_locked=1)

ILA: omitted intentionally (user decision — no debug fabric in this step)
DMA: not added
External BRAM IP: not added (wrapper uses inferred BRAM)

Address map:
- wrapper_0 base: 0xA0000000
- wrapper_0 range: 64 KB (covers registers 0x0000-0x0028 + memories 0x1000-0x2FFF)

validate_bd_design: NOT RUN (pending Windows Vivado)
Synthesis: NOT RUN
Bitstream: NOT RUN
RTL modified: No

Recommended user action — run on Windows:
```
cd C:\RTL_SYNC
scripts\windows\run_step27_create_zcu102_bd_no_ila.bat
```

Log output: reports\step27\step27_create_bd.log

---

## Next Step

### Step 28 — Synthesis / Implementation / Bitstream / XSA Export

Run the Step 27 block design through the full Vivado flow on Windows:
- Synthesis + implementation + write_bitstream
- write_hw_platform → sync_phase1.xsa
- Open XSA in Vitis for ARM firmware development

Or alternatively: connect AXI-Lite CFG registers to DUT runtime inputs
(THRESHOLD, WINDOW_LEN, HIT_COUNT) before implementation.
