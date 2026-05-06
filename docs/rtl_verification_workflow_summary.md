# RTL Verification Workflow Summary

## Agent Role

This project is building the **RTL Verification Agent** component of a planned multi-agent hardware development orchestrator.

---

## Workflow

```
Human prompt / policy
  ↓
Claude Code RTL Verification Agent
  ↓  (reads CLAUDE.md, current_status.md, approved source files)
RTL / TB / script creation or modification
  ↓
Vivado xsim (xvlog → xelab → xsim)
  ↓
Log parsing  →  [PASS]/[FAIL] count, FATAL detection
  ↓
Patch TB or script (auto, within scope)
OR flag RTL bug → await human approval → patch RTL
  ↓
Rerun → pass → update current_status.md + save prompt to md_files/
```

**Key constraints applied at every step:**
- Drive AXI signals on negedge; sample on posedge
- Timeout guard on every wait loop
- CI gate: `grep -qE '\[FAIL\]|FATAL' logs/*.log && exit 1`
- No RTL modification without explicit human approval
- Scope declared per-prompt; no whole-repo scanning

---

## Completed Verification Layers

| Layer | DUT | RTL File | Checks | Status |
|-------|-----|----------|--------|--------|
| 0 | AXI-lite register file | `rtl/axi_lite_regfile.v` | 133/133 | PASS |
| 1 | AXI4 memory model | `tb/axi_mem_model.sv` | 30/30 | PASS |
| 2 | Simple AXI4 master | `rtl/simple_axi_master.v` | 14/14 | PASS |
| 3 | 1-word DMA copy | `rtl/simple_dma_copy.v` | 16/16 | PASS |
| 4 | N-word DMA copy | `rtl/simple_dma_copy_nword.v` | 31/31 | PASS |
| 5 | AXI-lite DMA copy wrapper | `rtl/simple_dma_ctrl.v` | 208/208 | PASS |
| 6 | N-word DMA add engine | `rtl/simple_dma_add_nword.v` | 81/81 | PASS |
| 7 | AXI-lite DMA add accelerator | `rtl/simple_dma_add_ctrl.v` | 151/151 | PASS |
| | **Total** | | **664/664** | |

---

## Future Multi-Agent Orchestrator

```
┌─────────────────────────────────────────────────────────┐
│  Hardware Development Orchestrator                       │
│                                                          │
│  1. Algorithm Agent                                      │
│     Defines algorithm; produces reference output         │
│                                                          │
│  2. Python Modeling Agent                                │
│     Floating-point and fixed-point models               │
│                                                          │
│  3. RTL Design Agent                                     │
│     Produces synthesizable Verilog/SystemVerilog         │
│                                                          │
│  4. RTL Verification Agent   ← current focus            │
│     Testbench, xsim, log parsing, coverage closure      │
│                                                          │
│  5. FPGA Test Agent                                      │
│     Board execution, UART, ILA, DMA buffer loopback      │
└─────────────────────────────────────────────────────────┘
```

**Current focus:** Agent 4 — RTL Verification Agent.

Agents 1–3 and 5 are not yet implemented. When Agent 3 produces RTL, Agent 4 will verify it automatically using the patterns established in this benchmark. When Agent 5 is added, the loop extends from simulation into hardware.

---

## Coverage Gaps (simulation level)

- No formal verification or SVA assertions
- No constrained-random stimulus or functional coverage metrics
- No AXI4 burst support
- No clock-domain crossing tests
- No synthesis or timing closure
