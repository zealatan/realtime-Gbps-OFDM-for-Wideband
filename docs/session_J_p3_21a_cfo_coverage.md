# Session J / P3-21A: CFO Coverage Expansion

**Date:** 2026-05-29  
**Status:** CFO_GATE: pending simulation  
**DUT (J1):** `meyr_fft256_actual_integration_top` (USE_BEHAVIORAL_STUB=3)  
**DUT (J2/J3):** `phase3_sync_axis_dma_wrapper` (P3-14B RTL, THRESHOLD=40000)

---

## 1. Objective

Expand CFO verification coverage beyond the P3-13B baseline (k_int ∈ {0,±1,±2,±4,±8}).
Three sub-tests validate different regions of the CFO operating envelope:

| Sub-test | CFO type | Range | DUT path |
|----------|----------|-------|----------|
| J1 | Integer only | k_int ∈ {0,±1,±2,±4,±8,±12,±16} | Standalone Meyr, behavioral DFT |
| J2 | Fractional only | ε ∈ {-0.45,…,+0.45} | Full wrapper |
| J3 | Combined | (k_int,ε) = (±16,±0.45), (±12,∓0.30) | Full wrapper |

---

## 2. Mathematical Basis

### 2.1 VanDeBeek CP Autocorrelation Invariance

The CP autocorrelation timing metric is:

```
P = Σ_{k=0}^{L-1}  y[n+k] · y*[n+k+N]
```

where y[n] = s[n] · exp(j·2π·(ε + k_int)·n/N) is the CFO-rotated received signal.
For the CP region (n ∈ [0, L-1]):

```
y[n+k] · y*[n+k+N] = |s[n+k]|² · exp(-j·2π·ε)
```

because the factor exp(j·2π·k_int·n/N) cancels between the two copies (periodicity
of the integer multiple). Therefore:

```
|P| = Σ|s[n+k]|²
```

**The timing metric magnitude is invariant to both integer and fractional CFO.**
Frame detection always works for any CFO value within the operating range,
making J2 and J3 frame_found checks analytically guaranteed to pass.

### 2.2 Fractional CFO Recovery

The VanDeBeek fractional CFO estimator:

```
ε̂ = angle(P) / (2π)
```

is unambiguous for |ε| < 0.5, which covers the full J2/J3 range ε ∈ [-0.45, +0.45].

The RTL encodes the result as:

```
frac_cfo_word = round(2 · ε · 32768)
```

Expected values for J2 cases:

| frac (ε) | frac_cfo_word |
|----------|---------------|
| -0.45    | -29491        |
| -0.30    | -19661        |
| -0.15    |  -9830        |
|  0.00    |      0        |
| +0.15    |  +9830        |
| +0.30    | +19661        |
| +0.45    | +29491        |

### 2.3 Integer CFO — Bypass-FFT Limitation

The production pipeline uses `fft256_dual_symbol_frontend`, a time-domain bypass
that computes PSS×conj(SSS) cross-products. Because both PSS and SSS windows
experience the same integer CFO rotation, the cross-product phase cancels:

```
PSS[n] · SSS*[n] = |s_pss[n]| · |s_sss[n]| · exp(j·2π·k_int·n/N) · exp(-j·2π·k_int·n/N)
                 = |s_pss[n]| · |s_sss[n]|   (integer CFO phase cancelled)
```

Consequently `int_cfo = 0` regardless of k_int in J2/J3 wrapper runs.
This is a documented limitation, not a bug. Integer CFO correction for non-zero
k_int requires the Xilinx FFT IP path (P3-13B/C).

J1 sidesteps this by using `meyr_fft256_actual_integration_top` directly with
`USE_BEHAVIORAL_STUB=3` (exact 256-pt behavioral DFT), which gives the correct
Meyr peak_index = 255 + k_int.

---

## 3. Sweep Definitions

### J1 — Integer CFO (13 cases)

| Label | k_int | exp peak_index | exp int_cfo | File |
|-------|-------|----------------|-------------|------|
| k0    |   0   | 255            |   0         | j1_kp0.mem  |
| kp1   |  +1   | 256            |  +1         | j1_kp1.mem  |
| km1   |  -1   | 254            |  -1         | j1_km1.mem  |
| kp2   |  +2   | 257            |  +2         | j1_kp2.mem  |
| km2   |  -2   | 253            |  -2         | j1_km2.mem  |
| kp4   |  +4   | 259            |  +4         | j1_kp4.mem  |
| km4   |  -4   | 251            |  -4         | j1_km4.mem  |
| kp8   |  +8   | 263            |  +8         | j1_kp8.mem  |
| km8   |  -8   | 247            |  -8         | j1_km8.mem  |
| kp12  | +12   | 267            | +12         | j1_kp12.mem |
| km12  | -12   | 243            | -12         | j1_km12.mem |
| kp16  | +16   | 271            | +16         | j1_kp16.mem |
| km16  | -16   | 239            | -16         | j1_km16.mem |

Peak index formula: `peak_index = 255 + k_int` (zero-CFO bin is 255 in 511-lag range).

### J2 — Fractional CFO (7 cases)

| Label      | frac (ε) | File                   |
|------------|----------|------------------------|
| frac_m045  | -0.45    | j2_frac_m045.mem       |
| frac_m030  | -0.30    | j2_frac_m030.mem       |
| frac_m015  | -0.15    | j2_frac_m015.mem       |
| frac_p000  |  0.00    | j2_frac_p000.mem       |
| frac_p015  | +0.15    | j2_frac_p015.mem       |
| frac_p030  | +0.30    | j2_frac_p030.mem       |
| frac_p045  | +0.45    | j2_frac_p045.mem       |

Per-case checks: `frame_found`, `frac_cfo_valid`, `output_count==576`, `TLAST at beat 575`.

### J3 — Combined CFO (4 cases)

| Label           | k_int | frac (ε) | File                   |
|-----------------|-------|----------|------------------------|
| kp16_fp045      | +16   | +0.45    | j3_kp16_fp045.mem      |
| km16_fm045      | -16   | -0.45    | j3_km16_fm045.mem      |
| kp12_fm030      | +12   | -0.30    | j3_kp12_fm030.mem      |
| km12_fp030      | -12   | +0.30    | j3_km12_fp030.mem      |

Per-case checks: same as J2 (int_cfo not checked; see bypass-FFT limitation §2.3).

---

## 4. Gate Definitions

### Sub-gates

| Gate | Condition |
|------|-----------|
| `J1_GATE: PASS` | All 13 integer CFO cases pass (peak_index and int_cfo exact) |
| `J1_GATE: FAIL` | Any J1 case fails or compile error |
| `J2_GATE: PASS` | All 7 frac CFO cases pass (frame_found, frac_cfo_valid, count, TLAST) |
| `J2_GATE: FAIL` | Any J2 case fails or compile error |
| `J3_GATE: PASS` | All 4 combined cases pass (same checks as J2) |
| `J3_GATE: FAIL` | Any J3 case fails or compile error |

### Aggregated gate

| Gate | Condition |
|------|-----------|
| `CFO_GATE: PASS` | J1_GATE + J2_GATE + J3_GATE all PASS |
| `CFO_GATE: FAIL` | One or more sub-gates FAIL |

---

## 5. Signal Construction

All cases use the same base frame (SEED=0xC0FFEE):

```python
base = _build_base_frame()   # OFDM: [zeros×64][CP+sym1=288][CP+sym2=288][zeros×64]
frame = _apply_cfo(base, frac, k_int)
      = base[n] × exp(j·2π·(frac + k_int)·n/256)
```

Amplitude is normalized so max(|I|, |Q|) = 3000.0 (THRESHOLD=40000 in the DUT).

Frame structure (704 samples):

| Range       | Content                  |
|-------------|--------------------------|
| [0,63]      | Leading zeros            |
| [64,351]    | CP1 (32) + Symbol1 (256) |
| [352,639]   | CP2 (32) + Symbol2 (256) |
| [640,703]   | Trailing zeros           |

J1 TB extracts windows at:
- PSS: `frame_mem[96..351]`  (offset 96 = slot_start 64 + CP 32)
- SSS: `frame_mem[384..639]` (offset 384 = slot_start 64 + 2×CP + NSC)

---

## 6. File Inventory

| File | Description |
|------|-------------|
| `scripts/gen_p3_21a_cfo_sweep_vectors.py` | Generates all 24 stimulus .mem files and manifest.json |
| `tb/session_J_p3_21a_j1_meyr_sweep_tb.sv` | J1 standalone Meyr sweep (13 cases, behavioral DFT) |
| `tb/session_J_p3_21a_j2j3_wrapper_tb.sv` | J2/J3 full wrapper sweep (7 + 4 = 11 cases) |
| `scripts/run_session_J_p3_21a_cfo_coverage.sh` | Master runner: generates vectors, runs J1 and J2/J3, emits CFO_GATE |
| `golden/p3_21a_sweep/` | Output directory for all 24 .mem files + manifest.json |
| `docs/session_J_p3_21a_cfo_coverage.md` | This document |

---

## 7. Source Lists

### J1 RTL sources (behavioral DFT path)

```
rtl/meyr_fft256_harness_adapter.v
rtl/meyr_fft256_actual_integration_top.v
rtl/fft256_xilinx_wrapper.v             (behavioral stub when USE_BEHAVIORAL_STUB=3)
rtl/meyr_integer_cfo_freq_estimator_top.v
rtl/meyr_integer_cfo_core.v
rtl/meyr_pss_sss_product_gen.v
rtl/peak_detector.v
```

Compile flag: `-P session_J_p3_21a_j1_meyr_sweep_tb.USE_BEHAVIORAL_STUB=3`

ROM files required: `vectors/meyr_pss_fft_romhex.txt`, `vectors/meyr_sss_fft_romhex.txt`

### J2/J3 RTL sources (full wrapper path)

Same as P3-16A (Session E):

```
rtl/phase2_legacy/complex_mult.v
rtl/phase2_legacy/complex_to_mag.v
rtl/phase2_legacy/delay_sample.v
rtl/phase2_legacy/delayT.v
rtl/phase2_legacy/moving_avg_optimized.v
rtl/phase2_legacy/ram_2port.v
rtl/unit_test/and2.v
rtl/unit_test/cp_autocorr_core.v
rtl/unit_test/timing_metric_core.v
rtl/timing_sync_top.v
rtl/frac_cfo_estimator.v
rtl/timing_frac_cfo_top.v
rtl/iq_frame_buffer.v
rtl/frac_cfo_corrector_top.v
rtl/fft256_dual_symbol_frontend.v
rtl/meyr_term2_ref_rom.v
rtl/meyr_integer_cfo_fft_frontend_top.v
rtl/axis_complex_mult.v
rtl/complex_mult_iq.v
rtl/complex_rotator.v
rtl/cordic_atan2.v
rtl/nco_phase_gen.v
rtl/peak_detector.v
rtl/meyr_integer_cfo_core.v
rtl/meyr_pss_sss_product_gen.v
rtl/meyr_integer_cfo_freq_estimator_top.v
rtl/pss_sss_symbol_extractor.v
rtl/slot_start_controller.v
rtl/sample_power_sq.v
rtl/sliding_window_sum.v
rtl/frame_detect_fsm.v
rtl/frame_detector.v
rtl/frac_cfo_frame_corrector_top.v
rtl/phase3_sync_top.v
rtl/iq_replay_buffer_576.v
rtl/phase3_axi_lite_regs.v
rtl/phase3_sync_axis_dma_wrapper.v
```

ROM stubs created automatically if missing: `vectors/meyr_pss_reference_romhex.txt`, `vectors/meyr_sss_reference_romhex.txt`

---

## 8. Usage

```bash
cd /home/zealatan/RTL_SYNC_PHASE3

# Full run: generate vectors, then run all three sub-gates
bash scripts/run_session_J_p3_21a_cfo_coverage.sh

# Skip vector generation (reuse existing golden/p3_21a_sweep/)
bash scripts/run_session_J_p3_21a_cfo_coverage.sh --skip-gen

# Run only J1 (useful for quick Meyr DFT check)
bash scripts/run_session_J_p3_21a_cfo_coverage.sh --skip-j2j3

# Run only J2/J3 (wrapper, after J1 already passed)
bash scripts/run_session_J_p3_21a_cfo_coverage.sh --skip-j1

# Custom log directory
bash scripts/run_session_J_p3_21a_cfo_coverage.sh --log-dir /tmp/p3_21a_logs
```

---

## 9. Expected Output (CFO_GATE: PASS)

```
========================================================================
P3-21A CFO Coverage Expansion
  Date       : 2026-05-29 ...
========================================================================

Step 1: Vector Generation
  Running: python3 scripts/gen_p3_21a_cfo_sweep_vectors.py
  [gen_p3_21a] 24 stimulus files in .../golden/p3_21a_sweep/

Step 2: J1 — Integer CFO Sweep (Meyr, USE_BEHAVIORAL_STUB=3)
  Compile OK
  ...
  [J1] PASS  k0         peak=255  int_cfo=0   score=...
  [J1] PASS  kp1        peak=256  int_cfo=1   score=...
  ...
  [J1] PASS  kp16       peak=271  int_cfo=16  score=...
  [J1] PASS  km16       peak=239  int_cfo=-16 score=...
  J1 results: 13 passed, 0 failed
  J1_GATE: PASS
  Exact 256-pt DFT confirmed for k_int ∈ {0,±1,±2,±4,±8,±12,±16}.
J1_GATE: PASS

Step 3: J2/J3 — Full Wrapper Sweep
  Compile OK
  ...
  [J2] PASS  frac_m045  frame_found=1  frac_cfo_valid=1  count=576  tlast@575
  ...
  [J2] PASS  frac_p045  frame_found=1  frac_cfo_valid=1  count=576  tlast@575
  J2 results: 7 passed, 0 failed
  J2_GATE: PASS
  [J3] PASS  kp16_fp045 frame_found=1  frac_cfo_valid=1  count=576  tlast@575
  ...
  J3 results: 4 passed, 0 failed
  J3_GATE: PASS  [bypass-FFT: int_cfo=0 regardless of k_int — documented]
J2_GATE: PASS
J3_GATE: PASS

========================================================================
P3-21A CFO Coverage — Summary

  J1 (integer CFO sweep, behavioral DFT) : PASS
  J2 (frac CFO sweep, full wrapper)      : PASS
  J3 (combined sweep, full wrapper)      : PASS

CFO_GATE: PASS
========================================================================
```

---

## 10. Failure Classification

| Symptom | Likely cause |
|---------|-------------|
| J1 FAIL: timeout | Watchdog 200K cycles; check DUT start/done handshake |
| J1 FAIL: wrong peak | ROM mismatch — regenerate `meyr_pss_fft_romhex.txt` via `gen_meyr_fft_reference_roms.py` |
| J1 FAIL: wrong int_cfo | Peak decoder off-by-one; confirm `int_cfo = peak_index - 255` |
| J2/J3 FAIL: frame_found=0 | Frame detector threshold too high for amplitude=3000; check THRESHOLD=40000 |
| J2/J3 FAIL: frac_cfo_valid=0 | Frac CFO pipeline stall or FRAC_CFO_V latch not draining between cases |
| J2/J3 FAIL: count≠576 | Replay buffer not completing; check AXI CONTROL enable after reset |
| J2/J3 FAIL: no TLAST | M_AXIS TLAST not generated; check replay buffer TLAST logic |
| Compile error | Missing RTL source — check file list against §7 |

---

## 11. Relationship to Prior Sessions

| Session | Gate | Scope |
|---------|------|-------|
| P3-13B (Session B) | OFFICIAL_GATE: PASS | Real Xilinx FFT IP xsim sweep (k_int ∈ {0,±1,±2,±4,±8}) |
| P3-16A (Session E) | INTEGRATION_GATE: PASS | End-to-end Phase3 regression (k_int=0, frac=0) |
| P3-17B (Session F2) | BOARD_GATE: BLOCKED | Board DMA replay validation |
| **P3-21A (Session J)** | **CFO_GATE: pending** | **This session — extended CFO coverage** |

P3-21A extends P3-13B by adding ±12, ±16 integer CFO cases (J1) and introduces
fractional CFO verification (J2) and combined CFO coverage (J3) for the first time.
