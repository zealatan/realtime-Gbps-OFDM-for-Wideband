# =============================================================================
# step22_synth_check.tcl — Phase-1 OOC Synthesis Check for ZCU102
# =============================================================================
# Target:  frac_cfo_frame_corrector_top
# Part:    xczu9eg-ffvb1156-2-e (ZCU102)
# Clock:   aclk, 100 MHz (10.000 ns period)
# Mode:    Out-of-context (OOC) synthesis — no I/O constraints required
#
# Run from Windows PowerShell/CMD in C:\RTL_SYNC:
#   C:\Xilinx\Vivado\2022.2\bin\vivado.bat -mode batch -source scripts/step22_synth_check.tcl
#
# Synthesis stub strategy:
#   cordic_atan2.v and nco_phase_gen.v are behavioral simulation models that use
#   the 'real' data type and $sin/$cos/$atan2 system functions, which are not
#   synthesizable. For the OOC synthesis check, synthesizable port-only stubs are
#   substituted. In production, replace these stubs with Xilinx cordic_v6_0 IP.
# =============================================================================

set TOP   frac_cfo_frame_corrector_top
set PART  xczu9eg-ffvb1156-2-e
set RTL   rtl
set STUBS scripts/synth_stubs
set RPTS  reports

puts "========================================================"
puts "Step 22 OOC Synthesis: $TOP on $PART"
puts "========================================================"

# --- Create report directory -------------------------------------------------
file mkdir $RPTS

# --- Create in-memory project ------------------------------------------------
create_project -in_memory -part $PART synth_step22
set_property default_lib work [current_project]

# --- Read RTL sources --------------------------------------------------------
# Note: cordic_atan2.v and nco_phase_gen.v are REPLACED by synthesis stubs.
# All other sources are read as-is.

puts "INFO: Reading synthesizable RTL sources..."
read_verilog -sv [list \
    $RTL/axis_complex_mult.v        \
    $RTL/complex_mult_iq.v          \
    $RTL/complex_rotator.v          \
    $RTL/iq_frame_buffer.v          \
    $RTL/frame_detector.v           \
    $RTL/cp_autocorr_core.v         \
    $RTL/timing_metric_core.v       \
    $RTL/peak_detector.v            \
    $RTL/frac_cfo_estimator.v       \
    $RTL/frac_cfo_corrector_top.v   \
    $RTL/timing_sync_top.v          \
    $RTL/timing_frac_cfo_top.v      \
    $RTL/frac_cfo_frame_corrector_top.v \
]

puts "INFO: Reading synthesis stubs (replace behavioral CORDIC models)..."
read_verilog [list \
    $STUBS/cordic_atan2_stub.v  \
    $STUBS/nco_phase_gen_stub.v \
]

# --- Set top module and OOC mode --------------------------------------------
set_property top $TOP [current_fileset]

# --- Apply OOC constraints --------------------------------------------------
# Clock constraint for timing analysis
read_xdc -unmanaged -mode out_of_context [list]
create_clock -period 10.000 -name aclk [get_ports aclk]

# OOC: mark top-level ports as false paths to suppress missing constraint warnings
set_false_path -from [get_ports] -to [get_ports]

# --- Run synthesis -----------------------------------------------------------
puts "INFO: Starting synth_design (OOC mode)..."
if { [catch {
    synth_design \
        -top  $TOP  \
        -part $PART \
        -mode out_of_context \
        -include_dirs $RTL
} err] } {
    puts "ERROR: synth_design failed: $err"
    write_project_tcl -force $RPTS/step22_synth_failed.tcl
    exit 1
}

puts "INFO: Synthesis complete. Generating reports..."

# --- Reports -----------------------------------------------------------------
# Utilization
report_utilization \
    -file $RPTS/step22_synth_utilization.rpt \
    -hierarchical
puts "INFO: Wrote $RPTS/step22_synth_utilization.rpt"

# Timing summary
report_timing_summary \
    -file $RPTS/step22_timing_summary.rpt \
    -delay_type max \
    -report_unconstrained \
    -check_timing_verbose \
    -max_paths 10 \
    -input_pins \
    -routable_nets
puts "INFO: Wrote $RPTS/step22_timing_summary.rpt"

# DRC check
report_drc \
    -file $RPTS/step22_drc.rpt
puts "INFO: Wrote $RPTS/step22_drc.rpt"

# Clock interaction
report_clock_interaction \
    -file $RPTS/step22_clock_interaction.rpt
puts "INFO: Wrote $RPTS/step22_clock_interaction.rpt"

# --- Extract key metrics from timing summary --------------------------------
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
puts "========================================================"
puts "TIMING: WNS = $wns ns (target 100 MHz / 10.000 ns)"
if { $wns >= 0 } {
    puts "TIMING: PASS (positive slack)"
} else {
    puts "TIMING: FAIL (negative slack = timing violation)"
}
puts "========================================================"

# --- Print utilization summary to console -----------------------------------
report_utilization -return_string -hierarchical | puts

puts "========================================================"
puts "Step 22 OOC synthesis COMPLETE."
puts "Reports written to: $RPTS/"
puts "  step22_synth_utilization.rpt"
puts "  step22_timing_summary.rpt"
puts "  step22_drc.rpt"
puts "  step22_clock_interaction.rpt"
puts ""
puts "CORDIC IP REPLACEMENT REQUIRED before production synthesis:"
puts "  cordic_atan2  -> cordic_v6_0 IP (translate mode, 16-bit phase)"
puts "  nco_phase_gen -> cordic_v6_0 IP (rotate/sincos mode) + phase accumulator"
puts "========================================================"
