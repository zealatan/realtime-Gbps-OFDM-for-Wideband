# Step 31 — Meyr Integer CFO Core

## Objective

Implement and verify the core Meyr integer CFO correlation engine before adding FFT,
PSS/SSS product generation, or board integration. This step isolates the argmax logic
with a deterministic testbench using synthetic term1/term2 inputs.

---

## Relationship to Step 30

Step 30 specified the full Meyr algorithm (verified against `ref/receiver.c`):

```
term1[j] = PSS_FFT[j] · conj(SSS_FFT[j])         (received product)
term2[j] = mU[j+CP_LEN] · conj(goldU[j+CP_LEN])   (static reference product)
R[n]     = Σ_j conj(term2[j]) · term1[j+n]         (cross-correlation, 511 lags)
score[n] = |R[n]|²
intCFO   = argmax_n score[n] − (NSC−1)              = peakIndexMeyr − 255
```

Step 31 implements and verifies this mapping with:
- no FFT IP
- no PSS/SSS symbol extraction
- no board wrapper changes
- a synthetic PRNG term2 ROM shared between RTL and testbench

---

## What Is Implemented

| File | Description |
|------|-------------|
| `rtl/meyr_integer_cfo_core.v` | Direct-lag Meyr correlation core; instantiates `peak_detector.v` |
| `tb/meyr_integer_cfo_core_tb.sv` | 12-group deterministic testbench, 32 checks |
| `scripts/run_meyr_integer_cfo_core_sim.sh` | Vivado xsim compile + run script |

### RTL parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| NSC | 256 | FFT size / number of subcarriers |
| IQ_WIDTH | 16 | Per-channel IQ width (not directly used in core; for interface documentation) |
| PROD_WIDTH | 32 | term1/term2 input width per I or Q component |
| ACC_WIDTH | 56 | Signed accumulator width for R_I[n] and R_Q[n] |
| SCORE_WIDTH | 64 | Score `|R[n]|²` width, fed to peak_detector |
| INDEX_WIDTH | 9 | Peak index width (0..510 needs 9 bits) |

---

## What Is Intentionally Not Implemented Yet

- **FFT block**: term1 is fed directly by the testbench (synthetic shifted copy of term2).
  Step 32 will add a PSS/SSS FFT wrapper.
- **PSS/SSS product generator**: Step 32 target.
- **Real mU/goldU ROM**: term2 is a synthetic XOR-shift32 PRNG ROM; Step 32 replaces it.
- **Board integration**: no changes to BRAM wrapper, AXI-Lite registers, or Vitis app.
- **FFT-based correlation acceleration**: Step 32+ (current implementation is direct-lag).

---

## Correlation Convention

For lag index p ∈ {0, …, 510}:

```
lag = p − 255  (signed integer shift)

n_start = 0        if lag ≥ 0
          −lag     if lag < 0

n_end   = 255−lag  if lag ≥ 0
          255      if lag < 0

corr[p] = Σ_{n=n_start}^{n_end}  term1[n + lag]  ·  conj(term2[n])
```

Complex multiply:  `term1 · conj(term2) = (a+jb)(c−jd) → real=ac+bd, imag=bc−ad`

**Test vector convention**: for desired shift s, testbench sets:
```
term1[n] = term2[n − s]  if 0 ≤ n−s < NSC
           0              otherwise
```
This produces peak at p = 255 + s, and `intCFO = p − 255 = s`. ✓

---

## RTL Interface

```verilog
module meyr_integer_cfo_core #(
    parameter NSC = 256, PROD_WIDTH = 32, ACC_WIDTH = 56,
    SCORE_WIDTH = 64, INDEX_WIDTH = 9
)(
    input  wire                         aclk, aresetn,
    input  wire                         start,
    // Streamed term1: NSC beats, in-order (index 0..NSC-1)
    input  wire                         term1_valid,
    input  wire [7:0]                   term1_index,
    input  wire signed [PROD_WIDTH-1:0] term1_i, term1_q,
    output wire                         term1_ready,
    // Outputs
    output reg                          busy, done, error,
    output reg signed [15:0]            int_cfo,
    output reg [INDEX_WIDTH-1:0]        peak_index,
    output reg [SCORE_WIDTH-1:0]        peak_score
);
```

Protocol (consistent with project convention):
- Pulse `start=1` one clock. Core transitions to S_LOAD; `busy` asserts.
- Stream NSC term1 samples while `term1_ready=1`.
- After NSC samples, correlation runs automatically (no further host action).
- `done` pulses for exactly one clock; `busy` deasserts simultaneously.
- `error` is sticky (cleared only by `aresetn`); set by start-while-busy.

---

## Synthetic term2 ROM Note

The term2 ROM uses XOR-shift32 PRNG with seed `32'hCAFE_B0BB`. Each entry uses the
lower 8 bits of the PRNG state, sign-extended to PROD_WIDTH=32.

The testbench mirrors the same seed and sequence exactly. This makes all shift tests
fully deterministic — no floating-point models, no file I/O.

**To replace with real mU/goldU data in Step 32:**
1. Generate `term2_i_rom` and `term2_q_rom` offline (e.g., Python script reading `ref/receiver.c`
   reference sequences).
2. Store as `$readmemh` files or a localparam array.
3. Remove the `initial` PRNG block.

---

## Score Computation Note

Step 31 computes score from lower 32 bits of the 56-bit accumulator:
```
si = acc_i[31:0]  (safe for 8-bit synthetic data: max |acc| ≈ 2^22 << 2^31)
score = |si|² + |sq|²
```
For real FFT data (16-bit IQ, 32-bit products, max |acc| ≈ 2^47), scale accumulators
before squaring (e.g., right-shift by 16 before taking 32-bit slice).

---

## Testbench Scenarios

| Test | Shift | Expected peak_index | Expected int_cfo | Checks |
|------|-------|--------------------|----|--------|
| T1 reset_defaults | — | — | — | busy=done=error=0 |
| T2 zero_cfo | 0 | 255 | 0 | peak_index, int_cfo, score>0 |
| T3 positive_shift_plus1 | +1 | 256 | +1 | peak_index, int_cfo |
| T4 negative_shift_minus1 | −1 | 254 | −1 | peak_index, int_cfo |
| T5 positive_shift_plus3 | +3 | 258 | +3 | peak_index, int_cfo |
| T6 negative_shift_minus4 | −4 | 251 | −4 | peak_index, int_cfo |
| T7 positive_shift_plus8 | +8 | 263 | +8 | peak_index, int_cfo |
| T8 negative_shift_minus8 | −8 | 247 | −8 | peak_index, int_cfo |
| T9 restart_two_frames | 0 then +3 | 255, 258 | 0, +3 | Two consecutive runs |
| T10 start_while_busy | — | — | — | error=1 on second start |
| T11 zero_term1 | all zeros | 0 | −255 | score=0, tie→index 0 |
| T12 boundary_shifts | +2, −2 | 257, 253 | +2, −2 | Sign symmetry |

---

## Simulation Command

```bash
export PATH="/home/zealatan/Downloads/Vivado/2022.2/bin:$PATH"
bash scripts/run_meyr_integer_cfo_core_sim.sh
```

Log: `logs/meyr_integer_cfo_core_xsim.log`

---

## Current Result

```
PASS: 32   FAIL: 0
CI GATE: PASSED
```

All 12 test groups pass. Shifts from −8 to +8 verified. Error protocol verified.
Zero-input tie-break verified (index 0 wins, consistent with `peak_detector.v` strict `>` policy).

---

## Next Steps

- **Step 32**: Add PSS/SSS product generator (term1 = PSS_FFT · conj(SSS_FFT)) and replace
  the synthetic term2 ROM with real mU · conj(goldU) reference data from `ref/receiver.c`.
- **Step 33**: Add integer_cfo_estimator_top wrapping product generator + this core.
- **Step 34**: Add FFT256 wrapper/skeleton; feed corrected time-domain PSS/SSS symbols.
- **Step 35**: Integrate with corrected frame output (extend frame buffer to ≥576 samples).
