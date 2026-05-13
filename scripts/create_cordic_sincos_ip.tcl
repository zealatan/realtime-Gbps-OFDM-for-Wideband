# create_cordic_sincos_ip.tcl — Create Xilinx CORDIC IP for rotate-mode sin/cos generation.
#
# STATUS: PRELIMINARY — property names require confirmation via
#         scripts/probe_cordic_ip_properties.tcl before treating as verified.
#         Run probe_cordic_ip_properties.tcl first, review the CONFIG.* report
#         for the rotate-mode instance, then update TODO items before generating.
#
# PURPOSE:
#   Create a Xilinx CORDIC IP (cordic_v6_0) configured for rotate mode to replace
#   the 256-entry ROM sin/cos path in nco_phase_gen_xilinx_wrapper.v.
#
# TARGET: Vivado 2022.2
#
# Usage (Vivado Tcl console with project open, or batch mode):
#   source scripts/create_cordic_sincos_ip.tcl
#
# IP output directory:
#   ip/cordic_sincos_xilinx/
#
# Reports written to:
#   reports/cordic_sincos_ip_generation.log
#   reports/cordic_sincos_ip_properties.txt
#
# ---------------------------------------------------------------------------
# Design context — NCO phase convention (from nco_phase_gen_xilinx_wrapper.v)
# ---------------------------------------------------------------------------
#
#   Phase accumulator: 32-bit unsigned, wraps at 2^32 = full 2*pi.
#   Legacy sin/cos path: phase_acc[31:24] → 256-entry ROM (8-bit index).
#
#   CORDIC rotate-mode phase input: signed integer, maps [-pi, +pi) to
#   the full integer range of the input width.
#
#   Two integration modes are documented:
#
#   MODE A — Legacy-compatible (RECOMMENDED FIRST):
#     phase input = zero-extend( phase_acc[31:24] ) << 8 → {phase_acc[31:24], 8'h00}
#     Or more precisely: map 256-ROM index to Scaled_Radians 16-bit value.
#     phase_acc[31:24] = 0..255 → 0..65535 → interpret as unsigned angle index.
#     To match ROM: signed_phase_in = signed( { phase_acc[31], phase_acc[31:17] } )
#     i.e., phase_acc[31:16] treated as signed Q1.15.
#     This gives the same effective resolution as the 256-ROM (8-bit phase resolution)
#     when only the top 8 bits change significantly between steps.
#     Best for bit-exact or near-bit-exact regression against legacy ROM output.
#
#   MODE B — High-resolution (FUTURE UPGRADE):
#     phase input = signed( phase_acc[31:16] )  — full 16-bit phase resolution.
#     Better spectral purity; not bit-exact to legacy ROM.
#     Requires updated testbench tolerances (tolerance instead of exact match).
#
#   The phase accumulator itself is NOT inside this IP.
#   The accumulator remains in nco_phase_gen_xilinx_wrapper.v (rtl).
#
# ---------------------------------------------------------------------------
# Interface target (must match nco_phase_gen_xilinx_wrapper.v)
# ---------------------------------------------------------------------------
#
#   aclk                         — clock
#   aresetn                      — active-low synchronous reset
#   s_axis_phase_tvalid          — input valid  (= enable && !phase_reset)
#   s_axis_phase_tdata[15:0]     — signed 16-bit phase (Q1.15 Scaled_Radians)
#                                   range: -32768 → -pi, +32767 → +pi
#   m_axis_dout_tvalid           — output valid (LATENCY cycles after input valid)
#   m_axis_dout_tdata[31:0]      — {sin[15:0], cos[15:0]} packed output
#                                   sin = upper 16 bits, cos = lower 16 bits
#                                   (verify from generated instantiation template)
#
# Output scaling with Scale_Compensation enabled:
#   cos(0) → cos_out = +32767 ≈ +1.0
#   sin(pi/2) → sin_out = +32767 ≈ +1.0
#   sin(0) → sin_out = 0

# ---------------------------------------------------------------------------
# Parameters
# ---------------------------------------------------------------------------
set ip_name         "cordic_sincos_xilinx"
set ip_dir          "./ip/cordic_sincos_xilinx"
set report_dir      "./reports"
set phase_width     16
set output_width    16
set target_latency  15

# ---------------------------------------------------------------------------
# Directory setup
# ---------------------------------------------------------------------------
file mkdir $ip_dir
file mkdir $report_dir

set log_file "$report_dir/cordic_sincos_ip_generation.log"
set fh_log [open $log_file w]

proc log_sincos {fh msg} {
    puts $msg
    puts $fh $msg
}

log_sincos $fh_log "# CORDIC sincos IP Generation Log"
log_sincos $fh_log "# Script: scripts/create_cordic_sincos_ip.tcl"
log_sincos $fh_log "# Timestamp: [clock format [clock seconds]]"
log_sincos $fh_log "# Target: Vivado [version -short]"
log_sincos $fh_log "# ip_name:      $ip_name"
log_sincos $fh_log "# ip_dir:       $ip_dir"
log_sincos $fh_log "# phase_width:  $phase_width (signed input bits)"
log_sincos $fh_log "# output_width: $output_width (sin/cos bits each)"
log_sincos $fh_log "# target_latency: $target_latency cycles"
log_sincos $fh_log ""

# ---------------------------------------------------------------------------
# Remove existing instance if present (allow re-run)
# ---------------------------------------------------------------------------
if {[llength [get_ips -quiet $ip_name]] > 0} {
    log_sincos $fh_log "INFO: Removing existing IP instance: $ip_name"
    remove_ip [get_ips $ip_name]
}

# ---------------------------------------------------------------------------
# Create CORDIC IP instance
# ---------------------------------------------------------------------------
log_sincos $fh_log "INFO: Creating CORDIC IP instance: $ip_name"

if {[catch {
    create_ip \
        -name cordic \
        -vendor xilinx.com \
        -library ip \
        -version 6.0 \
        -module_name $ip_name \
        -dir $ip_dir
} err]} {
    log_sincos $fh_log "ERROR: create_ip failed: $err"
    log_sincos $fh_log "ACTION: Run scripts/probe_cordic_ip_properties.tcl to verify IP availability."
    close $fh_log
    error "create_ip failed — see $log_file"
}

log_sincos $fh_log "INFO: IP instance created."

# ---------------------------------------------------------------------------
# Configure the IP
# ---------------------------------------------------------------------------
# TODO items — review after running probe_cordic_ip_properties.tcl (rotate probe):
#
# [TODO-1] CONFIG.Functional_Selection = "Rotate"
#   Confirmed by: VALUE_RANGE in cordic_rotate_property_probe.txt.
#   This selects the rotate mode (phase → cos/sin).
#
# [TODO-2] CONFIG.Phase_Format = "Scaled_Radians"
#   Effect: s_axis_phase_tdata is a signed integer where the full range
#   maps to [-pi, +pi).  With phase_width=16: -32768 → -pi, +32767 → +pi.
#   Alternative: "Radians" — may use a different interpretation; check report.
#
# [TODO-3] CONFIG.Input_Width = 16 (phase_width)
#   For rotate mode, Input_Width governs the phase port width.
#   The Cartesian output width is governed by Output_Width.
#
# [TODO-4] CONFIG.Output_Width = 16
#   Controls the cos/sin output precision.
#
# [TODO-5] CONFIG.Scale_Compensation
#   Enum expected: "true" or {Yes} — check VALUE_RANGE in probe report.
#   Effect: removes CORDIC gain (~1.6468) so outputs are normalised to ±1.
#   Must be enabled; otherwise cos/sin outputs exceed Q1.15 range.
#   Confirm the exact property key and value from the probe report.
#
# [TODO-6] CONFIG.Has_ARESETn = "true"
#   Enables aresetn port.  Required for synchronous reset compatibility.
#
# [TODO-7] CONFIG.Has_ACLKEN = "false"
#   aclken not currently needed; phase accumulator and valid gating are in wrapper.
#
# [TODO-8] CONFIG.Flow_Control = "Blocking"
#   Enables AXI-Stream tvalid/tready handshake.  Wrapper drives phase_tvalid
#   from "enable && !phase_reset".
#
# [TODO-9] CONFIG.Architectural_Configuration = "Fully_Pipelined"
#   Required for maximum throughput (one output per clock after latency).

log_sincos $fh_log "INFO: Applying configuration..."

if {[catch {
    set_property -dict [list \
        CONFIG.Functional_Selection        {Rotate}            \
        CONFIG.Architectural_Configuration {Fully_Pipelined}   \
        CONFIG.Pipelining_Mode             {Maximum}           \
        CONFIG.Input_Width                 $phase_width        \
        CONFIG.Output_Width                $output_width       \
        CONFIG.Phase_Format                {Scaled_Radians}    \
        CONFIG.Scale_Compensation          {true}              \
        CONFIG.Has_ARESETn                 {true}              \
        CONFIG.Has_ACLKEN                  {false}             \
        CONFIG.Flow_Control                {Blocking}          \
    ] [get_ips $ip_name]
} err]} {
    log_sincos $fh_log "ERROR: set_property failed: $err"
    log_sincos $fh_log "ACTION: Check probe report for correct key names."
    close $fh_log
    error "set_property failed — see $log_file"
}

log_sincos $fh_log "INFO: Properties applied."

# ---------------------------------------------------------------------------
# Read back actual latency
# ---------------------------------------------------------------------------
if {[catch {
    set actual_latency [get_property CONFIG.Latency [get_ips $ip_name]]
    log_sincos $fh_log "INFO: Configured latency (CONFIG.Latency): $actual_latency"
    if {$actual_latency != $target_latency} {
        log_sincos $fh_log "WARN: Actual latency ($actual_latency) != target ($target_latency)."
        log_sincos $fh_log "WARN: Update LATENCY in rtl/nco_phase_gen_xilinx_wrapper.v to $actual_latency."
        log_sincos $fh_log "WARN: Also update nco_phase_gen_xilinx_wrapper_tb.sv if it depends on LATENCY."
    } else {
        log_sincos $fh_log "INFO: Latency matches target ($target_latency). OK."
    }
} err]} {
    log_sincos $fh_log "WARN: Could not read CONFIG.Latency: $err"
    log_sincos $fh_log "WARN: Determine latency from report_property or generated IP report."
}

# ---------------------------------------------------------------------------
# Dump property report
# ---------------------------------------------------------------------------
set prop_file "$report_dir/cordic_sincos_ip_properties.txt"
set fh_prop [open $prop_file w]
puts $fh_prop "# CORDIC sincos IP — Property Report"
puts $fh_prop "# Generated by scripts/create_cordic_sincos_ip.tcl"
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
log_sincos $fh_log "INFO: Property report: $prop_file"

# ---------------------------------------------------------------------------
# Generate output products
# ---------------------------------------------------------------------------
log_sincos $fh_log "INFO: Generating output products..."

if {[catch {
    generate_target all [get_ips $ip_name]
} err]} {
    log_sincos $fh_log "WARN: generate_target failed: $err"
    log_sincos $fh_log "WARN: XCI may still be usable without output products."
} else {
    log_sincos $fh_log "INFO: Output products generated."
}

# ---------------------------------------------------------------------------
# Document Mode A vs Mode B phase mapping
# ---------------------------------------------------------------------------
log_sincos $fh_log ""
log_sincos $fh_log "# ============================================================"
log_sincos $fh_log "# PHASE MAPPING NOTES — for wrapper integration"
log_sincos $fh_log "# ============================================================"
log_sincos $fh_log "#"
log_sincos $fh_log "# MODE A — Legacy-compatible (RECOMMENDED FOR FIRST INTEGRATION):"
log_sincos $fh_log "#   Use phase_acc\[31:16\] as signed 16-bit phase input."
log_sincos $fh_log "#   This maps 2^16 = 65536 accumulator steps to one full 2*pi cycle."
log_sincos $fh_log "#   Resolution: 2*pi / 65536 radians per step ≈ 0.0000958 rad/step."
log_sincos $fh_log "#   The legacy 256-ROM used 2*pi / 256 per step (8-bit resolution)."
log_sincos $fh_log "#   CORDIC with 16-bit phase provides much finer resolution but output"
log_sincos $fh_log "#   will NOT be bit-exact to legacy ROM — regression tolerance update needed."
log_sincos $fh_log "#"
log_sincos $fh_log "#   Wrapper assignment:"
log_sincos $fh_log "#     assign cordic_phase_in = \$signed(phase_acc_r\[31:16\]);"
log_sincos $fh_log "#"
log_sincos $fh_log "# MODE B — Strict legacy-match (closest to 256-ROM behavior):"
log_sincos $fh_log "#   Use phase_acc\[31:24\] (8-bit ROM index) expanded to 16 bits."
log_sincos $fh_log "#     assign cordic_phase_in = \$signed({phase_acc_r\[31:24\], 8'h00});"
log_sincos $fh_log "#   This gives exactly 256 effective phase values per 2*pi cycle."
log_sincos $fh_log "#   Closest to ROM but wastes CORDIC precision."
log_sincos $fh_log "#   Use only if bit-exact regression with old ROM is required."
log_sincos $fh_log "#"
log_sincos $fh_log "# RECOMMENDATION: Start with Mode A (16-bit phase_acc\[31:16\]) to"
log_sincos $fh_log "# exploit full CORDIC precision.  Update regression tolerances accordingly."

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
log_sincos $fh_log ""
log_sincos $fh_log "============================================================"
log_sincos $fh_log "CORDIC sincos IP creation complete."
log_sincos $fh_log "IP directory:      $ip_dir"
log_sincos $fh_log "XCI expected at:   $ip_dir/$ip_name/$ip_name.xci"
log_sincos $fh_log "Property report:   $prop_file"
log_sincos $fh_log ""
log_sincos $fh_log "NEXT STEPS:"
log_sincos $fh_log "  1. Verify CONFIG.Latency from prop report."
log_sincos $fh_log "     If != 15, update LATENCY in nco_phase_gen_xilinx_wrapper.v."
log_sincos $fh_log "  2. Verify output tdata packing: which 16-bit word is sin, which is cos."
log_sincos $fh_log "     Check generated instantiation template (.veo/.vho)."
log_sincos $fh_log "  3. Verify Scale_Compensation was applied: cos(0) output should be +32767."
log_sincos $fh_log "  4. Choose MODE A (phase_acc\[31:16\]) or MODE B (phase_acc\[31:24\]<<8)."
log_sincos $fh_log "  5. Replace gen_xilinx_ip_placeholder in nco_phase_gen_xilinx_wrapper.v"
log_sincos $fh_log "     with actual $ip_name instantiation."
log_sincos $fh_log "  6. Run tb/nco_phase_gen_xilinx_wrapper_tb.sv to validate."
log_sincos $fh_log "============================================================"
close $fh_log
