# build_ddc_full.tcl
# Full rebuild for RF 6c-1 DDC: regenerate adc_cap (widened/fixed RTL) + RFDC
# (DDC config), keep the dac_tone OFDM cache-purge logic, then synth + impl +
# bitstream. Resets the adc_cap and RFDC OOC runs (which build_08_ofdm.tcl does
# NOT) so the new RTL/IP config is actually re-synthesized.
set REPO /home/dsp-mikro7/FPGA_Based_OFDM_Transceiver
set XPR  $REPO/hardware/generated/08_rfdc_capture/zcu216_rfdc_capture.xpr
set BD   $REPO/hardware/generated/08_rfdc_capture/zcu216_rfdc_capture.srcs/sources_1/bd/system/system.bd
set HEX_SRC  $REPO/RTL_SYNC_PHASE5/golden/rf_loopback/ofdm_dac_fckp0.hex
set RTL_DIR  $REPO/hardware/rtl
set HEX_NAME ofdm_dac_fckp0.hex
set OOC_RUN  system_dac_tone_0_synth_1
set OOC_DIR  $REPO/hardware/generated/08_rfdc_capture/zcu216_rfdc_capture.runs/$OOC_RUN
proc fail {m} { puts "BUILDDDC: FAIL $m"; exit 1 }

# dac_tone hex belt-and-suspenders (same as build_08_ofdm.tcl).
file copy -force $HEX_SRC $RTL_DIR/$HEX_NAME

open_project $XPR
update_compile_order -fileset sources_1

# Regenerate adc_cap IP source from the fixed RTL (port unchanged, logic fixed).
catch { reset_target all [get_files $BD] }
catch { generate_target all [get_files $BD] }

# dac_tone IP cache purge (verbatim intent of build_08_ofdm.tcl).
catch { config_ip_cache -disable_cache }
catch { config_ip_cache -clear_output_repo }
catch {
    set ip_obj [get_ips -quiet system_dac_tone_0]
    if {[llength $ip_obj]} { config_ip_cache -remove -ip $ip_obj }
}
set CACHE_ROOT [get_property ip_output_repo [current_project]]
catch {
    foreach d [glob -nocomplain $CACHE_ROOT/*/*] {
        if {[file isdirectory $d] && [llength [glob -nocomplain $d/*dac_tone*]] > 0} {
            file delete -force $d
        }
    }
}
catch { set_property ip_cache_permissions {} [current_project] }

# Register dac_tone hex memory-init.
catch {
    set hexf [get_files -quiet $RTL_DIR/$HEX_NAME]
    if {[llength $hexf]} {
        set_property file_type {Memory Initialization Files} $hexf
        set_property used_in_synthesis true $hexf
    }
}

# Reset the OOC runs that must re-synthesize, then top synth/impl.
foreach r {system_adc_cap_0_synth_1 system_usp_rf_data_converter_0_0_synth_1 \
           system_dac_tone_0_synth_1} {
    catch { reset_run $r }
    puts "BUILDDDC: reset $r"
}
catch { reset_run synth_1 }
catch { reset_run impl_1 }

# dac_tone hex into its OOC run dir (CWD search path).
file mkdir $OOC_DIR
file copy -force $HEX_SRC $OOC_DIR/$HEX_NAME

# Launch the OOC runs first.
launch_runs system_adc_cap_0_synth_1 system_usp_rf_data_converter_0_0_synth_1 \
            system_dac_tone_0_synth_1 -jobs 8
foreach r {system_adc_cap_0_synth_1 system_usp_rf_data_converter_0_0_synth_1 \
           system_dac_tone_0_synth_1} {
    wait_on_run $r
    set p [get_property PROGRESS [get_runs $r]]
    set s [get_property STATUS [get_runs $r]]
    puts "BUILDDDC: $r progress=$p status=$s"
    if {$p ne "100%"} { fail "$r did not complete ($s)" }
}

# dac_tone readmemh sanity.
set ooc_log $OOC_DIR/runme.log
if {[file exists $ooc_log]} {
    set fh [open $ooc_log r]; set txt [read $fh]; close $fh
    if {[regexp -line {.*\$readmem .*ofdm_dac_fckp0.hex.* is read successfully.*} $txt m]} {
        puts "BUILDDDC: READMEMH OK -> $m"
    }
}

launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} { fail "synth_1" }
puts "BUILDDDC: synth_1 100%"

launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} { fail "impl_1" }
puts "BUILDDDC: impl_1 100%"

set impl_dir [get_property DIRECTORY [get_runs impl_1]]
set bit ""
foreach b [glob -nocomplain $impl_dir/*.bit] { set bit $b }
if {$bit eq ""} { fail "no .bit" }

set wns [get_property STATS.WNS [get_runs impl_1]]
set whs [get_property STATS.WHS [get_runs impl_1]]
set tns [get_property STATS.TNS [get_runs impl_1]]
set ths [get_property STATS.THS [get_runs impl_1]]
if {$wns >= 0 && $whs >= 0} {
    puts "BUILDDDC: Timing MET (WNS=$wns WHS=$whs TNS=$tns THS=$ths)"
} else {
    puts "BUILDDDC: Timing VIOLATED (WNS=$wns WHS=$whs TNS=$tns THS=$ths)"
}
puts "BUILDDDC: DONE bitstream=$bit"
exit 0
