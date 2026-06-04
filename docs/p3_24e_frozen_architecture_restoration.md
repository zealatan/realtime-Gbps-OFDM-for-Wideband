# P3-24E: Frozen Architecture Restoration

**Gate:** `FROZEN_ARCH_RESTORE_GATE: PASS`

## Summary

The production RTL hierarchy has been restored to the frozen architecture specification.
`frame_frac_cfo_top` now exists, `timing_sync_top` is active in the hierarchy, and
`timing_sync_top` instantiates both `streaming_cp_autocorr` and `peak_detector`.

## Required Hierarchy (frozen specification)

```
frac_cfo_frame_corrector_top
├─ iq_frame_buffer
├─ frame_detector
│   ├─ sliding_window_sum
│   └─ frame_detect_fsm
├─ frame_frac_cfo_top           ← created (was absent)
│   ├─ timing_sync_top          ← now active (was bypassed)
│   │   ├─ streaming_cp_autocorr
│   │   └─ peak_detector        ← now instantiated here
│   └─ frac_cfo_estimator
└─ frac_cfo_corrector_top
    ├─ nco_phase_gen
    └─ complex_rotator
```

## Problem

The working P3-24A design used `timing_frac_cfo_top` as a flat module that directly
instantiated `streaming_cp_autocorr` and `frac_cfo_estimator` with inline argmax logic.
Three hierarchy violations existed:

| Gap | Status |
|-----|--------|
| `frame_frac_cfo_top` module missing entirely | Fixed: created |
| `timing_sync_top` not in active hierarchy (dead module) | Fixed: now instantiated by frame_frac_cfo_top |
| `timing_sync_top` did not instantiate `peak_detector` | Fixed: peak_detector added |

## Changes

### `rtl/DUT/timing_sync_top.v` (rewritten)

Replaced inline sq_neg argmax with `peak_detector` instantiation.

Key design decisions:
- **Metric**: Manhattan `|P_I[47:16]| + |P_Q[47:16]|` — identical to working
  `timing_frac_cfo_top` algorithm; no algorithm change.
- **Full-window gate**: The SCA fires `out_valid` permanently once started,
  including for the initial CP_LEN-1 partial-window outputs.  Only outputs with
  `sca_sample_index >= STREAM_OFFSET` correspond to full Schmidl-Cox windows (lag
  0..NSC-1).  `full_win_valid` gates both `peak_detector.data_valid` and the shadow
  phasor tracker to exclude partial windows.
- **peak_detector.peak_index**: 0-based count among full-window outputs = physical
  lag directly; no FULL_WIN_START offset needed.
- **Shadow phasor tracker**: parallel strict-> comparison captures SCA phasors
  at the peak for `peak_corr_i/q/energy` outputs.
- **Buffer streaming**: STREAM_TOTAL=553, STREAM_DONE=567 — identical constants to
  timing_frac_cfo_top.

### `rtl/DUT/frame_frac_cfo_top.v` (new file)

Wrapper module encapsulating `timing_sync_top` (u_tst) and `frac_cfo_estimator` (u_fce).

- **Interface**: identical to `timing_frac_cfo_top` — `frac_cfo_frame_corrector_top`
  required no port changes.
- **FSM**: S_IDLE → S_TIMING (run timing_sync_top) → S_FRAC_CFO (run frac_cfo_estimator) → S_DONE.
- **Buffer read port**: passthrough from timing_sync_top during S_TIMING; idle otherwise.
- **Result latching**: timing results latched on tst_done before starting fce; stable
  through S_FRAC_CFO and S_DONE.

### `rtl/DUT/frac_cfo_frame_corrector_top.v` (minimal edit)

Changed instantiation at line 287 from `timing_frac_cfo_top` to `frame_frac_cfo_top`.
Parameters and port connections unchanged.

### `scripts/phase3_dut_filelist.f` (updated)

Added `rtl/DUT/frame_frac_cfo_top.v` after `timing_frac_cfo_top.v` in the
timing/frac-CFO hierarchy section (source count: 35 → 36).

## Algorithms Unchanged

All signal processing is identical to the working P3-24A design:
- Schmidl-Cox CP autocorrelation (streaming_cp_autocorr): unchanged
- Manhattan metric computation: unchanged
- CORDIC atan2 (frac_cfo_estimator): unchanged
- Frame detection sliding window: unchanged
- NCO/complex_rotator correction: unchanged

## Regression Results

| Test | Result | Key Checks |
|------|--------|-----------|
| Session A / P3-12C | SANITY_GATE: PASS (10/10) | frame_index=41, peak_lag=23, slot_start=64 |
| Session E / P3-16A | INTEGRATION_GATE: PASS (8/8) | frame_found, frac_cfo_valid, int_cfo_valid, output_count=576, tlast=575 |
| Session D / P3-15A | SANITY_EQUIV_GATE: PASS | All 6 stages PASS |
| Session K / P3-22A | CHANNEL_GATE: PASS (11/11) | All channel robustness cases |

## Gate

```
FROZEN_ARCH_RESTORE_GATE: PASS
```

`frame_frac_cfo_top` exists and wraps `timing_sync_top` + `frac_cfo_estimator`.
`timing_sync_top` instantiates `streaming_cp_autocorr` and `peak_detector`.
`frac_cfo_estimator` does not absorb `timing_sync_top` functionality.
All regression checks pass.
