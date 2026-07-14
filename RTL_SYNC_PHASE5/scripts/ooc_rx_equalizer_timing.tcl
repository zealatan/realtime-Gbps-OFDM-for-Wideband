# =====================================================================
# ooc_rx_equalizer_timing.tcl — OOC synth + Fmax for the ZF equalizer
# Target: xczu49dr-ffvf1760-2-e. Run from repo root:
#   vivado -mode batch -source scripts/ooc_rx_equalizer_timing.tcl -tclargs <period_ns>
# Fmax = 1000 / (period - WNS).
# =====================================================================
set part   xczu49dr-ffvf1760-2-e
set per    2.0
if {$argc >= 1} { set per [lindex $argv 0] }

set rtldir [file normalize [file join [pwd] rtl]]
set outdir [file normalize [file join [pwd] sim_out/ooc_rx_eq]]
file mkdir $outdir

read_verilog [file join $rtldir rx_eq_complex_div.v]
read_verilog [file join $rtldir rx_equalizer.v]
set_property include_dirs $rtldir [current_fileset]

synth_design -top rx_equalizer -part $part -mode out_of_context -no_iobuf \
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
report_utilization      -file [file join $outdir util.rpt]
report_timing_summary   -file [file join $outdir tsum.rpt]
report_timing -max_paths 3 -file [file join $outdir paths.rpt]
puts "DONE"
