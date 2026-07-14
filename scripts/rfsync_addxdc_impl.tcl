# RF 6c-2: register rfsync_clocks.xdc (async clock groups pl_clk0/pl_clk1) and
# re-run implementation only (netlist unchanged; clock_groups removes the
# spurious pl_clk0<->pl_clk1 cross-domain setup violations).
set REPO /home/dsp-mikro7/FPGA_Based_OFDM_Transceiver
set XPR  $REPO/hardware/generated/08_rfdc_capture/zcu216_rfdc_capture.xpr
set XDC  $REPO/hardware/rtl/rfsync_clocks.xdc
proc fail {m} { puts "RFSYNC_XDC: FAIL $m"; exit 1 }

open_project $XPR
if {[get_files -quiet $XDC] eq ""} {
    add_files -fileset constrs_1 -norecurse $XDC
    puts "RFSYNC_XDC: added $XDC to constrs_1"
}
set_property used_in_synthesis false [get_files $XDC]
set_property used_in_implementation true [get_files $XDC]

# Netlist unchanged -> only re-run impl from the existing synth_1 checkpoint.
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
set ip [get_property PROGRESS [get_runs impl_1]]
set is [get_property STATUS   [get_runs impl_1]]
puts "RFSYNC_XDC: impl_1 progress=$ip status=$is"
if {$ip ne "100%"} { fail "impl_1 ($is)" }

set wns [get_property STATS.WNS [get_runs impl_1]]
set whs [get_property STATS.WHS [get_runs impl_1]]
set tns [get_property STATS.TNS [get_runs impl_1]]
set ths [get_property STATS.THS [get_runs impl_1]]
if {$wns >= 0 && $whs >= 0} {
    puts "RFSYNC_XDC: Timing MET (WNS=$wns WHS=$whs TNS=$tns THS=$ths)"
} else {
    puts "RFSYNC_XDC: Timing VIOLATED (WNS=$wns WHS=$whs TNS=$tns THS=$ths)"
}
set impl_dir [get_property DIRECTORY [get_runs impl_1]]
foreach b [glob -nocomplain $impl_dir/*.bit] { set bit $b }
puts "RFSYNC_XDC: DONE bitstream=$bit"
exit 0
