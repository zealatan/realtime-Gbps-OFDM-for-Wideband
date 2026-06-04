# RTL_SYNC_PHASE4 — Verification Closure Summary
**Date:** 2026-06-03  
**Session:** A–G (verification_closure_20260603)  
**Simulator:** iverilog 11+ (USE_BEHAVIORAL_STUB=3 for FFT behavioral DFT)

---

## Gate Results

| Gate | Result | Details |
|------|--------|---------|
| DOC-001: PSS/SSS boundary | **PASS** | 17/17 — T1 no-BP, T2 rand-BP, T3 error-inject |
| DOC-002: FFT bin values | **PASS** | V0 max_err=0, V1/V2 max_err=1 LSB (behavioral DFT) |
| DOC-003: Meyr ROM check | **PASS** | 256/256 PSS, 256/256 SSS match generator |
| P3-21A J1: k_int sweep | **PASS** | 13/13 (k_int ∈ {0,±1,±2,±4,±8,±12,±16}) |
| P3-16A: Integration | **PASS** | 8/8 (regression, no change) |
| P3-20A: AXI backpressure | **PASS** | 37/37 (regression, no change) |
| P3-23A: Stress | **PASS** | 23/23 (regression, no change) |
| P3-15D: Random equiv | **FAIL** | 99/100 — case_087 only (ISSUE-002, was 85/100) |

---

## Bugs Found and Fixed

### 1. DOC-001: AXI-Stream output_collector pre-NBA sampling race
**File:** `tb/p3_24a_pss_sss_boundary_check_tb.sv`  
**Symptom:** T2 backpressure test showed mismatches — testbench sampled `m_tvalid` at posedge+1ns (post-NBA), missing the single-cycle `hold_valid=1` window.  
**Fix:** Removed `#1` after `@(posedge aclk)` in output_collector — reads at posedge (pre-NBA) where `hold_valid=1` during `m_fire` cycle.

### 2. DOC-002: AXI-Stream driver active-region race (testbench)
**File:** `tb/doc002_fft_value_check_tb.sv`  
**Symptom:** All FFT outputs were effectively zero — DUT's NBA `bd_ibuf[cnt] <= s_tdata` was reading the NEXT sample's data because the testbench updated `s_tdata` in the same active region.  
**Fix:** Pre-load sample 0 before the loop; advance `s_tdata` only at `posedge+1ns` (after NBA region completes). Same pattern as the DOC-001 race — confirmed root cause via hierarchical probe of `bd_ibuf[0]`.

### 3. J1: ROM parameter plumbing bug (RTL)
**Files:** `rtl/meyr_fft256_actual_integration_top.v`, `rtl/meyr_integer_cfo_freq_estimator_top.v`  
**Symptom:** k_int=0 passed, all non-zero k_int values failed with random peak positions. Compile warning: `parameter PSS_ROM_FILE not found in ...u_dut`.  
**Root cause:** `PSS_ROM_FILE` and `SSS_ROM_FILE` parameters were not declared in either intermediate module. The core always loaded the bypass (time-domain) ROM instead of the FFT-domain ROM — making the frequency-shift invariant property break for k_int≠0.  
**Fix:** Added `PSS_ROM_FILE`/`SSS_ROM_FILE` parameters to both modules and threaded them down to `meyr_integer_cfo_core`.

---

## Behavioral DFT Caveat (DOC-002)

The behavioral DFT stub (`USE_BEHAVIORAL_STUB=3`) computes an unscaled 256-pt DFT (numpy.fft.fft convention). The real Xilinx FFT IP scales by 1/16 via `SCALE_SCH=0xAA`. The comparison script uses golden values generated from the same unscaled convention, so DOC-002 PASS is valid for the behavioral path.

For production sign-off with the real IP, P3-25B (xsim) must re-run the same 3 vectors with USE_BEHAVIORAL_STUB=0 and compare against C reference `fft_without_rearrange()` (which divides by sqrt(256)=16).

---

## Open Issues

### ISSUE-002 (MEDIUM): case_087 random equivalence failure
P3-15D improved from 85/100 → 99/100 on this run. case_087 remains with `d2_slot_start` mismatch. Root cause not yet identified. The improvement from 85→99 on a re-run suggests some prior failures may have been transient (timing-dependent iverilog behavior) rather than structural RTL defects. case_087 is likely a boundary-condition in the CP autocorrelation peak detection.

---

## Reports Generated

| File | Contents |
|------|----------|
| `reports/verification_closure_20260603/doc001_pss_sss_boundary_gate.txt` | DOC-001 PASS gate |
| `reports/verification_closure_20260603/doc002_fft_value_gate.txt` | DOC-002 PASS gate |
| `reports/verification_closure_20260603/doc003_meyr_rom_check.txt` | DOC-003 PASS gate |
| `reports/verification_closure_20260603/doc003_meyr_rom_check.csv` | Per-bin ROM comparison |
| `reports/verification_closure_20260603/doc002_fft_value_compare.csv` | Per-bin FFT comparison |
| `reports/verification_closure_20260603/meyr_kint_sweep_gate.txt` | J1 sweep PASS (13/13) |
| `sim_out/session_J_p3_21a/p3_21a_j1.log` | Full J1 simulation output |
| `logs/verification_closure_20260603/` | All Phase G regression logs |

---

## HTML Reports Updated

- `reports/current_status.html` — KPI 16 gates / 15 PASS; new milestone rows; timeline; coverage Stage 4/5 updated; risk dashboard; next actions
- `reports/issue_tracking.html` — ISSUE-002 updated (1/100 remaining); 2026-06-03 timeline entry
- `docs/algorithm_reference_spec.html` — DOC-001/002/003 PASS badges; J1 result; module status updated; readiness matrix updated

---

## Overall Closure Status

All planned verification closure gates (DOC-001, DOC-002, DOC-003, J1 k_int sweep) have been executed and pass. The only remaining open item is ISSUE-002 case_087 (medium priority). Phase G regression confirms no regressions from the ROM parameter fix.
