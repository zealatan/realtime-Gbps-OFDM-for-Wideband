set part xczu9eg-ffvb1156-2-e
create_project -in_memory -part $part
set_property target_language Verilog [current_project]
file mkdir reports
add_files -norecurse [glob rtl/meyr_*.v rtl/complex_mult*.v]
foreach x {xfft_N xfft_2N xfft_IFFT} {
  set h [glob -nocomplain rtl/$x/$x.xci ip/$x/$x.xci]
  if {[llength $h]} {
    read_ip [lindex $h 0]
    upgrade_ip -quiet [get_ips $x]
    generate_target synthesis [get_ips $x]
    synth_ip [get_ips $x]
    puts "==> IP $x retargeted to $part"
  }
}
synth_design -top meyr_cfo_top -part $part -mode out_of_context
create_clock -name clk -period 4.000 [get_ports clk]
report_timing_summary -delay_type max -file reports/p5_meyr_cfo_top_ooc_timing.rpt
report_utilization -file reports/p5_meyr_cfo_top_ooc_util.rpt
set wns [get_property SLACK [get_timing_paths -delay_type max]]
puts "OOC meyr_cfo_top: WNS=$wns ns => Fmax ~ [expr {1000.0/(4.0-$wns)}] MHz"
puts "OOC SYNTH DONE"
