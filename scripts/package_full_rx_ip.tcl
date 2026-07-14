# Package the FULL RX board DUT (rx_full_board_top = sync + downstream FFT/CE/EQ/
# 16QAM-demod + internal pilot ROM + bit->beat adapter) as a Vivado IP with the
# SAME formal AXI4-Lite/AXIS interface as the sync-only IP, so it drops into the
# existing digital-loopback BD/firmware unchanged (m_axis now carries demod bits).
#
# Reuses the package_dut_ip.tcl approach but:
#   - top = rx_full_board_top
#   - adds ALL rtl/*.v (sync + rx_* downstream + wrappers) -> Vivado resolves the
#     hierarchy closure (same set the rx_full_chain xsim gate compiles).
#   - bakes the memory-init ROMs needed by $readmemh on the synth path:
#       pilot_rom.hex (golden), ce_interp_W.hex, rx_equalizer_recip_lut.hex,
#       bk_conj_fft512_rom.txt (sync correlator).
#   Run: vivado -mode batch -source scripts/package_full_rx_ip.tcl
set part   xczu49dr-ffvf1760-2-e
set root   [file normalize [file join [file dirname [info script]] ..]]
set dutdir [file join $root RTL_SYNC_PHASE5 rtl]
set iprepo [file join $root hardware ip_repo full_rx]
set proj   /tmp/full_rx_pkg_proj
file delete -force $proj
file delete -force $iprepo
file mkdir $iprepo

create_project full_rx_pkg $proj -part $part -force

# --- sources: ALL rtl .v (the full RX closure incl. downstream + wrappers) ----
set vfiles [glob -nocomplain [file join $dutdir *.v]]
foreach p $vfiles { add_files -norecurse $p }
puts "PKG: added [llength $vfiles] rtl .v files"

# xfft IPs (xczu49dr) — disable OOC so they live inside the packaged IP.
# xfft_N is instantiated TWICE (meyr core + rx_fft_frontend); one .xci suffices.
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
add_mem [file join $root RTL_SYNC_PHASE5 golden rx_downstream pilot_rom.hex]
add_mem [file join $dutdir rx_ch_est_rom ce_interp_W.hex]
# CE pilot-reciprocal ROM (replaces the old single-cycle complex divide with a
# precomputed-constant multiply -> full-rate timing). rx_full_board_top threads
# CE_RECIP_ROM = "ce_pilot_recip.hex" (bare) to rx_ch_est, so $readmemh must find
# it on the synth path by bare name (same handling as ce_interp_W.hex).
add_mem [file join $dutdir rx_ch_est_rom ce_pilot_recip.hex]
add_mem [file join $dutdir rx_equalizer_recip_lut.hex]
add_mem [file join $root RTL_SYNC_PHASE5 vectors bk_conj_fft512_rom.txt]
# On-chip HW BER checker golden reference ROM (rx_ber_checker $readmemh, bare name).
add_mem [file join $dutdir rx_ber_ref_rom.hex]

update_compile_order -fileset sources_1
set_property top rx_full_board_top [current_fileset]
update_compile_order -fileset sources_1
puts "PKG: top=[get_property top [current_fileset]]"

# --- package -----------------------------------------------------------------
ipx::package_project -root_dir $iprepo -vendor user -library user \
    -taxonomy /UserIP -import_files -force

set core [ipx::current_core]
set_property name rx_full_board_top $core
set_property version 1.0 $core
set_property display_name "OFDM FULL RX (sync+FFT/CE/EQ/16QAM demod)" $core

puts "PKG: inferred bus interfaces --"
foreach b [ipx::get_bus_interfaces -of_objects $core] {
    puts "PKG:  busif [get_property name $b] vlnv=[get_property bus_type_vlnv $b] mode=[get_property interface_mode $b]"
}
# associate aclk with the AXI ifaces
catch {
    set clk [ipx::get_bus_interfaces aclk -of_objects $core]
    set_property value s_axi:s_axis:m_axis:dbg_frac_m [ipx::get_bus_parameters ASSOCIATED_BUSIF -of_objects $clk]
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
