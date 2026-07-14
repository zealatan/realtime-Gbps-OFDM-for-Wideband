# run_rx_cfo_allmods.tcl
#
# PHASE-2 CFO-robustness gate (ALL modulations), built verbatim on
# run_rx_full_chain.tcl.  Drives tb/rx_cfo_allmods_tb.sv through
# rx_full_chain_top (frozen sync -> FFT -> CE -> EQ -> demod) with a CFO
# rotation applied to a per-mod sync frame, and grades on GATE: PASS_RX_CFO.
#
# Env-driven (set by run_rx_cfo_allmods.sh):
#   CFO_TAG        - short tag for log/gate file (e.g. CFO_M0_250)
#   CFO_PLUSARGS   - space-separated xsim plusargs (e.g. "MOD=0 CFO_MILLI=250")

set root [pwd]
set part_locked "xczu9eg-ffvb1156-2-e"
set part        $part_locked
if {[info exists ::env(XFFT_TARGET_PART)]} { set part $::env(XFFT_TARGET_PART) }
set part_fallback_note ""

set tag [expr {[info exists ::env(CFO_TAG)] ? $::env(CFO_TAG) : "CFO"}]
set plusargs [expr {[info exists ::env(CFO_PLUSARGS)] ? $::env(CFO_PLUSARGS) : ""}]

set log_dir [file join $root vivado_xsim logs]
set rpt_dir [file join $root vivado_xsim reports]
set build   [file join $log_dir rx_cfo_build_$tag]
file mkdir $log_dir
file mkdir $rpt_dir
file delete -force $build
file mkdir $build

set clog [file join $log_dir rx_cfo_${tag}_compile.log]
set elog [file join $log_dir rx_cfo_${tag}_elab.log]
set slog [file join $log_dir rx_cfo_${tag}_sim.log]
set gate [file join $rpt_dir rx_cfo_${tag}_gate.txt]

proc gate_out {msg path} {
    puts ""; puts [string repeat = 72]; puts $msg; puts [string repeat = 72]
    set fh [open $path w]; puts $fh $msg; close $fh
}

if {[catch {create_project -in_memory -part $part rx_cfo_inmem} cp_err]} {
    puts "*** WARNING: requested part '$part' not installed: $cp_err"
    set fb_candidates {xczu49dr-ffvf1760-2-e xczu7eg-ffvc1156-2-i xczu7ev-ffvc1156-2-e \
                       xczu5ev-sfvc784-2-i xczu3eg-sbva484-1-i}
    set chose ""
    foreach fb $fb_candidates {
        if {![catch {create_project -in_memory -part $fb rx_cfo_inmem} _]} { set chose $fb; break }
    }
    if {$chose eq ""} { gate_out "BLOCKED_PART_NOT_INSTALLED: requested=$part" $gate; exit 1 }
    set part_fallback_note "SIM_FALLBACK_PART: requested=$part used=$chose (xsim only)"
    set part $chose
    puts $part_fallback_note
}
puts "RX-CFO-$tag: target part = $part  (locked = $part_locked)"

# ---- 1. Register IPs ------------------------------------------------------
set ip_stage [file join $build ip_stage]
file mkdir $ip_stage
foreach n {xfft_N xfft_2N xfft_IFFT} {
    set src [file join $root rtl $n ${n}.xci]
    set dst_dir [file join $ip_stage $n]
    file mkdir $dst_dir
    set dst [file join $dst_dir ${n}.xci]
    file copy -force $src $dst
    read_ip $dst
}
foreach ip [get_ips xfft_N xfft_2N xfft_IFFT] { catch {set_property IS_LOCKED false $ip} }
upgrade_ip [get_ips xfft_N xfft_2N xfft_IFFT]
reset_target all [get_ips xfft_N xfft_2N xfft_IFFT]
generate_target {synthesis simulation} [get_ips xfft_N xfft_2N xfft_IFFT]

set ip_gen_root [file join $root vivado_xsim DSP_Rx.gen sources_1 ip]
set ip_sim_files [list]
foreach n {xfft_N xfft_2N xfft_IFFT} {
    foreach pat {hdl sim} {
        foreach f [glob -nocomplain [file join $ip_gen_root $n $pat *.vhd]] { lappend ip_sim_files $f }
        foreach f [glob -nocomplain [file join $ip_gen_root $n $pat *.v]]   { lappend ip_sim_files $f }
    }
}
puts "RX-CFO-$tag: IP sim file count = [llength $ip_sim_files]"

# ---- 2. Compile ---------------------------------------------------------
set tb_file [file join $root tb rx_cfo_allmods_tb.sv]
set rtl_files [glob [file join $root rtl *.v]]

set vlog_files [list]
set vhdl_files [list]
foreach f $ip_sim_files {
    set ext [string tolower [file extension $f]]
    if {$ext eq ".vhd" || $ext eq ".vhdl"} { lappend vhdl_files $f } else { lappend vlog_files $f }
}
cd $build
if {[llength $vhdl_files] > 0} {
    set cmd [list xvhdl --nolog -work xil_defaultlib]
    foreach f $vhdl_files { lappend cmd $f }
    set rc [catch {exec {*}$cmd 2>@1} out]
    set fh [open $clog w]; puts $fh "=== xvhdl IP ===\n$out"; close $fh
    if {$rc != 0} { cd $root; gate_out "BLOCKED_COMPILE_ERROR (xvhdl ip)" $gate; exit 1 }
}
if {[llength $vlog_files] > 0} {
    set cmd [list xvlog --nolog -work xil_defaultlib]
    foreach f $vlog_files { lappend cmd $f }
    set rc [catch {exec {*}$cmd 2>@1} out]
    set fh [open $clog a]; puts $fh "\n=== xvlog IP ===\n$out"; close $fh
    if {$rc != 0} { cd $root; gate_out "BLOCKED_COMPILE_ERROR (xvlog ip)" $gate; exit 1 }
}
set cmd [list xvlog --nolog]
foreach f $rtl_files { lappend cmd $f }
set rc [catch {exec {*}$cmd 2>@1} out]
set fh [open $clog a]; puts $fh "\n=== xvlog RTL ===\n$out"; close $fh
if {$rc != 0} { cd $root; gate_out "BLOCKED_COMPILE_ERROR (xvlog rtl)" $gate; puts $out; exit 1 }

set cmd [list xvlog --nolog -sv $tb_file]
set rc [catch {exec {*}$cmd 2>@1} out]
set fh [open $clog a]; puts $fh "\n=== xvlog TB ===\n$out"; close $fh
if {$rc != 0} { cd $root; gate_out "BLOCKED_COMPILE_ERROR (xvlog tb)" $gate; puts $out; exit 1 }

# ---- 3. Elab ------------------------------------------------------------
catch {file delete [file join $build rtl]}
catch {file link -symbolic [file join $build rtl] [file join $root rtl]}
catch {file copy -force [file join $root rtl rx_equalizer_recip_lut.hex] \
                        [file join $build rx_equalizer_recip_lut.hex]}
catch {file copy -force [file join $root golden rx_downstream ce_pilot_recip.hex] \
                        [file join $build ce_pilot_recip.hex]}

set cmd [list xelab --nolog -L work -L xil_defaultlib -L xfft_v9_1_8 \
            --snapshot rx_cfo_snap work.rx_cfo_allmods_tb]
set rc [catch {exec {*}$cmd 2>@1} out]
set fh [open $elog w]; puts $fh $out; close $fh
if {$rc != 0 || ![string match "*Built simulation snapshot*" $out]} {
    cd $root; gate_out "BLOCKED_COMPILE_ERROR (xelab)" $gate
    puts [string range $out end-1500 end]; exit 1
}

# ---- 4. Sim -------------------------------------------------------------
set cmd [list xsim --nolog rx_cfo_snap --runall --onerror quit]
foreach pa $plusargs { lappend cmd --testplusarg $pa }
set rc [catch {exec {*}$cmd 2>@1} simout]
set fh [open $slog w]; puts $fh $simout; close $fh
cd $root

set fb_line ""
if {$part_fallback_note ne ""} { set fb_line "\n$part_fallback_note" }
if {[string match "*GATE: PASS_RX_CFO*" $simout]} {
    gate_out "RX_CFO_${tag}_GATE: PASS (part=$part)$fb_line" $gate
    exit 0
} elseif {[string match "*GATE: FAIL_RX_CFO*" $simout]} {
    gate_out "RX_CFO_${tag}_GATE: FAIL (see $slog)$fb_line" $gate
    exit 1
} elseif {$rc != 0} {
    gate_out "RX_CFO_${tag}_GATE: BLOCKED (xsim exit $rc)$fb_line" $gate
    exit 1
} else {
    gate_out "RX_CFO_${tag}_GATE: FAIL (no gate line)$fb_line" $gate
    exit 1
}
