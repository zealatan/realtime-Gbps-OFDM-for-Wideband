# Phase 3 — Reference C vs RTL Verification Plan

**Version:** 1.0  
**Date:** 2026-05-27  
**Scope:** Simulation-only. No FPGA, Vivado implementation, DMA host code, board test, or ILA.

---

## 1. Overview

This document describes the simulation verification strategy for comparing the RTL synchronizer
(`rtl/phase2_streaming_sync_top.v`) against the C reference synchronizer in `ref/receiver.c`.

The approach is:
1. Run a modified C "golden dump" program to emit internal synchronization values to files
2. Convert the same input IQ samples to 16-bit fixed-point and feed them into the RTL testbench
3. Compare RTL outputs against C golden values with defined tolerances

---

## 2. C Reference Synchronization Flow

The entry point `synchronization()` in `ref/signal_processing_common.c` (line 261) implements:

```
synchronization(rxI, rxQ, rxLen, ...)
│
├── Step 1  frame_detector()
│   Energy: average |rx[n]|² over 25-sample window
│   Detects first run of 10 consecutive samples with avg energy > 40000
│   Output: frameStart  (int, absolute sample index, −1 on failure)
│
├── Step 2  VanDeBeekAutoCorrelation()
│   auto_corr(): for lag m = 0..NSC-1 (NSC=256):
│     P_I[m] = Σ_{i=0}^{CP_LEN-1}  (rxI[m+i]·rxI[m+i+NSC] + rxQ[m+i]·rxQ[m+i+NSC])
│     P_Q[m] = Σ_{i=0}^{CP_LEN-1}  (−rxI[m+i]·rxQ[m+i+NSC] + rxQ[m+i]·rxI[m+i+NSC])
│     E[m]   = Σ_{i=0}^{CP_LEN-1}  (|rx[m+i+NSC]|² + |rx[m+i]|²)
│   metric[m] = 2·|P[m]| − E[m]
│   peakIndexAuto = argmax(metric[0..NSC-1])
│   slotStartIndex = peakIndexAuto + frameStart
│   Output: peakIndexAuto, slotStartIndex, autoCorrOutI[], autoCorrOutQ[]
│
├── Step 3  Fractional CFO
│   fracfreqOffset = −atan2(P_Q[peak], P_I[peak]) / (2π)
│   apply_carrier_freq_offset(−fracfreqOffset·fs/NSC, ...)  in-place on rxI/rxQ
│
└── Step 4  Integer CFO (Meyr)
    carrierFreqOffsetEstMeyr(): FFT of PSS/SSS, frequency-domain cross-correlation
    Output: carrierFreqOffsetInt  (integer subcarrier bins)
    apply_carrier_freq_offset(−carrierFreqOffsetInt·fs/NSC, ...)
```

---

## 3. RTL Architecture (phase2_streaming_sync_top.v)

```
IQ stream (s_valid / s_data) ─────────────────────────────────┐
        │                                                       │
        ▼  accepted = s_valid & s_ready                        │
  ┌─────────────────┐                                          │
  │ P2-02           │  p_i/p_q/energy/sample_index/out_valid   │
  │ streaming_cp_   │ ─────────────────────────────────────────▼──►
  │ autocorr        │  ┌──────────────────────────────────────────┐
  └─────────────────┘  │ P2-06  streaming_cfo_corrector           │
        │               │ (NCO rotation, frac_phase_valid input)   │
        ▼               └──────────────────────────────────────────┘
  ┌─────────────────┐                                           ▲
  │ P2-03           │  metric/m_valid/m_sample_index/m_p_i/m_p_q
  │ streaming_      │ ─────────────────────────────────────────►
  │ timing_metric   │
  └─────────────────┘
        │
        ▼
  ┌─────────────────┐  timing_lock / lock_index / peak_p_i / peak_p_q
  │ P2-04           │ ─────────────────────────────────────────►
  │ streaming_peak_ │         │
  │ detector        │         │
  └─────────────────┘         │
                              ▼
                    ┌──────────────────────┐  frac_phase_valid / frac_phase
                    │ P2-05               │ ────────────────────────────────►
                    │ streaming_frac_cfo_ │         (→ P2-06 corrector)
                    │ estimator           │
                    └──────────────────────┘
```

---

## 4. Golden Value Mapping

| # | C Variable | C Source | Type | RTL Signal | RTL Module | Status |
|---|---|---|---|---|---|---|
| G1 | frameStart | frame_detector() | int | **(none)** | — | Missing in RTL |
| G2 | peakIndexAuto | VanDeBeekAutoCorrelation() | int | lock_index − frameStart | P2-04 (derived) | Partially observable |
| G3 | slotStartIndex | synchronization() | int | lock_index | top-level output port | **Observable** |
| G4 | autoCorrOutI[peak] | auto_corr() at peak lag | float | peak_p_i (48-bit) | P2-04 output port | **Observable** |
| G5 | autoCorrOutQ[peak] | auto_corr() at peak lag | float | peak_p_q (48-bit) | P2-04 output port | **Observable** |
| G6 | metric[peakIndexAuto] | VanDeBeekAutoCorrelation() | float | metric_dbg (32-bit, at lock cycle) | top-level debug port | **Observable** |
| G7 | fracfreqOffset | synchronization() step 3 | float | frac_phase_dbg (Q1.15) | top-level debug port | **Observable** |
| G8 | carrierFreqOffsetInt | carrierFreqOffsetEstMeyr() | int | *(separate module)* | meyr_integer_cfo_freq_estimator_top | Out of scope (not in streaming top) |
| G9 | P_I[m], P_Q[m] per sample | auto_corr() sliding | float[] | autocorr_p_i/p_q (internal wire) | P2-02 internal | **Not exposed at top** |
| G10 | metric[m] per sample | VanDeBeekAutoCorrelation() | float[] | metric_out (internal wire) | P2-03 internal | **Not exposed at top** |

---

## 5. Algorithm Differences (C vs RTL)

These differences affect numeric comparison tolerances:

| Aspect | C Reference | RTL Behaviour | Expected Error |
|---|---|---|---|
| Frame anchor | frame_detector energy detector | None; RTL counts from sample 0 | lock_index ≠ slotStartIndex unless frameStart=0 |
| Search window for peak | argmax over NSC=256 lags | argmax over WINDOW=NSC+CP_LEN=288 valid samples | Peak may differ by ±CP_LEN |
| \|P\| computation | Exact √(P_I² + P_Q²) | Alpha-max-beta-min: max+min/4+min/8 | ≤3.5% magnitude error |
| Energy accumulation | Σ(\|x[n+N]\|² + \|x[n]\|²) both sides | Σ(\|x[n]\|²) current sample only | Factor ~2 energy difference |
| Data type | float32 | 16-bit IQ → 48-bit ACC | Quantization noise |
| Integer CFO | Applied in synchronization() | Separate module, not in streaming top | G8 not comparable here |

---

## 6. Verification Plan — Steps

### Step A: Golden Dump (C side)

Build a standalone C program `scripts/golden_dump.c` (see Section 7) that:
- Reads a raw IQ file (float32 binary or space-separated text)
- Calls the reference synchronization() pipeline
- Writes golden values to `golden/` directory per the format in `docs/phase3_golden_dump_format.md`

The C dump program must not change any algorithm in `ref/`. It calls the functions as-is
and only adds file-writing after each internal step.

### Step B: IQ Stimulus Generation

Generate or capture a test IQ vector:
- Synthetic: C transmitter (`ref/transmitter.c`) generates a slot with known frameStart=0
- Saved as: `tb/data/iq_stimulus.f32` (binary float pairs I,Q) and `tb/data/iq_stimulus_q15.hex`
  (16-bit signed fixed-point, Q1.15 scaled, for RTL injection)

The C golden dump runs on `iq_stimulus.f32`. The RTL testbench drives `iq_stimulus_q15.hex`.

### Step C: RTL Simulation

Run `tb/phase3_sync_reference_compare_tb.sv` with a Verilog simulator (Icarus Verilog or Xcelium).
The testbench:
- Instantiates `phase2_streaming_sync_top`
- Streams the IQ stimulus sample by sample
- Captures timing_lock event and records lock_index, metric_dbg, peak_p_i/p_q, frac_phase_dbg
- Dumps RTL values to `sim_out/rtl_results.txt`

### Step D: Comparison

Run `scripts/compare_golden_rtl.py`:
- Reads `golden/phase3_golden_values.txt`
- Reads `sim_out/rtl_results.txt`
- Applies tolerances (see Section 8)
- Prints PASS / FAIL for each golden signal

---

## 7. Golden Dump C Program — Specification

File: `scripts/golden_dump.c`

The program implements a thin wrapper around the reference functions:

```c
// pseudo-code structure
int main(int argc, char** argv) {
    // 1. Read IQ float file argv[1] into rxI[], rxQ[]
    // 2. frameStart = frame_detector(rxI, rxQ, rxLen, 25, 40000);
    //    write: G1 frameStart
    // 3. peakIndexAuto = VanDeBeekAutoCorrelation(rxI, rxQ, frameStart,
    //                        autoCorrOutI, autoCorrOutQ);
    //    slotStartIndex = peakIndexAuto + frameStart;
    //    write: G2 peakIndexAuto
    //    write: G3 slotStartIndex
    //    write: G4 autoCorrOutI[peakIndexAuto]
    //    write: G5 autoCorrOutQ[peakIndexAuto]
    //    write: G6 2*|P[peak]| - E[peak]   (timing metric at peak)
    //    write: G9_full autoCorrOutI[], autoCorrOutQ[]  (all NSC values)
    //    write: G10_full normalizedValue_2[]            (all NSC metric values)
    // 4. fracfreqOffset = -atan2(autoCorrOutQ[peak], autoCorrOutI[peak])/(2*PI)
    //    write: G7 fracfreqOffset
}
```

Link against only the math library (−lm). Do NOT link libiio or fftw3 here — this is a
standalone comparator, not the full receiver. Use a local auto_corr() reimplementation
that avoids FFTW (since FFTW plans are created in signal_processing_parameters_init which
requires libiio). Alternatively, provide a synthetic IQ file so no FFTW is needed for
Steps 1–3 (frame_detector and VanDeBeekAutoCorrelation are FFTW-free in the C reference).

---

## 8. Comparison Tolerances

| Golden Value | Tolerance | Rationale |
|---|---|---|
| G3 slotStartIndex vs lock_index | ±0 samples (exact) when frameStart=0 | Index is an integer count |
| G4 autoCorrOutI[peak] vs peak_p_i | ±5% relative | Q1.15 quantization + alpha-max approx |
| G5 autoCorrOutQ[peak] vs peak_p_q | ±5% relative | Same |
| G6 metric at peak vs metric_dbg | ±10% relative | Energy accumulation difference (one-sided vs two-sided) |
| G7 fracfreqOffset vs frac_phase_dbg | ±2 LSB (Q1.15) | CORDIC + quantization |

When frameStart ≠ 0, test with synthetic IQ where frameStart is forced to 0 (burst preamble
starts at sample 0) to align C and RTL reference points.

---

## 9. What Can Be Tested Now

| Test | Status | Prerequisite |
|---|---|---|
| slotStartIndex (G3) vs lock_index | Ready to test | IQ stimulus where frameStart=0 |
| peak_p_i/p_q (G4/G5) vs autoCorrOutI/Q | Ready to test | Same |
| frac_phase (G7) vs fracfreqOffset | Ready to test | Same |
| metric_dbg (G6) at lock cycle | Ready to test | Same |
| Per-sample P_I/P_Q trace (G9) | Needs RTL change | autocorr_p_i/p_q not at top ports |
| Per-sample metric trace (G10) | Needs RTL change | metric_out not at top ports |
| Integer CFO (G8) | Out of scope here | Separate meyr module not in streaming top |

---

## 10. RTL Observability Gaps — Signals to Expose

The design session must add these debug output ports to `phase2_streaming_sync_top.v`
for full per-sample comparison capability:

| Signal | Source Module | Width | Purpose |
|---|---|---|---|
| dbg_autocorr_p_i | P2-02 autocorr_p_i | ACC_W=48 | Per-sample P_I (compare G9 array) |
| dbg_autocorr_p_q | P2-02 autocorr_p_q | ACC_W=48 | Per-sample P_Q |
| dbg_autocorr_energy | P2-02 autocorr_energy | ACC_W=48 | Per-sample energy |
| dbg_autocorr_valid | P2-02 autocorr_valid | 1 | Valid strobe |
| dbg_autocorr_index | P2-02 autocorr_index | 32 | Sample index |
| dbg_metric | P2-03 metric_out | METRIC_W=32 | Per-sample timing metric (compare G10) |
| dbg_metric_valid | P2-03 metric_valid | 1 | Valid strobe |
| dbg_metric_index | P2-03 m_sample_index | 32 | Sample index |

These are wire taps only; no datapath modification is required.

---

## 11. File Inventory (Produced by This Session)

| File | Description |
|---|---|
| `md_files/step02_phase3_reference_c_vs_rtl_verification_prompt.md` | Mandatory prompt archive |
| `docs/phase3_reference_c_vs_rtl_verification_plan.md` | This file |
| `docs/phase3_golden_dump_format.md` | Golden file format specification |
| `scripts/run_phase3_sync_sim.sh` | End-to-end simulation runner |
| `tb/phase3_sync_reference_compare_tb.sv` | RTL testbench skeleton |

---

## 12. Excluded Files

- `rtl/unit_test/phase2_integer_cfo_estimator.v` — unit-test/standalone; excluded from
  production architecture verification per project rules.
- All FPGA-specific, Vivado IP, DMA, and board files.
