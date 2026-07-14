# run_xsim_dual_symbol_fft_gate.tcl
# Gate TB for fft256_dual_symbol_frontend with real Xilinx FFT IP.

set root    [pwd]
set log_dir [file join $root vivado_xsim logs]
set rpt_dir [file join $root vivado_xsim reports]
file mkdir $log_dir; file mkdir $rpt_dir

set gate_file  [file join $rpt_dir xsim_dual_symbol_fft_gate.txt]
set clog       [file join $log_dir xsim_dual_fft_compile.log]
set slog       [file join $log_dir xsim_dual_fft_sim.log]
set elog       [file join $log_dir xsim_dual_fft_elab.log]
set build_dir  [file join $log_dir xsim_dual_fft_build]

proc gate_out {msg gate_file} {
    set border [string repeat = 72]
    puts ""; puts $border; puts $msg; puts $border
    set fh [open $gate_file w]; puts $fh $msg; close $fh
}

puts "\n=== Dual-Symbol FFT Real IP Gate — [clock format [clock seconds]] ==="

set rtl_files [list \
    [file join $root rtl DUT fft256_xilinx_wrapper.v] \
    [file join $root rtl DUT fft256_dual_symbol_frontend.v]]
set tb_sv     [file join $root vivado_xsim tb xsim_dual_symbol_fft_real_ip_tb.sv]
set vhd_r8    [file join $root ip fft256_xilinx sim fft256_xilinx_r8.vhd]

foreach f [concat $rtl_files [list $tb_sv $vhd_r8]] {
    if {![file exists $f]} {
        gate_out "BLOCKED_XCI_NOT_FOUND: missing [file tail $f]" $gate_file; exit 1
    }
}

set vivado_data ""
if {[info exists env(XILINX_VIVADO)]} {
    set vivado_data [file join $env(XILINX_VIVADO) data]
} else {
    set vivado_data [file join [file dirname [file dirname [info nameofexecutable]]] data]
}

file delete -force $build_dir; file mkdir $build_dir

set ini_flags [list]
set ini_src [file join $vivado_data xsim xsim.ini]
if {[file exists $ini_src]} {
    set fh [open $ini_src r]; set ini [read $fh]; close $fh
    regsub -all {\$RDI_DATADIR} $ini $vivado_data ini
    set ini_dst [file join $build_dir xsim.ini]
    set fh [open $ini_dst w]; puts $fh $ini; close $fh
    set ini_flags [list --initfile $ini_dst]
}

foreach d {vectors golden vivado_xsim} {
    set tgt [file join $root $d]
    if {[file exists $tgt]} { catch {file link -symbolic [file join $build_dir $d] $tgt} }
}

# VHDL: only fft256_xilinx_r8.vhd (NOT fft256_xilinx.vhd — that references pre-compiled xfft lib)
puts "\n=== \[1\] Compile VHDL ==="
set cmd [list xvhdl --nolog]; foreach f $ini_flags { lappend cmd $f }
lappend cmd -work xil_defaultlib $vhd_r8
set rc [catch {cd $build_dir; exec {*}$cmd 2>@1} out]; cd $root
set fh [open $clog w]; puts $fh $out; close $fh
if {$rc != 0} { gate_out "BLOCKED_COMPILE_ERROR (xvhdl)" $gate_file; puts $out; exit 1 }
puts "  VHDL: OK"

puts "\n=== \[2\] Compile Verilog ==="
set cmd [list xvlog --nolog --sv]
foreach f [concat $rtl_files [list $tb_sv]] { lappend cmd $f }
set rc [catch {cd $build_dir; exec {*}$cmd 2>@1} out]; cd $root
set fh [open $clog a]; puts $fh $out; close $fh
if {$rc != 0} { gate_out "BLOCKED_COMPILE_ERROR (xvlog)" $gate_file; puts $out; exit 1 }
puts "  Verilog: OK"

puts "\n=== \[3\] Elaborate ==="
set cmd [list xelab --nolog]; foreach f $ini_flags { lappend cmd $f }
lappend cmd -L work -L xil_defaultlib -L xfft_v9_1_8
lappend cmd --snapshot dual_fft_gate_snap work.xsim_dual_symbol_fft_real_ip_tb
set rc [catch {cd $build_dir; exec {*}$cmd 2>@1} out]; cd $root
set fh [open $elog w]; puts $fh $out; close $fh
if {$rc != 0 || ![string match "*Built simulation snapshot*" $out]} {
    gate_out "BLOCKED_COMPILE_ERROR (xelab)" $gate_file
    puts [string range $out end-500 end]; exit 1
}
puts "  Elaborate: OK"

puts "\n=== \[4\] Simulate ==="
set cmd [list xsim --nolog dual_fft_gate_snap --runall --onerror quit]
set rc [catch {cd $build_dir; exec {*}$cmd 2>@1} sim_out]; cd $root
set fh [open $slog w]; puts $fh $sim_out; close $fh

if {[string match "*GATE: PASS_VIVADO_XSIM_REAL_IP*" $sim_out]} {
    set res "PASS_VIVADO_XSIM_REAL_IP ([clock format [clock seconds] -format %Y-%m-%d])"
} elseif {[string match "*GATE: FAIL_VALUE_MISMATCH*" $sim_out]} {
    set res "FAIL_VALUE_MISMATCH"
} elseif {[string match "*GATE: FAIL_PROTOCOL*" $sim_out]} {
    set res "FAIL_PROTOCOL"
} elseif {$rc != 0} {
    set res "BLOCKED_COMPILE_ERROR (xsim exit $rc)"
} else {
    set res "FAIL (no gate line)"
}

gate_out "DUAL_SYMBOL_FFT_GATE: $res" $gate_file
puts "  Gate: $gate_file\n  Sim:  $slog"
if {[string match "PASS*" $res]} { exit 0 } else { exit 1 }
