# =============================================================================
# step28_build_bitstream_xsa.tcl
# Step 28: ZCU102 Synthesis, Implementation, Bitstream, and XSA Export
#          for Phase-1 OFDM synchronizer bring-up system.
#
# Opens the Step 27 Vivado block design project and runs:
#   synthesis → implementation → timing check → bitstream → XSA export
#
# No ILA, No DMA, No VIO, No FFT, No integer CFO.
#
# Run from Windows Vivado 2022.2 batch mode, from C:\RTL_SYNC:
#   C:\Xilinx\Vivado\2022.2\bin\vivado.bat -mode batch ^
#       -source scripts/vivado/step28_build_bitstream_xsa.tcl
#
# Outputs:
#   outputs/step28/sync_phase1_bd_wrapper.bit
#   outputs/step28/sync_phase1_bd_wrapper.xsa
#   reports/step28/step28_synth_utilization.rpt
#   reports/step28/step28_synth_timing_summary.rpt
#   reports/step28/step28_impl_utilization.rpt
#   reports/step28/step28_timing_summary.rpt
#   reports/step28/step28_drc.rpt
#   reports/step28/step28_power.rpt
# =============================================================================

set PROJ_FILE    "vivado/step27_zcu102_bd/step27_zcu102_bd.xpr"
set BD_TOP       "sync_phase1_bd_wrapper"
set RPTS         "reports/step28"
set OUT          "outputs/step28"
set BIT_FILE     "${OUT}/sync_phase1_bd_wrapper.bit"
set XSA_FILE     "${OUT}/sync_phase1_bd_wrapper.xsa"

puts "========================================================"
puts "Step 28: ZCU102 Synthesis + Implementation + Bitstream + XSA"
puts "Project: $PROJ_FILE"
puts "Top:     $BD_TOP"
puts "Outputs: $OUT"
puts "No ILA | No DMA | No integer CFO"
puts "========================================================"

file mkdir $RPTS
file mkdir $OUT

# =============================================================================
# Open Step 27 project
# =============================================================================
if {![file exists $PROJ_FILE]} {
    puts "ERROR: Step 27 project not found: $PROJ_FILE"
    puts "       Run scripts/vivado/step27_create_zcu102_bd_no_ila.tcl first."
    exit 1
}

puts ""
puts "--- Opening Step 27 Vivado project ---"
open_project $PROJ_FILE

# Verify top module
set cur_top [get_property TOP [get_fileset sources_1]]
puts "INFO: Current top: $cur_top"
if {$cur_top ne $BD_TOP} {
    puts "WARNING: Top is '$cur_top', expected '$BD_TOP'."
    puts "         Attempting to set top to $BD_TOP..."
    if {[catch {set_property TOP $BD_TOP [get_fileset sources_1]} t_err]} {
        puts "ERROR: Could not set top: $t_err"
        exit 1
    }
    puts "INFO: Top set to $BD_TOP."
}

# =============================================================================
# Reset prior runs to make script idempotent
# =============================================================================
puts ""
puts "--- Checking prior run state ---"
set synth_status [get_property STATUS [get_runs synth_1]]
set impl_status  [get_property STATUS [get_runs impl_1]]
puts "INFO: synth_1 status: $synth_status"
puts "INFO: impl_1  status: $impl_status"

if {$synth_status ne "Not started"} {
    puts "INFO: Resetting impl_1..."
    catch {reset_run impl_1}
    puts "INFO: Resetting synth_1..."
    catch {reset_run synth_1}
    puts "INFO: Runs reset."
}

# =============================================================================
# SYNTHESIS
# =============================================================================
puts ""
puts "--- Launching synthesis (synth_1) ---"
launch_runs synth_1 -jobs 4
wait_on_run synth_1

set synth_status [get_property STATUS [get_runs synth_1]]
puts "INFO: synth_1 finished with status: $synth_status"
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    puts "ERROR: Synthesis did not complete (progress != 100%)."
    exit 1
}
if {[string match "*fail*" [string tolower $synth_status]]} {
    puts "ERROR: Synthesis failed: $synth_status"
    exit 1
}
puts "INFO: Synthesis COMPLETE."

# Open synthesized design and generate reports
puts "INFO: Opening synthesized design..."
open_run synth_1 -name synth_1

puts "INFO: Generating synthesis utilization report..."
report_utilization \
    -file ${RPTS}/step28_synth_utilization.rpt \
    -quiet

puts "INFO: Generating synthesis timing summary..."
report_timing_summary \
    -delay_type min_max \
    -report_unconstrained \
    -check_timing_verbose \
    -max_paths 10 \
    -input_pins \
    -file ${RPTS}/step28_synth_timing_summary.rpt \
    -quiet

puts "INFO: Synthesis reports written to $RPTS."

# =============================================================================
# IMPLEMENTATION
# =============================================================================
puts ""
puts "--- Launching implementation (impl_1) ---"
launch_runs impl_1 -jobs 4
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
puts "INFO: impl_1 finished with status: $impl_status"
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    puts "ERROR: Implementation did not complete (progress != 100%)."
    exit 1
}
if {[string match "*fail*" [string tolower $impl_status]]} {
    puts "ERROR: Implementation failed: $impl_status"
    exit 1
}
puts "INFO: Implementation COMPLETE."

# Open implemented design and generate reports
puts "INFO: Opening implemented design..."
open_run impl_1 -name impl_1

puts "INFO: Generating implementation utilization report..."
report_utilization \
    -file ${RPTS}/step28_impl_utilization.rpt \
    -quiet

puts "INFO: Generating implementation timing summary..."
report_timing_summary \
    -delay_type min_max \
    -report_unconstrained \
    -check_timing_verbose \
    -max_paths 10 \
    -input_pins \
    -file ${RPTS}/step28_timing_summary.rpt \
    -quiet

puts "INFO: Generating DRC report..."
report_drc \
    -file ${RPTS}/step28_drc.rpt \
    -quiet

puts "INFO: Generating power report..."
report_power \
    -file ${RPTS}/step28_power.rpt \
    -quiet

puts "INFO: Implementation reports written to $RPTS."

# =============================================================================
# TIMING CHECK
# =============================================================================
puts ""
puts "--- Checking timing ---"
set setup_paths [get_timing_paths -max_paths 1 -nworst 1 -setup -quiet]
set hold_paths  [get_timing_paths -max_paths 1 -nworst 1 -hold  -quiet]

set timing_ok 1

if {[llength $setup_paths] > 0} {
    set wns [get_property SLACK [lindex $setup_paths 0]]
    puts "INFO: WNS (setup) = $wns ns"
    if {$wns < 0} {
        puts "ERROR: Setup timing violated (WNS = $wns ns)"
        set timing_ok 0
    }
} else {
    puts "WARNING: No setup timing paths found (unconstrained design?)."
}

if {[llength $hold_paths] > 0} {
    set whs [get_property SLACK [lindex $hold_paths 0]]
    puts "INFO: WHS (hold) = $whs ns"
    if {$whs < 0} {
        puts "ERROR: Hold timing violated (WHS = $whs ns)"
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
    puts "Timing violations found. Bitstream generation will be skipped."
    exit 1
}

# =============================================================================
# BITSTREAM
# =============================================================================
puts ""
puts "--- Writing bitstream ---"
if {[catch {
    write_bitstream -force $BIT_FILE
    puts "INFO: Bitstream written: $BIT_FILE"
} bit_err]} {
    puts "ERROR: write_bitstream failed: $bit_err"
    exit 1
}

# =============================================================================
# XSA EXPORT
# =============================================================================
puts ""
puts "--- Exporting hardware platform (XSA) ---"
# write_hw_platform requires the implemented design to be open and the bitstream
# to have been written.  -include_bit embeds the bitstream into the XSA so that
# Vitis can program the device without a separate .bit file.
# Vivado 2022.2 syntax: write_hw_platform -fixed -include_bit -force -file <path>
if {[catch {
    write_hw_platform \
        -fixed      \
        -include_bit \
        -force      \
        -file $XSA_FILE
    puts "INFO: XSA written: $XSA_FILE"
} xsa_err]} {
    puts "ERROR: write_hw_platform failed: $xsa_err"
    puts "       Trying without -include_bit..."
    if {[catch {
        write_hw_platform -fixed -force -file $XSA_FILE
        puts "INFO: XSA written (without embedded bitstream): $XSA_FILE"
    } xsa_err2]} {
        puts "ERROR: write_hw_platform failed again: $xsa_err2"
        exit 1
    }
}

# =============================================================================
# Done
# =============================================================================
puts ""
puts "========================================================"
puts "Step 28 COMPLETE."
puts ""
puts "Bitstream: $BIT_FILE"
puts "XSA:       $XSA_FILE"
puts ""
puts "Reports:"
puts "  Synth utilization: ${RPTS}/step28_synth_utilization.rpt"
puts "  Synth timing:      ${RPTS}/step28_synth_timing_summary.rpt"
puts "  Impl utilization:  ${RPTS}/step28_impl_utilization.rpt"
puts "  Impl timing:       ${RPTS}/step28_timing_summary.rpt"
puts "  DRC:               ${RPTS}/step28_drc.rpt"
puts "  Power:             ${RPTS}/step28_power.rpt"
puts ""
puts "No ILA, no DMA, no integer CFO, no Vitis firmware in this step."
puts "RTL not modified."
puts ""
puts "Timing: $wns ns WNS (setup)"
puts ""
puts "Step 29: Vitis baremetal C application for known-vector test"
puts "  Base address: 0xA0000000"
puts "  Open XSA in Vitis 2022.2, create baremetal Hello World, replace main()"
puts "========================================================"

exit 0
