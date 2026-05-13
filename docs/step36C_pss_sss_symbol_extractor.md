# Step 36C — PSS/SSS Symbol Extractor

## Overview

`pss_sss_symbol_extractor` is a standalone AXI-Stream module that ingests a
corrected time-domain frame and forwards exactly NSC (= 256) samples for the
PSS FFT window and NSC samples for the SSS FFT window.  CP removal is implicit:
the caller programs `pss_fft_start` / `sss_fft_start` to point at the first
post-CP sample; samples before those offsets are consumed and discarded.

## Parameters

| Parameter           | Default | Description                                    |
|---------------------|---------|------------------------------------------------|
| `NSC`               | 256     | Samples per symbol (FFT size)                  |
| `CP_LEN`            | 32      | Informational only — not used in RTL logic     |
| `IQ_WIDTH`          | 16      | Bits per I or Q sample                         |
| `FRAME_INDEX_WIDTH` | 12      | Width of frame sample counter and config ports |

## Ports

### Control

| Port           | Dir | Width | Description                                             |
|----------------|-----|-------|---------------------------------------------------------|
| `aclk`         | in  | 1     | System clock (rising edge)                              |
| `aresetn`      | in  | 1     | Active-low synchronous reset                            |
| `start`        | in  | 1     | One-cycle pulse: latch config and begin extraction      |
| `pss_fft_start`| in  | 12    | Frame index of first PSS FFT sample (post-CP)           |
| `sss_fft_start`| in  | 12    | Frame index of first SSS FFT sample (post-CP)           |
| `frame_len`    | in  | 12    | Total samples in the input frame                        |

### AXI-Stream Input (slave)

| Port             | Dir | Width    | Description                         |
|------------------|-----|----------|-------------------------------------|
| `s_axis_tvalid`  | in  | 1        | Input data valid                    |
| `s_axis_tready`  | out | 1        | Module ready to accept (wire)       |
| `s_axis_tdata`   | in  | 2×IQ_WIDTH | IQ sample {Q[15:0], I[15:0]}     |
| `s_axis_tlast`   | in  | 1        | Last sample of frame                |

### AXI-Stream Output (master)

| Port             | Dir | Width    | Description                                   |
|------------------|-----|----------|-----------------------------------------------|
| `m_axis_tvalid`  | out | 1        | Output data valid (combinatorial from hold reg)|
| `m_axis_tready`  | in  | 1        | Downstream ready                              |
| `m_axis_tdata`   | out | 2×IQ_WIDTH | Extracted IQ sample                        |
| `m_axis_tlast`   | out | 1        | Last sample of current symbol (NSC−1)         |
| `m_symbol_sel`   | out | 1        | 0 = PSS, 1 = SSS                             |
| `m_symbol_index` | out | 8        | Sample index within symbol (0–255)            |

### Status

| Port         | Dir | Width | Description                                |
|--------------|-----|-------|--------------------------------------------|
| `busy`       | out | 1     | High while extraction in progress          |
| `done`       | out | 1     | One-cycle pulse on successful completion   |
| `error`      | out | 1     | Sticky error flag (cleared on next `start`)|
| `error_code` | out | 4     | Error reason (see table below)             |

### Error Codes

| Code | Name                   | Cause                                                         |
|------|------------------------|---------------------------------------------------------------|
| 0    | none                   | No error                                                      |
| 1    | invalid_config         | Window extends past `frame_len`, windows overlap, or equal starts |
| 2    | frame_tlast_too_early  | `s_axis_tlast` received before both windows completed         |
| 4    | start_while_busy       | `start` received while in S_STREAM (ignored, non-fatal)       |

## Architecture

### State Machine

```
S_IDLE  ──start+valid_cfg──► S_STREAM ──both_windows_done / tlast──► S_DONE ──hold_drained──► S_IDLE
   │                              │                                                                │
   └──start+invalid_cfg──► S_ERROR ◄──────tlast_too_early────────────────────────────────────────┘
```

### Backpressure (One-Deep Hold Register)

The module contains a single hold register (`hold_valid`, `hold_data`, etc.).
All output ports are combinatorial wires driven directly from the hold register:

```
m_axis_tvalid = hold_valid   (wire)
m_axis_tdata  = hold_data    (wire)
```

`s_axis_tready` is deasserted whenever `hold_valid` is set, preventing new
input from overwriting an unacknowledged output sample.  This means the
input stream never stalls for more than one cycle per output sample.

### Discard / Drain Policy

- **S_STREAM**: samples outside both windows are consumed and discarded.
- **S_DONE**: `s_axis_tready` is asserted; remaining frame samples are consumed
  and discarded while the hold register drains.

### Config Validation (S_IDLE on start)

The following conditions set `error_code=1` and transition to S_ERROR:
- `pss_fft_start + NSC > frame_len`
- `sss_fft_start + NSC > frame_len`
- `pss_fft_start == sss_fft_start`
- PSS and SSS windows overlap in any direction

## Simulation

### Running

```bash
export PATH="/path/to/Vivado/2022.2/bin:$PATH"
bash scripts/run_pss_sss_symbol_extractor_sim.sh
```

### Test Suite (37 checks across 14 groups)

| Group | Name                         | Checks |
|-------|------------------------------|--------|
| T1    | reset_defaults               | busy/done/error/tvalid all 0 after reset |
| T2    | basic_extract                | counts=256, no error |
| T3    | pss_data_exact               | all 256 PSS words match frame_word(PSS_START+i) |
| T4    | sss_data_exact               | all 256 SSS words match frame_word(SSS_START+i) |
| T5    | tlast_positions              | tlast set only at index 255 for both symbols |
| T6    | output_backpressure          | counts, no error, data integrity with bp_period=3 |
| T7    | input_gaps                   | counts, no error with gap_period=5 |
| T8    | different_offsets            | pss_start=16, sss_start=400, frame=700 |
| T9    | invalid_config_pss_out_of_range | error=1, error_code=1, busy=0 |
| T10   | invalid_config_sss_out_of_range | error=1, error_code=1 |
| T11   | early_tlast                  | error=1, error_code=2 |
| T12   | start_while_busy             | busy stays, extraction still completes with 256+256 |
| T13   | overlap_invalid              | error=1, error_code=1 |
| T14   | exact_minimum_frame          | frame_len=SSS_START+NSC=576, tlast at last SSS sample |

**Result: 37/37 PASS — CI GATE: PASSED**

## Integration Notes

- This module sits between the integer CFO corrected-frame output and the FFT
  frontend (Step 34 / future Step 36A/B).
- `pss_fft_start` and `sss_fft_start` are derived from the PSS timing search
  result and are fixed per frame structure (standard LTE-like: CP_LEN=32,
  NSC=256).
- The output stream interleaves PSS and SSS samples in arrival order (whichever
  window comes first in the frame).  Downstream consumers use `m_symbol_sel`
  to demux.
