# run_p5_03_nightly.tcl - P5-03 spec (d) bit-exact gate (real IPs).

set root [pwd]
set part_locked "xczu9eg-ffvb1156-2-e"
set part        $part_locked
if {[info exists ::env(XFFT_TARGET_PART)]} { set part $::env(XFFT_TARGET_PART) }
set part_fallback_note ""

set log_dir [file join $root vivado_xsim logs]
set rpt_dir [file join $root vivado_xsim reports]
set build   [file join $log_dir p5_03_nightly_build]
file mkdir $log_dir; file mkdir $rpt_dir
file delete -force $build; file mkdir $build

set clog [file join $log_dir p5_03_nightly_compile.log]
set elog [file join $log_dir p5_03_nightly_elab.log]
set slog [file join $log_dir p5_03_nightly_sim.log]
set gate [file join $rpt_dir p5_03_nightly_gate.txt]

proc gate_out {msg path} {
    puts ""; puts [string repeat = 72]; puts $msg; puts [string repeat = 72]
    set fh [open $path w]; puts $fh $msg; close $fh
}

if {[catch {create_project -in_memory -part $part p5_03_nightly_inmem} _]} {
    set fb_candidates {xczu7eg-ffvc1156-2-i xczu7ev-ffvc1156-2-e}
    set chose ""
    foreach fb $fb_candidates {
        if {![catch {create_project -in_memory -part $fb p5_03_nightly_inmem} _]} { set chose $fb; break }
    }
    if {$chose eq ""} { gate_out "BLOCKED_PART_NOT_INSTALLED" $gate; exit 1 }
    set part_fallback_note "SIM_FALLBACK_PART: requested=$part used=$chose"
    set part $chose
}

set ip_stage [file join $build ip_stage]; file mkdir $ip_stage
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

# ---- xfft IP simulation compile (FIX ported from run_p5_d_meyr_cfo_top_unit.tcl, T1) -
# The old approach globbed a hard-coded `vivado_xsim/DSP_Rx.gen/sources_1/ip`
# path that does NOT exist for this in-memory project -> ZERO files -> xfft
# behavioral model never compiled -> "Module xfft_N not found" at elab. It also
# flat-compiled every file into xil_defaultlib and linked the WRONG IP version
# (-L xfft_v9_1_8). The fix below: (1) derive the real generated sim dir,
# (2) compile each support file into its own versioned library in the order
# from <ip>.xml, (3) feed every used IP library + secureip/unisim to xelab,
# (4) seed a local xsim.ini pointing at the pre-compiled simlib.
set tb_file [file join $root tb p5_03_continuous_nightly_tb.sv]
set rtl_files [glob [file join $root rtl *.v]]

# (library  hdl-basename) in dependency / compile order, from <ip>.xml.
set ip_hdl_order {
    {xbip_utils_v3_0_10        xbip_utils_v3_0_vh_rfs.vhd}
    {axi_utils_v2_0_6          axi_utils_v2_0_vh_rfs.vhd}
    {c_reg_fd_v12_0_6          c_reg_fd_v12_0_vh_rfs.vhd}
    {xbip_dsp48_wrapper_v3_0_4 xbip_dsp48_wrapper_v3_0_vh_rfs.vhd}
    {xbip_pipe_v3_0_6          xbip_pipe_v3_0_vh_rfs.vhd}
    {xbip_dsp48_addsub_v3_0_6  xbip_dsp48_addsub_v3_0_vh_rfs.vhd}
    {xbip_addsub_v3_0_6        xbip_addsub_v3_0_vh_rfs.vhd}
    {c_addsub_v12_0_14         c_addsub_v12_0_vh_rfs.vhd}
    {c_mux_bit_v12_0_6         c_mux_bit_v12_0_vh_rfs.vhd}
    {c_shift_ram_v12_0_14      c_shift_ram_v12_0_vh_rfs.vhd}
    {xbip_bram18k_v3_0_6       xbip_bram18k_v3_0_vh_rfs.vhd}
    {mult_gen_v12_0_17         mult_gen_v12_0_vh_rfs.vhd}
    {cmpy_v6_0_20              cmpy_v6_0_vh_rfs.vhd}
    {floating_point_v7_0_19    floating_point_v7_0_vh_rfs.vhd}
    {xfft_v9_1_6               xfft_v9_1_vh_rfs.vhd}
}

# Locate the per-IP generated-source dir: standalone managed gen dir, then the
# in-memory IP_DIR/IP_OUTPUT_DIR, then a glob under the staged ip dir. Returns
# "" if no dir with both hdl/ and sim/ for $n is found (NEVER hard-coded).
proc find_ip_gen_dir {root build n} {
    set cands [list]
    lappend cands [file join $root build_zcu216_ip xfft_ip.gen sources_1 ip $n]
    set ipobj [get_ips $n]
    if {[llength $ipobj] == 1} {
        foreach prop {IP_DIR IP_OUTPUT_DIR} {
            if {![catch {set d [get_property $prop $ipobj]}] && $d ne ""} {
                lappend cands $d
            }
        }
    }
    foreach g [glob -nocomplain -directory [file join $build ip_stage $n] -type d *] {
        lappend cands $g
    }
    foreach c $cands {
        if {$c eq ""} { continue }
        if {[file isdirectory [file join $c hdl]] \
            && [file isdirectory [file join $c sim]]} {
            return $c
        }
        foreach sub [glob -nocomplain -directory $c -type d *] {
            if {[file isdirectory [file join $sub hdl]] \
                && [file isdirectory [file join $sub sim]]} {
                return $sub
            }
        }
    }
    return ""
}

# Build the ordered (library . absolute-file) list: shared support files once
# (deduped, identical across the three IPs), then each IP's sim/<ip>.vhd wrapper.
set ip_sim_pairs [list]
set ip_gen_dirs  [list]
foreach n {xfft_N xfft_2N xfft_IFFT} {
    set d [find_ip_gen_dir $root $build $n]
    if {$d eq ""} { puts "*** WARNING: no generated sim dir found for $n"; continue }
    lappend ip_gen_dirs [list $n $d]
}
if {[llength $ip_gen_dirs] == 0} {
    gate_out "BLOCKED_NO_IP_SIM_SOURCES: no <ip>/{hdl,sim} dir located\
              (looked under build_zcu216_ip + in-memory IP_DIR + staged ip dir)" $gate
    exit 1
}
set shared_dir [lindex [lindex $ip_gen_dirs 0] 1]
foreach pair $ip_hdl_order {
    set lib  [lindex $pair 0]
    set base [lindex $pair 1]
    set f    [file join $shared_dir hdl $base]
    if {![file exists $f]} {
        gate_out "BLOCKED_NO_IP_SIM_SOURCES: missing support file $f" $gate
        exit 1
    }
    lappend ip_sim_pairs [list $lib $f]
}
foreach entry $ip_gen_dirs {
    set n [lindex $entry 0]
    set d [lindex $entry 1]
    set f [file join $d sim ${n}.vhd]
    if {![file exists $f]} {
        gate_out "BLOCKED_NO_IP_SIM_SOURCES: missing sim wrapper $f" $gate
        exit 1
    }
    lappend ip_sim_pairs [list xil_defaultlib $f]
}
if {[llength $ip_sim_pairs] == 0} {
    gate_out "BLOCKED_NO_IP_SIM_SOURCES: derived compile list is empty" $gate
    exit 1
}

cd $build
# Seed a local xsim.ini: explicit local mappings for each versioned IP library +
# xil_defaultlib (our own writable dir), then include the pre-compiled simlib so
# secureip/unisim/xpm/xilinx_vip resolve. Export XSIM_INI for every xvhdl/xelab.
set simlib_ini [file join $root sim_out xsim_simlib xsim.ini]
if {[file exists $simlib_ini]} {
    set local_ini [file join $build xsim.ini]
    set ip_lib_dir [file join $build ip_libs]
    file mkdir $ip_lib_dir
    set ih [open $local_ini w]
    puts $ih "-- Auto-generated by run_p5_03_nightly.tcl"
    puts $ih "include \$XILINX_VIVADO/data/xsim/ip/xsim_ip.ini"
    foreach pair $ip_hdl_order {
        set _lib [lindex $pair 0]
        puts $ih "$_lib=[file join $ip_lib_dir $_lib]"
    }
    puts $ih "xil_defaultlib=[file join $ip_lib_dir xil_defaultlib]"
    set sh [open $simlib_ini r]
    puts $ih [read $sh]
    close $sh
    close $ih
    set ::env(XSIM_INI) $local_ini
    puts "P5-03-NIGHTLY: using xsim.ini = $local_ini (IP libs -> $ip_lib_dir)"
} else {
    puts "*** WARNING: simlib xsim.ini not found at $simlib_ini -- elaboration\
          may fail to resolve secureip/unisim primitives."
}

# Compile each IP sim file into its packaging-assigned library, in order. The
# distinct libraries created here are fed to xelab as -L flags below.
set ip_libs [list]
set first_clog 1
foreach pair $ip_sim_pairs {
    set lib  [lindex $pair 0]
    set f    [lindex $pair 1]
    if {[lsearch -exact $ip_libs $lib] < 0} { lappend ip_libs $lib }
    set ext [string tolower [file extension $f]]
    if {$ext eq ".vhd" || $ext eq ".vhdl"} {
        set cmd [list xvhdl --nolog -work $lib $f]; set tag "xvhdl IP ($lib)"
    } elseif {$ext eq ".sv"} {
        set cmd [list xvlog --nolog -sv -work $lib $f]; set tag "xvlog IP sv ($lib)"
    } else {
        set cmd [list xvlog --nolog -work $lib $f]; set tag "xvlog IP ($lib)"
    }
    set rc [catch {exec {*}$cmd 2>@1} out]
    if {$first_clog} { set fh [open $clog w]; set first_clog 0 } else { set fh [open $clog a] }
    puts $fh "\n=== $tag : [file tail $f] ===\n$out"; close $fh
    if {$rc != 0} { cd $root; gate_out "BLOCKED_COMPILE_ERROR ($tag)" $gate; puts $out; exit 1 }
}

set cmd [list xvlog --nolog]; foreach f $rtl_files { lappend cmd $f }
set rc [catch {exec {*}$cmd 2>@1} out]
set fh [open $clog a]; puts $fh "\n=== xvlog RTL ===\n$out"; close $fh
if {$rc != 0} { cd $root; gate_out "BLOCKED_COMPILE_ERROR (xvlog rtl)" $gate; puts $out; exit 1 }

set cmd [list xvlog --nolog -sv $tb_file]
set rc [catch {exec {*}$cmd 2>@1} out]
set fh [open $clog a]; puts $fh "\n=== xvlog TB ===\n$out"; close $fh
if {$rc != 0} { cd $root; gate_out "BLOCKED_COMPILE_ERROR (xvlog tb)" $gate; puts $out; exit 1 }

# -L flags must cover work + xil_defaultlib, every versioned IP library we
# compiled ($ip_libs, incl. xfft_v9_1_6 -- NOT xfft_v9_1_8), and the pre-compiled
# Xilinx primitive libs (secureip/unisim/...). (FIX ported from T1.)
set cmd [list xelab --nolog -L work -L xil_defaultlib]
foreach lib $ip_libs {
    if {$lib ne "work" && $lib ne "xil_defaultlib"} { lappend cmd -L $lib }
}
foreach lib {secureip unisim unisims_ver unimacro unimacro_ver xpm xilinx_vip} {
    lappend cmd -L $lib
}
lappend cmd --snapshot p5_03_nightly_snap work.p5_03_continuous_nightly_tb
set rc [catch {exec {*}$cmd 2>@1} out]
set fh [open $elog w]; puts $fh $out; close $fh
if {$rc != 0 || ![string match "*Built simulation snapshot*" $out]} {
    cd $root; gate_out "BLOCKED_COMPILE_ERROR (xelab)" $gate
    puts [string range $out end-1500 end]; exit 1
}

set cmd [list xsim --nolog p5_03_nightly_snap --runall --onerror quit]
set rc [catch {exec {*}$cmd 2>@1} simout]
set fh [open $slog w]; puts $fh $simout; close $fh
cd $root

set fb_line ""
if {$part_fallback_note ne ""} { set fb_line "\n$part_fallback_note" }
if {[string match "*GATE: PASS_P5_CONT_NIGHTLY*" $simout]} {
    gate_out "P5_CONT_NIGHTLY_GATE: PASS (part=$part)$fb_line" $gate; exit 0
} elseif {[string match "*GATE: FAIL_P5_CONT_NIGHTLY*" $simout]} {
    gate_out "P5_CONT_NIGHTLY_GATE: FAIL (see $slog)$fb_line" $gate; exit 1
} elseif {$rc != 0} {
    gate_out "P5_CONT_NIGHTLY_GATE: BLOCKED (xsim exit $rc)$fb_line" $gate; exit 1
} else {
    gate_out "P5_CONT_NIGHTLY_GATE: FAIL (no gate line)$fb_line" $gate; exit 1
}
