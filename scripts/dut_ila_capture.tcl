# Attach to the already-programmed/running ZCU216 (10_digital_loopback) where the
# ELF has hung on the first DUT AXI-Lite write, trigger the dut_ila NOW, and dump
# the static stuck levels of dut_0/s_axi (AW/W/B/AR/R). Do NOT reprogram.
#   Run: ~/xilinx/Vivado/2022.2/bin/vivado -mode batch -source scripts/dut_ila_capture.tcl
open_hw_manager
connect_hw_server -url localhost:3121
open_hw_target

set dev ""
foreach d [get_hw_devices] { if {[string match -nocase *zu* $d]} { set dev $d } }
if {$dev eq ""} { set dev [lindex [get_hw_devices] end] }
current_hw_device $dev
puts "DUT_ILA: device = $dev"

set ltx [lindex [glob -nocomplain hardware/generated/10_digital_loopback/zcu216_loopback.runs/impl_1/*.ltx] 0]
puts "DUT_ILA: ltx = $ltx"
set_property PROBES.FILE $ltx $dev
refresh_hw_device -update_hw_probes true $dev

set ila [lindex [get_hw_ilas -of_objects $dev] 0]
puts "DUT_ILA: ila = $ila"
run_hw_ila -trigger_now $ila
wait_on_hw_ila $ila
upload_hw_ila_data $ila
catch { file delete /tmp/dut_ila.csv }
write_hw_ila_data -csv_file /tmp/dut_ila.csv [current_hw_ila_data]
puts "DUT_ILA: CSV -> /tmp/dut_ila.csv"

set d [current_hw_ila_data]
puts "DUT_ILA: s_axi probe levels (stuck state) --"
foreach p [lsort [get_hw_probes -of_objects $ila]] {
    if {[regexp -nocase {awaddr|awvalid|awready|wdata|wstrb|wvalid|wready|bvalid|bresp|araddr|arvalid|arready|rdata|rvalid|rready|rresp|bready} $p]} {
        catch { puts "  $p = [get_property VALUES.VALUE [get_hw_probe $p -of_objects $d]]" }
    }
}
puts "DUT_ILA: DONE"
