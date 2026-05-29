# P3-11 — Real FFT / Meyr Actual Path Audit (Mandatory Archive)

**Session:** P3-11  
**Role:** Claude-C — Real FFT / Meyr Actual Path Audit Owner  
**Date:** 2026-05-28  
**Status:** INVESTIGATION ONLY — No production RTL modified

---

## Full Prompt (verbatim)

```
ROLE: Claude-C — P3-11 Real FFT / Meyr Actual Path Audit Owner
WORKSPACE: /home/zealatan/RTL_SYNC_PHASE3

MANDATORY ARCHIVAL RULE: Before making any changes, create:
  md_files/p3_11_real_fft_meyr_path_audit_prompt.md

[BACKGROUND, GOAL, TASKS, DO NOT MODIFY, PASS CRITERIA as specified in prompt]
```

The full prompt covers:
- P3-08 brought up Meyr for integer CFO = 0 using ROMs compatible with the bypass FFT path
- fft256_dual_symbol_frontend.v is still a bypass/stub (S_COMPUTE copies buffers unchanged)
- Integer CFO sweep for k_int != 0 requires real FFT integration
- P3-09 identified real FFT integration as the unblock prerequisite
- This session is investigation, documentation, and implementation planning only

---

## Interpretation

This session audits the real FFT / Meyr integration path end-to-end:
1. Inspect all relevant RTL, scripts, docs, and vector files
2. Document bypass vs real FFT paths with module-level detail
3. Analyze ROM regeneration requirements for frequency-domain operation
4. Compare meyr_fft256_actual_integration_top vs meyr_integer_cfo_fft_frontend_top interfaces
5. Recommend an integration option (A/B/C)
6. Create implementation plan and optional dry-run script

No RTL is modified. No simulation PASS is faked.

---

## Files Inspected

### RTL
| File | Purpose | Key Finding |
|------|---------|-------------|
| `rtl/phase3_sync_top.v` | Production orchestration top | Instantiates meyr_integer_cfo_fft_frontend_top (unit_test) |
| `rtl/unit_test/meyr_integer_cfo_fft_frontend_top.v` | Bypass FFT + estimator wrapper | 6-state FSM; uses separate s_i/s_q ports; contains fft256_dual_symbol_frontend |
| `rtl/unit_test/fft256_dual_symbol_frontend.v` | FFT frontend stub | S_COMPUTE: buffer copy bypass, `// FFT PLACEHOLDER` comment |
| `rtl/meyr_fft256_actual_integration_top.v` | Real FFT integration top (Step 42-B) | 12-state FSM; packed AXI-Stream input; USE_BEHAVIORAL_STUB parameter; NOT in sim path |
| `rtl/fft256_xilinx_wrapper.v` | Xilinx FFT IP wrapper (3 modes) | STUB=0: requires fft256_xilinx IP; STUB=1: passthrough; STUB=2: sequential |
| `rtl/meyr_integer_cfo_freq_estimator_top.v` | Estimator (Step 32) | 6-state FSM; accepts PSS/SSS pairs; calls product_gen + core |
| `rtl/meyr_integer_cfo_core.v` | Correlation core (Step 31) | 511-lag correlation; $readmemh ROMs at init; peak_detector instance |
| `rtl/meyr_pss_sss_product_gen.v` | term1 = PSS×conj(SSS) | 1-clock pipeline; PROD_WIDTH=32; truncates to lower bits |

### Scripts
| File | Purpose |
|------|---------|
| `scripts/gen_meyr_reference_roms.py` | Generates bypass-compatible ROMs from time-domain stimulus |
| `scripts/gen_phase3_integer_cfo_sweep_vectors.py` | Generates 9 k_int sweep .mem files |
| `scripts/run_p3_09_integer_cfo_sweep.sh` | Sweep runner with Guard 2 (FFT PLACEHOLDER check) |

### Vectors
| File | Status |
|------|--------|
| `vectors/meyr_pss_reference_romhex.txt` | 256 entries, non-zero Q1.15 cross-products (bypass-compatible) |
| `vectors/meyr_sss_reference_romhex.txt` | 256 entries, all `00007fff` (sign=+1) |

### Docs
| File | Key Fact |
|------|----------|
| `docs/p3_07_pss_sss_meyr_backend_validation.md` | Confirmed bypass stub; meyr_fft256_actual_integration_top NOT in sim path |
| `docs/p3_08_meyr_backend_bringup.md` | CI_GATE PASS (10/10 checks) for k_int=0 bypass-compatible path |
| `docs/p3_09_integer_cfo_sweep_plan.md` | Sweep plan; execution BLOCKED on real FFT |
| `docs/p3_09_integer_cfo_sweep_status.md` | 8 of 9 cases BLOCKED; k_int=0 PASS (P3-08) |

### IP/Tool Status
| Item | Status |
|------|--------|
| `ip/fft256_xilinx/` directory | NOT PRESENT on build host |
| `fft256_xilinx.v` / `.veo` | NOT FOUND |
| xsim / Vivado | NOT INSTALLED |
| iverilog 11.0 | Available at /usr/bin/iverilog |

---

## Planned Modifications

**NONE to RTL, vectors, or golden files.**

Created only:
1. `md_files/p3_11_real_fft_meyr_path_audit_prompt.md` — this file
2. `docs/p3_11_real_fft_meyr_path_audit.md` — full audit document
3. `docs/p3_11_real_fft_meyr_integration_plan.md` — implementation plan
4. `scripts/run_p3_11_real_fft_meyr_dryrun_xsim.sh` — dry-run script skeleton

---

## Final Summary

- **Current path**: bypass stub (fft256_dual_symbol_frontend copies buffers; ROMs are time-domain cross-products; k_int=0 validated)
- **Real FFT path**: meyr_fft256_actual_integration_top wraps fft256_xilinx_wrapper → requires Xilinx IP or USE_BEHAVIORAL_STUB
- **Interface gap**: packed AXI-Stream (actual integration top) vs separate s_i/s_q (frontend top) — requires adapter or new harness
- **ROM gap**: current ROMs are time-domain compatible; real FFT needs DFT-domain cross-products
- **Recommended option**: Option C — separate test harness (does not touch any production RTL or unit_test RTL)
- **Simulation blocker**: no Xilinx FFT IP present; USE_BEHAVIORAL_STUB=1 enables compile but not accurate CFO; Vivado xsim + IP needed for accurate k_int sweep
- **Synthesis blocker**: Vivado not installed; fft256_xilinx IP not generated
