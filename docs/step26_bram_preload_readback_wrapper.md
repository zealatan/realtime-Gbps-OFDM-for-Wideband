# Step 26 — BRAM Preload/Readback Wrapper

## Goal

Wrap `frac_cfo_frame_corrector_top` with dual on-chip memory buffers (input BRAM + output BRAM)
accessible via a single AXI4-Lite slave.  Software can write IQ samples into input memory, trigger
a synchroniser run, then read corrected samples from output memory — all without DMA or Xilinx IP.

## Architecture

```
  CPU / PS
    │
    │  AXI4-Lite (16-bit address)
    ▼
┌──────────────────────────────────────────────────┐
│  frac_cfo_sync_bram_test_wrapper                 │
│                                                  │
│  0x0000-0x0028  Control / status registers       │
│  0x1000-0x1FFF  input_mem  (1024 × 32-bit, R/W) │
│  0x2000-0x2FFF  output_mem (1024 × 32-bit, R/O) │
│                                                  │
│  Stream source FSM: input_mem → DUT s_axis       │
│  Stream sink  FSM: DUT m_axis → output_mem       │
│                    (always-assert tready, no bp) │
│                                                  │
│  frac_cfo_frame_corrector_top (instantiated      │
│  directly — Option A, avoids dual AXI slave)     │
└──────────────────────────────────────────────────┘
```

## Register Map

Base address: user-defined (wrapper exposes 16-bit byte address).

| Offset | Name            | Access | Bits / Description |
|--------|-----------------|--------|--------------------|
| 0x0000 | CONTROL         | W/R    | [3]=enable, [2]=clr_status_pulse, [1]=soft_reset_pulse, [0]=start_pulse |
| 0x0004 | STATUS          | R/O    | [8]=frame_error_sticky, [7,1]=done_sticky, [6]=output_overflow_sticky, [5]=input_underflow, [4]=output_done, [3]=input_done, [2]=running, [0]=dut_busy |
| 0x0008 | CFG_CFO_STEP    | W/R    | 32-bit (stored, future use) |
| 0x000C | CFG_TIMING_OFFSET | W/R  | 32-bit (stored, future use) |
| 0x0010 | CFG_FRAME_LEN   | W/R    | 32-bit (stored, future use) |
| 0x0014 | INPUT_LEN       | W/R    | Number of input samples to stream from input_mem |
| 0x0018 | OUTPUT_MAX_LEN  | W/R    | Maximum output samples to store in output_mem |
| 0x001C | INPUT_COUNT     | R/O    | Input stream handshake counter |
| 0x0020 | OUTPUT_COUNT    | R/O    | Output stream handshake counter (capped at OUTPUT_MAX_LEN) |
| 0x0024 | DEBUG_STATE     | R/O    | 0=idle, 1=armed, 2=streaming_input, 3=waiting_output, 4=done, 5=error |
| 0x0028 | ERROR_STATUS    | R/O    | [3]=timeout, [1]=overflow, [0]=underflow |

SLVERR returned for:
- Register addresses outside 0x0000-0x0028 in region 0x0xxx
- Writes to output_mem (region 0x2xxx)
- Any access to unmapped regions (0x3xxx and above)

## Behavioural Description

### Run Sequence

1. Write input IQ samples to 0x1000 window (up to 1024 × 32-bit words)
2. Write INPUT_LEN and OUTPUT_MAX_LEN registers
3. Write CONTROL with enable=1 and start_pulse=1 in the same word
4. Poll STATUS until done_sticky (bit[1]) is set
5. Read INPUT_COUNT and OUTPUT_COUNT to verify
6. Read corrected samples from 0x2000 window

### CONTROL Register

- `start_pulse` (bit[0]): one-shot pulse triggering the run.  Auto-clears next cycle.
  Effective only when `enable=1` and `!running`.
- `soft_reset_pulse` (bit[1]): one-shot reset of all status/counters and DUT.  Auto-clears.
  Config registers (CFG_*, INPUT_LEN, OUTPUT_MAX_LEN) are preserved across soft reset.
- `clr_status_pulse` (bit[2]): clears sticky bits and counters without resetting the DUT.
- `enable` (bit[3]): enables runs; persists until written 0.

`dut_start = start_pulse && enable && !running` (combinatorial).

### Soft Reset

`dut_aresetn = aresetn && !soft_reset_pulse_r` — DUT held in reset for one cycle.
Source and sink FSMs also reset.  All sticky bits and counters cleared.

### Source FSM

`SRC_IDLE → SRC_STREAM → SRC_DONE → SRC_IDLE`

Reads `input_mem[src_ptr]` combinatorially.  Asserts `tlast` on the last sample
(`src_ptr == INPUT_LEN-1`).  Advances `src_ptr` on each accepted handshake.

### Sink FSM

`SNK_IDLE → SNK_CAPTURE → SNK_DONE → SNK_IDLE`

Always-asserts `m_axis_tready` in CAPTURE state (no backpressure).
Writes to `output_mem[snk_ptr]` while `output_count < OUTPUT_MAX_LEN`.
Extra samples beyond OUTPUT_MAX_LEN are discarded; `output_overflow_sticky` is set.
Terminates when `done_sticky` (set one cycle after `dut_done`) is observed.

### Timeout

Safety counter: if `running` and `timeout_cnt >= TIMEOUT_CYCLES`, `done_sticky` is forced set.
Prevents simulation / hardware hangs on misconfigured runs.

### Output Overflow

Sink always accepts samples (tready=1 in CAPTURE). Only writes to output_mem while
`output_count_r < OUTPUT_MAX_LEN`.  When more samples arrive: `output_overflow_sticky` is
asserted.  OUTPUT_COUNT is capped at OUTPUT_MAX_LEN.

## Files

| File | Description |
|------|-------------|
| `rtl/frac_cfo_sync_bram_test_wrapper.v` | RTL: AXI-Lite slave + dual BRAM + FSMs + DUT |
| `tb/frac_cfo_sync_bram_test_wrapper_tb.sv` | T1–T12 simulation testbench |
| `scripts/run_frac_cfo_sync_bram_test_wrapper_sim.sh` | xsim compile + run script |

## Simulation Results

```
Run: bash scripts/run_frac_cfo_sync_bram_test_wrapper_sim.sh
PASS=23  FAIL=0
CI GATE: PASSED
```

Regressions unchanged:
```
Run: bash scripts/run_frac_cfo_sync_axi_stream_wrapper_sim.sh
PASS=23  FAIL=0  CI GATE: PASSED

Run: bash scripts/run_frac_cfo_frame_corrector_top_sim.sh
PASS=176  FAIL=0  CI GATE: PASSED
```

## Test Groups

| Test | Description | Checks |
|------|-------------|--------|
| T1  | STATUS=0 after reset | STATUS=0 |
| T2  | Write enable, read CONTROL back | bresp=OKAY, enable bit set |
| T3  | INPUT_LEN / OUTPUT_MAX_LEN write/read | Both values round-trip |
| T4  | CFG register byte strobe | Full write, then strobe[3] only |
| T5  | input_mem write/read | 0x12345678 round-trips |
| T6  | output_mem = 0 before run | Read returns 0 |
| T7  | Known-vector run (8 quiet + 20 active) | done_sticky=1, no frame_error, INPUT_CNT=28, OUTPUT_CNT=20, read OKAY |
| T8  | Write output_mem → SLVERR | bresp=SLVERR |
| T9  | Read unmapped address → SLVERR | rresp=SLVERR |
| T10 | Output overflow (OUTPUT_MAX_LEN=5) | overflow_sticky=1, OUTPUT_CNT=5 |
| T11 | Soft reset clears all status | STATUS=0, INPUT_CNT=0, OUTPUT_CNT=0 |
| T12 | clr_status_pulse clears done_sticky | done_sticky 1→0 |

## Implementation Notes

### Option A (direct DUT instantiation)

Instantiating `frac_cfo_frame_corrector_top` directly (rather than nesting through
`frac_cfo_sync_axi_stream_wrapper`) avoids having two AXI-Lite slaves compete for the
same bus.  The wrapper re-implements the same control logic inline.

### threshold_in zero-extension fix

Same fix as Step 25: parameter `THRESHOLD` is a 32-bit `integer`.  The DUT port
`threshold_in` is `ENERGY_WIDTH=40` bits wide.  Using `THRESHOLD[ENERGY_WIDTH-1:0]`
produces X for bits [39:32] in xsim.

Fix applied:
```verilog
.threshold_in  ({{(ENERGY_WIDTH-32){1'b0}}, THRESHOLD[31:0]}),
```

### No-backpressure sink

The sink FSM asserts `m_axis_tready=1` unconditionally in `SNK_CAPTURE` state.
This prevents the DUT from stalling mid-frame, which would corrupt the pipeline
latency alignment and produce incorrect output.

## Step 27 Recommendation

- Connect AXI-Lite cfg registers (INPUT_LEN, OUTPUT_MAX_LEN, THRESHOLD, WINDOW_LEN,
  HIT_COUNT) to runtime DUT inputs (currently compile-time parameters).
- Or: integer CFO estimator (int_cfo_estimator.v) integration.
