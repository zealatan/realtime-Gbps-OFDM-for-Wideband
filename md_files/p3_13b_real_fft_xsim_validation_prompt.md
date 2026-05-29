# Claude Code Prompt — P3-13B Real FFT xsim Validation + Integer CFO Sweep

## Working Directory
`/home/zealatan/RTL_SYNC_PHASE3`

## Mandatory Archival Rule
Save this prompt to:
`md_files/p3_13b_real_fft_xsim_validation_prompt.md`
before any work.

---

# Context

P3-13A already completed:

```text
✔ FFT-domain ROM generator
✔ meyr_fft256_harness_adapter.v
✔ standalone TB
✔ dry-run infrastructure
✔ bypass vs real-FFT audit
```

Current blocker:

```text
real Xilinx FFT IP + xsim validation
```

The current production frontend:

```text
fft256_dual_symbol_frontend.v
```

still behaves as a bypass/stub.

The goal of this task is NOT architectural redesign.

The goal is:

```text
obtain the first true integer CFO validation
using real FFT behavior
```

---

# Objective

Validate the real FFT Meyr path using:

```text
Vivado xsim
Xilinx FFT IP
frequency-domain ROMs
integer CFO sweep vectors
```

and prove:

```text
peak_index = 255 + k_int
int_cfo    = k_int
```

for multiple nonzero integer CFO cases.

---

# Allowed Modifications

You may modify/create:

```text
rtl/fft256_xilinx_wrapper.v
rtl/meyr_fft256_actual_integration_top.v

tb/p3_13a_real_fft_meyr_tb.sv

scripts/run_p3_13b_real_fft_xsim.sh

docs/p3_13b_real_fft_validation.md

md_files/p3_13b_real_fft_xsim_validation_prompt.md
```

You may generate Vivado FFT IP collateral if required.

---

# Do NOT Modify

Do NOT modify:

```text
rtl/phase3_sync_top.v
rtl/frame_detector.v
rtl/frac_cfo_frame_corrector_top.v
rtl/phase3_axi_lite_regs.v
rtl/phase3_sync_axis_dma_wrapper.v
```

Do not modify bypass ROMs.

---

# Tasks

## 1. Verify real FFT IP instantiation

Confirm `fft256_xilinx_wrapper.v` actually instantiates `xfft_v9_x` or equivalent.
Verify USE_BEHAVIORAL_STUB=0 path works in xsim.
Document exact FFT configuration: 256-pt, streaming/burst, scaling schedule, latency.

## 2. Generate/import FFT IP

If missing: create_ip / generate_target for 256-point FFT.
Store generated collateral in project-local IP directory.
Document exact Vivado version.

## 3. Run real FFT integer CFO sweep

Use vectors/meyr_pss_fft_romhex.txt and vectors/meyr_sss_fft_romhex.txt.
Run sweep: k_int = 0, ±1, ±2, ±4, ±8.
Required checks: peak_index = 255 + k_int, int_cfo = k_int.
Measure: latency, done timing, peak magnitude.

## 4. Detect sign/bin convention mismatch

Explicitly verify FFT ordering, negative-bin mapping, signed peak index interpretation.
If mismatch: document exact convention.

## 5. Create official xsim runner

Create scripts/run_p3_13b_real_fft_xsim.sh.
Required outputs: OFFICIAL_GATE: PASS or OFFICIAL_GATE: FAIL.
Never print PASS unless real FFT + nonzero k_int cases pass.

## 6. Documentation

Create docs/p3_13b_real_fft_validation.md.

---

# Pass Criteria

Complete only if:

```text
1. Real Xilinx FFT path runs under xsim
2. Nonzero k_int cases execute
3. peak_index tracks k_int correctly
4. int_cfo tracks k_int correctly
5. official runner exists
6. docs exist
```

---

# Final Response Format

```text
P3-13B Final Status

1. Changed Files
2. FFT IP Configuration
3. Integer CFO Sweep Results
4. xsim Validation Result
5. Remaining Risks
6. Recommended Next Step
```
