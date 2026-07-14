# run_p5_coverage.tcl — B1 coverage-enabled re-run of the P5-EQUIV TB.
# Same setup as run_p5_d_meyr_cfo_top_unit.tcl, but xelab/xsim with
# -cov_db so a coverage database accumulates across the 17-case sweep.

set root [pwd]
set part_locked "xczu9eg-ffvb1156-2-e"
set part        $part_locked
if {[info exists ::env(XFFT_TARGET_PART)]} { set part $::env(XFFT_TARGET_PART) }
set part_fallback_note ""

set log_dir [file join $root vivado_xsim logs p5_cov_build]
file delete -force $log_dir; file mkdir $log_dir
set rpt_dir [file join $root reports p5_coverage]
file mkdir $rpt_dir
set cov_db  [file join $rpt_dir cov_db]
file mkdir $cov_db

set clog [file join $log_dir compile.log]
set elog [file join $log_dir elab.log]
set slog [file join $log_dir sim.log]
set gate [file join $rpt_dir p5_coverage_run.txt]

proc gate_out {msg path} {
    puts ""; puts [string repeat = 72]; puts $msg; puts [string repeat = 72]
    set fh [open $path w]; puts $fh $msg; close $fh
}

if {[catch {create_project -in_memory -part $part p5_cov_inmem} _]} {
    set fb {xczu7eg-ffvc1156-2-i xczu7ev-ffvc1156-2-e}
    set chose ""
    foreach f $fb {
        if {![catch {create_project -in_memory -part $f p5_cov_inmem} _]} { set chose $f; break }
    }
    if {$chose eq ""} { gate_out "BLOCKED_PART" $gate; exit 1 }
    set part $chose
}

# IPs
set ip_stage [file join $log_dir ip_stage]
file mkdir $ip_stage
foreach n {xfft_N xfft_2N xfft_IFFT} {
    set src [file join $root rtl $n ${n}.xci]
    set dst_dir [file join $ip_stage $n]; file mkdir $dst_dir
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

set rtl_files [list \
    [file join $root rtl complex_mult.v] \
    [file join $root rtl complex_mult_32.v] \
    [file join $root rtl meyr_ak_buf.v] \
    [file join $root rtl meyr_zeropad.v] \
    [file join $root rtl meyr_FFT_ak_dut.v] \
    [file join $root rtl meyr_feeder.v] \
    [file join $root rtl meyr_Rm_dut.v] \
    [file join $root rtl meyr_ifft_peak_dut.v] \
    [file join $root rtl meyr_cfo_top.v]]
set tb_file [file join $root tb p5_d_meyr_cfo_top_unit_tb.sv]
set inv_file [file join $root tb p5_invariants.sv]

set vlog_files [list]; set vhdl_files [list]
foreach f $ip_sim_files {
    set ext [string tolower [file extension $f]]
    if {$ext eq ".vhd" || $ext eq ".vhdl"} { lappend vhdl_files $f } else { lappend vlog_files $f }
}

cd $log_dir

if {[llength $vhdl_files] > 0} {
    set cmd [list xvhdl --nolog -work xil_defaultlib]
    foreach f $vhdl_files { lappend cmd $f }
    set rc [catch {exec {*}$cmd 2>@1} out]
    set fh [open $clog w]; puts $fh "=== xvhdl IP ===\n$out"; close $fh
    if {$rc != 0} { cd $root; gate_out "BLOCKED xvhdl" $gate; exit 1 }
}
if {[llength $vlog_files] > 0} {
    set cmd [list xvlog --nolog -work xil_defaultlib]
    foreach f $vlog_files { lappend cmd $f }
    set rc [catch {exec {*}$cmd 2>@1} out]
    set fh [open $clog a]; puts $fh "\n=== xvlog IP ===\n$out"; close $fh
    if {$rc != 0} { cd $root; gate_out "BLOCKED xvlog ip" $gate; exit 1 }
}
set cmd [list xvlog --nolog]
foreach f $rtl_files { lappend cmd $f }
set rc [catch {exec {*}$cmd 2>@1} out]
set fh [open $clog a]; puts $fh "\n=== xvlog RTL ===\n$out"; close $fh
if {$rc != 0} { cd $root; gate_out "BLOCKED xvlog rtl" $gate; puts $out; exit 1 }

set cov_file [file join $root tb p5_functional_cov.sv]
set cmd [list xvlog --nolog -sv $inv_file $cov_file $tb_file]
set rc [catch {exec {*}$cmd 2>@1} out]
set fh [open $clog a]; puts $fh "\n=== xvlog TB+inv ===\n$out"; close $fh
if {$rc != 0} { cd $root; gate_out "BLOCKED xvlog tb" $gate; puts $out; exit 1 }

# Coverage-enabled elab (B1-MEAS: -cc_type bcst = branch+cond+stmt+toggle)
set cmd [list xelab --nolog \
            -cc_type bcst -cc_dir $cov_db -cc_db p5_cov \
            -L work -L xil_defaultlib -L xfft_v9_1_8 \
            --snapshot p5_cov_snap work.p5_d_meyr_cfo_top_unit_tb]
set rc [catch {exec {*}$cmd 2>@1} out]
set fh [open $elog w]; puts $fh $out; close $fh
if {$rc != 0 || ![string match "*Built simulation snapshot*" $out]} {
    cd $root; gate_out "BLOCKED_COMPILE_ERROR (xelab cov)" $gate
    puts [string range $out end-1500 end]; exit 1
}

# Coverage-enabled sim (xsim auto-collects when snapshot was elaborated with -cc_type)
set cmd [list xsim --nolog p5_cov_snap --runall --onerror quit]
set rc [catch {exec {*}$cmd 2>@1} simout]
set fh [open $slog w]; puts $fh $simout; close $fh
cd $root

if {[string match "*GATE: PASS_P5_D_LEVEL1*" $simout]} {
    gate_out "P5_COVERAGE_RUN: PASS (sim 17/17, cov_db=$cov_db)" $gate
    exit 0
} else {
    gate_out "P5_COVERAGE_RUN: FAIL (sim line missing)" $gate
    exit 1
}
