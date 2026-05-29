# P3-07 — PSS/SSS Extraction + FFT/Meyr Backend Validation (Archive)

## Original Prompt

Role: Claude — P3-07 PSS/SSS Extraction + FFT/Meyr Backend Validation Owner.

Mandatory archive: md_files/p3_07_pss_sss_meyr_backend_validation_prompt.md (this file).

[Full prompt as provided — validates PSS/SSS extraction, FFT frontend status, ROM status,
Meyr integer CFO status after the passing P3-05C front-end synchronizer.]

---

## Interpretation

P3-05C confirmed that PSS_START=32 and SSS_START=320 match the golden. This step
audits the backend path that consumes those windows (FFT + integer CFO estimator)
and adds sample-level monitoring for PSS/SSS extraction observability.

---

## Files Inspected

- rtl/phase3_sync_top.v                          — hierarchy wiring
- rtl/pss_sss_symbol_extractor.v                 — extraction logic (functional)
- rtl/unit_test/meyr_integer_cfo_fft_frontend_top.v — sim path FFT frontend
- rtl/unit_test/fft256_dual_symbol_frontend.v    — FFT PLACEHOLDER (bypass stub)
- rtl/meyr_fft256_actual_integration_top.v       — full FFT top (NOT in sim path)
- rtl/fft256_xilinx_wrapper.v                    — Xilinx FFT IP wrapper (not used)
- rtl/meyr_integer_cfo_core.v                    — correlator, uses ROM via $readmemh
- rtl/meyr_pss_sss_product_gen.v                 — PSS×conj(SSS) product (functional)
- vectors/meyr_pss_reference_romhex.txt          — 256 × 00000000 (STUB)
- vectors/meyr_sss_reference_romhex.txt          — 256 × 00000000 (STUB)
- scripts/golden_dump.c                          — PSS_START=CP_LEN, SSS_START=2*CP_LEN+NSC
- scripts/compare_golden_rtl.py                  — compare script
- tb/phase3_sync_reference_compare_tb.sv         — existing TB

---

## Key Findings

### 1. FFT Frontend: BYPASS STUB
File: rtl/unit_test/fft256_dual_symbol_frontend.v

S_COMPUTE state (the "FFT" step):
  for (_k = 0; _k < FFT_LEN; _k++) begin
    fft_pss_i[_k] <= pss_buf_i[_k];   // INPUT COPY — no computation
    fft_pss_q[_k] <= pss_buf_q[_k];
    ...
  end

Time-domain samples are passed unchanged as "frequency-domain bins".
Integer CFO estimation therefore operates on time-domain data, not frequency-domain.

### 2. Reference ROMs: ALL ZEROS
Files: vectors/meyr_pss_reference_romhex.txt, vectors/meyr_sss_reference_romhex.txt

Both files: 256 lines of "00000000".
meyr_integer_cfo_core.v loads these with $readmemh().
With PSS=0 and SSS=0:
  - term2_i_rom[j] = 0 for all j (sss_i_val=0 >= 0 triggers positive branch)
  - term2_q_rom[j] = 0 for all j
  - Correlation of any term1 against all-zero term2 = 0 for all lags
  - Argmax returns undefined index (observed: peak_index=256 → int_cfo=1 → step_word=-2^24=-16777216)

### 3. meyr_fft256_actual_integration_top: NOT IN SIM PATH
File: rtl/meyr_fft256_actual_integration_top.v

This module wraps fft256_xilinx_wrapper with proper PSS/SSS buffering, FFT streaming,
flush logic, and capture. It is NOT instantiated in phase3_sync_top.v.
phase3_sync_top uses meyr_integer_cfo_fft_frontend_top (bypass stub path).

### 4. PSS/SSS Extraction: FUNCTIONALLY CORRECT
File: rtl/pss_sss_symbol_extractor.v

pss_fft_start = CP_LEN = 32       → PSS window: frame_idx [32..287]
sss_fft_start = 2*CP_LEN+NSC = 320 → SSS window: frame_idx [320..575]
Both already verified in P3-05C: RTL PSS_START=32 ✓, SSS_START=320 ✓.
P3-07 adds: sample count verification (expected 256 each).

### 5. Integer CFO: BLOCKED (two independent reasons)
Blocker 1: FFT is bypass → freq-domain data ≠ time-domain samples
Blocker 2: term2 ROM is all zeros → correlation always zero → argmax invalid

---

## Planned Modifications

### tb/phase3_sync_reference_compare_tb.sv
- Add PSS/SSS extraction monitoring via hierarchy access (u_dut.ext_m_*)
- Capture PSS/SSS first/last sample IQ values and sample counts
- Capture Meyr peak index via u_dut.u_meyr_fft.peak_index
- Add new fields to rtl_results.txt

### scripts/golden_dump.c
- Add PSS_SAMPLE_COUNT (=NSC=256) and SSS_SAMPLE_COUNT (=NSC=256) to golden output

### scripts/compare_golden_rtl.py
- Add PSS_SAMPLE_COUNT and SSS_SAMPLE_COUNT comparison checks

### docs/p3_07_pss_sss_meyr_backend_validation.md
- Full backend audit with findings, blockers, and replacement plan

---

## ROM Replacement Plan (to unblock integer CFO)

Step 1: Generate real PSS/SSS reference sequences
  PSS: Zadoff-Chu sequence for LTE/NR PSS (u=25 for NR, u=25/29/34 for LTE)
  SSS: BPSK-modulated Gold code sequence for SSS
  term2[j] = PSS_ref[j] × sign(SSS_ref_I[j]) (Q1.15, {Q[31:16], I[15:0]} packing)

Step 2: Populate vectors/meyr_pss_reference_romhex.txt and meyr_sss_reference_romhex.txt
  Each file: 256 lines of 8-digit hex (32-bit = {Q_I16[31:16], I_I16[15:0]})

Step 3: Replace meyr_integer_cfo_fft_frontend_top with meyr_fft256_actual_integration_top
  in phase3_sync_top.v (with USE_BEHAVIORAL_STUB=1 for simulation without Xilinx IP)

Step 4: Add a Python DFT model in the testbench or gen script to inject correct
  frequency-domain values (since USE_BEHAVIORAL_STUB still bypasses FFT computation)

Step 5: With INT_CFO=0 in the IQ stimulus, verify integer_cfo_word = 0 (peak at index 255)

---

## Summary

- PSS/SSS extraction: PASS (start indices correct; counts verified in this step)
- FFT frontend: BLOCKED (bypass stub — time-domain data fed as frequency bins)
- Reference ROMs: BLOCKED (all zeros)
- Integer CFO: BLOCKED (both FFT and ROM must be replaced)
- Recommended next step: P3-08 ROM generation + DFT injection to validate integer CFO

---

## Files Modified

- md_files/p3_07_pss_sss_meyr_backend_validation_prompt.md (this file)
- tb/phase3_sync_reference_compare_tb.sv (PSS/SSS monitoring)
- scripts/golden_dump.c (PSS_SAMPLE_COUNT + SSS_SAMPLE_COUNT)
- scripts/compare_golden_rtl.py (count checks)
- docs/p3_07_pss_sss_meyr_backend_validation.md (status doc)
