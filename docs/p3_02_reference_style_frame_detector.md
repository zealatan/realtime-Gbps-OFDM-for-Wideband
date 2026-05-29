# P3-02 Reference-Style Frame Detector

## 1. Purpose

`rtl/reference_style_frame_detector.v` is a streaming RTL implementation of the C
`frame_detector()` function (receiver.c lines 327–382, Toan's version).  It detects
the start of an OFDM frame by finding `CONFIRM_LEN` consecutive sliding-window energy
measurements above a power threshold.

---

## 2. C Reference Algorithm

```c
// Sliding-window mean energy:
envelopeBlock[j] = mean(I[j..j+WND-1]^2 + Q[j..j+WND-1]^2)

// Case A (env[0] < threshold): scan for CONFIRM_LEN consecutive above-threshold windows
//   indexFrame = j + 1 - CONFIRM_LEN  (start of the winning run)

// Case B (env[0] >= threshold): find first j where env[j] < threshold (startIndex),
//   then apply Case A counting from startIndex.
```

`indexFrame` is the buffer sample address of the first window in the `CONFIRM_LEN`-run.

---

## 3. RTL Module

### File
`rtl/reference_style_frame_detector.v`

### Parameters

| Parameter    | Default | Description                                   |
|--------------|---------|-----------------------------------------------|
| `IQ_W`       | 16      | Per-I or per-Q sample width                   |
| `POWER_W`    | 33      | `sample_power_sq` output width (2·IQ_W+1)     |
| `SUM_W`      | 48      | Window sum accumulator width                  |
| `INDEX_W`    | 16      | `frame_index` output width                    |
| `WND_LEN`    | 25      | Sliding window length                         |
| `CONFIRM_LEN`| 10      | Consecutive hits required                     |

### Ports

| Port         | Dir   | Width        | Description                               |
|--------------|-------|--------------|-------------------------------------------|
| `aclk`       | in    | 1            | Clock                                     |
| `aresetn`    | in    | 1            | Active-low synchronous reset              |
| `s_tdata`    | in    | 2·IQ_W       | IQ sample `{Q[2*IQ_W-1:IQ_W], I[IQ_W-1:0]}`|
| `s_tvalid`   | in    | 1            | AXI-Stream handshake                      |
| `s_tready`   | out   | 1            | = `busy` (accepts when running)           |
| `s_tlast`    | in    | 1            | Last sample in buffer (triggers drain)    |
| `threshold`  | in    | SUM_W        | Window **sum** threshold (see §4)         |
| `start`      | in    | 1            | 1-cycle start pulse                       |
| `done`       | out   | 1            | 1-cycle done pulse                        |
| `busy`       | out   | 1            | High while running                        |
| `frame_found`| out   | 1            | 1 = frame found; 0 = not found            |
| `frame_index`| out   | INDEX_W      | Sample index of first window in winning run|

### FSM

```
S_IDLE
  → (start) → S_SEARCH_RISE

S_SEARCH_RISE
  [Fills window; when first window valid:]
    above threshold → S_SEARCH_FALL (Case B)
    below threshold → stay (Case A, counting begins next window)
  [When window valid, first_done=1:]
    above threshold, consec < CONFIRM_LAST → consec++
    above threshold, consec == CONFIRM_LAST → frame_found=1, → S_DONE
    below threshold → consec = 0
  [End-of-stream] → S_DONE (frame_found=0)

S_SEARCH_FALL
  [Each window (guaranteed full):]
    above threshold → stay
    below threshold → consec=0, → S_SEARCH_RISE
  [End-of-stream] → S_DONE

S_DONE  (1 cycle)
  done=1, busy=0 → S_IDLE
```

---

## 4. Threshold Scaling

The `threshold` port is the **window sum threshold** — the C per-sample threshold
scaled for the RTL IQ integer representation and multiplied by `WND_LEN`:

```
threshold = C_threshold × IQ_scale² × WND_LEN
```

For `IQ_W=16` signed Q1.15 samples (`IQ_scale = 2^15 = 32768`):
- C threshold = 40000 (default in receiver.c)
- RTL `threshold` = 40000 × (32768/32768)² × ... depends on actual IQ scaling

For testbench verification, `IQ_scale = 1` (raw integer, max I=100):
- `threshold = 5000 × WND_LEN = 125000` (10% full-scale trigger)

A window with all 25 samples at I=100, Q=0 gives sum = 250000 > 125000 (above).

---

## 5. Sub-module Dependencies

| Module                | Location              | Role                         |
|-----------------------|-----------------------|------------------------------|
| `sample_power_sq`     | `rtl/phase2_legacy/`  | Computes I²+Q² (2-cycle lat) |
| `ram_2port`           | `rtl/phase2_legacy/`  | Used inside `sample_power_sq`|

`moving_avg_optimized` is **not used**: its window size is 2^WINDOW_SHIFT (power-of-2
only), incompatible with `WND_LEN=25`.  The sliding window is implemented with a
25-stage shift register and a running sum.

---

## 6. Latency and Pipeline

- `sample_power_sq`: 2-clock pipeline delay from input to `power_out_stb`
- First valid window result: after `WND_LEN + 2` input samples
- Frame found: `WND_LEN + 2 + CONFIRM_LEN + WND_LEN - 1` samples minimum

End-of-stream handling: `s_tlast` sets `eos_armed`; a 2-entry `drain_cnt` (the
pipeline depth of `sample_power_sq`) ensures the last powers are processed before
`S_DONE` is entered.

---

## 7. Test Cases

File: `tb/p3_02_reference_style_frame_detector_tb.sv`

| Test | Description                                 | Expected          |
|------|---------------------------------------------|-------------------|
| T01  | Case A: 25 LO + 34 HI                       | found, index=25   |
| T02  | Case B: 25 HI + 25 LO + 34 HI              | found, index=50   |
| T03  | Too few: 25 LO + 33 HI (9 hits)             | not found         |
| T04  | Minimal prefix: 1 LO + 34 HI               | found, index=1    |
| T05  | Interrupted run: 9 hits, gap, 10 hits       | found, index=83   |
| T06  | Case B long: 40 HI + 25 LO + 34 HI         | found, index=65   |
| T07  | All-zero input                              | not found         |
| T08  | At-boundary (I=99, sum=245025 < 249000)     | not found         |

Threshold for all tests: `SUM_THRESH = 249000`.  `HI=100` (power=10000);
`LO=0` (power=0).  A window is above threshold only when all 25 samples are HI
(sum=250000 > 249000).

---

## 8. Running the Simulation

```bash
bash scripts/run_p3_02_reference_style_frame_detector_sim.sh            # iverilog (default)
bash scripts/run_p3_02_reference_style_frame_detector_sim.sh --vcs      # Synopsys VCS
bash scripts/run_p3_02_reference_style_frame_detector_sim.sh --xvlog    # Xilinx xsim
```

Pass criterion: `RESULT: PASS 8 FAIL 0` in `sim_out/p3_02/sim.log`.

---

## 9. Index Computation Derivation

The `frame_index` output equals the **sample address** at the start of the first
window in the `CONFIRM_LEN`-run.

Inside the RTL:
- `pwr_cnt` counts power samples received (incremented on each `pwr_stb`, 0-indexed)
- When `pwr_stb` fires with `pwr_cnt = k`, this power corresponds to input sample `k`
- The window ending at power `k` starts at sample `k - (WND_LEN-1)`
- `wstart = pwr_cnt - WND_M1_I` (using the OLD pre-increment value of `pwr_cnt`)
- When `consec` transitions 0→1, `hit_start ← wstart`
- When `consec == CONFIRM_LAST`, `frame_index ← hit_start`

This matches the C: `indexFrame = j_first_hit` where `j` is the window start index.
