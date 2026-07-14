# Package the OFDM RX-sync DUT (phase3_sync_axis_dma_wrapper + its RTL closure +
# xfft sub-IPs) as a proper Vivado IP with FORMAL AXI4-Lite / AXIS interfaces.
# Rationale: as a raw module_ref the inferred s_axi interface — though correct in
# metadata — made the SmartConnect drive wstrb=0 to the DUT (writes never latched)
# while packaged-IP GPIO slaves work on the same SmartConnect. A formal IP
# interface should be handled like the GPIO IP.
#   Run: vivado -mode batch -source scripts/package_dut_ip.tcl
set part   xczu49dr-ffvf1760-2-e
set root   [file normalize [file join [file dirname [info script]] ..]]
set dutdir [file join $root RTL_SYNC_PHASE5 rtl]
set iprepo [file join $root hardware ip_repo dut_sync]
set proj   /tmp/dut_pkg_proj
file delete -force $proj
file delete -force $iprepo
file mkdir $iprepo

create_project dut_pkg $proj -part $part -force

# --- sources: DUT RTL closure (leaf-first via the filelist) ------------------
set flist [file join $root scripts phase3_dut_filelist_newdesign.f]
set added 0
if {[file exists $flist]} {
    set fh [open $flist r]; set lines [split [read $fh] "\n"]; close $fh
    foreach ln $lines {
        set ln [string trim $ln]
        if {$ln eq "" || [string match "#*" $ln]} continue
        # strip a leading rtl/ and re-root under RTL_SYNC_PHASE5/rtl
        regsub {^\./} $ln "" ln
        regsub {^rtl/} $ln "" ln
        if {[string match "*/DUT/*" $ln] || [string match "*xfft_*/*.xci" $ln]} continue
        set p [file join $dutdir $ln]
        if {[file exists $p]} { add_files -norecurse $p; incr added }
    }
}
if {$added == 0} {
    # fallback: add all .v under rtl/ except the stale DUT/ symlinks
    foreach p [glob -nocomplain [file join $dutdir *.v]] { add_files -norecurse $p }
}
# xfft IPs (already xczu49dr) + disable OOC so they live inside the packaged IP
foreach xci {xfft_N/xfft_N.xci xfft_2N/xfft_2N.xci xfft_IFFT/xfft_IFFT.xci} {
    set p [file join $dutdir $xci]
    if {[file exists $p]} {
        import_ip $p
        set f [get_files -quiet *[file rootname [file tail $xci]].xci]
        if {$f ne ""} { set_property generate_synth_checkpoint 0 $f }
    }
}
# bk_conj_fft512_rom.txt: meyr_Rm_dut.v line 84 has a synthesizable
#   initial $readmemh("bk_conj_fft512_rom.txt", rom)
# (the FFT-correlation B[k]* coefficient ROM). Vivado bakes it as the BRAM init
# ONLY if the file is a project source on the synth path. Without it the ROM is
# all-zero -> meyr correlation / PSS never fires -> NO frame detection on HW
# (observed: board normal-mode FSV=0, PSS_DONE=0). Bake it into the packaged IP.
set bkrom [file normalize [file join $dutdir .. vectors bk_conj_fft512_rom.txt]]
if {[file exists $bkrom]} {
    add_files -norecurse $bkrom
    catch { set_property file_type {Memory Initialization Files} [get_files -quiet [file tail $bkrom]] }
    catch { set_property used_in_simulation true [get_files -quiet [file tail $bkrom]] }
    puts "PKG: added bk_conj ROM -> $bkrom"
} else {
    puts "PKG: WARN bk_conj ROM MISSING: $bkrom (HW correlation will be all-zero)"
}

update_compile_order -fileset sources_1
set_property top phase3_sync_axis_dma_wrapper [current_fileset]
update_compile_order -fileset sources_1
puts "PKG: top=[get_property top [current_fileset]] sources_added=$added"

# --- package -----------------------------------------------------------------
ipx::package_project -root_dir $iprepo -vendor user -library user \
    -taxonomy /UserIP -import_files -force

set core [ipx::current_core]
set_property name phase3_sync_axis_dma_wrapper $core
set_property version 1.0 $core
set_property display_name "OFDM RX Sync DUT (phase3)" $core

# --- curate interfaces: force s_axi = AXI4LITE slave, assoc clk/reset --------
proc dump_busifs {core} {
    foreach b [ipx::get_bus_interfaces -of_objects $core] {
        puts "PKG:  busif [get_property name $b] vlnv=[get_property bus_type_vlnv $b] mode=[get_property interface_mode $b]"
    }
}
puts "PKG: inferred bus interfaces --"
dump_busifs $core

# Ensure aclk is associated with s_axi/s_axis/m_axis and aresetn too.
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
