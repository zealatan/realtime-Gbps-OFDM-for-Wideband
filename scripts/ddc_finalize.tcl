set REPO /home/dsp-mikro7/FPGA_Based_OFDM_Transceiver
set XPR  $REPO/hardware/generated/08_rfdc_capture/zcu216_rfdc_capture.xpr
set BD   $REPO/hardware/generated/08_rfdc_capture/zcu216_rfdc_capture.srcs/sources_1/bd/system/system.bd
open_project $XPR
update_compile_order -fileset sources_1
open_bd_design $BD

# Report the freshly re-parsed adc_cap port + the RFDC tdata pin width.
catch { puts "FINAL: adc_cap/s_axis = [get_property CONFIG.TDATA_NUM_BYTES [get_bd_intf_pins adc_cap/s_axis]] bytes" }
foreach p [get_bd_pins -quiet adc_cap/s_axis_tdata] {
    catch { puts "FINAL: adc_cap/s_axis_tdata LEFT=[get_property LEFT $p] RIGHT=[get_property RIGHT $p]" }
}

# Remove any auto dwidth converter and ensure direct connection.
foreach c [get_bd_cells -quiet *] {
    if {[string match *auto_ds* [get_property NAME $c]] || \
        [string match *axi_dwidth_converter* [get_property VLNV $c]]} {
        catch { delete_bd_objs [get_bd_intf_nets -quiet -of_objects $c] }
        catch { delete_bd_objs $c }
        puts "FINAL: deleted [get_property NAME $c]"
    }
}
if {[llength [get_bd_intf_nets -quiet -of_objects [get_bd_intf_pins adc_cap/s_axis]]] == 0} {
    connect_bd_intf_net [get_bd_intf_pins usp_rf_data_converter_0/m20_axis] [get_bd_intf_pins adc_cap/s_axis]
    puts "FINAL: reconnected m20_axis -> adc_cap/s_axis"
}

if {[catch {validate_bd_design} v]} { puts "FINAL: validate: $v" }
puts "FINAL: m20_axis       = [get_property CONFIG.TDATA_NUM_BYTES [get_bd_intf_pins usp_rf_data_converter_0/m20_axis]] bytes"
puts "FINAL: adc_cap/s_axis = [get_property CONFIG.TDATA_NUM_BYTES [get_bd_intf_pins adc_cap/s_axis]] bytes"
puts "FINAL: auto_ds remaining = {[get_bd_cells -quiet *auto_ds*]}"
save_bd_design
if {[catch {generate_target all [get_files $BD]} g]} { puts "FINAL: generate: $g" }
puts "FINAL: DONE"
exit 0
