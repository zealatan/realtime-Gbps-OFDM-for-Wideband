# Step 3 — Fixed-Point and Interface Specification for Full OFDM Synchronizer RTL

## 0. Scope and Constraints

This document specifies all fixed-point widths, AXI-Stream interface formats, the AXI-Lite
register map, and the saturation policy for the full RTL implementation of the C
`synchronization()` function. No RTL is written here.

Hardware target: Xilinx FPGA (Vivado toolchain). Input samples from PlutoSDR (AD9361 ADC,
12-bit signed, zero-padded to 16-bit in RTL). Clock domain: single clock throughout first
implementation.

Key constants driving all width choices:

| Constant | Value |
|---|---|
| NSC | 256 |
| CP_LEN | 32 |
| Energy window length (wndLen) | 25 |
| Energy threshold (C float) | 40000 |
| Consecutive hit count | 10 |
| PSS/SSS FFT size | 256 |
| Meyr correlation FFT size | 512 |
| Meyr cross-correlation span | 2×NSC−1 = 511 |

---

## 1. Global Fixed-Point Parameters

### Summary Table

| Parameter | Value | Primary role |
|---|---|---|
| `DATA_WIDTH` | 32 | AXI-Stream TDATA word (I+Q pair) |
| `SAMPLE_FRAC_BITS` | 15 | Q1.15 fractional bits in each 16-bit sample |
| `POWER_WIDTH` | 32 | Per-sample energy I²+Q² |
| `PRODUCT_WIDTH` | 32 | 16×16 signed multiply output |
| `ACC_WIDTH` | 40 | Correlation and energy window accumulator |
| `METRIC_WIDTH` | 32 | Timing metric 2\|corr\|−E output |
| `PHASE_WIDTH` | 16 | atan2 / CFO phase output |
| `CORDIC_PHASE_WIDTH` | 16 | CORDIC phase port width |
| `NCO_PHASE_WIDTH` | 32 | NCO phase accumulator |
| `ROTATOR_COEFF_WIDTH` | 16 | sin/cos coefficient (Q1.15) |
| `FFT_DATA_WIDTH` | 16 | Per-component FFT I/O |
| `FFT_TWIDDLE_WIDTH` | 16 | FFT twiddle factor precision |
| `MEYR_ACC_WIDTH` | 40 | Post-FFT Meyr peak detection accumulator |
| `INDEX_WIDTH` | 9 | Sample index / peak index |
| `AXIS_TDATA_WIDTH` | 32 | AXI-Stream TDATA (= DATA_WIDTH) |
| `AXIL_DATA_WIDTH` | 32 | AXI-Lite data bus |
| `AXIL_ADDR_WIDTH` | 8 | AXI-Lite address bus |

---

### 1.1 DATA_WIDTH = 32

**Reason.** One 32-bit AXI-Stream word carries a 16-bit signed I sample in bits [15:0] and a
16-bit signed Q sample in bits [31:16]. This matches the existing `axis_complex_mult.v`
default (DATA_WIDTH=32, COMPONENT_WIDTH=16) and the Xilinx AD9361/AD9364 driver format.

**Affected RTL blocks.** All AXI-Stream boundaries: sample_buffer.v, symbol_extractor.v,
cp_autocorr_core.v, complex_rotator.v, fft_wrapper.v, meyr_corr_core.v.

**Overflow risk.** None. This is a container width, not a computed value.

---

### 1.2 SAMPLE_FRAC_BITS = 15

**Reason.** Q1.15 format: 1 sign bit + 15 fractional bits, values in [−1.0, +1.0). The
AD9361 delivers 12-bit signed samples (range −2048..+2047). In RTL, each 12-bit sample is
sign-extended and left-shifted 4 bits to fill a 16-bit Q1.15 word. Digital full-scale
±32767 (0x7FFF / 0x8001) corresponds to ±1.0. SHIFT=15 in existing `axis_complex_mult.v`
enforces this scaling after multiply.

**Affected RTL blocks.** frame_detector.v (power computation), cp_autocorr_core.v (MAC
inputs), complex_rotator.v (rotation inputs/outputs), fft_wrapper.v (data input).

**Overflow risk.** Low at input. Saturate to ±32767 at the AXI-Stream ingress if the DMA
source delivers values outside 12-bit range. No overflow inside the 16-bit word because the
ADC physical range is guaranteed within 12 bits.

---

### 1.3 POWER_WIDTH = 32

**Reason.** Per-sample instantaneous power: P = I² + Q² where I, Q are 16-bit signed.
Maximum: I = Q = 32767 → P = 2 × 32767² = 2,147,418,114 < 2³¹. This fits in a 32-bit
unsigned word with one bit of headroom. Using 32 bits allows direct comparison with the
AXI-Lite threshold register without width conversion.

**Affected RTL blocks.** frame_detector.v (sliding-window accumulator input),
cp_autocorr_core.v (energy normalization array normalizedValue_1).

**Overflow risk.** None for the per-sample value. The sliding-window accumulator must use
ACC_WIDTH (see §1.5), not POWER_WIDTH, because summing 25 samples can reach 25 × 2³¹ ≈
2³⁵·⁶.

---

### 1.4 PRODUCT_WIDTH = 32

**Reason.** Result of a single 16-bit × 16-bit signed multiply. The product is
32-bit signed (sign + 31 magnitude bits). In Q1.15 × Q1.15 arithmetic, the product is
in Q2.30 format and must be right-shifted 15 bits (SHIFT=15) to return to Q1.15, yielding a
17-bit result that is then truncated to 16 bits with saturation. The 32-bit intermediate
product is held before the shift.

**Affected RTL blocks.** cp_autocorr_core.v (complex MAC multiplier stage),
complex_rotator.v (rotation multiply), axis_complex_mult.v (existing, internal wires).

**Overflow risk.** None for the product itself. Overflow becomes possible after the
shift-and-round step if the product magnitude exceeds Q1.15 range; saturation is applied
then (see §9).

---

### 1.5 ACC_WIDTH = 40

**Reason.** Two separate accumulators share this width:

1. **CP autocorrelation accumulator** (`cp_autocorr_core.v`): accumulates CP_LEN = 32
   complex products. Each product is 32-bit before the Q1.15 re-scaling. Worst-case sum of
   32 full-scale products: 32 × 2³¹ = 2³⁶. Guard bits needed: ⌈log₂(32)⌉ = 5.
   Minimum width: 32 + 5 = 37 bits. 40 bits provides 3 additional bits for saturation
   headroom and byte-alignment.

2. **Frame energy window accumulator** (`frame_detector.v`): sliding window of 25 samples,
   each up to 2³¹. Worst-case sum: 25 × 2³¹ ≈ 2³⁵·⁶. 40 bits covers this without
   overflow.

**Affected RTL blocks.** cp_autocorr_core.v (correlation and normalization accumulators),
frame_detector.v (window energy accumulator).

**Overflow risk.** None with 40 bits. The 40-bit accumulator is internal; outputs are
truncated/saturated to narrower widths before leaving the block.

---

### 1.6 METRIC_WIDTH = 32

**Reason.** Timing metric: `M[j] = 2·|autocorr[j]| − E[j]`. The magnitude |autocorr[j]|
is at most ACC_WIDTH-wide but is computed from a 40-bit accumulator whose values in practice
fit in 32 bits after normalization (CP_LEN × full-scale Q1.15 product ≤ 32 × 2^15 = 2^20 in
Q1.15 units). E[j] is the energy normalization (also ≤ 2^20 units). The difference M[j]
is signed (metric can be negative when no sync peak is present), so a 32-bit signed word
provides ample range and matches the AXI-Lite readback register width.

**Affected RTL blocks.** timing_metric_core.v (metric computation), peak_detector.v (real
argmax over 256 values).

**Overflow risk.** Low. The metric is bounded by the accumulator range. If the CORDIC
magnitude approximation is used (§4.1), the approximation error is bounded and cannot cause
overflow.

---

### 1.7 PHASE_WIDTH = 16

**Reason.** Output of the atan2 / CORDIC block representing the phase of the CP
autocorrelation peak. Xilinx CORDIC IP (AXI-Stream mode, translate function) outputs a
16-bit signed phase word where 0x7FFF = +π and 0x8000 = −π (full-scale = ±π radians,
effectively Q1.15 scaled by π). Phase resolution: π / 32767 ≈ 9.6 × 10⁻⁵ rad ≈ 0.0055°.

Fractional CFO derived from phase: `fracCFO = −phase / (2π)`. With 16-bit phase:
fractional CFO resolution = 1 / (2 × 32768) ≈ 1.5 × 10⁻⁵ subcarriers. This is well below
the subcarrier spacing and gives adequate CFO correction precision.

**Affected RTL blocks.** frac_cfo_estimator.v, cordic_atan2.v (or Xilinx CORDIC wrapper),
sync_control_fsm.v (receives phase → computes NCO step).

**Overflow risk.** None. atan2 output is always bounded to [−π, +π).

---

### 1.8 CORDIC_PHASE_WIDTH = 16

**Reason.** Phase word fed into the CORDIC engine for sin/cos computation (rotate mode) or
output from the CORDIC engine after atan2 (translate mode). Both use the same 16-bit
two's-complement phase word in ±π scaling.

Xilinx CORDIC IP v6.0: when data_format = SignedFraction, phase is 16-bit signed. Number
of CORDIC iterations = output_width − 1 = 15, giving approximately 15 bits of angular
precision after convergence.

**Affected RTL blocks.** cordic_atan2.v, nco_phase_gen.v (feeds CORDIC with the 16 MSBs
of the 32-bit phase accumulator to obtain sin/cos), complex_rotator.v.

**Overflow risk.** None. CORDIC phase input saturates to ±full-scale if out of range.

---

### 1.9 NCO_PHASE_WIDTH = 32

**Reason.** The NCO phase accumulator increments by a programmable step word each sample
clock. 32-bit width gives:

- Frequency resolution: f_sample / 2³² ≈ 7.1 mHz at f_sample = 30.72 MHz (PlutoSDR).
- Phase step for one subcarrier: 2³² / NSC = 2³² / 256 = 16,777,216 (0x01000000).
- Fractional CFO range ±0.5 subcarrier: step ∈ [−8,388,608, +8,388,607] — fits in 32-bit
  signed.
- Integer CFO range ±(NSC−1) = ±255 subcarriers: step ∈ [−4,278,190,080, +4,261,412,864]
  — fits in 32-bit signed.

The 32-bit accumulator wraps at 2³² = 2π (intended modulo behavior, not overflow).

The 16 MSBs of the accumulator are fed to the sin/cos CORDIC (CORDIC_PHASE_WIDTH = 16),
discarding the lower 16 fractional-phase bits. This gives sin/cos precision of 2π / 2¹⁶ ≈
9.6 × 10⁻⁵ rad.

**Affected RTL blocks.** nco_phase_gen.v (accumulator register), frac_cfo_estimator.v and
integer_cfo_estimator.v (compute the step word), sync_control_fsm.v (loads step into NCO).

**Overflow risk.** Intentional wrap. No saturation is applied to the accumulator; modulo-2³²
wrap is the correct behavior (full circle).

---

### 1.10 ROTATOR_COEFF_WIDTH = 16

**Reason.** The complex rotator multiplies each IQ sample by (cos θ + j·sin θ), where cos θ
and sin θ are Q1.15 16-bit values produced by the NCO/CORDIC. Using 16-bit coefficients
matches COMPONENT_WIDTH = 16 in existing `axis_complex_mult.v`, allowing direct reuse.

After complex multiply: result is Q2.30; right-shift by SHIFT = 15 returns to Q1.15 with
16-bit output. The multiplication is lossless (no rounding error beyond 1 LSB).

**Affected RTL blocks.** complex_rotator.v (feeds sin/cos as multiplier B input),
nco_phase_gen.v (CORDIC output width), axis_complex_mult.v (reused as the rotator core).

**Overflow risk.** Low. A unit-magnitude rotation cannot increase the signal magnitude. If
the input IQ is at full-scale (±32767 in Q1.15), the output is also at full-scale. The
only overflow risk is at the 1 LSB rounding step, guarded by saturation (see §9).

---

### 1.11 FFT_DATA_WIDTH = 16

**Reason.** Each I or Q component entering and leaving the FFT engine is 16-bit signed
(Q1.15). This matches the sample width throughout the pipeline and is a supported width
in Xilinx FFT IP v9.1 (8/16/24/32-bit supported).

FFT gain note: a 256-point FFT has a worst-case linear gain of 256 (= 2⁸), which would
require 8 additional bits to prevent internal overflow. Xilinx FFT IP addresses this with
**block floating-point** (BFP) scaling: each output frame carries a shared scale exponent
word in TUSER indicating how many right-shifts were applied. Downstream blocks must account
for this exponent when comparing FFT outputs. Alternatively, **unscaled** mode may be used
with wider internal buses; the IP then truncates to the output width at each stage.

For this design, **block floating-point mode** is recommended. The exponent is carried via
the TUSER sideband and consumed by the downstream cross-correlation and peak-detection blocks.

**Affected RTL blocks.** fft_wrapper.v (256-point and 512-point), meyr_corr_core.v,
integer_cfo_estimator.v, pss_sss_rom.v (output matches FFT input width).

**Overflow risk.** Moderate without BFP. With BFP enabled in the Xilinx IP, overflow within
the FFT is prevented by the IP's internal scaling. The scale exponent in TUSER must be
tracked and applied before any inter-block magnitude comparison.

---

### 1.12 FFT_TWIDDLE_WIDTH = 16

**Reason.** Xilinx FFT IP uses 16-bit internal twiddle factors when the data width is 16
bits. This gives twiddle factor precision of 2⁻¹⁵ ≈ 3 × 10⁻⁵, which provides approximately
15 bits of useful precision in the transform output. Increasing to 18 or 24 bits would
improve precision marginally at the cost of significantly more BRAM/DSP usage for the
twiddle ROM. 16 bits is the standard choice for this application.

**Affected RTL blocks.** Internal to fft_wrapper.v (Xilinx IP parameter).

**Overflow risk.** None. Twiddle factors are unit-magnitude phasors; no accumulation occurs
in the twiddle path.

---

### 1.13 MEYR_ACC_WIDTH = 40

**Reason.** After the Meyr IFFT, each cross-correlation output bin is a 16-bit complex
value (if Xilinx BFP is active) or up to 32-bit (unscaled). Peak detection requires
computing the squared magnitude I² + Q² for each of the 511 output bins:

- With 16-bit FFT output: I² + Q² ≤ 2 × 32767² ≈ 2³¹. Fits in 32 bits.
- To compare magnitudes across bins without sqrt, accumulate I² + Q² per bin. Each bin
  yields one 32-bit value. No multi-bin accumulation is needed for peak detection; 32-bit
  is sufficient, but 40 bits is used for consistency with ACC_WIDTH and to provide safe
  headroom if unscaled mode is selected for the 512-point FFT.

**Affected RTL blocks.** meyr_corr_core.v (IFFT output → magnitude), peak_detector.v
(Meyr 511-point complex argmax).

**Overflow risk.** None at 40 bits. With BFP FFT output (16-bit): max bin magnitude
squared ≈ 2³¹ << 2⁴⁰.

---

### 1.14 INDEX_WIDTH = 9

**Reason.** Must address the largest array in the design — the Meyr cross-correlation output
of length 2×NSC−1 = 511 samples. ⌈log₂(511)⌉ = 9 bits (2⁹ = 512 > 511). This same width
also covers the timing peak index (0..NSC−1 = 0..255), the symbol buffer address (0..NSC+CP_LEN−1 = 0..287), and the integer CFO range (−255..+255 as 9-bit signed, which fits since 2⁸ = 256 > 255).

**Affected RTL blocks.** peak_detector.v (index output), sync_control_fsm.v (timing offset
register, integer CFO register), integer_cfo_estimator.v (peak index → intCFO conversion),
sample_buffer.v (address counter).

**Overflow risk.** None. Fixed range, bounded by NSC and 2×NSC−1.

---

### 1.15 AXIS_TDATA_WIDTH = 32

**Reason.** Alias for DATA_WIDTH. Explicitly named to distinguish the AXI-Stream TDATA bus
from internal pipeline data buses. Defined separately to allow future expansion (e.g., wider
TDATA for 32-bit IQ samples) without affecting internal data widths.

**Affected RTL blocks.** All module port lists that expose AXI-Stream ports.

**Overflow risk.** None. Container width.

---

### 1.16 AXIL_DATA_WIDTH = 32

**Reason.** Standard AXI4-Lite data width. Matches existing `axi_lite_regfile.v`. All
synchronizer control and status values fit in 32-bit registers (see §7 for full register
map). Processor-side reads/writes use 32-bit bus transactions.

**Affected RTL blocks.** axi_lite_sync_regs.v.

**Overflow risk.** None.

---

### 1.17 AXIL_ADDR_WIDTH = 8

**Reason.** 8-bit byte address covers 256 bytes = 64 four-byte registers. The synchronizer
register map uses 15 registers (60 bytes), so 6 bits would technically suffice. 8 bits
matches the existing `axi_lite_regfile.v` port width and provides space for future registers
without an interface change.

**Affected RTL blocks.** axi_lite_sync_regs.v (address decode logic).

**Overflow risk.** None. Upper address bits decode as SLVERR (out-of-range).

---

## 2. AXI-Stream IQ Sample Format

### 2.1 Input sample stream — s_axis_iq_*

```text
Signal              Width   Description
─────────────────── ─────── ──────────────────────────────────────────────────
s_axis_iq_tdata     32      [15:0]  = I (in-phase),  signed Q1.15
                            [31:16] = Q (quadrature), signed Q1.15
s_axis_iq_tvalid    1       High when source presents a valid sample
s_axis_iq_tready    1       High when synchronizer accepts the sample
s_axis_iq_tlast     1       High on the last sample of the input burst
                            (marks end of the rxLen-sample block to process)
s_axis_iq_tuser     1       Optional: frame-start marker (high on sample 0
                            of the slot if known upstream); 0 if unused
```

**Format.** Signed two's complement, Q1.15. 0x7FFF = +0.99997 (≈ +1.0). 0x8000 = −1.0.
0x0000 = 0.0. The 12-bit AD9361 sample is sign-extended to 16 bits, then left-shifted 4
bits: `iq_q1_15 = adc_12bit_signed <<< 4`.

**Packing convention.**

```text
Bit 31          16 15          0
     ┌─────────────┬─────────────┐
     │  Q[15:0]   │  I[15:0]   │
     └─────────────┴─────────────┘
```

I (real / in-phase) occupies the lower 16 bits. Q (imaginary / quadrature) occupies the
upper 16 bits. This is the Xilinx ADC/DAC platform convention and the PlutoSDR IIO driver
output format.

**Existing axis_complex_mult.v compatibility note.** The existing module uses port names
`a_real = tdata[31:16]` and `a_imag = tdata[15:0]`. With this project's convention,
`a_real` maps to Q and `a_imag` maps to I. When instantiating `axis_complex_mult.v` for
standard complex multiplication (I+jQ)(I'+jQ'), the inputs must be swapped so that I is
presented on the `a_real` port (upper half) and Q on `a_imag` (lower half) — or a thin
wrapper `complex_mult_iq.v` must re-pack the TDATA bus before driving the existing module.
This wrapper is defined in §2.4 below.

### 2.2 Output streams — synchronizer results

Synchronizer outputs are delivered via AXI-Lite status registers (see §7), not as AXI-Stream
channels. The single AXI-Stream output is the corrected IQ stream, available after all CFO
corrections are applied:

```text
Signal              Width   Description
─────────────────── ─────── ──────────────────────────────────────────────────
m_axis_iq_tdata     32      Corrected I/Q in same Q1.15 format as input
m_axis_iq_tvalid    1       Valid when corrected sample available
m_axis_iq_tready    1       Backpressure from downstream
m_axis_iq_tlast     1       High on last corrected sample of the slot
m_axis_iq_tuser     1       High on first sample following integer CFO
                            correction (slot boundary marker)
```

### 2.3 TLAST and TUSER semantics

| Signal | Producer sets high when... | Consumer uses it to... |
|---|---|---|
| `s_axis_iq_tlast` | Last of rxLen input samples presented | Trigger end-of-frame detection in sync_control_fsm |
| `m_axis_iq_tlast` | Last corrected sample output | Signal downstream demodulator to expect no more samples |
| `s_axis_iq_tuser` | (Optional) upstream knows slot boundary | Skip frame_detector stage in FSM |
| `m_axis_iq_tuser` | First sample after integer CFO correction | Mark slot start for downstream OFDM demodulator |

### 2.4 complex_mult_iq.v wrapper interface (planned)

To bridge the I-lower / Q-upper convention with axis_complex_mult.v's upper=real port
naming, a thin wrapper will present:

```text
Input:  {Q_a[31:16], I_a[15:0]}  →  drives a_real=I_a (upper), a_imag=Q_a (lower)
                                       by swapping the 16-bit halves internally
Output: {Q_out[31:16], I_out[15:0]}  ←  reconstructed from {out_real=I, out_imag=Q}
```

The wrapper performs only bit-reordering (no arithmetic), costs zero LUTs, and preserves
the Q1.15 format throughout.

---

## 3. Stage-by-Stage Width Analysis

### Stage 1 — Frame Detector

| Path | Width | Notes |
|---|---|---|
| Input I, Q | 16-bit signed Q1.15 | From s_axis_iq |
| Per-sample power P = I²+Q² | 32-bit unsigned | Max ≈ 2³¹, fits in 32 bits |
| Window accumulator | 40-bit unsigned (ACC_WIDTH) | 25 samples × 2³¹ ≈ 2³⁵·⁶ |
| Window energy E (for compare) | 32-bit unsigned (saturated) | Truncate or saturate ACC → 32 for threshold comparison |
| Threshold register | 32-bit (AXIL_DATA_WIDTH) | Software-programmable; scale relative to Q1.15 input |
| Frame index output | 32-bit unsigned | Sample count can exceed 2¹⁶ for long buffers |
| Hit counter | 4-bit unsigned | Counts 0..10 (10 consecutive hits needed) |

**Threshold scaling.** The C code threshold of 40000 was computed with float samples in ADC
count units (12-bit range ±2048). With Q1.15 samples (range ±32767), the equivalent
threshold is: `RTL_threshold = 40000 × (32767/2048)² = 40000 × 256 = 10,240,000`.
This is the reset value programmed into the threshold register. Software may override it
via AXI-Lite.

### Stage 2 — CP Autocorrelation Core

| Path | Width | Notes |
|---|---|---|
| Input I, Q | 16-bit signed Q1.15 | |
| Conjugate path (−Q_a) | 16-bit signed | Negate Q of delayed sample |
| Each partial product | 32-bit signed | 16×16 multiply |
| Accumulator (real, imag) | 40-bit signed (ACC_WIDTH) | 32 taps × 32-bit products |
| Normalization accumulator | 40-bit unsigned | sum of I²+Q² over 32 samples |
| Output: autocorr_I, autocorr_Q | 32-bit signed (truncated from ACC) | Truncate upper 8 guard bits for downstream |
| Output: norm_E | 32-bit unsigned | Truncate for timing metric |

**Resource note.** 256 lags each requiring 32-sample accumulation. If fully pipelined
(one lag per clock), the core needs 256 × 4 DSP48 blocks (4 multipliers per complex MAC).
If time-multiplexed (one lag per 32 clocks, cycling through all 256 lags in 8192 clocks),
the core needs 4 DSP48 blocks total at the cost of throughput. The fixed-point widths above
support both implementations without change.

### Stage 3 — Timing Metric Core

| Path | Width | Notes |
|---|---|---|
| Input: autocorr_I, autocorr_Q | 32-bit signed | From Stage 2 |
| Magnitude |autocorr| | 32-bit unsigned | CORDIC or α·max+β·min approximation |
| 2×|autocorr| | 33-bit unsigned (left shift by 1) | |
| norm_E | 32-bit unsigned | From Stage 2 |
| Metric M = 2|autocorr| − E | 33-bit signed | Can be negative |
| Metric output (METRIC_WIDTH) | 32-bit signed (saturate) | Saturate 33-bit to 32-bit |

**Magnitude implementation.** Two options:
- **CORDIC translate mode** (recommended): accepts 32-bit I/Q inputs, outputs 32-bit
  magnitude. Uses Xilinx CORDIC IP configured for magnitude-only output.
- **α·max + β·min approximation**: magnitude ≈ max(|I|,|Q|) + 0.375·min(|I|,|Q|). Error
  ≤ 3.5%. Simple combinational logic; no IP required. Acceptable for peak detection since
  the approximation is monotone.

### Stage 4 — Peak Detector

| Path | Width | Notes |
|---|---|---|
| Timing metric input | 32-bit signed (METRIC_WIDTH) | From Stage 3 |
| Meyr magnitude input | 40-bit unsigned (MEYR_ACC_WIDTH) | I²+Q² of IFFT output |
| Peak index output | 9-bit unsigned (INDEX_WIDTH) | 0..NSC−1 or 0..510 |
| Running maximum register | Same width as input | Replaced when new value exceeds |

### Stage 5 — Fractional CFO Estimation

| Path | Width | Notes |
|---|---|---|
| Input: autocorr_I, autocorr_Q at peak | 32-bit signed | From Stage 2 at peak index |
| CORDIC input (Cartesian) | 32-bit signed per component | Feed to Xilinx CORDIC |
| CORDIC phase output | 16-bit signed (PHASE_WIDTH) | Represents [−π, +π) |
| fracCFO step word | 32-bit signed | NCO step = round(−phase × 2³²/(2π)) |

**CORDIC decision.** Use Xilinx CORDIC IP v6.0 in translate (atan2) mode, AXI-Stream
interface, 16-bit output phase in SignedFraction format. This avoids a LUT-based atan2
table and uses dedicated DSP resources. CORDIC converges in 15 iterations (= 15 clock
cycles of latency in the IP's pipelined implementation). The throughput is one result per
clock after the pipeline is full.

### Stage 6 — Fractional CFO Correction

| Path | Width | Notes |
|---|---|---|
| NCO phase accumulator | 32-bit unsigned (NCO_PHASE_WIDTH) | Wraps at 2³² |
| NCO step word | 32-bit signed | Computed from fracCFO phase |
| sin θ, cos θ (from CORDIC/LUT) | 16-bit signed Q1.15 (ROTATOR_COEFF_WIDTH) | Upper 16 bits of accumulator fed to CORDIC |
| Rotation input I, Q | 16-bit signed Q1.15 | From sample stream |
| Multiply: I·cos, Q·sin, etc. | 32-bit signed (PRODUCT_WIDTH) | Via axis_complex_mult.v |
| Rotation output I, Q | 16-bit signed Q1.15 | Right-shift 15, saturate |

**sin/cos implementation.** Use the same Xilinx CORDIC IP in rotate mode (or a separate
instance in sincos mode), fed with the 16 MSBs of the 32-bit NCO accumulator. Alternatively,
a 256-entry × 16-bit ROM holding one quadrant of sin values gives adequate precision at
lower latency. The CORDIC option is preferred for resource sharing with Stage 5.

### Stages 7–8 — PSS/SSS Symbol Extraction and FFT

| Path | Width | Notes |
|---|---|---|
| Symbol buffer samples | 16-bit I, 16-bit Q per sample | Stored post-correction |
| CP removal offset (PSS) | CP_LEN = 32 samples | Fixed in hardware |
| CP removal offset (SSS) | 2×CP_LEN + NSC = 320 samples | Fixed in hardware |
| FFT input | 16-bit per component (FFT_DATA_WIDTH) | From symbol buffer |
| FFT output | 16-bit per component + TUSER exponent | BFP mode |
| FFT TUSER (scale exponent) | 8-bit unsigned | Xilinx FFT IP TUSER carries log₂(scale) |

### Stage 9 — Integer CFO Estimation (Meyr)

| Path | Width | Notes |
|---|---|---|
| PSS_FFT[j], SSS_FFT[j] | 16-bit I, 16-bit Q (BFP) | From 256-point FFT |
| term1[j] = conj(PSS)×SSS | 16-bit I, 16-bit Q | Via complex_mult_iq.v |
| mU[j], goldU[j] (ROM) | 16-bit I, 16-bit Q | Q1.15 reference sequences |
| term2[j] = conj(mU)×goldU | 16-bit I, 16-bit Q | Via complex_mult_iq.v |
| 512-point FFT of term1, term2 | 16-bit I, 16-bit Q + exponent | BFP mode |
| Freq-domain product: conj(A)×B | 16-bit I, 16-bit Q | Via complex_mult_iq.v |
| IFFT output | 16-bit I, 16-bit Q + exponent | BFP mode |
| Peak magnitude: I²+Q² | 40-bit unsigned (MEYR_ACC_WIDTH) | Per IFFT bin |
| Peak index | 9-bit unsigned (INDEX_WIDTH) | 0..510 |
| Integer CFO | 10-bit signed (INDEX_WIDTH+1) | intCFO = peakIdx − (NSC−1); range ±255 |

### Stage 10 — Integer CFO Correction

| Path | Width | Notes |
|---|---|---|
| NCO step word | 32-bit signed | = round(−intCFO × 2³²/NSC) |
| sin θ, cos θ | 16-bit signed Q1.15 | Shared NCO+CORDIC from Stage 6 |
| Rotation I/Q output | 16-bit signed Q1.15 | Final corrected sample |

---

## 4. CORDIC Implementation Decisions

### 4.1 atan2 (Stage 5 — fractional CFO estimation)

**Decision: Xilinx CORDIC IP v6.0, translate mode, AXI-Stream interface.**

Rationale:
- Input: 32-bit signed I, Q (from autocorrelation peak). Xilinx CORDIC supports up to 48-bit inputs.
- Output: 16-bit signed phase (PHASE_WIDTH), SignedFraction format (0x7FFF = +π).
- Latency: 15 clock cycles (pipelined, one result per clock in steady state).
- No LUT memory required; pure DSP logic.
- Error: < 1 LSB at the 16-bit output width (≈ 9.6 × 10⁻⁵ rad).

Configuration parameters for Xilinx CORDIC:

```
Function:              Translate (atan2)
Architectural Config:  Parallel (fully pipelined)
Data Format:           Signed Fraction
Phase Format:          Radians
Input Width:           32
Output Width:          16
Round Mode:            Truncate
```

### 4.2 sin/cos for NCO (Stages 6 and 10 — CFO correction)

**Decision: Xilinx CORDIC IP v6.0, sincos mode, AXI-Stream interface.**

The 16 MSBs of the 32-bit NCO accumulator are fed to the CORDIC as the phase input. The
CORDIC outputs a 16-bit cos θ and 16-bit sin θ in Q1.15. These drive the complex rotator
(axis_complex_mult.v).

Alternative (LUT-based sin/cos): a 512-entry × 16-bit quarter-sine ROM with linear
interpolation gives comparable precision at lower latency (1–2 clocks vs. 15 for CORDIC)
but requires BRAM or LUT RAM. The CORDIC option is preferred for resource sharing with the
atan2 block (single IP instance switchable between modes via the AXI config channel, or two
separate instances).

---

## 5. NCO Phase Accumulator Specification

```text
Module:         nco_phase_gen.v
Accumulator:    NCO_PHASE_WIDTH = 32 bits, unsigned
Step register:  32-bit signed (two's complement, loaded from sync_control_fsm)
Update:         phase_acc <= phase_acc + step_reg  (every sample clock)
Phase output:   phase_acc[31:16] → CORDIC (16-bit, CORDIC_PHASE_WIDTH)
Wrap behavior:  Natural binary overflow (2³² ≡ 0), no saturation
Reset:          phase_acc <= 0 on aresetn or at start of each correction pass
```

**Step word encoding.**

| CFO type | Step word formula |
|---|---|
| Fractional CFO | `step = round(−fracCFO_phase × 2^NCO_PHASE_WIDTH / (2π))` |
| Integer CFO | `step = round(−intCFO × 2^NCO_PHASE_WIDTH / NSC)` |

Where `fracCFO_phase` is the CORDIC output in radians (PHASE_WIDTH = 16 bit word × π/32767)
and `intCFO` is the integer CFO in subcarrier units.

**Frequency resolution:** 30.72 MHz / 2³² ≈ 7.15 mHz per LSB of step word.

**Maximum step word:**
- Fractional CFO (±0.5 subcarrier): |step| ≤ 2³¹ / NSC = 8,388,608
- Integer CFO (±255 subcarriers): |step| ≤ 255 × 2³² / 256 = 4,278,190,080 < 2³²  ✓

---

## 6. FFT Specification

### 6.1 256-Point FFT (PSS/SSS symbol transform)

```text
IP:              Xilinx FFT IP v9.1 (or equivalent)
Transform size:  256 (fixed)
Data width:      16-bit per component (FFT_DATA_WIDTH)
Twiddle width:   16-bit (FFT_TWIDDLE_WIDTH)
Scaling mode:    Block Floating Point (BFP)
Direction:       Forward only (no bit-reversal re-order; C uses fft_without_rearrange)
Ordering:        Natural order (no fftshift applied)
TUSER:           8-bit scale exponent (how many right-shifts the IP applied)
Throughput:      One 256-sample frame per (256 + latency) clocks
```

**No fftshift note.** The C reference function `fft_without_rearrange()` does not apply an
fftshift. The Xilinx IP in natural-order output mode matches this behavior. DC bin is at
index 0, not NSC/2.

### 6.2 512-Point FFT (Meyr cross-correlation)

```text
IP:              Xilinx FFT IP v9.1 (second instance, or reconfigurable instance)
Transform size:  512 (fixed)
Data width:      16-bit per component
Scaling mode:    Block Floating Point
Direction:       Forward FFT (×2) + Inverse FFT (×1)
IFFT direction:  Configured via AXI config channel or fixed port tie-off
Ordering:        Natural order
TUSER:           8-bit scale exponent
```

**Two FFT sizes.** The design uses two distinct FFT sizes: 256 for PSS/SSS extraction and
512 for Meyr correlation. Options:
1. Two independent FFT IP instances (simple but higher resource usage).
2. One reconfigurable instance supporting both sizes (complex control, lower resource).
Option 1 is recommended for first implementation.

### 6.3 BFP Exponent Handling

The BFP scale exponent is carried in the AXI-Stream TUSER field throughout the FFT path.
When two FFT outputs are multiplied (frequency-domain cross-correlation), the exponents of
both inputs must be summed and tracked through to the IFFT. The peak detection step uses the
magnitude of the IFFT output to find the largest bin; since the BFP exponent is the same for
all bins within one frame, it does not affect the argmax result and can be ignored for peak
detection. It does affect the absolute magnitude value logged in the status register (see §7,
register MEYR_PEAK_MAG).

---

## 7. AXI-Lite Register Map

Base address: 0x00000000 (relative to the axi_lite_sync_regs.v slave port).

All registers are 32-bit wide (AXIL_DATA_WIDTH). Unimplemented bits read as 0 and ignore
writes.

```text
Offset  R/W  Name              Reset       Description
──────  ───  ────────────────  ──────────  ───────────────────────────────────────────
0x00    RW   CTRL              0x00000000  Control register
                                           [0]   START       Write 1 to begin sync; auto-clears
                                           [1]   ABORT       Write 1 to abort; auto-clears
                                           [7:2] (reserved)
0x04    RO   STATUS            0x00000000  Status register (sticky; cleared by write to CTRL.START)
                                           [0]   DONE        1 when synchronizer completes normally
                                           [1]   BUSY        1 while synchronizer is running
                                           [2]   ERROR       1 if frame not found or timeout
                                           [3]   FRAME_FOUND 1 when frame_detector succeeds
                                           [7:4] (reserved)
0x08    RW   INTR_EN           0x00000000  Interrupt enable
                                           [0]   DONE_IE     Enable interrupt on DONE
                                           [1]   ERROR_IE    Enable interrupt on ERROR
0x0C    RW   ENERGY_THRESH     0x009C4000  Energy threshold (32-bit unsigned, Q1.15 units)
                                           Reset = 10,240,000 = 40000 × 256 (C float equivalent)
0x10    RW   WINDOW_LEN        0x00000019  Energy window length (8-bit, default 25)
                                           [7:0] WNDLEN
0x14    RW   HIT_COUNT         0x0000000A  Consecutive window hits required (8-bit, default 10)
                                           [7:0] HITCNT
0x18    RW   SAMPLE_COUNT      0x00000000  Number of input IQ samples to process (rxLen)
                                           Must be written before START
0x1C    RW   SYMBOLS_PER_SLOT  0x00000380  Samples per slot (NSC+CP_LEN) × num_symbols
                                           Default: (256+32) × 7 = 2016 = 0x7E0
                                           Adjust based on actual slot structure
0x20    RO   FRAME_INDEX       0x00000000  Sample index of detected frame start (slotStartIndex)
0x24    RO   TIMING_OFFSET     0x00000000  CP autocorrelation peak lag (0..NSC−1)
                                           [8:0] TIMING_LAG
0x28    RO   FRAC_CFO          0x00000000  Fractional CFO estimate
                                           [15:0] Signed Q1.15 in units of subcarrier spacings
                                                  (0x7FFF = +0.5 sc, 0x8001 ≈ −0.5 sc)
0x2C    RO   INT_CFO           0x00000000  Integer CFO estimate
                                           [9:0] Signed, in subcarrier units (range −255..+255)
0x30    RO   PEAK_METRIC       0x00000000  Timing metric value at the detected peak (debug)
                                           [31:0] Signed METRIC_WIDTH value
0x34    RO   MEYR_PEAK_IDX     0x00000000  Meyr correlation peak index (debug)
                                           [9:0] Raw peak index (0..510); intCFO = idx − 255
0x38    RO   MEYR_PEAK_MAG     0x00000000  Meyr peak magnitude squared (debug, 32-bit sat)
                                           Useful for assessing integer CFO confidence
```

**Register count:** 15 registers × 4 bytes = 60 bytes. Fits within AXIL_ADDR_WIDTH = 8
(256-byte space). Addresses 0x3C..0xFF are reserved and return SLVERR on read or write.

**CTRL.START protocol.** Software writes 1 to bit 0. Hardware latches it as a one-clock
pulse and begins the synchronizer FSM. The bit auto-clears on the next clock. STATUS.DONE
and STATUS.ERROR are cleared when a new START is issued.

---

## 8. Saturation Policy

Saturation (clamping to the representable range without wrap) is applied at the following
boundaries:

| Location | From width | To width | Direction |
|---|---|---|---|
| AXI-Stream input ingress | 16-bit (from DMA) | 16-bit | Saturate at ±32767 if ADC overrange |
| Complex rotator output | 33-bit (after multiply+shift) | 16-bit Q1.15 | Saturate signed: ≤−32768 → −32768; ≥+32767 → +32767 |
| Timing metric output | 33-bit signed | 32-bit signed (METRIC_WIDTH) | Saturate: 33-bit overflow clamps to ±2³¹−1 |
| Phase word from CORDIC | 16-bit (CORDIC output) | 16-bit (PHASE_WIDTH) | No conversion needed; CORDIC saturates internally |
| FFT input | 16-bit | 16-bit | No truncation; Xilinx IP handles internal scaling via BFP |
| FFT output | BFP 16-bit | 16-bit | Exponent tracks scaling; no saturation at output |
| Meyr magnitude squared | 33-bit | 40-bit (MEYR_ACC_WIDTH) | Zero-extend; no saturation |
| AXI-Lite status registers | Variable internal widths | 32-bit | Saturate to fit; report saturation in STATUS.ERROR |

**Overflow vs. wrap.** Wrap-around (natural binary overflow) is intentional only in the NCO
phase accumulator. All other accumulators and pipeline stages use saturating arithmetic.
Saturating arithmetic prevents catastrophic false peaks caused by full-scale overflow flipping
the sign of the timing metric or energy value.

**Implementation in RTL.** Saturation is implemented as a Verilog assign with conditional:

```verilog
// Example: saturate 33-bit signed to 32-bit signed
assign out = (in[32] == in[31]) ? in[31:0]         // no overflow
                                 : {in[32], {31{~in[32]}}};  // saturate
```

---

## 9. Parameter Instantiation Reference

The following parameter values should be passed as Verilog parameters at instantiation.

```verilog
// Top-level parameter declarations (in ofdm_synchronizer_top.v)
parameter DATA_WIDTH          = 32;
parameter SAMPLE_FRAC_BITS    = 15;
parameter POWER_WIDTH         = 32;
parameter PRODUCT_WIDTH       = 32;
parameter ACC_WIDTH           = 40;
parameter METRIC_WIDTH        = 32;
parameter PHASE_WIDTH         = 16;
parameter CORDIC_PHASE_WIDTH  = 16;
parameter NCO_PHASE_WIDTH     = 32;
parameter ROTATOR_COEFF_WIDTH = 16;
parameter FFT_DATA_WIDTH      = 16;
parameter FFT_TWIDDLE_WIDTH   = 16;
parameter MEYR_ACC_WIDTH      = 40;
parameter INDEX_WIDTH         = 9;
parameter AXIS_TDATA_WIDTH    = 32;  // = DATA_WIDTH
parameter AXIL_DATA_WIDTH     = 32;
parameter AXIL_ADDR_WIDTH     = 8;
```

These parameters are propagated down through the hierarchy. Each sub-block declares only the
parameters it uses. The top-level module defines the full set, ensuring a single point of
change if any value is revised.

---

## 10. Known Implementation Hazards and Decisions Deferred to Step 4+

| Hazard | Risk level | Mitigation |
|---|---|---|
| axis_complex_mult port naming (upper="real", lower="imag") conflicts with I-lower / Q-upper sample format | High | Define complex_mult_iq.v wrapper; verify with Python model in Step 4 |
| BFP exponent tracking across FFT → multiply → IFFT | High | Implement exponent accumulation registers in meyr_corr_core.v; verify in Step 4 testbench |
| CP autocorrelation lag index off-by-one | High | Exhaustive lag sweep in Python model vs C reference (Step 4/5) |
| NCO phase accumulator reset timing (should reset at exact slot start) | Medium | FSM controls reset signal; verify end-to-end CFO correction with Python model |
| CORDIC latency (15 cycles) introduces pipeline bubble in fractional CFO path | Medium | FSM waits for CORDIC valid; throughput not critical for one-shot synchronizer |
| FFT ordering: no fftshift applied, but peak may wrap in frequency domain | Medium | Verify argmax with Python model that uses same no-fftshift FFT |
| Meyr peak index to intCFO: intCFO = peak − (NSC−1) requires care at boundaries | High | Unit test at peak = 0, 255, 510 |
| Energy threshold reset value is hardware-calculated from float C value | Medium | AXI-Lite register is software-programmable; characterize threshold with actual RF data in Step 28/29 |

---

## 11. Files Changed

| File | Action |
|---|---|
| `md_files/03_fixed_point_interface_spec_prompt.md` | Created — full prompt text backup |
| `docs/step3_fixedpoint_spec.md` | Created — this specification document |
