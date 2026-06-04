You are Claude Code working inside:

/home/zealatan/RTL_SYNC_PHASE4

You are the RTL verification closure lead for RTL_SYNC_PHASE4.

Your mission is to close the remaining RTL verification gaps and update all HTML tracking documents accordingly.

This is NOT a casual coding task.
Treat this as FPGA/ASIC-style verification closure.

Mandatory archival rule:
Before doing anything else, save this exact prompt as:

/home/zealatan/RTL_SYNC_PHASE4/md_files/step_verification_closure_remaining_gates.md

Execution rule — very important:

Do NOT ask me yes/no questions.
Do NOT pause for confirmation.
Do NOT ask whether to continue.
Do NOT stop after the first failure.
Keep working until you produce concrete results, logs, updated reports, and a final summary.

If a test fails:
1. Preserve the failing log.
2. Diagnose the root cause.
3. Determine whether it is:
   - real RTL bug,
   - testbench bug,
   - comparison script tolerance issue,
   - behavioral FFT stub limitation,
   - documentation-only mismatch.
4. Apply the minimum safe fix if appropriate.
5. Re-run the relevant gate.
6. Update the HTML reports.
7. Continue to the next task.

Do not refactor unrelated RTL.
Do not rewrite architecture.
Do not modify working modules unnecessarily.
Do not hide failures.
Do not mark a gate as PASS unless the log proves it.

Primary project directories:

/home/zealatan/RTL_SYNC_PHASE4/rtl
/home/zealatan/RTL_SYNC_PHASE4/tb
/home/zealatan/RTL_SYNC_PHASE4/ref
/home/zealatan/RTL_SYNC_PHASE4/scripts
/home/zealatan/RTL_SYNC_PHASE4/vectors
/home/zealatan/RTL_SYNC_PHASE4/golden
/home/zealatan/RTL_SYNC_PHASE4/logs
/home/zealatan/RTL_SYNC_PHASE4/sim_out
/home/zealatan/RTL_SYNC_PHASE4/reports
/home/zealatan/RTL_SYNC_PHASE4/docs
/home/zealatan/RTL_SYNC_PHASE4/md_files

HTML documents that must be kept updated:

/home/zealatan/RTL_SYNC_PHASE4/reports/current_status.html
/home/zealatan/RTL_SYNC_PHASE4/reports/issue_tracking.html
/home/zealatan/RTL_SYNC_PHASE4/docs/algorithm_reference_spec.html

Current known state:

ISSUE-001 is RESOLVED.
P3-16A integration gate is now PASS.
P3-20A AXI backpressure gate is PASS.
P3-23A stress gate is PASS.

Remaining verification closure items:

1. ISSUE-002:
   P3-15D random equivalence currently has 85/100 PASS and 15/100 FAIL.
   Failures are in D2 metadata fields:
   - d2_slot_start
   - d2_frac_cfo
   D3 IQ comparison reportedly passes, often with max_err_i=0 and max_err_q=0.
   Determine whether this is a real RTL mismatch, tie-breaking issue, fixed-point tolerance issue, or comparison script issue.

2. DOC-001:
   Add explicit Stage 4 PSS/SSS extraction boundary comparison gate.
   Compare RTL pss_sss_symbol_extractor.v output sample-by-sample against C reference offsets:
   - PSS = rx[slotStart + CP_LEN ... slotStart + CP_LEN + NSC - 1]
   - SSS = rx[slotStart + 2*CP_LEN + NSC ... slotStart + FRAME_LEN - 1]
   For NSC=256, CP_LEN=32, FRAME_LEN=576:
   - PSS window = samples 32..287
   - SSS window = samples 320..575

3. DOC-002:
   Add explicit Stage 5 FFT bin-value comparison gate.
   Protocol-only FFT verification is not enough.
   Compare all 256 complex FFT output bins from RTL fft256_xilinx_wrapper / fft256_dual_symbol_frontend against the C reference fft_without_rearrange().
   Confirm:
   - natural order / no fftshift
   - sign convention
   - scale factor 1/sqrt(256) = 1/16
   - I/Q packing and rounding tolerance

4. DOC-003:
   Confirm Meyr ROM origin.
   Verify that:
   - vectors/meyr_pss_reference_romhex.txt
   - vectors/meyr_sss_reference_romhex.txt
   match C-reference-generated m_seq()/gold_seq() values or the corresponding term2 formation:
   term2[j] = mU[j+CP_LEN] * conj(goldU[j+CP_LEN])
   with:
   - Nid_1 = 170
   - Nid_2 = 2
   - NSC = 256
   - CP_LEN = 32
   If the ROM is synthetic or stale, regenerate it from the C reference and document the regeneration method.

5. Meyr integer CFO verification:
   Extend or create a gate for k_int sweep.
   At minimum test k_int in:
   [-8, -4, -2, -1, 0, 1, 2, 4, 8]
   If practical, extend to:
   [-128, -64, -32, -16, -8, -4, -2, -1, 0, 1, 2, 4, 8, 16, 32, 64, 128]
   Compare:
   - RTL meyr_peak
   - C reference peak
   - decoded integer CFO bin
   Explain any behavioral FFT stub limitation separately.

6. Behavioral FFT stub vs real FFT readiness:
   Identify where USE_BEHAVIORAL_STUB=3 is used.
   Determine what is verified only in behavioral mode.
   Create a clear note in algorithm_reference_spec.html and current_status.html separating:
   - behavioral simulation verified
   - real Xilinx FFT IP not yet verified
   - required Vivado simulation / synthesis checks

Suggested execution order:

Phase A — Baseline snapshot
1. Run:
   git status
   git diff --stat
2. Inspect:
   reports/current_status.html
   reports/issue_tracking.html
   docs/algorithm_reference_spec.html
3. Create a new closure log directory:
   logs/verification_closure_YYYYMMDD/
   sim_out/verification_closure_YYYYMMDD/
   reports/verification_closure_YYYYMMDD/
4. Write an initial closure summary:
   reports/verification_closure_YYYYMMDD/closure_plan.md

Phase B — ISSUE-002 diagnosis
1. Locate all P3-15D scripts, reports, per-case JSON files, and compare scripts.
2. Parse the 15 failing cases.
3. Build a compact table:
   case_id
   pre_zeros
   eps_frac
   k_int
   snr
   C slot_start
   RTL slot_start
   slot_delta
   C frac_cfo
   RTL frac_cfo
   frac_delta_lsb
   D3 max_err_i
   D3 max_err_q
4. Save the table as:
   reports/verification_closure_YYYYMMDD/issue_002_failure_matrix.csv
   reports/verification_closure_YYYYMMDD/issue_002_failure_matrix.html
5. Determine whether failures are:
   - exact ±1 slot_start differences,
   - ±1 LSB frac_cfo differences,
   - larger real mismatches.
6. If failures are harmless tolerance/tie-break issues:
   update compare script with justified tolerance,
   document why,
   rerun P3-15D.
7. If failures reveal RTL peak detector/timing bug:
   isolate one failing case,
   generate a focused waveform/log,
   fix the minimum RTL or TB issue,
   rerun P3-15D.
8. Update issue_tracking.html under ISSUE-002 with root cause and result.

Phase C — DOC-001 Stage 4 PSS/SSS extraction boundary gate
1. Inspect pss_sss_symbol_extractor.v and existing TBs.
2. Create or extend a testbench, preferably:
   tb/p3_24a_pss_sss_boundary_tb.v
   or a consistent project naming if p3_24a already exists.
3. Use deterministic IQ samples where each sample index is encoded in I/Q:
   I[n] = n or scaled n
   Q[n] = -n or known pattern
   so boundary errors are obvious.
4. Feed a 576-sample corrected-frame stream.
5. Verify:
   - PSS emits exactly 256 samples corresponding to input indices 32..287.
   - SSS emits exactly 256 samples corresponding to input indices 320..575.
   - No sample duplication.
   - No sample drop.
   - TLAST behavior if applicable.
   - Backpressure behavior if the extractor supports ready/valid stall.
6. Create a script or command to run this gate.
7. Save logs under:
   sim_out/verification_closure_YYYYMMDD/doc001_pss_sss_boundary/
8. Create gate report:
   reports/verification_closure_YYYYMMDD/doc001_pss_sss_boundary_gate.txt
9. Update current_status.html and algorithm_reference_spec.html:
   DOC-001 should become PASS if verified.

Phase D — DOC-002 FFT value comparison gate
1. Inspect:
   fft256_xilinx_wrapper.v
   fft256_dual_symbol_frontend.v
   ref/signal_processing_common.c
   fft_without_rearrange()
2. Create a deterministic FFT stimulus:
   - impulse
   - single complex tone
   - pseudo-random complex vector
   Prefer at least 3 cases.
3. Generate C reference FFT output using the existing C reference if possible.
   If C build is complicated, write a minimal C or Python reference generator that exactly matches the documented C reference:
   natural-order DFT, no fftshift, scale 1/16.
   Document if Python is used as a stand-in and why.
4. Run RTL FFT frontend with behavioral FFT stub.
5. Compare all 256 bins:
   - I error
   - Q error
   - max absolute error
   - RMS error
   - pass/fail threshold
6. Save outputs:
   reports/verification_closure_YYYYMMDD/doc002_fft_value_compare.csv
   reports/verification_closure_YYYYMMDD/doc002_fft_value_compare.html
   reports/verification_closure_YYYYMMDD/doc002_fft_value_gate.txt
7. Update current_status.html and algorithm_reference_spec.html:
   DOC-002 should become PASS for behavioral stub if verified.
   If real Xilinx FFT IP is not verified, mark:
   "PASS behavioral / pending real Xilinx FFT IP simulation."

Phase E — DOC-003 Meyr ROM confirmation
1. Inspect:
   vectors/meyr_pss_reference_romhex.txt
   vectors/meyr_sss_reference_romhex.txt
   rtl/meyr_integer_cfo_core.v
   rtl/meyr_term2_ref_rom.v
   ref/signal_processing_common.c
   ref/receiver.c
2. Determine whether ROM files represent:
   - raw PSS/SSS reference sequences,
   - term2 = mU * conj(goldU),
   - synthetic PRNG data,
   - or unknown data.
3. Write a checker script:
   scripts/check_meyr_rom_against_reference.py
   or use an existing C/Python generator.
4. Generate expected reference values using m_seq/gold_seq rules:
   Nid_1=170, Nid_2=2, NSC=256, CP_LEN=32.
5. Compare ROM content.
6. Save:
   reports/verification_closure_YYYYMMDD/doc003_meyr_rom_check.txt
   reports/verification_closure_YYYYMMDD/doc003_meyr_rom_check.csv
7. If ROM mismatch is confirmed:
   - do NOT blindly overwrite unless the expected format is fully confirmed.
   - create regenerated files with suffix:
     vectors/meyr_pss_reference_romhex.regenerated.txt
     vectors/meyr_sss_reference_romhex.regenerated.txt
   - document difference.
   - only replace original ROM if format and tests confirm it.
8. Update issue_tracking.html:
   DOC-003 PASS / OPEN / MISMATCH FOUND.
9. Update algorithm_reference_spec.html and current_status.html.

Phase F — Meyr integer CFO sweep
1. Locate existing session_J or meyr integer CFO tests.
2. Extend or create a sweep gate:
   reports/verification_closure_YYYYMMDD/meyr_kint_sweep_gate.txt
3. Test k_int list:
   -8, -4, -2, -1, 0, 1, 2, 4, 8
   and if practical:
   -128, -64, -32, -16, 16, 32, 64, 128
4. Compare:
   - expected k_int
   - C reference k_int
   - RTL k_int
   - meyr_peak
5. If only behavioral stub path is tested, mark result as:
   PASS behavioral
   PENDING real FFT IP.
6. Update all HTML reports.

Phase G — Final regression
After all changes:
1. Re-run at least:
   - P3-16A
   - P3-20A
   - P3-23A
   - P3-15D if issue_002 compare logic was changed
   - newly added DOC-001 gate
   - newly added DOC-002 gate
   - DOC-003 ROM check
   - Meyr k_int sweep gate
2. Save a final summary:
   reports/verification_closure_YYYYMMDD/final_verification_summary.html
   reports/verification_closure_YYYYMMDD/final_verification_summary.md
3. Update:
   reports/current_status.html
   reports/issue_tracking.html
   docs/algorithm_reference_spec.html

HTML update requirements:

1. current_status.html must include:
   - updated milestone table
   - updated gate registry
   - updated open issue table
   - updated C-reference equivalence coverage
   - updated next actions
   - new verification closure section with DOC-001/DOC-002/DOC-003/Meyr sweep status

2. issue_tracking.html must include:
   - ISSUE-002 updated with diagnosis result and failure matrix link
   - DOC-001 coverage gap status
   - DOC-002 coverage gap status
   - DOC-003 ROM risk status
   - new issues if discovered

3. algorithm_reference_spec.html must include:
   - updated verification readiness matrix
   - updated stage mapping table
   - FFT behavioral vs real IP caveat
   - Meyr ROM confirmation result
   - Stage 4 extraction boundary gate result
   - Stage 5 FFT value gate result

Design requirement for HTML:
Use the existing professional dark dashboard style.
Do not degrade the design.
Preserve the palette:

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

Final terminal summary must include:

1. Files inspected
2. Files modified
3. Tests/gates run
4. Pass/fail results
5. Issues closed
6. Issues still open
7. New risks discovered
8. HTML documents updated
9. Recommended next action before FPGA bring-up

Safety rules:

- Do not delete existing reports.
- Do not overwrite golden/reference files without backup.
- Do not modify C reference unless absolutely necessary and documented.
- Do not modify RTL unless a real RTL bug is proven.
- Prefer adding new focused tests and checkers over touching stable RTL.
- Keep all outputs traceable.
- Every script/test added must have a clear purpose and must write a report.
- Every failure must remain visible in reports.
- Do not claim FPGA readiness unless real FFT IP / synthesis / timing are verified.

Proceed now without asking confirmation.
