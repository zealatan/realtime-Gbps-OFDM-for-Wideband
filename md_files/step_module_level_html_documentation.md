You are Claude Code working inside:

/home/zealatan/RTL_SYNC_PHASE4

Your mission is to create professional module-level HTML documentation for the RTL_SYNC_PHASE4 synchronizer subsystem.

This is a documentation task.
Do NOT modify RTL files.
Do NOT modify testbenches.
Do NOT modify vectors/golden files.
Only inspect source files and generate documentation.

Mandatory archival rule:

Before doing anything else, save this exact prompt as:

/home/zealatan/RTL_SYNC_PHASE4/md_files/step_module_level_html_documentation.md

Execution rule:

Do NOT ask me yes/no questions.
Do NOT pause for confirmation.
Do NOT ask whether to continue.
Continue until concrete HTML files are generated and reports are updated.

Target output directory:

/home/zealatan/RTL_SYNC_PHASE4/docs/modules/

Create this index file:

/home/zealatan/RTL_SYNC_PHASE4/docs/modules/index.html

Create detailed HTML documents for these modules:

1. phase3_sync_axis_dma_wrapper
2. phase3_sync_top
3. frac_cfo_frame_corrector_top
4. pss_sss_symbol_extractor
5. fft256_dual_symbol_frontend
6. meyr_integer_cfo_fft_frontend_top
7. meyr_integer_cfo_core
8. iq_replay_buffer_576
9. low_level_datapath_blocks

For low_level_datapath_blocks.html, include:

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

For each detailed module HTML file, include these sections:

1. Module Summary

- module name
- source file path
- role in full DUT
- algorithm stage
- verification status
- related gates
- known issues or resolved issues

2. Input Interface

Create a table with:

- signal name
- width
- direction
- type
- description
- valid/ready relation if applicable
- reset behavior if applicable

3. Output Interface

Create a table with:

- signal name
- width
- direction
- type
- description
- timing relation
- valid/ready relation if applicable

4. Parameters / Localparams

Create a table with:

- parameter name
- default value
- meaning
- where used
- dependency on NSC, CP_LEN, FRAME_LEN, etc.

5. Operation

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

6. Algorithm Mapping

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

7. Timing / Latency / Throughput

Include:

- sample-per-clock behavior if applicable
- cycles per frame if known
- pipeline latency if known
- FSM state timing if known
- valid-to-output latency
- done latency
- TLAST timing if applicable
- whether backpressure stalls internal counters
- whether NCO or FFT state must be reset between frames

8. Block Diagram

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

9. RTL Simulation Coverage

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

10. FPGA Bring-up Notes

Include:

- what to probe in ILA
- key debug signals
- expected valid/done pulses
- expected counters
- reset sequencing
- AXI-Lite register notes if relevant
- possible hardware risks

11. Known Issues / Lessons Learned

Include resolved and open items where applicable:

- ISSUE-001 complex_mult_iq backpressure bug resolved
- ISSUE-002 random equivalence D2 metadata issue if still relevant
- XIP full-sync real IP closure if available
- FFT IP reset between cases lesson from XIP-003

12. Review Checklist

Create a checklist for each module:

- interface checked
- reset checked
- backpressure checked
- timing checked
- C reference mapping checked
- simulation gate checked
- FPGA bring-up signal identified

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
- no external dependencies

Index page requirements:

docs/modules/index.html must include:

- full DUT hierarchy overview
- clickable cards for each module document
- table mapping:
  module
  source file
  algorithm stage
  documentation file
  verification status
- global DUT architecture block diagram
- link back to:
  ../algorithm_reference_spec.html
  ../../reports/current_status.html
  ../../reports/issue_tracking.html

Source inspection requirements:

Actually inspect RTL files before documenting.
Do not invent interfaces.
Do not guess signal widths if they are available in RTL.
If something is unclear, mark it as:

REQUIRES_CONFIRMATION

Do not claim a gate passed unless the reports/logs show it.

Suggested files to inspect:

rtl/phase3_sync_axis_dma_wrapper.v
rtl/phase3_sync_top.v
rtl/frac_cfo_frame_corrector_top.v
rtl/pss_sss_symbol_extractor.v
rtl/fft256_dual_symbol_frontend.v
rtl/meyr_integer_cfo_fft_frontend_top.v
rtl/meyr_integer_cfo_core.v
rtl/iq_replay_buffer_576.v
rtl/frame_detector.v
rtl/streaming_cp_autocorr.v
rtl/timing_metric_core.v
rtl/peak_detector.v
rtl/frac_cfo_estimator.v
rtl/cordic_atan2.v
rtl/frac_cfo_corrector_top.v
rtl/nco_phase_gen.v
rtl/complex_mult_iq.v
rtl/complex_rotator.v
rtl/fft256_xilinx_wrapper.v
rtl/meyr_pss_sss_product_gen.v
rtl/meyr_term2_ref_rom.v
rtl/phase3_axi_lite_regs.v

Also inspect:

reports/current_status.html
reports/issue_tracking.html
docs/algorithm_reference_spec.html
vivado_xsim/reports/
sim_out/
logs/

HTML update requirements:

After generating module docs, update:

/home/zealatan/RTL_SYNC_PHASE4/docs/algorithm_reference_spec.html

Add a new section:

"Module-Level Documentation"

with links to:

docs/modules/index.html
docs/modules/01_phase3_sync_axis_dma_wrapper.html
docs/modules/02_phase3_sync_top.html
docs/modules/03_frac_cfo_frame_corrector_top.html
docs/modules/04_pss_sss_symbol_extractor.html
docs/modules/05_fft256_dual_symbol_frontend.html
docs/modules/06_meyr_integer_cfo_fft_frontend_top.html
docs/modules/07_meyr_integer_cfo_core.html
docs/modules/08_iq_replay_buffer_576.html
docs/modules/09_low_level_datapath_blocks.html

Also update:

/home/zealatan/RTL_SYNC_PHASE4/reports/current_status.html

Add a documentation status row:

"Module-Level RTL Documentation"
Status:
PASS if all documents generated and linked.

Do not update issue_tracking.html unless documentation reveals a real inconsistency, missing verification, or source/report mismatch.

Final terminal summary must include:

1. RTL files inspected
2. HTML documents generated
3. modules documented
4. diagrams generated
5. gates referenced
6. reports updated
7. any REQUIRES_CONFIRMATION items
8. exact path to index.html

Proceed without asking confirmation.
