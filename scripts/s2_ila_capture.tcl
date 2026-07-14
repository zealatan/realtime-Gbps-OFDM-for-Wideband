# Attach to the already-programmed/running ZCU216 (xsct programmed the 09
# bitstream + ran the ELF, leaving the DMA stalled), refresh the ILA, trigger
# immediately to sample the stuck M_AXI_S2MM (AW/W/B) and input-stream levels,
# and dump to CSV. Do NOT reprogram — just observe the stuck state.
open_hw_manager
connect_hw_server -url localhost:3121
open_hw_target

set dev ""
foreach d [get_hw_devices] { if {[string match -nocase *zu* $d]} { set dev $d } }
if {$dev eq ""} { set dev [lindex [get_hw_devices] end] }
current_hw_device $dev
puts "S2_ILA: device = $dev"

set ltx [lindex [glob -nocomplain hardware/generated/09_pl_bypass/zcu216_rfdc_capture.runs/impl_1/*.ltx] 0]
puts "S2_ILA: ltx = $ltx"
set_property PROBES.FILE $ltx $dev
refresh_hw_device -update_hw_probes true $dev

set ila [lindex [get_hw_ilas -of_objects $dev] 0]
puts "S2_ILA: ila = $ila"
run_hw_ila -trigger_now $ila
wait_on_hw_ila $ila
upload_hw_ila_data $ila
write_hw_ila_data -csv_file /tmp/s2_ila.csv [current_hw_ila_data]
puts "S2_ILA: CSV written /tmp/s2_ila.csv"

# Print one row's key signal levels (stuck state is static, any row works).
set d [current_hw_ila_data]
puts "S2_ILA: probes —"
foreach p [lsort [get_hw_probes -of_objects $ila]] {
    if {[regexp -nocase {AWVALID|AWREADY|WVALID|WREADY|BVALID|BREADY|WLAST|TVALID|TREADY|TLAST} $p]} {
        catch { puts "  $p = [get_property VALUES.VALUE [get_hw_probe $p -of_objects $d]]" }
    }
}
puts "S2_ILA: DONE"
