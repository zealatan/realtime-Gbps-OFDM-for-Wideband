# Phase 3 OFDM Synchronizer — Architecture Summary

**Document:** Session G / P3-18A  
**Date:** 2026-05-28  
**Status:** Production RTL complete; integer CFO bypass stub pending real-FFT integration in `phase3_sync_top`

---

## 1. System Overview

Phase 3 implements the complete OFDM synchronizer described in `ref/receiver.c`. The
design converts a raw complex baseband IQ stream (S_AXIS in) into a fractional- and
integer-CFO-corrected output stream (M_AXIS out), passing all four synchronization
steps of the C reference algorithm.

### C Reference Algorithm Steps

| Step | Function | RTL Module |
|------|----------|-----------|
| 1 | Energy-based frame detection | `frame_detector` (P3-12A modular) |
| 2 | CP autocorrelation + fractional CFO estimation | `timing_frac_cfo_top` → `frac_cfo_corrector_top` |
| 3 | Slot start index (frame_index + peak_lag) | `slot_start_controller` |
| 4 | Meyr integer CFO estimation via 256-pt FFT | `meyr_integer_cfo_fft_frontend_top` |
| 4b | Integer CFO NCO correction + replay | NCO + rotator in `phase3_sync_axis_dma_wrapper` |

---

## 2. Module Hierarchy

```
phase3_sync_axis_dma_wrapper          ← production top (AXI-Lite + DMA)
├── phase3_axi_lite_regs              ← 22-register AXI-Lite slave
├── phase3_sync_top                   ← algorithm core
│   ├── frac_cfo_frame_corrector_top  ← Steps 1–3 (frame detect + frac CFO)
│   │   ├── frame_detector            ← P3-12A thin wrapper
│   │   │   ├── sample_power_sq       ← combinatorial I²+Q²
│   │   │   ├── sliding_window_sum    ← ring-buffer rolling accumulator
│   │   │   └── frame_detect_fsm      ← Case1/Case2 energy FSM
│   │   ├── timing_frac_cfo_top       ← CP autocorr + VanDeBeek estimator
│   │   │   ├── timing_sync_top
│   │   │   └── streaming_frac_cfo_estimator
│   │   ├── slot_start_controller     ← latches slotStartIndex
│   │   └── frac_cfo_corrector_top    ← fractional NCO + rotator
│   ├── pss_sss_symbol_extractor      ← extracts 256-sample PSS, SSS windows
│   └── meyr_integer_cfo_fft_frontend_top  ← Step 4: FFT + cross-correlation peak
│       ├── fft256_dual_symbol_frontend    ← ⚠ bypass stub (production: fft256_xilinx_wrapper)
│       ├── meyr_integer_cfo_core          ← cross-correlation argmax
│       ├── meyr_term2_ref_rom             ← PSS ROM (meyr_pss_reference_romhex.txt)
│       └── meyr_pss_sss_product_gen       ← PSS×conj(SSS) correlation kernel
├── iq_replay_buffer_576              ← 576-sample frac-corrected IQ store (BRAM)
├── nco_phase_gen                     ← integer CFO NCO (cos/sin, Q1.15)
└── complex_rotator                   ← IQ × exp(−jnω₀), CONJ_B=1
```

### Key Wiring Notes

- `frac_m` bus (frac_cfo_corrector_top M_AXIS output) is tapped by both the
  `pss_sss_symbol_extractor` and the `iq_replay_buffer_576` simultaneously via a
  side-channel handshake (`frac_hs = frac_m_tvalid & frac_m_tready`).
- The replay buffer captures exactly `FRAME_LEN=576` samples; replay begins after
  `dut_int_cfo_valid` asserts and the NCO has warmed up (16-cycle warmup).
- `start_armed_r` in the wrapper fires the DUT start on the first AXI-Lite enable write
  after reset; the wrapper re-arms for the next frame after each `replay_done`.

---

## 3. Parameter Table

| Parameter | Value | Notes |
|-----------|-------|-------|
| `NSC` | 256 | Number of subcarriers |
| `CP_LEN` | 32 | Cyclic prefix length |
| `FRAME_LEN` | 576 | `2 × (NSC + CP_LEN)` — one slot (2 OFDM symbols) |
| `STIM_DEPTH` | 704 | Stimulus samples: 64 preamble + 576 payload + 64 postamble |
| `DATA_WIDTH` | 32 | IQ packing: `{Q[31:16], I[15:0]}` |
| `CORDIC_LATENCY` | 15 | `nco_phase_gen` pipeline depth |
| `NCO_WARMUP` | 16 | `CORDIC_LATENCY + 1` (accounts for output register) |
| `ADDR_WIDTH` | 7 | AXI-Lite address bus width (22 registers × 4 bytes) |
| `VERSION` | `0x00316001` | AXI-Lite `ADDR_VERSION` readback |

### IQ Format Conventions

| Field | Convention |
|-------|-----------|
| AXI-S tdata | `{Q[31:16], I[15:0]}` (Q in upper half-word) |
| Frac CFO Q1.15 | `frac_cfo_word = round(+offset × 2 × 32768)` — same sign as C |
| Int CFO step word | `step_word = (−k_int) << 24`; `k_int = −(step_word >>> 24)` |
| Rotator convention | `CONJ_B=1`: `I_out = (I·cos + Q·sin) >> 15`, `Q_out = (Q·cos − I·sin) >> 15` |
| ROM index | `phase[31:24]` (upper 8 bits of 32-bit NCO accumulator) |

---

## 4. AXI-Lite Register Map (phase3_axi_lite_regs)

| Offset | Name | R/W | Description |
|--------|------|-----|-------------|
| `0x00` | ADDR_VERSION | R | `0x00316001` |
| `0x04` | ADDR_CONTROL | R/W | `[0]` enable, `[1]` soft_reset |
| `0x08` | ADDR_STATUS | R | `[0]` busy, `[1]` done, `[2]` error |
| `0x0C` | ADDR_ERROR_CODE | R | error reason |
| `0x10` | ADDR_FRAME_INDEX | R | frame_index (snapshot) |
| `0x14` | ADDR_PEAK_LAG | R | peak_lag (snapshot) |
| `0x18` | ADDR_SLOT_START | R | slot_start_index (snapshot) |
| `0x1C` | ADDR_FRAC_CFO | R | frac_cfo_word Q1.15 signed (snapshot) |
| `0x20` | ADDR_INT_CFO_VALID | R | int_cfo_valid sticky (clears on read) |
| `0x24` | ADDR_INT_CFO_WORD | R | int_cfo_word (snapshot on INT_CFO_VALID) |
| `0x28` | ADDR_INT_CFO_EST_BINS | R | derived int CFO in subcarrier bins |
| `0x2C` | ADDR_MEYR_PEAK | R | meyr_peak_index raw |
| `0x30` | ADDR_PSS_DONE | R | PSS extraction done flag |
| `0x34` | ADDR_SSS_DONE | R | SSS extraction done flag |
| `0x40` | ADDR_INT_CFO_I | R | int_cfo_index (AXI snapshot) |
| `0x44` | ADDR_INT_CFO_A | R | int_cfo_applied sticky |
| `0x48` | ADDR_OUT_COUNT | R | M_AXIS output sample count |
| `0x4C` | ADDR_TLAST_COUNT | R | M_AXIS TLAST count |
| `0x50` | ADDR_REPLAY_DONE | R | replay_done sticky |
| `0x54` | ADDR_REPLAY_ERR | R | replay_error sticky |

Snapshot registers latch on `dut_int_cfo_valid` rising edge. `ADDR_INT_CFO_VALID`
is W1C (clears on read). Version register is read-only constant.

---

## 5. RTL Source File List (production compile order)

```
rtl/sample_power_sq.v
rtl/sliding_window_sum.v
rtl/frame_detect_fsm.v
rtl/frame_detector.v
rtl/unit_test/cp_autocorr_core.v
rtl/unit_test/timing_metric_core.v
rtl/timing_sync_top.v
rtl/streaming_frac_cfo_estimator.v
rtl/timing_frac_cfo_top.v
rtl/iq_frame_buffer.v
rtl/frac_cfo_corrector_top.v
rtl/frac_cfo_frame_corrector_top.v
rtl/slot_start_controller.v
rtl/pss_sss_symbol_extractor.v
rtl/meyr_term2_ref_rom.v
rtl/meyr_pss_sss_product_gen.v
rtl/peak_detector.v
rtl/meyr_integer_cfo_core.v
rtl/fft256_dual_symbol_frontend.v    ← bypass stub (swap for fft256_xilinx_wrapper for real FFT)
rtl/meyr_integer_cfo_fft_frontend_top.v
rtl/phase3_sync_top.v
rtl/iq_replay_buffer_576.v
rtl/nco_phase_gen.v
rtl/complex_rotator.v
rtl/phase3_axi_lite_regs.v
rtl/phase3_sync_axis_dma_wrapper.v
```

Files that legitimately reside in `rtl/unit_test/` (not production):
`and2.v`, `cp_autocorr_core.v`, `timing_metric_core.v`

---

## 6. Test Infrastructure

| Script | DUT | Simulator | Gate |
|--------|-----|-----------|------|
| `run_session_A_p3_12c_full_phase3_regression.sh` | `phase3_sync_top` | iverilog / xsim | SANITY / CI |
| `run_session_B_p3_13c_real_fft_ip_xsim.sh` | `meyr_fft256_actual_integration_top` | xsim (Vivado) | OFFICIAL |
| `run_session_C_p3_14c_dma_replay_golden_compare.sh` | `phase3_sync_axis_dma_wrapper` | iverilog | OFFICIAL |
| `run_session_D_p3_15a_full_c_golden_equivalence.sh` | `phase3_sync_axis_dma_wrapper` | iverilog / xsim | SANITY_EQUIV |

---

## 7. Golden Assets

| File | Description |
|------|-------------|
| `golden/phase3_iq_stimulus.f32` | 704-sample float32 IQ stimulus (k_int=0, eps_frac=+0.05) |
| `golden/phase3_iq_stimulus.mem` | Same as hex: `{Q[15:0], I[15:0]}` per line |
| `golden/phase3_golden_values.txt` | C reference output (from `scripts/golden_dump.c`) |
| `golden/p3_09_sweep/case_k*.mem` | 9 per-case IQ stimulus files for integer CFO sweep |
| `vectors/meyr_pss_reference_romhex.txt` | Bypass-path ROM (time-domain cross-product) |
| `vectors/meyr_pss_fft_romhex.txt` | Real-FFT-path ROM (DFT-domain cross-product) |
| `golden/session_D_p3_15a/c_reference_observables.json` | Normalized C golden (Session D schema) |
