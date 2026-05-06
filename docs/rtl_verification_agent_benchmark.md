# RTL Verification Agent Benchmark — Mini AXI/DMA Verification Stack

## Purpose

This is not primarily a production RTL design.

It is a **benchmark suite** for testing whether an AI agent can perform RTL verification tasks: reading context, writing testbenches, running Vivado xsim, detecting failures, distinguishing TB bugs from RTL bugs, closing coverage gaps, and maintaining persistent project state.

The DUTs are intentionally small but **incrementally structured**: each layer adds one new protocol concept or design pattern on top of the previous layer. This controlled complexity growth is what makes the benchmark useful — an agent that can verify layer N without breaking layers 0..N-1 demonstrates compositional verification capability.

---

## Placement in the Multi-Agent Orchestrator

The long-term hardware development orchestrator is planned around five agents:

```
1. Algorithm Agent          — defines algorithm, produces reference output
2. Python Modeling Agent    — builds floating-point / fixed-point model
3. RTL Design Agent         — produces synthesizable Verilog/SystemVerilog
4. RTL Verification Agent   ← this project
5. FPGA Test Agent          — board execution, UART/ILA/DMA feedback
```

This project is building and validating **Agent 4: the RTL Verification Agent**.

The benchmark is the data used to evaluate whether the agent is working correctly, just as a software engineer runs a test suite before declaring a feature done.

---

## Verified Layers

### Layer 0 — AXI-Lite Register File

| Item | Detail |
|------|--------|
| RTL | `rtl/axi_lite_regfile.v` |
| Testbench | `tb/axi_lite_regfile_tb.sv` |
| Script | `scripts/run_axi_regfile_sim.sh` |
| Checks | **133/133 PASS** |

**Purpose:** Baseline AXI-lite slave with 4 × 32-bit registers, SLVERR on invalid addresses, and all three write-channel orderings (simultaneous AW+W, AW-before-W, W-before-AW).

**Main verification features:**
- Reset state checks
- All three write-ordering paths (W_IDLE, W_WAIT_W, W_WAIT_A)
- B-channel and R-channel backpressure under valid and invalid addresses
- Byte-lane WSTRB isolation
- Invalid-address sweep across all three FSM states
- No-alias checks

**Limitations:** 4 registers only; no AxPROT, no read-modify-write atomics, no interrupt.

---

### Layer 1 — AXI4 Memory Model

| Item | Detail |
|------|--------|
| Model | `tb/axi_mem_model.sv` |
| Testbench | `tb/mem_rw_tb.sv` |
| Script | `scripts/run_mem_rw_sim.sh` |
| Checks | **30/30 PASS** |

**Purpose:** Simulation-only AXI4 slave (1024 × 32-bit words, parameterisable depth and base). Used as the data memory in every subsequent DMA test.

**Main verification features:**
- Full-word write/readback
- Partial WSTRB byte-lane writes
- OOB address returns SLVERR; unwritten locations return zero
- Hierarchical memory seeding via `slave.mem[idx]` for deterministic test setup

**Limitations:** Single-beat only; no burst, no ID, no AxSIZE/AxLEN/AxPROT; simulation use only.

---

### Layer 2 — Simple AXI4 Master

| Item | Detail |
|------|--------|
| RTL | `rtl/simple_axi_master.v` |
| Testbench | `tb/simple_axi_master_tb.sv` |
| Script | `scripts/run_simple_axi_master_sim.sh` |
| Checks | **14/14 PASS** |

**Purpose:** Minimal AXI4 master (write then read, single-beat) used to validate the master-side handshake pattern before introducing DMA engines.

**Main verification features:**
- Write + readback correctness
- Error detection on OOB address (SLVERR → error=1)

**Limitations:** Single write+read cycle per start; no streaming, no pipelining.

---

### Layer 3 — 1-Word DMA Copy Engine

| Item | Detail |
|------|--------|
| RTL | `rtl/simple_dma_copy.v` |
| Testbench | `tb/simple_dma_copy_tb.sv` |
| Script | `scripts/run_simple_dma_copy_sim.sh` |
| Checks | **16/16 PASS** |

**Purpose:** Single-word read→write DMA engine. Introduces the split AXI read + AXI write sequence and the copied_data output. Foundation for the N-word engine.

**Main verification features:**
- Normal copy correctness
- Read-error abort (destination memory unchanged)
- Write-error with source data preserved

**Limitations:** One word per start; no counter, no interrupt, no streaming.

---

### Layer 4 — N-Word DMA Copy Engine

| Item | Detail |
|------|--------|
| RTL | `rtl/simple_dma_copy_nword.v` |
| Testbench | `tb/simple_dma_copy_nword_tb.sv` |
| Script | `scripts/run_simple_dma_copy_nword_sim.sh` |
| Checks | **31/31 PASS** |

**Purpose:** Multi-word DMA copy with `length_words` parameter, `copied_count` output, and mid-transfer error abort. Introduces the loop-per-word FSM pattern used in all subsequent DMA engines.

**Main verification features:**
- Zero-length fast path
- Multi-word correctness (4 words)
- Mid-transfer read error: correctly processed words counted, remaining skipped, canary preserved
- Mid-transfer write error: same abort discipline

**Limitations:** Sequential word-by-word (no burst); 16-bit word count maximum.

---

### Layer 5 — AXI-Lite Controlled DMA Copy Wrapper

| Item | Detail |
|------|--------|
| RTL | `rtl/simple_dma_ctrl.v` |
| Testbench | `tb/simple_dma_ctrl_tb.sv` |
| Script | `scripts/run_simple_dma_ctrl_sim.sh` |
| Checks | **208/208 PASS** |

**Purpose:** Memory-mapped peripheral wrapper around Layer 4. Introduces AXI-lite control plane separation from AXI4 data plane, sticky status registers, busy guard, and register latching on start.

**Register map:** CONTROL (0x00), SRC_ADDR (0x04), DST_ADDR (0x08), LENGTH_WORDS (0x0C), STATUS (0x10), COPIED_COUNT (0x14).

**Main verification features:**
- All three AXI-lite write orderings (W_IDLE, W_WAIT_W, W_WAIT_A)
- B-channel and R-channel backpressure under OKAY and SLVERR
- Busy-state register reads (STATUS.busy=1, COPIED_COUNT in-flight)
- Re-trigger guard: second CONTROL.start while busy is silently ignored
- Mid-flight register corruption (SRC/DST/LEN overwritten while running — latched values protect the active transfer)
- Zero-length and immediate restart
- OOB source and OOB destination mid-copy

**Limitations:** No interrupt output; COPIED_COUNT read may lag one cycle behind actual count; AXI-lite and AXI4 master share the same clock domain.

---

### Layer 6 — N-Word DMA Add/Processing Engine

| Item | Detail |
|------|--------|
| RTL | `rtl/simple_dma_add_nword.v` |
| Testbench | `tb/simple_dma_add_nword_tb.sv` |
| Script | `scripts/run_simple_dma_add_nword_sim.sh` |
| Checks | **81/81 PASS** |

**Purpose:** First processing DMA — identical FSM to Layer 4 but adds a programmable 32-bit constant to each word before writing. Introduces `add_value`, `last_input_data`, and `last_output_data` outputs. Demonstrates that the agent can extend a verified design with a new processing datapath while keeping existing tests passing.

**Main verification features:**
- Normal add correctness (single word, multi-word)
- 32-bit arithmetic overflow (wraps, no error)
- Identity mode (add_value=0 is a copy)
- Error-case observability: last_input_data and last_output_data correctly reflect the failed word
- Restart-after-read-error and restart-after-write-error

**Limitations:** Addition only; no multiply, shift, or configurable operation. Datapath is purely combinatorial — no pipeline register between read and write.

---

### Layer 7 — AXI-Lite Controlled DMA Add Accelerator

| Item | Detail |
|------|--------|
| RTL | `rtl/simple_dma_add_ctrl.v` |
| Testbench | `tb/simple_dma_add_ctrl_tb.sv` |
| Script | `scripts/run_simple_dma_add_ctrl_sim.sh` |
| Checks | **151/151 PASS** |

**Purpose:** Memory-mapped accelerator wrapper around Layer 6. Extends the Layer 5 control-plane pattern with four additional read-only registers: ADD_VALUE (R/W), STATUS.busy, PROCESSED_COUNT, LAST_INPUT_DATA, LAST_OUTPUT_DATA.

**Register map:** CONTROL (0x00), SRC_ADDR (0x04), DST_ADDR (0x08), LENGTH_WORDS (0x0C), ADD_VALUE (0x10), STATUS (0x14, includes busy bit), PROCESSED_COUNT (0x18), LAST_INPUT_DATA (0x1C), LAST_OUTPUT_DATA (0x20).

**Main verification features:**
- Register readback sanity and SLVERR for invalid addresses
- Normal add (1-word and 4-word), identity, overflow, zero-length
- OOB source and OOB destination mid-transfer
- Busy-state STATUS read + re-trigger guard
- Restart-after-error

**Limitations:** No AXI-lite write ordering tests (only simultaneous AW+W used in testbench); no backpressure tests on the accelerator's AXI-lite port; LAST_INPUT/LAST_OUTPUT not cleared between transfers.

---

## Cumulative Check Count

| Layer | DUT | Checks |
|-------|-----|--------|
| 0 | AXI-lite register file | 133 |
| 1 | AXI4 memory model | 30 |
| 2 | Simple AXI4 master | 14 |
| 3 | 1-word DMA copy | 16 |
| 4 | N-word DMA copy | 31 |
| 5 | AXI-lite DMA copy wrapper | 208 |
| 6 | N-word DMA add engine | 81 |
| 7 | AXI-lite DMA add accelerator | 151 |
| **Total** | | **664** |

All 664 checks pass with zero failures and zero FATAL events.

---

## Verification Patterns

### negedge-drive / posedge-sample

All testbench bus master tasks drive AXI signals on the falling clock edge and sample DUT ready/valid outputs on the rising edge. This eliminates the setup-time race that caused the first testbench hang during early development.

### Timeout guards

Every wait loop (`while (!done)`, `while (!bvalid)`, etc.) includes a cycle counter that calls `$fatal(1, ...)` after a configurable limit. Simulations never hang silently.

### [PASS]/[FAIL] log format

Every check emits either `[PASS]` or `[FAIL]` with the label, got value, and expected value. The final line reports `N/N checks passed` or `N/M checks passed (K failure(s))`.

### CI grep gate

The simulation script ends with:
```bash
if grep -qE '\[FAIL\]|FATAL' logs/*.log; then exit 1; fi
```
Any `[FAIL]` or `$fatal` line causes a non-zero exit code. This makes the scripts suitable for integration into CI pipelines.

### Prompt backup

Every task prompt is saved verbatim into `md_files/NN_<task_name>_prompt.md` before any implementation begins. This creates an auditable history of what was asked and in what order.

### current_status.md as persistent project memory

`ai_context/current_status.md` is the authoritative record of implementation state, register maps, FSM descriptions, verification counts, and remaining limitations for every layer. The agent reads this file at the start of every session before taking any action.

### Approval gate before RTL modification

The task scope in each prompt explicitly lists which files may be created or modified. RTL files are excluded by default. The agent must request explicit approval before patching RTL. This prevents silent RTL regressions across sessions.

### Targeted coverage-gap closure

Each prompt explicitly states the current limitation and the specific additional scenarios to cover, rather than asking for "more tests." This keeps each session focused and the check count growth predictable.

---

## What the RTL Verification Agent Does

The agent operates in a realistic simulation-feedback loop:

1. **Read context** — reads `CLAUDE.md`, `ai_context/current_status.md`, and relevant source files within the approved scope.
2. **Inspect allowed files only** — does not scan the full repository; works with the files listed in the prompt scope.
3. **Create/update testbenches** — writes or extends SystemVerilog testbenches with self-checking tasks, timeout guards, and [PASS]/[FAIL] output.
4. **Create/update simulation scripts** — writes Bash scripts that call xvlog, xelab, xsim, and apply the CI grep gate.
5. **Run Vivado xsim** — executes the simulation script and captures logs.
6. **Detect failures** — parses `[FAIL]` and `FATAL` lines; identifies which check failed and at what simulation time.
7. **Distinguish TB bug vs RTL bug** — determines whether the failure is a testbench mistake (wrong expected value, missing seed, race condition) or a genuine RTL behavioral issue.
8. **Patch TB/scripts automatically** — corrects testbench errors and reruns without human intervention, within the approved file scope.
9. **Request approval before RTL changes** — flags RTL bugs and waits for explicit authorization before modifying RTL files.
10. **Update current_status.md** — records the new check count, test descriptions, coverage annotations, and simulation end time after every successful run.
11. **Save prompt history** — writes the current prompt to `md_files/` before starting implementation.

---

## Why This Benchmark Matters

### Simulation-feedback loop

The benchmark tests whether the AI agent can operate in the same kind of closed-loop verification workflow that human engineers use: write a test, run a simulation, read the log, fix the bug, rerun. This is a non-trivial capability because it requires the agent to correctly interpret simulation log output, map failures back to source lines, and make targeted edits without breaking passing tests.

### Incremental complexity

The DUT stack progresses from a 4-register AXI-lite slave (133 checks) through a full memory-mapped processing accelerator (151 checks), with each layer introducing exactly one new concept. This controlled growth ensures that failures at later layers are attributable to the new concept, not accumulated technical debt.

### Foundation for OFDM/DSP verification

The add-accelerator pattern (read word → process → write word) is the same loop used in FFT butterfly units, FIR filter taps, and OFDM subcarrier processing. Verifying that a DMA engine can process words with a programmable arithmetic operation is a prerequisite for verifying more complex DSP datapaths.

### Path to FPGA and RF experiments

Once the RTL Verification Agent is reliable at the simulation level, the same workflow extends to:
- FPGA board execution with UART-based pass/fail reporting
- On-chip ILA captures for timing and protocol debugging
- DMA buffer loopback tests (write known data → accelerate → read back via DMA → compare)
- RF front-end experiments with SDR hardware, where the DUT is part of an OFDM receive chain

---

## Not Yet Covered

| Gap | Notes |
|-----|-------|
| Formal verification | No SVA assertions; no bounded model checking or equivalence checking |
| Randomized regression | All tests are directed; no constrained-random stimulus or coverage-driven closure |
| Functional coverage metrics | No SystemVerilog covergroups or coverpoints |
| Full AXI4 burst support | All DMA engines are single-beat; no INCR/WRAP burst, no AxLEN |
| Multiple outstanding transactions | One in-flight AXI transaction at a time |
| Board-level FPGA execution | Simulation only; no bitstream generation or hardware loop |
| RF/OFDM experiment automation | Not yet started; awaiting Algorithm Agent and Python Modeling Agent layers |
| Clock-domain crossing | All designs are single-clock |
| Power and timing closure | No synthesis or implementation runs |
