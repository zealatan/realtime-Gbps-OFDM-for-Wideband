# Step 25 — AXI-Lite + AXI-Stream Debug/Config Wrapper

## Goal

Wrap `frac_cfo_frame_corrector_top` with an AXI4-Lite register file for JTAG control
and status readback.  The AXI-Stream IQ data path is preserved unchanged.

## Architecture

```
          AXI-Lite (control / status)
          ┌─────────────────────────────────┐
CPU ──────►  frac_cfo_sync_control_s_axi    │
          │  (8 × 32-bit registers)         │
          └──────────────┬──────────────────┘
                         │ soft_reset_pulse, clear_status_pulse,
                         │ enable_out, cfg_*
                         ▼
          ┌─────────────────────────────────┐
s_axis ──►│ frac_cfo_sync_axi_stream_wrapper │──► m_axis
          │   ├─ enable/start gating        │
          │   ├─ sticky status registers    │
          │   ├─ sample/output counters     │
          │   └─ frac_cfo_frame_corrector_top│
          └─────────────────────────────────┘
```

## AXI-Lite Register Map

Base address: user-defined (wrapper exposes 6-bit byte address).

| Offset | Name              | Access | Bits / Description |
|--------|-------------------|--------|--------------------|
| 0x00   | CONTROL           | W/R    | [2]=enable, [1]=clear_status_pulse, [0]=soft_reset_pulse |
| 0x04   | STATUS            | R/O    | [6]=output_seen, [5]=input_seen, [4]=in_frame(=busy), [3]=frame_error, [2]=frame_detected, [1]=done, [0]=busy |
| 0x08   | CFG_CFO_STEP      | W/R    | 32-bit (stored, not yet connected to DUT) |
| 0x0C   | CFG_TIMING_OFFSET | W/R    | 32-bit (stored, not yet connected to DUT) |
| 0x10   | CFG_FRAME_LEN     | W/R    | 32-bit (stored, not yet connected to DUT) |
| 0x14   | SAMPLE_COUNT      | R/O    | Input stream handshake counter (resets on soft_reset or clear_status) |
| 0x18   | OUTPUT_COUNT      | R/O    | Output stream handshake counter |
| 0x1C   | DEBUG_STATE       | R/O    | {4'd0, peak_lag[8:0], frac_phase[15:0], fsm_state[2:0]} |

SLVERR returned for addresses outside the 8-register range.

## Behavioural Description

### Enable / Start

- Writing CONTROL[2]=1 asserts `enable_out`.
- The wrapper detects the rising edge of `enable_out` and generates a 1-cycle `dut_start` pulse to trigger the DUT's IDLE→FILL transition.
- While `enable_out=0`: `s_axis_tready=0` and DUT input tvalid=0 (stream gated).

### Soft Reset

- Writing CONTROL[0]=1 asserts `soft_reset_pulse` for exactly one clock cycle.
- `dut_aresetn = aresetn && !soft_reset_pulse` — DUT is held in reset for that one cycle.
- All sticky bits and counters reset on `soft_reset_pulse`.
- `enable_out` is written as part of the same CONTROL word; if bit[2]=0, enable de-asserts.

### Sticky Status

STATUS bits [6:1] are sticky (set-on-event, cleared by `soft_reset_pulse` or `clear_status_pulse`):

| Bit | Source |
|-----|--------|
| done (bit 1) | DUT `done` output |
| frame_detected (bit 2) | `done && frame_found && !frame_error` |
| frame_error (bit 3) | DUT `frame_error` output (held 1 cycle in DUT FRAME_DET state) |
| input_seen (bit 5) | First `s_axis` handshake |
| output_seen (bit 6) | First `m_axis` handshake |

### Counters

- `SAMPLE_COUNT`: increments on each `s_axis_tvalid && s_axis_tready` handshake.
- `OUTPUT_COUNT`: increments on each `m_axis_tvalid && m_axis_tready` handshake.
- Both reset on `clear_sticky = soft_reset_pulse || clear_status_pulse`.

### CFG Registers

`CFG_CFO_STEP`, `CFG_TIMING_OFFSET`, `CFG_FRAME_LEN` are read/write but not yet connected
to the DUT.  DUT uses compile-time parameters for threshold, window_len, and hit_count.

### DEBUG_STATE

Packed read-only word: `{4'd0, peak_lag_r[8:0], frac_phase_r[15:0], dbg_state_r[2:0]}`.
`peak_lag_r` and `frac_phase_r` are latched at `done`.

## Files

| File | Description |
|------|-------------|
| `rtl/frac_cfo_sync_control_s_axi.v` | AXI4-Lite slave register file (8 registers, write FSM) |
| `rtl/frac_cfo_sync_axi_stream_wrapper.v` | Top-level wrapper integrating register file + DUT |
| `tb/frac_cfo_sync_axi_stream_wrapper_tb.sv` | T1–T11 simulation test groups |
| `scripts/run_frac_cfo_sync_axi_stream_wrapper_sim.sh` | xsim compile + run script |

## Implementation Notes

### Verilog Parameter Bit-Select Bug (Fixed)

Connecting a 32-bit `parameter integer` to a wider port via `PARAM[WIDTH-1:0]`
produces X for the high bits in xsim when `WIDTH > 32`.  This caused `threshold_in`
to be X, making every frame-detector energy comparison evaluate to 0 (no frame found).

Fix: use explicit zero-extension in the wrapper:
```verilog
.threshold_in  ({{(ENERGY_WIDTH-32){1'b0}}, THRESHOLD[31:0]}),
```

### Frame Detector Signal Requirements

The frame_detector uses Case A / Case B logic:
- Case A (first window below threshold): scans for HIT_COUNT consecutive above-threshold windows.
- Case B (first window above threshold): skips until below-threshold, then Case A.

With a constant above-threshold signal, Case B never transitions back → no frame found.
Integration test T10 feeds `WINDOW_LEN*2=8` quiet samples (I=Q=0) before the active
signal to guarantee Case A entry.

## Simulation Results

```
Run: bash scripts/run_frac_cfo_sync_axi_stream_wrapper_sim.sh
PASS=23  FAIL=0
CI GATE: PASSED
```

Integration regression unchanged:
```
Run: bash scripts/run_frac_cfo_frame_corrector_top_sim.sh
PASS=176  FAIL=0
CI GATE: PASSED
```

## Test Groups

| Test | Description | Checks |
|------|-------------|--------|
| T1  | STATUS=0 after reset | STATUS=0, rresp=OKAY |
| T2  | Write enable=1, read back | enable bit set |
| T3  | Soft reset clears enable | enable=0 after soft_reset write |
| T4  | clear_status_pulse clears sticky | input_seen cleared |
| T5  | CFG register write/read (full + byte strobe) | 4 checks including strobe[3] |
| T6  | SLVERR for unmapped address | bresp=SLVERR, rresp=SLVERR |
| T7  | SAMPLE_COUNT increments | count=3 after 3 samples |
| T8  | OUTPUT_COUNT=0 before any output | count=0 after reset |
| T9  | STATUS busy=0 in idle | busy bit clear |
| T10 | Integration: feed quiet+signal, wait done, check output | done_sticky=1, output_count=20 |
| T11 | Soft reset clears all state | STATUS, SAMPLE_COUNT, OUTPUT_COUNT all zero |

## Step 26 Recommendation

Step 26 = integer CFO estimator (int_cfo_estimator.v) integration — deferred from earlier steps.
Or: AXI-Lite → THRESHOLD / WINDOW_LEN / HIT_COUNT runtime register connections for flexible frame detection.
