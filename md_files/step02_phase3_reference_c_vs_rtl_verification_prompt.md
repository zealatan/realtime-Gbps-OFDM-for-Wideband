# Step 02 — Phase3 Reference C vs RTL Verification Prompt Archive

**Date:** 2026-05-27  
**Session:** /status invocation, Phase 3 RTL simulation verification setup

---

## Full Prompt (as received)

> Build a simulation-only verification strategy that compares the RTL synchronizer behavior
> against the C reference synchronizer.
>
> Project context:  
>   ref/ — C reference OFDM receiver  
>   rtl/ — Verilog RTL implementation
>
> Do NOT work on FPGA, Vivado implementation, board test, Vitis, DMA host code, or ILA.
> This is RTL simulation and golden-reference comparison only.
>
> Key files:  
>   ref/receiver.c, ref/signal_processing_common.c, ref/auxiliary.c  
>   rtl/phase2_streaming_sync_top.v, rtl/streaming_cp_autocorr.v,  
>   rtl/streaming_timing_metric.v, rtl/streaming_peak_detector.v,  
>   rtl/streaming_frac_cfo_estimator.v, rtl/streaming_cfo_corrector.v,  
>   rtl/pss_sss_symbol_extractor.v, rtl/meyr_integer_cfo_freq_estimator_top.v,  
>   rtl/phase2_legacy/, rtl/unit_test/
>
> Exclude: rtl/unit_test/phase2_integer_cfo_estimator.v (unit-test/standalone only)

---

## My Interpretation

The task is to:
1. Trace the C `synchronization()` call graph to enumerate golden internal signals
2. Map each C signal to an observable RTL port or internal wire
3. Design a simulation-only verification plan (testbench + scripts + golden dump)
4. Produce required output artefacts without touching production RTL or FPGA flow

---

## Files Inspected

| File | Purpose |
|---|---|
| ref/receiver.c | Top-level synchronization() and all sub-functions |
| ref/signal_processing_common.c | auto_corr, VanDeBeekAutoCorrelation, frame_detector, apply_carrier_freq_offset, carrierFreqOffsetEstMeyr |
| ref/pluto.h | Constants: NSC=256, CP_LEN=32, NUM_SYN_BLOCKS=2 |
| ref/auxiliary.c | Helper utilities only (save, generate_complex_symbol) |
| rtl/phase2_streaming_sync_top.v | RTL top integration: P2-02..P2-06 |
| rtl/streaming_cp_autocorr.v | P2-02: sliding CP autocorr |
| rtl/streaming_timing_metric.v | P2-03: metric = 2\|P\| - energy |
| rtl/streaming_peak_detector.v | P2-04: window peak → timing_lock |
| rtl/streaming_frac_cfo_estimator.v | P2-05: CORDIC atan2 → frac_phase |
| rtl/pss_sss_symbol_extractor.v | PSS/SSS window extractor (standalone) |

---

## C Reference Synchronization Flow

```
synchronization(rxI, rxQ, rxLen, ...)
│
├── Step 1: frame_detector(rxI, rxQ, rxLen, wndLen=25, threshold=40000)
│   → frameStart   [energy window detection, 10 consecutive hits]
│
├── Step 2: VanDeBeekAutoCorrelation(rxI, rxQ, frameStart, autoCorrOutI, autoCorrOutQ)
│   │   auto_corr(rxI+frameStart, rxQ+frameStart, outI, outQ, NSC=256, CP_LEN=32)
│   │   P_I[m] = Σ_{i=0}^{31} (rx[m+i] · rx*[m+i+256])_real
│   │   P_Q[m] = Σ_{i=0}^{31} (rx[m+i] · rx*[m+i+256])_imag
│   │   E[m]   = Σ_{i=0}^{31} (|rx[m+i+256]|² + |rx[m+i]|²)
│   │   metric[m] = 2·|P[m]| − E[m]
│   └── peakIndexAuto = argmax(metric[0..NSC-1])
│       slotStartIndex = peakIndexAuto + frameStart
│
├── Step 3: fracfreqOffset = −atan2(P_Q[peakIndexAuto], P_I[peakIndexAuto]) / (2π)
│   apply_carrier_freq_offset(−fracfreqOffset·fs/NSC, ...)
│
└── Step 4: carrierFreqOffsetEstMeyr(rxI, rxQ, mUI, mUQ, goldUI, goldUQ, slotStartIndex, ...)
    → carrierFreqOffsetInt  [Meyr PSS/SSS cross-correlation in freq domain]
    apply_carrier_freq_offset(−carrierFreqOffsetInt·fs/NSC, ...)

return slotStartIndex
```

---

## Golden Internal Values to Compare

| # | C Variable | Location | Type | RTL Counterpart |
|---|---|---|---|---|
| 1 | frameStart | synchronization() step 1 | int (sample index) | **None** — energy detector absent in RTL |
| 2 | peakIndexAuto | VanDeBeekAutoCorrelation() | int (lag from frameStart) | lock_index − frameStart (derived) |
| 3 | slotStartIndex | synchronization() step 2 | int (absolute sample index) | lock_index (top-level output) |
| 4 | autoCorrOutI[peakIndexAuto] | auto_corr() at peak | float | peak_p_i (48-bit fixed, from P2-04) |
| 5 | autoCorrOutQ[peakIndexAuto] | auto_corr() at peak | float | peak_p_q (48-bit fixed, from P2-04) |
| 6 | normalizedValue_2[peakIndexAuto] | VanDeBeekAutoCorrelation() | float | max metric at timing_lock (metric_dbg at lock cycle) |
| 7 | fracfreqOffset | synchronization() step 3 | float (cycles/sample) | frac_phase_dbg (Q1.15 = atan2 output / π) |
| 8 | carrierFreqOffsetInt | carrierFreqOffsetEstMeyr() | int (subcarrier bins) | meyr_integer_cfo_freq_estimator_top (separate, not in streaming top) |
| 9 | slotStartIndex + CP_LEN | receiver.c (PSS symbol start) | int | pss_fft_start input to pss_sss_symbol_extractor |

---

## RTL Observable Signals (Available at Top Ports)

From `phase2_streaming_sync_top.v`:

| Port | Width | Maps to C |
|---|---|---|
| timing_lock | 1 | Pulse when peakIndexAuto found |
| lock_index | 32 | slotStartIndex |
| metric_dbg | 32 | normalizedValue_2 at peak (snapshot) |
| frac_phase_dbg | 16 | fracfreqOffset (Q1.15 format, atan2/π) |
| nco_locked | 1 | CFO corrector locked |
| state_dbg | 4 | Internal FSM state bits |

Internal wires needing exposure (not at top ports currently):

| Internal Wire | Module | What it represents |
|---|---|---|
| autocorr_p_i | P2-02 | P_I sliding window sum (per sample) |
| autocorr_p_q | P2-02 | P_Q sliding window sum (per sample) |
| autocorr_energy | P2-02 | E sliding window sum (per sample) |
| autocorr_index | P2-02 | Corresponding sample index |
| metric_out | P2-03 | Timing metric per sample |
| metric_index | P2-03 | Corresponding sample index |
| metric_valid | P2-03 | Valid strobe |

---

## RTL vs C Algorithm Differences

| Aspect | C Reference | RTL |
|---|---|---|
| Frame anchor | frame_detector (energy threshold) | None — assumes IQ stream from sample 0 |
| Autocorr window | N=NSC=256 lags, starting from frameStart | Sliding, all samples from start |
| Peak window | argmax over NSC=256 values | argmax over NSC+CP_LEN=288 valid samples per window |
| \|P\| computation | Exact sqrt() | Alpha-max-beta-min: p_max + p_min/4 + p_min/8 (~3.5% error) |
| Energy normalization | Σ(\|x[n+N]\|² + \|x[n]\|²) | Σ(\|x[n]\|²) only (current sample power) |
| Integer CFO | carrierFreqOffsetEstMeyr in synchronization() | meyr_integer_cfo_freq_estimator_top (separate, not chained) |
| Data types | float32 | 16-bit IQ input, 48-bit accumulator, Q1.15 phase |

---

## Allowed Modifications

- Add tb/ directory and testbench files
- Add scripts/ with simulation runner scripts
- Add docs/ with verification plan and golden dump format
- Add small C dump helper only if needed (no algorithm changes)
- Add md_files/ archive (this file)

## Do Not Modify

- Production RTL datapath (streaming_*.v, phase2_streaming_sync_top.v)
- ref/receiver.c, ref/signal_processing_common.c algorithm semantics
- No FPGA/board/Vitis work

---

## Required Outputs

1. `docs/phase3_reference_c_vs_rtl_verification_plan.md`
2. `scripts/run_phase3_sync_sim.sh`
3. `tb/phase3_sync_reference_compare_tb.sv`
4. `docs/phase3_golden_dump_format.md`
5. Final summary in response

---

## Pass Criteria

- Verification is simulation-only
- C internal values are identified and tabulated
- RTL observable signals are listed with what is missing
- No FPGA/board work introduced
- phase2_integer_cfo_estimator.v excluded from production verification
