# create_fft256_xilinx_ip.tcl — P3-13C Vivado FFT IP generation
#
# Generates a parameterized Xilinx xfft_v9_1 simulation model for use with
# fft256_xilinx_wrapper.v (USE_BEHAVIORAL_STUB=0).
#
# Configuration:
#   256-point FFT
#   Pipelined streaming I/O
#   Natural-order output
#   Run-time configurable scale schedule (SCALE_SCH from AXI config channel)
#   FWD_INV from AXI config channel
#   No aresetn (C_HAS_ARESETN=0)
#   Realtime throttle (C_THROTTLE_SCHEME=0 — no m_axis_data_tready on output)
#   xk_index on m_axis_data_tuser
#   16-bit input/output
#
# Usage (from Windows or WSL via cmd.exe):
#   vivado.bat -mode batch -source create_fft256_xilinx_ip.tcl [-nolog -nojournal]
#   or with custom output dir:
#   vivado.bat -mode batch -source create_fft256_xilinx_ip.tcl -tclargs <out_dir>
#
# Default output: ip/fft256_xilinx/  (relative to Vivado cwd)
# After generation, the simulation wrapper is at:
#   ip/fft256_xilinx/sim/fft256_xilinx.v
#
# Verified: Vivado 2023.1

set script_dir [file dirname [info script]]

# Parse optional output dir argument
if {[llength $argv] > 0} {
    set ip_root [lindex $argv 0]
} else {
    # Default: ip/ relative to this script's directory
    set ip_root [file normalize "${script_dir}/../ip"]
}
file mkdir $ip_root
puts "INFO: IP output root: $ip_root"

# Create a minimal in-memory project (no project file written)
create_project -in_memory -part xc7z020clg400-1
set_property target_simulator XSim [current_project]
set_property default_lib xil_defaultlib [current_project]

# Create xfft IP instance
create_ip \
    -name xfft \
    -vendor xilinx.com \
    -library ip \
    -version 9.1 \
    -module_name fft256_xilinx \
    -dir $ip_root

# Configure IP parameters
# Key parameter notes:
#   transform_length          256 — fixed, not run-time configurable
#   input_width               16 — Q1.15 IQ samples
#   output_width              implicit from scaling (equals input_width for scaled)
#   phase_factor_width        16 — twiddle factor precision
#   scaling_options           scaled — SCALE_SCH provided on s_axis_config
#   output_ordering           natural_order — matches wrapper convention
#   throttle_scheme           realtime — C_THROTTLE_SCHEME=0, no tready on output
#   aresetn                   false — C_HAS_ARESETN=0 (wrapper gates via state machine)
#   aclken                    false — no clock enable port
#   xk_index                  true — bin index on m_axis_data_tuser
#   ovflo                     false — no overflow flag port
#   cyclic_prefix_insertion   false — not needed for this application
#   channels                  1 — single-channel
#   implementation_options    pipelined_streaming_io — lowest latency architecture
#   complex_mult_type         use_mults_resources — DSP block multipliers
#   rounding_modes            truncation — matches bypass path convention
set_property -dict {
    CONFIG.transform_length              {256}
    CONFIG.implementation_options        {pipelined_streaming_io}
    CONFIG.run_time_configurable_transform_length {false}
    CONFIG.channels                      {1}
    CONFIG.input_width                   {16}
    CONFIG.phase_factor_width            {16}
    CONFIG.scaling_options               {scaled}
    CONFIG.rounding_modes                {truncation}
    CONFIG.complex_mult_type             {use_mults_resources}
    CONFIG.xk_index                      {true}
    CONFIG.throttle_scheme               {realtime}
    CONFIG.output_ordering               {natural_order}
    CONFIG.aresetn                       {false}
    CONFIG.aclken                        {false}
    CONFIG.ovflo                         {false}
    CONFIG.cyclic_prefix_insertion       {false}
} [get_ips fft256_xilinx]

# Verify key configuration (use get_property on safe per-parameter queries)
set ip [get_ips fft256_xilinx]
puts "INFO: transform_length: [get_property CONFIG.transform_length $ip]"
puts "INFO: input_width:       [get_property CONFIG.input_width $ip]"
puts "INFO: scaling_options:   [get_property CONFIG.scaling_options $ip]"
puts "INFO: output_ordering:   [get_property CONFIG.output_ordering $ip]"
puts "INFO: throttle_scheme:   [get_property CONFIG.throttle_scheme $ip]"

# Generate simulation target files
puts "INFO: Generating simulation target..."
generate_target simulation [get_ips fft256_xilinx]

# List generated simulation files (glob, no Vivado file APIs needed)
set sim_dir "${ip_root}/fft256_xilinx/sim"
puts ""
puts "INFO: Generated simulation files in ${sim_dir}:"
if {[file exists $sim_dir]} {
    foreach f [glob -nocomplain ${sim_dir}/*] {
        puts "  [file tail $f]"
    }
} else {
    puts "  (sim directory not found — generate_target may have failed)"
}

puts ""
puts "INFO: IP generation complete."
puts "INFO: Simulation files in: ${ip_root}/fft256_xilinx/"
puts ""
puts "INFO: Next steps for xsim:"
puts "  1. xvhdl -work xfft_v9_1_9  <Vivado>/data/ip/xilinx/xfft_v9_1/hdl/xfft_v9_1_vh_rfs.vhd"
puts "  2. xvhdl -work xil_defaultlib  ip/fft256_xilinx/sim/fft256_xilinx.vhd"
puts "  3. xvlog -sv -work xil_defaultlib  <RTL files> <TB files>"
puts "  4. xelab -snapshot p3_13c_snap xil_defaultlib.p3_13c_real_fft_top"
puts "  5. xsim p3_13c_snap --runall"
