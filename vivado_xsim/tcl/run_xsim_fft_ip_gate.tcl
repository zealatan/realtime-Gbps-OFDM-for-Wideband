# run_xsim_fft_ip_gate.tcl
# Vivado batch-mode TCL script: compile + sim xsim_fft_ip_value_protocol_tb
# against the real Xilinx xfft 9.1 IP.
#
# Usage (from project root, after sourcing settings64.sh):
#   vivado -mode batch -source vivado_xsim/tcl/run_xsim_fft_ip_gate.tcl \
#          -tclargs [--root <path>] [--log-dir <path>]
#
# Gate output: vivado_xsim/reports/xsim_fft_ip_gate.txt

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
set root     [pwd]
set log_dir  [file join $root vivado_xsim logs]
set rpt_dir  [file join $root vivado_xsim reports]

set args $argv
while {[llength $args] > 0} {
    set opt [lindex $args 0]
    set args [lrange $args 1 end]
    switch -- $opt {
        --root    { set root     [lindex $args 0]; set args [lrange $args 1 end] }
        --log-dir { set log_dir  [lindex $args 0]; set args [lrange $args 1 end] }
    }
}

file mkdir $log_dir
file mkdir $rpt_dir

set gate_file [file join $rpt_dir xsim_fft_ip_gate.txt]
set clog      [file join $log_dir xsim_fft_ip_compile.log]
set slog      [file join $log_dir xsim_fft_ip_sim.log]
set elog      [file join $log_dir xsim_fft_ip_elab.log]
set build_dir [file join $log_dir xsim_fft_ip_build]

proc gate_out {msg gate_file} {
    set border [string repeat = 72]
    puts ""; puts $border; puts $msg; puts $border
    set fh [open $gate_file w]; puts $fh $msg; close $fh
}

proc append_log {logfile text} {
    set fh [open $logfile a]; puts $fh $text; close $fh
}

proc write_log {logfile text} {
    set fh [open $logfile w]; puts $fh $text; close $fh
}

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------
puts "=== FFT IP Value+Protocol Gate — [clock format [clock seconds]] ==="

set vhd_r8  [file join $root ip fft256_xilinx sim fft256_xilinx_r8.vhd]
set vhd_top [file join $root ip fft256_xilinx sim fft256_xilinx.vhd]
set wrap_v  [file join $root rtl DUT fft256_xilinx_wrapper.v]
set tb_sv   [file join $root vivado_xsim tb xsim_fft_ip_value_protocol_tb.sv]

foreach f [list $vhd_r8 $wrap_v $tb_sv] {
    if {![file exists $f]} {
        gate_out "BLOCKED_XCI_NOT_FOUND: missing [file tail $f]" $gate_file
        exit 1
    }
}

set vhd_files [list $vhd_r8]
# fft256_xilinx.vhd references xfft_v9_1_9 pre-compiled library — DO NOT include.
# fft256_xilinx_r8.vhd provides the entity directly as a behavioral model.

# Vivado data dir for xsim.ini
set vivado_data ""
if {[info exists env(XILINX_VIVADO)]} {
    set vivado_data [file join $env(XILINX_VIVADO) data]
} else {
    # Fallback: derive from executable path
    set exe [info nameofexecutable]
    set vivado_data [file join [file dirname [file dirname $exe]] data]
}

# ---------------------------------------------------------------------------
# Build area
# ---------------------------------------------------------------------------
file delete -force $build_dir
file mkdir $build_dir

# xsim.ini with substituted paths
set ini_flags [list]
set ini_src [file join $vivado_data xsim xsim.ini]
if {[file exists $ini_src]} {
    set fh [open $ini_src r]
    set ini_content [read $fh]
    close $fh
    regsub -all {\$RDI_DATADIR} $ini_content $vivado_data ini_content
    set ini_dst [file join $build_dir xsim.ini]
    set fh [open $ini_dst w]; puts $fh $ini_content; close $fh
    set ini_flags [list --initfile $ini_dst]
    puts "  xsim.ini: $ini_dst"
} else {
    puts "  xsim.ini: not found (using defaults)"
}

# Symlinks so relative paths in the TB resolve from the build dir
foreach d {vectors golden vivado_xsim} {
    set tgt [file join $root $d]
    if {[file exists $tgt]} {
        catch {file link -symbolic [file join $build_dir $d] $tgt}
    }
}

# ---------------------------------------------------------------------------
# Step 1 — Compile VHDL
# ---------------------------------------------------------------------------
puts "\n=== \[1\] Compile VHDL ==="
set cmd [list xvhdl --nolog]
foreach f $ini_flags { lappend cmd $f }
lappend cmd -work xil_defaultlib
foreach f $vhd_files { lappend cmd $f }
set rc [catch {cd $build_dir; exec {*}$cmd 2>@1} out]
cd $root
write_log $clog $out
if {$rc != 0} {
    gate_out "BLOCKED_COMPILE_ERROR (xvhdl)" $gate_file
    puts "  See $clog"; puts "  Output: $out"
    exit 1
}
puts "  VHDL compile: OK"

# ---------------------------------------------------------------------------
# Step 2 — Compile Verilog DUT + TB
# ---------------------------------------------------------------------------
puts "\n=== \[2\] Compile Verilog ==="
set cmd [list xvlog --nolog --sv $wrap_v $tb_sv]
set rc [catch {cd $build_dir; exec {*}$cmd 2>@1} out]
cd $root
append_log $clog $out
if {$rc != 0} {
    gate_out "BLOCKED_COMPILE_ERROR (xvlog)" $gate_file
    puts "  See $clog"; puts "  Output: $out"
    exit 1
}
puts "  Verilog compile: OK"

# ---------------------------------------------------------------------------
# Step 3 — Elaborate
# ---------------------------------------------------------------------------
puts "\n=== \[3\] Elaborate ==="
set cmd [list xelab --nolog]
foreach f $ini_flags { lappend cmd $f }
lappend cmd -L work -L xil_defaultlib -L xfft_v9_1_8
lappend cmd --snapshot fft_ip_gate_snap
lappend cmd work.xsim_fft_ip_value_protocol_tb
set rc [catch {cd $build_dir; exec {*}$cmd 2>@1} out]
cd $root
write_log $elog $out
if {$rc != 0} {
    gate_out "BLOCKED_COMPILE_ERROR (xelab rc=$rc)" $gate_file
    puts "  See $elog"; puts "  Output: [string range $out end-500 end]"
    exit 1
}
if {![string match "*Built simulation snapshot*" $out]} {
    gate_out "BLOCKED_COMPILE_ERROR (no snapshot line)" $gate_file
    puts "  See $elog"
    exit 1
}
puts "  Elaborate: OK"

# ---------------------------------------------------------------------------
# Step 4 — Simulate
# ---------------------------------------------------------------------------
puts "\n=== \[4\] Simulate ==="
set cmd [list xsim --nolog fft_ip_gate_snap --runall --onerror quit]
set rc [catch {cd $build_dir; exec {*}$cmd 2>@1} sim_out]
cd $root
write_log $slog $sim_out

# ---------------------------------------------------------------------------
# Parse gate result
# ---------------------------------------------------------------------------
if {[string match "*GATE: PASS_VIVADO_XSIM_REAL_IP*" $sim_out]} {
    set result "PASS_VIVADO_XSIM_REAL_IP ([clock format [clock seconds] -format %Y-%m-%d])"
} elseif {[string match "*GATE: FAIL_VALUE_MISMATCH*" $sim_out]} {
    set result "FAIL_VALUE_MISMATCH"
} elseif {[string match "*GATE: FAIL_PROTOCOL*" $sim_out]} {
    set result "FAIL_PROTOCOL"
} elseif {$rc != 0} {
    set result "BLOCKED_COMPILE_ERROR (xsim exit $rc)"
} else {
    set result "FAIL (no gate line found in sim output)"
}

gate_out "FFT_IP_VALUE_PROTOCOL_GATE: $result" $gate_file
puts "  Gate: $gate_file"
puts "  Sim:  $slog"

if {[string match "PASS*" $result]} { exit 0 } else { exit 1 }
