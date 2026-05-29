# Claude Code Prompt — P3-13A Real FFT / Meyr Integer CFO Preparation

## Working Directory
`/home/zealatan/RTL_SYNC_PHASE3`

## Mandatory Archival Rule
Before making any code change, save this prompt verbatim to:

`md_files/p3_13a_real_fft_meyr_prep_prompt.md`

Create `md_files/` if it does not exist.

## Context
Current Phase3 Meyr integer CFO path exists structurally:

```text
phase3_sync_top
└─ meyr_integer_cfo_fft_frontend_top
   ├─ fft256_dual_symbol_frontend
   └─ meyr_integer_cfo_freq_estimator_top
```

However previous audit found that `fft256_dual_symbol_frontend` may still be a bypass/stub path. In that case, nonzero integer CFO `k_int != 0` is mathematically impossible to validate correctly because the time-domain product cancels the frequency shift sensitivity.

The goal of this task is preparation, not risky production integration.

## Objective
Prepare the real FFT Meyr path without breaking existing Phase3 top. Create a standalone harness, ROM generator, and dry-run checks so that accurate nonzero integer CFO verification can be performed when Vivado xsim + Xilinx FFT IP are available.

## Allowed Modifications
You may create/modify:

```text
scripts/gen_meyr_fft_reference_roms.py
rtl/meyr_fft256_harness_adapter.v
tb/p3_13a_real_fft_meyr_tb.sv
scripts/run_p3_13a_real_fft_meyr_dryrun.sh
docs/p3_13a_real_fft_meyr_prep.md
md_files/p3_13a_real_fft_meyr_prep_prompt.md
```

You may read existing files:

```text
rtl/fft256_dual_symbol_frontend.v
rtl/meyr_fft256_actual_integration_top.v
rtl/meyr_integer_cfo_fft_frontend_top.v
rtl/meyr_integer_cfo_freq_estimator_top.v
vectors/*
golden/*
```

## Do NOT Modify
Do not modify production top-level files:

```text
rtl/phase3_sync_top.v
rtl/frac_cfo_frame_corrector_top.v
rtl/frame_detector.v
rtl/fft256_dual_symbol_frontend.v
rtl/meyr_integer_cfo_fft_frontend_top.v
```

Do not overwrite existing bypass-compatible ROMs.

## Tasks

### 1. Audit existing FFT frontend
Inspect:

```text
rtl/fft256_dual_symbol_frontend.v
rtl/meyr_fft256_actual_integration_top.v
```

Document whether the current production frontend is:

```text
- real FFT
- behavioral passthrough stub
- direct buffer copy bypass
- Xilinx FFT IP wrapper
```

### 2. Create frequency-domain ROM generator
Create:

```text
scripts/gen_meyr_fft_reference_roms.py
```

The script should:

```python
PSS_fft = np.fft.fft(pss_td_ref, 256)
SSS_fft = np.fft.fft(sss_td_ref, 256)
ROM[j]  = PSS_fft[j] * np.conj(SSS_fft[j])
```

Normalize to signed Q1.15 or the existing project convention.

Output to new files only:

```text
vectors/meyr_pss_fft_romhex.txt
vectors/meyr_sss_fft_romhex.txt
```

Do not overwrite existing time-domain/bypass ROMs.

### 3. Create harness adapter
Create:

```text
rtl/meyr_fft256_harness_adapter.v
```

Purpose:

```text
convert existing separate I/Q/index style test input
into the packed AXI-Stream format expected by meyr_fft256_actual_integration_top
```

Keep this standalone. Do not instantiate it inside `phase3_sync_top`.

### 4. Create standalone TB
Create:

```text
tb/p3_13a_real_fft_meyr_tb.sv
```

This TB should be able to:

```text
- feed PSS/SSS symbols
- drive integer CFO sweep cases if vectors exist
- observe done/int_cfo/peak_index
- support a stub compile mode
```

Expected behavior:

```text
With real FFT:
    peak_index = 255 + k_int
    int_cfo    = k_int

With behavioral passthrough stub:
    only compile / done behavior is checked
    do not claim k_int correctness
```

### 5. Create dry-run runner
Create:

```text
scripts/run_p3_13a_real_fft_meyr_dryrun.sh
```

It should check:

```text
- Vivado/xsim availability
- Xilinx FFT IP availability
- existence of required RTL files
- existence of generated FFT ROMs
- whether current run is accurate or stub-only
```

If Vivado/IP unavailable, print:

```text
CI_GATE: BLOCKED_REAL_FFT_UNAVAILABLE
```

If only iverilog/stub compile succeeds, print:

```text
SANITY_GATE: PASS (stub compile only)
```

Never print official PASS unless real FFT + xsim + ROM-based k_int sweep actually passes.

### 6. Documentation
Create:

```text
docs/p3_13a_real_fft_meyr_prep.md
```

Include:

```text
- current FFT frontend status
- why bypass cannot validate k_int != 0
- new ROM format and scaling
- harness adapter role
- TB/runner usage
- exact blockers for official validation
```

## Pass Criteria
Complete only if:

```text
1. ROM generator exists and does not overwrite old ROMs
2. standalone harness adapter exists
3. standalone TB exists
4. dry-run script reports accurate blocking state
5. documentation clearly separates stub sanity from real FFT validation
6. no production top files are modified
```

## Final Response Format
Return:

```text
P3-13A Final Status

1. Changed Files
2. FFT Frontend Audit Result
3. ROM Generation Result
4. Harness/TB Result
5. Runner Result
6. Remaining Blockers
7. Recommended Next Step
```
