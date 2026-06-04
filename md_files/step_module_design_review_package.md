You are Claude Code working inside:

/home/zealatan/RTL_SYNC_PHASE4

Your mission is to create a professional module-level documentation package that can serve as:
1. RTL Design Review Package
2. FPGA Bring-Up Manual
3. Verification Closure Report
4. Handoff documentation for future engineers
5. Portfolio-quality engineering artifact

This is a documentation task.
Do NOT modify RTL files.
Do NOT modify testbenches.
Do NOT modify vectors/golden files.
Only inspect source files and generate documentation.

Mandatory archival rule:

Before doing anything else, save this exact prompt as:

/home/zealatan/RTL_SYNC_PHASE4/md_files/step_module_design_review_package.md

Execution rule:

Do NOT ask me yes/no questions.
Do NOT pause for confirmation.
Do NOT ask whether to continue.
Do NOT stop after generating only one document.
Continue until the complete module-level documentation package is generated, linked, and summarized.

Target output directory:

/home/zealatan/RTL_SYNC_PHASE4/docs/modules/

Overwrite existing files if present. The existing 12-section versions will be replaced with 18-section versions.

Create this index file:

/home/zealatan/RTL_SYNC_PHASE4/docs/modules/index.html

Create detailed HTML documents for these modules:

1. phase3_sync_axis_dma_wrapper   → 01_phase3_sync_axis_dma_wrapper.html
2. phase3_sync_top                → 02_phase3_sync_top.html
3. frac_cfo_frame_corrector_top   → 03_frac_cfo_frame_corrector_top.html
4. pss_sss_symbol_extractor       → 04_pss_sss_symbol_extractor.html
5. fft256_dual_symbol_frontend    → 05_fft256_dual_symbol_frontend.html
6. meyr_integer_cfo_fft_frontend_top → 06_meyr_integer_cfo_fft_frontend_top.html
7. meyr_integer_cfo_core          → 07_meyr_integer_cfo_core.html
8. iq_replay_buffer_576           → 08_iq_replay_buffer_576.html
9. low_level_datapath_blocks      → 09_low_level_datapath_blocks.html

For low_level_datapath_blocks.html, include sub-modules:

- frame_detector
- streaming_cp_autocorr
- timing_metric_core
- peak_detector
- frac_cfo_estimator
- cordic_atan2
- frac_cfo_corrector_top
- nco_phase_gen
- complex_mult_iq
- complex_rotator
- fft256_xilinx_wrapper
- meyr_pss_sss_product_gen
- meyr_term2_ref_rom
- phase3_axi_lite_regs

For each module HTML file, include these 18 sections:

SECTION 1 — Header / Hero

- module name banner with badge cluster (verification status badges)
- source file path, date, project name
- one-line role description
- pipeline stage indicator (1 through 6)
- quick-reference stats: input width, output width, latency cycles, gates PASS count

SECTION 2 — Integration Context

- where this module sits in the full DUT hierarchy
- upstream module(s) → this module → downstream module(s)
- AXI-S or control signals crossing this boundary
- any module-level clock domain considerations
- dependency on reset sequencing order

SECTION 3 — Block Diagram

Create a clean pure HTML/CSS block diagram.

Requirements:
- no external CDN
- no JavaScript required
- use only HTML/CSS
- show major internal sub-blocks
- show signal flow arrows
- show valid/ready paths when important
- show feedback/replay paths if applicable
- for wrapper/top modules, show hierarchy
- for algorithm blocks, show datapath and control FSM separately if useful

SECTION 4 — Input Interface

Create a table with:
- signal name
- width (exact from RTL)
- direction
- type (AXI-S, control, status, clock, reset)
- description
- valid/ready relation if applicable
- reset behavior if applicable

SECTION 5 — Output Interface

Create a table with:
- signal name
- width (exact from RTL)
- direction
- type
- description
- timing relation
- valid/ready relation if applicable

SECTION 6 — Parameters / Localparams

Create a table with:
- parameter name
- default value
- meaning
- where used internally
- dependency on NSC, CP_LEN, FRAME_LEN, FFT_SIZE, etc.

SECTION 7 — Operation

Explain block operation in clear engineering language.

Include:
- startup behavior
- main operation
- state machine behavior if FSM exists
- pipeline behavior if pipelined
- done/valid generation
- backpressure behavior
- reset behavior
- corner cases

SECTION 8 — Timing Diagram

Create a clean HTML/CSS timing diagram showing:
- clk
- reset_n
- key input signals (valid, data, ready)
- key output signals (valid, data, done)
- key internal state transitions
- latency annotations where applicable
- use waveform-style horizontal bars with CSS
- no JavaScript, no external dependencies

SECTION 9 — Internal FSM

If this module has an FSM:
- state names and encodings
- state transition table (from-state, condition, to-state, outputs)
- CSS/HTML FSM bubble diagram or state table
- reset state
- terminal states or self-looping states
- any Gray-coded or one-hot encoding notes

If no FSM, explain the pipeline/datapath control flow.

SECTION 10 — Algorithm Mapping

Map RTL behavior to C reference algorithm.

For each module, identify related C reference functions when applicable:
- synchronization()
- frame_detector()
- VanDeBeekAutoCorrelation()
- auto_corr()
- apply_carrier_freq_offset()
- carrierFreqOffsetEstMeyr()
- fft_correlation_Meyr()
- fft_without_rearrange()
- m_seq()
- gold_seq()

If no direct C reference exists, explain it as hardware infrastructure.

Provide line-level RTL-to-C cross-reference where possible.

SECTION 11 — Latency Analysis

Create a table:
- signal/operation
- latency (cycles)
- measurement method (RTL analysis, simulation)
- notes (pipeline stages, BRAM read latency, CORDIC latency, etc.)

Include:
- input-to-output data latency
- valid assertion latency
- done/tlast latency
- CORDIC latency if applicable
- FFT pipeline latency if applicable
- backpressure stall impact

SECTION 12 — Throughput Analysis

Create a table:
- operating mode
- samples per clock
- throughput (samples/cycle)
- bottleneck (if any)
- backpressure impact

Include:
- sustained throughput at 1 sample/clock
- burst behavior
- underflow/overflow conditions
- FIFO depth requirements

SECTION 13 — Resource Impact

Create a table estimating or citing:
- LUTs (estimated or from synthesis if available)
- Flip-Flops
- BRAM blocks
- DSP48 blocks
- any special primitives (CORDIC, FFT, NCO)
- notes on optimizations used (pipeline balancing, RAM inference, etc.)

SECTION 14 — RTL Simulation Coverage

Create a table:
- gate name
- simulator
- real Xilinx IP or behavioral stub
- cases
- status
- report path
- notes

Use existing reports where available.

At minimum include known gates:
- P3-12B / P3-12C replay buffer
- P3-13E FFT protocol
- P3-14B replay integration
- P3-14C C-reference stages 1-3
- P3-15A full equivalence
- P3-15C robust equivalence
- P3-15D random equivalence
- P3-16A full integration
- P3-20A AXI backpressure
- P3-22A AWGN robustness
- P3-23A reset/CFO/multiframe stress
- XIP-001/XIP-002/XIP-003/XIP-004 Vivado xsim real Xilinx FFT IP gates if present

SECTION 15 — Known Issues / Lessons Learned

Include resolved and open items where applicable:
- ISSUE-001 complex_mult_iq backpressure bug resolved
- ISSUE-002 random equivalence D2 metadata issue resolved
- XIP full-sync real IP closure
- FFT IP reset between cases lesson from XIP-003
- AXI-S testbench race pattern (critical knowledge)
- ROM parameter plumbing bug (meyr_integer_cfo_freq_estimator_top.v)

SECTION 16 — FPGA Bring-Up Guide

Include:
- what to probe in ILA
- key debug signals with exact RTL signal names
- expected valid/done pulse periods
- expected counter values
- reset sequencing steps (numbered)
- AXI-Lite register map notes if relevant
- possible hardware risks
- bringup sequence checklist

SECTION 17 — Debug Checklist

Create a numbered checklist:
1. Interface signals verified with ILA
2. Reset sequence followed (with order)
3. Backpressure tested (ready de-asserted, data not lost)
4. Timing closure met (from synthesis report if available)
5. C reference comparison run
6. Gate simulation PASS confirmed
7. FPGA bring-up signal identified
8. Corner cases handled

SECTION 18 — Review Notes

Include:
- design decisions that were non-obvious
- things a future RTL engineer should know
- open items or potential improvements
- REQUIRES_CONFIRMATION items

---

Index page (docs/modules/index.html) must include these 7 subsections:

1. Project overview header with verification closure badge
2. Full DUT hierarchy CSS block diagram
3. Module registry table (module, source file, algorithm stage, doc file, verification status, gates passing)
4. Verification status matrix (gate × module pass/fail heatmap style)
5. Quick-reference parameter table (all shared parameters: FRAME_LEN, NSC, CP_LEN, FFT_SIZE, PSS_OFFSET, SSS_OFFSET, etc.)
6. Report links section (links to algorithm_reference_spec.html, current_status.html, issue_tracking.html)
7. Document generation metadata (date, files generated, RTL files inspected)

---

Design requirements:

Use the same professional dark dashboard style as algorithm_reference_spec.html.

Use this color palette:
#001219
#005F73
#0A9396
#94D2BD
#E9D8A6
#EE9B00
#CA6702
#BB3E03
#AE2012
#9B2226

Style requirements:
- modern engineering documentation look
- sidebar or top navigation
- card-based layout
- clean tables
- badges for PASS/WARN/FAIL/PENDING/RESOLVED
- consistent typography
- block diagrams should look clean and readable
- timing diagrams: waveform-style using CSS divs/borders
- FSM diagrams: CSS circles or boxes with arrows
- no external dependencies whatsoever

---

Source inspection requirements:

Actually inspect RTL files before documenting.
Do not invent interfaces.
Do not guess signal widths if they are available in RTL.
If something is unclear, mark it as: REQUIRES_CONFIRMATION

Do not claim a gate passed unless the reports/logs show it.

RTL files to inspect:
rtl/DUT/phase3_sync_axis_dma_wrapper.v
rtl/DUT/phase3_sync_top.v
rtl/DUT/frac_cfo_frame_corrector_top.v
rtl/DUT/pss_sss_symbol_extractor.v
rtl/DUT/fft256_dual_symbol_frontend.v
rtl/DUT/meyr_integer_cfo_fft_frontend_top.v
rtl/DUT/meyr_integer_cfo_core.v
rtl/DUT/iq_replay_buffer_576.v
rtl/DUT/frame_detector.v
rtl/DUT/streaming_cp_autocorr.v
rtl/DUT/timing_metric_core.v
rtl/DUT/peak_detector.v
rtl/DUT/frac_cfo_estimator.v
rtl/DUT/cordic_atan2.v
rtl/DUT/frac_cfo_corrector_top.v
rtl/DUT/nco_phase_gen.v
rtl/DUT/complex_mult_iq.v
rtl/DUT/complex_rotator.v
rtl/DUT/fft256_xilinx_wrapper.v
rtl/DUT/meyr_pss_sss_product_gen.v
rtl/DUT/phase3_axi_lite_regs.v

Also inspect:
reports/current_status.html
reports/issue_tracking.html
docs/algorithm_reference_spec.html
docs/modules/ (existing 12-section versions)

---

HTML update requirements:

After generating module docs, update:

/home/zealatan/RTL_SYNC_PHASE4/docs/algorithm_reference_spec.html

Update the "Module-Level Documentation" section (Section 13) to:
"Module-Level Design Review Documentation"

with updated links and a note that these are 18-section design review packages.

Also update:

/home/zealatan/RTL_SYNC_PHASE4/reports/current_status.html

Update the documentation status row to:
"Module-Level RTL Design Review Package"
Status: PASS (18 sections, 10 files, 2026-06-04)

---

Quality checks before completing:

1. Verify all 10 HTML files exist in docs/modules/
2. Verify each file has at minimum sections 1-18
3. Verify no external CDN links (no https:// in style/script tags)
4. Verify all inter-module links work (relative paths)
5. Verify index.html links to all 9 module pages
6. Verify no placeholder text like "TBD" or "[TODO]" left in
7. Mark anything genuinely uncertain as REQUIRES_CONFIRMATION

---

Final terminal summary must include:

1. RTL files inspected
2. HTML documents generated (with sizes)
3. Modules documented
4. New sections added vs prior version
5. Timing diagrams generated
6. FSM diagrams generated
7. Gates referenced
8. Reports updated
9. Any REQUIRES_CONFIRMATION items
10. Exact path to index.html
