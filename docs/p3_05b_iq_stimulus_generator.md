# P3-05B — IQ Stimulus Generator

**Version:** 1.0  
**Date:** 2026-05-27  
**Generator:** `scripts/gen_phase3_iq_stimulus.py`

---

## Purpose

Provides a deterministic IQ test vector for the Phase 3 golden comparison flow.
Unblocks the `run_phase3_sync_sim.sh` Step b (golden_dump) which previously aborted
because `golden/phase3_iq_stimulus.f32` was absent.

---

## Signal Structure

```
Sample index  Content
─────────────────────────────────────────────────────────────────────────────
  0 ..  63   PRE_ZEROS   (64 zero samples)
 64 ..  95   CP1         (32-sample cyclic prefix = copy of S1[224:256])
 96 .. 351   S1          (256-sample OFDM symbol 1, IFFT of 256 QPSK subcarriers)
352 .. 383   CP2         (32-sample cyclic prefix = copy of S2[224:256])
384 .. 639   S2          (256-sample OFDM symbol 2)
640 .. 703   POST_ZEROS  (64 zero samples)
─────────────────────────────────────────────────────────────────────────────
Total: 704 samples
```

### CP Validity

Each CP is the **exact last CP_LEN=32 samples** of its symbol, constructed as:

```python
td = np.fft.ifft(qpsk_freq_vector)   # 256-sample time-domain symbol
cp = td[-32:]                         # last 32 samples
symbol_with_cp = concat([cp, td])     # [CP | symbol]
```

This guarantees a VanDeBeek autocorrelation peak at the CP/tail lag.

---

## Generator Parameters

| Parameter | Value | Notes |
|---|---|---|
| `NSC` | 256 | FFT size / subcarriers |
| `CP_LEN` | 32 | Cyclic prefix length |
| `FRAME_LEN` | 576 | 2 × (NSC + CP_LEN) — one slot |
| `PRE_ZEROS` | 64 | Silent prefix |
| `POST_ZEROS` | 64 | Silent suffix |
| `TARGET_PEAK` | 3000.0 | Peak float amplitude per component (I or Q) |
| `EPS_FRAC` | 0.05 | Fractional CFO in subcarrier spacings |
| `INT_CFO` | 0 | Integer CFO (not applied) |
| `NOISE_ON` | False | No additive noise |
| `SEED` | `0xC0FFEE` | `numpy.random.default_rng(seed)` |

---

## Fractional CFO

After frame assembly, every sample `x[n]` is rotated by:

```
x[n] = x[n] × exp(j × 2π × EPS_FRAC × n / NSC)
```

The CP autocorrelation peak at lag `m=peakIndexAuto` accumulates the phase
`exp(−j × 2π × EPS_FRAC)` from the NSC-sample displacement, so:

```
fracfreqOffset = −atan2(P_Q, P_I) / (2π)  ≈  +EPS_FRAC  = +0.05
```

---

## Expected Synchronisation Indices

These values are computed by the generator itself using an exact Python port
of `golden_dump.c`'s `frame_detector()` and `auto_corr()` functions, then
stored in `golden/phase3_iq_stimulus_meta.json`.

| Value | Result | Derivation |
|---|---|---|
| `frameStart` | **41** | First of 10 consecutive windows above threshold=40000, wnd=25. Window 41 contains CP1 samples with sufficient energy. |
| `peakIndexAuto` | **23** | `argmax(metric[0..255])`; lag where CP/tail correlation peaks (relative to frameStart=41). |
| `slotStartIndex` | **64** | `peakIndexAuto + frameStart = 23 + 41 = 64 = PRE_ZEROS`. Exact start of CP1. |
| `fracfreqOffset` | **≈ +0.05** | `−atan2(P_Q, P_I) / (2π)` at the peak lag ≈ EPS_FRAC. |

---

## Output Files

### `golden/phase3_iq_stimulus.f32`

Binary little-endian float32, interleaved: `I0 Q0 I1 Q1 …`  
Size: 704 × 2 × 4 = 5632 bytes.  
Consumed by `scripts/golden_dump` and by `run_phase3_sync_sim.sh` step c.

### `golden/phase3_iq_stimulus.mem`

ASCII hex, one 32-bit word per line.  
Format: `{Q[15:0], I[15:0]}` — signed int16, clamped, upper/lower 16-bit halves.  
Example line: `F9EE1A3C`  (Q=0xF9EE=−530, I=0x1A3C=6716)

### `golden/phase3_iq_stimulus_meta.json`

JSON metadata including all parameters, expected indices, and file format notes.
Regenerated on every generator run.

---

## How to Regenerate

```bash
python3 scripts/gen_phase3_iq_stimulus.py
```

Or, automatically when missing via the simulation runner:

```bash
bash scripts/run_phase3_sync_sim.sh   # auto-generates if .f32 absent
```

The generator is deterministic: same `SEED` and parameters always produce
the same files.

---

## Integration with run_phase3_sync_sim.sh

Step b was updated to auto-generate the stimulus if the default IQ file is missing:

```bash
if [[ ! -f "${IQ_FILE}" ]]; then
    python3 "${SCRIPT_DIR}/gen_phase3_iq_stimulus.py"
fi
```

Step c was updated to convert integer-scale float samples (amplitude ~3000) to
int16 by direct clamping rather than the previous normalise-to-[-1,1] approach
that would have clipped all samples to ±32767.

---

## Known Limitations

| Limitation | Impact |
|---|---|
| Single-path, no multipath | Does not exercise frequency-selective channel; timing metric is noise-free |
| No integer CFO | `INT_CFO=0`; integer CFO estimation in RTL will produce near-zero or arbitrary result (informational only) |
| OFDM PAPR ≈ 8–12 dB | Peak component ≈ 3000; RMS ≈ 1200–2000 per component depending on symbol realization |
| frameStart≠PRE_ZEROS−(WND_LEN−1) | Window 40 contains CP1[0] which happens to be insufficient on its own with this seed; detection starts at window 41. slotStartIndex=64=PRE_ZEROS is unaffected. |
| Metric value ≈ 0 at peak | For a perfect noiseless CP, `2|P|−E = 0` analytically; golden_dump reports metric=8 (float rounding). find_max_index still returns correct argmax. |
