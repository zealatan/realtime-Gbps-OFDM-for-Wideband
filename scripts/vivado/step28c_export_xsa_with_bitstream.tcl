# step28c_export_xsa_with_bitstream.tcl
#
# Step 28C:
#   Re-run synthesis/implementation up to write_bitstream,
#   then export XSA with embedded bitstream.
#
# Purpose:
#   Fix Step 28 issue where standalone write_bitstream succeeded,
#   but write_hw_platform -include_bit failed because Vivado run object
#   did not know the implementation-run BIT file.
#
# Important:
#   This script intentionally uses -to_step write_bitstream.
#   It also uses jobs=1 / maxThreads=1 to avoid Windows Vivado OOM
#   during ZCU102 PS + SmartConnect OOC synthesis.

set PROJ_FILE    "vivado/step27_zcu102_bd/step27_zcu102_bd.xpr"
set BD_TOP       "sync_phase1_bd_wrapper"
set RPTS         "reports/step28c"
set OUT          "outputs/step28"
set XSA_WITH_BIT "${OUT}/sync_phase1_bd_wrapper_with_bit.xsa"
set IMPL_RUN_DIR "vivado/step27_zcu102_bd/step27_zcu102_bd.runs/impl_1"

# -------------------------------------------------------------------------
# Memory safety for Windows Vivado
# -------------------------------------------------------------------------
# On Windows, ZCU102 PS IP OOC synthesis can hit out-of-memory when multiple
# OOC runs are launched in parallel. Keep everything serialized.
set_param general.maxThreads 1

puts "========================================================"
puts "Step 28C: Export XSA with embedded bitstream"
puts "Project:  $PROJ_FILE"
puts "Top:      $BD_TOP"
puts "Out XSA:  $XSA_WITH_BIT"
puts ""
puts "Key fix: impl_1 launched with -to_step write_bitstream"
puts "         so write_hw_platform -include_bit can locate the BIT file."
puts "Memory:  jobs=1, general.maxThreads=1 to avoid Windows OOM"
puts "No ILA | No DMA | No RTL changes in this script"
puts "========================================================"
puts ""

file mkdir $RPTS
file mkdir $OUT

# Remove stale output first.
# This prevents a previous good XSA from making the wrapper BAT falsely pass.
if {[file exists $XSA_WITH_BIT]} {
    file delete -force $XSA_WITH_BIT
    puts "INFO: Removed stale XSA: $XSA_WITH_BIT"
}

if {![file exists $PROJ_FILE]} {
    puts "ERROR: Step 27 project not found: $PROJ_FILE"
    puts "       Run Step 27 first:"
    puts "       scripts\\windows\\run_step27_create_zcu102_bd_no_ila.bat"
    exit 1
}

puts "INFO: Step 27 project found: $PROJ_FILE"
puts ""

# -------------------------------------------------------------------------
# Open project
# -------------------------------------------------------------------------
puts "--- Opening Step 27 Vivado project ---"
open_project $PROJ_FILE

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
puts ""

# -------------------------------------------------------------------------
# Reset old runs
# -------------------------------------------------------------------------
puts "--- Resetting prior run state ---"

if {[llength [get_runs synth_1]] == 0} {
    puts "ERROR: synth_1 run not found in project."
    exit 1
}

if {[llength [get_runs impl_1]] == 0} {
    puts "ERROR: impl_1 run not found in project."
    exit 1
}

set synth_status [get_property STATUS [get_runs synth_1]]
set impl_status  [get_property STATUS [get_runs impl_1]]
puts "INFO: synth_1 status before reset: $synth_status"
puts "INFO: impl_1  status before reset: $impl_status"

catch {reset_run impl_1}
catch {reset_run synth_1}

puts "INFO: Runs reset."
puts ""

# -------------------------------------------------------------------------
# Synthesis
# -------------------------------------------------------------------------
puts "--- Launching synthesis ---"
puts "    launch_runs synth_1 -jobs 1"
puts "    Reason: avoid Windows Vivado OOM during ZCU102 OOC IP synthesis"
launch_runs synth_1 -jobs 1

wait_on_run synth_1

set synth_progress [get_property PROGRESS [get_runs synth_1]]
set synth_status   [get_property STATUS   [get_runs synth_1]]

puts "INFO: synth_1 progress: $synth_progress"
puts "INFO: synth_1 status:   $synth_status"

if {$synth_progress ne "100%"} {
    puts "ERROR: Synthesis did not complete."
    puts "       Progress = $synth_progress"
    puts "       Status   = $synth_status"
    puts ""
    puts "Check logs:"
    puts "  vivado/step27_zcu102_bd/step27_zcu102_bd.runs/synth_1/runme.log"
    puts "  vivado/step27_zcu102_bd/step27_zcu102_bd.runs/*_synth_1/runme.log"
    exit 1
}

if {[string match "*fail*" [string tolower $synth_status]]} {
    puts "ERROR: Synthesis failed."
    puts "       Status = $synth_status"
    exit 1
}

puts "INFO: Synthesis COMPLETE."
puts ""

# -------------------------------------------------------------------------
# Synthesis reports
# -------------------------------------------------------------------------
puts "INFO: Opening synthesized design for reporting..."
if {[catch {open_run synth_1 -name synth_1} open_synth_err]} {
    puts "WARNING: Could not open synth_1 for reporting: $open_synth_err"
} else {
    if {[catch {
        report_utilization \
            -file ${RPTS}/step28c_synth_utilization.rpt \
            -quiet
    } rpt_err]} {
        puts "WARNING: Could not write synth utilization report: $rpt_err"
    } else {
        puts "INFO: Synthesis utilization report: ${RPTS}/step28c_synth_utilization.rpt"
    }

    if {[catch {
        report_timing_summary \
            -delay_type min_max \
            -report_unconstrained \
            -check_timing_verbose \
            -max_paths 10 \
            -input_pins \
            -file ${RPTS}/step28c_synth_timing_summary.rpt \
            -quiet
    } rpt_err]} {
        puts "WARNING: Could not write synth timing report: $rpt_err"
    } else {
        puts "INFO: Synthesis timing report:      ${RPTS}/step28c_synth_timing_summary.rpt"
    }

    catch {close_design}
}
puts ""

# -------------------------------------------------------------------------
# Implementation to write_bitstream
# -------------------------------------------------------------------------
puts "--- Launching implementation to write_bitstream stage ---"
puts "    launch_runs impl_1 -to_step write_bitstream -jobs 1"
puts "    Reason: register implementation-run BIT file for write_hw_platform -include_bit"
launch_runs impl_1 -to_step write_bitstream -jobs 1

wait_on_run impl_1

set impl_progress [get_property PROGRESS [get_runs impl_1]]
set impl_status   [get_property STATUS   [get_runs impl_1]]

puts "INFO: impl_1 progress: $impl_progress"
puts "INFO: impl_1 status:   $impl_status"

if {$impl_progress ne "100%"} {
    puts "ERROR: Implementation did not complete."
    puts "       Progress = $impl_progress"
    puts "       Status   = $impl_status"
    puts ""
    puts "Check log:"
    puts "  vivado/step27_zcu102_bd/step27_zcu102_bd.runs/impl_1/runme.log"
    exit 1
}

if {[string match "*fail*" [string tolower $impl_status]]} {
    puts "ERROR: Implementation failed."
    puts "       Status = $impl_status"
    exit 1
}

if {![string match "*write_bitstream Complete*" $impl_status]} {
    puts "ERROR: impl_1 did not finish at write_bitstream step."
    puts "       Status = $impl_status"
    puts "       Expected status containing: write_bitstream Complete!"
    exit 1
}

puts "INFO: Implementation COMPLETE."
puts ""

# -------------------------------------------------------------------------
# Verify run-directory bitstream
# -------------------------------------------------------------------------
puts "INFO: Verifying bitstream in run directory: $IMPL_RUN_DIR"

set bit_files [glob -nocomplain "${IMPL_RUN_DIR}/*.bit"]

if {[llength $bit_files] == 0} {
    puts "ERROR: No .bit file found in run directory: $IMPL_RUN_DIR"
    puts "       write_bitstream may not have run as part of impl_1."
    puts "       Check the implementation log for errors."
    exit 1
}

set RUN_BIT_FILE [lindex $bit_files 0]
puts "INFO: Bitstream found in run directory: $RUN_BIT_FILE"
puts ""

# -------------------------------------------------------------------------
# Implementation reports
# -------------------------------------------------------------------------
puts "INFO: Opening implemented design for reporting..."

if {[catch {open_run impl_1 -name impl_1} open_impl_err]} {
    puts "ERROR: Could not open impl_1: $open_impl_err"
    exit 1
}

if {[catch {
    report_utilization \
        -file ${RPTS}/step28c_impl_utilization.rpt \
        -quiet
} rpt_err]} {
    puts "WARNING: Could not write impl utilization report: $rpt_err"
} else {
    puts "INFO: Impl utilization report: ${RPTS}/step28c_impl_utilization.rpt"
}

if {[catch {
    report_timing_summary \
        -delay_type min_max \
        -report_unconstrained \
        -check_timing_verbose \
        -max_paths 10 \
        -input_pins \
        -file ${RPTS}/step28c_timing_summary.rpt \
        -quiet
} rpt_err]} {
    puts "WARNING: Could not write impl timing report: $rpt_err"
} else {
    puts "INFO: Impl timing report:      ${RPTS}/step28c_timing_summary.rpt"
}

if {[catch {
    report_drc \
        -file ${RPTS}/step28c_drc.rpt \
        -quiet
} rpt_err]} {
    puts "WARNING: Could not write DRC report: $rpt_err"
} else {
    puts "INFO: DRC report:              ${RPTS}/step28c_drc.rpt"
}

if {[catch {
    report_power \
        -file ${RPTS}/step28c_power.rpt \
        -quiet
} rpt_err]} {
    puts "WARNING: Could not write power report: $rpt_err"
} else {
    puts "INFO: Power report:            ${RPTS}/step28c_power.rpt"
}

puts ""

# -------------------------------------------------------------------------
# Timing gate
# -------------------------------------------------------------------------
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
        puts "ERROR: Setup timing violated. WNS = $wns_val ns"
        set timing_ok 0
    }
} else {
    puts "WARNING: No setup timing paths found."
}

if {[llength $hold_paths] > 0} {
    set whs_val [get_property SLACK [lindex $hold_paths 0]]
    puts "INFO: WHS (hold)  = $whs_val ns"

    if {$whs_val < 0} {
        puts "ERROR: Hold timing violated. WHS = $whs_val ns"
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

puts ""

# -------------------------------------------------------------------------
# Export embedded-bitstream XSA
# -------------------------------------------------------------------------
puts "--- Exporting XSA with embedded bitstream ---"
puts "    write_hw_platform -fixed -include_bit -force -file $XSA_WITH_BIT"

if {[catch {
    write_hw_platform \
        -fixed       \
        -include_bit \
        -force       \
        -file $XSA_WITH_BIT
} xsa_err]} {
    puts "ERROR: Embedded-bitstream XSA export failed:"
    puts "       $xsa_err"
    puts ""
    puts "Do NOT fall back to no-bit XSA in Step 28C."
    puts "This step is specifically for embedded-bitstream export."
    exit 1
}

puts "INFO: XSA written: $XSA_WITH_BIT"

if {![file exists $XSA_WITH_BIT]} {
    puts "ERROR: XSA file not found after export: $XSA_WITH_BIT"
    puts "       write_hw_platform did not raise an error but the file is missing."
    exit 1
}

puts "INFO: XSA file verified: $XSA_WITH_BIT"
puts ""

# -------------------------------------------------------------------------
# Final summary
# -------------------------------------------------------------------------
puts "========================================================"
puts "Step 28C COMPLETE."
puts ""
puts "XSA with embedded bitstream:"
puts "  $XSA_WITH_BIT"
puts ""
puts "Implementation-run bitstream:"
puts "  $RUN_BIT_FILE"
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
puts "Recommended Vitis platform input:"
puts "  $XSA_WITH_BIT"
puts ""
puts "No ILA, no DMA, no RTL changes in this script."
puts "========================================================"

exit 0