# p5_04_internal_timing.tcl
# Re-analyze the routed checkpoint with internal-only path filtering
# to get a meaningful register-to-register WNS (excluding the
# OOC output_delay artifact where the destination clock has no
# tree delay).

open_checkpoint reports/p5_04_post_route.dcp

# Per-category timing summary
report_timing_summary -delay_type max -file reports/p5_04_internal_summary.rpt

# Internal-only paths (register-to-register, no I/O endpoints)
report_timing -from [all_registers] -to [all_registers] \
    -delay_type max -max_paths 10 -nworst 1 \
    -file reports/p5_04_internal_top10.rpt

set wns_int [get_property SLACK \
    [lindex [get_timing_paths -from [all_registers] -to [all_registers] \
                              -delay_type max -max_paths 1] 0]]
puts "INTERNAL_REG2REG_WNS=$wns_int ns"

# Also report I/O ports separately so we know it really was the
# output_delay constraint that drove the -3.000 ns
set wns_out [get_property SLACK \
    [lindex [get_timing_paths -to [all_outputs] -delay_type max -max_paths 1] 0]]
puts "REG2OUT_WNS=$wns_out ns"

puts "P5_04_INTERNAL_DONE"
