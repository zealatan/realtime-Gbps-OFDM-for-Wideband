# p5_04_fulldesign_timing.tcl
# Full implementation (synth -> opt -> place -> route) of
# phase3_sync_axis_dma_wrapper @ 250 MHz on xczu9eg.
# Emits post-route timing + check_timing + utilization reports.

set part xczu9eg-ffvb1156-2-e
create_project -in_memory -part $part p5_04_fulldesign
set_property target_language Verilog [current_project]
file mkdir reports

# ---- IPs ----
foreach x {xfft_N xfft_2N xfft_IFFT} {
    set h [glob -nocomplain rtl/$x/$x.xci ip/$x/$x.xci]
    if {[llength $h]} {
        read_ip [lindex $h 0]
        catch {set_property IS_LOCKED false [get_ips $x]}
        upgrade_ip -quiet [get_ips $x]
        generate_target synthesis [get_ips $x]
        synth_ip [get_ips $x]
        puts "==> IP $x: ready"
    }
}

# ---- RTL ----
# Include every .v under rtl/ (rtl/DUT subdir has the legacy variants;
# include the top-level rtl/*.v only — that's the live P5 tree).
add_files -norecurse [glob rtl/*.v]

# ---- XDC ----
read_xdc scripts/p5_04_fulldesign_timing.xdc

# ---- Synth (top = wrapper) ----
synth_design -top phase3_sync_axis_dma_wrapper -part $part
write_checkpoint -force reports/p5_04_post_synth.dcp

# ---- Implementation ----
opt_design
place_design
phys_opt_design
route_design
write_checkpoint -force reports/p5_04_post_route.dcp

# ---- Reports ----
report_timing_summary -delay_type max -max_paths 20 \
    -file reports/p5_04_fulldesign_timing.rpt
check_timing -file reports/p5_04_checktiming.rpt
report_utilization -hierarchical -file reports/p5_04_fulldesign_util.rpt

set wns [get_property SLACK [get_timing_paths -delay_type max]]
puts "FULL_DESIGN_WNS=$wns ns"
if {$wns ne "" && [string is double -strict $wns]} {
    set fmax [expr {1000.0 / (4.0 - $wns)}]
    puts "FULL_DESIGN_FMAX=[format %.1f $fmax] MHz"
} else {
    puts "FULL_DESIGN_FMAX=UNKNOWN"
}

# Top critical paths for triage
report_timing -delay_type max -max_paths 5 \
    -file reports/p5_04_top5_paths.rpt -nworst 5

puts "P5_04_FULLDESIGN_DONE"
