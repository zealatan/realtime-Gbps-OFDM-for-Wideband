# Step 36B — CORDIC/NCO Xilinx IP Generation and Interface Audit

## Mandatory archival rule

Before modifying any file, save this entire prompt verbatim as:

md_files/36B_cordic_nco_xilinx_ip_audit_prompt.md

If the md_files/ directory does not exist, create it first.

## Working directory

/home/zealatan/RTL_SYNC_STEP36B_CORDICIP

## Branch / worktree context

This worktree is dedicated to Step 36B:

branch: step36b_cordic_nco_ip_audit
path: /home/zealatan/RTL_SYNC_STEP36B_CORDICIP

The main repository remains at:

/home/zealatan/RTL_SYNC

Do not modify the main worktree from this session.

## Important workflow separation

This project uses a split workflow:

WSL/Linux side:
- Claude Code works here.
- Source/documentation editing is done here.
- Tcl/script/documentation preparation is done here.
- Lightweight simulation may be run here if it does not require generated Xilinx IP artifacts.

Windows side:
- The user manually runs Vivado/Vitis when needed.
- The user manually generates actual Xilinx IP XCI/output products if WSL licensing/project flow is not suitable.
- The user manually programs the ZCU102 board later.
- The user manually runs UART/COM tests later.

For this step:
- Do not run Vitis.
- Do not access COM5.
- Do not modify board/Vitis host files.
- Do not claim any board result.
- Do not modify existing top integration files.
- Do not integrate CORDIC/NCO IP into the fractional CFO path yet.

This is an IP generation/interface audit step, not a full integration step.

## Critical output rule

Do not print long source files into the chat.

Create or edit files directly in the filesystem.

At the end, report only:
- files changed
- scripts created
- whether Vivado IP generation was run or only prepared
- PASS/FAIL/pending
- next step

## Context

The RTL_SYNC project currently has:

Step 29I:
- ZCU102 board regression PASS / CLOSED.
- AXI-Lite, BRAM source, stream handshake, frame detector, corrected output BRAM, and PS readback path validated.

Step 34:
- FFT256 frontend behavioral/bypass integration with Meyr estimator passed.
- PASS: 31, FAIL: 0, CI GATE: PASSED.
- No Xilinx FFT IP was used.
- Production FFT remains pending.

Step 35A:
- CORDIC atan2 wrapper preparation passed.
- PASS: 35, FAIL: 0, CI GATE: PASSED.
- Existing cordic_atan2.v was found to be synthesizable CORDIC RTL, not a pure $atan2 behavioral-only block.
- rtl/cordic_atan2_xilinx_wrapper.v was created as a future Xilinx CORDIC replacement wrapper.
- scripts/create_cordic_atan2_ip.tcl was created as a preliminary Tcl skeleton.
- Actual Xilinx CORDIC XCI generation remains pending.
- Integration into frac_cfo_estimator/timing path was not performed.

Step 35B:
- NCO sin/cos wrapper preparation passed.
- PASS: 88, FAIL: 0, CI GATE: PASSED.
- Existing NCO convention was captured:
  - 32-bit unsigned phase accumulator
  - full 2π corresponds to 2^32 accumulator wrap
  - legacy sin/cos generation uses phase_acc[31:24] as a 256-entry ROM index
  - Q1.15-style sin/cos outputs
  - positive rotation gives positive sin
- rtl/nco_phase_gen_xilinx_wrapper.v was created as a future CORDIC rotate-mode or DDS replacement wrapper.
- scripts/create_cordic_sincos_ip.tcl was created as a preliminary Tcl skeleton.
- Actual Xilinx CORDIC/DDS XCI generation remains pending.
- Integration into fractional CFO top was not performed.

Step 36B now focuses only on Xilinx IP generation/interface audit for:
1. CORDIC atan2/vectoring/translate mode replacement candidate.
2. CORDIC rotate-mode sin/cos or DDS Compiler replacement candidate for NCO.

## Why Step 36B is needed

The wrapper-preparation steps passed, but actual Xilinx IP was not generated.

Before replacing existing fractional CFO blocks, we must audit the actual Xilinx IP interfaces:

For CORDIC atan2:
- Can Vivado 2022.2 create the required CORDIC IP?
- What is the exact AXI-Stream input/output interface?
- What is the output phase format?
- Can the output scaling match existing PHASE_WIDTH=16 convention?
- What latency is produced?
- What reset/valid behavior should the wrapper handle?

For NCO sin/cos:
- Should production use CORDIC rotate mode or DDS Compiler?
- Can Vivado create the selected IP?
- What phase input format is expected?
- Can legacy phase_acc[31:24] ROM behavior be preserved, or will production mode use higher resolution?
- What latency and valid behavior are required?
- What port list will the wrapper need?

Step 36B should prepare and document these answers without modifying the production top path.

## Step 36B goal

Create scripts and documentation for CORDIC/NCO Xilinx IP generation and interface audit.

This step should:

1. Inspect Step 35A and Step 35B wrapper/docs/Tcl files.
2. Improve or add Tcl scripts to probe Xilinx CORDIC and DDS IP properties.
3. Create Tcl scripts for actual IP generation if property names are known or can be discovered.
4. Create documentation describing the intended IP configurations and audit procedures.
5. Optionally create lightweight compile-only stub wrappers or interface notes, but do not integrate into fractional CFO top.
6. Do not modify README.md or ai_context/current_status.md in this branch to avoid merge conflicts.
7. Be honest about whether actual IP generation was run or only prepared.

## Files to inspect first

Inspect these files before editing:

rtl/cordic_atan2_xilinx_wrapper.v
rtl/nco_phase_gen_xilinx_wrapper.v
docs/step35A_cordic_atan2_xilinx_wrapper.md
docs/step35B_nco_phase_gen_xilinx_wrapper.md
scripts/create_cordic_atan2_ip.tcl
scripts/create_cordic_sincos_ip.tcl
tb/cordic_atan2_xilinx_wrapper_tb.sv
tb/nco_phase_gen_xilinx_wrapper_tb.sv
rtl/cordic_atan2.v
rtl/nco_phase_gen.v

Also inspect script conventions:

find scripts -maxdepth 1 -type f -name "*.tcl" -print
find scripts -maxdepth 1 -type f -name "run_*_sim.sh" -print

Search for CORDIC/DDS/IP references:

grep -R "CORDIC\|cordic\|DDS\|dds\|create_ip\|cordic_v6_0\|dds_compiler\|Functional_Selection\|Translate\|Rotate\|AXIS\|s_axis" -n rtl tb docs scripts 2>/dev/null | head -300

## Do not modify shared status files

To avoid merge conflicts with other Step 36 worktrees, do not modify:

README.md
ai_context/current_status.md

All Step 36B status should go into:

docs/step36B_cordic_nco_xilinx_ip_audit.md

The main branch can later update README/current_status once Step 36A/36B/36C are merged.

## Required script: probe CORDIC IP properties

Create:

scripts/probe_cordic_ip_properties.tcl

Purpose:
- Create or open temporary Xilinx CORDIC IP instances and dump all available properties.
- One probe should target atan2/vectoring/translate style CORDIC.
- One probe should target rotate-mode CORDIC for sin/cos generation.
- Write reports to a clear location such as:
  reports/cordic_ip_properties.txt
  reports/cordic_atan2_property_probe.txt
  reports/cordic_rotate_property_probe.txt

The report should help identify:
- function selection property name
- input width property name
- output width property name
- phase format property name
- latency/control property name
- AXI-Stream interface ports
- cartesian/polar input/output mapping
- reset/aclken availability
- data format/scaling options

If exact property names differ by Vivado version, this probe script should still help discover them.

## Required script: create CORDIC atan2 IP Tcl

Update or create:

scripts/create_cordic_atan2_ip.tcl

Purpose:
- Create a Xilinx CORDIC IP candidate for atan2/phase extraction.
- Target Vivado 2022.2.
- Use a project-local ip directory if possible:
  ip/cordic_atan2_xilinx/
- Generate reports under:
  reports/cordic_atan2_ip_generation.log
  reports/cordic_atan2_ip_properties.txt

Target behavior:
- Function: atan2 equivalent, vectoring/translate mode as appropriate.
- Input: signed Cartesian x/y.
- Output: signed phase.
- Phase width: should be compatible with PHASE_WIDTH=16.
- Latency: should be controlled or documented; target around existing LATENCY=15 if possible.
- AXI-Stream interface.

Important:
- Do not invent unverified property names as guaranteed facts.
- If exact property names are uncertain, mark the script as preliminary and rely on probe_cordic_ip_properties.tcl.
- The script may include TODO comments for properties requiring confirmation.

## Required script: create CORDIC sin/cos IP Tcl

Update or create:

scripts/create_cordic_sincos_ip.tcl

Purpose:
- Create a Xilinx CORDIC rotate-mode IP candidate for sin/cos generation.
- Target Vivado 2022.2.
- Use a project-local ip directory if possible:
  ip/cordic_sincos_xilinx/
- Generate reports under:
  reports/cordic_sincos_ip_generation.log
  reports/cordic_sincos_ip_properties.txt

Target behavior:
- Existing RTL phase accumulator remains outside the IP.
- Phase input feeds CORDIC rotate-mode phase port.
- Output should provide cos and sin.
- Phase width should be compatible with 16-bit phase input candidate, likely phase_acc[31:16] or legacy-compatible phase_acc[31:24] expanded to 16 bits.
- Output width should be compatible with 16-bit Q1.15 sin/cos.
- Latency should be documented.
- AXI-Stream interface.

Important:
- The legacy NCO currently uses phase_acc[31:24] ROM indexing.
- Production CORDIC rotate mode may provide higher phase resolution.
- The documentation must clearly distinguish:
  - legacy-compatible behavior
  - high-resolution CORDIC behavior

## Optional script: probe DDS Compiler IP properties

Create if useful:

scripts/probe_dds_ip_properties.tcl

Purpose:
- Determine whether DDS Compiler is a better production replacement for nco_phase_gen.
- Dump available DDS IP properties under reports/.
- Do not force DDS integration unless clear.

Create if useful:

scripts/create_dds_nco_ip.tcl

Purpose:
- Preliminary DDS Compiler IP creation helper.
- Mark as optional/preliminary unless verified.

Important:
- DDS may own the phase accumulator internally, which may conflict with existing phase_reset/valid semantics.
- If DDS is less compatible with the existing design, document that CORDIC rotate mode is preferred for now.

## Required documentation

Create:

docs/step36B_cordic_nco_xilinx_ip_audit.md

The document must include:

# Step 36B — CORDIC/NCO Xilinx IP Generation and Interface Audit

Sections:
- Objective
- Relationship to Steps 35A and 35B
- Existing atan2 implementation status
- Existing NCO implementation status
- Why Xilinx IP audit is still useful
- CORDIC atan2 target configuration
- CORDIC rotate-mode sin/cos target configuration
- DDS Compiler alternative analysis
- Tcl scripts created/updated
- Expected AXI-Stream interfaces
- Phase scaling and compatibility risks
- Latency and valid alignment risks
- What was run in WSL
- What must be run in Windows Vivado
- Files expected from actual IP generation
- What should be committed to git
- Known limitations
- Next steps

Known limitations must include:
- Actual Xilinx CORDIC/DDS XCI may not be generated in this WSL step.
- Property names may require Vivado report_property confirmation.
- No integration into frac_cfo_estimator/timing path in Step 36B.
- No board validation in Step 36B.
- Existing synthesizable atan2 RTL and legacy NCO wrapper remain the verified paths until actual IP is generated and integrated.

## Important design notes to document

### atan2 path

Existing phase scaling from Step 35A:

phase = atan2(Q, I) / pi * 32767
signed 16-bit
pi maps approximately to +32767

Document that the future Xilinx CORDIC atan2 output scaling must be matched or converted.

### NCO path

Existing phase convention from Step 35B:

- 32-bit unsigned accumulator.
- 2π corresponds to 2^32 wrap.
- legacy sin/cos uses phase_acc[31:24] as 256-entry ROM index.
- Q1.15-like output.
- phase_reset clears accumulator and blocks pipeline entry.
- positive rotation gives positive sin.

Document that future CORDIC rotate-mode replacement has two modes:

Mode A — legacy-compatible:
- Use phase_acc[31:24] as the effective phase.
- Match 256-entry ROM behavior as closely as possible.
- Best for bit-exact regression.

Mode B — high-resolution:
- Use phase_acc[31:16] or more bits into CORDIC.
- Better spectral/phase quality.
- Not bit-exact to legacy ROM.
- Requires updated regression tolerances and possibly different expected outputs.

Recommended for first integration:
- legacy-compatible mode first
- high-resolution mode later as an improvement

## Required Windows Vivado instructions

In the documentation, include a section for the user:

To run on Windows Vivado:

1. Open Vivado 2022.2.
2. Source:
   source scripts/probe_cordic_ip_properties.tcl
3. Inspect generated reports under reports/.
4. Then run:
   source scripts/create_cordic_atan2_ip.tcl
   source scripts/create_cordic_sincos_ip.tcl
5. If DDS is being evaluated:
   source scripts/probe_dds_ip_properties.tcl
   source scripts/create_dds_nco_ip.tcl
6. Confirm .xci files were generated.
7. Save/copy:
   - ip/cordic_atan2_xilinx/*.xci
   - ip/cordic_sincos_xilinx/*.xci
   - optional ip/dds_nco_xilinx/*.xci
   - reports/*cordic*
   - reports/*dds*
   - generated instantiation templates or port lists
8. Report errors or property mismatches back into the project.

Do not claim these have been run unless actually run.

## Do not modify

Do not modify:
README.md
ai_context/current_status.md
host/
sw/
src/
include/

Do not modify:
rtl/frac_cfo_frame_corrector_top.v
rtl/timing_frac_cfo_top.v
rtl/frac_cfo_estimator.v
rtl/frac_cfo_sync_bram_test_wrapper.v

Do not modify FFT/Meyr files in this Step 36B lane.

Do not modify existing verified wrapper RTL unless only comment-level or script-path updates are necessary:
rtl/cordic_atan2_xilinx_wrapper.v
rtl/nco_phase_gen_xilinx_wrapper.v

Do not run board tests.

Do not perform destructive git operations.

Do not claim actual Xilinx CORDIC/DDS IP integration unless actual XCI/IP output exists and was verified.

## Local checks

Run:

git status --short

If Vivado Tcl can be tested lightly without requiring license/project side effects, it is acceptable to check Tcl syntax or run property probes. If not, document Windows Vivado pending.

If WSL Vivado is available and you choose to run a probe, make sure not to pollute the repository with generated build artifacts unless intended. Do not commit large generated files.

After checks:

git status --short

## Acceptance criteria

Step 36B is complete if:

- md_files/36B_cordic_nco_xilinx_ip_audit_prompt.md exists.
- scripts/probe_cordic_ip_properties.tcl exists.
- scripts/create_cordic_atan2_ip.tcl exists and is updated/improved.
- scripts/create_cordic_sincos_ip.tcl exists and is updated/improved.
- Optional DDS scripts are created only if useful and clearly marked.
- docs/step36B_cordic_nco_xilinx_ip_audit.md exists.
- README.md is not modified.
- ai_context/current_status.md is not modified.
- Existing top integration files are not modified.
- No board/Vitis files are modified.
- The distinction between Tcl preparation, actual XCI generation, wrapper preparation, and top-level integration is explicit.
- Final report honestly states whether actual IP generation was run or pending.

## Final response required

After completing Step 36B, report:

Step 36B CORDIC/NCO Xilinx IP audit preparation complete.

Files changed:
- ...

Main implementation:
- scripts/probe_cordic_ip_properties.tcl
- scripts/create_cordic_atan2_ip.tcl
- scripts/create_cordic_sincos_ip.tcl
- optional DDS scripts if created
- docs/step36B_cordic_nco_xilinx_ip_audit.md

Vivado/IP status:
- actual CORDIC atan2 XCI generated: yes/no
- actual CORDIC sincos XCI generated: yes/no
- actual DDS XCI generated: yes/no/not evaluated
- if no: pending Windows Vivado execution
- Tcl property confidence: verified / preliminary / requires report_property confirmation

Design decisions:
- atan2 path: existing synthesizable RTL remains verified fallback
- NCO path: legacy-compatible CORDIC rotate mode preferred first / DDS alternative documented
- fractional CFO top integration: no

Limitations:
- actual XCI generation pending unless generated
- phase scaling must be confirmed with actual IP
- latency/valid behavior must be confirmed with actual IP
- board validation not performed

Next recommended step:
- Run property probe and create scripts in Windows Vivado, then proceed to actual IP wrapper simulation or keep existing synthesizable RTL/legacy NCO as fallback while moving to FFT integration.
