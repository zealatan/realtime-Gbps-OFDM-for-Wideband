# create_dds_nco_ip.tcl — OPTIONAL: Create Xilinx DDS Compiler IP for NCO sin/cos.
#
# STATUS: OPTIONAL / PRELIMINARY
#   This script is provided for evaluation purposes only.
#   The RECOMMENDED production path for NCO sin/cos replacement is CORDIC rotate mode
#   (see scripts/create_cordic_sincos_ip.tcl).
#
#   Use this script ONLY if probe_dds_ip_properties.tcl + dds_ip_analysis.txt
#   shows that DDS Compiler is preferable for the project's requirements.
#
#   DO NOT integrate DDS into the fractional CFO top path without:
#   1. Resolving phase accumulator ownership (DDS internal vs RTL external).
#   2. Mapping phase_reset to DDS phase_clear or equivalent.
#   3. Mapping step_word to DDS phase increment reload port.
#   4. Validating output tdata packing (sin/cos channel order).
#   5. Confirming latency and updating LATENCY parameter in wrapper.
#
# TARGET: Vivado 2022.2
#   DDS Compiler: xilinx.com:ip:dds_compiler:6.0
#
# Usage:
#   source scripts/create_dds_nco_ip.tcl
#
# IP output directory:
#   ip/dds_nco_xilinx/
#
# Reports:
#   reports/dds_nco_ip_generation.log
#   reports/dds_nco_ip_properties.txt

# ---------------------------------------------------------------------------
# Parameters
# ---------------------------------------------------------------------------
set ip_name         "dds_nco_xilinx"
set ip_dir          "./ip/dds_nco_xilinx"
set report_dir      "./reports"
set phase_width     32
set output_width    16
set target_latency  15

# ---------------------------------------------------------------------------
# Directory setup
# ---------------------------------------------------------------------------
file mkdir $ip_dir
file mkdir $report_dir

set log_file "$report_dir/dds_nco_ip_generation.log"
set fh_log [open $log_file w]

proc log_dds {fh msg} {
    puts $msg
    puts $fh $msg
}

log_dds $fh_log "# DDS NCO IP Generation Log (OPTIONAL)"
log_dds $fh_log "# Script: scripts/create_dds_nco_ip.tcl"
log_dds $fh_log "# Timestamp: [clock format [clock seconds]]"
log_dds $fh_log "# Target: Vivado [version -short]"
log_dds $fh_log "# WARNING: CORDIC rotate mode is the recommended NCO path."
log_dds $fh_log "# This script is for evaluation only."
log_dds $fh_log ""

# ---------------------------------------------------------------------------
# Remove existing instance if present
# ---------------------------------------------------------------------------
if {[llength [get_ips -quiet $ip_name]] > 0} {
    log_dds $fh_log "INFO: Removing existing IP instance: $ip_name"
    remove_ip [get_ips $ip_name]
}

# ---------------------------------------------------------------------------
# Create DDS Compiler IP instance
# ---------------------------------------------------------------------------
log_dds $fh_log "INFO: Creating DDS Compiler IP instance: $ip_name"

if {[catch {
    create_ip \
        -name dds_compiler \
        -vendor xilinx.com \
        -library ip \
        -version 6.0 \
        -module_name $ip_name \
        -dir $ip_dir
} err]} {
    log_dds $fh_log "ERROR: create_ip failed: $err"
    log_dds $fh_log "ACTION: Run scripts/probe_dds_ip_properties.tcl to verify DDS availability."
    close $fh_log
    error "create_ip failed — see $log_file"
}

log_dds $fh_log "INFO: IP instance created."

# ---------------------------------------------------------------------------
# Configure the DDS IP
# ---------------------------------------------------------------------------
# TODO items — verify ALL property names from probe_dds_ip_properties.tcl:
#
# [TODO-1] CONFIG.PartsPresent or CONFIG.Parameter_Selection
#   Determines whether DDS owns the accumulator.
#   "Sine_and_Cosine_LUT_only" — DDS takes phase input externally (preferred).
#   "Phase_Generator_and_SIN_COS_LUT" — DDS owns accumulator (harder to integrate).
#   Target: SIN_COS_LUT_only mode if available, to preserve external accumulator.
#
# [TODO-2] CONFIG.Phase_Width or CONFIG.Phase_Increment_Width
#   Width of the external phase or phase increment input.
#   Should match or be mappable from 32-bit accumulator.
#
# [TODO-3] CONFIG.Output_Width
#   Width of sin/cos outputs.  Target: 16 bits (Q1.15).
#
# [TODO-4] CONFIG.Latency or CONFIG.Latency_Configuration
#   Target: 15 cycles.  Adjust if needed and update wrapper LATENCY parameter.
#
# [TODO-5] CONFIG.Has_Phase_Out
#   May add a phase output port; not needed here.
#
# NOTE: Property names below are PRELIMINARY.  Run probe_dds_ip_properties.tcl
# and cross-check VALUE_RANGE lines before trusting these names.

log_dds $fh_log "INFO: Applying configuration (preliminary — verify property names)..."

if {[catch {
    set_property -dict [list \
        CONFIG.PartsPresent          {SIN_COS_LUT_only} \
        CONFIG.Phase_Width           $phase_width        \
        CONFIG.Output_Width          $output_width       \
        CONFIG.Has_Phase_Out         {false}             \
        CONFIG.Latency_Configuration {Configurable}      \
        CONFIG.Latency               $target_latency     \
    ] [get_ips $ip_name]
} err]} {
    log_dds $fh_log "ERROR: set_property failed: $err"
    log_dds $fh_log "ACTION: Check probe_dds_ip_properties.tcl output for correct property names."
    log_dds $fh_log "ACTION: DDS Compiler property names differ significantly from CORDIC."
    close $fh_log
    error "set_property failed — see $log_file"
}

log_dds $fh_log "INFO: Properties applied."

# ---------------------------------------------------------------------------
# Dump property report
# ---------------------------------------------------------------------------
set prop_file "$report_dir/dds_nco_ip_properties.txt"
set fh_prop [open $prop_file w]
puts $fh_prop "# DDS NCO IP — Property Report"
puts $fh_prop "# Generated by scripts/create_dds_nco_ip.tcl"
puts $fh_prop "# Timestamp: [clock format [clock seconds]]"
puts $fh_prop ""
puts $fh_prop [report_property [get_ips $ip_name] -return_string]
puts $fh_prop ""
puts $fh_prop "# CONFIG.* values:"
foreach prop [lsort [list_property [get_ips $ip_name]]] {
    if {[string match "CONFIG.*" $prop]} {
        puts $fh_prop "  [format %-50s $prop] = [get_property $prop [get_ips $ip_name]]"
    }
}
close $fh_prop
log_dds $fh_log "INFO: Property report: $prop_file"

# ---------------------------------------------------------------------------
# Generate output products
# ---------------------------------------------------------------------------
if {[catch {
    generate_target all [get_ips $ip_name]
    log_dds $fh_log "INFO: Output products generated."
} err]} {
    log_dds $fh_log "WARN: generate_target failed: $err"
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
log_dds $fh_log ""
log_dds $fh_log "============================================================"
log_dds $fh_log "DDS NCO IP creation complete (OPTIONAL/EVALUATION)."
log_dds $fh_log "IP directory:    $ip_dir"
log_dds $fh_log "XCI expected:    $ip_dir/$ip_name/$ip_name.xci"
log_dds $fh_log "Property report: $prop_file"
log_dds $fh_log ""
log_dds $fh_log "IMPORTANT: Before integrating DDS into production:"
log_dds $fh_log "  1. Confirm CONFIG.PartsPresent — does DDS own the accumulator?"
log_dds $fh_log "     If yes, CORDIC rotate mode is strongly preferred."
log_dds $fh_log "  2. Confirm phase input port name and width."
log_dds $fh_log "  3. Confirm output tdata packing: which bits are sin, which are cos."
log_dds $fh_log "  4. Confirm latency and update LATENCY in nco_phase_gen_xilinx_wrapper.v."
log_dds $fh_log "  5. Confirm phase_reset mapping: DDS may need phase_clear port."
log_dds $fh_log "============================================================"
close $fh_log
