# Step 35B — NCO sin/cos Replacement Preparation and Standalone Verification

## Mandatory archival rule

Before modifying any file, save this entire prompt verbatim as:

md_files/35B_nco_phase_gen_xilinx_wrapper_prompt.md

If the md_files/ directory does not exist, create it first.

## Working directory

/home/zealatan/RTL_SYNC_STEP35B

## Branch / worktree context

This worktree is dedicated to Step 35B:

branch: step35b_nco_ip
path: /home/zealatan/RTL_SYNC_STEP35B

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

This is a standalone NCO sin/cos replacement-preparation step.

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

Step 35A:
- CORDIC atan2 replacement preparation is being handled separately in the Step35A worktree.

Now Step 35B focuses only on the fractional CFO path's NCO phase/sin/cos generation replacement preparation.

## Why Step 35B is needed

The current fractional CFO correction path likely uses a behavioral NCO/sin/cos generator.

The current file is expected to be something like:

rtl/nco_phase_gen.v

It may contain simulation-only constructs such as:
- real
- $sin
- $cos
- $itor
- $rtoi

This is acceptable for simulation but not production-synthesizable FPGA RTL.

The existing comments may already say something like:
- 32-bit NCO phase accumulator with behavioral sin/cos pipeline
- Synthesis target: replace with cordic_v6_0 IP or DDS Compiler IP

Therefore Step 35B should prepare an IP-ready replacement path for NCO sin/cos generation without modifying the existing top integration yet.

## Step 35B goal

Create a standalone Xilinx-IP-compatible NCO phase/sin-cos replacement strategy and verification testbench.

This step should:

1. Inspect the existing behavioral nco_phase_gen.v.
2. Document its interface, latency, phase accumulator behavior, reset behavior, valid behavior, sin/cos scaling, and phase step convention.
3. Create a new standalone wrapper module for a future Xilinx CORDIC rotate-mode or DDS Compiler replacement.
4. Preserve the old behavioral nco_phase_gen.v unchanged unless a trivial comment-only update is needed.
5. Create a deterministic self-checking testbench comparing the wrapper behavior against a golden NCO/sin/cos model.
6. Avoid integration into complex_rotator, timing_frac_cfo_top, or frac_cfo_frame_corrector_top in this step.
7. Avoid modifying board wrapper files.
8. Avoid modifying README.md and ai_context/current_status.md in this branch to reduce merge conflicts.
9. Produce documentation explaining whether CORDIC rotate mode or DDS Compiler is the recommended production replacement.

Important:
- If actual Xilinx CORDIC or DDS IP generation is feasible in this WSL environment and consistent with existing project flow, create a TCL helper script.
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

find . -type f | grep -Ei "nco|dds|cordic|sin|cos|rotator|cfo|phase"
grep -R "module nco_phase_gen\|nco_phase\|NCO\|DDS\|sin\|cos\|\$sin\|\$cos\|phase_step\|phase_acc" -n rtl tb docs scripts 2>/dev/null
grep -R "complex_rotator\|timing_frac_cfo\|frac_cfo_frame_corrector\|frac_cfo_estimator" -n rtl tb docs scripts 2>/dev/null

Inspect at minimum if present:

rtl/nco_phase_gen.v
rtl/complex_rotator.v
rtl/timing_frac_cfo_top.v
rtl/frac_cfo_frame_corrector_top.v
tb/nco_phase_gen_tb.sv
scripts/run_nco_phase_gen_sim.sh
docs/*nco*
docs/*cordic*
docs/*frac*cfo*
docs/step13*
docs/step15*
docs/step20*

Also inspect existing script style:

find scripts -maxdepth 1 -type f -name "run_*_sim.sh" -print

## Existing behavior to preserve

Do not break existing behavioral simulation flow.

If rtl/nco_phase_gen.v currently passes an existing testbench, preserve it.

If you create a new wrapper, use a new file name such as:

rtl/nco_phase_gen_xilinx_wrapper.v

Do not replace rtl/nco_phase_gen.v inside existing tops yet.

Step 35B is standalone. Integration into the real fractional CFO path should be a later step.

## Required design decision

The wrapper should be designed around a future production replacement for the current behavioral $sin/$cos path.

Evaluate and document two possible production strategies:

Option A — Xilinx CORDIC rotate mode:
- Keep existing phase accumulator in RTL.
- Convert phase accumulator output to the phase input expected by CORDIC.
- Use CORDIC rotate mode to compute cos/sin.
- Pros: direct phase-to-sin/cos generation, configurable latency, deterministic.
- Cons: requires careful phase scaling and AXI-Stream valid alignment.

Option B — Xilinx DDS Compiler:
- Use DDS Compiler as phase accumulator + sin/cos generator.
- Configure phase increment input or programmable frequency.
- Pros: production-grade NCO, optimized sine/cosine generation.
- Cons: integration may be less transparent; dynamic phase reset/valid gating must be matched to current behavior.

Required recommendation for Step 35B:
- Prefer CORDIC rotate-mode wrapper preparation if it best matches the existing nco_phase_gen.v interface and phase accumulator behavior.
- Document DDS Compiler as an alternative if it is more appropriate after inspecting the existing module.
- Do not integrate either real IP yet unless it is actually generated and compiled successfully.

## Required wrapper file

Create:

rtl/nco_phase_gen_xilinx_wrapper.v

Recommended interface should match or closely adapt to the existing nco_phase_gen.v interface after inspection.

If the existing nco_phase_gen.v interface is different, prioritize compatibility with the existing interface.

Possible interface pattern:

module nco_phase_gen_xilinx_wrapper #(
    parameter PHASE_WIDTH = 32,
    parameter OUT_WIDTH = 16,
    parameter LATENCY = 15,
    parameter USE_BEHAVIORAL_MODEL = 1
)(
    input  wire                         aclk,
    input  wire                         aresetn,

    input  wire                         phase_reset,
    input  wire                         s_valid,
    input  wire signed [PHASE_WIDTH-1:0] phase_step,

    output reg                          m_valid,
    output reg signed [OUT_WIDTH-1:0]   cos_out,
    output reg signed [OUT_WIDTH-1:0]   sin_out,
    output reg signed [PHASE_WIDTH-1:0] phase_acc_out
);

But adapt after inspecting the actual existing module.

The wrapper should preserve these expected behaviors if present in existing nco_phase_gen.v:
- phase accumulator increments by phase_step on valid input.
- phase_reset has priority and resets phase accumulator.
- output valid is delayed by LATENCY cycles.
- sin/cos correspond to the delayed phase.
- scaling matches the existing output format.
- reset clears valid pipeline.

## Simulation model requirement

Because actual Xilinx CORDIC/DDS IP may not be available in this branch, the wrapper may include a behavioral simulation mode:

parameter USE_BEHAVIORAL_MODEL = 1

If USE_BEHAVIORAL_MODEL=1:
- Use simulation-only sin/cos logic to produce the same expected outputs as the existing behavioral nco_phase_gen.v.
- Use explicit comments:
  This branch is for simulation and IP interface preparation only.
  Production synthesis must replace this behavioral path with Xilinx CORDIC rotate-mode IP or DDS Compiler IP.

If USE_BEHAVIORAL_MODEL=0:
- Provide a clearly marked placeholder area for future Xilinx IP instantiation.
- Do not instantiate a fake module with an unsupported name unless accompanied by a clear stub and documentation.
- If creating a stub module, name it clearly as a placeholder and do not claim it is the actual Xilinx IP.

Preferred:
- Keep the wrapper shell clean and production-replaceable.
- Keep behavioral $sin/$cos code under synthesis guards if appropriate:
  synthesis translate_off / translate_on
or project-consistent simulation guard.
- Do not introduce non-synthesizable code into production RTL without clear guard/comment.

## Phase and scaling requirement

Before writing the testbench expected values, inspect the current nco_phase_gen.v phase convention.

Document the convention in comments.

Determine:
- How phase_step maps to radians or cycles.
- Whether signed or unsigned phase accumulator is used.
- Whether phase 2^PHASE_WIDTH corresponds to 2*pi.
- Whether phase accumulator wraps naturally.
- Whether cos/sin output range is signed Q1.(OUT_WIDTH-1), e.g., +/-32767 for OUT_WIDTH=16.
- Whether output at phase 0 is cos=+max, sin=0.
- Whether positive phase produces positive sin or negative sin.
- How LATENCY is applied.

Do not guess. Infer from existing code.

The wrapper and testbench must use the same convention as existing nco_phase_gen.v.

## Required testbench

Create:

tb/nco_phase_gen_xilinx_wrapper_tb.sv

The testbench should be deterministic and self-checking.

It should:
- Reset the wrapper.
- Apply known phase_step sequences.
- Apply phase_reset cases.
- Wait for delayed m_valid.
- Compare cos_out/sin_out to a golden sin/cos model within acceptable integer tolerance.
- Check latency if the wrapper promises fixed latency.
- Check valid alignment.
- Print PASS/FAIL count and CI gate line.

Required tests: at least 12 groups.

Recommended tests:

T1 reset_defaults:
- After reset, m_valid=0 and outputs are stable/zero if applicable.

T2 phase_zero:
- phase_reset then valid with phase_step=0.
- Expected phase remains zero.
- Expected cos approximately +max, sin approximately 0.

T3 quarter_cycle:
- phase corresponding to +pi/2.
- Expected cos approximately 0, sin approximately +max or according to existing convention.

T4 half_cycle:
- phase corresponding to pi.
- Expected cos approximately -max, sin approximately 0.

T5 three_quarter_cycle:
- phase corresponding to 3*pi/2 or -pi/2.
- Expected cos approximately 0, sin approximately -max.

T6 small_positive_step_sequence:
- Apply small positive phase_step over multiple valid cycles.
- Check monotonically changing phase accumulator and selected sin/cos samples.

T7 negative_step_sequence:
- Apply negative phase_step if existing interface supports signed phase_step.
- Check opposite rotation direction.

T8 wraparound_positive:
- Start near maximum phase and step forward across wrap boundary.

T9 wraparound_negative:
- Start near zero and step negative across wrap boundary if signed step supported.

T10 phase_reset_priority:
- Assert phase_reset while valid is active.
- Confirm phase accumulator and valid pipeline behavior matches specification.

T11 back_to_back_valids:
- Multiple valid inputs in consecutive cycles.
- Verify output valid order and phase sequence.

T12 valid_gating:
- Insert gaps in s_valid.
- Verify output valid only appears for accepted valid samples after latency.

T13 large_step:
- Use a large phase_step, e.g., quarter or eighth cycle per sample.

T14 optional compare_existing_model:
- If safe and no module-name conflict, instantiate existing nco_phase_gen.v and compare wrapper outputs against it.

Required final output:
PASS: <count> FAIL: <count>
CI GATE: PASSED
or
CI GATE: FAILED

## Golden model guidance

The TB golden model may use real math because it is testbench-only.

Use:
- real angle = 2*pi * phase / 2^PHASE_WIDTH
- cos = round(scale * cos(angle))
- sin = round(scale * sin(angle))
or the exact convention inferred from existing nco_phase_gen.v.

Use an integer tolerance if the existing behavioral model rounds differently:
- recommended tolerance <= 2 LSB for sin/cos comparison
- if more tolerance is needed, document why

Do not hide large numerical mismatch with a broad tolerance.

## Required simulation script

Create:

scripts/run_nco_phase_gen_xilinx_wrapper_sim.sh

Use existing project script style.

The script should:
- compile rtl/nco_phase_gen_xilinx_wrapper.v
- compile tb/nco_phase_gen_xilinx_wrapper_tb.sv
- run xsim
- save logs according to project convention
- grep for FAIL/FATAL/CI GATE failure
- exit nonzero on failure
- be executable

If there is an existing rtl/nco_phase_gen.v and existing TB, do not delete them.

Optionally compile rtl/nco_phase_gen.v for comparison only if no duplicate module conflicts occur.

## Optional TCL helper

If useful, create one of:

scripts/create_cordic_sincos_ip.tcl
or
scripts/create_dds_nco_ip.tcl

Purpose:
- Future helper to create Xilinx CORDIC rotate-mode or DDS Compiler IP in Vivado.
- Clearly mark it as preliminary unless verified.
- It should not be required by Step 35B simulation.

If exact IP property names are uncertain:
- include comments and TODOs
- do not claim the TCL is production-ready
- do not make simulation depend on it

## Documentation update

Create:

docs/step35B_nco_phase_gen_xilinx_wrapper.md

Include:

# Step 35B — NCO sin/cos Replacement Preparation

Sections:
- Objective
- Why this step is needed
- Existing behavioral nco_phase_gen status
- Existing interface and phase scaling
- Existing latency and valid behavior
- Production replacement options
- Recommended replacement strategy
- Wrapper interface
- Simulation behavior
- Intended future Xilinx CORDIC/DDS IP configuration
- Testbench scenarios
- Simulation command
- Simulation result
- Known limitations
- Next steps

Known limitations must include:
- Actual Xilinx CORDIC/DDS IP XCI is not integrated unless this step truly generates and verifies it.
- Current wrapper may still use behavioral sin/cos for simulation.
- Integration into timing_frac_cfo_top or frac_cfo_frame_corrector_top is not done in Step 35B.
- Board validation is not part of Step 35B.

## Do not modify shared status files in this branch

To avoid merge conflicts with Step 35A and the main Step 34 lane, do not modify:

README.md
ai_context/current_status.md

Instead, put all Step 35B status in:

docs/step35B_nco_phase_gen_xilinx_wrapper.md

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

Do not modify CORDIC atan2 files in this step:
rtl/cordic_atan2.v
rtl/cordic_atan2_xilinx_wrapper.v if present

Do not modify existing rtl/nco_phase_gen.v unless only a trivial comment-only update is absolutely necessary.

Do not run board tests.

Do not perform destructive git operations.

Do not add Xilinx FFT IP.

Do not claim production Xilinx CORDIC/DDS integration unless an actual IP is generated and verified.

## Local checks and simulation

Run:

bash scripts/run_nco_phase_gen_xilinx_wrapper_sim.sh

If Vivado is not available, do not fake the result. Document simulation pending.

After running or attempting to run:

grep -R "CI GATE" -n logs build . 2>/dev/null | head -80
git status --short

## Acceptance criteria

Step 35B is complete if:

- md_files/35B_nco_phase_gen_xilinx_wrapper_prompt.md exists.
- rtl/nco_phase_gen_xilinx_wrapper.v exists.
- tb/nco_phase_gen_xilinx_wrapper_tb.sv exists.
- scripts/run_nco_phase_gen_xilinx_wrapper_sim.sh exists and is executable.
- docs/step35B_nco_phase_gen_xilinx_wrapper.md exists.
- README.md is not modified.
- ai_context/current_status.md is not modified.
- Existing top integration files are not modified.
- CORDIC atan2 files are not modified.
- Existing nco_phase_gen.v is preserved unless comment-only update is necessary.
- Testbench has at least 12 deterministic test groups.
- Simulation result is reported honestly.
- The distinction between simulation behavioral mode and future real Xilinx CORDIC/DDS IP is explicit.

## Final response required

After completing Step 35B, report:

Step 35B NCO sin/cos wrapper preparation complete.

Files changed:
- ...

Main implementation:
- rtl/nco_phase_gen_xilinx_wrapper.v
- tb/nco_phase_gen_xilinx_wrapper_tb.sv
- scripts/run_nco_phase_gen_xilinx_wrapper_sim.sh
- docs/step35B_nco_phase_gen_xilinx_wrapper.md

Design decisions:
- Existing phase convention: <describe>
- Existing sin/cos scaling: <describe>
- Existing latency/valid behavior: <describe>
- Recommended production replacement: CORDIC rotate mode / DDS Compiler / other, specify
- Wrapper mode: behavioral simulation / actual Xilinx IP / placeholder, specify
- Xilinx IP generated: yes/no
- Integration into fractional CFO top: no

Simulation:
- command: bash scripts/run_nco_phase_gen_xilinx_wrapper_sim.sh
- result: PASS / FAIL / pending
- CI gate: PASSED / FAILED / not run

Limitations:
- actual Xilinx CORDIC/DDS IP integration pending if not generated
- board validation not performed
- fractional CFO top integration not performed

Next recommended step:
- Step 35B-2: generate and verify actual Xilinx CORDIC rotate or DDS IP wrapper, or integrate this wrapper into the fractional CFO path after Step 35A CORDIC atan2 preparation is also complete.
