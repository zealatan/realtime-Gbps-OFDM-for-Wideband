# run_p5_d_meyr_cfo_top_unit.tcl
#
# P5-01A Step D Level-1 unit sim.
#   - Registers the three xfft 9.1 IPs (xfft_N, xfft_2N, xfft_IFFT) into an
#     in-memory Vivado project, generates simulation sources.
#   - Compiles the meyr_cfo_top hierarchy + p5_d unit TB.
#   - Elaborates + simulates with the BFP behavioral IP model.
#   - Reports PASS / FAIL based on the gate line emitted by the TB.

set root [pwd]
# PHASE5 target part of record: ZCU102 / xczu9eg. Env override is honored
# for CI installs that lack ZU9 part files; the fallback is recorded in
# the gate output so a green xsim is never mistaken for a part-correct build.
set part_locked "xczu9eg-ffvb1156-2-e"
set part        $part_locked
if {[info exists ::env(XFFT_TARGET_PART)]} { set part $::env(XFFT_TARGET_PART) }
set part_fallback_note ""

set log_dir [file join $root vivado_xsim logs]
set rpt_dir [file join $root vivado_xsim reports]
set build   [file join $log_dir p5_d_build]
file mkdir $log_dir
file mkdir $rpt_dir
file delete -force $build
file mkdir $build

set clog [file join $log_dir p5_d_compile.log]
set elog [file join $log_dir p5_d_elab.log]
set slog [file join $log_dir p5_d_sim.log]
set gate [file join $rpt_dir p5_d_gate.txt]

proc gate_out {msg path} {
    puts ""
    puts [string repeat = 72]
    puts $msg
    puts [string repeat = 72]
    set fh [open $path w]; puts $fh $msg; close $fh
}

# Probe whether the requested part exists in this Vivado install. If not,
# fall back loudly to the closest installed zynquplus part for the sim only
# - the gate output records the substitution so it cannot be mistaken for a
# part-correct build.
if {[catch {create_project -in_memory -part $part p5_d_inmem} cp_err]} {
    puts "*** WARNING: requested part '$part' not installed: $cp_err"
    # Closest available zynquplus part for the BFP sim model.
    set fb_candidates {xczu7eg-ffvc1156-2-i xczu7ev-ffvc1156-2-e \
                       xczu5ev-sfvc784-2-i xczu3eg-sbva484-1-i}
    set chose ""
    foreach fb $fb_candidates {
        if {![catch {create_project -in_memory -part $fb p5_d_inmem} _]} {
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
puts "P5-D: target part = $part  (locked = $part_locked)"

# ---- 1. Register IPs + generate simulation sources -------------------
# Stage copies of the XCIs under a writable IP dir; retarget to the
# current project part; reset+regenerate so the IP outputs match the
# project's part and aren't reused from a prior wrong-part run.
set ip_stage [file join $build ip_stage]
file mkdir $ip_stage
foreach n {xfft_N xfft_2N xfft_IFFT} {
    set src [file join $root rtl $n ${n}.xci]
    if {![file exists $src]} {
        gate_out "BLOCKED_XCI_NOT_FOUND: $src" $gate
        exit 1
    }
    set dst_dir [file join $ip_stage $n]
    file mkdir $dst_dir
    set dst [file join $dst_dir ${n}.xci]
    file copy -force $src $dst
    read_ip $dst
}
# Unlock, reset prior outputs, then regenerate both synthesis and simulation
# targets for the NEW project part. reset_target before generate_target
# ensures we never reuse stale outputs from a wrong-part attempt.
foreach ip [get_ips xfft_N xfft_2N xfft_IFFT] {
    catch {set_property IS_LOCKED false $ip}
}
upgrade_ip [get_ips xfft_N xfft_2N xfft_IFFT]
reset_target all [get_ips xfft_N xfft_2N xfft_IFFT]
generate_target {synthesis simulation} [get_ips xfft_N xfft_2N xfft_IFFT]

# Collect every simulation HDL file the three IPs need, IN COMPILE ORDER and
# WITH THE LIBRARY each file belongs to.
#
# ---------------------------------------------------------------------------
# WHY THE PREVIOUS APPROACHES FAILED ("Module <xfft_N> not found" at elab)
# ---------------------------------------------------------------------------
#   v1 globbed a hard-coded `vivado_xsim/DSP_Rx.gen/sources_1/ip` that does NOT
#   exist for this in-memory project -> ZERO files -> xfft behavioral model
#   never compiled.
#   v2 used `get_files -compile_order sources -used_in simulation -of_objects
#   [get_ips ...]`. In a `create_project -in_memory` flow with `read_ip` of a
#   *bare staged .xci*, Vivado does not always register the per-file simulation
#   fileset objects in the in-memory fileset graph, so this returned nothing
#   usable either -> the support libs (sim/<ip>.vhd + the encrypted
#   hdl/*_vh_rfs.vhd) were again never xvhdl'd into the work libraries and
#   xelab could not resolve xfft_N / xfft_2N / xfft_IFFT.
#
# ---------------------------------------------------------------------------
# ROBUST FIX (strategy (b) primary, strategy (a) fallback)
# ---------------------------------------------------------------------------
# We do NOT rely on get_files returning anything. Instead we drive the compile
# DETERMINISTICALLY from the IP's own packaging metadata + on-disk sources:
#
#   * Primary source dir: the standalone managed project that already generated
#     the three IPs with simulation targets for this same part/params:
#         build_zcu216_ip/xfft_ip.gen/sources_1/ip/<ip>/{hdl,sim}/
#   * Fallback source dir: wherever the in-memory generate_target above wrote
#     the sim outputs for the staged .xci (derived at runtime via [get_property
#     IP_DIR ...] / glob -- NEVER a hard-coded DSP_Rx.gen).
#
# The (library,file) compile order below is the AUTHORITATIVE order taken from
# each IP's <ip>.xml <spirit:view name="xilinx_vhdlbehavioralsimulation"> file-
# set sequence and each file's <spirit:logicalName> (the VHDL library it must
# compile into). xfft v9.1 in 2021.1 -> xfft_v9_1_6, and the support libs use
# their versioned names. The sim wrapper does `LIBRARY xfft_v9_1_6; USE
# xfft_v9_1_6.xfft_v9_1_6;`, so a flat xil_defaultlib mapping would never
# resolve -- each support file MUST land in its own versioned library.
#
# The 14 hdl/*_vh_rfs.vhd support files + the xfft model are byte-identical
# across all three IPs, so they are compiled ONCE (deduped by (lib,basename)).
# Only the three sim/<ip>.vhd wrappers differ (entity names xfft_N/2N/IFFT) and
# each compiles into xil_defaultlib.

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

# Locate the per-IP generated-source directory. Try, in order:
#   1) the standalone managed-project gen dir (primary, strategy (b)),
#   2) the in-memory project's actual gen dir derived from the IP object
#      (strategy (a) -- IP_DIR / IP_OUTPUT_DIR, NOT hard-coded),
#   3) a recursive glob next to the staged .xci.
# Returns "" if no dir with both hdl/ and sim/ for $n is found.
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
    # Anything generate_target may have written under the staged IP dir.
    foreach g [glob -nocomplain -directory [file join $build ip_stage $n] -type d *] {
        lappend cands $g
    }
    foreach c $cands {
        if {$c eq ""} { continue }
        if {[file isdirectory [file join $c hdl]] \
            && [file isdirectory [file join $c sim]]} {
            return $c
        }
        # The IP_DIR may itself be the parent; probe one level down.
        foreach sub [glob -nocomplain -directory $c -type d *] {
            if {[file isdirectory [file join $sub hdl]] \
                && [file isdirectory [file join $sub sim]]} {
                return $sub
            }
        }
    }
    return ""
}

# Build the ordered (library . absolute-file) list:
#   (a) the 15 shared support files once (from the FIRST IP whose gen dir we
#       can locate -- they are identical across IPs), then
#   (b) each IP's sim/<ip>.vhd wrapper -> xil_defaultlib, last.
set ip_sim_pairs [list]
set ip_gen_dirs  [list]
foreach n {xfft_N xfft_2N xfft_IFFT} {
    set d [find_ip_gen_dir $root $build $n]
    if {$d eq ""} {
        puts "*** WARNING: no generated sim dir found for $n"
        continue
    }
    lappend ip_gen_dirs [list $n $d]
}
if {[llength $ip_gen_dirs] == 0} {
    gate_out "BLOCKED_NO_IP_SIM_SOURCES: no <ip>/{hdl,sim} dir located\
              (looked under build_zcu216_ip + in-memory IP_DIR + staged ip dir)" $gate
    exit 1
}

# (a) shared support libs -- compile once, from the first located gen dir.
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
# (b) per-IP sim wrappers -> xil_defaultlib (entity xfft_N / xfft_2N / xfft_IFFT).
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

puts "P5-D: IP sim file count = [llength $ip_sim_pairs]\
      (support libs deduped from [file tail $shared_dir]/hdl,\
       [llength $ip_gen_dirs] sim wrappers)"
if {[llength $ip_sim_pairs] == 0} {
    gate_out "BLOCKED_NO_IP_SIM_SOURCES: derived compile list is empty" $gate
    exit 1
}

# ---- 2. Compile RTL + TB ---------------------------------------------
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

# Point xsim at the PRE-COMPILED Xilinx simulation library (secureip / unisim /
# xpm / xilinx_vip ...). The xfft 9.1 behavioral model and its *_vh_rfs.vhd
# support libs reference those primitives, so xvhdl/xelab must see this xsim.ini
# or they cannot find e.g. secureip / unisim. We seed a local xsim.ini in the
# build dir that includes the simlib mappings, and export XSIM_INI so every
# xvhdl/xvlog/xelab/xsim invocation below picks it up. (sim_out/xsim_simlib was
# built with compile_simlib for this same 2021.1 install.)
set simlib_ini [file join $root sim_out xsim_simlib xsim.ini]
cd $build
if {[file exists $simlib_ini]} {
    set local_ini [file join $build xsim.ini]
    # Dedicated local directory for the IP support libraries we compile here, so
    # `xvhdl --work <lib>` writes into OUR build tree and never clobbers the
    # pre-compiled simlib (two of the libs -- axi_utils_v2_0_6,
    # xbip_utils_v3_0_10 -- are also present in the simlib; our explicit mapping
    # below takes precedence and keeps everything self-consistent with the
    # build_zcu216_ip 2021.1 sources we are compiling).
    set ip_lib_dir [file join $build ip_libs]
    file mkdir $ip_lib_dir
    set ih [open $local_ini w]
    puts $ih "-- Auto-generated by run_p5_d_meyr_cfo_top_unit.tcl"
    puts $ih "include \$XILINX_VIVADO/data/xsim/ip/xsim_ip.ini"
    # Explicit local mappings FIRST: every IP support library (versioned) +
    # xil_defaultlib + work, each in our own writable dir. Listed before the
    # simlib include so they win for any duplicate library name.
    foreach pair $ip_hdl_order {
        set _lib [lindex $pair 0]
        puts $ih "$_lib=[file join $ip_lib_dir $_lib]"
    }
    puts $ih "xil_defaultlib=[file join $ip_lib_dir xil_defaultlib]"
    # Pull in the pre-compiled Xilinx primitive simlib mappings (secureip /
    # unisim / unisims_ver / unimacro / xpm / xilinx_vip; absolute paths inside).
    set sh [open $simlib_ini r]
    puts $ih [read $sh]
    close $sh
    close $ih
    set ::env(XSIM_INI) $local_ini
    puts "P5-D: using xsim.ini = $local_ini (IP libs -> $ip_lib_dir)"
} else {
    puts "*** WARNING: simlib xsim.ini not found at $simlib_ini -- elaboration\
          may fail to resolve secureip/unisim primitives."
}

# Compile each IP simulation file into the LIBRARY the IP packaging assigned to
# it (xil_defaultlib for the three sim wrappers, versioned libs such as
# xfft_v9_1_6 / xbip_utils_v3_0_10 / mult_gen_v12_0_17 for the encrypted support
# sources), in the deterministic compile order derived from <ip>.xml above. The
# set of distinct libraries we create here is fed to xelab as -L flags below.
set ip_libs [list]
set first_clog 1
foreach pair $ip_sim_pairs {
    set lib  [lindex $pair 0]
    set f    [lindex $pair 1]
    if {[lsearch -exact $ip_libs $lib] < 0} { lappend ip_libs $lib }
    set ext [string tolower [file extension $f]]
    if {$ext eq ".vhd" || $ext eq ".vhdl"} {
        set cmd [list xvhdl --nolog -work $lib $f]
        set tag "xvhdl IP ($lib)"
    } elseif {$ext eq ".sv"} {
        set cmd [list xvlog --nolog -sv -work $lib $f]
        set tag "xvlog IP sv ($lib)"
    } else {
        set cmd [list xvlog --nolog -work $lib $f]
        set tag "xvlog IP ($lib)"
    }
    set rc [catch {exec {*}$cmd 2>@1} out]
    if {$first_clog} { set fh [open $clog w]; set first_clog 0 } else { set fh [open $clog a] }
    puts $fh "\n=== $tag : [file tail $f] ===\n$out"; close $fh
    if {$rc != 0} { cd $root; gate_out "BLOCKED_COMPILE_ERROR ($tag)" $gate; puts $out; exit 1 }
}

set cmd [list xvlog --nolog]
foreach f $rtl_files { lappend cmd $f }
set rc [catch {exec {*}$cmd 2>@1} out]
# Append (the IP compile block above already created/owns $clog).
set fh [open $clog a]; puts $fh "\n=== xvlog RTL ===\n$out"; close $fh
if {$rc != 0} { cd $root; gate_out "BLOCKED_COMPILE_ERROR (xvlog rtl)" $gate; puts $out; exit 1 }

set inv_file [file join $root tb p5_invariants.sv]
set cov_file [file join $root tb p5_functional_cov.sv]
set cmd [list xvlog --nolog -sv $inv_file $cov_file $tb_file]
set rc [catch {exec {*}$cmd 2>@1} out]
set fh [open $clog a]; puts $fh "\n=== xvlog TB + invariants + cov ===\n$out"; close $fh
if {$rc != 0} { cd $root; gate_out "BLOCKED_COMPILE_ERROR (xvlog tb)" $gate; puts $out; exit 1 }

# ---- 3. Elaborate ----------------------------------------------------
# -L flags must cover: (a) work + xil_defaultlib (RTL/TB + IP top model),
# (b) every versioned IP support library we compiled above ($ip_libs, e.g.
# xfft_v9_1_6 / xbip_utils_v3_0 / mult_gen_v12_0 ...), and (c) the pre-compiled
# Xilinx primitive libs from the simlib (secureip / unisim / unisims_ver / xpm /
# xilinx_vip). The old hard-coded "-L xfft_v9_1_8" was BOTH the wrong version
# (this 2021.1 IP build links xfft_v9_1_6, taken from the sim model's
# `USE xfft_v9_1_6.xfft_v9_1_6;`) AND incomplete (no secureip/unisim), so the
# behavioral model could never elaborate.
set cmd [list xelab --nolog -L work -L xil_defaultlib]
foreach lib $ip_libs {
    if {$lib ne "work" && $lib ne "xil_defaultlib"} { lappend cmd -L $lib }
}
foreach lib {secureip unisim unisims_ver unimacro unimacro_ver xpm xilinx_vip} {
    lappend cmd -L $lib
}
lappend cmd --snapshot p5_d_snap work.p5_d_meyr_cfo_top_unit_tb
set rc [catch {exec {*}$cmd 2>@1} out]
set fh [open $elog w]; puts $fh $out; close $fh
if {$rc != 0 || ![string match "*Built simulation snapshot*" $out]} {
    cd $root; gate_out "BLOCKED_COMPILE_ERROR (xelab)" $gate
    puts [string range $out end-1500 end]; exit 1
}

# ---- 4. Simulate -----------------------------------------------------
set cmd [list xsim --nolog p5_d_snap --runall --onerror quit]
set rc [catch {exec {*}$cmd 2>@1} simout]
set fh [open $slog w]; puts $fh $simout; close $fh
cd $root

set fb_line ""
if {$part_fallback_note ne ""} {
    set fb_line "\n$part_fallback_note"
}
if {[string match "*GATE: PASS_P5_D_LEVEL1*" $simout]} {
    gate_out "P5_D_LEVEL1_GATE: PASS (part=$part)$fb_line" $gate
    exit 0
} elseif {[string match "*GATE: FAIL_P5_D_LEVEL1*" $simout]} {
    gate_out "P5_D_LEVEL1_GATE: FAIL (see $slog)$fb_line" $gate
    exit 1
} elseif {$rc != 0} {
    gate_out "P5_D_LEVEL1_GATE: BLOCKED (xsim exit $rc)$fb_line" $gate
    exit 1
} else {
    gate_out "P5_D_LEVEL1_GATE: FAIL (no gate line emitted)$fb_line" $gate
    exit 1
}
