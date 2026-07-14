# OOC synth of rx_fft_frontend to estimate the WRAPPER logic Fmax on the
# locked ZCU216 RF part. The xfft_N IP is a black box here (its own OOC
# Fmax is >300 MHz on this part), so this measures the symbol-extract FSM
# + BFP-recover + fftshift datapath critical path only.
set part xczu49dr-ffvf1760-2-e
create_project -in_memory -part $part
set_property target_language Verilog [current_project]
file mkdir reports

# Black-box stub for the IP so synth treats it as a boundary.
set bb reports/xfft_N_bb.v
set fh [open $bb w]
puts $fh "(* black_box *) module xfft_N (
  input aclk, input aresetn,
  input s_axis_config_tvalid, output s_axis_config_tready, input \[7:0\] s_axis_config_tdata,
  input s_axis_data_tvalid, output s_axis_data_tready, input \[31:0\] s_axis_data_tdata, input s_axis_data_tlast,
  output m_axis_data_tvalid, input m_axis_data_tready, output \[31:0\] m_axis_data_tdata, output m_axis_data_tlast, output \[7:0\] m_axis_data_tuser,
  input m_axis_status_tready,
  output event_frame_started, output event_tlast_unexpected, output event_tlast_missing,
  output event_status_channel_halt, output event_data_in_channel_halt, output event_data_out_channel_halt
); endmodule"
close $fh

add_files -norecurse [list rtl/rx_fft_frontend.v $bb]
synth_design -top rx_fft_frontend -part $part -mode out_of_context
create_clock -name clk -period 4.000 [get_ports clk]
report_timing_summary -delay_type max -file reports/rx_fft_frontend_ooc_timing.rpt
report_utilization -file reports/rx_fft_frontend_ooc_util.rpt
set wns [get_property SLACK [get_timing_paths -delay_type max]]
puts "OOC rx_fft_frontend: WNS=$wns ns @250MHz => Fmax ~ [expr {1000.0/(4.0-$wns)}] MHz"
puts "OOC SYNTH DONE"
