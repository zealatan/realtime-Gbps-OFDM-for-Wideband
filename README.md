# AI-assisted RTL/FPGA Verification Workflow Experiment

## 1. Overview

This project is a small experiment using **Claude Code Pro** as an AI-assisted RTL/FPGA verification agent in a minimal Vivado project.

The goal was to test whether an AI coding agent can participate in a realistic verification loop:

```text
Spec → Code Generation → Simulation → Failure Detection → Debugging → Patch → Re-run → Pass Summary
```

Project path:

```text
/home/zealatan/AI_ORC/messi/VIVADO_MIN_EXAMPLE
```

Initial project:

```text
rtl/and2.v
tb/and2_tb.sv
scripts/run_vivado_sim.sh
CLAUDE.md
ai_context/current_status.md
```

The project was extended from a simple AND-gate example into an AXI-lite register-file verification experiment.

---

## 2. Workflow Concept

The current structure is:

```text
Human prompt / policy
  ↓
Claude Code agent
  ↓
Read / Write / Bash / MCP tools
  ↓
Vivado xsim / logs / patches
```

Interpretation:

```text
Prompt / policy       = control plane
Claude Code           = execution agent
Read/Write/Bash/MCP   = execution plane
Vivado xsim/logs      = verification feedback
```

This is currently a **single-agent + human-in-the-loop verification workflow**.

---

## 3. What Was Tried

Claude Code was asked to:

```text
1. Read CLAUDE.md and ai_context/current_status.md first.
2. Inspect only selected folders.
3. Generate a verification plan.
4. Create an AXI-lite register-file RTL.
5. Create a self-checking SystemVerilog testbench.
6. Create a Vivado xsim run script.
7. Run simulation.
8. Detect failures.
9. Patch the testbench or RTL when allowed.
10. Re-run simulation and summarize the result.
```

---

## 4. AXI-lite Register File Experiment

Generated/updated files:

```text
rtl/axi_lite_regfile.v
tb/axi_lite_regfile_tb.sv
scripts/run_axi_regfile_sim.sh
ai_context/current_status.md
```

The DUT implements:

```text
4 × 32-bit AXI-lite registers
Valid addresses: 0x00, 0x04, 0x08, 0x0C
Invalid address detection using addr[31:4] != 0
SLVERR response for invalid read/write
No register modification on invalid write
```

---

## 5. First Failure

The first generated testbench caused xsim to hang during the first read test.

Observed behavior:

```text
xvlog passed
xelab passed
xsim started
Test 1 hung during axi_read()
No timeout guard existed
```

Root cause:

```text
The testbench drove and deasserted AXI signals on the same posedge where the DUT sampled them.
```

This created a SystemVerilog TB/DUT race condition.

---

## 6. Fix

The testbench was patched with a safer timing rule:

```text
Drive AXI master signals on negedge.
Sample DUT ready/valid on posedge.
Add timeout guards to every wait loop.
Use $fatal on timeout.
Print [DONE] only after all checks pass.
```

Initial fixed result:

```text
16/16 checks passed
Simulation completed successfully
```

---

## 7. Extended Verification Result

The AXI-lite testbench was extended with:

```text
Reset checks
Register write/read checks
Partial WSTRB byte-lane writes
AW-before-W ordering
W-before-AW ordering
Simultaneous AW+W
B-channel backpressure
R-channel backpressure
Invalid address tests
No-alias checks
```

Final result:

```text
133/133 checks passed
0 failures
0 $fatal
CI grep gate passed
Simulation end time: 3720 ns
```

---

## 8. Key Lesson

The important result was not just code generation.

The important result was that Claude Code participated in a real verification feedback loop:

```text
Generate RTL/TB/script
→ Run simulation
→ Encounter failure
→ Diagnose testbench race
→ Patch testbench
→ Re-run
→ Extend tests
→ Find RTL limitation
→ Patch invalid-address handling
→ Re-run
→ Reach 133/133 pass
```

---

## 9. Human vs AI Role

Current role split:

```text
Human:
- Defines goal
- Sets file scope
- Controls RTL modification approval
- Reviews failure classification
- Decides next verification layer

Claude Code:
- Reads project context
- Generates RTL/TB/scripts
- Runs xsim
- Reads logs
- Patches code
- Updates status files
- Summarizes results
```

---

## 10. Automation Insight

Right now, the human gives detailed prompts manually.

This is useful because repeated prompt patterns reveal what should later become an automation policy.

Repeated rules include:

```text
Read CLAUDE.md and current_status.md first.
Do not scan the whole repository.
Modify only approved files.
Do not modify RTL unless explicitly authorized.
Use timeout guards in all wait loops.
Use negedge-drive / posedge-sample for bus master tasks.
Run the relevant simulation script after changes.
Classify failures as TB bug or RTL bug.
Report changed files, pass/fail count, CI status, and remaining failures.
```

These rules should later be moved into:

```text
ai_context/autonomous_policy.md
```

The workflow can then move from:

```text
Human-in-the-loop
```

toward:

```text
Human-on-the-loop with approval gates
```

---

## 11. Current Maturity

| Level | Description |
|---|---|
| Level 0 | Ask ChatGPT for code snippets |
| Level 1 | Claude edits files |
| Level 2 | Claude runs simulations and reads logs |
| Level 3 | Claude detects failures and patches TB/scripts |
| Level 4 | Policy-based autonomous verification with approval gates |
| Level 5 | FPGA board, UART, ILA, DMA, and hardware feedback loop |

Current experiment:

```text
Level 2.5 to Level 3
```

---

## 12. Next Steps

Recommended next steps:

```text
1. Continue manual prompting for a few more verification layers.
2. Build tb/axi_mem_model.sv.
3. Build tb/mem_rw_tb.sv.
4. Add scripts/run_mem_rw_sim.sh.
5. Verify AXI memory read/write behavior.
6. Then move toward DMA verification.
7. Convert repeated prompt patterns into ai_context/autonomous_policy.md.
```

Do not automate everything immediately.

First, repeat the workflow manually, observe patterns, and then turn those patterns into policy files and scripts.

---

## 13. One-Line Summary

This experiment shows that a single Claude Code agent, guided by structured prompts and project policy files, can already participate in a meaningful RTL verification loop: generate RTL/TB/scripts, run Vivado xsim, detect failures, patch testbench/RTL issues, re-run simulations, and reach a clean passing verification result across an incrementally growing DUT stack.

---

## 14. AI-Assisted RTL Verification Benchmark

This project has grown into a structured RTL Verification Agent benchmark covering eight DUT layers and **664 passing checks**.

### Current Status

| Layer | DUT | Checks |
|-------|-----|--------|
| 0 | AXI-lite register file | 133/133 |
| 1 | AXI4 memory model | 30/30 |
| 2 | Simple AXI4 master | 14/14 |
| 3 | 1-word DMA copy engine | 16/16 |
| 4 | N-word DMA copy engine | 31/31 |
| 5 | AXI-lite DMA copy wrapper | 208/208 |
| 6 | N-word DMA add/processing engine | 81/81 |
| 7 | AXI-lite DMA add accelerator | 151/151 |
| **Total** | | **664/664** |

All checks pass. CI grep gate (`[FAIL]` / `FATAL`) is clean on all simulation scripts.

### Documentation

- [RTL Verification Agent Benchmark](docs/rtl_verification_agent_benchmark.md) — full layer-by-layer breakdown, verification patterns, agent capabilities, and coverage gaps
- [RTL Verification Workflow Summary](docs/rtl_verification_workflow_summary.md) — compact workflow diagram, completed-layer table, and future orchestrator context

### Context

This benchmark is being built to validate **Agent 4 (RTL Verification Agent)** in a planned five-agent hardware development orchestrator:

```
Algorithm Agent → Python Modeling Agent → RTL Design Agent
  → RTL Verification Agent (← here) → FPGA Test Agent
```
