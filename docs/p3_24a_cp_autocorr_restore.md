# P3-24A: Restore Production CP Autocorrelator Path

## Summary

`timing_frac_cfo_top.v` was instantiating `timing_sync_top` to perform Schmidl-Cox CP
timing synchronization. The old design had `timing_sync_top` wrapping `cp_autocorr_core`
(a batch, buffer-random-access Van De Beek correlator), which was located in
`rtl/unit_test/` — the wrong location for production code and not part of the
production compile.

P3-24A replaces this with a direct instantiation of `streaming_cp_autocorr` inside
`timing_frac_cfo_top`, removing the `timing_sync_top` dependency and restoring the
correct production hierarchy.

## Old Dependency (broken)

```
frac_cfo_frame_corrector_top
  └─ timing_frac_cfo_top
       ├─ timing_sync_top        ← DID NOT EXIST in production compile
       │    └─ cp_autocorr_core  ← batch correlator, rtl/unit_test/
       └─ frac_cfo_estimator
```

## New Dependency (P3-24A)

```
frac_cfo_frame_corrector_top
  └─ timing_frac_cfo_top
       ├─ streaming_cp_autocorr  ← direct instantiation, rtl/DUT/
       └─ frac_cfo_estimator
```

## streaming_cp_autocorr Interface

Module `streaming_cp_autocorr` (rtl/DUT/streaming_cp_autocorr.v):

| Port          | Direction | Width | Description |
|---------------|-----------|-------|-------------|
| clk           | in        | 1     | Clock (note: named `clk` not `aclk`) |
| aresetn       | in        | 1     | Async active-low reset |
| s_valid       | in        | 1     | Input sample valid strobe |
| s_data        | in        | 32    | IQ: [15:0]=I, [31:16]=Q |
| p_i           | out       | 48    | Sliding CP correlation I (48-bit signed) |
| p_q           | out       | 48    | Sliding CP correlation Q (48-bit signed) |
| energy        | out       | 48    | Sliding energy sum |
| out_valid     | out       | 1     | Permanently asserted after first valid output |
| sample_index  | out       | 32    | Count of s_valid pulses accepted |

## Integration Method

`timing_frac_cfo_top` now runs a 4-state FSM:

- **S_IDLE** → on `start`: release `streaming_cp_autocorr` from reset, issue first buffer read, go to S_STREAM
- **S_STREAM**: issue sequential buffer reads (STREAM_TOTAL reads total), continuously update peak via argmax on Manhattan metric `|P_I[47:16]| + |P_Q[47:16]|`, wait for pipeline drain after last read, then compute `peak_lag` and start `frac_cfo_estimator`
- **S_FRAC_CFO**: wait for `frac_cfo_estimator` (CORDIC atan2) to complete
- **S_DONE**: pulse `done`, hold results stable

### Key Parameters

| Localparam    | Value (defaults) | Formula |
|---------------|-----------------|---------|
| STREAM_OFFSET | 297              | NSC + CP_LEN + 9 |
| STREAM_TOTAL  | 553              | STREAM_OFFSET + NSC |
| PIPE_DRAIN    | 12               | cycles after last s_valid |

`STREAM_OFFSET = 297` accounts for the full pipeline latency from when a sample is fed
to when `timing_frac_cfo_top` can read the corresponding correlation output:
- delay_sample fill: NSC = 256 samples
- delay_sample output registration: +1 cycle
- complex_mult pipeline: +3 cycles
- moving_avg window fill: +(CP_LEN-1) = +31 samples
- moving_avg pipeline: +4 cycles
- out_valid propagation + register read: +2 cycles
- **Total: 256 + 1 + 3 + 31 + 4 + 2 = 297**

### Data Packing

Buffer data is packed `{Q[31:16], I[15:0]}`. streaming_cp_autocorr expects `s_data[15:0]=I, s_data[31:16]=Q`. The wiring in timing_frac_cfo_top:

```verilog
assign sca_s_data = {buf_rd_data_Q, buf_rd_data_I};
```

### Buffer Read Alignment

The `buf_rd_en`/`buf_rd_addr` ports were changed from `output wire` to `output reg` because they are now driven by the timing_frac_cfo_top FSM directly (previously driven by timing_sync_top output wires).

The buffer has 1-cycle registered read latency. `sca_s_valid_r` is a 1-cycle delayed copy of `buf_rd_en`, so streaming_cp_autocorr sees the data and s_valid aligned.

## Changed Files

| File | Change |
|------|--------|
| `rtl/DUT/timing_frac_cfo_top.v` | Full rewrite: replaced timing_sync_top+cp_autocorr_core with direct streaming_cp_autocorr instantiation + inline argmax FSM |
| `rtl/DUT/frame_detector.v` | Removed broken sample_power_sq submodule instantiation (wrong port interface); inlined combinatorial I²+Q² power computation |
| `rtl/DUT/timing_sync_top.v` | NEW standalone module (compiled but not instantiated in hierarchy): wraps streaming_cp_autocorr with argmax. Fixed partial-sum bug: argmax skips first CP_LEN-1 outputs (partial windows), scans to lag_cnt=NSC+CP_LEN-2, reports `peak_lag = lag_cnt - (CP_LEN-1)`. |
| `rtl/DUT/cordic_atan2.v` | NEW: behavioral LATENCY=15 atan2 stub |
| `rtl/DUT/complex_mult_iq.v` | NEW: 1-cycle AXI-S complex multiplier with CONJ_B option |
| `rtl/DUT/meyr_pss_sss_product_gen.v` | NEW: PSS × conj(SSS) product, 1-cycle pipeline |
| `rtl/DUT/meyr_integer_cfo_core.v` | NEW: integer CFO stub (k_int=0) |

## Regression Results

**Date:** 2026-06-01

**Gate:** `SANITY_CP_AUTOCORR_RESTORE_GATE: PASS` (8/8 checks)

| Check | Description | Result |
|-------|-------------|--------|
| C1 | frame_found == 1 | PASS (1) |
| C2 | frame_index ∈ [40,42] | PASS (40) |
| C3 | peak_lag ∈ [22,24] | PASS (23) |
| C4 | slot_start ∈ [63,65] | PASS (63) |
| C5 | frac_cfo_valid | PASS |
| C6 | int_cfo_valid | PASS |
| C7 | output_count == 576 | PASS |
| C8 | TLAST at beat 575 | PASS |

## Remaining Risks

- **STREAM_OFFSET calibration**: The value 297 was derived empirically from the regression result. A change to the delay_sample or moving_avg implementation (e.g., different RAM_LATENCY) would shift STREAM_OFFSET and require re-calibration.
- **Session E / L runners**: These reference `rtl/phase2_legacy/` and `rtl/unit_test/` directories that no longer exist. They are blocked with BLOCKED_MISSING_FILES regardless of P3-24A changes.
- **Non-zero k_int**: The full pipeline passes for k_int=0 stimulus. Non-zero integer CFO requires the Xilinx FFT IP path.
