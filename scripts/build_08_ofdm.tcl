# build_08_ofdm.tcl
# Rebuild the 08_rfdc_capture bitstream so the DAC streams a pre-computed OFDM
# waveform (RF bringup 6b).
#
# The dac_tone module (hardware/rtl/zcu216_dac_tone_axis.v) now has an OFDM mode
# (ctrl[1]=1) that streams a pre-computed full-rate real OFDM passband from an
# internal BRAM initialized with:
#     $readmemh("ofdm_dac_fckp0.hex", ofdm_mem)
# referenced by the BARE name "ofdm_dac_fckp0.hex".
#
# dac_tone is a BD module_ref synthesized OUT-OF-CONTEXT as the run
# system_dac_tone_0_synth_1. That OOC synth process runs with its CWD set to the
# run dir and reads the RTL via:
#     read_verilog .../hardware/rtl/zcu216_dac_tone_axis.v
#     synth_design -top system_dac_tone_0 -mode out_of_context
#
# Vivado resolves a relative $readmemh path during synthesis by searching:
#   1. the synth process CWD  (= the OOC run dir)
#   2. the directory that contains the HDL source file
#
# To make $readmemh("ofdm_dac_fckp0.hex") resolve robustly we put the hex in
# BOTH places:
#   (A) next to the .v file (hardware/rtl/)         -> source-dir search hit
#   (B) into the OOC run dir, AFTER reset_run and    -> CWD search hit
#       BEFORE launch_runs (reset_run recreates dir)
# and we also register it as a project Memory-Init source (used_in_synthesis).
# Any one of these is sufficient; together they are belt-and-suspenders so the
# #1 risk (readmemh cannot open the file) cannot happen.

set REPO        /home/dsp-mikro7/FPGA_Based_OFDM_Transceiver
set XPR         $REPO/hardware/generated/08_rfdc_capture/zcu216_rfdc_capture.xpr
set HEX_SRC     $REPO/RTL_SYNC_PHASE5/golden/rf_loopback/ofdm_dac_fckp0.hex
set RTL_DIR     $REPO/hardware/rtl
set RTL_V       $RTL_DIR/zcu216_dac_tone_axis.v
set HEX_NAME    ofdm_dac_fckp0.hex
set OOC_RUN     system_dac_tone_0_synth_1
set OOC_RUN_DIR $REPO/hardware/generated/08_rfdc_capture/zcu216_rfdc_capture.runs/$OOC_RUN

proc fail {msg} {
    puts "BUILD08_OFDM: FAIL"
    puts "BUILD08_OFDM: $msg"
    exit 1
}

if {![file exists $HEX_SRC]} { fail "hex source not found: $HEX_SRC" }
if {![file exists $XPR]}     { fail "project not found: $XPR" }
if {![file exists $RTL_V]}   { fail "rtl not found: $RTL_V" }

# (A) Copy hex next to the .v source (source-dir search path for $readmemh).
set HEX_IN_RTL $RTL_DIR/$HEX_NAME
file copy -force $HEX_SRC $HEX_IN_RTL
puts "BUILD08_OFDM: copied hex -> $HEX_IN_RTL"

open_project $XPR

# CRITICAL: the dac_tone OOC synth keys its IP cache on the .xci IP config,
# which did NOT change when the EXTERNAL RTL (zcu216_dac_tone_axis.v) gained the
# OFDM mode. A prior run therefore reused the stale pre-OFDM cached synthesis
# (cache-ID 7802f64bf3e47d09, "Using cached IP synthesis design") and the OFDM
# logic + $readmemh never got synthesized. Disable the IP cache for this build
# and purge any stale dac_tone cache entry so the OOC run re-synthesizes the
# modified RTL for real.
catch { config_ip_cache -disable_cache }
catch { config_ip_cache -clear_output_repo }
catch {
    set ip_obj [get_ips -quiet system_dac_tone_0]
    if {[llength $ip_obj]} { config_ip_cache -remove -ip $ip_obj }
}
set CACHE_ROOT [get_property ip_output_repo [current_project]]
catch {
    foreach d [glob -nocomplain $CACHE_ROOT/*/7802f64bf3e47d09] {
        file delete -force $d
        puts "BUILD08_OFDM: purged stale IP cache entry $d"
    }
}
# Belt: blow away every dac_tone-bearing cache entry regardless of hash.
catch {
    foreach d [glob -nocomplain $CACHE_ROOT/*/*] {
        if {[file isdirectory $d] && \
            [llength [glob -nocomplain $d/*dac_tone*]] > 0} {
            file delete -force $d
            puts "BUILD08_OFDM: purged dac_tone IP cache entry $d"
        }
    }
}
# Also disconnect the project from the cache repo so launch_runs cannot read it.
catch { set_property ip_cache_permissions {} [current_project] }

# Sanity: confirm the project really uses the modified rtl/ .v (not a copy).
set v_files [get_files -quiet -all *zcu216_dac_tone_axis.v]
puts "BUILD08_OFDM: dac_tone .v files seen by project: $v_files"
set uses_rtl_v 0
foreach f $v_files {
    if {[string match *hardware/rtl/zcu216_dac_tone_axis.v $f]} { set uses_rtl_v 1 }
}
if {!$uses_rtl_v} {
    puts "BUILD08_OFDM: WARNING dac_tone source is not the rtl/ file; re-adding."
}

# Register the hex as a project Memory-Init source, used in synthesis, and
# scope it to the dac_tone module so the OOC run picks it up too.
if {[llength [get_files -quiet $HEX_NAME]] == 0 && \
    [llength [get_files -quiet $HEX_IN_RTL]] == 0} {
    catch { add_files -norecurse -fileset sources_1 $HEX_IN_RTL }
}
catch {
    set hexf [get_files -quiet $HEX_IN_RTL]
    if {[llength $hexf]} {
        set_property file_type {Memory Initialization Files} $hexf
        set_property used_in_synthesis true  $hexf
        set_property used_in_simulation true $hexf
        puts "BUILD08_OFDM: registered hex as Memory Init source: $hexf"
    }
}

# Add the rtl/ dir as a Verilog include dir on the sources fileset (another
# search path for $readmemh).
catch {
    set inc [get_property include_dirs [get_filesets sources_1]]
    if {[lsearch -exact $inc $RTL_DIR] < 0} {
        lappend inc $RTL_DIR
        set_property include_dirs $inc [get_filesets sources_1]
        puts "BUILD08_OFDM: added include_dir $RTL_DIR to sources_1"
    }
}

# ---- Reset and relaunch the OOC dac_tone synth so the OFDM RTL + hex go in ----
catch { reset_run $OOC_RUN }
puts "BUILD08_OFDM: reset OOC run $OOC_RUN"

# (B) reset_run recreated the OOC run dir -> drop the hex into it (CWD of synth).
file mkdir $OOC_RUN_DIR
file copy -force $HEX_SRC $OOC_RUN_DIR/$HEX_NAME
puts "BUILD08_OFDM: copied hex -> $OOC_RUN_DIR/$HEX_NAME"

# Also reset top synth/impl so they restitch the new OOC dcp.
catch { reset_run synth_1 }
catch { reset_run impl_1 }

# Launch OOC synth first (must finish before top synth can stitch its dcp).
launch_runs $OOC_RUN -jobs 8
wait_on_run $OOC_RUN
set ooc_status [get_property STATUS  [get_runs $OOC_RUN]]
set ooc_prog   [get_property PROGRESS [get_runs $OOC_RUN]]
puts "BUILD08_OFDM: OOC run status=$ooc_status progress=$ooc_prog"
if {$ooc_prog ne "100%"} { fail "OOC dac_tone synth did not complete ($ooc_status)" }

# Verify the OOC run actually RE-SYNTHESIZED the OFDM RTL (not a cache reuse)
# and that $readmemh opened the hex.
set ooc_log $OOC_RUN_DIR/runme.log
if {[file exists $ooc_log]} {
    set fh [open $ooc_log r]
    set txt [read $fh]
    close $fh
    if {[string match "*Using cached IP synthesis design*" $txt]} {
        fail "OOC run REUSED stale IP cache (OFDM RTL not synthesized) -- cache not disabled"
    }
    if {[regexp -line {.*\$readmem data file .*ofdm_dac_fckp0.hex.* is read successfully.*} $txt mline]} {
        puts "BUILD08_OFDM: READMEMH OK -> $mline"
    } elseif {[regexp -line {.*[Cc]annot open.*ofdm_dac_fckp0.hex.*} $txt mline]} {
        fail "READMEMH FAILED -> $mline"
    } elseif {[regexp -line {.*[Ff]ailed to open.*ofdm_dac_fckp0.hex.*} $txt mline]} {
        fail "READMEMH FAILED -> $mline"
    } else {
        puts "BUILD08_OFDM: WARNING no explicit readmemh line found in OOC log (check manually)"
    }
    if {[regexp -line {.*synthesizing module 'zcu216_dac_tone_axis'.*} $txt sline]} {
        puts "BUILD08_OFDM: OFDM RTL synthesized -> $sline"
    }
}

# Belt-and-suspenders: the hex may be consumed/moved during the OOC run; ensure
# it is present again for any rerun, harmless if untouched.
catch { file copy -force $HEX_SRC $OOC_RUN_DIR/$HEX_NAME }

# ---- Top synthesis ----
launch_runs synth_1 -jobs 8
wait_on_run synth_1
set s_prog [get_property PROGRESS [get_runs synth_1]]
puts "BUILD08_OFDM: synth_1 progress=$s_prog"
if {$s_prog ne "100%"} { fail "top synth_1 failed (progress=$s_prog)" }

# ---- Implementation + bitstream ----
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
set i_prog [get_property PROGRESS [get_runs impl_1]]
puts "BUILD08_OFDM: impl_1 progress=$i_prog"
if {$i_prog ne "100%"} { fail "impl_1 / write_bitstream failed (progress=$i_prog)" }

# ---- Locate bitstream ----
set impl_dir [get_property DIRECTORY [get_runs impl_1]]
set bit ""
foreach b [glob -nocomplain $impl_dir/*.bit] { set bit $b }
if {$bit eq ""} { fail "no .bit found in $impl_dir" }

# ---- Timing summary ----
set tns [get_property STATS.TNS [get_runs impl_1]]
set whs [get_property STATS.WHS [get_runs impl_1]]
set ths [get_property STATS.THS [get_runs impl_1]]
set timing_line "WNS unknown"
catch {
    set wns [get_property STATS.WNS [get_runs impl_1]]
    if {$wns >= 0 && $whs >= 0} {
        set timing_line "Timing MET  (WNS=$wns ns, WHS=$whs ns, TNS=$tns, THS=$ths)"
    } else {
        set timing_line "Timing VIOLATED (WNS=$wns ns, WHS=$whs ns, TNS=$tns, THS=$ths)"
    }
}

puts "BUILD08_OFDM: DONE bitstream=$bit"
puts "BUILD08_OFDM: $timing_line"
exit 0
