# build_xsim_simlib.tcl
#
# One-time precompile of the Xilinx simulation libraries for xsim.
# Once built (~5-10 minutes), all downstream xelab invocations
# reference these precompiled libraries instead of re-elaborating
# the xfft_v9_1 / cmpy / xbip_* sources from scratch on every gate.
#
# Output: $XILINX_SIMLIB (or $repo/sim_out/xsim_simlib by default)
#
# Invocation:
#   vivado -mode batch -source scripts/build_xsim_simlib.tcl

set repo_root [pwd]
set simlib_dir [file join $repo_root sim_out xsim_simlib]
if {[info exists ::env(XILINX_SIMLIB)]} { set simlib_dir $::env(XILINX_SIMLIB) }

if {![file exists $simlib_dir]} {
    file mkdir $simlib_dir
}

puts ""
puts "================================================================"
puts " compile_simlib (xsim, family=zynquplus)"
puts "   target dir : $simlib_dir"
puts "================================================================"
puts ""

compile_simlib -simulator xsim \
               -family zynquplus \
               -language all \
               -library all \
               -directory $simlib_dir \
               -force \
               -no_ip_compile

puts "PHASE5_XSIM_SIMLIB: OK ($simlib_dir)"
