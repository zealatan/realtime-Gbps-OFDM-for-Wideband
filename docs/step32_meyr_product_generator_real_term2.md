# Step 32 — Meyr PSS/SSS Product Generator and term2 Reference ROM

## Objective

Add the product-generation layer for the Meyr integer CFO estimator before FFT integration:

1. `meyr_pss_sss_product_gen.v` — computes `term1[j] = PSS_FFT[j] * conj(SSS_FFT[j])`
2. `meyr_term2_ref_rom.v` — term2 reference ROM (`mU * conj(goldU)`); synthetic PRNG fallback
3. `meyr_integer_cfo_freq_estimator_top.v` — wrapper connecting product_gen → term1 buffer → Meyr core

No FFT IP is used. The testbench supplies synthetic PSS_FFT / SSS_FFT vectors directly.

---

## Relationship to Step 30 and Step 31

Step 30 defined the full Meyr algorithm verified against `ref/receiver.c`:

```
term1[j] = PSS_FFT[j] · conj(SSS_FFT[j])          (C ref: lines 523-525)
term2[j] = mU[j+CP_LEN] · conj(goldU[j+CP_LEN])    (C ref: lines 527-528)
R[n]     = Σ_j conj(term2[j]) · term1[j+n]
intCFO   = argmax_n |R[n]|² − 255
```

Step 31 verified the core correlation engine with a synthetic PRNG term2 ROM (no PSS/SSS layer).

Step 32 adds the PSS/SSS product-generation layer above the Step 31 core, completing the frequency-domain estimator path. No changes to the Step 31 core are required.

---

## C-Reference Formulas

From `ref/receiver.c` lines 523-528:

```c
// term1 = PSS_FFT * conj(SSS_FFT)
crossCorrTerm1I[j] = signalPSSfftI[j]*signalSSSfftI[j] + signalPSSfftQ[j]*signalSSSfftQ[j];
crossCorrTerm1Q[j] = -signalPSSfftI[j]*signalSSSfftQ[j] + signalPSSfftQ[j]*signalSSSfftI[j];

// term2 = mU * conj(goldU)
crossCorrTerm2I[j] = mUI[j+CP_LEN]*goldUI[j+CP_LEN] + mUQ[j+CP_LEN]*goldUQ[j+CP_LEN];
crossCorrTerm2Q[j] = -mUI[j+CP_LEN]*goldUQ[j+CP_LEN] + mUQ[j+CP_LEN]*goldUI[j+CP_LEN];
```

Both formulas follow: `(a+jb)(c-jd) → real=ac+bd, imag=bc-ad`.

---

## Product Generator Arithmetic (`meyr_pss_sss_product_gen.v`)

| Signal | Formula |
|--------|---------|
| `term1_i` | `pss_i * sss_i + pss_q * sss_q` |
| `term1_q` | `pss_q * sss_i - pss_i * sss_q` |

**Pipeline**: 1-clock latency. Stage 1 registers inputs; stage 2 captures product. Backpressure supported via `m_ready`.

**Width**: IQ_WIDTH=16 inputs, PROD_WIDTH=32 outputs. 33-bit intermediate accumulators prevent sum-of-products overflow.

---

## term2 ROM Source (`meyr_term2_ref_rom.v`)

### Real mU/goldU-derived term2 ROM: **PENDING**

In `ref/receiver.c`, `mUI`, `mUQ`, `goldUI`, `goldUQ` are passed as external parameters to `synchronization()` and `carrierFreqOffsetEstMeyr()`. Their generation code is not present in `ref/receiver.c`. Extracting exact values requires the full transmitter/generator source, which is outside the current scope.

### Synthetic fallback ROM: **implemented and verified** (`USE_SYNTHETIC_FALLBACK=1`)

Uses the same XOR-shift32 PRNG as `meyr_integer_cfo_core.v` (seed `32'hCAFE_B0BB`). This ensures that the estimator top and testbench are internally consistent for shift-recovery tests.

**To replace with real mU/goldU data (Step 33+)**:
1. Generate ROM contents offline: `term2_i[j] = mU_i[j+CP_LEN]*goldU_i[j+CP_LEN] + mU_q[j+CP_LEN]*goldU_q[j+CP_LEN]`
2. Store in `$readmemh` files or `localparam` arrays.
3. Set `USE_SYNTHETIC_FALLBACK=0` and remove the PRNG `initial` block.

---

## Frequency Estimator Top Architecture (`meyr_integer_cfo_freq_estimator_top.v`)

```
PSS_FFT / SSS_FFT stream (s_valid/s_ready, NSC pairs)
  ↓
meyr_pss_sss_product_gen (1-cycle latency)
  ↓
term1_buf[256] (I/Q register arrays)
  ↓
meyr_integer_cfo_core (Step 31, internal PRNG term2 ROM)
  ↓
int_cfo / peak_index / peak_score
```

**meyr_term2_ref_rom** is instantiated as an architecture placeholder for Step 33+ external term2 routing. The core uses its own identical PRNG ROM in this step.

### FSM States

| State | Action |
|-------|--------|
| S_IDLE | Wait for `start` |
| S_RECV | Collect NSC PSS/SSS pairs through product_gen; fill term1_buf |
| S_START_CORE | Pulse `core.start`; initialize stream counter |
| S_STREAM | Stream term1_buf to core combinatorially when `term1_ready` |
| S_WAIT_CORE | Wait for `core.done` |
| S_DONE | Pulse `done`; deassert `busy` |

**Core connections**: term1 values are fed combinatorially (`assign core_term1_valid = (state == S_STREAM)`, direct array reads). The core latches each sample in its S_LOAD state on the clock edge.

---

## Testbench Scenarios

### `meyr_pss_sss_product_gen_tb.sv` (13 checks)

| Test | Inputs | Expected | Result |
|------|--------|---------|--------|
| T1 reset_defaults | — | m_valid=0 | PASS |
| T2 real_multiply | PSS=2+j0, SSS=3+j0 | term1=6+j0 | PASS |
| T3 conjugate | PSS=1+j2, SSS=3+j4 | term1=11+j2 | PASS |
| T4 negative | PSS=-3+j0, SSS=2+j0 | term1=-6+j0 | PASS |
| T5 index_preservation | index=77 | m_index=77 | PASS |
| T6 unit_sss | PSS=7+j5, SSS=1+j0 | term1=7+j5 | PASS |
| T7 sss_imaginary | PSS=3+j4, SSS=0+j1 | term1=4-j3 | PASS |
| T8 backpressure | m_ready=0 | s_ready deasserts | PASS |

### `meyr_integer_cfo_freq_estimator_top_tb.sv` (32 checks)

**Note**: All shift tests use synthetic PRNG term2 ROM. PSS_FFT[n] = term2[n-s], SSS_FFT[n] = 1+j0; so term1[n] = PSS_FFT[n], identical to the Step 31 testbench vectors.

| Test | Shift | Expected peak_index | Expected int_cfo | Result |
|------|-------|---------------------|-----------------|--------|
| T1 reset_defaults | — | — | — | PASS |
| T2 zero_cfo | 0 | 255 | 0 | PASS |
| T3 positive_shift_plus1 | +1 | 256 | +1 | PASS |
| T4 negative_shift_minus1 | −1 | 254 | −1 | PASS |
| T5 positive_shift_plus3 | +3 | 258 | +3 | PASS |
| T6 negative_shift_minus4 | −4 | 251 | −4 | PASS |
| T7 positive_shift_plus8 | +8 | 263 | +8 | PASS |
| T8 negative_shift_minus8 | −8 | 247 | −8 | PASS |
| T9 restart_two_frames | 0, +3 | 255, 258 | 0, +3 | PASS |
| T10 start_while_busy | — | — | error=1 | PASS |
| T11 zero_pss_input | all zeros | 0 | −255 | PASS |
| T12 index_alignment | +2, −2 | 257, 253 | +2, −2 | PASS |

---

## Simulation Commands

```bash
export PATH="/home/zealatan/Downloads/Vivado/2022.2/bin:$PATH"

# Product generator unit test
bash scripts/run_meyr_pss_sss_product_gen_sim.sh
# Log: logs/meyr_pss_sss_product_gen_xsim.log

# Estimator top integration test
bash scripts/run_meyr_integer_cfo_freq_estimator_top_sim.sh
# Log: logs/meyr_integer_cfo_freq_estimator_top_xsim.log
```

---

## Simulation Results

```
meyr_pss_sss_product_gen_tb:
  PASS: 13   FAIL: 0
  CI GATE: PASSED

meyr_integer_cfo_freq_estimator_top_tb:
  PASS: 32   FAIL: 0
  CI GATE: PASSED
```

Step 31 regression: `meyr_integer_cfo_core.v` was not modified; regression not required.

---

## Known Limitations

1. **Real mU/goldU ROM pending**: The term2 ROM uses a synthetic PRNG fallback. Actual mU/goldU sequences must be sourced from the transmitter codebase and loaded via `$readmemh` or a localparam array.

2. **Score scaling**: The 56-bit accumulator lower-32-bit squaring scheme is safe for the current 8-bit synthetic data. With real 16-bit FFT outputs, accumulators must be scaled before squaring (right-shift by ≥16).

3. **No FFT**: PSS_FFT and SSS_FFT are fed directly by the testbench. FFT frontend integration is Step 34+.

4. **meyr_term2_ref_rom.v not yet connected to core**: Exists as an architecture placeholder. The core reads its own internal PRNG ROM. External term2 routing requires a future core refactor (Option A or B from Step 32 design plan).

---

## Next Steps

- **Step 33**: Complete real mU/goldU ROM extraction (requires transmitter sequence source) OR consolidate the Meyr estimator top for FFT frontend connection.
- **Step 34**: Add FFT256 wrapper feeding PSS/SSS frequency-domain samples to the estimator top.
- **Step 35**: Extend frame buffer to ≥576 samples to cover both PSS and SSS symbols.
