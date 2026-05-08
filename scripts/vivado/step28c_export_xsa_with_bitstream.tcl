# =============================================================================
# step28c_export_xsa_with_bitstream.tcl
# Step 28C: Export XSA with embedded bitstream for Phase-1 ZCU102 bring-up.
#
# Root cause of Step 28 XSA issue:
#   write_hw_platform -include_bit failed because the impl_1 run was launched
#   without -to_step write_bitstream.  Vivado's write_hw_platform -include_bit
#   requires that write_bitstream was invoked through the run infrastructure
#   (not a standalone write_bitstream call), so the run's BIT file pointer is set.
#
# Fix applied here:
#   launch_runs impl_1 -to_step write_bitstream
#   This drives impl_1 all the way through write_bitstream as a run step,
#   after which write_hw_platform -include_bit succeeds.
#
# Key differences from step28_build_bitstream_xsa.tcl:
#   1. impl_1 launched with -to_step write_bitstream (not default route_design stop)
#   2. Bitstream existence verified in run directory before XSA export
#   3. No fallback to no-bit XSA — exits non-zero if -include_bit fails
#   4. Output XSA: sync_phase1_bd_wrapper_with_bit.xsa (additive, does not overwrite)
#   5. Reports go to reports/step28c/ (not reports/step28/)
#
# Run from Windows Vivado 2022.2 batch mode, from C:\RTL_SYNC:
#   C:\Xilinx\Vivado\2022.2\bin\vivado.bat -mode batch ^
#       -source scripts/vivado/step28c_export_xsa_with_bitstream.tcl ^
#       -log    reports/step28c/step28c_export_xsa_with_bitstream.log ^
#       -journal reports/step28c/step28c_export_xsa_with_bitstream.jou
#
# Outputs (additive — does not delete Step 28 outputs):
#   outputs/step28/sync_phase1_bd_wrapper_with_bit.xsa  <-- NEW
#   reports/step28c/step28c_synth_utilization.rpt
#   reports/step28c/step28c_synth_timing_summary.rpt
#   reports/step28c/step28c_impl_utilization.rpt
#   reports/step28c/step28c_timing_summary.rpt
#   reports/step28c/step28c_drc.rpt
#   reports/step28c/step28c_power.rpt
#
# Preserved Step 28 outputs (not touched):
#   outputs/step28/sync_phase1_bd_wrapper.bit
#   outputs/step28/sync_phase1_bd_wrapper.xsa
# =============================================================================

set PROJ_FILE    "vivado/step27_zcu102_bd/step27_zcu102_bd.xpr"
set BD_TOP       "sync_phase1_bd_wrapper"
set RPTS         "reports/step28c"
set OUT          "outputs/step28"
set XSA_WITH_BIT "${OUT}/sync_phase1_bd_wrapper_with_bit.xsa"

# impl_1 run directory — bitstream will be written here by the run infrastructure
set IMPL_RUN_DIR "vivado/step27_zcu102_bd/step27_zcu102_bd.runs/impl_1"

puts "========================================================"
puts "Step 28C: Export XSA with embedded bitstream"
puts "Project:  $PROJ_FILE"
puts "Top:      $BD_TOP"
puts "Out XSA:  $XSA_WITH_BIT"
puts ""
puts "Key fix: impl_1 launched with -to_step write_bitstream"
puts "         so write_hw_platform -include_bit can locate the BIT file."
puts "No ILA | No DMA | No RTL changes"
puts "========================================================"

file mkdir $RPTS
file mkdir $OUT

# =============================================================================
# Preflight: verify Step 27 project exists
# =============================================================================
if {![file exists $PROJ_FILE]} {
    puts "ERROR: Step 27 project not found: $PROJ_FILE"
    puts "       Run Step 27 first:"
    puts "       scripts\\windows\\run_step27_create_zcu102_bd_no_ila.bat"
    exit 1
}
puts "INFO: Step 27 project found: $PROJ_FILE"

# =============================================================================
# Open Step 27 project
# =============================================================================
puts ""
puts "--- Opening Step 27 Vivado project ---"
open_project $PROJ_FILE

# Verify / set top module
set cur_top [get_property TOP [get_fileset sources_1]]
puts "INFO: Current top: $cur_top"
if {$cur_top ne $BD_TOP} {
    puts "WARNING: Top is '$cur_top', expected '$BD_TOP'."
    puts "         Attempting to set top to $BD_TOP..."
    if {[catch {set_property TOP $BD_TOP [get_fileset sources_1]} t_err]} {
        puts "ERROR: Could not set top: $t_err"
        exit 1
    }
    set cur_top [get_property TOP [get_fileset sources_1]]
    puts "INFO: Top is now: $cur_top"
}

# =============================================================================
# Reset prior runs (idempotent — safe to call on a fresh or used project)
# =============================================================================
puts ""
puts "--- Resetting prior run state ---"
set synth_status [get_property STATUS [get_runs synth_1]]
set impl_status  [get_property STATUS [get_runs impl_1]]
puts "INFO: synth_1 status before reset: $synth_status"
puts "INFO: impl_1  status before reset: $impl_status"
catch {reset_run impl_1}
catch {reset_run synth_1}
puts "INFO: Runs reset."

# =============================================================================
# SYNTHESIS
# =============================================================================
puts ""
puts "--- Launching synthesis (synth_1, 4 jobs) ---"
launch_runs synth_1 -jobs 4
wait_on_run synth_1

set synth_progress [get_property PROGRESS [get_runs synth_1]]
set synth_status   [get_property STATUS   [get_runs synth_1]]
puts "INFO: synth_1 progress: $synth_progress"
puts "INFO: synth_1 status:   $synth_status"

if {$synth_progress ne "100%"} {
    puts "ERROR: Synthesis did not complete (progress = $synth_progress)."
    exit 1
}
if {[string match "*fail*" [string tolower $synth_status]]} {
    puts "ERROR: Synthesis failed: $synth_status"
    exit 1
}
puts "INFO: Synthesis COMPLETE."

# Open synthesized design and generate reports
puts "INFO: Opening synthesized design for reporting..."
open_run synth_1 -name synth_1

report_utilization \
    -file ${RPTS}/step28c_synth_utilization.rpt \
    -quiet
puts "INFO: Synthesis utilization report: ${RPTS}/step28c_synth_utilization.rpt"

report_timing_summary \
    -delay_type min_max \
    -report_unconstrained \
    -check_timing_verbose \
    -max_paths 10 \
    -input_pins \
    -file ${RPTS}/step28c_synth_timing_summary.rpt \
    -quiet
puts "INFO: Synthesis timing report:      ${RPTS}/step28c_synth_timing_summary.rpt"

# =============================================================================
# IMPLEMENTATION — to_step write_bitstream
# =============================================================================
# The critical difference from Step 28:
#   -to_step write_bitstream makes the run infrastructure invoke write_bitstream
#   as part of impl_1.  The run then records the path to the generated BIT file.
#   write_hw_platform -include_bit queries this path; if it was not set via the
#   run infrastructure, the command fails with "Unable to get BIT file".
# =============================================================================
puts ""
puts "--- Launching implementation to write_bitstream stage ---"
puts "    (launch_runs impl_1 -to_step write_bitstream -jobs 4)"
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

set impl_progress [get_property PROGRESS [get_runs impl_1]]
set impl_status   [get_property STATUS   [get_runs impl_1]]
puts "INFO: impl_1 progress: $impl_progress"
puts "INFO: impl_1 status:   $impl_status"

if {$impl_progress ne "100%"} {
    puts "ERROR: Implementation did not complete (progress = $impl_progress)."
    exit 1
}
if {[string match "*fail*" [string tolower $impl_status]]} {
    puts "ERROR: Implementation failed: $impl_status"
    exit 1
}
puts "INFO: Implementation COMPLETE."

# Verify the bitstream file was actually written inside the run directory.
# This is an additional guard — write_hw_platform -include_bit requires this file.
puts "INFO: Verifying bitstream in run directory: $IMPL_RUN_DIR"
set bit_files [glob -nocomplain "${IMPL_RUN_DIR}/*.bit"]
if {[llength $bit_files] == 0} {
    puts "ERROR: No .bit file found in run directory: $IMPL_RUN_DIR"
    puts "       write_bitstream may not have run as part of impl_1."
    puts "       Check the implementation log for errors."
    exit 1
}
puts "INFO: Bitstream found in run directory: [lindex $bit_files 0]"

# =============================================================================
# Open implemented design and generate reports
# =============================================================================
puts "INFO: Opening implemented design for reporting..."
open_run impl_1 -name impl_1

report_utilization \
    -file ${RPTS}/step28c_impl_utilization.rpt \
    -quiet
puts "INFO: Impl utilization report: ${RPTS}/step28c_impl_utilization.rpt"

report_timing_summary \
    -delay_type min_max \
    -report_unconstrained \
    -check_timing_verbose \
    -max_paths 10 \
    -input_pins \
    -file ${RPTS}/step28c_timing_summary.rpt \
    -quiet
puts "INFO: Impl timing report:      ${RPTS}/step28c_timing_summary.rpt"

report_drc \
    -file ${RPTS}/step28c_drc.rpt \
    -quiet
puts "INFO: DRC report:              ${RPTS}/step28c_drc.rpt"

report_power \
    -file ${RPTS}/step28c_power.rpt \
    -quiet
puts "INFO: Power report:            ${RPTS}/step28c_power.rpt"

# =============================================================================
# TIMING CHECK
# =============================================================================
puts ""
puts "--- Checking timing ---"
set setup_paths [get_timing_paths -max_paths 1 -nworst 1 -setup -quiet]
set hold_paths  [get_timing_paths -max_paths 1 -nworst 1 -hold  -quiet]

set timing_ok 1
set wns_val   "N/A"
set whs_val   "N/A"

if {[llength $setup_paths] > 0} {
    set wns_val [get_property SLACK [lindex $setup_paths 0]]
    puts "INFO: WNS (setup) = $wns_val ns"
    if {$wns_val < 0} {
        puts "ERROR: Setup timing violated (WNS = $wns_val ns)"
        set timing_ok 0
    }
} else {
    puts "WARNING: No setup timing paths found."
}

if {[llength $hold_paths] > 0} {
    set whs_val [get_property SLACK [lindex $hold_paths 0]]
    puts "INFO: WHS (hold)  = $whs_val ns"
    if {$whs_val < 0} {
        puts "ERROR: Hold timing violated (WHS = $whs_val ns)"
        set timing_ok 0
    }
} else {
    puts "WARNING: No hold timing paths found."
}

if {$timing_ok} {
    puts ""
    puts "TIMING CHECK: PASS"
} else {
    puts ""
    puts "TIMING CHECK: FAIL"
    puts "Timing violations present. XSA export skipped."
    exit 1
}

# =============================================================================
# XSA EXPORT — with embedded bitstream, no fallback
# =============================================================================
# write_hw_platform -include_bit succeeds here because impl_1 was launched with
# -to_step write_bitstream, so the run infrastructure has the BIT file path set.
# We intentionally do NOT fall back to a no-bit XSA in this step.
# =============================================================================
puts ""
puts "--- Exporting XSA with embedded bitstream ---"
puts "    write_hw_platform -fixed -include_bit -force -file $XSA_WITH_BIT"

if {[catch {
    write_hw_platform \
        -fixed       \
        -include_bit \
        -force       \
        -file $XSA_WITH_BIT
} xsa_err]} {
    puts "ERROR: Embedded-bitstream XSA export failed: $xsa_err"
    puts ""
    puts "Possible causes:"
    puts "  - The run bitstream path was not registered (should not happen with"
    puts "    -to_step write_bitstream, but check impl_1 status)."
    puts "  - Vivado version incompatibility with -include_bit flag."
    puts ""
    puts "Do NOT fall back to no-bit XSA — this step is specifically for"
    puts "embedded-bitstream export.  Investigate the error above."
    exit 1
}
puts "INFO: XSA written: $XSA_WITH_BIT"

# Verify file was created
if {![file exists $XSA_WITH_BIT]} {
    puts "ERROR: XSA file not found after export: $XSA_WITH_BIT"
    puts "       write_hw_platform did not raise an error but the file is missing."
    exit 1
}
puts "INFO: XSA file verified: $XSA_WITH_BIT"

# =============================================================================
# Done
# =============================================================================
puts ""
puts "========================================================"
puts "Step 28C COMPLETE."
puts ""
puts "XSA with embedded bitstream:"
puts "  $XSA_WITH_BIT"
puts ""
puts "Timing:"
puts "  WNS (setup) = $wns_val ns"
puts "  WHS (hold)  = $whs_val ns"
puts ""
puts "Reports:"
puts "  ${RPTS}/step28c_synth_utilization.rpt"
puts "  ${RPTS}/step28c_synth_timing_summary.rpt"
puts "  ${RPTS}/step28c_impl_utilization.rpt"
puts "  ${RPTS}/step28c_timing_summary.rpt"
puts "  ${RPTS}/step28c_drc.rpt"
puts "  ${RPTS}/step28c_power.rpt"
puts ""
puts "Step 28 outputs preserved (not modified):"
puts "  outputs/step28/sync_phase1_bd_wrapper.bit"
puts "  outputs/step28/sync_phase1_bd_wrapper.xsa"
puts ""
puts "Recommended Vitis platform input:"
puts "  $XSA_WITH_BIT"
puts ""
puts "No ILA, no DMA, no RTL changes."
puts "========================================================"

exit 0
