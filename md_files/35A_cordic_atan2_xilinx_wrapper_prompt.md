# Step 35A — Xilinx CORDIC atan2 Replacement Preparation and Standalone Verification

## Mandatory archival rule

Before modifying any file, save this entire prompt verbatim as:

md_files/35A_cordic_atan2_xilinx_wrapper_prompt.md

If the md_files/ directory does not exist, create it first.

## Working directory

/home/zealatan/RTL_SYNC_STEP35A

## Branch / worktree context

This worktree is dedicated to Step 35A:

branch: step35a_cordic_atan2_ip
path: /home/zealatan/RTL_SYNC_STEP35A

The main repository remains at:

/home/zealatan/RTL_SYNC

Do not modify the main worktree from this session.

## Important workflow separation

This project uses a split workflow:

WSL/Linux side:
- Claude Code works here.
- Source/documentation editing is done here.
- RTL/testbench/simulation work is done here.
- Vivado xsim simulation may be run from WSL if supported.

Windows side:
- The user manually pulls/merges code later.
- The user manually uses Vivado/Vitis for synthesis/implementation/board execution.
- The user manually programs the ZCU102 board.
- The user manually runs UART/COM tests.

For this step:
- Do not run Windows Vivado.
- Do not run Vitis.
- Do not access COM5.
- Do not modify board/Vitis host files.
- Do not claim any board result.

This is a standalone CORDIC atan2 replacement-preparation step.

## Critical output rule

Do not print long source files into the chat.

Create or edit files directly in the filesystem.

At the end, report only:
- files changed
- tests run
- PASS/FAIL/pending
- next step

## Context

The current RTL_SYNC project has already achieved:

Step 29I:
- ZCU102 board regression PASS / CLOSED.
- AXI-Lite, BRAM source, stream handshake, frame detector, corrected output BRAM, and PS readback path validated.

Step 30:
- Meyr integer CFO architecture spec completed.

Step 31:
- Meyr direct-correlation core completed.
- PASS: 32, FAIL: 0, CI GATE: PASSED.

Step 32:
- Meyr PSS/SSS product generator and frequency-domain estimator top completed.
- Product generator PASS: 13, FAIL: 0.
- Estimator top PASS: 32, FAIL: 0.

Step 33:
- real mU/goldU audit completed.
- real mU/goldU-derived term2 ROM remains pending.

Step 34:
- FFT frontend behavioral integration is being handled separately in the main lane.

Now Step 35A focuses only on the fractional CFO path's atan2/CORDIC replacement preparation.

## Why Step 35A is needed

The current fractional CFO/timing path uses a behavioral CORDIC atan2 model.

The current file is expected to be something like:

rtl/cordic_atan2.v

It likely contains simulation-only constructs such as:
- real
- $atan2
- $itor
- $rtoi

This is acceptable for simulation but not production-synthesizable FPGA RTL.

The existing comments may already say something like:
- Behavioral simulation model of Xilinx CORDIC IP v6.0
- Synthesis target: replace with cordic_v6_0 IP instantiation

Therefore Step 35A should prepare an IP-ready replacement path for atan2 without modifying the existing top integration yet.

## Step 35A goal

Create a standalone Xilinx-CORDIC-compatible atan2 wrapper strategy and verification testbench.

This step should:

1. Inspect the existing behavioral cordic_atan2.v.
2. Document its interface, latency, input/output format, and expected phase scaling.
3. Create a new standalone wrapper module for a future Xilinx CORDIC atan2/vectoring/translate IP replacement.
4. Preserve the old behavioral module unchanged unless a trivial comment-only update is needed.
5. Create a deterministic self-checking testbench comparing the wrapper behavior against a golden atan2 model.
6. Avoid integration into timing_frac_cfo_top or frac_cfo_frame_corrector_top in this step.
7. Avoid modifying board wrapper files.
8. Avoid modifying README.md and ai_context/current_status.md in this branch to reduce merge conflicts.
9. Produce documentation explaining how the eventual Xilinx CORDIC IP should be configured and where it will replace the behavioral model.

Important:
- If actual Xilinx CORDIC IP generation is feasible in this WSL environment and consistent with existing project flow, create a TCL helper script.
- If actual IP generation is not feasible, do not fake it. Create an IP-ready wrapper and document that real XCI/IP generation is pending.
- The standalone testbench may use a behavioral model for simulation as long as it is clearly marked simulation-only.
- Do not claim that production Xilinx IP has been integrated unless an actual IP instance/XCI is generated and compiled.

## Files to inspect first

Inspect these files before editing:

rtl/
tb/
scripts/
docs/
md_files/

Specifically search:

find . -type f | grep -Ei "cordic|atan|cfo|timing|frac|nco|rotator|corrector"
grep -R "module cordic_atan2\|atan2\|CORDIC\|cordic\|real\|\$atan2\|\$sin\|\$cos" -n rtl tb docs scripts 2>/dev/null
grep -R "timing_frac_cfo\|frac_cfo_estimator\|frac_cfo_frame_corrector\|nco_phase_gen" -n rtl tb docs scripts 2>/dev/null

Inspect at minimum if present:

rtl/cordic_atan2.v
rtl/frac_cfo_estimator.v
rtl/timing_frac_cfo_top.v
rtl/frac_cfo_frame_corrector_top.v
tb/cordic_atan2_tb.sv
scripts/run_cordic_atan2_sim.sh
docs/step11*
docs/*cordic*
docs/*frac*cfo*

Also inspect existing script style:

find scripts -maxdepth 1 -type f -name "run_*_sim.sh" -print

## Existing behavior to preserve

Do not break existing behavioral simulation flow.

If rtl/cordic_atan2.v currently passes an existing testbench, preserve it.

If you create a new wrapper, use a new file name such as:

rtl/cordic_atan2_xilinx_wrapper.v

Do not replace rtl/cordic_atan2.v inside existing tops yet.

Step 35A is standalone. Integration into the real fractional CFO path should be a later step.

## Required design decision

The wrapper should be designed around a future Xilinx CORDIC atan2 equivalent.

Xilinx CORDIC IP likely uses AXI-Stream style input/output, with a latency and valid pipeline.

The current project probably expects a simpler module-level interface.

Therefore create a project-local wrapper that hides the eventual Xilinx IP details.

Recommended wrapper file:

rtl/cordic_atan2_xilinx_wrapper.v

Recommended interface should match or closely adapt to the existing cordic_atan2.v interface after inspection.

If the existing cordic_atan2.v interface is different, prioritize compatibility with the existing interface.

Possible interface pattern:

module cordic_atan2_xilinx_wrapper #(
    parameter XY_WIDTH = 40,
    parameter PHASE_WIDTH = 16,
    parameter LATENCY = 15,
    parameter USE_BEHAVIORAL_MODEL = 1
)(
    input  wire                         aclk,
    input  wire                         aresetn,

    input  wire                         s_valid,
    input  wire signed [XY_WIDTH-1:0]   s_x,
    input  wire signed [XY_WIDTH-1:0]   s_y,

    output reg                          m_valid,
    output reg signed [PHASE_WIDTH-1:0] m_phase
);

But adapt this after inspecting the actual existing module.

## Simulation model requirement

Because actual Xilinx CORDIC IP may not be available in this branch, the wrapper may include a behavioral simulation mode:

parameter USE_BEHAVIORAL_MODEL = 1

If USE_BEHAVIORAL_MODEL=1:
- Use simulation-only atan2 logic to produce the same expected phase as the existing behavioral cordic_atan2.v.
- Use explicit comments:
  This branch is for simulation and IP interface preparation only.
  Production synthesis must replace this behavioral path with Xilinx CORDIC IP.

If USE_BEHAVIORAL_MODEL=0:
- Provide a clearly marked placeholder area for future Xilinx CORDIC IP instantiation.
- Do not instantiate a fake module with an unsupported name unless accompanied by a clear stub and documentation.
- If creating a stub module, name it clearly as a placeholder and do not claim it is the actual Xilinx IP.

Preferred:
- Keep the wrapper synthesizable shell clean.
- Keep behavioral atan2 model under synthesis guards if appropriate:
  synthesis translate_off / translate_on
or project-consistent simulation guard.

Do not introduce non-synthesizable code into modules that will be treated as production RTL without clear guard/comment.

## Xilinx IP configuration document

Create documentation that states the intended Xilinx CORDIC IP configuration.

The document should discuss:

- IP: Xilinx CORDIC v6.0 or compatible
- Function: atan2 equivalent, likely Translate / Vectoring mode
- Input: signed X/Y Cartesian vector
- Output: phase angle
- AXI-Stream input/output
- Output phase format and scaling
- Latency target: match existing LATENCY parameter, likely 15 cycles
- Need to verify phase scaling against current PHASE_WIDTH=16 convention
- Need to verify quadrant correctness
- Need to verify valid pipeline alignment
- Need to verify reset behavior
- Need to verify zero-vector behavior

If you do not know exact Xilinx CORDIC parameter names, do not invent exact Tcl properties as facts. You may provide a preliminary Tcl skeleton with TODO comments.

## Optional TCL helper

If useful, create:

scripts/create_cordic_atan2_ip.tcl

Purpose:
- Future helper to create Xilinx CORDIC atan2 IP in Vivado.
- It should be clearly marked as preliminary unless verified.
- It should not be required by the Step 35A simulation.

If exact IP property names are uncertain:
- include comments and TODOs
- do not claim the TCL is production-ready
- do not make simulation depend on it

## Required testbench

Create:

tb/cordic_atan2_xilinx_wrapper_tb.sv

The testbench should be deterministic and self-checking.

It should:
- Reset the wrapper.
- Apply known X/Y vectors.
- Wait for m_valid.
- Compare m_phase to a golden atan2 model within acceptable integer tolerance.
- Check latency if the wrapper promises fixed latency.
- Check valid alignment.
- Print PASS/FAIL count and CI gate line.

Required tests: at least 12 groups.

Recommended tests:

T1 reset_defaults:
- After reset, output valid low and phase stable/zero if applicable.

T2 positive_x_zero_y:
- x > 0, y = 0
- expected phase approximately 0.

T3 zero_x_positive_y:
- x = 0, y > 0
- expected phase approximately +pi/2.

T4 negative_x_zero_y:
- x < 0, y = 0
- expected phase approximately +pi or -pi depending convention.
- Document expected convention.

T5 zero_x_negative_y:
- x = 0, y < 0
- expected phase approximately -pi/2.

T6 quadrant_I:
- x > 0, y > 0.

T7 quadrant_II:
- x < 0, y > 0.

T8 quadrant_III:
- x < 0, y < 0.

T9 quadrant_IV:
- x > 0, y < 0.

T10 small_values:
- low magnitude vector.

T11 large_values:
- near maximum safe input values.

T12 back_to_back_valids:
- multiple valid inputs in consecutive cycles.
- Verify output valid order and phase sequence.

T13 optional zero_vector:
- x=0, y=0.
- Define and test expected behavior if current model has one.

T14 optional pipeline_latency:
- Check m_valid occurs exactly LATENCY cycles after s_valid if fixed latency is part of the wrapper contract.

Required final output:
PASS: <count> FAIL: <count>
CI GATE: PASSED
or
CI GATE: FAILED

## Phase scaling requirement

Before writing the testbench expected values, inspect the current cordic_atan2.v phase scaling.

Document the convention in comments.

Possible convention examples:
- signed PHASE_WIDTH where pi maps to +32768 or -32768 for PHASE_WIDTH=16
- 2*pi maps to 2^PHASE_WIDTH
- output range may be [-pi, +pi)
- output range may be [0, 2*pi)

Do not guess. Infer from existing code.

The wrapper and testbench must use the same convention as existing cordic_atan2.v.

If existing convention is ambiguous, document the inferred convention and add tests that match the current behavioral model.

## Required simulation script

Create:

scripts/run_cordic_atan2_xilinx_wrapper_sim.sh

Use existing project script style.

The script should:
- compile rtl/cordic_atan2_xilinx_wrapper.v
- compile tb/cordic_atan2_xilinx_wrapper_tb.sv
- run xsim
- save logs according to project convention
- grep for FAIL/FATAL/CI GATE failure
- exit nonzero on failure
- be executable

If there is an existing rtl/cordic_atan2.v and existing tb, do not delete them.

Optionally, if useful, also compile rtl/cordic_atan2.v for comparison in the testbench, but avoid duplicate module name conflicts.

## Documentation update

Create:

docs/step35A_cordic_atan2_xilinx_wrapper.md

Include:

# Step 35A — Xilinx CORDIC atan2 Wrapper Preparation

Sections:
- Objective
- Why this step is needed
- Existing behavioral cordic_atan2 status
- Existing interface and phase scaling
- Proposed Xilinx CORDIC replacement strategy
- Wrapper interface
- Simulation behavior
- Intended future Xilinx IP configuration
- Testbench scenarios
- Simulation command
- Simulation result
- Known limitations
- Next steps

Known limitations must include:
- Actual Xilinx CORDIC IP XCI is not integrated unless this step truly generates and verifies it.
- Current wrapper may still use behavioral atan2 for simulation.
- Integration into timing_frac_cfo_top is not done in Step 35A.
- Board validation is not part of Step 35A.

## Do not modify shared status files in this branch

To avoid merge conflicts with Step 35B and the main Step 34 lane, do not modify:

README.md
ai_context/current_status.md

Instead, put all Step 35A status in:

docs/step35A_cordic_atan2_xilinx_wrapper.md

The main branch can later merge/cherry-pick this branch and update README/current_status once.

## Do not modify

Do not modify board/Vitis host files.

Do not modify:
host/
sw/
src/
include/

Do not modify frame/timing/fractional CFO top integration files in this step:
rtl/timing_frac_cfo_top.v
rtl/frac_cfo_frame_corrector_top.v
rtl/frac_cfo_sync_bram_test_wrapper.v

Do not modify NCO files in this step:
rtl/nco_phase_gen.v
or any future NCO replacement file

Do not run board tests.

Do not perform destructive git operations.

Do not add Xilinx FFT IP.

Do not claim production Xilinx CORDIC integration unless an actual IP is generated and verified.

## Local checks and simulation

Run:

bash scripts/run_cordic_atan2_xilinx_wrapper_sim.sh

If Vivado is not available, do not fake the result. Document simulation pending.

After running or attempting to run:

grep -R "CI GATE" -n logs build . 2>/dev/null | head -80
git status --short

## Acceptance criteria

Step 35A is complete if:

- md_files/35A_cordic_atan2_xilinx_wrapper_prompt.md exists.
- rtl/cordic_atan2_xilinx_wrapper.v exists.
- tb/cordic_atan2_xilinx_wrapper_tb.sv exists.
- scripts/run_cordic_atan2_xilinx_wrapper_sim.sh exists and is executable.
- docs/step35A_cordic_atan2_xilinx_wrapper.md exists.
- README.md is not modified.
- ai_context/current_status.md is not modified.
- Existing top integration files are not modified.
- NCO files are not modified.
- Testbench has at least 12 deterministic test groups.
- Simulation result is reported honestly.
- The distinction between simulation behavioral mode and future real Xilinx CORDIC IP is explicit.

## Final response required

After completing Step 35A, report:

Step 35A CORDIC atan2 wrapper preparation complete.

Files changed:
- ...

Main implementation:
- rtl/cordic_atan2_xilinx_wrapper.v
- tb/cordic_atan2_xilinx_wrapper_tb.sv
- scripts/run_cordic_atan2_xilinx_wrapper_sim.sh
- docs/step35A_cordic_atan2_xilinx_wrapper.md

Design decisions:
- Existing phase scaling: <describe>
- Wrapper mode: behavioral simulation / actual Xilinx IP / placeholder, specify
- Xilinx CORDIC IP generated: yes/no
- Integration into timing_frac_cfo_top: no

Simulation:
- command: bash scripts/run_cordic_atan2_xilinx_wrapper_sim.sh
- result: PASS / FAIL / pending
- CI gate: PASSED / FAILED / not run

Limitations:
- actual Xilinx CORDIC IP integration pending if not generated
- board validation not performed
- fractional CFO top integration not performed

Next recommended step:
- Step 35A-2: generate and verify actual Xilinx CORDIC IP wrapper, or integrate this wrapper into the fractional CFO path after Step 35B NCO replacement is prepared.
