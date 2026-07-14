# run_rx_fft_frontend_rand_unit.tcl
#
# RX-FFT-FRONTEND ROBUST multi-vector sim with the REAL Xilinx xfft_N 9.1 IP.
#   - Same IP compile flow as run_rx_fft_frontend_unit.tcl (proven), but
#     drives tb/rx_fft_frontend_rand_tb.sv over N random + edge vectors
#     (golden/rx_fft_rand/*).
#   - Reports PASS / FAIL based on the "RESULT: PASS" gate line from the TB.
#
# Does NOT modify any existing RTL/shared files.

set root [pwd]
set part_locked "xczu49dr-ffvf1760-2-e"   ;# ZCU216 RF part (matches xfft .xci)
set part        $part_locked
if {[info exists ::env(XFFT_TARGET_PART)]} { set part $::env(XFFT_TARGET_PART) }
set part_fallback_note ""

# number of vectors (line1 of meta.txt = "N_VEC <n>")
set n_vec 28
set metaf [file join $root golden rx_fft_rand meta.txt]
if {[file exists $metaf]} {
    set mh [open $metaf r]; set ml [gets $mh]; close $mh
    if {[regexp {N_VEC\s+(\d+)} $ml -> nv]} { set n_vec $nv }
}
puts "RX-FFT-RAND: N_VEC = $n_vec"

set log_dir [file join $root vivado_xsim logs]
set rpt_dir [file join $root vivado_xsim reports]
set build   [file join $log_dir rxfft_rand_build]
file mkdir $log_dir
file mkdir $rpt_dir
file delete -force $build
file mkdir $build

set clog [file join $log_dir rxfft_rand_compile.log]
set elog [file join $log_dir rxfft_rand_elab.log]
set slog [file join $log_dir rxfft_rand_sim.log]
set gate [file join $rpt_dir rxfft_rand_gate.txt]

proc gate_out {msg path} {
    puts ""
    puts [string repeat = 72]
    puts $msg
    puts [string repeat = 72]
    set fh [open $path w]; puts $fh $msg; close $fh
}

if {[catch {create_project -in_memory -part $part rxfftr_inmem} cp_err]} {
    puts "*** WARNING: requested part '$part' not installed: $cp_err"
    set fb_candidates {xczu7eg-ffvc1156-2-i xczu7ev-ffvc1156-2-e \
                       xczu5ev-sfvc784-2-i xczu3eg-sbva484-1-i \
                       xczu9eg-ffvb1156-2-e}
    set chose ""
    foreach fb $fb_candidates {
        if {![catch {create_project -in_memory -part $fb rxfftr_inmem} _]} {
            set chose $fb; break
        }
    }
    if {$chose eq ""} {
        gate_out "BLOCKED_PART_NOT_INSTALLED: requested=$part" $gate; exit 1
    }
    set part_fallback_note "SIM_FALLBACK_PART: requested=$part used=$chose \
        (xsim only - synth/timing/bitstream MUST run on the locked part)"
    set part $chose
    puts $part_fallback_note
}
puts "RX-FFT-RAND: target part = $part  (locked = $part_locked)"

# ---- 1. Register xfft_N + generate simulation sources ----------------
set ip_stage [file join $build ip_stage]
file mkdir $ip_stage
set n xfft_N
set src [file join $root rtl $n ${n}.xci]
if {![file exists $src]} { gate_out "BLOCKED_XCI_NOT_FOUND: $src" $gate; exit 1 }
set dst_dir [file join $ip_stage $n]
file mkdir $dst_dir
set dst [file join $dst_dir ${n}.xci]
file copy -force $src $dst
read_ip $dst
foreach ip [get_ips $n] { catch {set_property IS_LOCKED false $ip} }
upgrade_ip [get_ips $n]
reset_target all [get_ips $n]
generate_target {synthesis simulation} [get_ips $n]

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
        if {[file isdirectory [file join $c hdl]] && [file isdirectory [file join $c sim]]} { return $c }
        foreach sub [glob -nocomplain -directory $c -type d *] {
            if {[file isdirectory [file join $sub hdl]] && [file isdirectory [file join $sub sim]]} { return $sub }
        }
    }
    return ""
}

set gen_dir [find_ip_gen_dir $root $build $n]
if {$gen_dir eq ""} {
    gate_out "BLOCKED_NO_IP_SIM_SOURCES: no $n/{hdl,sim} dir located" $gate
    exit 1
}
puts "RX-FFT-RAND: xfft_N gen dir = $gen_dir"

set ip_sim_pairs [list]
foreach pair $ip_hdl_order {
    set lib  [lindex $pair 0]
    set base [lindex $pair 1]
    set f    [file join $gen_dir hdl $base]
    if {![file exists $f]} { gate_out "BLOCKED_NO_IP_SIM_SOURCES: missing $f" $gate; exit 1 }
    lappend ip_sim_pairs [list $lib $f]
}
set wrapf [file join $gen_dir sim ${n}.vhd]
if {![file exists $wrapf]} { gate_out "BLOCKED_NO_IP_SIM_SOURCES: missing wrapper $wrapf" $gate; exit 1 }
lappend ip_sim_pairs [list xil_defaultlib $wrapf]

# ---- 2. Point xsim at the pre-compiled Xilinx simlib ------------------
set simlib_ini [file join $root sim_out xsim_simlib xsim.ini]
cd $build
if {[file exists $simlib_ini]} {
    set local_ini [file join $build xsim.ini]
    set ip_lib_dir [file join $build ip_libs]
    file mkdir $ip_lib_dir
    set ih [open $local_ini w]
    puts $ih "-- Auto-generated by run_rx_fft_frontend_rand_unit.tcl"
    puts $ih "include \$XILINX_VIVADO/data/xsim/ip/xsim_ip.ini"
    foreach pair $ip_hdl_order {
        set _lib [lindex $pair 0]
        puts $ih "$_lib=[file join $ip_lib_dir $_lib]"
    }
    puts $ih "xil_defaultlib=[file join $ip_lib_dir xil_defaultlib]"
    set sh [open $simlib_ini r]; puts $ih [read $sh]; close $sh
    close $ih
    set ::env(XSIM_INI) $local_ini
    puts "RX-FFT-RAND: using xsim.ini = $local_ini"
} else {
    puts "*** WARNING: simlib xsim.ini not found at $simlib_ini"
}

# ---- 3. Compile IP sim sources into their versioned libraries ---------
set ip_libs [list]
set first_clog 1
foreach pair $ip_sim_pairs {
    set lib  [lindex $pair 0]
    set f    [lindex $pair 1]
    if {[lsearch -exact $ip_libs $lib] < 0} { lappend ip_libs $lib }
    set cmd [list xvhdl --nolog -work $lib $f]
    set rc [catch {exec {*}$cmd 2>@1} out]
    if {$first_clog} { set fh [open $clog w]; set first_clog 0 } else { set fh [open $clog a] }
    puts $fh "\n=== xvhdl ($lib) : [file tail $f] ===\n$out"; close $fh
    if {$rc != 0} { cd $root; gate_out "BLOCKED_COMPILE_ERROR (xvhdl $lib [file tail $f])" $gate; puts $out; exit 1 }
}

# ---- 4. Compile DUT RTL + TB ------------------------------------------
set cmd [list xvlog --nolog [file join $root rtl rx_fft_frontend.v]]
set rc [catch {exec {*}$cmd 2>@1} out]
set fh [open $clog a]; puts $fh "\n=== xvlog RTL ===\n$out"; close $fh
if {$rc != 0} { cd $root; gate_out "BLOCKED_COMPILE_ERROR (xvlog rtl)" $gate; puts $out; exit 1 }

set cmd [list xvlog --nolog -sv [file join $root tb rx_fft_frontend_rand_tb.sv]]
set rc [catch {exec {*}$cmd 2>@1} out]
set fh [open $clog a]; puts $fh "\n=== xvlog TB ===\n$out"; close $fh
if {$rc != 0} { cd $root; gate_out "BLOCKED_COMPILE_ERROR (xvlog tb)" $gate; puts $out; exit 1 }

# ---- 5. Elaborate -----------------------------------------------------
set cmd [list xelab --nolog -L work -L xil_defaultlib]
foreach lib $ip_libs {
    if {$lib ne "work" && $lib ne "xil_defaultlib"} { lappend cmd -L $lib }
}
foreach lib {secureip unisim unisims_ver unimacro unimacro_ver xpm xilinx_vip} {
    lappend cmd -L $lib
}
lappend cmd --snapshot rxfftr_snap work.rx_fft_frontend_rand_tb
set rc [catch {exec {*}$cmd 2>@1} out]
set fh [open $elog w]; puts $fh $out; close $fh
if {$rc != 0 || ![string match "*Built simulation snapshot*" $out]} {
    cd $root; gate_out "BLOCKED_COMPILE_ERROR (xelab)" $gate
    puts [string range $out end-2000 end]; exit 1
}

# ---- 6. Simulate ------------------------------------------------------
catch {file delete [file join $build golden]}
catch {file link -symbolic [file join $build golden] [file join $root golden]}
set ::env(XSIM_INI) [file join $build xsim.ini]
cd $build
set cmd [list xsim --nolog rxfftr_snap --runall --onerror quit -testplusarg N_VEC=$n_vec]
set rc [catch {exec {*}$cmd 2>@1} simout]
cd $root
set fh [open $slog w]; puts $fh $simout; close $fh

set fb_line ""
if {$part_fallback_note ne ""} { set fb_line "\n$part_fallback_note" }
if {[string match "*RESULT: PASS*" $simout]} {
    gate_out "RXFFT_RAND_GATE: PASS (part=$part, N_VEC=$n_vec)$fb_line" $gate
    puts $simout
    exit 0
} elseif {[string match "*RESULT: FAIL*" $simout]} {
    gate_out "RXFFT_RAND_GATE: FAIL (see $slog)$fb_line" $gate
    puts $simout
    exit 1
} elseif {$rc != 0} {
    gate_out "RXFFT_RAND_GATE: BLOCKED (xsim exit $rc)$fb_line" $gate
    puts [string range $simout end-2000 end]
    exit 1
} else {
    gate_out "RXFFT_RAND_GATE: FAIL (no gate line emitted)$fb_line" $gate
    exit 1
}
