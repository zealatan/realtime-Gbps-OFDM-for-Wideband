# run_rx_full_chain.tcl
#
# FULL-RX INTEGRATION STEP 2 gate: SYNC -> FULL DOWNSTREAM (rx_full_chain_top).
# Drives rx_full_chain_top (frozen synchronizer + frozen rx_downstream_top :
# FFT -> CE -> EQ -> DEMOD) with the sync-capable golden frame + pilot ROM and
# checks (a) sync lock and (b) END-TO-END demod BER vs
# golden/rx_downstream/tx_bits.txt.  Real Xilinx xfft 9.1 IPs (xsim).
#
# Structure cloned from run_rx_full_step1.tcl (proven flow for the wrapper +
# all rtl + the 3 xfft IPs).  Adds ONLY: the new TB, the gate strings, and the
# downstream-module $readmemh resolution (symlink rtl/ + drop the EQ LUT into
# the sim cwd) — the same convention the standalone rx_downstream gate uses.

set root [pwd]
set part_locked "xczu9eg-ffvb1156-2-e"
set part        $part_locked
if {[info exists ::env(XFFT_TARGET_PART)]} { set part $::env(XFFT_TARGET_PART) }
set part_fallback_note ""

set log_dir [file join $root vivado_xsim logs]
set rpt_dir [file join $root vivado_xsim reports]
set build   [file join $log_dir xcvr_3mode_build]
file mkdir $log_dir
file mkdir $rpt_dir
file delete -force $build
file mkdir $build

set clog [file join $log_dir xcvr_3mode_compile.log]
set elog [file join $log_dir xcvr_3mode_elab.log]
set slog [file join $log_dir xcvr_3mode_sim.log]
set gate [file join $rpt_dir xcvr_3mode_gate.txt]

proc gate_out {msg path} {
    puts ""; puts [string repeat = 72]; puts $msg; puts [string repeat = 72]
    set fh [open $path w]; puts $fh $msg; close $fh
}

if {[catch {create_project -in_memory -part $part xcvr_3mode_inmem} cp_err]} {
    puts "*** WARNING: requested part '$part' not installed: $cp_err"
    set fb_candidates {xczu49dr-ffvf1760-2-e xczu7eg-ffvc1156-2-i xczu7ev-ffvc1156-2-e \
                       xczu5ev-sfvc784-2-i xczu3eg-sbva484-1-i}
    set chose ""
    foreach fb $fb_candidates {
        if {![catch {create_project -in_memory -part $fb xcvr_3mode_inmem} _]} {
            set chose $fb; break
        }
    }
    if {$chose eq ""} {
        gate_out "BLOCKED_PART_NOT_INSTALLED: requested=$part" $gate; exit 1
    }
    set part_fallback_note "SIM_FALLBACK_PART: requested=$part used=$chose (xsim only)"
    set part $chose
    puts $part_fallback_note
}
puts "XCVR-3MODE: target part = $part  (locked = $part_locked)"

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
foreach ip [get_ips xfft_N xfft_2N xfft_IFFT] {
    catch {set_property IS_LOCKED false $ip}
}
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
puts "XCVR-3MODE: IP sim file count = [llength $ip_sim_files]"

# ---- 2. Compile ---------------------------------------------------------
set tb_file [file join $root tb ofdm_transceiver_top_tb.sv]
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
# Downstream modules ($readmemh) resolve their default RELATIVE paths from the
# sim cwd ($build):
#   rx_ch_est    CE_W_ROM  = "rtl/rx_ch_est_rom/ce_interp_W.hex"
#   rx_equalizer LUT_FILE  = "rx_equalizer_recip_lut.hex"  (bare filename)
# So symlink the repo rtl/ tree into $build and drop the bare LUT next to it.
catch {file delete [file join $build rtl]}
catch {file link -symbolic [file join $build rtl] [file join $root rtl]}
catch {file copy -force [file join $root rtl rx_equalizer_recip_lut.hex] \
                        [file join $build rx_equalizer_recip_lut.hex]}
# CE pilot-reciprocal ROM (replaces the old CE divide); default bare filename
# "ce_pilot_recip.hex" resolves from $build cwd.
catch {file copy -force [file join $root golden rx_downstream ce_pilot_recip.hex] \
                        [file join $build ce_pilot_recip.hex]}
# rx_ber_checker reference ROM (default bare filename "rx_ber_ref_rom.hex").
catch {file copy -force [file join $root rtl rx_ber_ref_rom.hex] \
                        [file join $build rx_ber_ref_rom.hex]}

set cmd [list xelab --nolog -L work -L xil_defaultlib -L xfft_v9_1_8 \
            --snapshot xcvr_3mode_snap work.ofdm_transceiver_top_tb]
set rc [catch {exec {*}$cmd 2>@1} out]
set fh [open $elog w]; puts $fh $out; close $fh
if {$rc != 0 || ![string match "*Built simulation snapshot*" $out]} {
    cd $root; gate_out "BLOCKED_COMPILE_ERROR (xelab)" $gate
    puts [string range $out end-1500 end]; exit 1
}

# ---- 4. Sim -------------------------------------------------------------
set cmd [list xsim --nolog xcvr_3mode_snap --runall --onerror quit]
set rc [catch {exec {*}$cmd 2>@1} simout]
set fh [open $slog w]; puts $fh $simout; close $fh
cd $root

set fb_line ""
if {$part_fallback_note ne ""} { set fb_line "\n$part_fallback_note" }
if {[string match "*GATE: PASS_TRANSCEIVER_3MODE*" $simout]} {
    gate_out "TRANSCEIVER_3MODE_GATE: PASS (part=$part)$fb_line" $gate
    exit 0
} elseif {[string match "*GATE: FAIL_TRANSCEIVER_3MODE*" $simout]} {
    gate_out "TRANSCEIVER_3MODE_GATE: FAIL (see $slog)$fb_line" $gate
    exit 1
} elseif {$rc != 0} {
    gate_out "TRANSCEIVER_3MODE_GATE: BLOCKED (xsim exit $rc)$fb_line" $gate
    exit 1
} else {
    gate_out "TRANSCEIVER_3MODE_GATE: FAIL (no gate line)$fb_line" $gate
    exit 1
}
