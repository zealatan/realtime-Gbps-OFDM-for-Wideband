# Session D3 / P3-15C — Equivalence Robustness Expansion

## Goal

Expand the C-reference equivalence verification from Session D (single baseline stimulus)
to five stimuli with different frame offsets, fractional CFO values, and signal power
levels. Verify that the RTL observables (frame detection, CFO estimates, slot timing) and
the M_AXIS IQ output match reference values across the full coverage range.

## Deliverables

| ID | Task | Output |
|----|------|--------|
| D3-1 | Generate 5 stimulus files | `golden/p3_15c_stimuli/stim_0{1-5}.{f32,mem,_meta.json}` |
| D3-2 | Metadata equivalence (RTL vs C reference) | ROBUST_EQUIV_GATE check in compare script |
| D3-3 | IQ equivalence: 576 samples ≤ 1 LSB vs Python NCO model | ROBUST_EQUIV_GATE check |
| D3-4 | Session summary matrix | `docs/session_D3_p3_15c_equivalence_matrix.md` |

## Stimulus Parameters

| ID | pre_zeros | eps_frac | amplitude | seed | k_int | Variation |
|----|-----------|----------|-----------|------|-------|-----------|
| stim_01 | 64 | +0.05 | 3000 | 0xC0FFEE | 0 | Baseline (same as Session C/D) |
| stim_02 | 32 | +0.05 | 3000 | 0xC0FFEE | 0 | Earlier frame (PRE_ZEROS=32) |
| stim_03 | 64 | −0.10 | 3000 | 0xC0FFEE | 0 | Negative fractional CFO |
| stim_04 | 64 | +0.05 | 1500 | 0xC0FFEE | 0 | Half power (amplitude=1500) |
| stim_05 | 80 | +0.20 | 2000 | 0xDEAD00 | 0 | Combined offset + large CFO |

All stimuli: 704 total samples (pre + 576 OFDM samples + post, post = 704 - 576 - pre).

## Equivalence Criteria

### Metadata (D3-2)

Compared against C reference (`golden_dump` output per stimulus):

| Field | Tolerance |
|-------|-----------|
| FRAME_START | ± 1 sample |
| PEAK_INDEX_AUTO (lag) | ± 1 lag |
| SLOT_START_INDEX | ± 1 sample |
| FRAC_CFO_OFFSET | ≤ 1% relative error |
| MEYR_PEAK_INDEX | ± 1 bin (255 ± 1) |
| INTEGER_CFO_WORD | Exact (0 for k_int=0) |

### IQ Samples (D3-3)

576 M_AXIS samples compared against Python NCO model (Session C pattern):
- step_word read from AXI-Lite register after simulation
- frac-corrected IQ captured from `dbg_frac_m` debug tap
- Python rotator applied: I_out = (I*cos + Q*sin) >> 15, Q_out = (Q*cos - I*sin) >> 15
- Tolerance: ± 1 LSB per component

## Gate

`ROBUST_EQUIV_GATE: PASS` — all 5 stimuli pass both metadata and IQ checks.
`ROBUST_EQUIV_GATE: FAIL` — any stimulus fails any check.

## Files

| File | Purpose |
|------|---------|
| `scripts/gen_p3_15c_multi_stimuli.py` | Generate 5 .f32 / .mem / _meta.json files |
| `tb/session_D3_p3_15c_equiv_tb.sv` | Reusable TB with +STIM_FILE / +OUT_PREFIX plusargs |
| `scripts/compare_session_D3_p3_15c_equiv.py` | Metadata + IQ compare per stimulus |
| `scripts/run_session_D3_p3_15c_equiv_robustness.sh` | Loop runner + gate emitter |
| `docs/session_D3_p3_15c_equivalence_matrix.md` | Final result matrix |
