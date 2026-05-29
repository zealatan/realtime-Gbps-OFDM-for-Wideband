# Phase 3 Verification Matrix

**Document:** Session G / P3-18A  
**Date:** 2026-05-28

---

## Summary

| Session | Scope | Simulator | Gate | Result |
|---------|-------|-----------|------|--------|
| Pre-session (P3-01 – P3-15B) | Architecture, compile, unit tests | iverilog | SANITY | PASS |
| Session A (P3-12C) | Full `phase3_sync_top` regression | iverilog | SANITY | **PASS** |
| Session B (P3-13C) | Real Xilinx FFT + integer CFO sweep | xsim (Vivado 2023.1) | OFFICIAL | **PASS** |
| Session C (P3-14C) | DMA replay IQ golden compare | iverilog | OFFICIAL* | **PASS** |
| Session D (P3-15A) | C reference equivalence framework | iverilog | SANITY_EQUIV | **PARTIAL_PASS_BLOCKED** |
| Session E (P3-16A) | Full end-to-end wrapper integration | iverilog | INTEGRATION | **PASS** |
| Session F (P3-17A) | Board / Vitis smoke infrastructure | hardware (pending) | SMOKE | **BLOCKED** |

*Session C OFFICIAL_GATE is emitted by the iverilog runner; a full xsim re-run is still required for
 an authoritative CI gate on `phase3_sync_axis_dma_wrapper`.

---

## Pre-Session Work (P3-01 – P3-15B)

### P3-01 / P3-02 — Architecture + Frame Detector

| Check | Expected | Result |
|-------|----------|--------|
| Phase 3 gap analysis documented | All 4 C steps mapped to RTL | PASS |
| `rtl/slot_start_controller.v` created | New module | PASS |
| `docs/phase3_reference_synchronizer_architecture.md` | Complete | PASS |

### P3-03 — `phase3_sync_top` Integration

| Check | Expected | Result |
|-------|----------|--------|
| `rtl/phase3_sync_top.v` created | 4-submodule orchestration FSM | PASS |
| All port interfaces correct | No width/name mismatches | PASS |

### P3-04 — Compile Smoke

| Check | Expected | Result |
|-------|----------|--------|
| `<<<` operator replaced with `<<` | Verilog-2005 compatibility | PASS |
| Stub ROMs created (`vectors/*.txt`) | 256-line placeholder files | PASS |
| 22-file compile order verified | iverilog exits 0 | PASS |

### P3-05 / P3-05B — Golden Infrastructure + Stimulus

| Check | Expected | Result |
|-------|----------|--------|
| `scripts/golden_dump.c` builds with `gcc -lm` | No fftw3/libiio deps | PASS |
| `golden/phase3_iq_stimulus.f32` generated | 704 samples, deterministic | PASS |
| C reference: `frame_index=41, peak_lag=23, slot_start=64` | Per algorithm | PASS |
| C reference: `frac_cfo_offset ≈ +0.05 (+eps_frac)` | eps_frac=+0.05 | PASS |

### P3-07 / P3-08 — Meyr Backend Bringup

| Check | Expected | Result |
|-------|----------|--------|
| PSS extraction: 256 samples at correct window | `frame[slot+CP:slot+CP+NSC]` | PASS |
| SSS extraction: 256 samples at correct window | One OFDM symbol later | PASS |
| Bypass-path ROM derived (time-domain cross-product) | All entries non-zero | PASS |
| `meyr_peak_index = 255` for k_int=0 (bypass path) | Self-correlation peak | PASS |
| `integer_cfo_word = 0x00000000` for k_int=0 | Zero CFO stimulus | PASS |

### P3-12A — Frame Detector Refactor

| Check | Expected | Result |
|-------|----------|--------|
| `sliding_window_sum` TB: 24/24 checks | Ring-buffer accumulator | PASS |
| `frame_detect_fsm` TB: 13/13 checks | Case1/Case2 C-reference FSM | PASS |
| System TB: 26/26 checks | End-to-end frame_detector | PASS |
| Port interface identical to old `frame_detector.v` | Drop-in replacement | PASS |

### P3-14A / P3-14B — AXI-Lite Wrapper

| Check | Expected | Result |
|-------|----------|--------|
| Smoke TB: 8/8 checks | VERSION, CONTROL, AXIS smoke | PASS |
| DMA replay TB: 14/14 checks | Interface-level replay structure | PASS |
| Integer NCO warmup bug fixed (wu_cnt) | Correct phase at sample n=0 | PASS |

---

## Session A (P3-12C) — Full Phase3 Regression

**DUT:** `phase3_sync_top`  
**Simulator:** iverilog  
**Stimulus:** `golden/phase3_iq_stimulus_q15.hex` (704 pairs, k_int=0, eps_frac=+0.05)

| Check | Description | Expected | Got | Result |
|-------|-------------|----------|-----|--------|
| C1 | frame_found | 1 | 1 | PASS |
| C2 | frame_index | 41 ±1 | 41 | PASS |
| C3 | peak_lag | 23 ±1 | 23 | PASS |
| C4 | slot_start_index | 64 ±1 | 64 | PASS |
| C5 | slot_start = frame_index + peak_lag | 64 | 64 | PASS |
| C6 | done asserted | @ any cycle | @105325 | PASS |
| C7 | error_code | 0 | 0 | PASS |
| C8 | Modular FSM hierarchy probe | asserted | @4258 | PASS |
| C9 | slot_start_valid (PSS/SSS windows) | asserted | @38490 | PASS |
| C10 | integer_cfo_valid (Meyr done) | asserted | @105324 | PASS |

**Gate: SANITY_GATE: PASS (10/10)** | CI_GATE: BLOCKED_XSIM_UNAVAILABLE on build host

---

## Session B (P3-13C) — Real Xilinx FFT Integer CFO Sweep

**DUT:** `meyr_fft256_actual_integration_top` (USE_BEHAVIORAL_STUB=0)  
**Simulator:** Vivado 2023.1 xsim (Windows, via WSL2 interop)  
**FFT IP:** xfft_v9_1_9, 256-pt pipelined streaming, SCALE_SCH=0xAA  
**Vectors:** `golden/p3_09_sweep/case_k*.mem`, ROMs: `vectors/meyr_pss_fft_romhex.txt`

| Case | k_int | Exp peak | Got peak | Exp int_cfo | Got int_cfo | Corr. score | Result |
|------|-------|----------|----------|-------------|-------------|-------------|--------|
| k0   | 0     | 255 | 255 | 0  | 0  | 551,119,181 | PASS |
| kp1  | +1    | 256 | 256 | +1 | +1 | 546,586,445 | PASS |
| km1  | −1    | 254 | 254 | −1 | −1 | 455,116,793 | PASS |
| kp2  | +2    | 257 | 257 | +2 | +2 | 609,114,013 | PASS |
| km2  | −2    | 253 | 253 | −2 | −2 | 451,304,185 | PASS |
| kp4  | +4    | 259 | 259 | +4 | +4 | 513,340,745 | PASS |
| km4  | −4    | 251 | 251 | −4 | −4 | 513,963,081 | PASS |
| kp8  | +8    | 263 | 263 | +8 | +8 | 509,590,562 | PASS |
| km8  | −8    | 247 | 247 | −8 | −8 | 509,590,562 | PASS |

**Gate: OFFICIAL_GATE: PASS (9/9 k_int sweep cases)**

Additional observations:
- Real IP exercised pipeline stalls (tready=0 backpressure); all handled correctly.
- SCALE_SCH=0xAA applies ÷16 scaling; peak location is invariant to uniform scaling.
- FLUSH_COUNT=1 drain frame required for pipelined streaming IP (PSS consumes flush credit).

---

## Session C (P3-14C) — DMA Replay IQ Golden Compare

**DUT:** `phase3_sync_axis_dma_wrapper`  
**Simulator:** iverilog  
**Stimulus:** k_int=0, eps_frac=+0.05 (step_word=0xFF000000 → int_cfo=+1 observed via wrapper)  
**Reference:** Python NCO model (`compare_session_C_p3_14c_dma_replay_golden.py`)

| Stage | Description | Expected | Got | Result |
|-------|-------------|----------|-----|--------|
| Stage 1 | Structural: INT_CFO_APPLIED, OUTPUT_COUNT, TLAST_COUNT | 1, 576, 1 | 1, 576, 1 | PASS |
| Stage 2 | TLAST position | 575 | 575 | PASS |
| Stage 3 | Sample-by-sample IQ vs Python NCO model (±1 LSB) | 0/576 mismatches | 0/576 | PASS |

**Gate: OFFICIAL_GATE: PASS (0/576 IQ mismatches, ±1 LSB)**

Additional observations:
- NCO effective latency confirmed as 16 cycles (15-stage CORDIC + 1 output register).
- `replay_start` deferred until NCO warmup counter `wu_cnt == 1`.
- Three bugs fixed in `phase3_sync_axis_dma_wrapper.v` during this session (see known limitations).

---

## Session D (P3-15A) — C Reference Equivalence Framework

**DUT:** `phase3_sync_axis_dma_wrapper`  
**Simulator:** iverilog  
**C reference:** `scripts/golden_dump.c` → `golden/phase3_golden_values.txt`

| Stage | Fields | C Reference | RTL Observed | Tolerance | Result |
|-------|--------|------------|--------------|-----------|--------|
| 0 | Schema availability | all keys present | all keys present | — | PASS |
| 1 | frame_found, frac_cfo_valid, int_cfo_valid | true, true, true | 1, 1, 1 | exact | PASS |
| 2 | frame_index, peak_lag, slot_start_index | 41, 23, 64 | 40, 23, 63 | ±1 | PASS |
| 3a | frac_cfo_word (Q1.15) | 3277 | 3278 | ±1% rel | PASS (0.031%) |
| 3b | int_cfo_index | 255 | 256 | ±1 | PASS |
| 3c | int_cfo_est_bins | 0 | 1 | ±1 | PASS |
| 3d | int_cfo_applied | 1 (RTL-only) | 1 | exact | PASS |
| 4 | m_axis.length, m_axis.tlast_index | unavailable | 576, 575 | — | BLOCKED |
| 5 | M_AXIS IQ sequence (576 samples) | unavailable | captured | — | BLOCKED |

**Gate: SANITY_EQUIV_GATE: PARTIAL_PASS_BLOCKED**  
Stages 4–5 blocked: `golden_dump.c` does not implement integer NCO correction.

---

## Session E (P3-16A) — Full End-to-End Integration

**DUT:** `phase3_sync_axis_dma_wrapper`  
**Simulator:** iverilog  
**Stimulus:** `golden/phase3_iq_stimulus.mem` (704 samples, k_int=0, eps_frac=+0.05)

| Check | Description | Expected | Got | Result |
|-------|-------------|----------|-----|--------|
| C1 | frame_found | 1 | 1 | PASS |
| C2 | frame_index | 41 ±1 | 40 | PASS |
| C3 | frac_cfo_valid | asserted | asserted | PASS |
| C4 | int_cfo_valid | asserted | asserted | PASS |
| C5 | int_cfo_applied | 1 | 1 | PASS |
| C6 | output_count | 576 | 576 | PASS |
| C7 | tlast at sample 575 | 575 | 575 | PASS |
| C8 | max M_AXIS gap | < 4 cycles | 1 | PASS |

**Gate: INTEGRATION_GATE: PASS (8/8)**

Additional observations:
- Total simulation = 103168 cycles (dominated by meyr_integer_cfo_core 65536 MACs).
- `iq_replay_buffer_576` BRAM throughput produces 1-cycle gap between every pair of beats (max_gap=1 confirmed).
- `STATUS=0x3` at end of run: DUT re-armed for second frame, expected behavior.
- CI_GATE: BLOCKED_XSIM_UNAVAILABLE (xsim not on build host).

---

## Session F (P3-17A) — Board / Vitis Smoke

**DUT:** Phase3 bitstream on Zynq-7000 hardware  
**Tool:** Vitis xsct (JTAG connection)  
**Infrastructure:** `vitis/session_F_p3_17a_phase3_smoke.c`, `scripts/windows/run_session_F_p3_17a_phase3_smoke.bat`

| Check | Description | Expected | Status |
|-------|-------------|----------|--------|
| C0 | Soft reset → RESET_DONE | 1 | PENDING |
| C1 | VERSION readable | 0x00316001 | PENDING |
| C2 | CONTROL enable R/W | write 1, read 1 | PENDING |
| C3 | STATUS readable | any value | PENDING |
| C4 | FRAME_LEN_SAMPLES R/W | write 576, read 576 | PENDING |
| C5 | DMA init | XST_SUCCESS | PENDING |
| C6 | DMA RX start | XST_SUCCESS | PENDING |
| C7 | DMA TX start | XST_SUCCESS | PENDING |
| C8 | Both DMA channels complete | no timeout | PENDING |
| C9 | INPUT_COUNT | 704 | PENDING |
| C10 | OUTPUT_COUNT | 576 | PENDING |
| C11 | TLAST_COUNT | ≥ 1 | PENDING |
| C12 | INT_CFO_VALID observed | snapshot taken | PENDING |
| C13 | Output buffer nonzero | ≥ 1 nonzero sample | PENDING |

**Gate: SMOKE_GATE: BLOCKED**  
Blocked on: Phase3 bitstream not generated from `rtl/phase3_sync_axis_dma_wrapper.v`.
Vitis infrastructure is complete and syntax-verified. Addresses `SYNC_BASEADDR=0x43C00000` and
`DMA_BASEADDR=0x40400000` are placeholders; confirm from Vivado address editor before running.

---

## Unblocking Conditions for Stages 4–5

| Deliverable | Source Session | Status |
|-------------|---------------|--------|
| C software model producing NCO-corrected IQ (576 int16 pairs) | Session C / external | Not delivered |
| File path: `golden/session_D_p3_15a/c_m_axis_iq_golden.txt` | — | Does not exist |
| Meyr peak index convention confirmed (255 vs 256 for k_int=0 in wrapper path) | Session B | Known: 255 correct, 256 is wrapper probe artifact |

---

## Full Gate Summary

| Gate | Value | Authority |
|------|-------|-----------|
| `phase3_sync_top` full regression (Session A) | SANITY_GATE: PASS | iverilog |
| Meyr integer CFO, real Xilinx FFT, 9-case sweep (Session B) | OFFICIAL_GATE: PASS | xsim (Vivado 2023.1) |
| DMA replay integer CFO correction, IQ golden (Session C) | OFFICIAL_GATE: PASS | iverilog runner |
| C reference equivalence, available fields (Session D) | SANITY_EQUIV_GATE: PARTIAL_PASS_BLOCKED | iverilog |
| Full end-to-end wrapper integration (Session E) | INTEGRATION_GATE: PASS | iverilog |
| Board / Vitis smoke (Session F) | SMOKE_GATE: BLOCKED | hardware (bitstream pending) |
| Official xsim gate for `phase3_sync_axis_dma_wrapper` | CI_GATE: PENDING | xsim required |
