# OOC synth of rx_ch_est (CE + interp_fft) on the locked ZCU216 RF part, to
# measure Fmax of the CE-divide + 32-wide complex MAC adder-tree datapath.
# No IP: the interp_fft is the fused 256x32 W-matrix MAC (coeff ROM only).
set part xczu49dr-ffvf1760-2-e
create_project -in_memory -part $part
set_property target_language Verilog [current_project]
file mkdir reports

add_files -norecurse rtl/rx_ch_est.v
# coeff ROM is read via $readmemh at elaboration; point it at the repo copy.
set_property generic {W_ROM=rtl/rx_ch_est_rom/ce_interp_W.hex} [current_fileset]

synth_design -top rx_ch_est -part $part -mode out_of_context
create_clock -name clk -period 4.000 [get_ports clk]
report_timing_summary -delay_type max -file reports/rx_ch_est_ooc_timing.rpt
report_utilization -file reports/rx_ch_est_ooc_util.rpt
set paths [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
set wns [get_property SLACK $paths]
puts "OOC rx_ch_est: WNS=$wns ns @250MHz (4.0ns) => Fmax ~ [expr {1000.0/(4.0-$wns)}] MHz"
puts "OOC SYNTH DONE"
