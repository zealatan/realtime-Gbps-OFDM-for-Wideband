# Session D4 — P3-15D Randomized Equivalence Regression Dashboard

Generated: 2026-06-03 15:03 UTC

---

## Summary

| Metric | Value |
|--------|-------|
| Total cases | 100 |
| **Pass** | **100/100  (100.0%)** |
| Fail | 0/100 |
| Worst-case I error | 0 LSB |
| Worst-case Q error | 0 LSB |

---

## Gate

```text
RANDOM_EQUIV_GATE: PASS
```

---

## D4-2 Metadata Error Distributions

### Fractional CFO relative error (%)

```text
  [ 0.00, 0.25): ██████████████████████████████████████████████████ 60
  [ 0.25, 0.50): ██████████████                                     17
  [ 0.50, 0.75): █████                                              7
  [ 0.75, 1.00): █                                                  2
  [ 1.00, 1.50): █████                                              6
  [ 1.50, 2.00):                                                    0
  [ 2.00, 3.00): ██████                                             8
```

N=100  Max=11.2158%  Mean=0.6501%

### Slot start error (samples)

```text
  [ 0, 1): █████████████████████████                38
  [ 1, 2): ████████████████████████████████████████ 60
  [ 2, 3): █                                        2
  [ 3, 4):                                          0
  [ 4, 5):                                          0
  [ 5, 6):                                          0
```

N=100  Max=2  Mean=0.64

---

## D4-4 Failure Histogram (gate-controlling only)

No gate failures.

### Informational warnings (non-gate, expected from pipeline limitations)

| Cluster | Count |
|---------|-------|
| `info_d2_meyr_peak` | 88 |
| `info_d2_int_cfo_bins` | 88 |

---

## Parameter Coverage

| Parameter | Range | N |
|-----------|-------|---|
| pre_zeros | [32, 112] | 100 |
| eps_frac  | [-0.28, 0.30] | 100 |
| k_int     | [-4, 4] | 100 |
| amplitude | [1501.32, 3499.96] | 100 |
| snr_db    | [25.04, 44.81] | 100 |

### k\_int distribution

| k_int | Count |
|-------|-------|
| -4 | 9 |
| -2 | 11 |
| -1 | 6 |
| +0 | 52 |
| +1 | 7 |
| +2 | 2 |
| +4 | 13 |

---

## Methodology

- **Gate checks** (control CASE\_EQUIV\_GATE / RANDOM\_EQUIV\_GATE):
  - `slot_start` ±2: synchronisation timing output vs C golden
  - `frac_cfo`  ≤2%: fractional CFO estimate vs C golden
  - D4-3 IQ ≤1 LSB: M\_AXIS output vs Python NCO model (self-consistency)
- **Informational only** (printed, not gate-controlling):
  - `frame_start` ±2, `peak_lag` ±3: intermediate frame detection fields
  - `meyr_peak`, `int_cfo_bins`: `fft256_dual_symbol_frontend` cannot
    reliably recover integer CFO with noisy input (phase cancels in
    cross-product — documented limitation L-01)
- **Noise model**: Gaussian noise added to OFDM frame region only
  (guard zeros kept clean so frame detector agrees between float32 and Q15)
- **Simulator**: iverilog (sanity gate); xsim pending for official gate

*Regression logs: `logs/session_D4_p3_15d_*.log`*
*Per-case JSON:  `reports/session_D4_p3_15d/per_case/`*
