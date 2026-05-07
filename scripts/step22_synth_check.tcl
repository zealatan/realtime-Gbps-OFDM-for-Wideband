set TOP   frac_cfo_frame_corrector_top
set PART  xczu9eg-ffvb1156-2-e
set RTL   rtl
set STUBS scripts/synth_stubs
set RPTS  reports

puts "========================================================"
puts "Step 22 OOC Synthesis: $TOP on $PART"
puts "========================================================"

file mkdir $RPTS

create_project synth_step22 ./build/step22_synth -part $PART -force
set_property default_lib work [current_project]

puts "INFO: Reading synthesizable RTL sources..."
read_verilog -sv [list \
    $RTL/axis_complex_mult.v \
    $RTL/complex_mult_iq.v \
    $RTL/complex_rotator.v \
    $RTL/iq_frame_buffer.v \
    $RTL/frame_detector.v \
    $RTL/cp_autocorr_core.v \
    $RTL/timing_metric_core.v \
    $RTL/peak_detector.v \
    $RTL/frac_cfo_estimator.v \
    $RTL/frac_cfo_corrector_top.v \
    $RTL/timing_sync_top.v \
    $RTL/timing_frac_cfo_top.v \
    $RTL/frac_cfo_frame_corrector_top.v \
]

puts "INFO: Reading synthesis stubs..."
read_verilog -sv [list \
    $STUBS/cordic_atan2_stub.v \
    $STUBS/nco_phase_gen_stub.v \
]

update_compile_order -fileset sources_1

puts "INFO: Running synthesis..."
synth_design -top $TOP -part $PART -mode out_of_context

puts "INFO: Applying 100 MHz clock constraint on aclk..."
create_clock -period 10.000 [get_ports aclk]

puts "INFO: Writing reports..."
report_utilization -file $RPTS/step22_synth_utilization.rpt
report_timing_summary -file $RPTS/step22_timing_summary.rpt
report_drc -file $RPTS/step22_drc.rpt

puts "========================================================"
puts "Step 22 synthesis completed successfully."
puts "Reports written under $RPTS"
puts "========================================================"

exit 0
