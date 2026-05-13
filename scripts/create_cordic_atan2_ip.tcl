# create_cordic_atan2_ip.tcl — Preliminary TCL helper to generate the Xilinx CORDIC atan2 IP.
#
# STATUS: PRELIMINARY / NOT VERIFIED
# This script is a skeleton for future use in Vivado.
# Property names and values are based on Xilinx CORDIC v6.0 documentation and
# need to be verified against the actual IP Catalog in the target Vivado version.
# Do NOT run this script in production without reviewing all TODO items.
#
# Purpose:
#   Create a Xilinx CORDIC IP (cordic_v6_0) configured for atan2 (vectoring/translate)
#   with the interface matching cordic_atan2_xilinx_wrapper.v parameters.
#
# Intended use:
#   1. Open a Vivado project containing the RTL_SYNC design.
#   2. Run: source scripts/create_cordic_atan2_ip.tcl
#   3. Review the generated XCI, verify phase scaling and latency.
#   4. Replace the gen_ip_placeholder always block in cordic_atan2_xilinx_wrapper.v
#      with the actual cordic_v6_0 instantiation.
#
# Phase convention target (must match cordic_atan2.v):
#   atan2(Q, I) / pi * 32767, signed 16-bit, range [-32767, +32767]
#   pi -> +32767 (0x7FFF)

# ---------------------------------------------------------------------------
# Parameters — match cordic_atan2_xilinx_wrapper.v defaults
# ---------------------------------------------------------------------------
set ip_name       "cordic_atan2_inst"
set input_width   32
set phase_width   16
set latency       15
set output_dir    "./ip_cores"

# ---------------------------------------------------------------------------
# Create output directory
# ---------------------------------------------------------------------------
file mkdir $output_dir

# ---------------------------------------------------------------------------
# Create CORDIC IP
# TODO: Verify exact property names against Vivado IP Catalog for your version.
#       Open IP Catalog > CORDIC > customize > check exact CONFIG.* keys.
# ---------------------------------------------------------------------------
create_ip \
    -name cordic \
    -vendor xilinx.com \
    -library ip \
    -version 6.0 \
    -module_name $ip_name \
    -dir $output_dir

# Configure the IP
# TODO: Verify each CONFIG property name and value in your Vivado version.
set_property -dict [list \
    CONFIG.Functional_Selection     {Translate}        \
    CONFIG.Architectural_Configuration {Fully_Pipelined} \
    CONFIG.Pipelining_Mode          {Maximum}          \
    CONFIG.Input_Width              $input_width       \
    CONFIG.Output_Width             $phase_width       \
    CONFIG.Round_Mode               {Truncate}         \
    CONFIG.ARESETN                  {true}             \
    CONFIG.Flow_Control             {Blocking}         \
    CONFIG.Phase_Format             {Radians}          \
] [get_ips $ip_name]

# TODO: The OUTPUT phase scaling of the Xilinx CORDIC in Translate/Radians mode
#       must be verified to match: pi -> +32767 (Q15 format, PHASE_WIDTH=16).
#       Vivado CORDIC may scale differently depending on Round_Mode and Phase_Format.
#       Test vectors from cordic_atan2_xilinx_wrapper_tb.sv should be used to verify.

# Generate output products
generate_target all [get_ips $ip_name]

puts "CORDIC IP skeleton created: $output_dir/$ip_name"
puts "NEXT STEPS:"
puts "  1. Review the generated XCI in $output_dir/$ip_name"
puts "  2. Check pipeline latency matches LATENCY=$latency"
puts "  3. Check phase output scaling: pi -> +32767 for PHASE_WIDTH=$phase_width"
puts "  4. Check tdata packing: s_axis_cartesian_tdata = {Q[$input_width-1:0], I[$input_width-1:0]}"
puts "  5. Replace gen_ip_placeholder in rtl/cordic_atan2_xilinx_wrapper.v"
puts "     with actual $ip_name instantiation"
puts "  6. Run cordic_atan2_xilinx_wrapper_tb.sv with USE_BEHAVIORAL_MODEL=0"
puts "     (requires updating tb to instantiate wrapper without behavioral guard)"
