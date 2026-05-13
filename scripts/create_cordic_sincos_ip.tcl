# create_cordic_sincos_ip.tcl — preliminary helper to create cordic_v6_0 IP
# for NCO sin/cos generation in rotate (translate) mode.
#
# STATUS: PRELIMINARY — not verified in Vivado.
#         Property names and values may differ between Vivado versions.
#         Do NOT make simulation depend on this script.
#         Run manually in Vivado Tcl console or as a Vivado batch script.
#
# Usage (Vivado Tcl console or vivado -mode batch -source create_cordic_sincos_ip.tcl):
#   cd <project_dir>
#   source scripts/create_cordic_sincos_ip.tcl
#
# This script is NOT required for Step 35B simulation.
# It is a placeholder for a future Step 35B-2 IP generation task.

# TODO: Set actual project path if running standalone
# set proj_dir [pwd]

# ---------------------------------------------------------------------------
# Configuration parameters (review before running)
# ---------------------------------------------------------------------------
set ip_name       "cordic_sincos"
set ip_vlnv       "xilinx.com:ip:cordic:6.0"
set output_dir    "./ip"

# CORDIC rotate mode configuration:
#   Functional Selection: Translate = rotate mode (computes cos/sin from phase)
#   Phase Format: Radians
#   Input width: 16-bit phase (signed, maps -pi..pi as Q1.15)
#   Output width: 16-bit (signed Q1.15)
#   Pipelining: Maximum for best throughput
#   Scale Compensation: enabled (removes CORDIC gain ~1.6468, outputs in ±1.0 range)
#   AXI4-Stream: enabled
#
# Phase input mapping (from nco_phase_gen_xilinx_wrapper.v):
#   cordic_phase_in = signed(phase_acc[31:16])
#   Range: -32768 .. +32767 maps to -pi .. +pi
#
# TODO: verify correct CONFIG property names against target Vivado version.
#       Common properties for cordic_v6_0 — check with:
#         create_ip -name cordic -vendor xilinx.com -library ip -version 6.0 -module_name check_cordic
#         report_property [get_ips check_cordic]

# ---------------------------------------------------------------------------
# IP creation
# ---------------------------------------------------------------------------
if {![file isdirectory $output_dir]} {
    file mkdir $output_dir
}

create_ip \
    -name cordic \
    -vendor xilinx.com \
    -library ip \
    -version 6.0 \
    -module_name $ip_name

# TODO: Verify these property names in your Vivado version before use.
set_property -dict [list \
    CONFIG.Functional_Selection    {Translate} \
    CONFIG.Phase_Format            {Radians} \
    CONFIG.Input_Width             {16} \
    CONFIG.Output_Width            {16} \
    CONFIG.Pipelining_Mode         {Maximum} \
    CONFIG.Scale_Compensation      {true} \
    CONFIG.Has_ACLKEN              {false} \
    CONFIG.Has_ARESETn             {true} \
    CONFIG.Flow_Control            {Blocking} \
] [get_ips $ip_name]

# Generate the IP files (creates XCI + synthesized stubs)
generate_target all [get_ips $ip_name]

puts "INFO: $ip_name IP created."
puts "INFO: Review latency: report_property \[get_ips $ip_name\] | grep -i latency"
puts "TODO: Update LATENCY parameter in nco_phase_gen_xilinx_wrapper.v to match."
puts "TODO: Add XCI path to xvlog compile list in run_nco_phase_gen_xilinx_wrapper_sim.sh."
puts "TODO: Set USE_BEHAVIORAL_MODEL=0 and instantiate real IP."
