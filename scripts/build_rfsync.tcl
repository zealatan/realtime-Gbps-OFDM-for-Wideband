# build_rfsync.tcl  (RF bringup 6c-2)
# Build the 08_rfdc_capture bitstream after the rfsync BD integration
# (RFDC DDC -> async FIFO -> rfdc_deser -> DUT -> rfsync_cap).
#
# Reuses the dac_tone OFDM hex cache-purge logic from build_ddc_full.tcl
# (CRITICAL: the dac_tone OOC synth keys on the .xci, not the external RTL, so a
# stale cache would drop the OFDM logic + $readmemh). Regenerates BD targets so
# the new module_ref cells (rfdc_deser, dut_capture) and the packaged DUT IP +
# its xfft OOC cores are stitched, then synth + impl + bitstream.
set REPO /home/dsp-mikro7/FPGA_Based_OFDM_Transceiver
set XPR  $REPO/hardware/generated/08_rfdc_capture/zcu216_rfdc_capture.xpr
set BD   $REPO/hardware/generated/08_rfdc_capture/zcu216_rfdc_capture.srcs/sources_1/bd/system/system.bd
set HEX_SRC  $REPO/RTL_SYNC_PHASE5/golden/rf_loopback/ofdm_dac_fckp0.hex
set RTL_DIR  $REPO/hardware/rtl
set HEX_NAME ofdm_dac_fckp0.hex
set OOC_RUN  system_dac_tone_0_synth_1
set OOC_DIR  $REPO/hardware/generated/08_rfdc_capture/zcu216_rfdc_capture.runs/$OOC_RUN
proc fail {m} { puts "BUILDRFSYNC: FAIL $m"; exit 1 }

if {[file exists $HEX_SRC]} { file copy -force $HEX_SRC $RTL_DIR/$HEX_NAME }

open_project $XPR
update_compile_order -fileset sources_1

# Regenerate BD targets so all module_ref + packaged-IP OOC runs are created.
catch { generate_target all [get_files $BD] }

# dac_tone IP cache purge (verbatim intent of build_ddc_full.tcl).
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
catch {
    set hexf [get_files -quiet $RTL_DIR/$HEX_NAME]
    if {[llength $hexf]} {
        set_property file_type {Memory Initialization Files} $hexf
        set_property used_in_synthesis true $hexf
    }
}

# Reset the OOC runs that must (re)synthesize. The DUT IP + its xfft OOC runs are
# auto-created by generate_target; reset_run on synth_1/impl_1 forces a restitch.
foreach r {system_adc_cap_0_synth_1 system_usp_rf_data_converter_0_0_synth_1 \
           system_dac_tone_0_synth_1} {
    catch { reset_run $r }
    puts "BUILDRFSYNC: reset $r"
}
catch { reset_run synth_1 }
catch { reset_run impl_1 }

file mkdir $OOC_DIR
if {[file exists $HEX_SRC]} { file copy -force $HEX_SRC $OOC_DIR/$HEX_NAME }

# Synthesize. Let Vivado schedule all out-of-date OOC IP runs as part of synth_1
# (launch_runs synth_1 pulls in its prerequisites automatically).
launch_runs synth_1 -jobs 8
wait_on_run synth_1
set sp [get_property PROGRESS [get_runs synth_1]]
set ss [get_property STATUS   [get_runs synth_1]]
puts "BUILDRFSYNC: synth_1 progress=$sp status=$ss"
if {$sp ne "100%"} { fail "synth_1 ($ss)" }

# dac_tone readmemh sanity (best-effort).
if {[file exists $OOC_DIR/runme.log]} {
    set fh [open $OOC_DIR/runme.log r]; set txt [read $fh]; close $fh
    if {[regexp -line {.*\$readmem .*ofdm_dac_fckp0.hex.* is read successfully.*} $txt m]} {
        puts "BUILDRFSYNC: READMEMH OK -> $m"
    }
}

launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
set ip [get_property PROGRESS [get_runs impl_1]]
set is [get_property STATUS   [get_runs impl_1]]
puts "BUILDRFSYNC: impl_1 progress=$ip status=$is"
if {$ip ne "100%"} { fail "impl_1 ($is)" }

set impl_dir [get_property DIRECTORY [get_runs impl_1]]
set bit ""
foreach b [glob -nocomplain $impl_dir/*.bit] { set bit $b }
if {$bit eq ""} { fail "no .bit in $impl_dir" }

set wns [get_property STATS.WNS [get_runs impl_1]]
set whs [get_property STATS.WHS [get_runs impl_1]]
set tns [get_property STATS.TNS [get_runs impl_1]]
set ths [get_property STATS.THS [get_runs impl_1]]
if {$wns >= 0 && $whs >= 0} {
    puts "BUILDRFSYNC: Timing MET (WNS=$wns WHS=$whs TNS=$tns THS=$ths)"
} else {
    puts "BUILDRFSYNC: Timing VIOLATED (WNS=$wns WHS=$whs TNS=$tns THS=$ths)"
}
puts "BUILDRFSYNC: DONE bitstream=$bit"
exit 0
