# p5_09_util_power.tcl — P3 E3+E4: utilization + power on post-route.

if {![file exists reports/p5_06_post_route.dcp]} {
    puts "P5_09_GATE: BLOCKED · reports/p5_06_post_route.dcp missing"
    exit 1
}

open_checkpoint reports/p5_06_post_route.dcp

# Utilization
report_utilization -hierarchical -hierarchical_depth 4 \
    -file reports/p5_09_util_hier.rpt
report_utilization -file reports/p5_09_util_flat.rpt

# Power estimation
report_power -file reports/p5_09_power.rpt

# Top-level summary numbers — extract for dashboard
set util_fp [open reports/p5_09_util_flat.rpt r]
set util_txt [read $util_fp]; close $util_fp

# Extract DSP / BRAM / LUT / FF percentages
regexp -line {DSPs\s+\|\s+(\d+)\s+\|.+?\|.+?\|\s+([0-9.]+)} $util_txt _ dsp_n dsp_pct
regexp -line {Block RAM Tile\s+\|\s+([0-9.]+)\s+\|.+?\|.+?\|\s+([0-9.]+)} $util_txt _ bram_n bram_pct
regexp -line {CLB LUTs\s+\|\s+(\d+)\s+\|.+?\|.+?\|\s+([0-9.]+)} $util_txt _ lut_n lut_pct
regexp -line {CLB Registers\s+\|\s+(\d+)\s+\|.+?\|.+?\|\s+([0-9.]+)} $util_txt _ ff_n ff_pct

# Power: extract total
set pow_fp [open reports/p5_09_power.rpt r]
set pow_txt [read $pow_fp]; close $pow_fp
set total_power "unknown"
regexp -line {Total On-Chip Power \(W\)\s+\|\s+([0-9.]+)} $pow_txt _ total_power

set fh [open reports/p5_09_summary.txt w]
puts $fh "# P5-09 utilization + power summary"
puts $fh "LUT: $lut_n  (${lut_pct}%)"
puts $fh "FF:  $ff_n  (${ff_pct}%)"
puts $fh "DSP: $dsp_n (${dsp_pct}%)"
puts $fh "BRAM: $bram_n (${bram_pct}%)"
puts $fh "Power_W: $total_power"
close $fh
puts "P5_09_UTIL_POWER: OK"
