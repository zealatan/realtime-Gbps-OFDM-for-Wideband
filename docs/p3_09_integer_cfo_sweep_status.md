# P3-09 — Integer CFO Sweep Status

**Date:** 2026-05-28  
**Overall Status:** INFRASTRUCTURE READY — Execution BLOCKED on real FFT integration

---

## What Is Ready

| Artifact | Status | Path |
|----------|--------|------|
| Sweep plan | DONE | `docs/p3_09_integer_cfo_sweep_plan.md` |
| Session archive | DONE | `md_files/p3_09_integer_cfo_sweep_prep_prompt.md` |
| Vector generator | DONE (skeleton) | `scripts/gen_phase3_integer_cfo_sweep_vectors.py` |
| Compare script | DONE (skeleton) | `scripts/compare_p3_09_integer_cfo_sweep.py` |
| Run script | DONE (blocked guard) | `scripts/run_p3_09_integer_cfo_sweep.sh` |
| Stimulus vectors | NOT YET | Run generator to create `golden/p3_09_sweep/*.mem` |
| Simulation results | NOT YET | Blocked on real FFT |

---

## Blocker: Bypass FFT Cannot Test k_int≠0

The `fft256_dual_symbol_frontend.v` S_COMPUTE state is a bypass stub that copies
time-domain input buffers to the "FFT output" buffers unchanged.

**Why this blocks the sweep:** The Meyr integer CFO estimator identifies the CFO
from a cross-correlation lag in the frequency domain. With bypass, the core receives
time-domain data. The integer CFO rotation applied to the stimulus cancels exactly in
the PSS×conj(SSS) cross-product:

```
term1_shifted[j] = PSS_td_ref[j] · exp(j·2π·k·j/N) × conj(SSS_td_ref[j] · exp(j·2π·k·j/N))
                 = PSS_td_ref[j] × conj(SSS_td_ref[j])   ← phase cancels
                 = term1_ref[j]
```

Result: bypass mode always produces `peak_index=255` and `int_cfo=0` for all k_int.

---

## Current Simulation Status

| Case | k_int | Expected peak | Expected word | Simulation | Compare |
|------|-------|---------------|---------------|------------|---------|
| km8  |    -8 |           247 |  +134217728   | NOT RUN    | BLOCKED |
| km4  |    -4 |           251 |   +67108864   | NOT RUN    | BLOCKED |
| km2  |    -2 |           253 |   +33554432   | NOT RUN    | BLOCKED |
| km1  |    -1 |           254 |   +16777216   | NOT RUN    | BLOCKED |
| k0   |     0 |           255 |             0 | **PASS** (P3-08) | N/A |
| kp1  |    +1 |           256 |   -16777216   | NOT RUN    | BLOCKED |
| kp2  |    +2 |           257 |   -33554432   | NOT RUN    | BLOCKED |
| kp4  |    +4 |           259 |   -67108864   | NOT RUN    | BLOCKED |
| kp8  |    +8 |           263 |  -134217728   | NOT RUN    | BLOCKED |

k_int=0 was validated in P3-08 (CI_GATE PASS, iverilog 11.0).

---

## Dependencies

| Requirement | Status | Notes |
|-------------|--------|-------|
| P3-08 baseline (k_int=0) | **DONE** | 10/10 checks PASS, P3-08 session |
| Real FFT backend | **BLOCKED** | `fft256_dual_symbol_frontend.v` S_COMPUTE must compute actual DFT |
| Frequency-domain ROM | **BLOCKED** | PSS_rom[j] = DFT(PSS_ref)[j] × conj(DFT(SSS_ref)[j]) |
| Sweep vectors generated | NOT YET | Run `gen_phase3_integer_cfo_sweep_vectors.py` |

---

## How to Unblock

### Step A — Integrate real FFT

Options (from `docs/p3_07_pss_sss_meyr_backend_validation.md`):

1. **Wire `meyr_fft256_actual_integration_top.v`** into `phase3_sync_top.v` in place
   of the current `meyr_integer_cfo_fft_frontend_top` unit_test version.
   Use `USE_BEHAVIORAL_STUB=1` parameter to enable iverilog-compatible simulation.

2. **Replace S_COMPUTE** in `fft256_dual_symbol_frontend.v` with an actual 256-point
   DFT implementation (behavioral for simulation, IP for synthesis).

### Step B — Regenerate reference ROMs for frequency domain

```python
PSS_fft = np.fft.fft(pss_td_ref, n=NSC)    # DFT of PSS OFDM symbol
SSS_fft = np.fft.fft(sss_td_ref, n=NSC)    # DFT of SSS OFDM symbol
term1_fft[j] = PSS_fft[j] * np.conj(SSS_fft[j])
PSS_rom[j]   = term1_fft[j]  normalized to Q1.15
SSS_rom_I[j] = +32767   (sign = +1, same convention as P3-08)
```

With frequency-domain ROM and real FFT, the correlation peaks at `lag = k_int`,
giving `peak_index = 255 + k_int` for each case.

### Step C — Run sweep

```bash
# Generate vectors (creates golden/p3_09_sweep/*.mem and manifest.json)
python3 scripts/gen_phase3_integer_cfo_sweep_vectors.py

# Run sweep (will BLOCKED until Steps A+B complete)
bash scripts/run_p3_09_integer_cfo_sweep.sh
```

---

## No RTL Modified in This Session

All files created by P3-09 are in:
- `md_files/` — mandatory archive
- `docs/` — plans and status
- `scripts/` — generator, compare, runner

No changes to `rtl/`, `tb/`, `vectors/`, or any existing golden/simulation file.
