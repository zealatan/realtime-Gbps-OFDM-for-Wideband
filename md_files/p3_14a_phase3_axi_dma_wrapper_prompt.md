# Claude Code Prompt — P3-14A AXI-Lite / AXI-Stream DMA Wrapper Planning and Skeleton

## Working Directory
`/home/zealatan/RTL_SYNC_PHASE3`

## Mandatory Archival Rule
Before making any code change, save this prompt verbatim to:

`md_files/p3_14a_phase3_axi_dma_wrapper_prompt.md`

Create `md_files/` if it does not exist.

## Context
Phase2 previously had board-facing AXI-Lite/AXI-Stream/DMA integration logic, including:

```text
phase2_axi_lite_regs.v
phase2_sync_axis_dma_wrapper.v or equivalent wrapper files
```

Phase3 currently focuses on the algorithm DUT:

```text
phase3_sync_top
```

but lacks the board/Vitis-facing control/status shell:

```text
PS/Vitis software
   -> AXI-Lite control/status registers
   -> AXI-Stream DMA input/output
   -> phase3_sync_top
```

This task should not disturb the frame detector or Meyr tasks. It is a parallel system-integration preparation task.

## Objective
Analyze `phase2_axi_lite_regs.v`, identify reusable control/status fields, and create a Phase3 wrapper skeleton that connects AXI-Lite control/status and AXI-Stream DMA-facing ports around `phase3_sync_top`.

## Allowed Modifications
You may create/modify:

```text
docs/p3_14a_phase2_axi_lite_regs_analysis.md
docs/p3_14a_phase3_axi_dma_wrapper_plan.md
rtl/phase3_axi_lite_regs.v              new or generated from phase2, if safe
rtl/phase3_sync_axis_dma_wrapper.v      new skeleton
tb/phase3_axi_dma_wrapper_smoke_tb.sv   new optional smoke TB
scripts/run_p3_14a_axi_dma_wrapper_smoke.sh
md_files/p3_14a_phase3_axi_dma_wrapper_prompt.md
```

You may read:

```text
rtl/phase2_axi_lite_regs.v
rtl/phase2*_wrapper*.v
rtl/phase3_sync_top.v
docs/*
scripts/*
```

## Do NOT Modify
Do not modify:

```text
rtl/phase3_sync_top.v
rtl/frac_cfo_frame_corrector_top.v
rtl/frame_detector.v
rtl/meyr_*.v
rtl/fft256_dual_symbol_frontend.v
```

Do not attempt bitstream generation in this task.

## Tasks

### 1. Analyze Phase2 register file
Inspect:

```text
rtl/phase2_axi_lite_regs.v
```

Extract and document:

```text
- address map
- control bits
- status bits
- counters
- debug/status snapshots
- reset behavior
- write-one-to-clear behavior, if any
- software-visible fields
```

Write:

```text
docs/p3_14a_phase2_axi_lite_regs_analysis.md
```

### 2. Define Phase3 register map
Create a proposed Phase3 map that includes Phase2 reusable fields plus Phase3-specific fields:

Required Phase3 debug/status fields:

```text
VERSION
CONTROL
STATUS
FRAME_LEN_SAMPLES
INPUT_COUNT
OUTPUT_COUNT
FRAME_START_VALID
FRAME_START_INDEX
PEAK_INDEX
SLOT_START_INDEX
FRAC_CFO_VALID
FRAC_CFO_PHASE
PSS_DONE
SSS_DONE
INT_CFO_VALID
INT_CFO_EST
INT_CFO_INDEX
INT_CFO_APPLIED
ERROR_FLAGS
TLAST_COUNT
```

Write:

```text
docs/p3_14a_phase3_axi_dma_wrapper_plan.md
```

### 3. Create Phase3 AXI-Lite regs skeleton
If safe, create:

```text
rtl/phase3_axi_lite_regs.v
```

It may be derived from `phase2_axi_lite_regs.v`, but must have a Phase3 version constant and Phase3 field names.

Keep it synthesizable.

### 4. Create Phase3 AXI/DMA wrapper skeleton
Create:

```text
rtl/phase3_sync_axis_dma_wrapper.v
```

It should conceptually connect:

```text
AXI-Lite slave
AXI-Stream S_AXIS from DMA
AXI-Stream M_AXIS to DMA
phase3_sync_top
```

Minimum behavior:

```text
- soft reset support
- enable gating
- input/output counters
- status/debug wiring from phase3_sync_top
- no algorithm changes
```

If some `phase3_sync_top` debug ports are not present, leave TODO comments and expose placeholder wires, but do not modify `phase3_sync_top`.

### 5. Optional smoke TB
Create a lightweight compile/smoke TB:

```text
tb/phase3_axi_dma_wrapper_smoke_tb.sv
```

Check:

```text
- reset exits
- AXI-Lite VERSION read path if implemented
- control write toggles enable/soft reset
- AXI-Stream handshakes do not X-propagate
```

### 6. Runner
Create:

```text
scripts/run_p3_14a_axi_dma_wrapper_smoke.sh
```

This can be compile-oriented. If dependencies are missing, report clearly.

Use:

```text
SANITY_GATE: PASS
```

for smoke-level success only.

Do not claim official system PASS.

## Pass Criteria
Complete only if:

```text
1. Phase2 AXI-Lite register analysis doc exists
2. Phase3 wrapper plan doc exists
3. Phase3 AXI-Lite skeleton exists or a clear reason is documented
4. Phase3 AXI/DMA wrapper skeleton exists
5. No algorithm RTL is modified
6. Smoke runner exists or clear blockers are documented
```

## Final Response Format
Return:

```text
P3-14A Final Status

1. Changed Files
2. Phase2 Register Analysis
3. Phase3 Register Map Proposal
4. Wrapper Skeleton Result
5. Smoke Test Result
6. Open Integration Points
7. Recommended Next Step
```
