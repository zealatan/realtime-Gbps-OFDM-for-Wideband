# ddc_bd_edit.tcl
# RF bringup 6c-1: reconfigure 08_rfdc_capture RFDC ADC tile2/blk0 for a DDC.
#
# RFDC usp_rf_data_converter_0, ADC tile2/block0 == "20". Apply order matters
# (the IP cross-validates): Data_Type(IQ) -> Decimation -> Mixer_Type(fine) ->
# NCO. Mixer_Mode is fixed to 0 by the IP for fine-mixer + IQ (the correct DDC
# mode; values 1/2 are rejected). Result (probed):
#   ADC_Data_Type20=1 (I/Q), ADC_Decimation_Mode20=16, ADC_Mixer_Type20=2
#   (fine), ADC_Mixer_Mode20=0, ADC_NCO_Freq20=-0.3 GHz, ADC_Data_Width20=10
#   -> m20_axis = 160 bits (5 complex samples/beat), clk_adc2 307.2 MHz,
#      fabric word rate 30.72 MHz, complex rate 153.6 Msps.
#
# Also refreshes the adc_cap module_ref so the BD picks up its new 160-bit
# s_axis port (the RTL zcu216_adc_capture.v was widened to [159:0]).

set REPO /home/dsp-mikro7/FPGA_Based_OFDM_Transceiver
set XPR  $REPO/hardware/generated/08_rfdc_capture/zcu216_rfdc_capture.xpr
set BD   $REPO/hardware/generated/08_rfdc_capture/zcu216_rfdc_capture.srcs/sources_1/bd/system/system.bd

proc fail {msg} { puts "DDC_EDIT: FAIL $msg"; exit 1 }
if {![file exists $XPR]} { fail "project not found: $XPR" }

open_project $XPR
open_bd_design $BD
set rfdc [get_bd_cells usp_rf_data_converter_0]
if {$rfdc eq ""} { fail "RFDC cell not found" }

# Apply DDC config (ordered).
set_property CONFIG.ADC_Data_Type20       {1}    $rfdc
set_property CONFIG.ADC_Decimation_Mode20 {16}   $rfdc
set_property CONFIG.ADC_Mixer_Type20      {2}    $rfdc
set_property CONFIG.ADC_NCO_Freq20        {-0.3} $rfdc

puts "DDC_EDIT: ===== applied RFDC config ====="
foreach p {ADC_Data_Type20 ADC_Decimation_Mode20 ADC_Mixer_Type20 \
           ADC_Mixer_Mode20 ADC_NCO_Freq20 ADC_Data_Width20 \
           ADC2_Outclk_Freq ADC2_Fabric_Freq ADC2_Sampling_Rate} {
    catch { puts "  CONFIG.$p = [get_property CONFIG.$p $rfdc]" }
}

# Refresh the adc_cap module_ref so the BD re-reads the widened RTL port.
catch {
    set acm [get_bd_cells adc_cap]
    if {$acm ne ""} {
        update_compile_order -fileset sources_1
        update_module_reference adc_cap
        puts "DDC_EDIT: refreshed adc_cap module_ref"
    }
}

if {[catch {validate_bd_design} verr]} {
    puts "DDC_EDIT: validate_bd_design reported: $verr"
}

# ---- READ BACK actual m20_axis (gearbox-sizing fact) ----
set m20 [get_bd_intf_pins usp_rf_data_converter_0/m20_axis]
puts "DDC_EDIT: ===== POST-DDC m20_axis (RFDC master) ====="
foreach prop {CONFIG.TDATA_NUM_BYTES CONFIG.FREQ_HZ CONFIG.CLK_DOMAIN} {
    catch { puts "  m20_axis $prop = [get_property $prop $m20]" }
}
catch {
    set w [get_property CONFIG.TDATA_NUM_BYTES $m20]
    puts "  m20_axis TDATA = $w bytes = [expr {$w*8}] bits"
}
set acs [get_bd_intf_pins adc_cap/s_axis]
catch { puts "DDC_EDIT: adc_cap/s_axis TDATA = [get_property CONFIG.TDATA_NUM_BYTES $acs] bytes" }

save_bd_design

puts "DDC_EDIT: regenerating BD targets..."
if {[catch {generate_target all [get_files $BD]} gerr]} {
    puts "DDC_EDIT: generate_target reported: $gerr"
}
puts "DDC_EDIT: DONE"
exit 0
