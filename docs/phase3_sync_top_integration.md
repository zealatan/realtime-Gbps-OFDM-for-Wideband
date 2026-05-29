# Phase 3 Sync Top Integration

## 1. Module Hierarchy

```
phase3_sync_top
├── u_frac_corr    frac_cfo_frame_corrector_top   (rtl/)
│   ├── u_buf          iq_frame_buffer             (unit_test/)
│   ├── u_fd           frame_detector              (unit_test/)
│   ├── u_tfc          timing_frac_cfo_top         (unit_test/)
│   │   ├── u_tst          timing_sync_top
│   │   └── u_fce          frac_cfo_estimator
│   └── u_corr         frac_cfo_corrector_top      (unit_test/)
├── u_ssc          slot_start_controller           (rtl/)
├── u_extractor    pss_sss_symbol_extractor        (rtl/)
└── u_meyr_fft     meyr_integer_cfo_fft_frontend_top (unit_test/)
    ├── u_fft          fft256_dual_symbol_frontend
    └── u_est          meyr_integer_cfo_freq_estimator_top (rtl/)
        ├── u_prod_gen     meyr_pss_sss_product_gen
        └── u_core         meyr_integer_cfo_core
```

**Excluded from production path:** `phase2_integer_cfo_estimator.v`

---

## 2. C Reference → RTL Mapping

| C reference (receiver.c)             | RTL location                               |
|--------------------------------------|--------------------------------------------|
| `frame_detector()`                   | `frac_cfo_frame_corrector_top` → `frame_detector` |
| `VanDeBeekAutoCorrelation()`         | `frac_cfo_frame_corrector_top` → `timing_frac_cfo_top` |
| `slotStartIndex = f + peak`          | `slot_start_controller.slot_start`         |
| `fracfreqOffset = -atan2(...)`       | `frac_cfo_frame_corrector_top` → `frac_cfo_estimator` → CORDIC |
| `apply_carrier_freq_offset` (frac)   | `frac_cfo_frame_corrector_top` → `frac_cfo_corrector_top` |
| `generate_complex_symbol` + FFT (PSS)| `meyr_integer_cfo_fft_frontend_top` → `fft256_dual_symbol_frontend` |
| `generate_complex_symbol` + FFT (SSS)| same                                       |
| `fft_correlation_Meyr` → `int_cfo`  | `meyr_integer_cfo_fft_frontend_top` → `meyr_integer_cfo_freq_estimator_top` |
| `apply_carrier_freq_offset` (int)    | **NOT YET IMPLEMENTED** — connection point exposed |

---

## 3. Stream Datapath

```
 IQ input (s_axis)
      │  AXI-Stream, 32-bit {Q[31:16], I[15:0]}
      ▼
 frac_cfo_frame_corrector_top
      │  OUTPUT_SAMPLES = FRAME_LEN = 2*(NSC+CP_LEN)  e.g. 576
      │  frac-corrected IQ starting from slotStartIndex
      │  32-bit {Q[31:16], I[15:0]}  with tlast on last sample
      ▼
 pss_sss_symbol_extractor
      │  PSS: samples at offsets [CP_LEN .. CP_LEN+NSC-1]
      │  SSS: samples at offsets [2*CP_LEN+NSC .. FRAME_LEN-1]
      │  PSS emitted first (m_symbol_sel=0), then SSS (m_symbol_sel=1)
      │  32-bit {Q[31:16], I[15:0]}  + symbol_sel + symbol_index
      ▼
 meyr_integer_cfo_fft_frontend_top
      │  FFT both symbols; buffer PSS FFT; pair PSS[k] + SSS[k]
      │  Meyr cross-correlation → peak → int_cfo (signed 16-bit, bins)
      ▼
 dbg_integer_cfo_word = -int_cfo * 2^(32-log2(NSC))
   (NCO step word for integer CFO correction, to be used by downstream corrector)
```

---

## 4. Key Parameter Relationships

| Symbol          | Expression               | Default value |
|-----------------|--------------------------|---------------|
| PSS_OFFSET      | CP_LEN                   | 32            |
| SSS_OFFSET      | 2 * CP_LEN + NSC         | 320           |
| FRAME_LEN       | 2 * (NSC + CP_LEN)       | 576           |
| NSC_LOG2        | $clog2(NSC)              | 8             |
| INT_CFO_SHIFT   | 32 - NSC_LOG2            | 24            |

The `OUTPUT_SAMPLES` of `frac_cfo_frame_corrector_top` is set to `FRAME_LEN` (576).
The default value (0 → NSC+CP_LEN = 288) is **insufficient** for Phase 3 since it
would not include the SSS symbol.

---

## 5. Debug Signal Reference

| Port                       | Source                              | Timing          |
|----------------------------|-------------------------------------|-----------------|
| `dbg_frame_start_valid`    | `frac_frac_phase_valid`             | 1-cycle pulse   |
| `dbg_frame_start_index`    | `frac_frame_index` (BUF_AW bits)   | stable at valid |
| `dbg_peak_valid`           | `frac_frac_phase_valid`             | same pulse      |
| `dbg_peak_index`           | `frac_peak_lag` (INDEX_WIDTH bits)  | stable at valid |
| `dbg_slot_start_valid`     | `ssc_slot_valid`                    | 1-cycle on done |
| `dbg_slot_start_index`     | `ssc_slot_start` (BUF_AW bits)     | stable at valid |
| `dbg_frac_cfo_valid`       | `frac_frac_phase_valid`             | same pulse      |
| `dbg_frac_cfo_word`        | `frac_frac_phase` (Q1.15)           | stable at valid |
| `dbg_pss_start`            | `ssc_pss_fft_start` (constant)     | always CP_LEN   |
| `dbg_sss_start`            | `ssc_sss_fft_start` (constant)     | always SSS_OFFSET |
| `dbg_integer_cfo_valid`    | registered on `meyr_done`          | 1-cycle pulse   |
| `dbg_integer_cfo_word`     | latched `-int_cfo<<<INT_CFO_SHIFT` | stable after valid |
| `dbg_done`                 | top-level `done`                    | 1-cycle pulse   |
| `dbg_error_code`           | top-level `error_code`              | stable after done |

**Note on dbg_frame_start_valid timing:** `frac_frac_phase_valid` fires at the end of
`S_TIMING_CFO` inside `frac_cfo_frame_corrector_top` (CORDIC latency after peak found).
At this clock edge `frame_index` and `peak_lag` are both stable; the testbench can
safely sample them on this pulse.

---

## 6. FSM States

| State   | Entry condition          | Exit condition                             |
|---------|--------------------------|--------------------------------------------|
| S_IDLE  | reset or S_DONE exit     | start && !busy → pulse 3 subs → S_RUN     |
| S_RUN   | from S_IDLE              | frac_frame_error → S_DONE (error=1)        |
|         |                          | meyr_done → latch step word → S_DONE       |
| S_DONE  | from S_RUN               | 1 cycle: done=1, busy=0 → S_IDLE           |

---

## 7. Integer CFO Correction — Connection Point

The step word for integer CFO removal is exposed as `dbg_integer_cfo_word` when
`dbg_integer_cfo_valid` pulses.  To complete Step 5 of the C reference flow, a
downstream module must:

1. Capture `dbg_integer_cfo_word` on the `dbg_integer_cfo_valid` cycle.
2. Load it into a second `frac_cfo_corrector_top` instance via `load_step`.
3. Re-feed the 576 frac-corrected IQ samples through that instance.

Step 3 requires a **replay buffer** holding the frac-corrected IQ output.
This is the sole remaining gap for a complete Phase 3 RTL implementation.

---

## 8. What Is Complete vs. Remaining

### Complete (Phase 3 step 03)
- All Steps 1–5 (estimation side) are instantiated and wired
- slotStartIndex generation and exposure
- PSS/SSS window addresses derived from parameters
- All 14 debug signals connected and documented
- `phase2_integer_cfo_estimator.v` excluded

### Remaining
| Priority | Item                                                       |
|----------|------------------------------------------------------------|
| P0       | Replay buffer (576-sample) for integer CFO correction pass |
| P0       | Second-stage `frac_cfo_corrector_top` for integer CFO      |
| P1       | Phase 3 top-level simulation testbench                     |
| P1       | AXI-Lite register interface for status/config              |
| P2       | Replace `fft256_dual_symbol_frontend` placeholder with Xilinx FFT IP |
