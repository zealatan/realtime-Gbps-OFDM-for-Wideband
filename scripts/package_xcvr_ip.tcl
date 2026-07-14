# Package the MODE-SELECTABLE OFDM TRANSCEIVER board adapter (ofdm_xcvr_board_top
# = frozen ofdm_transceiver_top [TX/RX/LOOPBACK] + internal pilot/data ROMs +
# bit->beat adapter + TX-IQ m_axis mux + mode/start decode from ber_ctrl) as a
# Vivado IP with the SAME formal AXI4-Lite/AXIS/ber boundary as the previous
# rx_full_board_top IP, so it is a DROP-IN swap in the 11_full_rx_loopback BD
# (only the BD cell VLNV changes).
#
#   top = ofdm_xcvr_board_top
#   adds ALL rtl/*.v + the 3 xfft .xci (same closure as the rx_full_chain gate)
#   bakes the $readmemh ROMs: pilot_rom, ce_interp_W, ce_pilot_recip,
#     rx_equalizer_recip_lut, bk_conj_fft512_rom, rx_ber_ref_rom,
#     tx_specmap, tx_sync_rom, tx_data_bits_packed.
#   Run: vivado -mode batch -source scripts/package_xcvr_ip.tcl
set part   xczu49dr-ffvf1760-2-e
set root   [file normalize [file join [file dirname [info script]] ..]]
set dutdir [file join $root RTL_SYNC_PHASE5 rtl]
set iprepo [file join $root hardware ip_repo xcvr]
set proj   /tmp/xcvr_pkg_proj
file delete -force $proj
file delete -force $iprepo
file mkdir $iprepo

create_project xcvr_pkg $proj -part $part -force

# --- sources: ALL rtl .v (full TX + RX closure incl. downstream + wrappers) ---
set vfiles [glob -nocomplain [file join $dutdir *.v]]
foreach p $vfiles { add_files -norecurse $p }
puts "PKG: added [llength $vfiles] rtl .v files"

# MM2S DMA -> parallel TX-payload bridge (lives under hardware/rtl, not dutdir).
set bridge [file join $root hardware rtl axi_to_parallel_tx.v]
if {[file exists $bridge]} {
    add_files -norecurse $bridge
    puts "PKG: added MM2S bridge $bridge"
} else {
    puts "PKG: WARN MM2S bridge missing: $bridge"
}

# xfft IPs (xczu49dr) — disable OOC so they live inside the packaged IP.
foreach xci {xfft_N/xfft_N.xci xfft_2N/xfft_2N.xci xfft_IFFT/xfft_IFFT.xci} {
    set p [file join $dutdir $xci]
    if {[file exists $p]} {
        import_ip $p
        set f [get_files -quiet *[file rootname [file tail $xci]].xci]
        if {$f ne ""} { catch { set_property generate_synth_checkpoint 0 $f } }
    }
}

# --- memory-init ROMs (must be on the synth path for $readmemh by bare name) ---
proc add_mem {f} {
    if {[file exists $f]} {
        add_files -norecurse $f
        catch { set_property file_type {Memory Initialization Files} [get_files -quiet [file tail $f]] }
        catch { set_property used_in_simulation true [get_files -quiet [file tail $f]] }
        catch { set_property used_in_synthesis  true [get_files -quiet [file tail $f]] }
        puts "PKG: added mem-init [file tail $f]"
    } else { puts "PKG: WARN mem-init MISSING: $f" }
}
# RX-side ROMs (same as the proven full_rx IP)
add_mem [file join $root RTL_SYNC_PHASE5 golden rx_downstream pilot_rom.hex]
add_mem [file join $dutdir rx_ch_est_rom ce_interp_W.hex]
add_mem [file join $dutdir rx_ch_est_rom ce_pilot_recip.hex]
add_mem [file join $dutdir rx_equalizer_recip_lut.hex]
add_mem [file join $root RTL_SYNC_PHASE5 vectors bk_conj_fft512_rom.txt]
add_mem [file join $dutdir rx_ber_ref_rom.hex]
# TX-side ROMs (tx_ofdm_top spectral map + sync rom; bare names threaded by adapter)
add_mem [file join $dutdir tx_rom tx_specmap.hex]
add_mem [file join $dutdir tx_rom tx_sync_rom.hex]
# Board adapter TX data-bits ROM (golden bits the host BER compares against)
add_mem [file join $root RTL_SYNC_PHASE5 golden tx tx_data_bits_packed.hex]

update_compile_order -fileset sources_1
set_property top ofdm_xcvr_board_top [current_fileset]
update_compile_order -fileset sources_1
puts "PKG: top=[get_property top [current_fileset]]"

# --- package -----------------------------------------------------------------
ipx::package_project -root_dir $iprepo -vendor user -library user \
    -taxonomy /UserIP -import_files -force

set core [ipx::current_core]
set_property name ofdm_xcvr_board_top $core
set_property version 1.0 $core
set_property display_name "OFDM XCVR (TX/RX/LOOPBACK mode-selectable)" $core

puts "PKG: inferred bus interfaces --"
foreach b [ipx::get_bus_interfaces -of_objects $core] {
    puts "PKG:  busif [get_property name $b] vlnv=[get_property bus_type_vlnv $b] mode=[get_property interface_mode $b]"
}
# associate aclk with the AXI ifaces (incl. the new tx_s_axis MM2S payload slave)
catch {
    set clk [ipx::get_bus_interfaces aclk -of_objects $core]
    set_property value s_axi:s_axis:m_axis:tx_s_axis:dbg_frac_m [ipx::get_bus_parameters ASSOCIATED_BUSIF -of_objects $clk]
}

ipx::create_xgui_files $core
ipx::update_checksums $core
ipx::check_integrity $core
ipx::save_core $core
puts "PKG: saved IP -> $iprepo"
puts "PKG: vlnv = [get_property vlnv $core]"
ipx::unload_core
close_project
puts "PKG: DONE"
