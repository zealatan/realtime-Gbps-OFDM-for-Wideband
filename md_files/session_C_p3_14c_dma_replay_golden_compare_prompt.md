# Claude Code Prompt — Session C / P3-14C Full DMA Replay Golden Compare

## Working Directory
`/home/zealatan/RTL_SYNC_PHASE3`

## Mandatory Archival Rule
Before making any code change, save this prompt verbatim to:

`md_files/session_C_p3_14c_dma_replay_golden_compare_prompt.md`

Create `md_files/` if it does not exist.

---

# Session Naming

This is **Claude Session C**.

Session C owns:

```text
AXI-Lite / AXI-Stream DMA wrapper
replay buffer
integer CFO correction path
M_AXIS corrected stream
Python golden compare
```

---

# Current Known Status

P3-14B completed:

```text
rtl/phase3_sync_axis_dma_wrapper.v
  replay buffer + integer NCO + rotator wired
  M_AXIS stub replaced

rtl/phase3_sync_top.v
  debug frac-tap ports + dbg_meyr_peak_index wired

rtl/phase3_axi_lite_regs.v
  INT_CFO_INDEX / INT_CFO_APPLIED registers fully wired

tb/p3_14b_dma_replay_tb.sv
  14-check interface TB

scripts/run_p3_14b_dma_replay.sh
  compile + simulate runner
  anchored OFFICIAL_GATE grep fixed

docs/p3_14b_dma_replay_integration.md
  pipeline diagram, latency, AXIS timing, re-arm protocol
```

Result:

```text
SANITY_GATE: PASS
14/14 checks PASS
```

Important limitation:

```text
P3-14B verified interface/no-deadlock/register behavior.
It did NOT yet prove sample-by-sample IQ correctness.
```

---

# Objective

Create a Python golden-compare validation for the full DMA replay + integer CFO correction path.

Required flow:

```text
RTL simulation produces M_AXIS corrected IQ capture
Python reference computes expected corrected IQ
compare sample-by-sample
```

This task should prove whether the replay + integer CFO correction path is numerically correct.

---

# Allowed Modifications

You may create/modify:

```text
tb/session_C_p3_14c_dma_replay_golden_tb.sv
scripts/run_session_C_p3_14c_dma_replay_golden_compare.sh
scripts/compare_session_C_p3_14c_dma_replay_golden.py
docs/session_C_p3_14c_dma_replay_golden_compare.md
md_files/session_C_p3_14c_dma_replay_golden_compare_prompt.md
```

You may minimally modify:

```text
rtl/phase3_sync_axis_dma_wrapper.v
tb/p3_14b_dma_replay_tb.sv
```

only to expose/capture necessary debug/output signals.

---

# Do NOT Modify

Do not modify algorithm RTL unless a clear bug is found and documented first:

```text
rtl/frame_detector.v
rtl/frame_detect_fsm.v
rtl/sliding_window_sum.v
rtl/fft256_dual_symbol_frontend.v
rtl/meyr_*.v
rtl/frac_cfo_frame_corrector_top.v
```

Do not change Session A frame detector behavior.

Do not change Session B FFT/Meyr estimator behavior.

---

# Required Validation Scope

Compare at least:

```text
frame_index
slot_start_index
int_cfo_est
int_cfo_index
int_cfo_applied
M_AXIS tdata sequence
M_AXIS tlast position
output_count
tlast_count
```

For IQ sample comparison:

```text
RTL M_AXIS output
vs
Python corrected IQ reference
```

Tolerance may be used for fixed-point rounding:

```text
I/Q absolute error <= small integer tolerance
```

Document the tolerance.

---

# Tasks

## 1. Create full replay golden TB

Create:

```text
tb/session_C_p3_14c_dma_replay_golden_tb.sv
```

It should:

```text
drive AXI-Lite control
feed AXI-Stream IQ stimulus
wait for replay/integer correction
capture M_AXIS output to file
capture debug/status to file
```

Suggested output files:

```text
sim_out/session_C_p3_14c/rtl_m_axis_iq.txt
sim_out/session_C_p3_14c/rtl_status.txt
```

Use key=value text if JSON is inconvenient in SV.

## 2. Create Python golden compare

Create:

```text
scripts/compare_session_C_p3_14c_dma_replay_golden.py
```

It should:

```text
load input stimulus
load RTL M_AXIS capture
load RTL status
compute expected correction
compare sample-by-sample
print PASS/FAIL summary
```

If exact full reference is not available yet, implement a staged compare:

```text
Stage 1: structural/status compare
Stage 2: tlast/output length compare
Stage 3: IQ compare using known int_cfo_word and NCO convention
```

## 3. Verify correction sign convention

Explicitly test and document:

```text
integer_cfo_word sign
NCO phase accumulation direction
rotator sign convention
```

This is high-risk. Do not assume.

## 4. Create runner

Create:

```text
scripts/run_session_C_p3_14c_dma_replay_golden_compare.sh
```

Behavior:

```text
compile/simulate TB
run Python compare
print gate result
```

Gate rules:

```text
SANITY_GATE: PASS  only for structural/no-deadlock checks
OFFICIAL_GATE: PASS only if sample-by-sample golden IQ compare passes
```

Anchor grep patterns to avoid false positives.

## 5. Documentation

Create:

```text
docs/session_C_p3_14c_dma_replay_golden_compare.md
```

Include:

```text
pipeline under test
files generated
reference model assumptions
fixed-point tolerance
sign convention
sample compare result
remaining risks
```

---

# Pass Criteria

Complete if:

```text
1. full replay TB exists
2. RTL M_AXIS capture file generated
3. Python compare script exists
4. status/debug compare implemented
5. M_AXIS length/tlast compare implemented
6. IQ compare implemented or blocker explicitly documented
7. runner exists
8. docs exist
```

Official closure only if:

```text
OFFICIAL_GATE: PASS
```

from sample-by-sample golden IQ comparison.

---

# Final Response Format

Return:

```text
Session C / P3-14C Final Status

1. Changed Files
2. Golden TB Result
3. Python Compare Result
4. Status/Debug Compare
5. M_AXIS IQ Compare
6. Gate Result
7. Remaining Risks
8. Recommended Next Step
```
