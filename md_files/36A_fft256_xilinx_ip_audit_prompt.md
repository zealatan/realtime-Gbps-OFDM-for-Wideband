# Step 36A — Xilinx FFT256 IP Generation and Interface Audit

## Mandatory archival rule

Before modifying any file, save this entire prompt verbatim as:

md_files/36A_fft256_xilinx_ip_audit_prompt.md

If the md_files/ directory does not exist, create it first.

## Working directory

/home/zealatan/RTL_SYNC_STEP36A_FFTIP

## Branch / worktree context

This worktree is dedicated to Step 36A:

branch: step36a_fft256_ip_audit
path: /home/zealatan/RTL_SYNC_STEP36A_FFTIP

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
- Do not integrate FFT IP into the full receiver yet.

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

Step 30:
- Meyr-based integer CFO / PSS-SSS architecture specified.
- Correct C-reference formulas:
  term1[j] = PSS_FFT[j] * conj(SSS_FFT[j])
  term2[j] = mU[j + CP_LEN] * conj(goldU[j + CP_LEN])
  intCFO = peakIndexMeyr - 255

Step 31:
- Meyr direct-correlation core passed.
- PASS: 32, FAIL: 0, CI GATE: PASSED.

Step 32:
- Meyr PSS/SSS product generator and frequency-domain estimator top passed.
- Product generator PASS: 13, FAIL: 0.
- Estimator top PASS: 32, FAIL: 0.

Step 33:
- real mU/goldU audit completed.
- real mU/goldU-derived term2 ROM remains pending because source arrays are external.

Step 34:
- FFT256 frontend behavioral/bypass integration with Meyr estimator passed.
- PASS: 31, FAIL: 0, CI GATE: PASSED.
- No Xilinx FFT IP was used.
- Production FFT remains pending.

Step 35A:
- CORDIC atan2 wrapper preparation passed.
- PASS: 35, FAIL: 0.
- Actual Xilinx CORDIC XCI generation pending.

Step 35B:
- NCO sin/cos wrapper preparation passed.
- PASS: 88, FAIL: 0.
- Actual Xilinx CORDIC/DDS XCI generation pending.

Step 36A now focuses only on the Xilinx FFT256 IP generation and interface audit.

## Why Step 36A is needed

The Meyr integer CFO path requires PSS/SSS FFT outputs.

Step 34 verified a behavioral/frontend path, but it did not add production FFT RTL/IP.

The current biggest production missing block is:

FFT256 frontend

Before integrating FFT into the Meyr estimator or corrected-frame path, we must audit the actual Xilinx FFT IP:

- Can Vivado 2022.2 create the IP?
- What is the exact AXI-Stream interface?
- What is the config channel format?
- What are the output data widths?
- What is the output bin order?
- How is scaling configured?
- What are the event/status signals?
- What latency behavior should the wrapper expect?
- What files should be committed: Tcl only, XCI, wrapper, or all?

## Step 36A goal

Create scripts and documentation for Xilinx FFT256 IP generation and interface audit.

This step should:

1. Inspect the existing Step 34 FFT frontend files and documentation.
2. Create a Vivado Tcl script to generate or probe a Xilinx FFT256 IP.
3. Create an IP property probe Tcl script if useful.
4. Create a preliminary wrapper RTL skeleton for the future Xilinx FFT256 IP.
5. Create documentation describing the intended IP configuration and audit procedure.
6. Optionally create a lightweight testbench scaffold, but do not require actual generated IP to be present.
7. Do not integrate the FFT IP into the full receiver yet.
8. Do not modify README.md or ai_context/current_status.md in this branch to avoid merge conflicts.
9. Be honest about whether actual IP generation was run or only prepared.

## Files to inspect first

Inspect these files before editing:

rtl/fft256_dual_symbol_frontend.v
rtl/meyr_integer_cfo_fft_frontend_top.v
tb/fft256_behavioral_model.sv
tb/meyr_integer_cfo_fft_frontend_top_tb.sv
scripts/run_meyr_integer_cfo_fft_frontend_top_sim.sh
docs/step34_fft256_frontend_behavioral_integration.md
docs/step30_meyr_integer_cfo_pss_sss_architecture.md
docs/step32_meyr_product_generator_real_term2.md
docs/step33_real_mU_goldU_term2_reference_audit.md

Also inspect current script conventions:

find scripts -maxdepth 1 -type f -name "*.tcl" -print
find scripts -maxdepth 1 -type f -name "run_*_sim.sh" -print
find rtl -maxdepth 1 -type f | grep -Ei "fft|meyr|cfo|frontend"
find tb -maxdepth 1 -type f | grep -Ei "fft|meyr|cfo|frontend"

Search for previous FFT/IP references:

grep -R "FFT\|fft\|xfft\|XFFT\|create_ip\|xilinx.com:ip:xfft\|s_axis_config\|m_axis_data\|event_tlast" -n rtl tb docs scripts 2>/dev/null | head -300

## Do not modify shared status files

To avoid merge conflicts with other Step 36 worktrees, do not modify:

README.md
ai_context/current_status.md

All Step 36A status should go into:

docs/step36A_fft256_xilinx_ip_audit.md

The main branch can later update README/current_status once Step 36A/36B/36C are merged.

## Required script: create FFT256 IP Tcl

Create:

scripts/create_fft256_ip.tcl

Purpose:
- Create a Xilinx FFT IP configured for a 256-point forward FFT suitable for PSS/SSS symbols.
- Target Vivado 2022.2.
- The script should be safe to run in a fresh Vivado project.
- It should create the IP under a project-local ip directory if possible.

Important:
- Do not invent unverified property names as guaranteed facts.
- Use report_property or a probe flow to discover properties.
- If exact CONFIG property names are uncertain, create a two-stage script:
  1. create/probe IP
  2. apply known or tentative properties with comments/TODOs

Recommended Tcl structure:

- Determine script directory and repository root.
- Create ip/fft256_xilinx or ip/xfft_256 directory.
- create_ip -name xfft -vendor xilinx.com -library ip -module_name fft256_xilinx
- report_property [get_ips fft256_xilinx] to a log file
- Set target properties if known:
  - transform length = 256
  - forward transform
  - AXI-Stream interface
  - natural order output if available
  - fixed-point input/output
  - input width around 16 bits initially
  - phase factor width documented
  - scaling schedule documented
- generate_target all [get_ips fft256_xilinx]
- export generated instantiation template if possible

If property names are uncertain:
- Mark the script as preliminary.
- Make sure it still helps the user discover valid property names.

## Required script: probe FFT IP properties

Create:

scripts/probe_fft256_ip_properties.tcl

Purpose:
- Create or open a temporary FFT IP and dump all available properties to a readable report.
- This script is for Windows Vivado/manual audit if WSL cannot generate IP.
- It should write reports to a clear location such as:
  reports/fft256_ip_properties.txt
  reports/fft256_ip_config_summary.txt

The report should help identify:
- transform length property name
- data width property name
- phase factor width property name
- output ordering property name
- scaling option property name
- architecture option
- throttle/backpressure option
- AXI config/status/event ports

If exact report commands differ, use robust Vivado Tcl commands and comments.

## Required wrapper RTL skeleton

Create:

rtl/fft256_xilinx_wrapper.v

Purpose:
- Provide a project-local wrapper around the future Xilinx FFT IP.
- Hide vendor IP details from the rest of RTL_SYNC.
- Establish the interface expected by future Step 37.

Do not instantiate a fake production FFT.

Recommended interface:

module fft256_xilinx_wrapper #(
    parameter FFT_LEN = 256,
    parameter IQ_WIDTH = 16,
    parameter FFT_OUT_WIDTH = 16,
    parameter USE_BEHAVIORAL_STUB = 1
)(
    input  wire                         aclk,
    input  wire                         aresetn,

    input  wire                         start,

    input  wire                         s_axis_tvalid,
    output wire                         s_axis_tready,
    input  wire [2*IQ_WIDTH-1:0]         s_axis_tdata,
    input  wire                         s_axis_tlast,

    output wire                         m_axis_tvalid,
    input  wire                         m_axis_tready,
    output wire [2*FFT_OUT_WIDTH-1:0]    m_axis_tdata,
    output wire                         m_axis_tlast,

    output wire                         busy,
    output wire                         done,
    output wire                         error,

    output wire                         event_frame_started,
    output wire                         event_tlast_unexpected,
    output wire                         event_tlast_missing,
    output wire                         event_data_in_channel_halt,
    output wire                         event_data_out_channel_halt,
    output wire                         event_status_channel_halt
);

If this differs from existing Step 34 frontend style, document the mapping.

Behavior:
- USE_BEHAVIORAL_STUB=1 may pass through input to output or provide a simple placeholder for compile-only.
- The stub must not be claimed as FFT.
- USE_BEHAVIORAL_STUB=0 should contain a clearly marked TODO instantiation block for the generated Xilinx FFT IP.
- Include comments indicating expected Xilinx IP ports, but do not instantiate a non-existent module unless guarded or documented.
- Keep this wrapper synthesizable in stub mode.

Important:
- This wrapper is not a production FFT until actual XCI/IP is generated and instantiated.
- Do not connect this wrapper to Meyr estimator in this step.

## Optional compile-only testbench

Create if useful:

tb/fft256_xilinx_wrapper_stub_tb.sv

Purpose:
- Verify the wrapper stub compiles and has basic valid/tlast behavior.
- It is not an FFT correctness test.
- It should clearly print that USE_BEHAVIORAL_STUB=1 is only a placeholder.

If created, also create:

scripts/run_fft256_xilinx_wrapper_stub_sim.sh

The test should not claim FFT correctness.

Minimum checks:
- reset behavior
- ready/valid passthrough or stub behavior
- tlast propagation if applicable
- event outputs are zero in stub mode
- CI GATE line

If this is too much for Step 36A, skip the testbench and focus on Tcl/docs/wrapper.

## Required documentation

Create:

docs/step36A_fft256_xilinx_ip_audit.md

The document must include:

# Step 36A — Xilinx FFT256 IP Generation and Interface Audit

Sections:
- Objective
- Relationship to Step 34
- Why production FFT IP is needed
- Current Step 34 behavioral/frontend limitation
- Proposed Xilinx FFT256 IP role
- Intended FFT configuration
- Tcl scripts created
- Expected Xilinx FFT AXI-Stream interface
- Configuration channel notes
- Output bin order audit plan
- Scaling and width audit plan
- Latency and event signal audit plan
- Wrapper interface
- What was run in WSL
- What must be run in Windows Vivado
- Files expected from actual IP generation
- What should be committed to git
- Known limitations
- Next steps

Known limitations must include:
- Actual Xilinx FFT XCI may not be generated in this WSL step.
- Property names may require Vivado report_property confirmation.
- No full receiver integration in Step 36A.
- No board validation in Step 36A.
- Step 34 behavioral FFT/bypass remains the verified simulation path until actual IP is generated and integrated.

## Intended FFT configuration to document

Document the target, even if exact Tcl properties are pending:

- FFT length: 256
- Transform: forward FFT
- Input: complex signed fixed-point, initially 16-bit I and 16-bit Q
- Output: complex signed fixed-point, width to be confirmed
- Interface: AXI-Stream
- Output order: natural order preferred
- Scaling: conservative/scaled mode preferred initially to avoid overflow
- Config channel: must be driven deterministically by wrapper or static config logic
- TLAST: asserted on sample 255 for input frame
- Output TLAST: expected on bin 255
- Bin convention:
  k=0 DC
  k=1..127 positive frequencies
  k=128..255 negative frequencies
  no fftshift
- Audit test required later:
  single-bin tone at k=5 -> peak at output bin 5
  single-bin tone at k=-4 -> peak at output bin 252

## Required Windows Vivado instructions

In the documentation, include a section for the user:

To run on Windows Vivado:

1. Open Vivado 2022.2.
2. Source the Tcl script:
   source scripts/probe_fft256_ip_properties.tcl
3. Inspect generated reports under reports/.
4. If properties are correct, run:
   source scripts/create_fft256_ip.tcl
5. Confirm .xci was generated.
6. Copy/save:
   - ip/fft256_xilinx/*.xci
   - generated instantiation template or port list
   - reports/fft256_ip_properties.txt
   - reports/fft256_ip_generation.log
7. Report any errors back into the project.

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
rtl/frac_cfo_sync_bram_test_wrapper.v
rtl/meyr_integer_cfo_fft_frontend_top.v
rtl/fft256_dual_symbol_frontend.v

Do not modify Step 31/32/34 verified modules unless absolutely necessary.

Do not modify CORDIC/NCO files in this Step 36A lane.

Do not run board tests.

Do not perform destructive git operations.

Do not claim actual Xilinx FFT IP integration unless actual XCI/IP output exists and was verified.

## Local checks

Run:

git status --short

If a stub testbench/script is created and Vivado is available:

export PATH="/home/zealatan/Downloads/Vivado/2022.2/bin:$PATH"
bash scripts/run_fft256_xilinx_wrapper_stub_sim.sh

If Vivado is unavailable, do not fake the result. Document pending.

Check:

git status --short

## Acceptance criteria

Step 36A is complete if:

- md_files/36A_fft256_xilinx_ip_audit_prompt.md exists.
- scripts/create_fft256_ip.tcl exists.
- scripts/probe_fft256_ip_properties.tcl exists.
- rtl/fft256_xilinx_wrapper.v exists.
- docs/step36A_fft256_xilinx_ip_audit.md exists.
- README.md is not modified.
- ai_context/current_status.md is not modified.
- Existing top integration files are not modified.
- No board/Vitis files are modified.
- The distinction between wrapper/stub, Tcl preparation, and actual generated Xilinx IP is explicit.
- Final report honestly states whether actual IP generation was run or pending.

Optional complete criteria:
- tb/fft256_xilinx_wrapper_stub_tb.sv exists.
- scripts/run_fft256_xilinx_wrapper_stub_sim.sh exists.
- stub simulation passes.

## Final response required

After completing Step 36A, report:

Step 36A FFT256 Xilinx IP audit preparation complete.

Files changed:
- ...

Main implementation:
- scripts/create_fft256_ip.tcl
- scripts/probe_fft256_ip_properties.tcl
- rtl/fft256_xilinx_wrapper.v
- docs/step36A_fft256_xilinx_ip_audit.md
- optional stub TB/script if created

Vivado/IP status:
- actual Xilinx FFT XCI generated: yes/no
- if no: pending Windows Vivado execution
- Tcl property confidence: verified / preliminary / requires report_property confirmation

Wrapper status:
- USE_BEHAVIORAL_STUB mode: yes/no
- production FFT instantiated: yes/no
- full receiver integration: no

Simulation:
- stub simulation command if any
- result: PASS / FAIL / not run

Limitations:
- actual FFT IP XCI pending unless generated
- bin order/scaling must be confirmed with actual IP
- board validation not performed

Next recommended step:
- Run scripts/probe_fft256_ip_properties.tcl and scripts/create_fft256_ip.tcl in Windows Vivado, then proceed to Step 37 — Xilinx FFT256 standalone wrapper simulation with actual generated IP.
