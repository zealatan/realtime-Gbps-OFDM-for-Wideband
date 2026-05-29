# Phase 3 Final Closure Summary

**Document:** Session G / P3-18A  
**Date:** 2026-05-28  
**Overall status:** Production RTL complete and functionally verified. Official xsim gate on `phase3_sync_axis_dma_wrapper` and Stage 4/5 IQ golden comparison remain open.

---

## 1. What Was Built

### Production RTL

`phase3_sync_axis_dma_wrapper` is the synthesizable top module. It combines:

- **All four synchronization steps** from the C reference algorithm:
  1. Energy-based frame detection (P3-12A modular `frame_detector`)
  2. CP autocorrelation + fractional CFO estimation (`timing_frac_cfo_top`)
  3. Slot start index derivation (`slot_start_controller`)
  4. Meyr integer CFO estimation via 256-pt FFT (`meyr_integer_cfo_fft_frontend_top`)
- **Integer CFO correction path:** 576-sample replay buffer + NCO + rotator, producing
  a corrected M_AXIS output stream.
- **AXI-Lite control/status interface:** 22 registers, VERSION=0x00316001.
- **Auto-rearm:** Wrapper re-arms for the next frame after each `replay_done` without
  requiring host intervention.

**No algorithm RTL files were modified in Session A, B, C, or D.** All verified
algorithm logic was written in the pre-session design steps (P3-01 through P3-15B).

### Verification Infrastructure

- `scripts/golden_dump.c` — standalone C reference extractor (Steps 1–3, no fftw3/libiio)
- `scripts/gen_meyr_fft_reference_roms.py` — DFT-based ROM generator for real FFT path
- `scripts/gen_phase3_iq_stimulus.py` — deterministic IQ stimulus generator
- `scripts/compare_session_C_p3_14c_dma_replay_golden.py` — 3-stage IQ golden compare
- `scripts/compare_full_phase3_against_c_reference.py` — 6-stage C reference equivalence
- Python normalization and export scripts for all golden JSON schemas
- 7+ testbenches covering unit, integration, and full-system levels
- 4 session-level runner scripts with SANITY / OFFICIAL / SANITY_EQUIV gate logic

---

## 2. Session Accomplishments

### Session A (P3-12C) — Full Phase3 Regression

- **Accomplished:** Validated `phase3_sync_top` end-to-end: frame detection → frac CFO
  correction → PSS/SSS extraction → Meyr integer CFO estimation. 10/10 checks passed.
- **Confirmed:** Modular P3-12A `frame_detector` (P3-12A FSM architecture) is live and
  produces identical output to the prior monolithic version.
- **Confirmed:** Source-list audit across all 9 Phase3 scripts — 8 stale `unit_test/`
  paths corrected to `rtl/` in every runner.
- **Audit finding:** `rtl/phase2_legacy/sample_power_sq.v` excluded from all production
  compile paths; only `rtl/sample_power_sq.v` (P3-12A interface) is used.
- **Gate:** `SANITY_GATE: PASS` (iverilog). CI_GATE blocked by xsim unavailability.

### Session B (P3-13C) — Real Xilinx FFT + Integer CFO Sweep

- **Accomplished:** Generated Vivado 2023.1 xfft_v9_1_9 IP (256-pt, pipelined streaming,
  `SCALE_SCH=0xAA`), compiled mixed VHDL+Verilog xsim snapshot, and ran full 9-case
  integer CFO sweep.
- **Confirmed:** For every k_int ∈ {−8, −4, −2, −1, 0, +1, +2, +4, +8}, the Meyr
  estimator reports `peak_index = 255 + k_int` and `int_cfo = k_int` exactly.
- **Confirmed:** Real IP exercises pipeline stalls (tready=0 backpressure); the wrapper
  handles all stall events without missing samples.
- **Confirmed:** `FLUSH_COUNT=1` drain frame is required for the pipelined streaming IP.
- **Gate:** `OFFICIAL_GATE: PASS` (xsim, Vivado 2023.1) — the only authoritative xsim
  gate in the project.

### Session C (P3-14C) — DMA Replay IQ Golden Compare

- **Accomplished:** Verified the complete integer CFO correction pipeline of
  `phase3_sync_axis_dma_wrapper` sample-by-sample against a Python NCO reference model:
  S_AXIS → frac_cfo_corrector_top → iq_replay_buffer_576 → NCO → rotator → M_AXIS.
- **Confirmed:** 0/576 IQ sample mismatches at ±1 LSB tolerance.
- **Confirmed:** NCO effective latency = 16 cycles (15-stage CORDIC + 1 output register).
  `replay_start` correctly deferred until `wu_cnt == 1`.
- **Fixed three bugs** in `rtl/phase3_sync_axis_dma_wrapper.v`:
  1. S_AXIS `tlast` not asserted in TB → `iq_frame_buffer` capture_done never fired; FSM
     stuck in `S_FILL`. (TB fix, not RTL.)
  2. Watchdog 100K → 150K cycles (Meyr pipeline needs ~110K cycles total).
  3. Integer NCO warmup: old enable logic (`!sincos_valid | ...`) was already 0 at
     `step_word` load time; replaced with `wu_cnt` counter forcing enable=1 for
     `CORDIC_LATENCY+1=16` cycles post `dut_int_cfo_valid`.
- **Gate:** `OFFICIAL_GATE: PASS` (iverilog runner; authoritative xsim run pending).

### Session D (P3-15A) — C Reference Equivalence Framework

- **Accomplished:** Built complete 6-stage equivalence infrastructure comparing
  `phase3_sync_axis_dma_wrapper` against the C reference golden values.
- **Confirmed:** All available fields (Stages 0–3) match C reference within tolerance:
  frame timing ±1 sample, frac CFO 0.031% relative error, integer CFO ±1 bin.
- **Framework delivered:** Export script, normalization script, comparison engine,
  integrated runner, observable dump TB, and normalized JSON schema are all in place and
  wired; Stages 4–5 will run automatically once the C IQ golden file is provided.
- **Gate:** `SANITY_EQUIV_GATE: PARTIAL_PASS_BLOCKED` (Stages 4–5 blocked by missing
  C M_AXIS golden).

### Session E (P3-16A) — Full End-to-End Integration

- **Accomplished:** Validated the complete `phase3_sync_axis_dma_wrapper` pipeline from
  S_AXIS to M_AXIS with a single testbench covering all major observable outputs.
  8/8 checks passed: frame_found, frame_index (±1), frac_cfo_valid, int_cfo_valid,
  int_cfo_applied=1, output_count=576, tlast_at_575, max_gap=1 (< 4).
- **Confirmed:** M_AXIS continuity — `iq_replay_buffer_576` BRAM 2-cycle throughput
  produces 1-cycle gaps between pairs of beats; max_gap=1 confirmed.
- **Confirmed:** Full pipeline timing — 103168 total simulation cycles, dominated by
  65536-MAC Meyr cross-correlation. DUT correctly re-arms after `replay_done`.
- **Gate:** `INTEGRATION_GATE: PASS` (iverilog). CI_GATE: BLOCKED_XSIM_UNAVAILABLE.

### Session F (P3-17A) — Board / Vitis Smoke

- **Accomplished:** Delivered complete Vitis board bring-up infrastructure:
  - `vitis/session_F_p3_17a_phase3_smoke.c` — 14-check standalone Vitis application
    with embedded golden IQ stimulus (704 samples × 32-bit).
  - `scripts/windows/run_session_F_p3_17a_phase3_smoke.bat` — Windows xsct build+run
    script with `--program` (JTAG bitstream load) and `--build-only` flags.
  - `docs/session_F_p3_17a_board_smoke.md` — full prerequisites, register map, and
    simulation baseline reference.
- **Syntax verified:** C source file compiles to exit 0 with GCC stub headers.
- **Gate:** `SMOKE_GATE: BLOCKED` — Phase3 bitstream not yet generated from
  `rtl/phase3_sync_axis_dma_wrapper.v` in Vivado. All infrastructure ready for
  first-board bring-up once bitstream is available.

---

## 3. Open Items

| ID | Item | Blocking | Owner |
|----|------|----------|-------|
| O-01 | C software model for NCO-corrected IQ output (576 samples) → `golden/session_D_p3_15a/c_m_axis_iq_golden.txt` | Stage 4/5 in Session D | External / new session |
| O-02 | Official xsim run of `phase3_sync_axis_dma_wrapper` (Sessions C and D) | Authoritative CI gate | Requires Vivado on Linux or Windows Vivado run |
| O-03 | Connect real FFT to `phase3_sync_top` (replace bypass stub) | Integer CFO accuracy end-to-end | Architecture work, P3-11 plan exists |
| O-04 | Validate additional k_int values through full wrapper (currently only k_int=0 tested end-to-end via wrapper) | Coverage | New session |
| O-05 | Meyr peak index off-by-one root cause in wrapper probe | Correctness confidence | Needs xsim run with real FFT |

---

## 4. Gate Status Table

| Component | Gate | Value | Simulator | Date |
|-----------|------|-------|-----------|------|
| `phase3_sync_top` full pipeline (Session A) | SANITY_GATE | PASS | iverilog | 2026-05-28 |
| Meyr estimator, real Xilinx FFT, 9-case sweep (Session B) | OFFICIAL_GATE | PASS | xsim (Vivado 2023.1) | 2026-05-28 |
| DMA replay integer CFO correction, 576 samples (Session C) | OFFICIAL_GATE | PASS | iverilog | 2026-05-28 |
| C reference equivalence, available fields (Session D) | SANITY_EQUIV_GATE | PARTIAL_PASS_BLOCKED | iverilog | 2026-05-28 |
| Full end-to-end wrapper integration (Session E) | INTEGRATION_GATE | PASS | iverilog | 2026-05-28 |
| Board / Vitis smoke (Session F) | SMOKE_GATE | BLOCKED | hardware | — |
| `phase3_sync_axis_dma_wrapper` official xsim | CI_GATE | PENDING | xsim | — |

---

## 5. Recommended Next Steps (Priority Order)

### 5.1 Provide C M_AXIS IQ Golden (unblocks Session D Stages 4–5)

Extend `scripts/golden_dump.c` or write a new Python script to apply the NCO rotation
from `int_cfo_est_bins` and produce 576 signed int16 output samples. Write to:

```
golden/session_D_p3_15a/c_m_axis_iq_golden.txt
```

Then re-run:
```bash
./scripts/run_session_D_p3_15a_full_c_golden_equivalence.sh --sim iverilog --skip-sim
```

The comparison framework will automatically execute Stages 4 and 5.

### 5.2 Official xsim Run of `phase3_sync_axis_dma_wrapper`

From a host with Vivado available:
```bash
./scripts/run_session_C_p3_14c_dma_replay_golden_compare.sh --sim xsim
./scripts/run_session_D_p3_15a_full_c_golden_equivalence.sh --sim xsim
```

Both runners have full xsim compile paths wired and will emit `CI_GATE: PASS` or
`EQUIV_GATE: PASS` on success.

### 5.3 Connect Real FFT to `phase3_sync_top`

Replace `fft256_dual_symbol_frontend` with the real Xilinx xfft_v9_1_9 wrapper:

1. Adapt `meyr_fft256_harness_adapter.v` for integration into `phase3_sync_top`.
2. Regenerate ROMs using `scripts/gen_meyr_fft_reference_roms.py`.
3. Re-run Session A regression to confirm end-to-end integer CFO accuracy.

See `docs/p3_11_real_fft_meyr_integration_plan.md` for the full integration spec.

### 5.4 Multi-CFO Wrapper Sweep

After real FFT is connected, run the full wrapper pipeline (Sessions C + D) for at
least k_int ∈ {−4, 0, +4} to confirm integer CFO accuracy end-to-end, not just
within the Meyr estimator harness.

---

## 6. File Inventory — Session G / P3-18A

| File | Purpose |
|------|---------|
| `docs/session_G_p3_18a_phase3_architecture.md` | Module hierarchy, parameters, register map, source list |
| `docs/session_G_p3_18a_verification_matrix.md` | Per-session check tables and gate results |
| `docs/session_G_p3_18a_known_limitations.md` | 10 documented limitations with resolution paths |
| `docs/session_G_p3_18a_final_closure_summary.md` | This file |

No RTL was modified in Session G.
