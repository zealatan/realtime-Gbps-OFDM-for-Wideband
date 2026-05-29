# P3-09X — Phase 3 Architecture and Verification Flow Audit Report

**Date:** 2026-05-28  
**Auditor:** Claude-A (P3-09X session)  
**Status:** Drift confirmed; repairs applied; xsim runner created

---

## 1. Architecture Overview

### 1.1 Intended Architecture (from ref/receiver.c)

```
IQ samples (streaming)
  │
  ▼
[Step 1] frame_detector()
  │  frameStart index (energy-threshold crossing)
  ▼
[Step 2] VanDeBeekAutoCorrelation()
  │  peakIndexAuto (lag of max CP autocorrelation power)
  │  fracCFO_offset = -atan2(P_Q, P_I) / (2π)
  ▼
[Step 3] slotStartIndex = frameStart + peakIndexAuto
  ▼
[Step 4] frac CFO correction (NCO rotation, sample-by-sample)
  │  frac-corrected IQ, FRAME_LEN = 576 samples from slotStart
  ▼
[Step 5a] PSS/SSS extraction (CP removal, symbol windowing)
  │  PSS[0..255], SSS[0..255] (time-domain, frac-corrected)
  ▼
[Step 5b] FFT-256 of PSS and SSS
  │  PSS_F[0..255], SSS_F[0..255] (frequency domain)
  ▼
[Step 5c] Meyr cross-correlation: corr[p] = Σ PSS_F[n+p] × conj(SSS_F[n]) × conj(PSS_rom[n]) × sign(SSS_rom[n])
  │  peak_index = argmax corr;  int_cfo = peak_index - CENTER
  ▼
[Step 5d] Integer CFO correction (second NCO rotation)
  │  Requires REPLAY of frac-corrected 576 samples through second corrector
  ▼
Fully synchronized IQ output (frac + integer CFO corrected)
```

### 1.2 Intended Module Hierarchy

```
phase3_sync_top
  ├── frac_cfo_frame_corrector_top   (Steps 1–4)
  ├── slot_start_controller          (Step 3)
  ├── pss_sss_symbol_extractor       (Step 5a)
  ├── meyr_integer_cfo_fft_frontend_top  (Steps 5b+5c)
  │     ├── fft256_dual_symbol_frontend  [REAL FFT — Xilinx IP or behavioral]
  │     └── meyr_integer_cfo_freq_estimator_top
  │           ├── meyr_pss_sss_product_gen
  │           └── meyr_integer_cfo_core
  ├── iq_replay_buffer_576           (Step 5d replay store)  [NOT YET CONNECTED]
  └── int_cfo_corrector_pass         (Step 5d second NCO)    [NOT YET IMPLEMENTED]
```

### 1.3 Actual Implemented Architecture (as of P3-09X)

```
phase3_sync_top
  ├── frac_cfo_frame_corrector_top   (Steps 1–4: COMPLETE, verified)
  ├── slot_start_controller          (Step 3: COMPLETE, verified)
  ├── pss_sss_symbol_extractor       (Step 5a: COMPLETE, verified)
  └── meyr_integer_cfo_fft_frontend_top  (Steps 5b+5c: PARTIAL)
        ├── fft256_dual_symbol_frontend  [BYPASS STUB — copies time-domain buffers]
        └── meyr_integer_cfo_freq_estimator_top
              ├── meyr_pss_sss_product_gen   [connected; operates on bypass data]
              └── meyr_integer_cfo_core      [connected; ROMs tuned for bypass path]

NOTE: iq_replay_buffer_576.v EXISTS at rtl/ but is NOT instantiated in phase3_sync_top.
NOTE: int_cfo_corrector_pass does NOT exist yet.
NOTE: integer CFO word (dbg_integer_cfo_word) is computed but NOT applied to the IQ stream.
```

---

## 2. Mismatch List

| # | Expected | Actual | Severity |
|---|----------|--------|----------|
| M1 | Real 256-pt FFT in fft256_dual_symbol_frontend | Bypass stub (copies time-domain buffers) | **HIGH** |
| M2 | Meyr ROM derived from DFT of ZC PSS + Gold SSS | ROM derived from time-domain cross-product (bypass-compatible) | **HIGH** |
| M3 | Integer CFO sweep (k_int ≠ 0) passes | Blocked — bypass FFT makes all k_int look like k_int=0 | **HIGH** |
| M4 | iq_replay_buffer_576 integrated in phase3_sync_top | Module exists but is not instantiated | MEDIUM |
| M5 | Integer CFO applied to output IQ stream | Not connected; word computed only as debug output | MEDIUM |
| M6 | Vivado xsim as CI gate | iverilog 11.0 used for all CI_GATE PASS results | **HIGH** |
| M7 | run_p3_08 defaults to xsim | Hard-codes `SIM="iverilog"` | MEDIUM |
| M8 | run_p3_09 defaults to xsim | Hard-codes `SIM="iverilog"` | MEDIUM |
| M9 | run_p3_09 xsim compilation implemented | Stub: "not implemented in this skeleton" | MEDIUM |
| M10 | run_p3_09 RTL source list correct | 3 nonexistent files; 15+ required files absent | **HIGH** |
| M11 | 1 sample/clock replay throughput (P3-10A concern) | 1 sample per 2 cycles (BRAM read latency) | LOW |

---

## 3. Official vs Non-Official Simulation Status

| Runner | Default simulator | Official status |
|--------|-------------------|-----------------|
| `scripts/run_phase3_sync_sim.sh` | xsim (correct) | Not official until xsim runs | 
| `scripts/run_phase3_sync_xsim.sh` (NEW) | xsim only | **OFFICIAL CI GATE** |
| `scripts/run_p3_08_meyr_backend.sh` | iverilog (drift; now repaired to xsim) | Not official until xsim runs |
| `scripts/run_p3_09_integer_cfo_sweep.sh` | iverilog (drift; now repaired to xsim) | BLOCKED — bypass FFT |
| `scripts/run_p3_10a_iq_replay_buffer_sim.sh` | iverilog | Optional sanity only |

---

## 4. Previous PASS Results — Validity Assessment

### 4.1 Results That Remain Algorithmically Valid

The following results are **functionally correct** and the code logic is sound. However, they were all produced using iverilog and require Vivado xsim revalidation before constituting official CI sign-off.

| Step | Checks validated | Algorithmic validity | xsim revalidation |
|------|------------------|---------------------|-------------------|
| P3-05C | 1–6: detection, frameStart, peakIdx, slotStart, fracCFO, PSS/SSS offsets | VALID | REQUIRED |
| P3-07 | 7–8: PSS/SSS sample counts (256 each) | VALID | REQUIRED |
| P3-08 | 9–10: Meyr peak index, integer CFO word (k_int=0 only, bypass path) | CONDITIONALLY VALID | REQUIRED |
| P3-10A | T01–T08: replay buffer unit tests | VALID | REQUIRED |

### 4.2 Results With Conditional Validity (bypass workaround)

**P3-08 checks 9+10** (Meyr peak index = 255, integer_cfo_word = 0):

These checks PASS because the ROMs were specifically derived from the bypass path
(time-domain cross-products, not frequency-domain DFT). The results are:

- **Valid for k_int=0**: Confirms the Meyr pipeline executes correctly end-to-end.
- **Invalid for k_int≠0**: The bypass FFT causes all integer CFO offsets to cancel in the
  PSS×conj(SSS) cross-product. The P3-09 sweep (k_int ∈ {±1,±2,±4,±8}) is blocked for this reason.
- **Not equivalent to real FFT validation**: Once the real FFT is integrated, the ROMs
  must be regenerated from the DFT of the ZC PSS and Gold SSS reference sequences.

### 4.3 Results That Need Vivado xsim Revalidation

**ALL previous CI_GATE PASS results require xsim revalidation.** iverilog results are
prototype-level only. Priority order for xsim revalidation:

1. P3-05C core path (checks 1–6) — highest priority; foundational
2. P3-07 PSS/SSS extraction (checks 7–8)
3. P3-08 Meyr backend k_int=0 (checks 9–10)
4. P3-10A replay buffer unit tests (standalone module)

---

## 5. Replay Buffer Clarification

**The term "replay buffer" refers to an on-chip BRAM store of frac-corrected IQ samples,**
**not a raw RF frame buffer.**

### 5.1 What It Is

`rtl/iq_replay_buffer_576.v` captures exactly 576 IQ samples from the output of
`frac_cfo_frame_corrector_top` (the fractional CFO-corrected IQ stream). These are
already processed samples — frame-detected, timing-aligned, and fractional-CFO-corrected.

### 5.2 Why Replay Is Needed

The Meyr integer CFO estimator requires the PSS/SSS symbols to compute the integer CFO
offset. By the time the integer CFO is known, the 576-sample window has already been
consumed. The replay buffer stores those samples so they can be re-fed through a second
corrector instance (the "integer CFO correction pass").

### 5.3 What It Is NOT

- Not a raw RF frame buffer (not capturing pre-detection IQ)
- Not a DMA buffer (on-chip BRAM, not system memory)
- Not a circular buffer (single-shot capture per frame; requires clear between frames)
- Not a sample-rate conversion or rate-adaptation buffer

### 5.4 Throughput Note (P3-10A Concern)

The original P3-06 requirement loosely implied "1 sample/clock" replay throughput.
The implemented `iq_replay_buffer_576.v` achieves **1 sample per 2 clock cycles** due
to the BRAM18E2 read latency pipeline (1 registered latency + 1 output hold stage).

**This is acceptable and intentional.** Given the ~130K clock cycle Meyr estimator
latency, the 576-sample replay at 1 sample/2 cycles takes ~1,153 cycles — negligible.
The doc (`docs/p3_10a_iq_replay_buffer.md`, Section 5) explicitly states this.

The concern (M11) is noted but is not a functional defect.

---

## 6. FFT / Meyr Status Clarification

### 6.1 fft256_dual_symbol_frontend.v — Bypass Stub

`rtl/unit_test/fft256_dual_symbol_frontend.v` contains the string "FFT PLACEHOLDER" in
multiple places (lines 8, 77, 148). The S_COMPUTE state (lines 152–163) copies the
time-domain input buffers directly to the FFT output buffers without any frequency
transformation.

**Effect:** The Meyr core receives time-domain PSS and SSS samples, not their DFTs.

### 6.2 meyr_fft256_actual_integration_top.v — Not Connected

`rtl/meyr_fft256_actual_integration_top.v` exists but is NOT in the `phase3_sync_top`
simulation compile path. It is a separate integration target that has not been wired in.

### 6.3 Bypass ROM Strategy (P3-08)

Because the bypass FFT passes time-domain samples unchanged, the Meyr cross-correlation
receives `term1[j] = PSS_td[j] × conj(SSS_td[j])`. To obtain `peak_index = 255`
(center = zero CFO), the reference term must match, requiring:

```
PSS_rom[j] = PSS_td[j] × conj(SSS_td[j])  (normalized to Q1.15)
SSS_rom[j] = {I=+32767, Q=0}               (sign = +1 everywhere)
```

This is what `gen_meyr_reference_roms.py` produces. These ROMs are **not interchangeable**
with the frequency-domain ROMs needed for real FFT operation.

### 6.4 Path to Real FFT Integration

1. Replace S_COMPUTE in `fft256_dual_symbol_frontend.v` with a real 256-pt FFT
   (Xilinx FFT v9.1 IP core or behavioral DFT for simulation).
2. Regenerate reference ROMs: `PSS_rom[k] = FFT{ZC_PSS}[k]` and `SSS_rom[k] = FFT{Gold_SSS}[k]`
   — frequency-domain cross-products, not time-domain.
3. Remove the "FFT PLACEHOLDER" marker (this will unblock P3-09 Guard 2).
4. Re-run P3-08 (k_int=0 sanity) and then P3-09 sweep.

---

## 7. Recommended Corrected Roadmap

| Priority | Step | Description | Blocker |
|----------|------|-------------|---------|
| P0 | Install Vivado | Get xvlog/xelab/xsim on the build host | Environment |
| P0 | xsim revalidate P3-05C/07 | Run `run_phase3_sync_xsim.sh` — core path checks 1–8 | xsim unavailable |
| P1 | xsim revalidate P3-08 k_int=0 | Run `run_p3_08_meyr_backend.sh` with xsim | xsim unavailable |
| P1 | xsim revalidate P3-10A | Run `run_p3_10a_iq_replay_buffer_sim.sh --sim xsim` | xsim unavailable |
| P2 | Real FFT integration | Replace S_COMPUTE in fft256_dual_symbol_frontend.v | Engineering work |
| P2 | Regenerate frequency-domain ROMs | DFT-based gen_meyr_reference_roms.py | Real FFT needed first |
| P2 | Re-run P3-08 (k_int=0, real FFT) | Validate Meyr pipeline with actual FFT output | Real FFT needed first |
| P3 | P3-09 integer CFO sweep | Run sweep for k_int ∈ {±1,±2,±4,±8} | Real FFT + new ROMs |
| P4 | P3-10B: integrate replay buffer | Add S_REPLAY state + iq_replay_buffer_576 to phase3_sync_top | P3-09 PASS |
| P4 | Implement int_cfo_corrector_pass | Second NCO+rotator for integer CFO correction | P3-10B integration |
| P5 | Synthesis check | Vivado implementation run | All RTL complete |
| P6 | FPGA/board bring-up | Not part of this phase | Hardware needed |

---

## 8. Summary of Confirmed Drift Points

1. **All CI_GATE PASS results are iverilog-only** — require Vivado xsim revalidation.
2. **P3-08 Meyr PASS uses bypass-FFT-compatible ROMs** — not real FFT validation; conditionally valid for k_int=0 only.
3. **P3-09 blocked on bypass FFT** — Guard 2 correctly prevents fake sweep PASS.
4. **run_p3_08_meyr_backend.sh default was `SIM=iverilog`** — repaired to `SIM=xsim`.
5. **run_p3_09_integer_cfo_sweep.sh default was `SIM=iverilog`** — repaired to `SIM=xsim`; xsim compile path implemented.
6. **run_p3_09 RTL source list had 3 nonexistent file paths and was missing 15+ required files** — repaired to match run_phase3_sync_sim.sh source list.
7. **No xsim-specific official runner existed** — repaired: `scripts/run_phase3_sync_xsim.sh` created.
8. **P3-10A replay buffer throughput is 1 sample/2 cycles** — not 1 sample/clock; documented as acceptable; not a functional defect.
9. **Integer CFO correction is not connected in phase3_sync_top** — expected; next phase (P3-10B).
10. **iq_replay_buffer_576 is not instantiated in phase3_sync_top** — expected; next phase (P3-10B).
