# Phase 3 Reference Synchronizer Architecture

## 1. C Reference: `synchronization()` Flow

Source: `ref/receiver.c`, function `synchronization()` (line 261).

The complete synchronization sequence proceeds in four steps:

```
Step 1  frame_detector()          → frameStart
Step 2  VanDeBeekAutoCorrelation() → peakIndexAuto
Step 3  slotStartIndex = frameStart + peakIndexAuto
Step 4  frac CFO = -atan2(Q[peakIndexAuto], I[peakIndexAuto]) / 2π
        apply_carrier_freq_offset(-fracCFO, ..., rxI + slotStartIndex)
Step 5  carrierFreqOffsetEstMeyr(..., slotStartIndex, ...)  → carrierFreqOffsetInt
        apply_carrier_freq_offset(-intCFO, ..., rxI + slotStartIndex)
Return: slotStartIndex
```

### 1.1 Step 1 — `frame_detector()` (receiver.c:327)

Energy-based frame start detector (Toan's version):

```
wndLen    = 25
threshold = 40000 (floating-point; RTL scales: threshold × 256 = 10,240,000)
HIT_COUNT = 10

envelopeBlock[j] = mean( I[i]² + Q[i]², i=j..j+wndLen-1 )

Case A (env[0] < threshold):
    scan j=1..len/2+10; count consecutive env[j] > threshold;
    when count == 10: frameStart = j + 1 - 10; return.

Case B (env[0] >= threshold):
    find startIndex = first j where env[j] < threshold;
    then scan from startIndex as in Case A.
```

Key: the search is limited to the first half of the received buffer
(`len/2 + 10`), preventing false detections in the data payload.

### 1.2 Step 2 — `VanDeBeekAutoCorrelation()` (receiver.c:556)

CP sliding-window autocorrelation starting from `frameStart`:

```
auto_corr(rxI + frameStart, rxQ + frameStart, autoCorrOutI, autoCorrOutQ,
          NSC=256, CP_LEN=32, normalizedValue_1)

normalizedValue_2[j] = 2 * |autocorr[j]| - normalizedValue_1[j]

peakIndexAuto = argmax(normalizedValue_2, NSC)
```

The `auto_corr()` function (receiver.c:571) computes:
```
P[m]    = sum_{i=0}^{CP_LEN-1} conj(rx[i+m]) × rx[i+m+NSC]
norm[m] = sum_{i=0}^{CP_LEN-1} (|rx[i+m+NSC]|² + |rx[i+m]|²)
```

This is the Schmidl-Cox / Van de Beek CP correlation metric.

### 1.3 Step 3 — `slotStartIndex`

```c
slotStartIndex = peakIndexAuto + frameStart;   // receiver.c:291
```

This is the absolute index in the receive buffer of the first CP sample of
the first OFDM symbol in the detected frame.

### 1.4 Step 4 — Fractional CFO Estimation and Correction

```c
fracfreqOffset = -atan2(autoCorrOutQ[peakIndexAuto],
                        autoCorrOutI[peakIndexAuto]) / (2 * PI);

apply_carrier_freq_offset(-fracfreqOffset * samplingFreq / NSC, 0,
                          samplingFreq, 0, symbols_per_slot,
                          rxI + slotStartIndex, rxQ + slotStartIndex);
```

The correction is applied **starting from slotStartIndex** and covers
`symbols_per_slot` samples (the entire slot).

### 1.5 Step 5 — Meyr Integer CFO Estimation and Correction

```c
carrierFreqOffsetInt = carrierFreqOffsetEstMeyr(rxI, rxQ, ..., slotStartIndex, ...);
```

Inside `carrierFreqOffsetEstMeyr()` (receiver.c:498):
```c
// PSS FFT input: NSC samples at rxI + slotStartIndex + CP_LEN
generate_complex_symbol(rxI + slotStartIndex + CP_LEN, ..., rxCmplx_PSS, NSC);

// SSS FFT input: NSC samples at rxI + slotStartIndex + 2*CP_LEN + NSC
generate_complex_symbol(rxI + slotStartIndex + 2*CP_LEN + NSC, ..., rxCmplx_SSS, NSC);
```

Meyr computes `term1 = FFT(PSS) × conj(FFT(SSS))`, cross-correlates with
known `term2 = m-seq × conj(gold-seq)`, finds peak → `carrierFreqOffsetInt`.

Then integer CFO correction is applied in the same way as fractional CFO.

---

## 2. RTL Module Inventory and Mapping

| C Function                        | RTL Module                                | Location                   |
|-----------------------------------|-------------------------------------------|----------------------------|
| `frame_detector()`                | `frame_detector`                          | `rtl/unit_test/`           |
| `VanDeBeekAutoCorrelation()`      | `timing_frac_cfo_top` → `timing_sync_top` | `rtl/unit_test/`           |
| `auto_corr()`                     | `cp_autocorr_core`                        | `rtl/phase2_legacy/`       |
| `slotStartIndex = f + p`          | `slot_start_r` in `frac_cfo_frame_corrector_top` | `rtl/`            |
| frac CFO atan2                    | `frac_cfo_estimator` (CORDIC)             | `rtl/phase2_legacy/`       |
| `apply_carrier_freq_offset()` (frac) | `frac_cfo_corrector_top`               | `rtl/phase2_legacy/`       |
| PSS/SSS extraction                | `pss_sss_symbol_extractor`                | `rtl/`                     |
| `carrierFreqOffsetEstMeyr()`      | `meyr_integer_cfo_freq_estimator_top`     | `rtl/`                     |
| `apply_carrier_freq_offset()` (int) | **not yet instantiated at Phase 3 level** | —                        |

### Top-Level Integration Module

`rtl/frac_cfo_frame_corrector_top.v` already integrates Steps 1–4:

```
FSM: IDLE → FILL → FRAME_DET → TIMING_CFO → LOAD_NCO → CORRECT → DONE
                     ↑               ↑              ↑
               frame_detector  timing_frac_cfo_top  frac_cfo_corrector_top
```

It exposes:
- `frame_index` — buffer address of frame start (= frameStart)
- `peak_lag`    — CP autocorr peak offset (= peakIndexAuto, relative to frameStart)
- `frac_phase`  — Q1.15 fractional CFO phase
- `done`        — 1-cycle pulse when TOTAL_SAMPLES corrected IQ are emitted
- `m_axis_*`    — corrected IQ stream, TOTAL_SAMPLES samples starting from slotStartIndex

---

## 3. slotStartIndex in RTL Context

Within `frac_cfo_frame_corrector_top`:
```verilog
slot_start_r <= frame_index_r + peak_lag;   // frac_cfo_frame_corrector_top.v:443
```

The corrected output stream (`m_axis_*`) starts from `slot_start_r` in the
buffer. Therefore, relative to the corrected output stream, the sample offsets are:

| Quantity                   | Absolute in buffer          | Relative to output stream |
|----------------------------|-----------------------------|---------------------------|
| CP start (slot start)      | `slot_start_r`              | 0                         |
| PSS FFT start              | `slot_start_r + CP_LEN`     | `CP_LEN` = 32             |
| PSS FFT end (exclusive)    | `slot_start_r + CP_LEN+NSC` | `CP_LEN + NSC` = 288      |
| SSS FFT start              | `slot_start_r + 2*CP_LEN+NSC` | `2*CP_LEN + NSC` = 320  |
| SSS FFT end (exclusive)    | `slot_start_r + 2*(CP_LEN+NSC)` | `2*(CP_LEN+NSC)` = 576 |

**Critical constraint**: Meyr requires 2 OFDM symbols (PSS + SSS each with their
CPs). The corrected output must be at least `2*(NSC+CP_LEN) = 576` samples.
`frac_cfo_frame_corrector_top`'s `OUTPUT_SAMPLES` parameter must be set to
`2*(NSC+CP_LEN)` when used in Phase 3.

---

## 4. Phase 3 Proposed Top-Level Block Diagram

```
IQ stream ──→ frac_cfo_frame_corrector_top (OUTPUT_SAMPLES=576)
                │  done, frame_index, peak_lag, frac_phase
                │  m_axis: 576 corrected IQ samples starting at slotStartIndex
                ↓
           slot_start_controller
                │  slot_valid, slot_start, pss_fft_start=32, sss_fft_start=320
                ↓
           pss_sss_symbol_extractor (frame_len=576, PSS@32, SSS@320)
                │  PSS stream (NSC samples), SSS stream (NSC samples)
                ↓
           [FFT256 ×2]
                │  PSS_FFT, SSS_FFT
                ↓
           meyr_integer_cfo_freq_estimator_top
                │  int_cfo
                ↓
           [NCO + complex_rotator: integer CFO correction]
                │
                ↓ fully synchronized IQ (for demodulation)
```

---

## 5. Production Path Note

`rtl/phase2_integer_cfo_estimator.v` is **excluded** from the Phase 3 production
path. It was a standalone unit-test/development file for experimenting with integer
CFO estimation. The production integer CFO estimator for Phase 3 is
`meyr_integer_cfo_freq_estimator_top.v`, which uses the Meyr algorithm as
implemented in the C reference.
