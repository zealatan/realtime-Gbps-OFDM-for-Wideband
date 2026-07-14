# =====================================================================
# ooc_rx_downstream_top_timing.tcl
#   OOC synth + Fmax for the integrated rx_downstream_top.
#   Target: xczu49dr-ffvf1760-2-e. Run from repo root:
#     vivado -mode batch -source scripts/ooc_rx_downstream_top_timing.tcl -tclargs <period_ns>
#
#   xfft_N is treated as a BLACK BOX here (the real IP closes >300 MHz OOC
#   on this part and is NOT on this wrapper's added critical path). This
#   measurement isolates the integration glue + the 4 downstream modules'
#   logic, to confirm the added align buffer / data-carrier gate / counters
#   do NOT degrade the min-Fmax module (equalizer ~268 MHz).
#
#   Fmax = 1000 / (period - WNS).
# =====================================================================
set part   xczu49dr-ffvf1760-2-e
set per    3.73   ;# ~268 MHz target (equalizer min Fmax)
if {$argc >= 1} { set per [lindex $argv 0] }

set rtldir [file normalize [file join [pwd] rtl]]
set outdir [file normalize [file join [pwd] sim_out/ooc_rx_ds_top]]
file mkdir $outdir

# xfft_N synthesizable REGISTERED stub: the real IP closes >300 MHz OOC and is
# NOT on this wrapper's added critical path. A registered passthrough lets the
# tool place/route the WRAPPER logic (align buffer + data gate + the 4 modules)
# so we measure whether the INTEGRATION GLUE degrades Fmax. The stub's own I/O
# is registered so it never creates an artificial cross-module comb path.
set bb [file join $outdir xfft_N_stub.v]
set fh [open $bb w]
puts $fh "module xfft_N ("
puts $fh "  input aclk, input aresetn,"
puts $fh "  input s_axis_config_tvalid, output s_axis_config_tready, input \[7:0\] s_axis_config_tdata,"
puts $fh "  input s_axis_data_tvalid, output s_axis_data_tready, input \[31:0\] s_axis_data_tdata, input s_axis_data_tlast,"
puts $fh "  output reg m_axis_data_tvalid, input m_axis_data_tready, output reg \[31:0\] m_axis_data_tdata, output reg m_axis_data_tlast, output reg \[7:0\] m_axis_data_tuser,"
puts $fh "  input m_axis_status_tready,"
puts $fh "  output event_frame_started, output event_tlast_unexpected, output event_tlast_missing,"
puts $fh "  output event_status_channel_halt, output event_data_in_channel_halt, output event_data_out_channel_halt"
puts $fh ");"
puts $fh "  assign s_axis_config_tready=1'b1; assign s_axis_data_tready=m_axis_data_tready;"
puts $fh "  assign {event_frame_started,event_tlast_unexpected,event_tlast_missing,event_status_channel_halt,event_data_in_channel_halt,event_data_out_channel_halt}=6'b0;"
puts $fh "  always @(posedge aclk) begin"
puts $fh "    m_axis_data_tvalid<=s_axis_data_tvalid; m_axis_data_tdata<=s_axis_data_tdata;"
puts $fh "    m_axis_data_tlast<=s_axis_data_tlast; m_axis_data_tuser<=8'd2;"
puts $fh "  end"
puts $fh "endmodule"
close $fh
read_verilog $bb

# the 5 downstream RTL modules (xfft_N left as black box)
read_verilog [file join $rtldir rx_eq_complex_div.v]
read_verilog [file join $rtldir rx_equalizer.v]
read_verilog [file join $rtldir rx_demod_16qam.v]
read_verilog [file join $rtldir rx_ch_est.v]
read_verilog [file join $rtldir rx_fft_frontend.v]
read_verilog [file join $rtldir rx_downstream_top.v]
set_property include_dirs $rtldir [current_fileset]

synth_design -top rx_downstream_top -part $part -mode out_of_context -no_iobuf \
             -flatten_hierarchy rebuilt
create_clock -name clk -period $per [get_ports clk]
set_input_delay  -clock clk [expr {$per*0.15}] [all_inputs]
set_output_delay -clock clk [expr {$per*0.15}] [all_outputs]
set_false_path -from [get_ports rst_n]

opt_design
place_design
phys_opt_design
route_design

set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
set fmax [expr {1000.0/($per - $wns)}]
puts "============================================================"
puts "TIMING_RESULT part=$part period=${per}ns WNS=${wns}ns  FMAX=${fmax}MHz"
puts "============================================================"
report_utilization    -file [file join $outdir util.rpt]
report_timing_summary -file [file join $outdir tsum.rpt]
report_timing -max_paths 5 -file [file join $outdir paths.rpt]
puts "DONE"
