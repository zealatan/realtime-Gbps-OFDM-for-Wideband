# syn_rx_demod_16qam_fmax.tcl
# OOC synth of rx_demod_16qam on target part, binary-search the min clock
# period (max Fmax) via a tight constraint + WNS read-back.
set part xczu49dr-ffvf1760-2-e
set rtl  [file normalize [file join [pwd] rtl/rx_demod_16qam.v]]

read_verilog $rtl
# aggressive target period (ns) to push Fmax; report WNS to derive actual.
set period 1.0
synth_design -top rx_demod_16qam -part $part -mode out_of_context
create_clock -name clk -period $period [get_ports clk]
# realistic IO budget so the comparator->reg path is what's measured
set_input_delay  -clock clk 0.2 [all_inputs]
set_output_delay -clock clk 0.2 [all_outputs]
opt_design
place_design
route_design

set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
set achieved [expr {$period - $wns}]
set fmax [expr {1000.0 / $achieved}]
puts "============================================================"
puts "FMAX_REPORT part=$part target_period=${period}ns"
puts "FMAX_REPORT WNS=${wns} ns"
puts "FMAX_REPORT achieved_period=${achieved} ns"
puts "FMAX_REPORT FMAX=${fmax} MHz"
puts "============================================================"
report_utilization
