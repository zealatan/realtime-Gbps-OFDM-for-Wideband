# Step 30 — Meyr-Based Integer CFO / PSS-SSS Algorithm-to-RTL Architecture

> **Note:** An earlier preliminary architecture document exists at
> `docs/step30_integer_cfo_pss_sss_architecture.md`. This document supersedes it
> with the Meyr-specific formulation verified against `ref/receiver.c`.

---

## Objective

Define the algorithm, placement, product formulation, correlation method, block architecture,
RTL interface, fixed-point strategy, and verification roadmap for Meyr-based integer CFO
estimation using PSS/SSS frequency-domain products.

This document is aligned with the actual C reference implementation in `ref/receiver.c`
(`carrierFreqOffsetEstMeyr`, `fft_correlation_Meyr`).

This step is documentation only; no RTL is created.

---

## Current Validated Receiver State

Step 29I has passed on ZCU102 (board regression via UART):

```
Case A: negative short-quiet detector stress : PASS
  STATUS=0x0000019A, INPUT_COUNT=116, OUTPUT_COUNT=0
  FRAME_ERROR=1 (expected — no frame in stimulus)

Case B: positive long-quiet frame detection : PASS
  STATUS=0x0000009A, INPUT_COUNT=632, OUTPUT_COUNT=288
  FRAME_ERROR=0, handshake_seen=1
```

The on-board validated data path is:

```
PS host (AXI-Lite)
  → input BRAM preload
  → AXI-Stream source FSM
  → frac_cfo_frame_corrector_top
      ├── iq_frame_buffer         (sample storage, 4096 × 32-bit)
      ├── frame_detector          (energy-window detection)
      ├── timing_sync_top         (CP autocorrelation, peak lag)
      ├── frac_cfo_estimator      (CORDIC atan2 of autocorr peak)
      └── frac_cfo_corrector_top  (NCO + complex_rotator)
  → corrected AXI-Stream output: NSC + CP_LEN = 288 samples
  → output BRAM
  → PS readback
```

The corrected 288-sample output is the entry point for the integer CFO path.

---

## Integer CFO Problem Definition

In OFDM, total carrier frequency offset normalised to the subcarrier spacing decomposes as:

```
ε_total = ε_int + ε_frac
```

| Component | Definition | Magnitude | Effect after FFT |
|-----------|-----------|-----------|-----------------|
| ε_frac | fractional subcarrier offset | \|ε_frac\| < 0.5 | ICI; phase tilt; rotation visible to CP autocorrelation |
| ε_int | integer subcarrier offset | integer bins | Circular shift of entire subcarrier mapping; invisible to CP autocorrelation |

After fractional CFO correction the received FFT output is:

```
Y[k] = X[k − ε_int] · H[k − ε_int] + N[k]
```

The integer shift ε_int must be recovered by comparing received FFT bins against a known
synchronisation structure that has the same integer shift applied.

---

## Relationship to Fractional CFO

| Property | Fractional CFO | Integer CFO |
|----------|---------------|-------------|
| Effect in time domain | Phase ramp across samples; grows with symbol index | Zero (CP metric is blind to integer shifts) |
| Effect in freq domain | ICI; phase rotation per bin | Circular subcarrier permutation |
| Detection method | CP autocorrelation → CORDIC atan2 | FFT + PSS/SSS product cross-correlation |
| RTL location | Before FFT (time-domain correction) | After FFT (frequency-domain estimation) |
| Current RTL status | Implemented and board-verified | **Planned — this step onwards** |

The two corrections are orthogonal and sequential:
1. Correct fractional CFO first (time domain) — **done**.
2. Estimate and correct integer CFO next (frequency domain) — **Step 31+**.

---

## C-Reference Meyr Algorithm Summary

The C reference at `ref/receiver.c` contains the authoritative implementation.

### Functions verified in `ref/receiver.c`

| Function | Lines | Purpose |
|----------|-------|---------|
| `carrierFreqOffsetEstMeyr()` | 498–541 | Top-level integer CFO estimator |
| `fft_correlation_Meyr()` | 458–490 | FFT-based cross-correlation |
| `find_peak_index()` | 543–554 | Magnitude-squared argmax |

### Step-by-step C reference flow

**Step 1 — Extract and FFT the received PSS symbol**

```c
// PSS symbol: skip slotStartIndex + CP_LEN samples
generate_complex_symbol(rxI + slotStartIndex + CP_LEN, rxQ + slotStartIndex + CP_LEN,
                        rxCmplx_PSS, NSC);
fft_without_rearrange(rxCmplx_PSS, signalPSSfftI, signalPSSfftQ, NSC, plan_fft);
```

PSS symbol starts at byte offset `slotStartIndex + CP_LEN` (= slotStart + 32 in default config).
Length = NSC = 256 samples.

**Step 2 — Extract and FFT the received SSS symbol**

```c
// SSS symbol: skip 2*CP_LEN + NSC past slotStartIndex
generate_complex_symbol(rxI + slotStartIndex + 2*CP_LEN + NSC, ..., rxCmplx_SSS, NSC);
fft_without_rearrange(rxCmplx_SSS, signalSSSfftI, signalSSSfftQ, NSC, plan_fft);
```

SSS symbol starts at `slotStartIndex + 2·CP_LEN + NSC` (= slotStart + 320 in default config).
Length = NSC = 256 samples.

**Step 3 — Form received product term1 (verified from C code)**

```c
for (int j = 0; j < NSC; j++) {
    crossCorrTerm1I[j] =  signalPSSfftI[j]*signalSSSfftI[j]
                        + signalPSSfftQ[j]*signalSSSfftQ[j];
    crossCorrTerm1Q[j] = -signalPSSfftI[j]*signalSSSfftQ[j]
                        + signalPSSfftQ[j]*signalSSSfftI[j];
}
```

Mathematical form (verified):

```
term1[j] = PSS_FFT[j] · conj(SSS_FFT[j])
```

> **Note on conjugation convention:** The high-level description in this step's planning
> listed `term1 = conj(PSS_FFT) · SSS_FFT`. That is the complex conjugate of the actual C
> code. Both formulations produce the **same magnitude-squared cross-correlation peak** and
> the **same intCFO estimate**. The RTL implementation should match the C code exactly:
> `term1 = PSS_FFT · conj(SSS_FFT)`.

**Step 4 — Form reference product term2 (verified from C code)**

```c
for (int j = 0; j < NSC; j++) {
    crossCorrTerm2I[j] =  mUI[j+CP_LEN]*goldUI[j+CP_LEN]
                        + mUQ[j+CP_LEN]*goldUQ[j+CP_LEN];
    crossCorrTerm2Q[j] = -mUI[j+CP_LEN]*goldUQ[j+CP_LEN]
                        + mUQ[j+CP_LEN]*goldUI[j+CP_LEN];
}
```

Mathematical form (verified):

```
term2[j] = mU[j + CP_LEN] · conj(goldU[j + CP_LEN])
```

`mU` and `goldU` are the known PSS and SSS (gold-sequence) reference vectors. They are
passed in as pre-generated float arrays from the signal-processing state structure.
For the RTL, these will be preloaded into ROM or BRAM from offline-generated fixed-point tables.

**Step 5 — Compute Meyr cross-correlation**

```c
fft_correlation_Meyr(crossCorrTerm2I, crossCorrTerm2Q,
                     crossCorrTerm1I, crossCorrTerm1Q,
                     crossCorrOut2I, crossCorrOut2Q,
                     plan_fft_corr, plan_ifft_corr);
```

Inside `fft_correlation_Meyr` (verified):

```c
fftwf_execute_dft(plan_forward, inCmplx1, inFreq1);   // FFT(term2)
fftwf_execute_dft(plan_forward, inCmplx2, inFreq2);   // FFT(term1)
for (int i = 0; i < NSC * 2; i++)
    outFreq[i] = conjf(inFreq1[i]) * inFreq2[i];      // conj(FFT(term2)) · FFT(term1)
fftwf_execute_dft(plan_backward, outFreq, outCmplx);  // IFFT
```

The IFFT of `conj(FFT(term2)) · FFT(term1)` is the **circular cross-correlation**:

```
R[n] = Σ_k  conj(term2[k]) · term1[k + n]   (i.e. term2 ⋆ term1)
```

The output array is then rearranged into 511 lags (±255) with the rearrangement code
placing lag 0 at output index `NSC − 1 = 255`.

**Step 6 — Find peak and compute intCFO**

```c
int crossCorrLen   = 2 * NSC - 1;   // = 511
int peakIndexMeyr  = find_peak_index(crossCorrOut2I, crossCorrOut2Q, crossCorrLen, &peakValue);
int carrierFreqOffsetInt = peakIndexMeyr - (NSC - 1);  // = peakIndexMeyr - 255
```

`find_peak_index` computes `|R[i]|² = R_I[i]² + R_Q[i]²` and returns the argmax index.

**Summary of the complete lag mapping:**

| Peak index | Integer CFO |
|-----------|-------------|
| 0 | −255 |
| 254 | −1 |
| **255** | **0** (no integer CFO) |
| 256 | +1 |
| 510 | +255 |

---

## PSS/SSS Representation Choices

### Option 1 — Frequency-domain PSS/SSS references

Store references `mU` and `goldU` as frequency-domain complex vectors (post-FFT, length NSC).
After FFT of received PSS and SSS, form the Meyr product terms and correlate.

**Pros:**
- Direct match with C reference algorithm.
- Integer CFO is a circular bin-index shift; comparison is a simple index offset.
- term2 (= mU · conj(goldU)) can be precomputed offline and stored as a 256-entry ROM.
- Correlation output maps cleanly to the existing `peak_detector.v`.

**Cons:**
- Requires NSC-point FFT for each received symbol (PSS and SSS) before product generation.
- FFT frontend is a separate implementation concern.

### Option 2 — Time-domain IFFT'ed PSS/SSS references

Store IFFT'd PSS/SSS as time-domain sequences for matched-filter correlation.

**Cons for integer CFO:**
- Integer CFO in time domain appears as a complex phase ramp, not a simple shift.
- Does not match the C reference Meyr algorithm.
- Searching over candidate integer offsets requires multiple derotation passes.
- More complex RTL and testbench.

### Recommended Representation for This Project

**Use frequency-domain PSS/SSS representation. This is the only option that directly
matches the C reference `carrierFreqOffsetEstMeyr`.**

Time-domain IFFT'd sequences may be retained for future coarse frame-timing detection
experiments but are not the integer CFO path.

---

## Meyr Product Generation

The two product vectors fed into the correlation are:

```
term1[j] = PSS_FFT[j] · conj(SSS_FFT[j])     j = 0 .. NSC-1
           (received signal product — computed from board samples)

term2[j] = mU[j+CP_LEN] · conj(goldU[j+CP_LEN])   j = 0 .. NSC-1
           (known reference product — precomputed, stored in ROM/BRAM)
```

**Key implementation note:** term2 is **entirely known offline** because `mU` and `goldU`
are fixed reference sequences. In RTL, term2 does not need to be computed dynamically.
It can be preloaded as a 256-entry complex ROM at synthesis time or loaded into BRAM at
initialisation. This simplifies Step 31 significantly: only term1 is "live" data.

**Complex multiply formula for term1[j] = PSS_FFT[j] · conj(SSS_FFT[j]):**

```
term1_I[j] = PSS_I[j] · SSS_I[j] + PSS_Q[j] · SSS_Q[j]
term1_Q[j] = PSS_Q[j] · SSS_I[j] - PSS_I[j] · SSS_Q[j]
```

This is the same operation as `complex_mult_iq.v` with `CONJ_B=1`.

---

## Meyr Correlation and Peak Mapping

### Correlation definition

```
R[n] = Σ_{j=0}^{NSC-1}  conj(term2[j]) · term1[j + n]
```

for lag `n = -(NSC-1) .. +(NSC-1)`, total 2·NSC−1 = 511 lags.

Score:

```
score[n] = |R[n]|² = R_I[n]² + R_Q[n]²
```

Peak:

```
peakIndexMeyr = argmax_n score[n]
                (n mapped to output index 0..510; n=0 is at index NSC-1=255)

intCFO = peakIndexMeyr − (NSC − 1)
       = peakIndexMeyr − 255   (for NSC=256)
```

### C-reference FFT-based correlation (for RTL Step 32+)

The C reference implements the cross-correlation via FFT convolution on a 2·NSC = 512-point
zero-padded buffer for efficiency. The mathematical result is identical to direct summation.
For Step 31 RTL, the **direct summation** is recommended (simpler, verifiable without FFT IP).
The FFT-based correlation can replace it later in a Step 32 optimisation.

---

## Proposed Block-Level Architecture

### Full pipeline (Step 35+ integration target)

```
[Validated corrected time-domain frame: 288 samples today]
        │
        │  Note: must be extended to ≥576 samples for SSS (Step 34/35)
        │
        ▼
┌─────────────────────────┐
│  pss_sss_symbol_extractor│
│  PSS: samples CP_LEN..   │  → rxCmplx_PSS[j], j=0..255
│  SSS: samples 2·CP_LEN+  │  → rxCmplx_SSS[j]
│        NSC..2·CP_LEN+2NSC│
└────────────┬────────────┘
             │
     ┌───────┴────────┐
     ▼                ▼
┌──────────┐    ┌──────────┐
│ pss_fft  │    │ sss_fft  │  256-pt FFT (behavioral model first, Xilinx IP later)
│ wrapper  │    │ wrapper  │  ← FFT IP insertion point
└────┬─────┘    └────┬─────┘
     │  PSS_FFT[j]   │  SSS_FFT[j]
     └───────┬────────┘
             ▼
┌───────────────────────────┐
│   term1_generator         │
│   term1 = PSS·conj(SSS)   │  256 complex multiplies (reuse complex_mult_iq.v, CONJ_B=1)
└────────────┬──────────────┘
             │  term1[j]
             ▼
┌───────────────────────────┐   ┌──────────────────────────┐
│   meyr_corr_core          │◄──│  term2_rom                │
│   R[n] = Σ conj(t2)·t1   │   │  precomputed mU·conj(goldU│
│   n = 0..510 (511 lags)   │   │  256 × 32-bit complex ROM │
└────────────┬──────────────┘   └──────────────────────────┘
             │  score[n] = |R[n]|², n=0..510
             ▼
┌───────────────────────────┐
│   peak_detector.v (reuse) │  METRIC_WIDTH=64, INDEX_WIDTH=9 (handles 511 candidates)
└────────────┬──────────────┘
             │  peak_index (0..510)
             ▼
┌───────────────────────────┐
│   intCFO decode           │  intCFO = peak_index − 255
│   int_cfo_est_reg         │  AXI-Lite readable; done/error outputs
└───────────────────────────┘
```

### Step 31 initial path (no FFT, no symbol extraction)

```
synthetic term1[j] (j=0..NSC-1)    ← testbench injects known shifted version of term2
          +
term2_rom[j] (pre-generated)
          │
          ▼
  meyr_corr_core.v
          │
  peak_detector.v (reuse)
          │
  intCFO = peak_index − 255
```

No FFT, no PSS/SSS extraction, no board wrappers changed in Step 31.

---

## Proposed RTL Interface

The following interface is a documented proposal for Step 31 implementation.
No RTL file is created in Step 30.

```verilog
module meyr_integer_cfo_core #(
    parameter NSC        = 256,   // FFT size / number of subcarriers
    parameter IQ_WIDTH   = 16,    // signed per I and Q channel
    parameter PROD_WIDTH = 32,    // term1/term2 product width (output of complex mult)
    parameter ACC_WIDTH  = 56,    // complex accumulator for R[n]
    parameter SCORE_WIDTH = 64    // |R[n]|² comparison width fed to peak_detector
)(
    input  wire                          aclk,
    input  wire                          aresetn,
    input  wire                          start,         // 1-clock pulse, begins processing

    // Streamed term1 input: one entry per clock, j=0..NSC-1, valid during processing
    input  wire                          term_valid,
    input  wire [$clog2(NSC)-1:0]        term_index,   // j
    input  wire signed [PROD_WIDTH-1:0]  term1_i,      // Re(PSS_FFT[j]·conj(SSS_FFT[j]))
    input  wire signed [PROD_WIDTH-1:0]  term1_q,      // Im(PSS_FFT[j]·conj(SSS_FFT[j]))

    // term2 is sourced internally from ROM or preloaded register array

    output wire                          busy,
    output wire                          done,          // 1-clock pulse
    output wire signed [15:0]            int_cfo,       // = peak_index − (NSC−1), signed
    output wire [$clog2(2*NSC-1)-1:0]    peak_index,   // raw argmax index 0..511
    output wire [SCORE_WIDTH-1:0]        peak_score,   // winning magnitude-squared score
    output wire                          error          // sticky, cleared by aresetn
);
```

**Port notes consistent with project conventions:**
- `IQ_WIDTH=16`, `tdata[15:0]=I`, `tdata[31:16]=Q` (project-wide standard).
- `done` is a 1-clock pulse, consistent with all existing RTL modules.
- `error` is sticky, cleared only by `aresetn`, consistent with existing convention.
- term2 contents (= precomputed `mU[j+CP_LEN] · conj(goldU[j+CP_LEN])`) are stored in
  an internal ROM parameter array or preloaded BRAM — not an external streaming port.
- The `$clog2(2*NSC-1)` index width evaluates to 9 for NSC=256 (handles 0..510), which
  matches the `INDEX_WIDTH=9` already in `peak_detector.v`.

---

## Direct-Correlation First Strategy

The C reference computes the cross-correlation via FFT convolution (512-point FFT/IFFT)
for computational efficiency. For the initial Step 31 RTL:

**Use direct lag-by-lag summation:**

For each lag n ∈ {0, 1, ..., 510}:
```
R_I[n] = Σ_{j=0}^{255}  [term2_I[j] · term1_I[j+n] + term2_Q[j] · term1_Q[j+n]]
R_Q[n] = Σ_{j=0}^{255}  [term2_I[j] · term1_Q[j+n] − term2_Q[j] · term1_I[j+n]]
score[n] = R_I[n]² + R_Q[n]²
```

(Indices j+n are taken modulo NSC=256 for the circular wrap case, or treated as linear with
zero-padding — depending on whether circular or linear correlation is chosen. Linear correlation
matching the C reference: term1 is zero-padded to 512 before correlation.)

**Advantages of direct correlation in Step 31:**
- Mathematically identical peak result to the reference.
- No FFT dependency.
- Fully deterministic; easy to verify with a testbench golden model.
- Hardware: can be implemented as a time-multiplexed single complex-multiply-accumulate engine
  that iterates over 511 lags × 256 terms = 130,816 MAC operations.

**Latency estimate (direct approach at 100 MHz):**
- 511 lags × (256 MAC clocks + overhead) ≈ 130,000–140,000 clocks ≈ 1.3–1.4 ms.
- Acceptable for a once-per-frame synchronisation operation.

---

## Future FFT-Based Acceleration Path

When FFT-based correlation is introduced (Step 32+):

```
term2[j]  →  zero-pad to 512  →  FFT_512
term1[j]  →  zero-pad to 512  →  FFT_512
                                        ↓
                   conj(FFT(term2)) · FFT(term1)
                                        ↓
                            IFFT_512 → rearrange → R[n] (511 lags)
```

**Insertion point:** the `fft256_wrapper` and a companion `fft512_wrapper` (or reconfigured
single instance) insert before the product and correlation stages. All downstream logic
(score computation, peak_detector, intCFO decode) remains unchanged.

**Latency estimate (FFT-based at 100 MHz):**
- Two 256-pt FFTs + one 512-pt IFFT ≈ 3,000–5,000 clocks (Xilinx FFT IP pipeline).
- ~100× faster than direct correlation; useful for tighter frame timing budgets.

---

## Fixed-Point and Accumulator Considerations

| Stage | Width | Notes |
|-------|-------|-------|
| Input IQ samples (corrected frame) | 16-bit signed (Q1.15) | Project-wide convention |
| FFT output Y[k] | 16-bit IQ | Block floating point or saturating 16-bit |
| term1[j] = PSS_FFT · conj(SSS_FFT) | 32-bit IQ | 16×16 complex multiply |
| term2[j] from ROM | 16-bit IQ (Q1.15 normalized) | Precomputed, can be 16-bit |
| Correlation product conj(t2)·t1 | 32-bit intermediate | 16×16 in term2 × 32 in term1 → guard with 48-bit |
| Accumulator R_I[n], R_Q[n] | **56-bit signed** | Sum of 256 × ~32-bit products; 32+8=40 bits minimum; 56 provides clear headroom |
| Score |R[n]|² | 112-bit before truncation | Two 56² products; right-shift by 32 → 80-bit; truncate to 64-bit for peak_detector |
| Peak detector input | 64-bit unsigned | Matches `METRIC_WIDTH=64` in `peak_detector.v` |
| int_cfo output | 16-bit signed | Range −255..+255; fits in 9-bit signed; use 16-bit for future expansion |

**Design rules:**
1. Never truncate before accumulation completes.
2. Score truncation (right-shift) is applied identically to all 511 lag candidates,
   preserving the argmax — safe regardless of exact shift amount.
3. If term2 ROM entries are limited to 16-bit, the correlation product is 16×32=48-bit
   before accumulation; 56-bit accumulator is still sufficient.
4. Magnitude-squared overflow: for 56-bit accumulator, the maximum value is ~2^55.
   Squaring gives ~2^110. Shift right by 46 before storing in 64-bit score register.
5. The existing `peak_detector.v` uses `METRIC_WIDTH=64, INDEX_WIDTH=9` and handles
   511 candidates — no modification needed for Step 31 or full Meyr.

---

## Verification Strategy

### Step 31 deterministic test cases

All tests inject synthetic term1 (shifted copy of term2) directly into the core,
bypassing FFT. The testbench computes a golden model score independently.

| Test | term1 setup | Expected peak_index | Expected int_cfo |
|------|-------------|--------------------|----|
| T1: Zero CFO | term1 = term2 | 255 | 0 |
| T2: +1 shift | term1 = term2 circularly shifted by +1 bin | 256 | +1 |
| T3: −1 shift | shifted by −1 | 254 | −1 |
| T4: +4 shift | shifted by +4 | 259 | +4 |
| T5: −4 shift | shifted by −4 | 251 | −4 |
| T6: +2, −2 | two separate runs | 257, 253 | +2, −2 |
| T7: +3, −3 | two separate runs | 258, 252 | +3, −3 |
| T8: Noise only | term1 = random | any index | (verify no crash; score low) |
| T9: Tie-break | two equal peaks at indices 254 and 256 | 254 | −1 (lowest index wins) |
| T10: Reset/restart | run T1, assert aresetn, run T2 | 256 | +1 |
| T11: Done pulse | single clock wide | — | — |
| T12: Busy protocol | busy asserts on start, deasserts with done | — | — |

**Tie-breaking policy (document and implement consistently):**
`peak_detector.v` already uses strict `>` comparison (first occurrence wins on ties).
The same policy applies here: the lower-index candidate is reported.

---

## Recommended Step 31 Target

**Step 31 — Meyr Correlation Core RTL and Deterministic Testbench**

Implement:

| File | Description |
|------|-------------|
| `rtl/meyr_integer_cfo_core.v` | Direct-lag correlation: term1 + term2 ROM → R[n] → score[n]; instantiates `peak_detector.v` |
| `tb/meyr_integer_cfo_core_tb.sv` | 12 test groups (T1–T12 above); golden model in SV |
| `scripts/run_meyr_integer_cfo_core_sim.sh` | Vivado xsim compile + run script |

**Acceptance criteria:**
- T1–T7 pass: peak_index and int_cfo exactly match golden model.
- T10: reset then re-run gives correct result.
- T11/T12: timing protocol matches project convention (done = 1 clock, busy deasserts with done).
- No FFT IP, no Xilinx IP, no board wrapper changes.
- Reuses `peak_detector.v` unmodified.
- Uses 56-bit accumulator, 64-bit score.

---

## Future Integration Notes

1. **Frame buffer extension for SSS:**
   The current corrected output is 288 samples (= NSC + CP_LEN = 1 symbol). The SSS symbol
   starts at `slotStartIndex + 2·CP_LEN + NSC` (= +320 relative to slot start).
   The SSS symbol ends at +576 relative to slot start. Therefore the corrected frame output
   must be extended from 288 to at least 576 samples before Step 35 integration.
   The `iq_frame_buffer` supports 4096 samples; extending the playback count is a parameter
   change in `frac_cfo_frame_corrector_top.v` (or the AXI-Lite config register).

2. **term2 ROM generation:**
   `mU` and `goldU` are fixed reference sequences that depend on the system configuration
   (PSS/SSS identity). For Step 31, a single precomputed example pair can be used.
   The offline generation script can be a Python script that outputs a Verilog `$readmemh`
   file or a `localparam` array.

3. **FFT insertion (Step 34):**
   Only `pss_fft_wrapper.v` and `sss_fft_wrapper.v` (or a shared `fft256_wrapper.v` run twice)
   need to be inserted. The `term1_generator`, `meyr_integer_cfo_core`, and `peak_detector`
   are unaffected.

4. **Integer CFO correction (Step 33 or later):**
   After estimating ε_int, correction is applied by rotating all subcarriers by −ε_int
   bins. In the time domain this is an NCO correction with step word:
   ```
   step_word = ε_int × 2^32 / NSC = ε_int × 16,777,216   (for NSC=256)
   ```
   The existing `nco_phase_gen.v` + `complex_rotator.v` can be reused for this.

5. **Existing reuse summary:**
   - `peak_detector.v` (METRIC_WIDTH=64, INDEX_WIDTH=9): reused unmodified.
   - `complex_mult_iq.v` (CONJ_B=1): reusable for term1 product generation.
   - `iq_frame_buffer.v`: reused unmodified (extend playback count via parameter).
   - `nco_phase_gen.v`, `complex_rotator.v`: reused for integer CFO correction.

---

## Conclusion

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Algorithm | Meyr PSS/SSS product cross-correlation | Matches C reference `carrierFreqOffsetEstMeyr` |
| Received product | `term1 = PSS_FFT · conj(SSS_FFT)` | Verified exact C code formula |
| Reference product | `term2 = mU · conj(goldU)` precomputed ROM | Verified exact C code formula; static — compute once |
| Correlation | `R[n] = Σ conj(term2[j]) · term1[j+n]` | Standard cross-correlation; matches C `fft_correlation_Meyr` |
| Peak decode | `intCFO = peak_index − 255` | Verified from C: `(peakIndexMeyr) − (NSC−1)` |
| Search range | 511 lags (−255 to +255) | Full range from C; `peak_detector.v` INDEX_WIDTH=9 covers it |
| Representation | Frequency domain | Natural for bin-shift estimation; matches C reference |
| Step 31 target | Direct-lag Meyr core, synthetic inputs, no FFT | Isolates core logic; deterministic testbench; no IP dependency |
| FFT strategy | Behavioral model first, Xilinx FFT IP later | Phase-1 design stance; insertion point documented |
| Accumulators | 56-bit R_I/R_Q, 64-bit score | Safe headroom; reuses `peak_detector.v` METRIC_WIDTH=64 |

**Recommended next step:**

> **Step 31 — implement `rtl/meyr_integer_cfo_core.v` with 56-bit accumulators,
> precomputed term2 ROM, peak_detector reuse, and a deterministic 12-test SV testbench.
> No FFT IP required.**
