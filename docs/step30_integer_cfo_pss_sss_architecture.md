# Step 30 — Integer CFO / PSS-SSS Algorithm-to-RTL Architecture

## Objective

Define the algorithm, placement, representation, block architecture, RTL interface, fixed-point
strategy, and verification roadmap for integer CFO estimation using PSS/SSS.
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

The validated on-board data path is:

```
PS host (AXI-Lite)
  → input BRAM preload
  → AXI-Stream source FSM
  → frac_cfo_frame_corrector_top
      ├── iq_frame_buffer       (sample storage)
      ├── frame_detector        (energy-window detection)
      ├── timing_sync_top       (CP autocorrelation, lag=peak timing offset)
      ├── frac_cfo_estimator    (CORDIC atan2 of lag-peak autocorr)
      └── frac_cfo_corrector_top (NCO + complex_rotator)
  → corrected AXI-Stream output (288 samples: CP + one OFDM symbol)
  → output BRAM
  → PS readback
```

The corrected 288-sample AXI-Stream output is the starting point for integer CFO estimation.

---

## Integer CFO Problem Definition

In OFDM, carrier frequency offset (CFO) shifts all subcarriers by the same fractional amount.
CFO can be decomposed as:

```
Normalized CFO = ε_int + ε_frac
```

where:

- **ε_frac** (fractional part, |ε_frac| < 0.5 subcarrier spacings):
  Causes inter-carrier interference and a phase ramp across the OFDM symbol.
  Already estimated and corrected by the CP autocorrelation path (Steps 9–18).

- **ε_int** (integer part, integer number of subcarrier spacings):
  Causes a circular shift of the received subcarrier mapping in the FFT output.
  Cannot be detected by CP autocorrelation — it is invisible to time-domain correlation.
  Must be estimated by comparing received FFT bins against a known frequency-domain reference.

After fractional CFO correction, the received FFT output Y[k] satisfies:

```
Y[k] = X[k − ε_int] · H[k − ε_int] + N[k]
```

where X[k] is the transmitted spectrum, H[k] is the channel, N[k] is noise, and
ε_int is the integer subcarrier shift. The goal of integer CFO estimation is to find ε_int.

**Design decision**: integer CFO estimation must occur **after** FFT of the received samples.
The FFT transforms the subcarrier shift into a simple bin-index offset, making it tractable.

---

## Relationship to Fractional CFO

| Property               | Fractional CFO                         | Integer CFO                                     |
|------------------------|----------------------------------------|-------------------------------------------------|
| Magnitude              | |ε| < 0.5 subcarrier                  | ε = integer subcarrier count                    |
| Effect in time domain  | Phase ramp across symbol               | Invisible (no CP metric change)                 |
| Effect in freq domain  | ICI, phase tilt across bins            | Circular shift of entire spectrum               |
| Detection method       | CP autocorrelation → CORDIC atan2      | FFT bin comparison with known reference         |
| Input needed           | Time-domain received samples           | Frequency-domain FFT output of sync symbol      |
| RTL location           | Before FFT (time-domain correction)    | After FFT (frequency-domain estimation)         |
| Current RTL status     | Implemented and board-verified         | **Planned — this step**                         |

The two corrections are orthogonal and sequential:
1. Correct fractional CFO first (time domain) — **done**.
2. Estimate and correct integer CFO next (frequency domain) — **Step 31+**.

---

## PSS/SSS Representation Choices

### Option 1 — Frequency-Domain PSS/SSS Reference

Store the PSS and SSS reference sequences as frequency-domain complex vectors of length NSC = 256.
After FFT of the received sync symbol, compare shifted received bins against the stored reference.

**Pros:**
- Direct: integer CFO appears as a bin-index shift; searching over shift candidates is a simple
  address offset in the correlation loop.
- RTL-natural: all arithmetic operates on fixed-size register arrays.
- No time-domain complications (phase ramps, multi-hypothesis derotation).
- Matches the C reference algorithm (`carrierFreqOffsetEstMeyr` uses FFT'd sequences throughout).

**Cons:**
- Requires FFT of the received symbol before correlation.
- A stored NSC=256 complex vector (16-bit I + 16-bit Q) = 8 KB per reference sequence.

### Option 2 — Time-Domain IFFT'ed PSS/SSS Reference

Store pre-computed IFFT'd PSS/SSS sequences as time-domain samples.
Use matched-filter time-domain correlation (cross-correlation without FFT).

**Pros:**
- No FFT required for the correlation itself.
- Useful for initial coarse frame timing (future enhancement).

**Cons:**
- Integer CFO is **not** a simple bin shift in the time domain; it appears as a complex phase
  ramp multiplied onto the entire symbol.
- To search over candidate integer CFO values, each candidate requires a separate derotation
  of the received samples before correlation — expensive and less natural.
- Not used in the C reference implementation for integer CFO estimation.

### Recommended Representation for This Project

**Use frequency-domain PSS reference for integer CFO estimation.**

Rationale:
- The C reference (`carrierFreqOffsetEstMeyr`) operates entirely in the frequency domain.
- A bin-shift search is a simple address offset, directly mappable to RTL.
- The existing `peak_detector.v` (INDEX_WIDTH=9, handles up to 511 candidates) already covers
  the full Meyr search range of NSC×2−1 = 511 lags.
- Time-domain PSS may be kept as a future option for detection, but is not the integer CFO path.

---

## Candidate Integer CFO Algorithm

### Simple Single-Symbol Frequency-Domain Candidate Search (Step 31 Target)

This is a simplified first algorithm that uses only the PSS symbol. It is the recommended
first RTL implementation target.

**Inputs:**
```
Y[k]       = FFT output of the fractional-CFO-corrected PSS OFDM symbol, k = 0 .. NSC-1
PSS_REF[k] = known frequency-domain PSS reference, k = 0 .. NSC-1 (preloaded from ROM/RAM)
m          = candidate integer CFO shift, m ∈ {−M, ..., +M}
```

**Per-candidate metric:**
```
metric[m] = Σ_{k ∈ active_PSS_bins} conj(PSS_REF[k]) · Y[(k + m) mod NSC]
```

**Score:**
```
score[m] = |metric[m]|² = metric[m]_I² + metric[m]_Q²
```

**Decision:**
```
ε̂_int = argmax_m score[m]
```

**Search range for first RTL skeleton:** M = 4 (9 candidates: −4 to +4).
The range can be extended later; `peak_detector.v` handles up to 511 candidates.

**Active PSS bins:** In the reference system (NSC=256), the PSS occupies a contiguous block of
127 active subcarriers centered in the spectrum (indices 1..64 and 193..255 in natural FFT order,
with DC=0 and guard bands at the edges). The exact bin mapping should be confirmed from
`ref/receiver.c` and `pluto.h` when implementing Step 31.

### Full Meyr Algorithm (C Reference — Future Step 32+)

The `carrierFreqOffsetEstMeyr` function in `ref/receiver.c` implements the full Meyr method,
which uses **both** PSS and SSS for higher robustness:

**Step 1:** FFT the received fractional-CFO-corrected PSS symbol → Y_PSS[k]

**Step 2:** FFT the received fractional-CFO-corrected SSS symbol → Y_SSS[k]

**Step 3:** Form received cross-product:
```
T1[k] = Y_PSS[k] · conj(Y_SSS[k])
```

**Step 4:** Form known reference cross-product:
```
T2[k] = mU[k] · conj(goldU[k])
```
where `mU` and `goldU` are the known PSS and SSS reference sequences at the frame start.

**Step 5:** Compute frequency-domain circular cross-correlation via double FFT:
```
R[n] = IFFT( conj(FFT(T2)) · FFT(T1) )
       (both FFTs are 2×NSC = 512-point, zero-padded)
```

**Step 6:** Find peak index and decode:
```
ε̂_int = peak_index(R) − (NSC − 1)
         (center index = NSC−1 = 255 → zero integer CFO)
```

The full Meyr method:
- Is robust against unknown PSS/SSS identity (cell ID unknown at the receiver).
- Cancels the channel phase since T1 = Y_PSS × conj(Y_SSS) and H[k] cancels out.
- Requires **two FFTs** (PSS + SSS symbols) and **one 512-point FFT correlation**.
- Produces a 511-bin search result, handled exactly by the existing `peak_detector.v`.

**Implementation notes for full Meyr (Step 32+):**
- The corrected frame output must span at least 2 OFDM symbols + 2 CPs = 2×(NSC+CP_LEN) = 576 samples.
  The current output is 288 samples (1 symbol). The buffer must be extended before Step 32.
- Two 256-point FFT blocks are required (PSS and SSS symbols separately).
- A 512-point FFT correlation block is required for `fft_correlation_Meyr`.

---

## Placement in the Receiver Chain

### Options Considered

**Option A** — Run integer CFO before fractional CFO correction (after frame detection only):
- Problem: fractional CFO distorts the FFT output; integer CFO estimation would be less reliable.
- Not recommended.

**Option B** — Run integer CFO after fractional CFO correction, using corrected time-domain frame:
- The corrected frame output (Step 29I validated) feeds into an FFT and then the integer CFO estimator.
- Natural pipeline extension.
- **Recommended** for this project.

**Option C** — Integer CFO as a separate validation/detection stage, run independently after
the full frac-CFO corrector outputs are stable:
- Functionally equivalent to Option B but architecturally separate.
- Useful for bring-up (test integer CFO estimator in isolation first).
- **Also recommended** for Step 31 testbench strategy.

### Recommended Placement

```
[Existing validated path]
corrected time-domain frame (288 samples)
        │
        ▼
  sync_symbol_extractor
  (strips CP, selects PSS OFDM symbol: NSC=256 samples)
        │
        ▼
  fft256_wrapper / skeleton
  (256-point FFT; initially behavioral model or placeholder)
        │
        ▼
  active_bin_selector
  (extracts the ~127 active PSS subcarrier bins)
        │
        ▼
  integer_cfo_candidate_correlator
  (tries shifts m = −M .. +M, accumulates conj(REF[k])·Y[k+m])
        │
        ▼
  peak_detector (reuse existing rtl/peak_detector.v)
  (argmax over 2M+1 scores → ε̂_int as signed integer)
        │
        ▼
  integer_cfo_estimate_register
  (AXI-Lite readable output)
        │
        ▼
  [Future] integer_cfo_corrector
  (step 33+: NCO correction at integer subcarrier granularity)
```

**Key integration note:** The PSS OFDM symbol starts at `slot_start + CP_LEN` (skipping the
cyclic prefix). The current corrected output includes CP + symbol (288 samples). The
`sync_symbol_extractor` skips the first CP_LEN=32 samples and passes the next NSC=256 samples
to the FFT.

---

## Proposed Block-Level Architecture

```
┌───────────────────────────────────────────────────────────────────────────┐
│                    integer_cfo_estimator_top                              │
│                                                                           │
│  s_axis (AXI-Stream, corrected time-domain frame, 288 samples)           │
│       │                                                                   │
│       ▼                                                                   │
│  ┌─────────────────────┐                                                  │
│  │ sync_symbol_extractor│  skip CP_LEN samples, buffer NSC samples       │
│  └──────────┬──────────┘                                                  │
│             │  NSC=256 complex samples (time domain)                      │
│             ▼                                                             │
│  ┌─────────────────────┐                                                  │
│  │   fft256_wrapper    │  256-pt FFT                                      │
│  │  (skeleton/model)   │  ← future: Xilinx FFT IP insertion point        │
│  └──────────┬──────────┘                                                  │
│             │  Y[k], k=0..255 (frequency domain)                         │
│             ▼                                                             │
│  ┌─────────────────────┐   ┌──────────────────┐                          │
│  │  active_bin_selector│◄──│  pss_ref_rom      │  PSS_REF[k], 127 bins  │
│  └──────────┬──────────┘   └──────────────────┘                          │
│             │  (Y_active[k], REF_active[k]) pairs                        │
│             ▼                                                             │
│  ┌──────────────────────────────┐                                         │
│  │ integer_cfo_candidate_corr   │  for m = −M..+M:                       │
│  │                              │    metric[m] = Σ conj(REF[k])·Y[k+m]  │
│  │                              │    score[m] = |metric[m]|²             │
│  └──────────────┬───────────────┘                                         │
│                 │  (score[m], m index) stream                            │
│                 ▼                                                         │
│  ┌─────────────────────┐                                                  │
│  │   peak_detector.v   │  (reuse existing, INDEX_WIDTH=4 for M=4)       │
│  └──────────┬──────────┘                                                  │
│             │  peak_index (unsigned) → decode: ε̂_int = peak_index − M   │
│             ▼                                                             │
│  ┌─────────────────────┐                                                  │
│  │  int_cfo_est_reg    │  AXI-Lite readable; done/error outputs          │
│  └─────────────────────┘                                                  │
└───────────────────────────────────────────────────────────────────────────┘
```

**Xilinx FFT IP insertion point:** `fft256_wrapper` has a clean AXI-Stream interface.
When Xilinx FFT IP is added (future step), only this module changes; all downstream logic is unaffected.

---

## Proposed RTL Interface

The following interface is a documented proposal for future implementation.
No RTL file is created in Step 30.

```verilog
module integer_cfo_estimator_top #(
    parameter FFT_LEN      = 256,   // must be power of 2
    parameter NUM_PSS_BINS = 127,   // active PSS subcarriers
    parameter SEARCH_RADIUS = 4,    // m ∈ {-M..+M}, total 2M+1 candidates
    parameter IQ_WIDTH     = 16,    // signed per I and Q channel
    parameter ACC_WIDTH    = 48     // complex accumulator width
)(
    input  wire                      aclk,
    input  wire                      aresetn,

    // AXI-Stream input: corrected time-domain frame (CP + OFDM symbol)
    input  wire                      s_axis_tvalid,
    output wire                      s_axis_tready,
    input  wire [2*IQ_WIDTH-1:0]     s_axis_tdata,   // [15:0]=I, [31:16]=Q
    input  wire                      s_axis_tlast,

    // AXI-Stream output: integer CFO estimate (one beat per frame)
    output wire                      m_axis_tvalid,
    input  wire                      m_axis_tready,
    output wire signed [15:0]        m_axis_integer_cfo,   // signed, units = subcarrier bins
    output wire [ACC_WIDTH-1:0]      m_axis_peak_score,    // magnitude² of winning metric

    output wire                      done,
    output wire                      error
);
```

**Port notes:**
- `s_axis_tdata[15:0]` = I sample (Q1.15), `s_axis_tdata[31:16]` = Q sample (Q1.15).
  Consistent with the existing project convention used throughout the synchronizer chain.
- `m_axis_integer_cfo` is signed: negative = received spectrum shifted down, positive = shifted up.
- `m_axis_peak_score` allows the host to assess confidence (SNR proxy).
- `done` is a 1-clock pulse (consistent with all existing RTL modules).
- `error` is sticky, cleared by `aresetn` (consistent with existing convention).

---

## Fixed-Point and Accumulator Considerations

| Stage                          | Bit Width             | Notes                                               |
|--------------------------------|-----------------------|-----------------------------------------------------|
| Input IQ samples               | 16-bit signed (Q1.15) | Convention throughout project                       |
| FFT input                      | 16-bit IQ             | Pass through unchanged                              |
| FFT output bins Y[k]           | 16-bit IQ             | Block floating point or saturating 16-bit           |
| PSS reference REF[k]           | 16-bit IQ (ROM)       | Pre-normalized to ±32767                            |
| Complex product conj(REF)·Y    | 32-bit IQ             | 16×16 = 32-bit product; two 16-bit multipliers      |
| Accumulator for metric[m] I/Q  | **48-bit signed**     | Sum of up to 127 × 32-bit products; 32+7 = 39 bits minimum; 48 bits gives comfortable headroom |
| Score = metric_I² + metric_Q²  | 96-bit before trunc   | Two 48² products; truncate to 64 bits after shift   |
| Peak detector input            | 64-bit unsigned       | `METRIC_WIDTH=64` in `peak_detector.v`              |
| Integer CFO output             | 16-bit signed         | Range ±SEARCH_RADIUS; values ≤ ±255 for full Meyr  |

**Key rules:**
1. Do not truncate before the accumulation is complete. Rounding/truncation should happen
   only when writing the final score to the peak detector input.
2. For the score comparison, a right-shift by a constant (e.g., 16 bits) before writing to the
   64-bit peak_detector input is acceptable because all candidates are shifted by the same amount —
   it preserves the argmax result.
3. `peak_detector.v` already uses unsigned 64-bit metric and 9-bit index, which covers both
   the Step 31 (2M+1 = 9 candidates) and future full Meyr (511 candidates) cases.
4. Do not use Block Floating Point for the accumulator in Step 31; use fixed-width 48-bit.
   BFP can be added in a later optimization step if dynamic range is a problem.

---

## Verification Strategy

### Step 31 — Option 31A (Recommended Starting Point)

**Goal:** Implement and verify the `integer_cfo_candidate_correlator` and `peak_detector`
integration using synthetic frequency-domain inputs — **no FFT required**.

**What to build in Step 31:**

1. `rtl/integer_cfo_candidate_corr.v`:
   - Input: frequency-domain bins Y_active[k] and PSS_REF[k] (from parameter/ROM)
   - For each candidate m, compute metric[m] and score[m]
   - Output: score stream to peak_detector.v

2. `rtl/integer_cfo_estimator_top.v` (minimal):
   - Wraps `integer_cfo_candidate_corr.v` + existing `peak_detector.v`
   - Decodes peak index to signed integer CFO

3. `tb/integer_cfo_estimator_top_tb.sv`:
   - Directly feeds shifted PSS frequency bins (simulates FFT output with known integer shift)
   - Verifies `m_axis_integer_cfo` equals the injected shift
   - Tests: zero shift, ±1, ±M, ±(M+1) out-of-range (peak saturation), SNR degraded input

**Why Option 31A first:**
- Isolates the argmax logic from FFT complexity.
- Deterministic testbench: inject PSS_REF shifted by exactly m, confirm estimator returns m.
- No Xilinx IP dependency.
- The FFT block can be mocked as a combinatorial passthrough in the testbench.

### Step 32 — Add FFT Frontend

- Create `rtl/fft256_wrapper.v`: behavioral FFTW-equivalent model in RTL simulation.
- Later: replace with Xilinx FFT IP (AXI-Stream interface, natural-order output).
- Testbench: feed fractional-CFO-corrected time-domain samples, verify FFT output,
  then verify integer CFO estimator end-to-end.

### Step 33 — Full Integration

- Extend `frac_cfo_sync_bram_test_wrapper.v` to include the integer CFO path.
- Add AXI-Lite register for `integer_cfo_estimate` readback.
- Board test: inject known IQ vector with deliberate integer CFO, verify readback value.

---

## Recommended Step 31 Target

**Step 31 — Frequency-Domain Integer CFO Candidate Correlator (Option 31A)**

Implement:
- `rtl/integer_cfo_candidate_corr.v` — correlator core
- `rtl/integer_cfo_estimator_top.v` — top-level wrapper with peak_detector integration
- `tb/integer_cfo_estimator_top_tb.sv` — deterministic testbench using synthetic FFT bins
- `scripts/run_integer_cfo_estimator_sim.sh` — Vivado xsim script

**Acceptance criteria:**
- Passes all testbench checks for integer shifts m = 0, ±1, ±2, ±M.
- Does not require Xilinx FFT IP.
- Uses 48-bit accumulators and 64-bit peak detector score input.
- Reuses existing `rtl/peak_detector.v` without modification.

---

## Future Integration Notes

1. **Buffer extension for full Meyr**: the current corrected output is 288 samples (1 symbol + CP).
   Full Meyr requires PSS + SSS = 2 symbols + 2 CPs = 576 samples. The `iq_frame_buffer`
   can hold 4096 samples; extending the output playback count is a parameter change in
   `frac_cfo_frame_corrector_top.v`.

2. **Xilinx FFT IP insertion**: When Xilinx FFT IP is introduced, only `fft256_wrapper.v` changes.
   The correlator, peak detector, and top-level interface are unaffected. The FFT IP uses a
   natural-order AXI-Stream interface compatible with the proposed block boundary.

3. **Integer CFO correction**: after estimation, the correction is an NCO rotation at integer
   subcarrier granularity. The formula for the correction step word is:
   ```
   freq_offset_Hz = ε̂_int × (f_sample / NSC)
   step_word = freq_offset_Hz / f_sample × 2^32
             = ε̂_int × 2^32 / NSC
             = ε̂_int × 16,777,216  (for NSC=256)
   ```
   The existing `nco_phase_gen.v` and `complex_rotator.v` can be reused for this correction.

4. **Cell ID (PSS/SSS index)**: the C reference also uses PSS/SSS for cell identity estimation
   (`cellIDMseq`, `cellIDGoldseq`). These functions are commented out in the current reference
   flow. They are deferred beyond Step 33.

5. **Peak_detector.v reuse**: the existing `peak_detector.v` parameters are:
   - `METRIC_WIDTH=64, INDEX_WIDTH=9, COUNT_WIDTH=10`
   - This supports up to 511 candidates (full Meyr range) and 1024-sample streams.
   - No modification needed for Step 31 or full Meyr.

---

## Conclusion

Integer CFO estimation is the next algorithmic stage after the validated fractional-CFO
corrector. The recommended implementation path is:

| Decision | Choice | Reason |
|----------|--------|--------|
| Domain | Frequency domain | Integer CFO is a bin shift — direct measurement after FFT |
| Reference type | Frequency-domain PSS_REF[k] | Matches C reference; RTL-natural; no derotation search |
| First algorithm | Single-symbol candidate search | Simpler; Step 31-ready without FFT IP |
| Future algorithm | Full Meyr (PSS × conj(SSS)) | Matches C reference; more robust; Step 32+ |
| FFT | Placeholder/behavioral first | Avoid Xilinx IP dependency in Phase 1 |
| Step 31 target | Option 31A correlator only | Isolates argmax logic; deterministic testbench |
| Fixed-point | 16-bit IQ in, 48-bit accumulator, 64-bit score | Safe headroom; reuses peak_detector.v |
| Placement | After frac-CFO correction (Option B) | Board-validated output is the natural input |

**Recommended next step:** Step 31 — implement `integer_cfo_candidate_corr.v` and
`integer_cfo_estimator_top.v` with a deterministic frequency-domain testbench.
No FFT IP required.
