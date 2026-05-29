# Claude Code Prompt — P3-14B Phase3 DMA Replay + Integer CFO Correction Integration

## Working Directory
`/home/zealatan/RTL_SYNC_PHASE3`

## Mandatory Archival Rule

Save this prompt to:

`md_files/p3_14b_dma_replay_int_cfo_prompt.md`

before any work.

---

# Context

P3-14A already completed:

```text
✔ phase3_axi_lite_regs.v
✔ phase3_sync_axis_dma_wrapper.v skeleton
✔ AXI-Lite register map
✔ smoke test
```

Current wrapper limitation:

```text
M_AXIS output path is still stubbed
core_m_valid = 0
```

Also:

```text
integer CFO estimate exists
but replay/integer correction path is not connected
```

This task integrates:

```text
replay buffer
second correction stage
DMA-visible corrected IQ output
```

without changing frame detector semantics.

---

# Objective

Connect:

```text
iq_replay_buffer_576
integer CFO correction
DMA-facing M_AXIS stream
```

so the Phase3 wrapper can output:

```text
fully corrected IQ stream
```

after:

```text
fractional CFO correction
+
integer CFO correction
```

---

# Allowed Modifications

You may modify/create:

```text
rtl/phase3_sync_axis_dma_wrapper.v
rtl/phase3_sync_top.v          minimal debug/output additions only
rtl/iq_replay_buffer_576.v

tb/p3_14b_dma_replay_tb.sv

scripts/run_p3_14b_dma_replay.sh

docs/p3_14b_dma_replay_integration.md

md_files/p3_14b_dma_replay_int_cfo_prompt.md
```

---

# Do NOT Modify

Do NOT modify:

```text
rtl/frame_detector.v
rtl/frame_detect_fsm.v
rtl/sliding_window_sum.v
rtl/fft256_dual_symbol_frontend.v
```

Do not redesign Meyr estimator algorithm.

---

# Required Architecture

Target pipeline:

```text
AXIS input IQ
    →
fractional CFO correction
    →
replay buffer
    →
Meyr integer CFO estimate
    →
second rotator/NCO correction
    →
DMA-visible corrected AXIS output
```

---

# Tasks

## 1. Replay buffer integration

Instantiate:

```text
iq_replay_buffer_576
```

inside wrapper/top path.

Verify:

```text
frame-aligned replay
tlast handling
replay_done timing
```

---

## 2. Integer CFO correction stage

Connect:

```text
integer_cfo_word
```

to a second rotator/NCO stage.

Expected:

```text
fractional correction first
integer correction second
```

Do not overwrite fractional path.

---

## 3. M_AXIS output activation

Replace stub:

```verilog
core_m_valid = 0;
```

with actual corrected stream.

Verify:

```text
m_axis_tvalid
m_axis_tready
m_axis_tlast
```

operate correctly.

---

## 4. Register integration

Wire the following registers fully:

```text
INT_CFO_INDEX
INT_CFO_APPLIED
OUTPUT_COUNT
TLAST_COUNT
```

Set:

```text
INT_CFO_APPLIED
```

only after replay correction becomes active.

---

## 5. Replay TB

Create:

```text
tb/p3_14b_dma_replay_tb.sv
```

Verify:

```text
fractional-only mode
fractional+integer correction mode
replay completion
AXIS continuity
TLAST correctness
no deadlock
```

---

## 6. Runner

Create:

```text
scripts/run_p3_14b_dma_replay.sh
```

Output:

```text
SANITY_GATE: PASS
or
OFFICIAL_GATE: PASS
```

Only use OFFICIAL if replay + correction + AXIS output are all verified under xsim.

---

## 7. Documentation

Create:

```text
docs/p3_14b_dma_replay_integration.md
```

Include:

```text
pipeline diagram
latency analysis
AXIS timing
replay timing
register updates
remaining limitations
```

---

# Pass Criteria

Complete only if:

```text
1. replay buffer is integrated
2. integer correction stage connected
3. M_AXIS outputs corrected stream
4. INT_CFO_APPLIED works
5. replay TB exists
6. no AXIS deadlock
7. docs exist
```

---

# Final Response Format

```text
P3-14B Final Status

1. Changed Files
2. Replay Integration Result
3. Integer CFO Correction Result
4. AXIS Output Result
5. Register Wiring Result
6. Test Results
7. Remaining Risks
8. Recommended Next Step
```
