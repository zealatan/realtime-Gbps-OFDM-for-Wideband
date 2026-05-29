# Claude Code Prompt — Session D / P3-15A Full C Golden Equivalence Infrastructure

## Working Directory
`/home/zealatan/RTL_SYNC_PHASE3`

## Mandatory Archival Rule
Before making any code change, save this prompt verbatim to:

`md_files/session_D_p3_15a_full_c_golden_equivalence_prompt.md`

Create `md_files/` if it does not exist.

---

# Session Naming

This is **Claude Session D**.

Session D owns:

```text
Full C reference equivalence infrastructure
golden C output normalization
RTL output/status normalization
Python compare framework
regression summary/dashboard
```

Session D must NOT take ownership of:

```text
Session A: frame detector implementation/regression
Session B: real FFT/Meyr estimator implementation
Session C: DMA replay/integer CFO correction implementation
```

Session D is an integration/verification framework task.

---

# Current Project Status

Session A status:

```text
P3-12C PASS under iverilog
frame_found = 1
frame_index = 41
peak_lag = 23
slot_start = 64
integer_cfo_valid asserted
10/10 PASS
CI_GATE blocked only by xsim availability
```

Session B status:

```text
P3-13B behavioral DFT validation PASS
k_int = 0, ±1, ±2, ±4, ±8 all pass
peak_index = 255 + k_int
int_cfo = k_int
real Xilinx FFT official xsim still pending
```

Session C status:

```text
P3-14B replay buffer + integer NCO/rotator + M_AXIS path connected
14/14 sanity checks PASS
sample-by-sample IQ golden compare still pending
```

---

# Objective

Create the infrastructure for full C reference vs RTL equivalence.

This task should prepare a unified framework that compares:

```text
C golden receiver/reference outputs
vs
RTL simulation outputs
```

for key Phase3 synchronization and correction observables.

This task should not require B/C to be fully completed, but it must be able to absorb their outputs when ready.

---

# Required Equivalence Targets

The framework should compare at least:

```text
frame_found
frame_index
peak_lag
slot_start_index
frac_cfo_valid
frac_cfo_phase / frac_cfo_word
int_cfo_valid
int_cfo_index / peak_index
int_cfo_est / integer_cfo_word
int_cfo_applied
PSS/SSS extraction status
M_AXIS output length
M_AXIS tlast position
M_AXIS IQ sequence if available
```

Comparison should be staged:

```text
Stage 0: file/schema availability
Stage 1: scalar status comparison
Stage 2: timing/index comparison
Stage 3: CFO word/sign convention comparison
Stage 4: M_AXIS length/tlast comparison
Stage 5: sample-by-sample IQ comparison
```

If Stage 5 data is not available yet, report:

```text
STAGE5_BLOCKED_M_AXIS_GOLDEN_UNAVAILABLE
```

not FAIL.

---

# Allowed Modifications

You may create/modify:

```text
scripts/export_c_reference_phase3_golden.py
scripts/normalize_rtl_phase3_outputs.py
scripts/compare_full_phase3_against_c_reference.py
scripts/run_session_D_p3_15a_full_c_golden_equivalence.sh

tb/session_D_p3_15a_phase3_observable_dump_tb.sv

docs/session_D_p3_15a_full_c_golden_equivalence_plan.md
docs/session_D_p3_15a_equivalence_result.md

md_files/session_D_p3_15a_full_c_golden_equivalence_prompt.md
```

You may read:

```text
golden/*
ref/*
rtl/*
tb/*
scripts/*
docs/*
```

You may create output directories:

```text
sim_out/session_D_p3_15a/
golden/session_D_p3_15a/
reports/session_D_p3_15a/
```

---

# Do NOT Modify

Do not modify algorithm RTL:

```text
rtl/phase3_sync_top.v
rtl/frac_cfo_frame_corrector_top.v
rtl/frame_detector.v
rtl/frame_detect_fsm.v
rtl/sliding_window_sum.v
rtl/sample_power_sq.v
rtl/meyr_*.v
rtl/fft256_dual_symbol_frontend.v
rtl/phase3_sync_axis_dma_wrapper.v
rtl/phase3_axi_lite_regs.v
```

Do not patch Session A/B/C implementation logic.

If a required signal is missing, document it as a required producer-side output for A/B/C.

---

# Tasks

## 1. Discover existing C reference and golden assets

Search for:

```text
receiver.c
golden vectors
p3_05c
p3_09
p3_13
p3_14
compare scripts
```

Document:

```text
which C/reference file is authoritative
which existing vectors are usable
which outputs already exist
which outputs must still be generated
```

Create:

```text
docs/session_D_p3_15a_full_c_golden_equivalence_plan.md
```

---

## 2. Define a normalized golden schema

Create a normalized JSON or key=value schema.

Recommended file:

```text
golden/session_D_p3_15a/c_reference_observables.json
```

Schema should include:

```json
{
  "frame_found": true,
  "frame_index": 41,
  "peak_lag": 23,
  "slot_start_index": 64,
  "frac_cfo_valid": true,
  "frac_cfo_word": null,
  "int_cfo_valid": true,
  "int_cfo_index": null,
  "int_cfo_est": null,
  "int_cfo_applied": null,
  "m_axis": {
    "available": false,
    "length": null,
    "tlast_index": null,
    "iq_file": null
  }
}
```

If exact values are not available, use:

```text
null + "status": "unknown"
```

Do not invent values.

---

## 3. Create C reference export script

Create:

```text
scripts/export_c_reference_phase3_golden.py
```

This script should:

```text
locate existing C golden/reference outputs
extract known scalar values
write normalized JSON
```

If C reference cannot be compiled/run automatically, the script should still create a partial JSON from existing known data and mark missing fields as unavailable.

Do not fail the whole flow just because M_AXIS golden IQ is not available.

---

## 4. Create RTL observable dump TB

Create:

```text
tb/session_D_p3_15a_phase3_observable_dump_tb.sv
```

This TB should reuse or wrap existing Phase3 regression stimulus.

It must dump observable RTL status to:

```text
sim_out/session_D_p3_15a/rtl_observables.txt
```

At minimum dump:

```text
frame_found
frame_index
peak_lag
slot_start_index
done_cycle
error_code
frac_cfo_valid if accessible
frac_cfo_phase if accessible
integer_cfo_valid
integer_cfo_word
meyr_peak_index if accessible
```

If M_AXIS output is available, dump:

```text
sim_out/session_D_p3_15a/rtl_m_axis_iq.txt
sim_out/session_D_p3_15a/rtl_m_axis_meta.txt
```

---

## 5. Normalize RTL output

Create:

```text
scripts/normalize_rtl_phase3_outputs.py
```

This script should convert:

```text
rtl_observables.txt
rtl_m_axis_meta.txt
rtl_m_axis_iq.txt
```

into:

```text
sim_out/session_D_p3_15a/rtl_observables.json
```

Use the same schema as the C reference JSON.

---

## 6. Create comparison script

Create:

```text
scripts/compare_full_phase3_against_c_reference.py
```

It should compare:

```text
golden/session_D_p3_15a/c_reference_observables.json
sim_out/session_D_p3_15a/rtl_observables.json
```

Required behavior:

```text
PASS for matching available fields
BLOCKED for unavailable-but-required future fields
FAIL for mismatched available fields
```

Suggested output:

```text
STAGE0_SCHEMA: PASS
STAGE1_SCALARS: PASS
STAGE2_TIMING: PASS
STAGE3_CFO: PASS/BLOCKED/FAIL
STAGE4_AXIS_META: PASS/BLOCKED/FAIL
STAGE5_AXIS_IQ: PASS/BLOCKED/FAIL
```

The final gate should be:

```text
EQUIV_GATE: PASS
EQUIV_GATE: PARTIAL_PASS_BLOCKED
EQUIV_GATE: FAIL
```

Rules:

```text
Do not call unavailable M_AXIS IQ a FAIL.
Do not call partial compare a full PASS.
```

---

## 7. Create integrated runner

Create:

```text
scripts/run_session_D_p3_15a_full_c_golden_equivalence.sh
```

Runner should:

```text
1. export C reference JSON
2. compile/run RTL observable dump TB
3. normalize RTL outputs
4. run comparison script
5. write final report
```

Gate rules:

```text
EQUIV_GATE: PASS                 only if all required stages pass
EQUIV_GATE: PARTIAL_PASS_BLOCKED if available fields pass but future fields unavailable
EQUIV_GATE: FAIL                 if any available required field mismatches
```

If xsim unavailable and iverilog is used, print:

```text
SANITY_EQUIV_GATE: PARTIAL_PASS_BLOCKED
```

not official full PASS.

---

## 8. Documentation

Create:

```text
docs/session_D_p3_15a_equivalence_result.md
```

Include:

```text
available C golden fields
available RTL fields
matched fields
blocked fields
mismatch fields
scripts used
commands
next producer-side requirements for Sessions B/C
```

---

# Pass Criteria

Complete if:

```text
1. C reference export script exists
2. RTL observable dump TB exists
3. RTL normalization script exists
4. comparison script exists
5. integrated runner exists
6. equivalence plan doc exists
7. equivalence result doc exists
8. framework can report PASS/PARTIAL_PASS_BLOCKED/FAIL correctly
9. no algorithm RTL was modified
```

---

# Final Response Format

Return:

```text
Session D / P3-15A Final Status

1. Changed Files
2. C Reference Asset Discovery
3. Normalized Schema
4. RTL Observable Dump Result
5. Comparison Result
6. Gate Result
7. Blocked Fields
8. Required Producer-Side Outputs from B/C
9. Recommended Next Step
```
