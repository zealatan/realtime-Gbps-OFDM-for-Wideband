# AI-Assisted RTL/FPGA Synchronizer Verification Workflow

## 1. Overview

This project is an AI-assisted RTL/FPGA verification experiment using **Claude Code Pro** as a coding and verification agent.

The active workspace for this project is:

```text
/home/zealatan/RTL_SYNC
```

This workspace is separate from the earlier `VIVADO_MIN_EXAMPLE` benchmark project.

The current goal of `RTL_SYNC` is to build and verify an FPGA-ready **OFDM synchronizer subsystem** step by step.

The project currently focuses on:

```text
OFDM frame detection
→ CP/timing synchronization
→ fractional CFO estimation
→ fractional CFO correction
→ corrected time-domain frame output
```

This is **not yet a full OFDM receiver**. The current scope intentionally stops before FFT, integer CFO, channel estimation, equalization, and demodulation.

---

## 2. Project Roadmap

The project roadmap is organized into three phases.

```text
Phase 1: Functional FPGA synchronizer
Phase 2: 1 sample/clock streaming synchronizer
Phase 3: multi-sample/clock parallel synchronizer
```

### Phase 1 Goal

Phase 1 focuses on proving that the synchronizer block can functionally run on FPGA.

The Phase 1 design is allowed to be:

```text
frame-buffered
FSM-controlled
debug-friendly
not fully throughput-optimized
```

Phase 1 does **not** require a continuous 1 sample/clock streaming architecture.

### Phase 2 Goal

Phase 2 will redesign the synchronizer into a true 1 sample/clock streaming pipeline.

This likely requires:

```text
sliding CP/autocorrelation update
continuous metric generation
streaming peak detection
streaming NCO correction
pipeline balancing
```

### Phase 3 Goal

Phase 3 will extend the design into a multi-sample/clock architecture for high-throughput RFSoC-class operation.

This likely requires:

```text
multi-lane input/output
parallel correlation updates
lane-wise peak detection
multi-lane NCO correction
wide AXI-Stream datapaths
```

---

## 3. Active Workspace Policy

The active workspace is:

```text
/home/zealatan/RTL_SYNC
```

All RTL, testbench, simulation, documentation, prompt archive, and status updates for this project should be performed inside this workspace.

Do not confuse this project with:

```text
/home/zealatan/AI_ORC/messi/VIVADO_MIN_EXAMPLE
```

That path belongs to a different earlier RTL verification benchmark.

Before any major Claude task, the agent should verify:

```bash
pwd
git rev-parse --show-toplevel
```

The path must resolve to:

```text
/home/zealatan/RTL_SYNC
```

---

## 4. Environment Split

The workflow uses a split environment.

### WSL Environment

The WSL workspace is used for:

```text
RTL editing
testbench editing
Vivado xsim simulation
documentation
prompt archive
ai_context updates
Claude Code RTL/simulation work
```

### Windows Environment

Windows is used for:

```text
Vivado synthesis
Vivado implementation
bitstream generation
Vivado Hardware Manager
Vitis firmware development
ZCU102 board programming
```

Reason:

```text
The valid Vivado license for ZCU102 synthesis/implementation/bitstream generation is installed or served on Windows.
```

Therefore, WSL may prepare TCL/scripts, but exact ZCU102 synthesis, implementation, bitstream generation, and Vitis work should be executed on Windows Vivado/Vitis unless the Windows license server is reliably reachable from WSL.

Target board:

```text
ZCU102
```

Target part:

```text
xczu9eg-ffvb1156-2-e
```

Current synchronizer clock port:

```text
aclk
```

Do not use `clk` as the top-level clock name for current synthesis constraints.

---

## 5. Current Design Scope

The current top-level synchronizer block is:

```text
rtl/frac_cfo_frame_corrector_top.v
```

Current testbench:

```text
tb/frac_cfo_frame_corrector_top_tb.sv
```

Current simulation script:

```text
scripts/run_frac_cfo_frame_corrector_top_sim.sh
```

The top-level architecture is:

```text
AXI-Stream IQ input
  ↓
input capture / frame buffer
  ↓
frame detector
  ↓
CP timing / fractional CFO estimation
  ↓
NCO-based fractional CFO correction
  ↓
AXI-Stream corrected IQ output
```

The current architecture is best described as:

```text
Phase-1 frame-buffered sequential synchronizer
```

It is not yet a Phase-2 1 sample/clock streaming synchronizer.

---

## 6. Completed Steps

### Step 20 — frac_cfo_frame_corrector_top Integration

Step 20 integrated the fractional-CFO synchronizer pipeline into:

```text
rtl/frac_cfo_frame_corrector_top.v
```

The integrated top includes:

```text
input capture
shared IQ frame buffer
frame detection
CP timing / fractional CFO estimation
NCO-based fractional CFO correction
AXI-Stream corrected output playback
```

Step 20 result:

```text
PASS = 39
FAIL = 0
CI GATE = PASSED
```

Step 20 established the first complete integrated top for the Phase-1 synchronizer path.

---

### Step 21 — Randomized Verification Campaign

Step 21 strengthened verification of `frac_cfo_frame_corrector_top`.

The previous plan for Step 21 was:

```text
int_cfo_estimator.v
```

However, this was deferred.

Reason:

```text
The current Phase 1 goal is to close the existing fractional-CFO frame synchronizer as a robust functional FPGA-ready block before adding integer CFO or FFT-based functionality.
```

Step 21 added randomized and sweep-based verification.

Verification groups:

```text
R1 — Timing offset sweep
R2 — Fractional CFO sweep
R3 — Randomized frame placement
R4 — Randomized amplitude scaling
R5 — AXI-Stream output backpressure
R6 — Reset robustness
R7 — No-frame / false-trigger rejection
R8 — Buffer boundary stress
```

Step 21 result:

```text
PASS = 176
FAIL = 0
Randomized trials = 30
CI GATE = PASSED
RTL modified = No
```

Bugs found:

```text
RTL bugs: none

Testbench bugs:
1. Group failure logic used global fail count instead of per-group delta.
2. Some tests used fewer than WINDOW_LEN=4 quiet samples before frame onset.
```

Both were fixed in the testbench.

---

## 7. Deferred Work

### Deferred: Integer CFO Estimator

The following planned block is deferred:

```text
int_cfo_estimator.v
```

Original idea:

```text
PSS cross-correlation
512-point FFT
conj(PSS_ref) multiplication
IFFT
peak detection
integer CFO estimation
```

Reason for deferral:

```text
Integer CFO estimation introduces FFT/IFFT, PSS/reference sequence handling, and additional algorithmic scope.
The current goal is Phase 1 FPGA functional bring-up of the existing fractional-CFO synchronizer block.
```

Integer CFO may be revisited later as:

```text
Phase 1b extension
Phase 2 feature
or a separate synchronizer expansion task
```

---

## 8. Next Steps

The revised roadmap from the current state is:

```text
Step 22 — Phase-1 synthesis-readiness and Vivado resource/timing check
Step 23 — AXI-Lite + AXI-Stream debug/config wrapper
Step 24 — BRAM preload/readback wrapper for known-vector FPGA test
Step 25 — Windows Vivado ZCU102 project / synthesis / implementation / bitstream flow
Step 26 — Vitis baremetal control/readback application
Step 27 — Known-vector FPGA run
Step 28 — CFO/timing sweep hardware test
Step 29 — Phase-1 final report/demo package
```

---

## 9. Step 22 Plan

Step 22 should check whether the Step 21-verified synchronizer top is synthesizable and suitable for Phase-1 FPGA bring-up.

Step 22 should create or update:

```text
scripts/run_frac_cfo_frame_corrector_top_synth.sh
scripts/step22_synth_check.tcl
docs/step22_synthesis_readiness_report.md
reports/
ai_context/current_status.md
```

Important Step 22 target information:

```text
Target board = ZCU102
Target part = xczu9eg-ffvb1156-2-e
Clock port = aclk
Clock target = 100 MHz
```

Important constraint:

```text
Do not use clk.
Use aclk.
```

Step 22 should audit for synthesis risks such as:

```text
real
shortreal
$sin
$cos
$atan
$atan2
$sqrt
$ln
delay statements
file I/O
runtime initial blocks
latch inference risks
combinational loop risks
multi-driven net risks
```

Because the ZCU102 license is on Windows, exact ZCU102 synthesis should be treated as a Windows Vivado task.

---

## 10. Step 23 Plan

Step 23 should add an AXI-Lite debug/config wrapper while preserving AXI-Stream data ports.

Important distinction:

```text
AXI-Lite = control/status plane
AXI-Stream = IQ sample data plane
```

The wrapper should expose both:

```text
AXI-Lite slave interface
AXI-Stream input
AXI-Stream output
```

Step 23 should not add:

```text
FFT
integer CFO
DMA
BRAM preload/readback
bitstream generation
Phase 2 redesign
```

Possible register map:

```text
0x00 CONTROL
0x04 STATUS
0x08 CFG_CFO_STEP
0x0C CFG_TIMING_OFFSET
0x10 CFG_FRAME_LEN
0x14 SAMPLE_COUNT
0x18 OUTPUT_COUNT
0x1C DEBUG_STATE
```

---

## 11. Step 24 Plan

Step 24 should provide a data path for known-vector FPGA testing.

Purpose:

```text
preload input IQ samples
feed them into the synchronizer as AXI-Stream
capture output samples
read back output samples
compare against Python/golden reference
```

Recommended structure:

```text
AXI-Lite control
  ↓
Input BRAM
  ↓
AXI-Stream source FSM
  ↓
frac_cfo synchronizer
  ↓
AXI-Stream sink FSM
  ↓
Output BRAM
```

Step 24 is still a Phase-1 functional bring-up step.

---

## 12. Prompt Archive Policy

All major Claude/RTL verification prompts must be saved under:

```text
md_files/
```

Naming convention:

```text
NN_descriptive_step_name_prompt.md
```

Current important prompt archives include:

```text
md_files/20_frac_cfo_frame_corrector_top_prompt.md
md_files/21_frac_cfo_frame_corrector_randomized_verification_prompt.md
```

The next required prompt archive is:

```text
md_files/22_synthesis_readiness_prompt.md
```

Prompt files are part of the experiment record and should be committed to git.

---

## 13. AI-Assisted Verification Method

This project continues the broader experiment of using Claude Code as an RTL/FPGA verification agent.

The repeated loop is:

```text
Spec
→ Code generation
→ Simulation
→ Failure detection
→ Debugging
→ Patch
→ Re-run
→ Pass summary
→ Documentation update
```

Human role:

```text
define scope
approve roadmap changes
protect file boundaries
classify high-level design direction
decide when to defer scope expansion
review final reports
```

Claude Code role:

```text
read CLAUDE.md and ai_context/current_status.md
save prompt archives
modify allowed files
generate RTL/TB/scripts/docs
run xsim
read logs
fix testbench issues
avoid RTL changes unless proven necessary
update status files
summarize results
```

---

## 14. Current Maturity

For `RTL_SYNC`, the current maturity is:

```text
Level 2.5 to Level 3
```

Meaning:

```text
Claude edits files
Claude runs simulations
Claude reads logs
Claude detects and fixes testbench issues
Claude updates documentation/status
Human still controls roadmap and approval gates
```

The project has not yet reached FPGA hardware feedback loop level.

That will begin after:

```text
Step 24 BRAM preload/readback wrapper
Step 25 Windows Vivado bitstream flow
Step 26 Vitis control app
Step 27 known-vector FPGA run
```

---

## 15. One-Line Summary

`RTL_SYNC` is now a Phase-1 AI-assisted RTL/FPGA synchronizer verification project. The fractional-CFO frame synchronizer top has passed integration testing and a stronger randomized verification campaign, while integer CFO has been deferred so the current synchronizer block can first be closed as a functional FPGA-ready subsystem.
