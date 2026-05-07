# =============================================================================
# step27_create_zcu102_bd_no_ila.tcl
# Step 27: ZCU102 Vivado Block Design — frac_cfo_sync_bram_test_wrapper
#          No ILA, No DMA, No implementation.
#
# Run from Windows Vivado 2022.2 batch mode, from C:\RTL_SYNC:
#   C:\Xilinx\Vivado\2022.2\bin\vivado.bat -mode batch \
#       -source scripts/vivado/step27_create_zcu102_bd_no_ila.tcl
#
# Block design: sync_phase1_bd
# Architecture:
#   Zynq UltraScale+ MPSoC
#     -> M_AXI_HPM0_FPD
#     -> AXI SmartConnect (1 master, 1 slave)
#     -> frac_cfo_sync_bram_test_wrapper (AXI-Lite slave)
#
# Address map:
#   wrapper base = 0xA000_0000
#   wrapper range = 64 KB (covers 0x0000-0x2FFF)
# =============================================================================

set PART        "xczu9eg-ffvb1156-2-e"
set BOARD_PART  "xilinx.com:zcu102:part0:3.4"
set PROJ_NAME   "step27_zcu102_bd"
set PROJ_DIR    "vivado/step27_zcu102_bd"
set BD_NAME     "sync_phase1_bd"
set RTL         "rtl"
set RPTS        "reports/step27"
set WRAP_MOD    "frac_cfo_sync_bram_test_wrapper"
set WRAP_CELL   "wrapper_0"
set WRAP_BASE   "0xA0000000"
set WRAP_RANGE  "64K"

puts "========================================================"
puts "Step 27: ZCU102 Block Design Creation"
puts "Part:    $PART"
puts "BD:      $BD_NAME"
puts "Top RTL: $WRAP_MOD"
puts "No ILA | No DMA | No implementation"
puts "========================================================"

file mkdir $RPTS
file mkdir $PROJ_DIR

# =============================================================================
# 1. Create Vivado project
# =============================================================================
create_project $PROJ_NAME $PROJ_DIR -part $PART -force
set_property default_lib    work    [current_project]
set_property target_language Verilog [current_project]

# Attempt to load ZCU102 board files (requires Vivado board store)
if {[catch {set_property board_part $BOARD_PART [current_project]} err]} {
    puts "INFO: Board part '$BOARD_PART' not found — continuing without board preset."
    puts "      Install ZCU102 board files from Vivado board store if needed."
    set board_available 0
} else {
    puts "INFO: ZCU102 board part loaded."
    set board_available 1
}

# =============================================================================
# 2. Add all RTL sources for frac_cfo_sync_bram_test_wrapper hierarchy
# =============================================================================
puts "INFO: Reading RTL sources..."
read_verilog -sv [list \
    $RTL/axis_complex_mult.v \
    $RTL/complex_mult_iq.v \
    $RTL/complex_rotator.v \
    $RTL/nco_phase_gen.v \
    $RTL/frac_cfo_corrector_top.v \
    $RTL/cp_autocorr_core.v \
    $RTL/timing_metric_core.v \
    $RTL/peak_detector.v \
    $RTL/timing_sync_top.v \
    $RTL/cordic_atan2.v \
    $RTL/frac_cfo_estimator.v \
    $RTL/timing_frac_cfo_top.v \
    $RTL/iq_frame_buffer.v \
    $RTL/frame_detector.v \
    $RTL/frac_cfo_frame_corrector_top.v \
    $RTL/frac_cfo_sync_control_s_axi.v \
    $RTL/frac_cfo_sync_axi_stream_wrapper.v \
    $RTL/frac_cfo_sync_bram_test_wrapper.v \
]

update_compile_order -fileset sources_1
puts "INFO: RTL sources loaded."

# =============================================================================
# 3. Create block design
# =============================================================================
puts "INFO: Creating block design '$BD_NAME'..."
create_bd_design $BD_NAME
current_bd_design $BD_NAME

# =============================================================================
# 4. Add Zynq UltraScale+ MPSoC PS
# =============================================================================
puts "INFO: Adding Zynq UltraScale+ MPSoC..."
set ps [create_bd_cell -type ip \
    -vlnv xilinx.com:ip:zynq_ultra_ps_e:* \
    zynq_ultra_ps_e_0]

# Try board automation (configures DDR, clocks, etc. from board preset)
set bd_auto_ok 0
if {$board_available} {
    if {[catch {
        apply_bd_automation \
            -rule xilinx.com:bd_rule:zynq_ultra_ps_e \
            -config {apply_board_preset "1"} \
            [get_bd_cells zynq_ultra_ps_e_0]
        set bd_auto_ok 1
        puts "INFO: Board automation applied — PS configured from ZCU102 preset."
    } err]} {
        puts "INFO: Board automation failed ($err) — using manual PS config."
    }
}

# Minimal manual PS configuration (applied if board automation unavailable,
# or as idempotent reinforcement after automation).
# Enable M_AXI_HPM0_FPD (PL AXI master for peripheral control)
set_property CONFIG.PSU__USE__M_AXI_GP0 {1} $ps

# Enable PL clock 0 at 100 MHz
set_property CONFIG.PSU__FPGA_PL0_ENABLE          {1}   $ps
set_property CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ {100} $ps

puts "INFO: PS configuration applied."

# =============================================================================
# 5. Add Processor System Reset
# =============================================================================
puts "INFO: Adding proc_sys_reset..."
set rst0 [create_bd_cell -type ip \
    -vlnv xilinx.com:ip:proc_sys_reset:* \
    proc_sys_reset_0]

# Tie dcm_locked to 1 (no external DCM/MMCM in this design)
set const1 [create_bd_cell -type ip \
    -vlnv xilinx.com:ip:xlconstant:* \
    xlconstant_0]
set_property CONFIG.CONST_VAL   {1} $const1
set_property CONFIG.CONST_WIDTH {1} $const1

# =============================================================================
# 6. Add AXI SmartConnect (1 master in, 1 slave out)
# =============================================================================
puts "INFO: Adding AXI SmartConnect..."
set sc [create_bd_cell -type ip \
    -vlnv xilinx.com:ip:smartconnect:* \
    axi_smc]
set_property CONFIG.NUM_SI   {1} $sc
set_property CONFIG.NUM_CLKS {1} $sc

# =============================================================================
# 7. Add frac_cfo_sync_bram_test_wrapper as BD module
# =============================================================================
puts "INFO: Adding $WRAP_MOD as BD module ($WRAP_CELL)..."
set wrap [create_bd_cell -type module \
    -reference $WRAP_MOD \
    $WRAP_CELL]

# =============================================================================
# 8. Clock connections  (all on PL clock 0 = 100 MHz domain)
# =============================================================================
puts "INFO: Connecting clocks..."

# PL clock 0 → HPM0 FPD clock input (required for PS AXI master)
connect_bd_net \
    [get_bd_pins zynq_ultra_ps_e_0/pl_clk0] \
    [get_bd_pins zynq_ultra_ps_e_0/maxihpm0_fpd_aclk]

# PL clock 0 → proc_sys_reset slowest_sync_clk
connect_bd_net \
    [get_bd_pins zynq_ultra_ps_e_0/pl_clk0] \
    [get_bd_pins proc_sys_reset_0/slowest_sync_clk]

# PL clock 0 → SmartConnect aclk
connect_bd_net \
    [get_bd_pins zynq_ultra_ps_e_0/pl_clk0] \
    [get_bd_pins axi_smc/aclk]

# PL clock 0 → wrapper aclk
connect_bd_net \
    [get_bd_pins zynq_ultra_ps_e_0/pl_clk0] \
    [get_bd_pins ${WRAP_CELL}/aclk]

# =============================================================================
# 9. Reset connections
# =============================================================================
puts "INFO: Connecting resets..."

# PS pl_resetn0 (active-low) → proc_sys_reset ext_reset_in
connect_bd_net \
    [get_bd_pins zynq_ultra_ps_e_0/pl_resetn0] \
    [get_bd_pins proc_sys_reset_0/ext_reset_in]

# Constant 1 → proc_sys_reset dcm_locked
connect_bd_net \
    [get_bd_pins xlconstant_0/dout] \
    [get_bd_pins proc_sys_reset_0/dcm_locked]

# proc_sys_reset peripheral_aresetn (active-low) → SmartConnect aresetn
connect_bd_net \
    [get_bd_pins proc_sys_reset_0/peripheral_aresetn] \
    [get_bd_pins axi_smc/aresetn]

# proc_sys_reset peripheral_aresetn → wrapper aresetn
connect_bd_net \
    [get_bd_pins proc_sys_reset_0/peripheral_aresetn] \
    [get_bd_pins ${WRAP_CELL}/aresetn]

# =============================================================================
# 10. AXI interface connections
# =============================================================================
puts "INFO: Connecting AXI interfaces..."

# PS HPM0 FPD master → SmartConnect slave 0
connect_bd_intf_net \
    [get_bd_intf_pins zynq_ultra_ps_e_0/M_AXI_HPM0_FPD] \
    [get_bd_intf_pins axi_smc/S00_AXI]

# SmartConnect master 0 → wrapper AXI-Lite slave
connect_bd_intf_net \
    [get_bd_intf_pins axi_smc/M00_AXI] \
    [get_bd_intf_pins ${WRAP_CELL}/s_axi]

# =============================================================================
# 11. Address assignment
# =============================================================================
puts "INFO: Assigning addresses..."
assign_bd_address

# Set wrapper base address and range
set segs [get_bd_addr_segs -of_objects \
    [get_bd_intf_pins ${WRAP_CELL}/s_axi]]

if {[llength $segs] > 0} {
    set seg [lindex $segs 0]
    set_property offset $WRAP_BASE $seg
    set_property range  $WRAP_RANGE $seg
    puts "INFO: $WRAP_CELL address: $WRAP_BASE, range $WRAP_RANGE"
} else {
    puts "WARNING: Address segment for ${WRAP_CELL}/s_axi not found."
    puts "         Run assign_bd_address and set address manually in GUI."
}

# =============================================================================
# 12. Validate block design
# =============================================================================
puts "INFO: Validating block design..."
if {[catch {validate_bd_design} vld_err]} {
    puts "WARNING: validate_bd_design reported: $vld_err"
    puts "INFO:    Continuing — check Vivado messages for critical vs. advisory."
} else {
    puts "INFO: Block design validated OK."
}

# =============================================================================
# 13. Save block design
# =============================================================================
save_bd_design
puts "INFO: Block design saved."

# =============================================================================
# 14. Create HDL wrapper and set as top
# =============================================================================
puts "INFO: Creating HDL wrapper..."
set bd_files [get_files ${BD_NAME}.bd]
if {[llength $bd_files] > 0} {
    set wrapper_file [make_wrapper -files [lindex $bd_files 0] -top]
    add_files -norecurse $wrapper_file
    set_property top ${BD_NAME}_wrapper [current_fileset]
    update_compile_order -fileset sources_1
    puts "INFO: HDL wrapper '${BD_NAME}_wrapper' set as top."
} else {
    puts "WARNING: BD file not found — HDL wrapper not created."
}

# =============================================================================
# 15. Generate output products (no synthesis)
# =============================================================================
puts "INFO: Generating block design output products..."
if {[catch {
    generate_target all [get_files ${BD_NAME}.bd]
} gen_err]} {
    puts "WARNING: generate_target: $gen_err"
}

# =============================================================================
# Done
# =============================================================================
puts ""
puts "========================================================"
puts "Step 27 block design COMPLETE."
puts "Project:  $PROJ_DIR/$PROJ_NAME.xpr"
puts "BD:       $BD_NAME"
puts "Top:      ${BD_NAME}_wrapper"
puts "Address:  $WRAP_BASE (range $WRAP_RANGE)"
puts ""
puts "No synthesis, no implementation, no bitstream generated."
puts "RTL not modified."
puts ""
puts "Next step (Step 28 — Windows Vivado):"
puts "  launch_runs synth_1 -jobs 4"
puts "  wait_on_run synth_1"
puts "  launch_runs impl_1 -to_step write_bitstream -jobs 4"
puts "  wait_on_run impl_1"
puts "  write_hw_platform -fixed -include_bit -force \\"
puts "    -file reports/step28/sync_phase1.xsa"
puts "========================================================"

exit 0
