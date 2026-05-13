# create_cordic_atan2_ip.tcl — Create Xilinx CORDIC IP for atan2/vectoring mode.
#
# STATUS: PRELIMINARY — property names require confirmation via
#         scripts/probe_cordic_ip_properties.tcl before treating as verified.
#         Run probe_cordic_ip_properties.tcl first, review the CONFIG.* report,
#         then update TODO items below before generating production XCI.
#
# PURPOSE:
#   Create a Xilinx CORDIC IP (cordic_v6_0) configured for atan2/vectoring (Translate)
#   mode, matching the interface expected by rtl/cordic_atan2_xilinx_wrapper.v.
#
# TARGET: Vivado 2022.2
#
# Usage (Vivado Tcl console with project open, or batch mode):
#   source scripts/create_cordic_atan2_ip.tcl
#
# IP output directory:
#   ip/cordic_atan2_xilinx/
#
# Reports written to:
#   reports/cordic_atan2_ip_generation.log
#   reports/cordic_atan2_ip_properties.txt
#
# ---------------------------------------------------------------------------
# Interface target (must match rtl/cordic_atan2_xilinx_wrapper.v)
# ---------------------------------------------------------------------------
#
#   aclk                             — clock
#   aresetn                          — active-low synchronous reset
#   s_axis_cartesian_tvalid          — input valid
#   s_axis_cartesian_tready          — output ready (always 1, fully pipelined)
#   s_axis_cartesian_tdata[63:0]     — {Q[31:0], I[31:0]} (upper=Y/Q, lower=X/I)
#   m_axis_dout_tvalid               — output valid (asserted LATENCY cycles after input)
#   m_axis_dout_tdata[15:0]          — signed 16-bit phase: pi->+32767, -pi->-32767
#
# Phase convention target (matches cordic_atan2.v and wrapper):
#   atan2(Q, I) / pi * 32767, signed 16-bit
#   pi  -> +32767 (0x7FFF)
#   0   -> 0      (0x0000)
#   -pi/2 -> -16383 approx
#   +pi/2 -> +16383 approx
#
#   Xilinx CORDIC in Scaled_Radians phase format maps [-pi, +pi) to
#   [-(2^(N-1)), +(2^(N-1))-1] where N = output width.
#   With N=16: pi -> +32767.  This matches the project convention.
#
# Latency target:
#   15 clock cycles (matches cordic_atan2.v LATENCY=15 and frac_cfo_estimator).
#   Vivado CORDIC latency is determined by pipeline configuration.
#   After generation, read CONFIG.Latency or run report_property to confirm.
#   If actual latency differs from 15, update LATENCY parameter in the wrapper.

# ---------------------------------------------------------------------------
# Parameters
# ---------------------------------------------------------------------------
set ip_name       "cordic_atan2_xilinx"
set ip_dir        "./ip/cordic_atan2_xilinx"
set report_dir    "./reports"
set input_width   32
set phase_width   16
set target_latency 15

# ---------------------------------------------------------------------------
# Directory setup
# ---------------------------------------------------------------------------
file mkdir $ip_dir
file mkdir $report_dir

set log_file "$report_dir/cordic_atan2_ip_generation.log"
set fh_log [open $log_file w]

proc log_msg {fh msg} {
    puts $msg
    puts $fh $msg
}

log_msg $fh_log "# CORDIC atan2 IP Generation Log"
log_msg $fh_log "# Script: scripts/create_cordic_atan2_ip.tcl"
log_msg $fh_log "# Timestamp: [clock format [clock seconds]]"
log_msg $fh_log "# Target: Vivado [version -short]"
log_msg $fh_log "# ip_name:      $ip_name"
log_msg $fh_log "# ip_dir:       $ip_dir"
log_msg $fh_log "# input_width:  $input_width (bits per Cartesian component)"
log_msg $fh_log "# phase_width:  $phase_width (bits, signed output)"
log_msg $fh_log "# target_latency: $target_latency cycles"
log_msg $fh_log ""

# ---------------------------------------------------------------------------
# Remove existing instance if present (allow re-run)
# ---------------------------------------------------------------------------
if {[llength [get_ips -quiet $ip_name]] > 0} {
    log_msg $fh_log "INFO: Removing existing IP instance: $ip_name"
    remove_ip [get_ips $ip_name]
}

# ---------------------------------------------------------------------------
# Create CORDIC IP instance
# ---------------------------------------------------------------------------
log_msg $fh_log "INFO: Creating CORDIC IP instance: $ip_name"

if {[catch {
    create_ip \
        -name cordic \
        -vendor xilinx.com \
        -library ip \
        -version 6.0 \
        -module_name $ip_name \
        -dir $ip_dir
} err]} {
    log_msg $fh_log "ERROR: create_ip failed: $err"
    log_msg $fh_log "ACTION: Run scripts/probe_cordic_ip_properties.tcl to discover available IP."
    close $fh_log
    error "create_ip failed — see $log_file"
}

log_msg $fh_log "INFO: IP instance created successfully."

# ---------------------------------------------------------------------------
# Configure the IP
# ---------------------------------------------------------------------------
# TODO items — review after running probe_cordic_ip_properties.tcl:
#
# [TODO-1] CONFIG.Functional_Selection
#   Expected value: "Translate"  (Xilinx GUI label for vectoring/atan2)
#   Confirmed by: VALUE_RANGE in cordic_atan2_property_probe.txt
#   Alternative names seen in older Vivado: "Arc_Tan" — check report.
#
# [TODO-2] CONFIG.Architectural_Configuration
#   Expected value: "Fully_Pipelined"
#   Alternative: "Word_Serial" (slower, smaller area)
#   Confirmed by: property report.
#
# [TODO-3] CONFIG.Pipelining_Mode
#   Expected: "Maximum" (most pipeline stages, lowest logic per stage)
#   Alternative: "Optimal" (Vivado selects best for timing)
#   Confirmed by: property report.
#
# [TODO-4] CONFIG.Input_Width
#   Set to $input_width = 32 (bits per Cartesian component X or Y).
#   Maximum supported: typically 48 for cordic_v6.0; minimum 8.
#   Confirmed by: property report VALUE_RANGE.
#
# [TODO-5] CONFIG.Output_Width
#   Set to $phase_width = 16 (phase output bits).
#   Must be <= Input_Width.  Confirmed by property report.
#
# [TODO-6] CONFIG.Phase_Format
#   Expected value: "Scaled_Radians"
#   Effect: maps [-pi, +pi) to [-(2^(N-1)), +(2^(N-1))-1]
#   This gives pi -> +32767 for N=16.  Matches project convention.
#   Alternative: "Radians" — check if this differs.
#   Confirmed by: property report.
#
# [TODO-7] CONFIG.Round_Mode
#   "Truncate" is typical.  "Round_Pos_Inf" or "Nearest_Even" may differ by 1 LSB.
#   Confirmed by: property report.
#
# [TODO-8] CONFIG.Has_ARESETn
#   Expected: "true" — enables the aresetn port (active-low synchronous reset).
#   Confirmed by: property report.  Required by wrapper interface.
#
# [TODO-9] CONFIG.Flow_Control
#   "Blocking" means the IP uses tvalid/tready handshake.
#   "NonBlocking" means it runs at full rate without tready.
#   Wrapper always drives tready=1, so either works; Blocking is cleaner.
#   Confirmed by: property report.
#
# [TODO-10] CONFIG.Latency / CONFIG.Latency_Configuration
#   Some Vivado versions expose CONFIG.Latency as a read-only computed value.
#   Others allow setting it.  After generation, check actual latency via report_property.
#   Target: $target_latency = 15 cycles.

log_msg $fh_log "INFO: Applying configuration properties..."

if {[catch {
    set_property -dict [list \
        CONFIG.Functional_Selection        {Translate}         \
        CONFIG.Architectural_Configuration {Fully_Pipelined}   \
        CONFIG.Pipelining_Mode             {Maximum}           \
        CONFIG.Input_Width                 $input_width        \
        CONFIG.Output_Width                $phase_width        \
        CONFIG.Phase_Format                {Scaled_Radians}    \
        CONFIG.Round_Mode                  {Truncate}          \
        CONFIG.Has_ARESETn                 {true}              \
        CONFIG.Has_ACLKEN                  {false}             \
        CONFIG.Flow_Control                {Blocking}          \
    ] [get_ips $ip_name]
} err]} {
    log_msg $fh_log "ERROR: set_property failed: $err"
    log_msg $fh_log "ACTION: Run probe_cordic_ip_properties.tcl, verify CONFIG key names,"
    log_msg $fh_log "        then update this script with correct property names."
    close $fh_log
    error "set_property failed — see $log_file"
}

log_msg $fh_log "INFO: Properties applied."

# ---------------------------------------------------------------------------
# Read back actual latency (may be set by Vivado after configuration)
# ---------------------------------------------------------------------------
if {[catch {
    set actual_latency [get_property CONFIG.Latency [get_ips $ip_name]]
    log_msg $fh_log "INFO: Configured latency (CONFIG.Latency): $actual_latency"
    if {$actual_latency != $target_latency} {
        log_msg $fh_log "WARN: Actual latency ($actual_latency) != target ($target_latency)."
        log_msg $fh_log "WARN: Update LATENCY parameter in rtl/cordic_atan2_xilinx_wrapper.v"
        log_msg $fh_log "WARN: and in rtl/frac_cfo_estimator.v (CORDIC_LATENCY) when integrating."
    } else {
        log_msg $fh_log "INFO: Latency matches target ($target_latency). OK."
    }
} err]} {
    log_msg $fh_log "WARN: Could not read CONFIG.Latency: $err"
    log_msg $fh_log "WARN: Check latency manually from report_property output."
}

# ---------------------------------------------------------------------------
# Dump all CONFIG.* properties to property report
# ---------------------------------------------------------------------------
set prop_file "$report_dir/cordic_atan2_ip_properties.txt"
set fh_prop [open $prop_file w]
puts $fh_prop "# CORDIC atan2 IP — Property Report"
puts $fh_prop "# Generated by scripts/create_cordic_atan2_ip.tcl"
puts $fh_prop "# Timestamp: [clock format [clock seconds]]"
puts $fh_prop "# Vivado: [version -short]"
puts $fh_prop ""
puts $fh_prop "# All properties:"
puts $fh_prop [report_property [get_ips $ip_name] -return_string]
puts $fh_prop ""
puts $fh_prop "# CONFIG.* values:"
foreach prop [lsort [list_property [get_ips $ip_name]]] {
    if {[string match "CONFIG.*" $prop]} {
        puts $fh_prop "  [format %-45s $prop] = [get_property $prop [get_ips $ip_name]]"
    }
}
close $fh_prop
log_msg $fh_log "INFO: Property report: $prop_file"

# ---------------------------------------------------------------------------
# Generate output products
# ---------------------------------------------------------------------------
log_msg $fh_log "INFO: Generating output products (stubs, instantiation template)..."

if {[catch {
    generate_target all [get_ips $ip_name]
} err]} {
    log_msg $fh_log "WARN: generate_target failed: $err"
    log_msg $fh_log "WARN: XCI may still be usable but output products are incomplete."
} else {
    log_msg $fh_log "INFO: Output products generated."
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
log_msg $fh_log ""
log_msg $fh_log "============================================================"
log_msg $fh_log "CORDIC atan2 IP creation complete."
log_msg $fh_log "IP directory:      $ip_dir"
log_msg $fh_log "XCI expected at:   $ip_dir/$ip_name/$ip_name.xci"
log_msg $fh_log "Property report:   $prop_file"
log_msg $fh_log ""
log_msg $fh_log "NEXT STEPS:"
log_msg $fh_log "  1. Verify CONFIG.Latency matches LATENCY=15 in wrapper."
log_msg $fh_log "     If not: update LATENCY in rtl/cordic_atan2_xilinx_wrapper.v."
log_msg $fh_log "  2. Verify phase scaling: run simulation with test angle pi/2."
log_msg $fh_log "     Expected output: ~+16383 (0x3FFF) for pi/2."
log_msg $fh_log "  3. Verify tdata packing: s_axis_cartesian_tdata[31:0]=I, [63:32]=Q."
log_msg $fh_log "  4. Inspect generated instantiation template (.veo or .vho) in:"
log_msg $fh_log "     $ip_dir/$ip_name/"
log_msg $fh_log "  5. Replace gen_ip_placeholder in rtl/cordic_atan2_xilinx_wrapper.v"
log_msg $fh_log "     with actual $ip_name instantiation."
log_msg $fh_log "  6. Add XCI path to simulation compile list when testing with USE_BEHAVIORAL_MODEL=0."
log_msg $fh_log "  7. Run tb/cordic_atan2_xilinx_wrapper_tb.sv to validate."
log_msg $fh_log "============================================================"
close $fh_log
