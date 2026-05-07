set TOP   frac_cfo_frame_corrector_top
set PART  xczu9eg-ffvb1156-2-e
set RTL   rtl
set RPTS  reports

puts "========================================================"
puts "Step 24 OOC Synthesis (no stubs): $TOP on $PART"
puts "========================================================"

file mkdir $RPTS

create_project synth_step24 ./build/step24_synth -part $PART -force
set_property default_lib work [current_project]

puts "INFO: Reading real RTL sources (no synthesis stubs)..."
read_verilog -sv [list \
    $RTL/axis_complex_mult.v \
    $RTL/complex_mult_iq.v \
    $RTL/complex_rotator.v \
    $RTL/iq_frame_buffer.v \
    $RTL/frame_detector.v \
    $RTL/cp_autocorr_core.v \
    $RTL/timing_metric_core.v \
    $RTL/peak_detector.v \
    $RTL/cordic_atan2.v \
    $RTL/frac_cfo_estimator.v \
    $RTL/nco_phase_gen.v \
    $RTL/frac_cfo_corrector_top.v \
    $RTL/timing_sync_top.v \
    $RTL/timing_frac_cfo_top.v \
    $RTL/frac_cfo_frame_corrector_top.v \
]

puts "INFO: No synthesis stubs loaded. cordic_atan2 and nco_phase_gen are real RTL."

update_compile_order -fileset sources_1

puts "INFO: Running synthesis..."
synth_design -top $TOP -part $PART -mode out_of_context

puts "INFO: Applying 100 MHz clock constraint on aclk..."
create_clock -period 10.000 [get_ports aclk]

puts "INFO: Writing reports..."
report_utilization    -file $RPTS/step24_synth_utilization.rpt
report_timing_summary -file $RPTS/step24_timing_summary.rpt
report_drc            -file $RPTS/step24_drc.rpt

puts "INFO: Checking for blackbox cells..."
set bbox_cells [get_cells -hierarchical -filter {BLACK_BOX == 1}]
if {[llength $bbox_cells] == 0} {
    puts "BLACKBOX CHECK: PASS — no blackbox cells found."
} else {
    puts "BLACKBOX CHECK: WARNING — [llength $bbox_cells] blackbox cell(s) found:"
    foreach c $bbox_cells {
        puts "  $c"
    }
}

puts "========================================================"
puts "Step 24 synthesis completed successfully."
puts "Reports written under $RPTS"
puts "========================================================"

exit 0
