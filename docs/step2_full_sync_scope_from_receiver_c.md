# Step 2 — Full C Synchronizer Scope: receiver.c Analysis and RTL Architecture Mapping

## 1. Purpose and Final Goal

The final goal is **full RTL replacement of the C `synchronization()` function** in `ref/receiver.c`.

This is not a timing-only project. The complete synchronization path covers:

```text
frame detection (energy detector)
→ CP auto-correlation timing (Van De Beek)
→ timing metric generation and peak detection
→ fractional CFO estimation (atan2 of autocorrelation peak)
→ fractional CFO correction (NCO + complex rotation)
→ PSS/SSS symbol extraction and FFT
→ Meyr integer CFO estimation (frequency-domain cross-correlation)
→ integer CFO correction (NCO + complex rotation)
```

The RTL top module will be: `ofdm_synchronizer_top.v`

---

## 2. C Synchronization Call Graph

### Actual call graph from receiver.c

```text
synchronization()                               [receiver.c:261]
├── frame_detector()                            [receiver.c:327]
│     (energy sliding-window, no sub-calls)
│
├── VanDeBeekAutoCorrelation()                  [receiver.c:556]
│   ├── auto_corr()                             [receiver.c:571]
│   │     (CP correlator, no sub-calls)
│   └── find_max_index()                        [receiver.c:585]
│         (argmax, no sub-calls)
│
├── atan2()                                     [libc — fractional CFO phase]
│
├── apply_carrier_freq_offset()                 [receiver.c:443]   ← fractional CFO correction
│     (NCO + complex rotate, no sub-calls)
│
├── carrierFreqOffsetEstMeyr()                  [receiver.c:498]
│   ├── generate_complex_symbol() × 2           [pluto.h:213 — I/Q packing for PSS, SSS]
│   ├── fft_without_rearrange() × 2             [pluto.h:151 — PSS FFT, SSS FFT]
│   ├── [inline: pointwise conj(PSS)*SSS]       [receiver.c:523-525 — crossCorrTerm1]
│   ├── [inline: pointwise conj(mU)*goldU]      [receiver.c:527-528 — crossCorrTerm2]
│   ├── fft_correlation_Meyr()                  [receiver.c:458]
│   │   ├── generate_complex_symbol() × 2       [pack I/Q → complex]
│   │   ├── fftwf_execute_dft() × 2             [forward FFTs — size 2*NSC]
│   │   ├── [inline: pointwise conj*]           [receiver.c:474-476]
│   │   └── fftwf_execute_dft()                 [IFFT — size 2*NSC]
│   └── find_peak_index()                       [receiver.c:543]
│         (argmax of |I|²+|Q|², no sub-calls)
│
└── apply_carrier_freq_offset()                 [receiver.c:307] ← integer CFO correction
      (NCO + complex rotate, no sub-calls)
```

### Deviation from expected graph in prompt

The prompt expected `auto_corr_norm()` as a separate call. In the actual code, the
timing metric normalization is computed **inline** inside `VanDeBeekAutoCorrelation()`:

```c
normalizedValue_2[j] = 2 * sqrt(pow(autoCorrOutI[j],2) + pow(autoCorrOutQ[j],2))
                        - normalizedValue_1[j];
```

`auto_corr()` returns both the complex correlation and the power normalization value via a
third output array (`normalizedValue`). There is no separate `auto_corr_norm()` function.

---

## 3. Key Constants (from pluto.h)

| Constant | Value | Meaning |
|----------|-------|---------|
| `NSC` | 256 | FFT size / number of subcarriers |
| `CP_LEN` | 32 | Cyclic prefix length in samples |
| `NUM_SYN_BLOCKS` | 2 | Sync symbol blocks per slot |
| `NUM_EST_BLOCKS` | 0 | Estimation blocks |
| `NUM_CTRL_BLOCKS` | 0 | Control blocks |
| `NUM_DATA_BLOCKS` | 5 | Data blocks per slot |
| `PSS_RANGE` | 3 | PSS cell ID range (0..2) |
| `SSS_RANGE` | 336 | SSS cell ID range |
| `PI` | 3.1415926535 | — |
| Symbol period | NSC + CP_LEN = 288 | samples per OFDM symbol |
| `threshold` | 40000 | energy detector threshold (hardcoded in synchronization()) |
| `wndLen` | 25 | energy window length (hardcoded in synchronization()) |

---

## 4. Full Synchronization Stage Breakdown

### Stage 1 — Frame Detection

| Item | Detail |
|------|--------|
| C function | `frame_detector()` |
| Purpose | Coarse energy-based detection of slot boundary. Finds the first sample index where the signal energy rises above a threshold for 10 consecutive windows. |
| Inputs | `rxI[rxLen]`, `rxQ[rxLen]`, `len`, `wndLen=25`, `threshold=40000` |
| Outputs | `indexFrame` — first sample of valid slot energy, or -1 on failure |
| Main computation | Sliding-window average energy: `E[j] = (1/wndLen) * sum_{i=j}^{j+wndLen-1} (I[i]² + Q[i]²)`. Two cases: start below threshold (look for rising edge), start above threshold (skip initial high-energy region, then look for rising edge). Returns when `counterFrame == 10`. |
| Important constants | `wndLen=25`, `threshold=40000`, `counterFrame_needed=10`, searches first `len/2 + 10` samples |
| RTL difficulty | Low. Sliding-window accumulator with subtract-and-add update, comparator, counter. No complex arithmetic. |
| Verification risk | Low. Threshold and window length are fixed; two FSM paths (Case 1 / Case 2) must both be tested. |

---

### Stage 2 — CP Auto-Correlation (Van De Beek)

| Item | Detail |
|------|--------|
| C function | `VanDeBeekAutoCorrelation()` → calls `auto_corr()` |
| Purpose | Compute the cyclic-prefix autocorrelation over NSC candidate timing offsets to find the OFDM symbol boundary. |
| Inputs | `rxI`, `rxQ` (offset by `frameStart`); `NSC=256`, `CP_LEN=32` |
| Outputs | Complex correlation arrays `autoCorrOutI[NSC]`, `autoCorrOutQ[NSC]`; normalization `normalizedValue_1[NSC]` |
| Main computation | For each lag m in [0, NSC): `out[m] = sum_{i=0}^{CP_LEN-1} conj(rx[i+m]) * rx[i+m+NSC]`. Normalization: `E[m] = sum_{i=0}^{CP_LEN-1} (|rx[i+m+NSC]|² + |rx[i+m]|²)`. Each of the NSC lags requires CP_LEN=32 complex multiply-accumulate operations. |
| Important constants | `NSC=256` lags, `CP_LEN=32` accumulation length. Total operations: 256×32 = 8192 complex MACs. |
| RTL difficulty | High. Dual sliding-window correlator with complex arithmetic. Resource-intensive: 8192 complex MACs needed; must be serialized or pipelined. Output must be valid before `find_max_index` is called. |
| Verification risk | High. Numerical precision (fixed-point accumulator width), timing metric shape, correct peak location. Off-by-one in lag indexing will give wrong symbol boundary. |

---

### Stage 3 — Timing Metric Generation

| Item | Detail |
|------|--------|
| C function | Inline in `VanDeBeekAutoCorrelation()` |
| Purpose | Converts complex correlation output and energy normalization into a real-valued timing metric with a sharp peak. |
| Inputs | `autoCorrOutI[NSC]`, `autoCorrOutQ[NSC]`, `normalizedValue_1[NSC]` |
| Outputs | `normalizedValue_2[NSC]` |
| Main computation | `metric[j] = 2 * sqrt(I[j]² + Q[j]²) - E[j]`. Equivalent to: `2 * |autocorr[j]| - power_normalization[j]`. |
| Important constants | NSC=256 point evaluation |
| RTL difficulty | Moderate. Requires magnitude computation (CORDIC or approximation), subtraction. |
| Verification risk | Moderate. Magnitude approximation vs exact sqrt will shift peak slightly. |

---

### Stage 4 — Peak Detection

| Item | Detail |
|------|--------|
| C function | `find_max_index()` (for timing metric), `find_peak_index()` (for Meyr correlation) |
| Purpose | `find_max_index`: argmax of a real array. `find_peak_index`: argmax of `I²+Q²` of a complex array. |
| Inputs | Array + length |
| Outputs | Index of maximum |
| Main computation | Linear scan, keep running maximum |
| Important constants | `find_max_index` over NSC=256; `find_peak_index` over `crossCorrLen = 2*NSC-1 = 511` |
| RTL difficulty | Low. Comparator tree or sequential scan. Reusable across timing and CFO paths. |
| Verification risk | Low. Edge cases: all-equal array, maximum at index 0 or last index. |

---

### Stage 5 — Fractional CFO Estimation

| Item | Detail |
|------|--------|
| C function | Inline `atan2()` in `synchronization()` |
| Purpose | Extract fractional carrier frequency offset from the phase angle of the CP autocorrelation peak. |
| Inputs | `autoCorrOutQ[peakIndexAuto]`, `autoCorrOutI[peakIndexAuto]` |
| Outputs | `fracfreqOffset` — fractional CFO in cycles/sample, range (-0.5, +0.5) |
| Main computation | `fracfreqOffset = -atan2(Q_peak, I_peak) / (2*PI)`. The phase of the autocorrelation peak equals `2*PI * CFO / NSC * NSC_samples = 2*PI * fracCFO`, so dividing by `2*PI` gives fractional CFO in subcarrier spacings. |
| Important constants | Range ±0.5 subcarrier (fractional only) |
| RTL difficulty | High. `atan2` requires CORDIC or LUT-based phase computation. This is the most complex single arithmetic operation in the synchronizer. |
| Verification risk | High. Phase wrapping, quadrant handling, precision of atan2 approximation. |

---

### Stage 6 — Fractional CFO Correction

| Item | Detail |
|------|--------|
| C function | `apply_carrier_freq_offset()` — first call in `synchronization()` |
| Purpose | Rotate the received signal by a per-sample complex exponential to cancel the fractional CFO. |
| Inputs | `freq_offset = -fracfreqOffset * samplingFreq/NSC` (Hz), `phase=0`, `samplingFreq`, `startPoint=0`, `lenIN=symbols_per_slot`, `rxI/Q + slotStartIndex` |
| Outputs | In-place corrected `rxI`, `rxQ` |
| Main computation | For each sample j: `angle[j] = 2*PI * freq_offset * j / samplingFreq`; `rx[j] *= exp(j*angle[j])`. Implemented as: `I_out = cos(angle)*I - sin(angle)*Q`, `Q_out = cos(angle)*Q + sin(angle)*I`. |
| Important constants | Correction applied over `symbols_per_slot` samples starting at `slotStartIndex` |
| RTL difficulty | High. Requires NCO (phase accumulator + sine/cosine lookup or CORDIC) feeding a complex rotator. Continuous phase coherence across all samples is essential. |
| Verification risk | High. Phase wrap-around, NCO phase accumulator resolution, interaction with downstream integer CFO correction. |

---

### Stage 7 — PSS/SSS Symbol Extraction and FFT

| Item | Detail |
|------|--------|
| C function | `generate_complex_symbol()` + `fft_without_rearrange()` inside `carrierFreqOffsetEstMeyr()` |
| Purpose | Extract the PSS (symbol 0) and SSS (symbol 1) OFDM symbols after CP removal, pack I/Q into complex format, and compute their DFTs. |
| Inputs | `rxI/Q + slotStartIndex + CP_LEN` for PSS; `rxI/Q + slotStartIndex + 2*CP_LEN + NSC` for SSS; NSC=256 samples each |
| Outputs | `signalPSSfftI/Q[NSC]`, `signalSSSfftI/Q[NSC]` — frequency-domain representations |
| Main computation | `generate_complex_symbol`: pack float I/Q → `float complex`. `fft_without_rearrange`: NSC-point DFT via FFTW (no fftshift). |
| Important constants | PSS at `+CP_LEN` offset, SSS at `+2*CP_LEN + NSC` offset from `slotStartIndex`; both are NSC=256-sample symbols |
| RTL difficulty | Moderate (extraction) + High (FFT). CP removal is a simple pointer offset in C; in RTL it requires a buffer and address counter. The FFT requires a 256-point engine. |
| Verification risk | High. Wrong CP removal offset will corrupt the FFT output. FFT numerical precision must match the reference. |

---

### Stage 8 — FFT

| Item | Detail |
|------|--------|
| C function | `fft_without_rearrange()` (NSC-point); `fftwf_execute_dft()` (2*NSC-point inside `fft_correlation_Meyr`) |
| Purpose | Two distinct FFT uses: (1) NSC=256-point DFT for PSS/SSS symbol transform; (2) 2*NSC=512-point DFT/IFFT for frequency-domain cross-correlation in Meyr estimator. |
| Inputs | Complex array, length, pre-allocated FFTW plan |
| Outputs | Complex frequency-domain array |
| Main computation | Radix-2 Cooley-Tukey FFT |
| Important constants | Two sizes: NSC=256 and 2*NSC=512 |
| RTL difficulty | High. May use Xilinx FFT IP (configurable point size). Two instances with different sizes or a reconfigurable core. No fftshift applied in the sync path. |
| Verification risk | High. Bit-reversal ordering, scaling convention, and twiddle factor precision must all match the reference model. |

---

### Stage 9 — Integer CFO Estimation (Meyr Method)

| Item | Detail |
|------|--------|
| C function | `carrierFreqOffsetEstMeyr()` + `fft_correlation_Meyr()` |
| Purpose | Estimate the integer subcarrier carrier frequency offset using a frequency-domain cross-correlation between the received PSS/SSS pair and a reference PSS/SSS pair (mU, goldU sequences). |
| Inputs | Corrected `rxI/Q` at `slotStartIndex`; reference sequences `mUI/Q` and `goldUI/Q` (PSS/SSS local replica) |
| Outputs | `carrierFreqOffsetInt` — integer CFO in subcarrier units, range [-(NSC-1), +(NSC-1)] |
| Main computation | 1. Extract PSS and SSS symbols, FFT each. 2. Compute `term1[j] = conj(PSS_FFT[j]) * SSS_FFT[j]` (received product). 3. Compute `term2[j] = conj(mU[j+CP_LEN]) * goldU[j+CP_LEN]` (reference product). 4. Cross-correlate term2 with term1 via `fft_correlation_Meyr` (forward FFT both, multiply, IFFT). 5. `peakIndexMeyr = argmax(|corr|²)`. 6. `intCFO = peakIndexMeyr - (NSC-1)`. |
| Important constants | `crossCorrLen = 2*NSC-1 = 511`; reference accessed at `[j + CP_LEN]` offset; `intCFO ∈ [-(NSC-1), NSC-1]` |
| RTL difficulty | Very high. Requires: 2× NSC FFT, 2× NSC-point pointwise multiply, 1× 2*NSC FFT + IFFT, 1× 511-point peak detector. Heavy resource use. |
| Verification risk | Very high. Requires ROM for PSS/SSS reference sequences (mU, goldU). FFT sizes differ between PSS extraction (NSC) and correlation (2*NSC). Off-by-one in peak-to-offset mapping yields wrong integer CFO. |

---

### Stage 10 — Integer CFO Correction

| Item | Detail |
|------|--------|
| C function | `apply_carrier_freq_offset()` — second call in `synchronization()` |
| Purpose | Rotate the signal to cancel the estimated integer subcarrier offset. |
| Inputs | `freq_offset = -carrierFreqOffsetInt * samplingFreq/NSC` (Hz), `phase=0`, same other params as Stage 6 |
| Outputs | In-place corrected `rxI/Q + slotStartIndex` |
| Main computation | Same NCO + complex rotation as Stage 6, but with integer-subcarrier step size |
| Important constants | Correction over `symbols_per_slot` samples |
| RTL difficulty | Moderate. Shares the NCO + complex rotator hardware with Stage 6. Can reuse if the correction can be applied sequentially or if a programmable NCO step is used. |
| Verification risk | Moderate. Must confirm correct sign convention and that fractional and integer corrections are applied in the right order. |

---

## 5. C-to-RTL Block Mapping

| C function / operation | Proposed RTL block | Notes |
|---|---|---|
| `frame_detector()` | `frame_detector.v` | Sliding-window energy accumulator, 2-case FSM |
| `auto_corr()` | `cp_autocorr_core.v` | NSC=256-lag × CP_LEN=32-tap complex MAC engine |
| timing metric: `2*|autocorr|-energy` | `timing_metric_core.v` | Magnitude + subtract; shares accumulator with `cp_autocorr_core.v` |
| `find_max_index()` | `peak_detector.v` | Argmax of real array; reused for timing |
| `find_peak_index()` | `peak_detector.v` (same, parameterized) | Argmax of I²+Q² over 511-point array |
| `atan2(Q, I)` | `cordic_atan2.v` or `xilinx_cordic_wrapper.v` | Phase of autocorrelation peak → fractional CFO |
| `apply_carrier_freq_offset()` (both calls) | `nco_phase_gen.v` + `complex_rotator.v` | Programmable NCO step, shared between frac and int CFO corrections |
| `generate_complex_symbol()` | `symbol_extractor.v` | CP skip + I/Q → complex packing; produces NSC samples from symbol buffer |
| `fft_without_rearrange()` (NSC=256) | `fft_wrapper.v` (256-point) | Wraps Xilinx FFT IP or custom radix-2 engine |
| `fftwf_execute_dft` (2*NSC=512, fwd+inv) | `fft_wrapper.v` (512-point, fwd) + `ifft_wrapper.v` (512-point, inv) | Used only inside Meyr correlation |
| `conj(PSS_FFT[j]) * SSS_FFT[j]` (inline) | `axis_complex_mult.v` (existing) | Reuse existing complex multiplier |
| `conj(mU[j]) * goldU[j]` (inline) | `pss_sss_rom.v` + `axis_complex_mult.v` | ROM provides mU/goldU; multiplier forms reference product |
| `fft_correlation_Meyr()` | `meyr_corr_core.v` | Orchestrates 512-pt FFT×2 + conj multiply + IFFT |
| `carrierFreqOffsetEstMeyr()` | `integer_cfo_estimator.v` | Top wrapper: symbol extract → FFTs → cross-corr → peak |
| `int intCFO = peak - (NSC-1)` | inside `integer_cfo_estimator.v` | Subtract NSC-1 to center |
| `apply_carrier_freq_offset()` (integer) | `integer_cfo_corrector.v` | Drives the shared NCO+rotator with integer-subcarrier step |
| Top-level FSM sequencing all stages | `sync_control_fsm.v` | State machine: FRAME_DET → AUTOCORR → FRAC_CFO → INT_CFO → DONE |
| AXI-Lite register interface | `axi_lite_sync_regs.v` | Config inputs, status outputs, threshold/window programmability |

---

## 6. Proposed Final RTL Hierarchy

```text
ofdm_synchronizer_top.v
│
├── axi_lite_sync_regs.v          ← AXI-Lite slave: config registers + status readback
│                                    (threshold, window, CFO limits, done/error flags)
│
├── sync_control_fsm.v             ← Top-level sequencer FSM
│                                    States: IDLE → FRAME_DET → AUTOCORR →
│                                    FRAC_CFO_EST → FRAC_CFO_CORR → INT_CFO_EST →
│                                    INT_CFO_CORR → DONE
│
├── frame_detector.v               ← Stage 1: energy sliding-window detector
│                                    Sliding accumulator, threshold compare, run-of-10 counter
│
├── cp_autocorr_core.v             ← Stage 2: Van De Beek CP autocorrelation
│                                    256-lag, 32-tap complex MAC; outputs complex corr + power
│
├── timing_metric_core.v           ← Stage 3: timing metric = 2|corr| - power
│                                    Magnitude + subtraction post-processor on cp_autocorr_core output
│
├── peak_detector.v                ← Stage 4 (shared): argmax module
│                                    Parameterized for real (NSC=256) and complex-mag (511-point)
│
├── frac_cfo_estimator.v           ← Stage 5: phase of autocorr peak → fractional CFO
│   └── cordic_atan2.v             ←   CORDIC-based atan2 or Xilinx CORDIC IP wrapper
│         (or xilinx_cordic_wrapper.v)
│
├── nco_phase_gen.v                ← Stage 6+10 shared: programmable NCO
│                                    Phase accumulator with programmable step (set by FSM)
│
├── complex_rotator.v              ← Stage 6+10 shared: complex multiply by e^{jθ}
│   └── axis_complex_mult.v        ←   reuse existing complex multiplier
│         (existing, reused)
│
├── integer_cfo_estimator.v        ← Stage 9 top: Meyr integer CFO estimator
│   │
│   ├── symbol_extractor.v         ←   CP removal + pack I/Q for PSS and SSS
│   │
│   ├── fft_wrapper.v              ←   256-point FFT (PSS + SSS symbols)
│   │     (wraps Xilinx FFT IP or custom)
│   │
│   ├── pss_sss_rom.v              ←   ROM holding mU and goldU reference sequences
│   │
│   ├── axis_complex_mult.v        ←   conj(PSS)*SSS and conj(mU)*goldU (reused existing)
│   │     (existing, reused ×2)
│   │
│   └── meyr_corr_core.v           ←   512-point cross-correlation engine
│       ├── fft_wrapper.v          ←     512-point forward FFT (×2 instances)
│       │     (or shared/reconfigured)
│       ├── [conj multiply]        ←     pointwise conj(A)*B in freq domain
│       ├── ifft_wrapper.v         ←     512-point IFFT
│       └── peak_detector.v        ←     511-point complex-mag argmax (reused)
│
├── integer_cfo_corrector.v        ← Stage 10: load NCO with integer CFO step, apply correction
│
└── sample_buffer.v                ← Input sample store (holds NSC+CP_LEN × num_symbols)
                                     (needed for random-access to slotStartIndex + symbol offsets)
```

---

## 7. Reuse from Existing Repository

| Existing module | Reuse opportunity |
|---|---|
| `axis_complex_mult.v` | **Direct reuse** for: (1) conj(PSS_FFT)*SSS_FFT inside `integer_cfo_estimator.v`, (2) conj(mU)*goldU, (3) frequency-domain multiply inside `meyr_corr_core.v`, (4) complex rotation inside `complex_rotator.v`. The dual-input AXI-Stream interface and Q15 fixed-point arithmetic match the synchronizer's requirements. |
| `axi_lite_regfile.v` | **Template reuse** for `axi_lite_sync_regs.v`. The 4-state write FSM and 2-state read FSM are directly applicable. Expand from 4 to ~10–12 registers for threshold, window, CFO limits, timing offset, CFO output, status, and interrupt enable. |
| `simple_dma_add_ctrl.v` | **Pattern reuse** for `sync_control_fsm.v`. The AXI-Lite + AXI4-master dual-bus system DUT demonstrates how to layer a control-plane register file on top of a multi-step datapath engine. The busy/done/error sticky-register pattern and start-pulse protocol will be reproduced in the synchronizer top. |
| `axi_mem_model.sv` | **Direct reuse** in testbenches. The 1024×32-bit AXI4 memory model will serve as the IQ sample store in all synchronizer testbenches, providing an AXI4 slave for the DMA-fed sample buffer. |
| `simple_dma_copy_nword.v` | **Concept reuse** for input sample DMA. The sample buffer may be loaded via a DMA engine matching this pattern before the synchronizer FSM starts. |

---

## 8. Full Implementation Roadmap (30 Steps)

### Foundation (Steps 1–5)

| Step | Action | New files |
|------|--------|-----------|
| 1 | Workspace audit and DUT ladder analysis | (complete) |
| 2 | Full C synchronizer scope extraction | (this step) |
| 3 | Fixed-point and interface specification | `docs/step3_fixedpoint_spec.md` |
| 4 | Build Python/NumPy golden model of all 10 stages | `ref/sync_golden.py` |
| 5 | Validate Python model matches C output on captured IQ data | test vectors in `ref/` |

### Building Blocks (Steps 6–16)

| Step | Action | New RTL files |
|------|--------|---------------|
| 6 | `peak_detector.v` — parameterized argmax + testbench | `rtl/peak_detector.v`, `tb/peak_detector_tb.sv` |
| 7 | `frame_detector.v` — energy sliding-window + testbench | `rtl/frame_detector.v`, `tb/frame_detector_tb.sv` |
| 8 | `cp_autocorr_core.v` — 256-lag×32-tap complex MAC + testbench | `rtl/cp_autocorr_core.v`, `tb/cp_autocorr_core_tb.sv` |
| 9 | `timing_metric_core.v` — 2\|corr\| − power + testbench | `rtl/timing_metric_core.v`, `tb/timing_metric_core_tb.sv` |
| 10 | `cordic_atan2.v` — CORDIC-based atan2 (or Xilinx wrapper) + testbench | `rtl/cordic_atan2.v`, `tb/cordic_atan2_tb.sv` |
| 11 | `nco_phase_gen.v` — programmable NCO phase accumulator + testbench | `rtl/nco_phase_gen.v`, `tb/nco_phase_gen_tb.sv` |
| 12 | `complex_rotator.v` — per-sample complex rotation using NCO output | `rtl/complex_rotator.v`, `tb/complex_rotator_tb.sv` |
| 13 | `symbol_extractor.v` — CP removal + AXI-Stream I/Q output | `rtl/symbol_extractor.v`, `tb/symbol_extractor_tb.sv` |
| 14 | `fft_wrapper.v` — 256-point FFT (Xilinx IP or custom radix-2) + testbench | `rtl/fft_wrapper.v`, `tb/fft_wrapper_tb.sv` |
| 15 | `pss_sss_rom.v` — ROM for mU/goldU reference sequences | `rtl/pss_sss_rom.v`, `tb/pss_sss_rom_tb.sv` |
| 16 | `meyr_corr_core.v` — 512-point cross-correlation engine + testbench | `rtl/meyr_corr_core.v`, `tb/meyr_corr_core_tb.sv` |

### Subsystem Integration (Steps 17–22)

| Step | Action | New RTL files |
|------|--------|---------------|
| 17 | `frac_cfo_estimator.v` — integrates autocorr peak + CORDIC | `rtl/frac_cfo_estimator.v`, `tb/frac_cfo_estimator_tb.sv` |
| 18 | Fractional CFO correction subsystem — integrates NCO + rotator + verify end-to-end | `tb/frac_cfo_correction_tb.sv` |
| 19 | `integer_cfo_estimator.v` — integrates symbol extractor + 2× FFT + Meyr corr + peak detector | `rtl/integer_cfo_estimator.v`, `tb/integer_cfo_estimator_tb.sv` |
| 20 | `integer_cfo_corrector.v` — programs NCO with integer step, applies rotation | `rtl/integer_cfo_corrector.v`, `tb/integer_cfo_corrector_tb.sv` |
| 21 | `axi_lite_sync_regs.v` — expanded AXI-Lite register file for synchronizer config/status | `rtl/axi_lite_sync_regs.v`, `tb/axi_lite_sync_regs_tb.sv` |
| 22 | `sync_control_fsm.v` — top-level sequencer FSM, no datapath yet | `rtl/sync_control_fsm.v`, `tb/sync_control_fsm_tb.sv` |

### Top Integration (Steps 23–27)

| Step | Action | New RTL files |
|------|--------|---------------|
| 23 | `sample_buffer.v` — AXI4-facing IQ sample SRAM interface | `rtl/sample_buffer.v`, `tb/sample_buffer_tb.sv` |
| 24 | `ofdm_synchronizer_top.v` v1 — integrate FSM + frame detector + autocorr + frac CFO | `rtl/ofdm_synchronizer_top.v`, `tb/ofdm_synchronizer_top_tb.sv` |
| 25 | v2 — add integer CFO path to top | update `rtl/ofdm_synchronizer_top.v` |
| 26 | v3 — add AXI-Lite registers and AXI4 sample DMA to top | update top |
| 27 | Python golden model comparison — feed same IQ data to C model, Python model, and RTL simulation; compare all outputs | `tb/ofdm_sync_golden_compare_tb.sv` |

### Hardening (Steps 28–30)

| Step | Action | Deliverable |
|------|--------|-------------|
| 28 | Randomized regression — randomized IQ offsets, noise levels, CFO magnitudes | regression script in `scripts/` |
| 29 | Synthesis and resource review — Vivado Out-of-Context synthesis, check DSP/BRAM/LUT usage | `docs/step29_synthesis_report.md` |
| 30 | FPGA/ILA bring-up plan — define ILA probe list, UART status output, bring-up procedure | `docs/step30_fpga_bringup_plan.md` |

---

## 9. Fixed-Point Decisions Required in Step 3

### Signal widths

| Decision | Description |
|----------|-------------|
| Input IQ width | ADC bit depth (likely 12 or 16 bits). Determines all downstream widths. |
| Correlation multiplier width | Width of each complex MAC operand in `cp_autocorr_core.v`. Affects DSP block usage. |
| Accumulator width | Output width of the CP_LEN=32-tap accumulator. Must not overflow: `input_width + ceil(log2(CP_LEN))`. |
| Timing metric width | `2*|autocorr| - power`: must represent the difference without wrap. |
| Phase width | Output of atan2/CORDIC. Determines fractional CFO precision. Must cover range ±π without wrapping. |
| CORDIC output width | Number of CORDIC iterations and output precision. Determines atan2 accuracy. |
| NCO phase accumulator width | Determines frequency resolution. Common choice: 32-bit accumulator → ~0.23 Hz resolution at 1 MHz sample rate. |

### Implementation decisions

| Decision | Options |
|----------|---------|
| Sine/cosine implementation | LUT (small ROM, limited precision) vs CORDIC (no extra memory, iterative). |
| Complex rotator output scaling | After multiply: truncate, round, or saturate to input width? |
| FFT input/output width | Typically same as input IQ or slightly wider to absorb FFT gain. |
| Meyr correlation accumulator width | Must hold sum of NSC=256 complex products without overflow. |
| CFO estimate representation | Signed fixed-point: fractional CFO as Q-format fraction; integer CFO as signed integer in subcarrier units. |
| Saturation vs wrap | Everywhere overflows are possible (accumulators, rotator output, FFT bins). Choose saturation at AXI-Stream boundaries. |

### Interface decisions

| Decision | Description |
|----------|-------------|
| AXI-Stream input format | Interleaved I/Q or separate channels? Word width per sample? TUSER/TLAST semantics for frame boundaries. |
| AXI-Stream output format | Timing offset as integer; fractional + integer CFO as fixed-point. Delivered via AXI-Lite status registers or AXI-Stream sideband? |
| AXI-Lite register map | Which parameters are programmable (threshold, wndLen, NSC, CP_LEN)? Which are read-only status (offset, CFO, done, error)? |
| Sample buffer interface | Does the top take a streaming input or a DMA-loaded SRAM? The C code uses a float array; the RTL needs a defined memory interface. |
| Clock domains | Single clock assumed for first implementation. CDC analysis needed if AXI-Lite and datapath run at different rates. |

---

## 10. Recommended Step 3

```text
Step 3 — Fixed-Point and Interface Specification for Full OFDM Synchronizer RTL
```

Step 3 should produce `docs/step3_fixedpoint_spec.md` covering:

- Input IQ bit width and format (based on actual hardware: PlutoSDR ADC is 12-bit)
- All internal widths derived from the input width
- CORDIC vs LUT decision for atan2 and NCO
- NCO phase accumulator width
- FFT width (input, output, twiddle)
- AXI-Stream input/output interface definition
- AXI-Lite register map (address map, reset values, R/W permissions)
- Saturation policy

Do not implement RTL in Step 3.

---

## 11. Files Inspected

| File | Purpose |
|------|---------|
| `ref/receiver.c` | Primary C reference: `synchronization()` and all sub-functions |
| `/home/zealatan/PY_OFDM/pluto.h` | Macro definitions: NSC, CP_LEN, NUM_*, function declarations |
| `md_files/02_full_sync_scope_from_receiver_c_prompt.md` | Step 2 task instructions |
| `docs/rtl_verification_agent_benchmark.md` | DUT layer history and check counts |
| Existing RTL files (Step 1 audit) | `axis_complex_mult.v`, `axi_lite_regfile.v`, `simple_dma_add_ctrl.v`, `axi_mem_model.sv` |

---

## 12. Files Changed

| File | Action |
|------|--------|
| `docs/step2_full_sync_scope_from_receiver_c.md` | Created (this file) |
| `ai_context/current_status.md` | Created |
