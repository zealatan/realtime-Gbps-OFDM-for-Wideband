# Step 4 — Full RTL Architecture and Module Boundary Specification

## 0. Document Purpose and Scope

This document defines the complete RTL architecture, module hierarchy, per-module port lists,
FSM state machine, inter-module handshake protocols, memory allocation, latency budget, and
build order for `ofdm_synchronizer_top.v`.

No RTL is written here. This document is the authoritative reference for all subsequent
implementation steps (Steps 6–30).

All fixed-point widths, AXI-Stream formats, and the AXI-Lite register map are inherited from
`docs/step3_fixedpoint_spec.md` without repetition. Widths are referenced by parameter name.

---

## 1. Architecture Overview

### 1.1 Buffer-Then-Process Rationale

The C `synchronization()` function operates on an in-memory float array of `rxLen` samples.
It accesses samples non-sequentially: the CP autocorrelation reads two windows that are
`NSC = 256` samples apart; the PSS and SSS symbol extractors skip to fixed offsets inside
the slot; the corrected buffer is read again for the Meyr correlation. This random-access
pattern makes pure streaming unsafe for a first implementation for several reasons:

| Issue | Pure streaming | Buffer-then-process |
|---|---|---|
| CP autocorrelation needs rx[m] and rx[m+NSC] simultaneously for each of 256 lags | Requires two independent 256-sample delay lines consuming 2×256×32 = 16 Kbit of shift register or FIFO | Single BRAM read at two addresses; no shift register needed |
| PSS at slotStart+CP_LEN, SSS at slotStart+2×CP_LEN+NSC — known only after frame detection | Symbol extractor would need to buffer the entire slot and replay from an arbitrary start | Direct random-access to BRAM by address |
| Fractional CFO correction must re-read the same slot after the CFO is known | Requires either a second buffer or pipeline stall until CORDIC atan2 returns | FSM sequentially reads buffer; no pipeline hazard |
| Integer CFO correction needs to re-read the already-fractionally-corrected slot | Same problem; third pass over data | Third buffer read pass; trivial with BRAM addressing |
| Verification: each stage can be checked independently with known buffer contents | Hard to inject mid-pipeline stimuli | Freeze buffer, run one stage, check outputs |

Pure streaming is appropriate once all pipeline latencies are characterized and timing is
fixed. The buffer-then-process architecture provides a correct, verifiable first RTL target.
Streaming optimization is deferred to post-Step-27.

### 1.2 High-Level Block Diagram

```
                    ┌──────────────────────────────────────────────────────────┐
                    │                 ofdm_synchronizer_top.v                  │
                    │                                                           │
  s_axis_iq  ──────►│ sample_buffer.v       ◄───── sync_control_fsm.v ──────── │
  (32-bit)   ◄──────│ (4096 × 32-bit BRAM)  ──────► (master sequencer FSM)    │
  m_axis_iq         │         │                          │                     │
                    │         │ rd_I, rd_Q               │ enables, addresses  │
                    │         ▼                          ▼                     │
                    │ ┌──────────────┐     ┌──────────────────────────────┐    │
                    │ │frame_detector│     │   axi_lite_sync_regs.v       │    │
                    │ └──────┬───────┘     │   (config + status registers)│◄───┤ AXI-Lite
                    │        │frame_index  └──────────────────────────────┘    │
                    │        ▼                                                  │
                    │ ┌─────────────────┐                                      │
                    │ │cp_autocorr_core │                                      │
                    │ └──────┬──────────┘                                      │
                    │        │ corr[256], norm_E[256]                          │
                    │        ▼                                                  │
                    │ ┌──────────────────┐  ┌──────────────┐                  │
                    │ │timing_metric_core│─►│peak_detector │                  │
                    │ └──────────────────┘  └──────┬───────┘                  │
                    │                              │ peak_lag                  │
                    │ ┌───────────────────────┐    │                           │
                    │ │frac_cfo_estimator.v   │◄───┘                          │
                    │ │ └─ cordic_atan2.v     │                                │
                    │ └──────────┬────────────┘                                │
                    │            │ frac_phase (16-bit)                         │
                    │            ▼                                              │
                    │ ┌──────────────────────────────────┐                    │
                    │ │ nco_phase_gen.v  (shared NCO)    │                    │
                    │ │  └─ [Xilinx CORDIC sincos mode]  │                    │
                    │ └──────────┬───────────────────────┘                    │
                    │            │ sin/cos (16-bit Q1.15)                      │
                    │            ▼                                              │
                    │ ┌──────────────────────────────────┐                    │
                    │ │complex_rotator.v  (shared)       │                    │
                    │ │  └─ complex_mult_iq.v             │                    │
                    │ └──────────────────────────────────┘                    │
                    │   ▲ reads sample_buffer                                  │
                    │   │ writes corrected samples back to sample_buffer       │
                    │   │                                                       │
                    │ ┌─────────────────────────────────────────────────┐     │
                    │ │ integer_cfo_estimator.v                          │     │
                    │ │  ├─ symbol_extractor.v                           │     │
                    │ │  ├─ fft_wrapper.v  (256-pt × 2 instances)       │     │
                    │ │  ├─ pss_sss_rom.v                                │     │
                    │ │  ├─ complex_mult_iq.v  (term1 and term2)        │     │
                    │ │  └─ meyr_corr_core.v                             │     │
                    │ │      ├─ fft_wrapper.v  (512-pt, reconfigurable) │     │
                    │ │      └─ complex_mult_iq.v  (freq-domain mult)   │     │
                    │ └─────────────────────┬───────────────────────────┘     │
                    │                       │ int_cfo (9-bit signed)           │
                    │                       ▼                                  │
                    │ ┌──────────────────────────────────┐                    │
                    │ │integer_cfo_corrector.v            │                    │
                    │ │  (reprograms shared NCO + rotator)│                   │
                    │ └──────────────────────────────────┘                    │
                    │     └──► m_axis_iq output stream                         │
                    └──────────────────────────────────────────────────────────┘
```

### 1.3 Top-Level Processing Sequence

The sync_control_fsm advances through the following states in order. Each state is active
until the active submodule asserts its `done` output.

```
IDLE
  │  (SW writes 1 to CTRL.START)
  ▼
FILL_BUFFER
  │  Accepts AXI-Stream input samples; writes into sample_buffer sequentially.
  │  Transitions when s_axis_iq_tlast is received OR sample_count register is reached.
  ▼
FRAME_DETECT
  │  Runs frame_detector.v over the buffered samples.
  │  Output: frame_index (sample offset of detected slot boundary).
  │  → ERROR if frame not found.
  ▼
CP_AUTOCORR
  │  Runs cp_autocorr_core.v starting at frame_index in the buffer.
  │  Stores 256 complex correlations and 256 normalization values internally.
  │  Then runs timing_metric_core.v and peak_detector.v.
  │  Output: peak_lag (timing offset, INDEX_WIDTH bits).
  ▼
FRAC_CFO_EST
  │  Reads autocorr_I[peak_lag] and autocorr_Q[peak_lag] from cp_autocorr_core storage.
  │  Runs frac_cfo_estimator.v (CORDIC atan2, 15-cycle latency).
  │  Output: frac_phase (PHASE_WIDTH = 16-bit signed, ±π radians).
  │  Computes NCO step word: step = round(−frac_phase × 2^32 / (2π)).
  ▼
FRAC_CFO_CORR
  │  Programs nco_phase_gen.v with frac step word; resets NCO phase to 0.
  │  Runs complex_rotator.v over symbols_per_slot samples starting at slotStartIndex.
  │  slotStartIndex = frame_index + peak_lag.
  │  Writes corrected samples back into sample_buffer at the same addresses.
  │  Output: corrected IQ in buffer; NCO+CORDIC latency absorbed by pipeline.
  ▼
INT_CFO_EST
  │  Runs integer_cfo_estimator.v.
  │    → symbol_extractor reads PSS (slotStart+CP_LEN, 256 samples) from buffer.
  │    → fft_wrapper (256-pt) computes PSS FFT.
  │    → symbol_extractor reads SSS (slotStart+2×CP_LEN+NSC, 256 samples).
  │    → fft_wrapper (256-pt) computes SSS FFT.
  │    → pss_sss_rom provides mU[j] and goldU[j] references.
  │    → complex_mult_iq: term1[j] = conj(PSS_FFT[j]) × SSS_FFT[j].
  │    → complex_mult_iq: term2[j] = conj(mU[j+CP_LEN]) × goldU[j+CP_LEN].
  │    → meyr_corr_core: 512-pt FFT of term1, 512-pt FFT of term2,
  │                       freq-domain conj(A)×B, 512-pt IFFT.
  │    → peak_detector (511-point complex-magnitude argmax).
  │  Output: int_cfo = peak_index − (NSC−1).
  ▼
INT_CFO_CORR
  │  Computes integer NCO step: step = round(−int_cfo × 2^32 / NSC).
  │  Programs nco_phase_gen.v (resets phase to 0).
  │  Runs complex_rotator.v over symbols_per_slot samples at slotStartIndex.
  │  Output: final corrected IQ streamed directly to m_axis_iq output.
  ▼
DONE
  │  Asserts STATUS.DONE. Writes frame_index, peak_lag, frac_cfo, int_cfo to AXI-Lite status.
  │  Holds until SW clears by writing CTRL.START again.
  ▼
ERROR  (reachable from FRAME_DETECT if no frame found, or from any state on timeout)
     Asserts STATUS.ERROR.
```

---

## 2. Module Hierarchy

```
ofdm_synchronizer_top.v
│
├── axi_lite_sync_regs.v              [new]  AXI-Lite slave, 15 registers
│
├── sync_control_fsm.v                [new]  Master sequencer FSM
│
├── sample_buffer.v                   [new]  4096×32-bit true dual-port BRAM
│
├── frame_detector.v                  [new]  Energy sliding-window frame detector
│
├── cp_autocorr_core.v                [new]  256-lag × 32-tap complex MAC engine
│   └── [internal 256-entry corr/norm BRAM or dist-RAM]
│
├── timing_metric_core.v              [new]  2|corr| − E metric computation
│
├── peak_detector.v                   [new]  Parameterized argmax (shared)
│
├── frac_cfo_estimator.v              [new]  Reads autocorr peak → CORDIC → phase
│   └── cordic_atan2.v                [new]  Xilinx CORDIC IP v6.0, translate mode
│
├── nco_phase_gen.v                   [new]  Shared 32-bit NCO (frac + int corrections)
│   └── [Xilinx CORDIC IP, sincos mode, or sin/cos ROM]
│
├── complex_rotator.v                 [new]  Per-sample rotation (uses nco_phase_gen output)
│   └── complex_mult_iq.v             [new]  Thin wrapper: swaps I↔upper, Q↔lower for axis_complex_mult
│       └── axis_complex_mult.v       [EXISTING, unmodified]
│
├── integer_cfo_estimator.v           [new]  Meyr integer CFO top wrapper
│   ├── symbol_extractor.v            [new]  CP removal + address generation
│   ├── fft_256_pss.v                 [new]  Instance 1: 256-pt FFT for PSS
│   │   └── fft_wrapper.v             [new]  Xilinx FFT IP wrapper
│   ├── fft_256_sss.v                 [new]  Instance 2: 256-pt FFT for SSS
│   │   └── fft_wrapper.v             [new]  Same wrapper, second instance
│   ├── pss_sss_rom.v                 [new]  ROM: mU[288], goldU[288] (Q1.15)
│   ├── term_mult_1.v                 [new]  conj(PSS_FFT) × SSS_FFT
│   │   └── complex_mult_iq.v         [new]  Reused
│   ├── term_mult_2.v                 [new]  conj(mU) × goldU
│   │   └── complex_mult_iq.v         [new]  Reused
│   └── meyr_corr_core.v              [new]  512-pt cross-correlation engine
│       ├── fft_512.v                 [new]  512-pt FFT (reconfigurable fwd/inv)
│       │   └── fft_wrapper.v         [new]  Parameterized for 512-pt
│       └── freq_mult.v               [new]  conj(A) × B in freq domain
│           └── complex_mult_iq.v     [new]  Reused
│
└── integer_cfo_corrector.v           [new]  Step-word calc; drives shared NCO+rotator
```

**Shared hardware note.** `nco_phase_gen.v` and `complex_rotator.v` are instantiated once
in `ofdm_synchronizer_top.v` and driven by both `sync_control_fsm.v` (for FRAC_CFO_CORR)
and `integer_cfo_corrector.v` (for INT_CFO_CORR). The FSM arbitrates access: only one
correction pass runs at a time.

**fft_wrapper.v.** A single parameterized Verilog module. Instantiated three times with
different FFT_SIZE and/or direction settings:
- `fft_256_pss.v` / `fft_256_sss.v`: FFT_SIZE=256, always forward.
- `fft_512.v` inside `meyr_corr_core.v`: FFT_SIZE=512, direction controlled by
  `s_axis_config` (run forward twice, then inverse once).

---

## 3. Top-Level Port List — ofdm_synchronizer_top.v

```
Parameter               Default   Description
─────────────────────── ───────── ────────────────────────────────────────────
DATA_WIDTH              32        AXI-Stream TDATA width
SAMPLE_FRAC_BITS        15        Q1.15 fractional bits
POWER_WIDTH             32        Per-sample energy width
ACC_WIDTH               40        Correlation / energy accumulator width
METRIC_WIDTH            32        Timing metric output width
PHASE_WIDTH             16        CFO phase (CORDIC output) width
CORDIC_PHASE_WIDTH      16        CORDIC phase port width
NCO_PHASE_WIDTH         32        NCO phase accumulator width
ROTATOR_COEFF_WIDTH     16        sin/cos coefficient width
FFT_DATA_WIDTH          16        FFT per-component width
MEYR_ACC_WIDTH          40        Meyr peak detection accumulator width
INDEX_WIDTH             9         Sample/peak index width
AXIL_DATA_WIDTH         32        AXI-Lite data bus width
AXIL_ADDR_WIDTH         8         AXI-Lite address bus width
BUFFER_DEPTH            4096      Input sample buffer depth (must be power of 2)
NSC                     256       FFT size / subcarrier count
CP_LEN                  32        Cyclic prefix length
```

```
Signal                   Dir  Width  Description
──────────────────────── ───  ─────  ──────────────────────────────────────────
aclk                     in   1      Master clock (all domains)
aresetn                  in   1      Active-low synchronous reset

// AXI-Stream IQ input
s_axis_iq_tdata          in   32     {Q[31:16], I[15:0]}, Q1.15
s_axis_iq_tvalid         in   1
s_axis_iq_tready         out  1
s_axis_iq_tlast          in   1      Last sample of input burst
s_axis_iq_tuser          in   1      Optional slot-start marker

// AXI-Stream corrected IQ output
m_axis_iq_tdata          out  32     {Q[31:16], I[15:0]}, Q1.15, post-correction
m_axis_iq_tvalid         out  1
m_axis_iq_tready         in   1
m_axis_iq_tlast          out  1      Last corrected sample of slot
m_axis_iq_tuser          out  1      High on first sample after INT_CFO_CORR

// AXI-Lite slave
s_axil_awaddr            in   8
s_axil_awvalid           in   1
s_axil_awready           out  1
s_axil_wdata             in   32
s_axil_wstrb             in   4
s_axil_wvalid            in   1
s_axil_wready            out  1
s_axil_bresp             out  2
s_axil_bvalid            out  1
s_axil_bready            in   1
s_axil_araddr            in   8
s_axil_arvalid           in   1
s_axil_arready           out  1
s_axil_rdata             out  32
s_axil_rresp             out  2
s_axil_rvalid            out  1
s_axil_rready            in   1

// Interrupt
irq_out                  out  1      Pulses high for 1 clock on DONE or ERROR
                                     (gated by INTR_EN register)
```

---

## 4. Module Specifications

### 4.1 sample_buffer.v

**Purpose.** True dual-port BRAM holding up to BUFFER_DEPTH input IQ samples. Port A is
the write port (used during FILL_BUFFER and FRAC_CFO_CORR write-back). Port B is the read
port (used by all processing stages and INT_CFO_CORR output streaming). During
FRAC_CFO_CORR, Port A and Port B address the same sample simultaneously: Port B reads
sample N, Port A writes corrected sample N one clock later (pipeline latency of 1 from
rotator).

```
Parameter           Default   Description
─────────────────── ───────── ──────────────────────────────────
BUFFER_DEPTH        4096      Must be power of 2
DATA_WIDTH          32        Bit width per entry
ADDR_WIDTH          12        = log2(BUFFER_DEPTH)
```

```
Signal              Dir  Width  Description
─────────────────── ───  ─────  ────────────────────────────────────────────────
aclk                in   1
aresetn             in   1

// Port A — write (streaming fill and CFO correction write-back)
a_wr_en             in   1      Write enable
a_wr_addr           in   12     Write address
a_wr_data           in   32     Data to write

// Port B — read (processing stages)
b_rd_en             in   1      Read enable (optional register output enable)
b_rd_addr           in   12     Read address
b_rd_data           out  32     Registered output, available 1 clock after b_rd_en

// Write pointer (fill status)
wr_ptr              out  12     Current write pointer; advanced by FSM during FILL
sample_count_out    out  13     Number of samples written (0..BUFFER_DEPTH)
```

**Memory sizing.** 4096 × 32-bit = 128 Kbit = 2 × BRAM36 (Xilinx 7-series or UltraScale).
A BUFFER_DEPTH of 2048 (1 × BRAM36 = 64 Kbit) is sufficient for NSC=256 systems but
leaves no margin for longer search windows; 4096 is recommended.

**Addressing convention.** Address 0 holds the first received sample. The FSM passes
`frame_index`, `slotStartIndex = frame_index + peak_lag`, and specific symbol offsets to the
processing submodules. All addresses are absolute (relative to buffer base 0).

---

### 4.2 frame_detector.v

**Purpose.** Implements the C `frame_detector()` sliding-window energy detector. Reads
samples sequentially from the buffer and finds the first sample where the signal energy
exceeds `threshold` for `hit_count` consecutive windows.

```
Parameter           Default   Description
─────────────────── ───────── ──────────────────────────────────
POWER_WIDTH         32
ACC_WIDTH           40
WINDOW_LEN_MAX      64        Maximum programmable window length
HIT_COUNT_MAX       16        Maximum programmable hit count
SEARCH_LEN_MAX      4096      Maximum samples to search
```

```
Signal              Dir  Width  Description
─────────────────── ───  ─────  ────────────────────────────────────────────────
aclk / aresetn      in   1

// Control from FSM
start               in   1      Pulse high for 1 clock to begin
threshold           in   32     Energy threshold (POWER_WIDTH)
window_len          in   7      Samples per window (1..WINDOW_LEN_MAX)
hit_count           in   4      Consecutive hits required (1..HIT_COUNT_MAX)
search_base         in   12     Buffer address of first sample to search
search_len          in   13     Number of samples to search

// Buffer read interface
buf_rd_addr         out  12     Address to present to sample_buffer Port B
buf_rd_data_I       in   16     I component from buffer output [15:0]
buf_rd_data_Q       in   16     Q component from buffer output [31:16]

// Outputs
frame_index         out  12     Buffer address of detected slot start
frame_found         out  1      High when search succeeded
done                out  1      High (1 clock) when search complete
busy                out  1      High while running
```

**Internal FSM.** Two-case sequential FSM:
- Case A (start below threshold): scan for first window above threshold, then count
  `hit_count` consecutive above-threshold windows.
- Case B (start above threshold): skip initial above-threshold region, then transition
  to Case A behavior.
Counter: 4-bit `hit_ctr`. Sliding-window accumulator: 40-bit, updated by
add-newest / subtract-oldest.

---

### 4.3 cp_autocorr_core.v

**Purpose.** Computes the Van De Beek CP autocorrelation: for each of NSC=256 lags m,
accumulates CP_LEN=32 complex multiply-accumulates of `conj(rx[m+k]) × rx[m+k+NSC]` and
the corresponding power normalization `|rx[m+k+NSC]|² + |rx[m+k]|²`.

Processes one lag at a time (time-multiplexed). Total computation: 256 lags × 32 taps.

```
Parameter           Default   Description
─────────────────── ───────── ──────────────────────────────────
NSC                 256
CP_LEN              32
ACC_WIDTH           40
PRODUCT_WIDTH       32
INDEX_WIDTH         9
ADDR_WIDTH          12
```

```
Signal              Dir  Width  Description
─────────────────── ───  ─────  ────────────────────────────────────────────────
aclk / aresetn      in   1

// Control
start               in   1      Begin autocorrelation
base_addr           in   12     Buffer address = frame_index (from frame_detector)

// Buffer read interface (Port B of sample_buffer)
buf_rd_addr         out  12     Requested read address
buf_rd_data_I       in   16
buf_rd_data_Q       in   16

// Stored results (readable by frac_cfo_estimator and timing_metric_core via addr)
result_rd_addr      in   9      Lag index to read (0..NSC-1)
result_autocorr_I   out  32     Signed, from 40-bit accumulator truncated upper 8 bits
result_autocorr_Q   out  32     Signed
result_norm_E       out  32     Unsigned, energy normalization

// Status
done                out  1      High (1 clock) when all 256 lags complete
busy                out  1
```

**Timing.** Per-lag: 32 read pairs (2 buffer reads per tap) + 3-cycle MAC pipeline = 35
clocks per lag. Total: 256 × 35 = 8960 clocks ≈ 90 µs at 100 MHz. Buffer Port B provides
one sample per clock; two samples per lag-step are fetched using consecutive addresses
(one for rx[m+k], one for rx[m+k+NSC]), so each tap takes 2 clocks → 32 × 2 = 64 clocks
per lag + pipeline drain = ~67 clocks. Total: 256 × 67 ≈ 17,152 clocks ≈ 172 µs at 100 MHz.
This is acceptable for a one-shot synchronizer.

**Internal storage.** 256 entries × (32+32+32) bits = 3072 bytes. Implemented as three
parallel arrays of 256 × 32-bit registers or a single 256 × 96-bit distributed/block RAM.

---

### 4.4 timing_metric_core.v

**Purpose.** For each lag m, computes the timing metric:
`M[m] = 2 × |autocorr[m]| − norm_E[m]`

where `|autocorr[m]|` is the magnitude of the complex autocorrelation value.

```
Parameter           Default   Description
─────────────────── ───────── ──────────────────────────────────
NSC                 256
METRIC_WIDTH        32
ACC_WIDTH           40
```

```
Signal              Dir  Width  Description
─────────────────── ───  ─────  ────────────────────────────────────────────────
aclk / aresetn      in   1

// Control
start               in   1
num_lags            in   9      Number of lags to compute (default 256)

// Autocorrelation results from cp_autocorr_core (driven by this module's read addr)
result_rd_addr      out  9      Address into cp_autocorr_core result RAM
result_autocorr_I   in   32
result_autocorr_Q   in   32
result_norm_E       in   32

// Output stream to peak_detector
metric_out          out  32     Signed METRIC_WIDTH metric value
metric_valid        out  1      One cycle per lag, sequential m=0..NSC-1
metric_last         out  1      High on lag m=NSC-1

// Status
done                out  1
busy                out  1
```

**Magnitude implementation.** Use the α·max + β·min approximation for first implementation:
`|C| ≈ max(|I|, |Q|) + 0.375 × min(|I|, |Q|)`.
This is purely combinational (one cycle per lag), avoids CORDIC IP dependency in this block,
and gives < 3.5% relative error — sufficient for argmax peak detection.
The 0.375 coefficient is implemented as `(min >> 2) + (min >> 3)` (two right-shifts, one
addition). No multiplier needed.

---

### 4.5 peak_detector.v

**Purpose.** Parameterized streaming argmax. Accepts a sequence of values and tracks the
largest value seen and its index. Supports both signed (timing metric) and unsigned
(Meyr magnitude) input via parameter.

```
Parameter           Default   Description
─────────────────── ───────── ──────────────────────────────────
DATA_WIDTH          32        Input value width (METRIC_WIDTH or MEYR_ACC_WIDTH)
INDEX_WIDTH         9         Output index width
ARRAY_LEN           256       Expected number of input values (for index counter)
SIGNED_INPUT        1         1 = treat input as signed (timing metric)
                              0 = treat input as unsigned (Meyr magnitude)
```

```
Signal              Dir  Width  Description
─────────────────── ───  ─────  ────────────────────────────────────────────────
aclk / aresetn      in   1

// Input stream (one value per clock while valid is high)
data_in             in   DATA_WIDTH   Value at current index
data_valid          in   1
data_last           in   1            High on final value

// Outputs
peak_index          out  INDEX_WIDTH  Index of maximum value seen
peak_value          out  DATA_WIDTH   Maximum value
done                out  1            High (1 clock) after data_last
```

**Reuse.** Instantiated twice in the design:
1. In `timing_metric_core.v` output path: ARRAY_LEN=256, SIGNED_INPUT=1, DATA_WIDTH=32.
2. In `meyr_corr_core.v`: ARRAY_LEN=511, SIGNED_INPUT=0, DATA_WIDTH=40.

---

### 4.6 frac_cfo_estimator.v

**Purpose.** Reads the complex autocorrelation value at `peak_lag` from `cp_autocorr_core`
and computes its phase angle via CORDIC atan2. Outputs the phase as a 16-bit signed word
in ±π scaling (Q1.15 × π radians).

```
Parameter           Default   Description
─────────────────── ───────── ──────────────────────────────────
PHASE_WIDTH         16
```

```
Signal              Dir  Width  Description
─────────────────── ───  ─────  ────────────────────────────────────────────────
aclk / aresetn      in   1

// Control
start               in   1      Pulse to begin
peak_lag            in   9      Which lag index to read (from peak_detector)

// Autocorrelation result read-back (drives cp_autocorr_core result_rd_addr)
result_rd_addr      out  9
autocorr_I          in   32     Signed
autocorr_Q          in   32     Signed

// Output
frac_phase          out  16     Signed PHASE_WIDTH: atan2(Q, I); 0x7FFF = +π
frac_phase_valid    out  1
done                out  1

// CORDIC submodule (cordic_atan2.v) is instantiated inside this module
```

---

### 4.7 cordic_atan2.v

**Purpose.** Thin wrapper around Xilinx CORDIC IP v6.0 configured in translate (atan2) mode
with AXI-Stream interface. Accepts 32-bit I and Q on separate AXI-Stream channels; outputs
16-bit phase.

```
Parameter           Default   Description
─────────────────── ───────── ──────────────────────────────────
INPUT_WIDTH         32        Cartesian input component width
PHASE_WIDTH         16        Phase output width
LATENCY             15        CORDIC pipeline latency (clock cycles)
```

```
Signal              Dir  Width  Description
─────────────────── ───  ─────  ────────────────────────────────────────────────
aclk / aresetn      in   1

// AXI-Stream Cartesian input  {Q[31:0], I[31:0]} packed as 64-bit TDATA
s_axis_cartesian_tdata     in   64
s_axis_cartesian_tvalid    in   1
s_axis_cartesian_tready    out  1

// AXI-Stream phase output
m_axis_dout_tdata          out  16     Signed phase, 0x7FFF = +π
m_axis_dout_tvalid         out  1
```

**Xilinx CORDIC IP configuration:**
```
Function:              Translate (atan2 = arctan(Y/X))
Architecture:          Parallel (fully pipelined)
Coarse Rotation:       Enabled (handles all quadrants)
Data Format:           Signed Fraction
Phase Format:          Radians  (output scaled to ±1.0 = ±π)
Input Width:           32
Output Width:          16 (phase only; magnitude output unused)
Round Mode:            Truncate
Iterations:            15
```

---

### 4.8 nco_phase_gen.v

**Purpose.** 32-bit phase accumulator. Each clock, increments by `step_word` (signed).
Outputs the 16 MSBs of the accumulator to an internal Xilinx CORDIC (sincos mode) to
produce sin θ and cos θ as Q1.15 16-bit values. Shared between fractional and integer CFO
correction passes.

```
Parameter           Default   Description
─────────────────── ───────── ──────────────────────────────────
NCO_PHASE_WIDTH     32
CORDIC_PHASE_WIDTH  16
ROTATOR_COEFF_WIDTH 16
LATENCY             15        CORDIC sincos pipeline latency
```

```
Signal              Dir  Width  Description
─────────────────── ───  ─────  ────────────────────────────────────────────────
aclk / aresetn      in   1

// Control
step_word           in   32     Signed NCO step (2's complement); loaded combinationally
load_step           in   1      When high, step_word is latched on next rising edge
phase_reset         in   1      Synchronously clears phase accumulator to 0
enable              in   1      When high, accumulator increments each clock

// Outputs
sin_out             out  16     Signed Q1.15; valid LATENCY clocks after first enable
cos_out             out  16     Signed Q1.15
sincos_valid        out  1      High when sin_out / cos_out are valid
phase_acc           out  32     Current accumulator value (for debug)
```

**Phase accumulator behavior.** Natural binary wrap (modulo 2³²) is intentional and is NOT
saturation. The FSM must assert `phase_reset` before each new correction pass so the NCO
starts at angle 0 for each batch of samples.

**sin/cos implementation.** Xilinx CORDIC IP v6.0, sin/cos (rotate) mode:
```
Function:       Sin and Cos
Architecture:   Parallel (pipelined)
Data Format:    Signed Fraction
Phase Format:   Radians (input 0x7FFF = +π)
Input Width:    16 (= CORDIC_PHASE_WIDTH, = NCO acc[31:16])
Output Width:   16 (= ROTATOR_COEFF_WIDTH)
Round Mode:     Truncate
```

---

### 4.9 complex_rotator.v

**Purpose.** Multiplies each IQ sample by the complex phasor `cos θ + j·sin θ` produced by
`nco_phase_gen.v`. Reads one sample per clock from `sample_buffer` starting at a given base
address; writes corrected samples back to Port A of `sample_buffer` (or directly to the
m_axis_iq output during INT_CFO_CORR, controlled by `output_mode`).

```
Parameter           Default   Description
─────────────────── ───────── ──────────────────────────────────
DATA_WIDTH          32
ROTATOR_COEFF_WIDTH 16
ADDR_WIDTH          12
```

```
Signal              Dir  Width  Description
─────────────────── ───  ─────  ────────────────────────────────────────────────
aclk / aresetn      in   1

// Control
start               in   1      Begin rotation pass
base_addr           in   12     Buffer address of first sample to rotate
num_samples         in   13     Number of samples to process
output_mode         in   1      0 = write-back to sample_buffer; 1 = stream to m_axis_iq

// NCO coefficients (from nco_phase_gen; new values each clock)
sin_in              in   16     Q1.15
cos_in              in   16     Q1.15
sincos_valid        in   1

// Buffer read (Port B)
buf_rd_addr         out  12
buf_rd_data         in   32     {Q[31:16], I[15:0]}

// Buffer write-back (Port A; used when output_mode=0)
buf_wr_en           out  1
buf_wr_addr         out  12
buf_wr_data         out  32     {Q_rot[31:16], I_rot[15:0]}

// AXI-Stream output (used when output_mode=1, INT_CFO_CORR pass)
m_axis_tdata        out  32
m_axis_tvalid       out  1
m_axis_tready       in   1
m_axis_tlast        out  1      High on last corrected sample
m_axis_tuser        out  1      High on first sample

// Status
done                out  1
busy                out  1
```

**Address pipelining.** The buffer read has 1-cycle registered latency. The rotator writes
back to `buf_wr_addr = buf_rd_addr − 1` (one address behind the read pointer) to absorb
the BRAM read latency. The CORDIC pipeline adds `LATENCY = 15` cycles of startup delay;
the first 15 valid sin/cos outputs arrive 15 clocks after `phase_reset` is deasserted.
The FSM must account for this: `num_samples` rotation outputs arrive cycles 16..16+num_samples.

---

### 4.10 complex_mult_iq.v

**Purpose.** Zero-LUT wrapper around `axis_complex_mult.v` that enforces the project I/Q
convention: TDATA[15:0] = I (in-phase), TDATA[31:16] = Q (quadrature). Internally swaps
the upper and lower 16 bits before presenting data to `axis_complex_mult.v` (which treats
upper = real, lower = imaginary). Swaps the output back.

This fixes the packing mismatch documented in Step 3 §2.1.

```
Parameter           Default   Description
─────────────────── ───────── ──────────────────────────────────
DATA_WIDTH          32        Full TDATA width (I+Q packed)
COMPONENT_WIDTH     16        = DATA_WIDTH / 2
SHIFT               15        Q1.15 output right-shift
CONJ_A              0         If 1, negate Q of input A (computes conj(A)×B)
CONJ_B              0         If 1, negate Q of input B (computes A×conj(B))
```

```
Signal              Dir  Width  Description
─────────────────── ───  ─────  ────────────────────────────────────────────────
aclk / aresetn      in   1

// Input A: {Q_a[31:16], I_a[15:0]}
s_axis_a_tdata      in   32     I-lower, Q-upper convention
s_axis_a_tvalid     in   1
s_axis_a_tready     out  1
s_axis_a_tlast      in   1

// Input B: {Q_b[31:16], I_b[15:0]}
s_axis_b_tdata      in   32
s_axis_b_tvalid     in   1
s_axis_b_tready     out  1
s_axis_b_tlast      in   1

// Output: {Q_out[31:16], I_out[15:0]}
// I_out = I_a×I_b − Q_a×Q_b   (standard complex product real part)
// Q_out = I_a×Q_b + Q_a×I_b   (standard complex product imag part)
// If CONJ_A=1: conj(A)×B → I_out = I_a×I_b + Q_a×Q_b, Q_out = I_b×Q_a − I_a×Q_b
m_axis_tdata        out  32
m_axis_tvalid       out  1
m_axis_tready       in   1
m_axis_tlast        out  1
```

**Internal swap logic (no LUTs, only wire assignments):**
```verilog
wire [31:0] a_reordered = {a_tdata[15:0], a_tdata[31:16]};  // swap: I→upper, Q→lower
wire [31:0] b_reordered = {b_tdata[15:0], b_tdata[31:16]};
// feed reordered to axis_complex_mult; receive output
wire [31:0] mult_out;
assign m_axis_tdata = {mult_out[15:0], mult_out[31:16]};    // swap back: Q→upper, I→lower
```

**CONJ parameter.** When `CONJ_A=1`, the Q component of A is negated before the swap:
`a_reordered = {~a_tdata[15:0] + 1, a_tdata[31:16]}` (negate the lower 16 bits = Q_a).
This allows the CP autocorrelation and Meyr cross-correlation to form conjugate products
without separate negation logic.

---

### 4.11 symbol_extractor.v

**Purpose.** Presents NSC consecutive IQ samples from `sample_buffer`, starting at a
computed CP-removal offset, as an AXI-Stream suitable for feeding `fft_wrapper.v`.

```
Parameter           Default   Description
─────────────────── ───────── ──────────────────────────────────
NSC                 256
CP_LEN              32
ADDR_WIDTH          12
```

```
Signal              Dir  Width  Description
─────────────────── ───  ─────  ────────────────────────────────────────────────
aclk / aresetn      in   1

// Control
start               in   1      Pulse to begin
slot_start_addr     in   12     Buffer address of slotStartIndex
symbol_sel          in   1      0 = PSS (offset = CP_LEN)
                                 1 = SSS (offset = 2×CP_LEN + NSC)

// Buffer read (Port B)
buf_rd_addr         out  12
buf_rd_data         in   32

// AXI-Stream output (NSC samples, one per clock)
m_axis_tdata        out  32
m_axis_tvalid       out  1
m_axis_tready       in   1
m_axis_tlast        out  1      High on sample NSC-1
m_axis_tuser        out  1      High on sample 0

// Status
done                out  1
busy                out  1
```

**Offset calculation.**
- PSS: `rd_addr = slot_start_addr + CP_LEN + sample_idx` (sample_idx = 0..NSC-1)
- SSS: `rd_addr = slot_start_addr + 2×CP_LEN + NSC + sample_idx`

The extractor is a simple address counter with two preset values. No BRAM required; the
buffer is the storage. Latency: 1 cycle (BRAM registered read) + AXI-Stream pipeline.

---

### 4.12 fft_wrapper.v

**Purpose.** Parameterized wrapper around the Xilinx FFT IP v9.1. Configures the IP for
a fixed point size (256 or 512) and direction (forward/inverse). Uses Block Floating Point
mode; carries the BFP scale exponent in TUSER.

```
Parameter           Default   Description
─────────────────── ───────── ──────────────────────────────────
FFT_SIZE            256       Transform length (256 or 512)
DATA_WIDTH          32        TDATA width (= FFT_DATA_WIDTH × 2)
TUSER_WIDTH         8         Scale exponent width
FORWARD_INV         1         1 = forward FFT; 0 = inverse FFT
                              (may be overridden by s_axis_config at runtime)
```

```
Signal              Dir  Width  Description
─────────────────── ───  ─────  ────────────────────────────────────────────────
aclk / aresetn      in   1

// Optional runtime direction config (for 512-pt reconfigurable instance)
s_axis_config_tdata in   8      [0] = FWD_INV (1=fwd, 0=inv)
s_axis_config_tvalid in  1
s_axis_config_tready out 1

// Input frame: FFT_SIZE complex samples
s_axis_data_tdata   in   32     {Q[31:16], I[15:0]}, Q1.15
s_axis_data_tvalid  in   1
s_axis_data_tready  out  1
s_axis_data_tlast   in   1      High on sample FFT_SIZE-1

// Output frame
m_axis_data_tdata   out  32     {Q[31:16], I[15:0]}, Q1.15 (post-BFP scaling)
m_axis_data_tvalid  out  1
m_axis_data_tready  in   1
m_axis_data_tlast   out  1
m_axis_data_tuser   out  8      BFP scale exponent (right-shifts applied by IP)

// Status
event_frame_started out  1      Debug: asserted on first output sample of each frame
event_blk_exp_valid out  1      Synonym for m_axis_data_tvalid on first output sample
```

**No fftshift.** Output is in natural order (DC = bin 0). This matches the C function
`fft_without_rearrange()`. No output reordering is applied inside the wrapper.

**BFP exponent tracking.** The 8-bit TUSER value on the output stream carries the scale
exponent for the entire output frame. Downstream blocks that compare magnitudes across
frames (e.g., Meyr cross-correlation) must record both exponents and add them to find the
effective exponent of the element-wise product.

---

### 4.13 pss_sss_rom.v

**Purpose.** Synchronous ROM holding the PSS and SSS reference sequences (`mU` and `goldU`
from the C code). Provides `mU[j]` and `goldU[j]` for j = 0..NSC+CP_LEN−1 = 0..287 (the
C code accesses at offset `j + CP_LEN`, so the ROM is indexed from 0 and the CP_LEN offset
is applied by the caller).

```
Parameter           Default   Description
─────────────────── ───────── ──────────────────────────────────
NSC                 256
CP_LEN              32
ROM_DEPTH           288       = NSC + CP_LEN
DATA_WIDTH          16        Per-component width (Q1.15)
```

```
Signal              Dir  Width  Description
─────────────────── ───  ─────  ────────────────────────────────────────────────
aclk                in   1

rd_addr             in   9      ROM read address (0..287)
mU_I                out  16     PSS I component, Q1.15
mU_Q                out  16     PSS Q component, Q1.15
goldU_I             out  16     SSS I component, Q1.15
goldU_Q             out  16     SSS Q component, Q1.15
```

**ROM initialization.** The ROM is initialized from a `$readmemh` file or via `localparam`
array in the RTL. The reference sequences are pre-computed for a fixed cell ID (PSS root
index u=25 and a corresponding SSS sequence). If multiple cell IDs are needed, this module
is expanded to hold all PSS roots (3 sequences) or parameterized; this is deferred to later
steps.

**Memory sizing.** 288 × (16+16+16+16) bits = 288 × 64 bits = 18,432 bits = 0.5 × BRAM36.
Fits in a single BRAM18. Can also use distributed ROM (288 × 64 = 2304 × 4-bit LUT6s).

---

### 4.14 meyr_corr_core.v

**Purpose.** Implements the `fft_correlation_Meyr()` function. Takes `term1[256]` and
`term2[256]` (frequency-domain products computed upstream), zero-pads each to 512 samples,
computes forward FFTs, multiplies `conj(term1_fft) × term2_fft` pointwise, computes the
IFFT, and finds the argmax of the magnitude-squared output.

```
Parameter           Default   Description
─────────────────── ───────── ──────────────────────────────────
NSC                 256
CORR_FFT_SIZE       512       = 2 × NSC
DATA_WIDTH          32
MEYR_ACC_WIDTH      40
INDEX_WIDTH         9
```

```
Signal              Dir  Width  Description
─────────────────── ───  ─────  ────────────────────────────────────────────────
aclk / aresetn      in   1

// Control
start               in   1

// Input: term1 and term2, NSC samples each, streamed in sequentially
// term1 first (NSC samples), then term2 (NSC samples)
s_axis_terms_tdata  in   32    {Q[31:16], I[15:0]}
s_axis_terms_tvalid in   1
s_axis_terms_tready out  1
s_axis_terms_tuser  in   1     0 = term1 sample, 1 = term2 sample
s_axis_terms_tlast  in   1     High on last term2 sample

// Outputs
peak_index          out  9     0..510; int_cfo = peak_index − 255
peak_valid          out  1
done                out  1
```

**Internal sequence:**

```
1. Buffer term1[0..255] and term2[0..255] into internal storage (2 × 256 × 32-bit dist-RAM)
2. Zero-pad both to 512 samples (append 256 zeros to each)
3. Forward FFT of zero-padded term1 → TERM1_FFT[512]  (using fft_512 instance)
4. Forward FFT of zero-padded term2 → TERM2_FFT[512]  (reuse fft_512 instance, 2nd pass)
5. Pointwise: CORR_FFT[j] = conj(TERM1_FFT[j]) × TERM2_FFT[j]  (via freq_mult complex_mult_iq)
6. IFFT of CORR_FFT → corr_out[512]  (reuse fft_512 instance, 3rd pass, inverse)
7. Magnitude squared: mag[j] = corr_out_I[j]² + corr_out_Q[j]²  for j = 0..510
8. argmax(mag[0..510]) → peak_index
```

**fft_512 reuse.** The single `fft_wrapper.v` instance (FFT_SIZE=512) is run three times
sequentially, with `s_axis_config` changed to inverse for the third pass. This saves ~50%
BRAM compared to three separate instances.

**Latency.** Each 512-point FFT pass takes 512 + pipeline_latency clocks. With three
passes and pointwise multiply: approximately 3 × 600 + 512 = 2300 clocks ≈ 23 µs at
100 MHz.

---

### 4.15 integer_cfo_estimator.v

**Purpose.** Top-level wrapper for the integer CFO estimation. Orchestrates symbol
extraction, dual PSS/SSS FFTs, reference ROM reads, term computation, and `meyr_corr_core`.
Outputs the integer CFO estimate in signed subcarrier units.

```
Signal              Dir  Width  Description
─────────────────── ───  ─────  ────────────────────────────────────────────────
aclk / aresetn      in   1

// Control
start               in   1
slot_start_addr     in   12     slotStartIndex in sample_buffer

// Buffer read (Port B; shared with symbol_extractor)
buf_rd_addr         out  12
buf_rd_data         in   32

// Outputs
int_cfo             out  9      Signed; range −255..+255 (9-bit signed 2's complement)
int_cfo_valid       out  1
done                out  1
busy                out  1
```

**Internal FSM states:**
```
IDLE
→ EXTRACT_PSS      symbol_extractor, symbol_sel=0 (PSS)
→ FFT_PSS          fft_256_pss, forward
→ EXTRACT_SSS      symbol_extractor, symbol_sel=1 (SSS)
→ FFT_SSS          fft_256_sss, forward
→ COMPUTE_TERMS    Read PSS_FFT, SSS_FFT, mU, goldU; compute term1, term2 via complex_mult_iq
→ MEYR_CORR        meyr_corr_core (3×512-pt FFT sequence)
→ DECODE_CFO       int_cfo = peak_index − (NSC−1) = peak_index − 255
→ DONE
```

**int_cfo encoding.** The IFFT output length is 512 samples; the valid cross-correlation
spans indices 0..510 (length 2×NSC−1 = 511). Integer CFO = peak_index − (NSC−1):
- peak_index = 255 → int_cfo = 0 (zero CFO)
- peak_index = 0   → int_cfo = −255 (maximum negative CFO)
- peak_index = 510 → int_cfo = +255 (maximum positive CFO)

---

### 4.16 integer_cfo_corrector.v

**Purpose.** Computes the NCO step word corresponding to `int_cfo`, programs `nco_phase_gen.v`,
and triggers `complex_rotator.v` for a second correction pass over the buffered samples.
During this pass, `complex_rotator.v` is set to `output_mode=1`, so corrected samples flow
directly to `m_axis_iq` rather than being written back to the buffer.

```
Parameter           Default   Description
─────────────────── ───────── ──────────────────────────────────
NSC                 256
NCO_PHASE_WIDTH     32
```

```
Signal              Dir  Width  Description
─────────────────── ───  ─────  ────────────────────────────────────────────────
aclk / aresetn      in   1

// Control (from sync_control_fsm)
start               in   1
int_cfo             in   9      Signed integer CFO in subcarrier units
slot_start_addr     in   12
num_samples         in   13     = symbols_per_slot register value

// Shared NCO control (drives nco_phase_gen)
nco_step_word       out  32     = round(−int_cfo × 2^NCO_PHASE_WIDTH / NSC)
nco_load_step       out  1
nco_phase_reset     out  1
nco_enable          out  1

// Shared rotator control (drives complex_rotator)
rot_start           out  1
rot_base_addr       out  12
rot_num_samples     out  13
rot_output_mode     out  1      Always 1 (stream to m_axis_iq)

// Status
done                out  1
```

**Step word computation.** Implemented as a signed multiply-shift:
`step = −int_cfo × (2^32 / NSC)` = `−int_cfo × 16,777,216` (for NSC=256).
This is a signed 9-bit × 25-bit multiply → 34-bit signed product, then truncated to 32
bits. Since `|int_cfo| ≤ 255`, the product fits in 33 bits. A single DSP48 handles this.

---

### 4.17 sync_control_fsm.v

**Purpose.** Master sequencer. Implements the top-level state machine. Holds the state
register, issues start pulses to submodules, waits for their `done` outputs, reads status
values, and writes results to `axi_lite_sync_regs.v`.

```
Signal              Dir  Width  Description
─────────────────── ───  ─────  ────────────────────────────────────────────────
aclk / aresetn      in   1

// AXI-Lite register interface (simplified)
ctrl_start          in   1      From CTRL register bit 0
ctrl_abort          in   1      From CTRL register bit 1
threshold_reg       in   32     From ENERGY_THRESH register
window_len_reg      in   7      From WINDOW_LEN register
hit_count_reg       in   4      From HIT_COUNT register
sample_count_reg    in   13     From SAMPLE_COUNT register
symbols_per_slot    in   13     From SYMBOLS_PER_SLOT register

// Status outputs (to AXI-Lite registers)
status_done         out  1
status_busy         out  1
status_error        out  1
status_frame_found  out  1
frame_index_out     out  12
timing_offset_out   out  9
frac_cfo_out        out  16
int_cfo_out         out  9
peak_metric_out     out  32
meyr_peak_idx_out   out  9

// Submodule enables and addresses (selected connections shown)
buf_wr_en_fill      out  1      Enable sample_buffer write during FILL_BUFFER
buf_wr_addr_fill    out  12
fd_start            out  1      → frame_detector
fd_threshold        out  32
fd_window_len       out  7
fd_hit_count        out  4
fd_search_base      out  12
fd_search_len       out  13
fd_frame_found      in   1
fd_frame_index      in   12
fd_done             in   1

ac_start            out  1      → cp_autocorr_core
ac_base_addr        out  12
ac_done             in   1

tm_start            out  1      → timing_metric_core
tm_done             in   1
tm_peak_lag         in   9      Peak lag from peak_detector

fc_start            out  1      → frac_cfo_estimator
fc_peak_lag         out  9
fc_frac_phase       in   16
fc_done             in   1

nco_step_word       out  32     → nco_phase_gen
nco_load_step       out  1
nco_phase_reset     out  1
nco_enable          out  1

rot_start           out  1      → complex_rotator
rot_base_addr       out  12
rot_num_samples     out  13
rot_output_mode     out  1
rot_done            in   1

ice_start           out  1      → integer_cfo_estimator
ice_slot_start      out  12
ice_int_cfo         in   9
ice_done            in   1

icc_start           out  1      → integer_cfo_corrector
icc_int_cfo         out  9
icc_slot_start      out  12
icc_num_samples     out  13
icc_done            in   1

irq_out             out  1
```

---

### 4.18 axi_lite_sync_regs.v

**Purpose.** AXI-Lite slave register file. Expanded from the existing 4-register
`axi_lite_regfile.v` to 15 registers, retaining the same 4-state write FSM and 2-state
read FSM structure. Register address map as defined in Step 3 §7.

```
Parameter           Default   Description
─────────────────── ───────── ──────────────────────────────────
AXIL_DATA_WIDTH     32
AXIL_ADDR_WIDTH     8
NUM_REGS            15
```

Ports match the AXI-Lite slave interface defined in §3 (top-level port list).

**Register access rules.** Config registers (0x0C..0x1C) are writable only when
STATUS.BUSY = 0. Writing to a config register while BUSY will be silently ignored (no
SLVERR). The STATUS register and all RO registers are written only by `sync_control_fsm.v`
via an internal sideband bus, not by the AXI-Lite master.

---

## 5. FSM State Machine

### 5.1 State Encoding

```verilog
localparam ST_IDLE           = 4'd0;
localparam ST_FILL_BUFFER    = 4'd1;
localparam ST_FRAME_DETECT   = 4'd2;
localparam ST_CP_AUTOCORR    = 4'd3;
localparam ST_FRAC_CFO_EST   = 4'd4;
localparam ST_FRAC_CFO_CORR  = 4'd5;
localparam ST_INT_CFO_EST    = 4'd6;
localparam ST_INT_CFO_CORR   = 4'd7;
localparam ST_DONE           = 4'd8;
localparam ST_ERROR          = 4'd9;
```

### 5.2 State Transition Table

| From state | Condition | Next state | Action on transition |
|---|---|---|---|
| IDLE | ctrl_start | FILL_BUFFER | Clear STATUS; reset all submodules |
| FILL_BUFFER | s_axis_tlast OR sample_count reached | FRAME_DETECT | Latch wr_ptr as actual_rxLen |
| FILL_BUFFER | ctrl_abort | ERROR | — |
| FRAME_DETECT | fd_done AND fd_frame_found | CP_AUTOCORR | Latch frame_index; set status_frame_found |
| FRAME_DETECT | fd_done AND NOT fd_frame_found | ERROR | Set status_error |
| CP_AUTOCORR | ac_done AND tm_done AND peak_done | FRAC_CFO_EST | Latch peak_lag; latch peak_metric |
| FRAC_CFO_EST | fc_done | FRAC_CFO_CORR | Latch frac_phase; compute NCO step; latch slotStartIndex |
| FRAC_CFO_CORR | rot_done | INT_CFO_EST | — |
| INT_CFO_EST | ice_done | INT_CFO_CORR | Latch int_cfo |
| INT_CFO_CORR | icc_done | DONE | Write all results to AXI-Lite status regs |
| DONE | ctrl_start (new run) | FILL_BUFFER | — |
| DONE | — | DONE | Hold |
| ERROR | ctrl_start | FILL_BUFFER | Clear error flag |
| Any | ctrl_abort (if busy) | ERROR | Abort active submodule |

**Note on CP_AUTOCORR state.** The timing_metric_core and peak_detector run pipelined
immediately after cp_autocorr_core completes. The FSM waits for all three done signals
before transitioning. In the implementation, `tm_start` is issued when `ac_done` is high;
peak_detector receives the streaming metric output from timing_metric_core and asserts its
own `done`. The FSM latches the three done signals OR'd (or sequenced) as appropriate.

### 5.3 Datapath Enable Summary per State

| State | Active submodules | Buffer port usage |
|---|---|---|
| FILL_BUFFER | AXI-Stream input → Port A (write) | Port A: write |
| FRAME_DETECT | frame_detector | Port B: sequential read |
| CP_AUTOCORR | cp_autocorr_core, timing_metric_core, peak_detector | Port B: random read (2 addresses per tap) |
| FRAC_CFO_EST | frac_cfo_estimator, cordic_atan2 | Port B: 1 read (autocorr peak value from submodule storage) |
| FRAC_CFO_CORR | nco_phase_gen, complex_rotator (output_mode=0) | Port A: write corrected; Port B: read original |
| INT_CFO_EST | integer_cfo_estimator (symbol_extractor, FFTs, meyr_corr_core) | Port B: sequential reads |
| INT_CFO_CORR | nco_phase_gen, complex_rotator (output_mode=1), integer_cfo_corrector | Port B: read corrected; output → m_axis_iq |
| DONE / ERROR | axi_lite_sync_regs (update status) | None |

---

## 6. Inter-Module Handshake Protocols

### 6.1 Start/Done Protocol

All non-AXI-Stream submodule control uses a simple start/done protocol:
- `start`: 1-clock pulse from the FSM. The submodule latches its configuration inputs on
  the rising edge of `start`.
- `done`: 1-clock pulse from the submodule when complete. The FSM transitions on `done`.
- `busy`: level signal, high while the submodule is running. The FSM does not issue a new
  `start` to a submodule while its `busy` is high.

This protocol avoids AXI-Stream overhead for non-streaming control paths and is trivial to
verify.

### 6.2 Sample Buffer Arbitration

The FSM owns all buffer addresses. No two submodules drive `buf_rd_addr` simultaneously;
the FSM enables exactly one submodule's read port at a time by multiplexing the address
bus. The Port A write side is likewise driven by exactly one source at a time: the AXI-
Stream fill logic (FILL_BUFFER state) or `complex_rotator.v` (FRAC_CFO_CORR state).

### 6.3 Shared NCO Arbitration

`nco_phase_gen.v` has one `step_word` input and one `load_step` input. During
FRAC_CFO_CORR, these are driven by `sync_control_fsm.v` directly. During INT_CFO_CORR,
they are driven by `integer_cfo_corrector.v`. The FSM ensures these states are mutually
exclusive. The `nco_step_word` and `nco_load_step` signals are multiplexed at the
`ofdm_synchronizer_top.v` level using the current state as the select.

### 6.4 AXI-Stream Flow Control

`symbol_extractor.v` drives the `fft_wrapper.v` input directly. The FFT wrapper asserts
`s_axis_data_tready` when its input FIFO has space. `symbol_extractor.v` stalls (holds
`tvalid` high without advancing) when `tready` is deasserted. The FSM's `done` from
symbol extraction is therefore gated on the FFT accepting all samples.

---

## 7. Memory Allocation

| Storage | Module | Width × Depth | Type | Size |
|---|---|---|---|---|
| Input IQ sample buffer | sample_buffer.v | 32 × 4096 | BRAM36 TDP | 128 Kbit = 2 × BRAM36 |
| Autocorrelation results | cp_autocorr_core.v | 96 × 256 | Dist-RAM or BRAM18 | 24 Kbit |
| Timing metric array | timing_metric_core.v | — | Streaming; not stored | 0 |
| PSS FFT output | integer_cfo_estimator.v | 32 × 256 | Dist-RAM | 8 Kbit |
| SSS FFT output | integer_cfo_estimator.v | 32 × 256 | Dist-RAM | 8 Kbit |
| term1 buffer | meyr_corr_core.v | 32 × 256 | Dist-RAM | 8 Kbit |
| term2 buffer | meyr_corr_core.v | 32 × 256 | Dist-RAM | 8 Kbit |
| 512-pt FFT intermediate | meyr_corr_core.v | 32 × 512 | BRAM18 | 16 Kbit |
| PSS/SSS reference ROM | pss_sss_rom.v | 64 × 288 | BRAM18 | 18 Kbit |
| AXI-Lite registers | axi_lite_sync_regs.v | 32 × 15 | FF | <1 Kbit |
| **Total** | | | | **~219 Kbit ≈ 7 × BRAM36** |

**Note.** The dist-RAM entries (autocorr results, PSS/SSS FFT outputs, Meyr term buffers)
are small enough to use distributed RAM (LUT-based) to avoid consuming BRAM18 primitives.
Total distributed RAM: 24+8+8+8+8 = 56 Kbit ≈ 896 LUT6s. Reasonable for any modern FPGA.

---

## 8. Latency Budget

Latencies below assume 100 MHz system clock and full-throughput operation (no stalls).
All values are approximate worst-case for NSC=256, CP_LEN=32, symbols_per_slot=2016.

| State | Dominant latency source | Estimated clocks | @ 100 MHz |
|---|---|---|---|
| FILL_BUFFER | rxLen = 4096 input samples | 4,096 | 41 µs |
| FRAME_DETECT | Search half buffer: 2048 windows | ~2,200 | 22 µs |
| CP_AUTOCORR | 256 lags × ~67 clocks/lag | ~17,200 | 172 µs |
| FRAC_CFO_EST | 1 CORDIC atan2 pass | 15 + overhead ≈ 50 | 0.5 µs |
| FRAC_CFO_CORR | 2016 samples + 15 CORDIC startup | ~2,031 | 20 µs |
| INT_CFO_EST | 2×256-pt FFT + 3×512-pt FFT + misc | ~6,500 | 65 µs |
| INT_CFO_CORR | 2016 samples + 15 CORDIC startup | ~2,031 | 20 µs |
| **Total** | | **~34,123** | **~341 µs** |

At 30.72 MHz input sample rate, one 7-symbol slot = 2016 samples ≈ 65.6 µs. The
synchronizer takes ~341 µs = ~5.2 slot periods. This is acceptable for a one-shot
synchronization that runs once at startup. Real-time tracking or continuous re-sync is out
of scope for the first implementation.

---

## 9. DSP and LUT Resource Estimates

Rough estimates for Xilinx 7-series / UltraScale. Final counts from Vivado synthesis
(Step 29).

| Module | DSP48 | BRAM36 | LUT (est) | FF (est) |
|---|---|---|---|---|
| sample_buffer.v | 0 | 2 | 50 | 30 |
| frame_detector.v | 2 (I²+Q²) | 0 | 150 | 80 |
| cp_autocorr_core.v | 4 (complex MAC) | 1 | 300 | 200 |
| timing_metric_core.v | 0 (α·max approx) | 0 | 80 | 40 |
| peak_detector.v (×2 inst) | 0 | 0 | 60 | 30 |
| frac_cfo_estimator + CORDIC | 4 (Xilinx CORDIC) | 0 | 200 | 150 |
| nco_phase_gen + CORDIC | 4 (Xilinx CORDIC) | 0 | 100 | 50 |
| complex_rotator + mult_iq | 4 (axis_complex_mult) | 0 | 80 | 60 |
| integer_cfo_estimator | 8 (4× mult_iq) | 2 | 400 | 300 |
| meyr_corr_core + 3× fft_wrapper | 12 (Xilinx FFT DSPs) | 2 | 500 | 400 |
| integer_cfo_corrector | 1 (step multiply) | 0 | 50 | 30 |
| sync_control_fsm | 0 | 0 | 200 | 100 |
| axi_lite_sync_regs | 0 | 0 | 100 | 60 |
| **Total (rough)** | **~39** | **~7** | **~2,270** | **~1,530** |

Xilinx Artix-7 XC7A100T has 240 DSP48, 135 BRAM36, 63,400 LUT6: this design comfortably
fits. An XC7A35T (90 DSP, 50 BRAM36) should also fit with some compression.

---

## 10. Build Order

The step-by-step implementation order (Steps 6–30) follows from the dependency graph.
Lower layers must be verified before the modules that depend on them.

```
Step 6   peak_detector.v               No dependencies; simplest DUT
Step 7   frame_detector.v              Needs sample_buffer read interface (use testbench model)
Step 8   sample_buffer.v               Foundation for all buffer-reading modules
Step 9   cp_autocorr_core.v            Needs sample_buffer
Step 10  timing_metric_core.v          Needs cp_autocorr_core output interface
Step 11  cordic_atan2.v                Xilinx IP wrapper; no datapath dependencies
Step 12  frac_cfo_estimator.v          Needs cordic_atan2 + cp_autocorr_core result bus
Step 13  nco_phase_gen.v               Xilinx CORDIC sincos wrapper
Step 14  complex_mult_iq.v             Wrapper around existing axis_complex_mult.v
Step 15  complex_rotator.v             Needs nco_phase_gen + complex_mult_iq + sample_buffer
Step 16  symbol_extractor.v            Needs sample_buffer
Step 17  fft_wrapper.v (256-pt)        Xilinx FFT IP wrapper, 256-point
Step 18  pss_sss_rom.v                 ROM init file required first
Step 19  fft_wrapper.v (512-pt)        Parameterized version of Step 17
Step 20  meyr_corr_core.v              Needs fft_wrapper(512) + complex_mult_iq
Step 21  integer_cfo_estimator.v       Needs symbol_extractor + fft_wrapper(256) + pss_sss_rom + meyr_corr_core
Step 22  integer_cfo_corrector.v       Needs nco_phase_gen + complex_rotator interfaces
Step 23  axi_lite_sync_regs.v          Expand existing axi_lite_regfile.v
Step 24  sync_control_fsm.v            Needs all submodule done/busy interfaces
Step 25  ofdm_synchronizer_top.v v1    Integrate FSM + buffer + frame detector + autocorr + frac CFO
Step 26  ofdm_synchronizer_top.v v2    Add integer CFO path
Step 27  ofdm_synchronizer_top.v v3    Add AXI-Lite + full top testbench
Step 28  Python golden model comparison Validate RTL vs C reference
Step 29  Synthesis review              Vivado OOC, check DSP/BRAM/LUT
Step 30  FPGA/ILA bring-up plan        Define probe list and UART status output
```

---

## 11. Files Changed

| File | Action |
|---|---|
| `md_files/04_full_rtl_architecture_prompt.md` | Created — full prompt text backup |
| `docs/step4_rtl_architecture_spec.md` | Created — this architecture specification |
| `ai_context/current_status.md` | Updated — Step 4 marked complete |
