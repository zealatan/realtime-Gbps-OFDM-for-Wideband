# S2 build: regenerate BD outputs, synth + impl + bitstream, export XSA.
set proj hardware/generated/09_pl_bypass/zcu216_rfdc_capture.xpr
open_project $proj
generate_target all [get_files system.bd]
reset_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
puts "S2_BUILD: impl_1 status=[get_property STATUS [get_runs impl_1]] progress=[get_property PROGRESS [get_runs impl_1]]"
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    puts "S2_BUILD: BUILD_FAILED"
} else {
    write_hw_platform -fixed -include_bit -force hardware/generated/09_pl_bypass/zcu216_pl_bypass.xsa
    puts "S2_BUILD: XSA=[file normalize hardware/generated/09_pl_bypass/zcu216_pl_bypass.xsa]"
    puts "S2_BUILD: BITSTREAM=[glob -nocomplain hardware/generated/09_pl_bypass/zcu216_rfdc_capture.runs/impl_1/*.bit]"
    puts "S2_BUILD: BUILD_OK"
}
puts "S2_BUILD: DONE"
