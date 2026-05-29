# P3-06 — Integer CFO Replay Strategy

## 1. Problem Statement

`phase3_sync_top.v` runs the full OFDM synchronization pipeline through integer
CFO estimation and exposes the result as `dbg_integer_cfo_word`. No correction
path exists. The 576 frac-corrected IQ samples that were streamed from
`frac_cfo_frame_corrector_top` have been consumed by `pss_sss_symbol_extractor`
and are no longer available anywhere in the design after `meyr_done` fires.

To produce a fully corrected output frame, the 576 frac-corrected samples must
be replayed through a second CFO corrector configured with the integer CFO step
word. This document specifies three candidate replay architectures and recommends
one for implementation.

---

## 2. System Parameters

| Symbol          | Value (NSC=256, CP_LEN=32) | Notes                                |
|-----------------|----------------------------|--------------------------------------|
| NSC             | 256                        | Subcarrier count                     |
| CP_LEN          | 32                         | Cyclic prefix length                 |
| FRAME_LEN       | 576 samples                | 2×(NSC+CP_LEN); output of frac corr |
| IQ_WIDTH        | 16 bits per component      | {Q[31:16], I[15:0]} packed           |
| Sample width    | 32 bits                    | Both I and Q components              |
| Buffer size     | 576 × 32b = 18,432 b       | ≈ 2.25 KB                            |
| INT_CFO_SHIFT   | 24 bits                    | 32 − log2(NSC)                       |
| step_word       | −int_cfo <<< 24 (32b)      | Latched in int_cfo_step_word_r       |
| NCO warm-up     | 15 cycles                  | CORDIC_LATENCY in nco_phase_gen      |
| S_CORRECT rate  | 1 sample / 2 clocks        | Buffer read + 1-deep hold FIFO       |
| Replay duration | ≈ 1,152 cycles             | 576 samples × 2                      |
| Meyr latency    | ~130,000+ cycles           | 511 lags × 256 accumulations         |

---

## 3. Current Datapath (Baseline)

```
s_axis ──► frac_cfo_frame_corrector_top  (OUTPUT_SAMPLES=FRAME_LEN=576)
                │ frac_m [tdata/tvalid/tready/tlast]
                ▼
         pss_sss_symbol_extractor ──► meyr_integer_cfo_fft_frontend_top
                                              │ meyr_done
                                              ▼
                                    int_cfo_step_word_r  ──► dbg_integer_cfo_word
                                              │
                                   *** CORRECTION MISSING ***
```

The frac-corrected 576-sample stream is passed to the extractor and discarded.
After `meyr_done`, the step word is stable but there is no second corrector
and no copy of the 576-sample frame.

---

## 4. Architecture Options

### Option A — 576-Sample Replay Buffer (Recommended)

**Concept:**
Tap the frac-corrected stream (`frac_m_tdata/tvalid/tready`) and write every
accepted sample into a dedicated 576×32b SRAM (the "replay buffer"). The write
is a side-effect tap: the existing path to the extractor is unchanged. After
`meyr_done` fires and `int_cfo_step_word_r` is stable, replay the buffer through
a second `frac_cfo_corrector_top` instance (NCO + complex_rotator) configured
with the 32-bit integer CFO step word. The replayed output is the fully corrected
frame emitted on a new output AXIS port.

```
frac_m stream ──┬──► pss_sss_symbol_extractor (existing, unchanged)
                │
                └──► iq_replay_buffer_576   ← write on (tvalid & tready)
                              │
                    (after meyr_done, NCO warm-up)
                              ▼
                   frac_cfo_corrector_top #2   ← step_word = int_cfo_step_word_r
                              │
                   m_int_cfo_axis [tdata/tvalid/tready/tlast]
```

**Required buffer size:**
576 × 32 bits = 18,432 bits. One Xilinx BRAM18E2 (simple dual-port mode:
write port taps frac_m, read port feeds corrector #2 during replay).

**Latency:**
Additional latency relative to current `meyr_done` signal:
  NCO warm-up  = 15 cycles
  Replay       = 576 × 2 cycles = 1,152 cycles
  Total added  ≈ 1,167 cycles (~11.7 μs at 100 MHz)

`meyr_done` itself fires ~130K cycles after the last SSS sample is received,
which is the dominant term. The replay overhead is < 1% of total frame time.

**AXIS backpressure behavior:**
During the capture phase, the replay buffer write port has no backpressure; it
always accepts when `frac_m_tvalid & frac_m_tready`. The extractor drives
`frac_m_tready` normally. During the replay phase, `m_int_cfo_tready` from the
downstream consumer controls the output rate. Backpressure must be propagated
back through the replay FSM (hold register + can_issue logic, identical to the
pattern in `frac_cfo_frame_corrector_top` S_CORRECT).

**TLAST behavior:**
- Capture: TLAST on sample index 575 (mirrors `frac_m_tlast`). The replay buffer
  tracks a write counter; `tlast` is re-generated during replay at the same index.
- Replay: `m_int_cfo_tlast` asserts on the 576th output sample regardless of
  downstream backpressure.

**Debug/status impact:**
New top-level status ports: `replay_busy`, `replay_done`, `replay_error`.
Existing `dbg_integer_cfo_valid` / `dbg_integer_cfo_word` are unaffected.
`done` of phase3_sync_top is extended: pulses only after replay completes,
or optionally a separate `replay_done` port is added so `done` retains its
current single-pass meaning for backward compatibility.

**Synthesis/resource impact (Xilinx Artix/Kintex/Zynq target):**
- 1× BRAM18E2 (simple dual-port, 1K×18b per side — 576×32b fits with padding)
- ~16 DSP48E2 for the second `complex_mult_iq` (same as the first corrector)
- ~50–80 LUTs for replay FSM + replay counter + AXIS steering logic
- NCO: 256-entry distributed ROM (~256 LUTs) + 15 pipeline registers

**Compatibility with current phase3_sync_top:**
- No existing module interfaces change.
- The `frac_m` tap is purely observational (write-only side port).
- The top FSM gains a new state `S_REPLAY` after `S_RUN`:
  `S_RUN` → `meyr_done` → latch step word → assert `replay_start` → `S_REPLAY`
  `S_REPLAY` → `replay_done` → `S_DONE`
- All existing debug ports (`dbg_*`) remain connected identically.

**Verification plan:**
See Section 6 (TB matrix T01–T07).

---

### Option B — Two-Pass External DMA/Host Replay

**Concept:**
The first pass runs the current pipeline as-is to estimate integer CFO. The host
reads `dbg_integer_cfo_word` via AXI-Lite, programs the combined (frac + int)
CFO into a configurable streaming corrector, re-issues the original IQ data stream,
and the second pass produces the corrected output.

**Required buffer size:**
Zero additional on-chip BRAM. The host holds the raw IQ samples in DDR/DRAM.

**Latency:**
Two full frame processing cycles plus DMA transfer round-trip. For a 576-sample
frame at 30.72 MSps, one frame ≈ 18.75 μs raw. Including DMA overhead:
total latency is on the order of 40–100 μs, 3–10× higher than Option A.
This is incompatible with real-time receiver operation.

**AXIS backpressure behavior:**
Standard; the DMA engine handles flow control on both passes independently.

**TLAST behavior:**
Standard per-frame TLAST from the DMA descriptor.

**Debug/status impact:**
Requires AXI-Lite slave with a readable `int_cfo_word` register and a writable
`int_cfo_step_word` register for the combined corrector. Significant additional
interface logic.

**Synthesis/resource impact:**
Minimal on-chip memory addition, but requires AXI-Lite register block, DMA engine,
and host-side software driver — significant integration complexity.

**Compatibility with current phase3_sync_top:**
Requires AXI-Lite wrapper and DMA integration. A separate streaming CFO corrector
(e.g., `streaming_cfo_corrector`) must be added in the DMA path.

**Why rejected:**
- Doubles minimum frame latency; incompatible with real-time operation.
- Requires host software intervention for every frame — fragile.
- No deterministic latency guarantee (DMA scheduling jitter).

---

### Option C — Delayed Streaming with Large FIFO

**Concept:**
Insert a large FIFO between the frac CFO corrector output and the final output.
Hold all 576 frac-corrected samples in the FIFO until `meyr_done` fires. Then
pass the held samples through a streaming integer CFO corrector and release them.

**Required buffer size:**
The FIFO must hold all data produced during the entire time from the first
frac-corrected sample until `meyr_done`. The frac corrector starts streaming
at cycle 0. The Meyr estimator finishes approximately:
  - PSS extraction starts at sample CP_LEN=32 (~64 cycles into streaming)
  - SSS extraction ends at sample FRAME_LEN=576 (~1152 cycles into streaming)
  - Meyr receives 256 pairs; correlation: 511 lags × 256 accums ≈ 130,816 cycles
  - FFT latency (fft256_xilinx_wrapper): ~300–500 cycles typical
  - meyr_done fires approximately 132,000+ cycles after the first frac-corrected
    sample is produced

All frac-corrected samples (576 at 2 clk/sample = 1152 cycles) are produced
well before `meyr_done`. But the FIFO must hold 576 samples AND remain
backpressure-free for the extractor while the Meyr pipeline runs (132K cycles).
576-sample FIFO fits in 1 BRAM18E2 — but this is only feasible if the 576 samples
fit before `meyr_done`. They do fit: 576 samples arrive in ~1152 cycles while
`meyr_done` is ~132K cycles away. So the FIFO depth required is exactly 576.

However, this option has a fundamental flow-control problem: the FIFO must
simultaneously:
  (a) accept samples from the frac corrector (write port)
  (b) pass samples to the extractor (read port — for PSS/SSS extraction)
  (c) re-read samples for integer CFO correction after `meyr_done` (second read)

A single FIFO cannot be simultaneously read twice. Implementing both (b) and (c)
requires either:
  - A dual-read-port FIFO (not standard)
  - Two separate FIFOs or a scatter approach (write twice)
  - A 576-sample random-access buffer (which becomes identical to Option A)

Once a FIFO becomes a random-access buffer to support two independent read streams,
Option C collapses into Option A.

**Additional risk:**
If `meyr_done` never fires (estimator error), the FIFO would block indefinitely,
stalling s_axis_tready for all downstream consumers.

**Why rejected:**
- Requires dual-read-port or scatter buffer — equivalent hardware to Option A.
- Introduces indefinite stall on estimator timeout.
- AXIS backpressure during FIFO hold stalls the entire input path for ~132K cycles
  if implemented naively — impractical in a streaming pipeline.

---

## 5. Option Comparison Summary

| Criterion                  | Option A (Replay Buffer)    | Option B (DMA Host)      | Option C (FIFO)            |
|----------------------------|-----------------------------|--------------------------|----------------------------|
| Additional buffer depth    | 576 × 32b (1 BRAM18)        | 0 on-chip (DDR)          | 576 × 32b (1 BRAM18)       |
| Additional latency         | ~1,167 cycles               | 2× frame + DMA overhead  | ~1,167 cycles (if feasible)|
| AXIS backpressure clean?   | Yes                         | Yes (DMA-managed)        | No — stalls input path     |
| TLAST clean?               | Yes                         | Yes                      | Complex (two read passes)  |
| Host software required?    | No                          | Yes                      | No                         |
| Real-time compatible?      | Yes                         | No                       | No (indefinite stall risk) |
| New RTL modules needed     | iq_replay_buffer_576 +      | AXI-Lite regs + DMA      | Dual-read FIFO (non-std)   |
|                            | frac_cfo_corrector_top inst  |                          | or reverts to Option A     |
| BRAM18E2 count             | 1                           | 0                        | 1 (if feasible)            |
| DSP48E2 count              | +16                         | +16 (in DMA path)        | +16                        |
| Complexity                 | Low — mirrors existing FSM  | High — software driver   | High — dual-port logic     |
| Risk                       | Low                         | Medium–High              | High (stall, collapse)     |

---

## 6. Recommended Architecture: Option A

**Rationale:**
Option A is self-contained, adds deterministic latency (~1,167 cycles), requires
only 1 BRAM18E2, and mirrors the already-proven buffer+replay pattern in
`frac_cfo_frame_corrector_top`. No host software, no dual-port memory, and no
indefinite stall risk. It is the natural completion of the Phase 3 pipeline as
described in the project memory and the comment block in `phase3_sync_top.v`.

**Risks:**
1. The replay buffer write counter must be reset exactly at the start of the
   frac-corrected output stream (tied to `frac_start_r`). A missed reset would
   capture stale data → wrong correction.
2. The replay FSM must handle `m_int_cfo_tready = 0` without losing samples
   (hold register pattern).
3. NCO phase must be reset to 0 before replay starts (same as S_LOAD_NCO in
   `frac_cfo_frame_corrector_top`).
4. Two consecutive frames must not overlap: replay must complete before the next
   `start` is accepted (enforced by the `busy` signal).

---

## 7. Future Interface Proposal

The following ports would be added to `phase3_sync_top` (or to a new wrapper
`phase3_int_cfo_replay_top` that wraps the current top without modifying it):

### Control Ports

| Port name              | Width | Dir | Description                                              |
|------------------------|-------|-----|----------------------------------------------------------|
| `int_cfo_apply_enable` | 1     | in  | 1 = enable integer CFO correction; 0 = replay disabled  |
| `int_cfo_step_word`    | 32    | out | NCO step word for integer CFO (latched from meyr_done)   |
| `replay_start`         | 1     | out | 1-cycle pulse when replay begins (for debug/ILA)         |
| `replay_busy`          | 1     | out | Asserted during the replay pass                          |
| `replay_done`          | 1     | out | 1-cycle pulse on replay completion                       |
| `replay_error`         | 1     | out | Sticky: set on replay timeout or buffer overrun          |

### Output Frame AXIS Ports

| Port name               | Width    | Dir | Description                                 |
|-------------------------|----------|-----|---------------------------------------------|
| `m_int_cfo_tdata`       | 32       | out | Integer-CFO-corrected IQ: {Q[31:16],I[15:0]}|
| `m_int_cfo_tvalid`      | 1        | out | AXIS valid for corrected output              |
| `m_int_cfo_tready`      | 1        | in  | AXIS ready from downstream consumer         |
| `m_int_cfo_tlast`       | 1        | out | Asserts on sample 575 of the corrected frame |

### Internal Signals (new module: `iq_replay_buffer_576`)

| Signal                  | Width    | Description                                        |
|-------------------------|----------|----------------------------------------------------|
| `wr_en`                 | 1        | = `frac_m_tvalid & frac_m_tready` (tap)            |
| `wr_addr`               | 10       | Write pointer, 0..575, reset on `frac_start_r`     |
| `wr_data`               | 32       | = `frac_m_tdata`                                   |
| `rd_en`                 | 1        | Issued by replay FSM                               |
| `rd_addr`               | 10       | Read pointer, 0..575, incremented during replay    |
| `rd_data`               | 32       | Registered output (1-cycle read latency)           |
| `capture_done`          | 1        | Pulses when `wr_addr == 575` and write fires       |

### New FSM States in phase3_sync_top

```
S_IDLE  → start     → S_RUN
S_RUN   → frac_frame_error  → S_DONE (error)
S_RUN   → meyr_done         → [int_cfo_apply_enable?] → S_REPLAY or S_DONE
S_REPLAY → NCO warm-up (15 cycles) → stream 576 samples → replay_done → S_DONE
S_DONE  → done pulse → S_IDLE
```

`busy` remains asserted throughout S_RUN and S_REPLAY.
`done` pulses in S_DONE only after replay (or immediately if apply_enable=0).

---

## 8. New Module: iq_replay_buffer_576 (Proposed Interface)

```verilog
module iq_replay_buffer_576 #(
    parameter integer DATA_WIDTH   = 32,
    parameter integer FRAME_LEN    = 576,
    parameter integer ADDR_WIDTH   = 10   // 2^10=1024 >= 576
) (
    input  wire                    aclk,
    input  wire                    aresetn,

    // Capture side (tap from frac_m stream)
    input  wire                    capture_reset,   // pulse on frac_start_r
    input  wire                    wr_en,           // frac_m_tvalid & frac_m_tready
    input  wire [DATA_WIDTH-1:0]   wr_data,         // frac_m_tdata
    output wire                    capture_done,    // 1-cycle: wrote sample 575

    // Replay side (driven by replay FSM)
    input  wire                    rd_en,
    input  wire [ADDR_WIDTH-1:0]   rd_addr,
    output wire [DATA_WIDTH-1:0]   rd_data          // 1-cycle registered latency
);
```

Implementation: simple dual-port BRAM or distributed RAM (BUF_AW=10, depth=1024).
BRAM option: `(* ram_style = "block" *)` attribute, 1 BRAM18E2.

---

## 9. New Module: int_cfo_corrector_pass (Proposed Interface)

This is a thin wrapper around the existing `frac_cfo_corrector_top` that accepts
a 32-bit step word directly (bypassing the Q1.15 → step conversion in
`streaming_cfo_corrector`):

```verilog
module int_cfo_corrector_pass #(
    parameter integer IQ_WIDTH         = 16,
    parameter integer NCO_PHASE_WIDTH  = 32,
    parameter integer CORDIC_LATENCY   = 15
) (
    input  wire                            aclk,
    input  wire                            aresetn,

    // Step word (from int_cfo_step_word_r, stable before load_step pulse)
    input  wire                            load_step,
    input  wire signed [NCO_PHASE_WIDTH-1:0] step_word,
    input  wire                            phase_reset,
    input  wire                            nco_enable,

    // AXI-Stream IQ input
    input  wire [2*IQ_WIDTH-1:0]           s_axis_tdata,
    input  wire                            s_axis_tvalid,
    output wire                            s_axis_tready,
    input  wire                            s_axis_tlast,

    // AXI-Stream IQ output (corrected)
    output wire [2*IQ_WIDTH-1:0]           m_axis_tdata,
    output wire                            m_axis_tvalid,
    input  wire                            m_axis_tready,
    output wire                            m_axis_tlast,

    output wire                            sincos_valid
);
```

Internally instantiates `frac_cfo_corrector_top` with the 32-bit step word fed
directly to `load_step` / `step_word`. No Q1.15 conversion needed because
`int_cfo_step_word_r` is already a 32-bit NCO accumulator increment.

---

## 10. Testbench Matrix

All tests target the future `phase3_int_cfo_replay_top` (or equivalent).
`int_cfo_apply_enable = 1` unless stated.

| ID  | Name                          | Stimulus                                   | Pass Criterion                                              |
|-----|-------------------------------|--------------------------------------------|-------------------------------------------------------------|
| T01 | Zero integer CFO              | int_cfo=0 → step_word=0                    | Output matches frac-corrected input sample-for-sample       |
| T02 | +1 bin integer CFO            | int_cfo=+1 → step_word=−2^24              | Output IQ rotated by +2π/NSC per sample; phase slope check |
| T03 | −1 bin integer CFO            | int_cfo=−1 → step_word=+2^24              | Output IQ rotated by −2π/NSC per sample; phase slope check |
| T04 | Backpressure during replay    | m_int_cfo_tready toggled low mid-replay    | No samples dropped; tlast fires correctly; no FSM stall     |
| T05 | Integer CFO invalid timeout   | meyr_done never fires; watchdog added      | replay_error asserts after timeout; top enters S_DONE;      |
|     |                               |                                            | m_int_cfo stream not started; reset recovers cleanly        |
| T06 | Reset during replay           | aresetn deasserted mid-replay              | All state machines return to S_IDLE; no ghost output valid; |
|     |                               |                                            | next `start` begins fresh frame cleanly                     |
| T07 | Two frames back-to-back       | Second `start` issued immediately after    | Second frame replay buffer captures new data;               |
|     |                               | first `done`                               | First frame output not corrupted; busy deasserts between    |

### T02 / T03 Phase Slope Check Detail

For int_cfo=+1, the corrector applies `exp(-j * 2π * (+1) * n / NSC)` per sample.
Expected output at sample n relative to sample 0:
  I_out[n] = I_in[n] * cos(−2πn/256) − Q_in[n] * sin(−2πn/256)
  Q_out[n] = Q_in[n] * cos(−2πn/256) + I_in[n] * sin(−2πn/256)
Tolerance: ±2 LSB (Q1.15 NCO ROM quantization error at 16-bit precision).

---

## 11. Risks and Mitigations

| Risk                                              | Mitigation                                               |
|---------------------------------------------------|----------------------------------------------------------|
| Capture counter not reset on frac_start_r         | Tie capture_reset to frac_start_r; verify in T07        |
| NCO phase not reset before replay                 | Assert phase_reset=1 one cycle before load_step (same   |
|                                                   | sequence as S_LOAD_NCO in frac_cfo_frame_corrector_top) |
| m_int_cfo_tready stall causes BRAM read overrun   | Hold register + can_issue gating (copy S_CORRECT FSM)   |
| Replay buffer overwritten if FRAME_LEN > depth    | Parameterize ADDR_WIDTH = ⌈log2(FRAME_LEN)⌉+1; assert  |
|                                                   | FRAME_LEN ≤ 2^ADDR_WIDTH in RTL generate check          |
| meyr_done timeout leaves busy asserted forever    | Add replay watchdog counter; assert replay_error        |
| Two frames overlapping (start while replay busy)  | busy=1 during S_REPLAY; start is gated by !busy check  |

---

## 12. Next Implementation Step

1. Create `rtl/iq_replay_buffer_576.v` — 576×32b simple-dual-port BRAM wrapper
   with capture_reset / write port / registered read port.

2. Create `rtl/int_cfo_corrector_pass.v` — thin wrapper around existing
   `frac_cfo_corrector_top` with direct 32-bit step word input.

3. Add `S_REPLAY` state to `phase3_sync_top.v` FSM (after S_RUN, before S_DONE).

4. Instantiate `iq_replay_buffer_576` at top level, tapping `frac_m` handshake.

5. Instantiate `int_cfo_corrector_pass` at top level, feeding from replay buffer.

6. Add output ports: `replay_busy`, `replay_done`, `replay_error`,
   `m_int_cfo_tdata/tvalid/tready/tlast`.

7. Run testbench T01–T07 before integration.

No existing RTL file is modified in steps 1–2. Steps 3–6 modify only
`phase3_sync_top.v` (additive changes: new instantiations, new FSM state,
new ports — no existing logic removed or altered).
