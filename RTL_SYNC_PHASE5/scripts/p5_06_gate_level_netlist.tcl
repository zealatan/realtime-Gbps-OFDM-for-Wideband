# p5_06_gate_level_netlist.tcl
# Full implementation + post-route gate-level netlist + SDF for
# timing-accurate gate-level simulation.
#
# Outputs:
#   reports/p5_06_post_route.dcp           - post-route checkpoint
#   sim_out/gate_level/phase3_*_netlist.v  - structural Verilog
#   sim_out/gate_level/phase3_*.sdf        - SDF timing back-annotation
#   reports/p5_06_fulldesign_timing.rpt    - timing summary (sanity)

set part xczu9eg-ffvb1156-2-e
create_project -in_memory -part $part p5_06_gate
set_property target_language Verilog [current_project]
file mkdir reports
file mkdir sim_out/gate_level

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
add_files -norecurse [glob rtl/*.v]
read_xdc scripts/p5_04_fulldesign_timing.xdc

# ---- Synth + impl ----
synth_design -top phase3_sync_axis_dma_wrapper -part $part
opt_design
place_design
phys_opt_design
route_design
write_checkpoint -force reports/p5_06_post_route.dcp

report_timing_summary -delay_type max \
    -file reports/p5_06_fulldesign_timing.rpt

set wns [get_property SLACK [get_timing_paths -delay_type max]]
puts "GATE_LEVEL_BASELINE_WNS=$wns ns"

# ---- Gate-level netlist + SDF ----
# Mode "timesim" emits structural netlist suitable for SDF back-annotation.
write_verilog -mode timesim -force \
    -sdf_anno true \
    -sdf_file sim_out/gate_level/phase3_wrapper.sdf \
    sim_out/gate_level/phase3_wrapper_netlist.v
write_sdf -mode timesim -force \
    sim_out/gate_level/phase3_wrapper.sdf

# Also emit funcsim netlist for a no-SDF sanity comparison
write_verilog -mode funcsim -force \
    sim_out/gate_level/phase3_wrapper_funcsim.v

puts "P5_06_GATE_LEVEL_DONE"
