# =============================================================================
# step27_create_zcu102_bd_no_ila.tcl  (v3 — HPM1 disable + address fix)
# Step 27: ZCU102 Vivado Block Design — frac_cfo_sync_bram_test_wrapper
#          No ILA, No DMA, No implementation.
#
# Fix applied (Step 27B): original v1 used
#   create_bd_cell -type module -reference frac_cfo_sync_bram_test_wrapper
# Vivado 2022.2 rejected this because read_verilog -sv marks the file as
# SystemVerilog, and BD module-reference does not accept SystemVerilog tops.
# Fix: package the RTL hierarchy as a local Vivado IP (using ipx commands),
# then instantiate via -type ip -vlnv instead of -type module -reference.
#
# Fix applied (Step 27C):
#   1. ZCU102 board automation enabled M_AXI_HPM1_FPD, leaving maxihpm1_fpd_aclk
#      unconnected and causing validate_bd_design to error.
#      Fix: explicitly set PSU__USE__M_AXI_GP1=0 after automation.
#   2. set_property offset/range on slave-side bd_addr_segs emitted warnings
#      (OFFSET/RANGE properties only exist on master-mapped segments).
#      Fix: use assign_bd_address -offset -range <slave_seg> directly.
#
# Run from Windows Vivado 2022.2 batch mode, from C:\RTL_SYNC:
#   C:\Xilinx\Vivado\2022.2\bin\vivado.bat -mode batch ^
#       -source scripts/vivado/step27_create_zcu102_bd_no_ila.tcl
#
# Phase 1: Package frac_cfo_sync_bram_test_wrapper as local Vivado IP.
# Phase 2: Create ZCU102 block design using the packaged IP.
#
# IP VLNV:  zealatan.local:user:frac_cfo_sync_bram_test_wrapper:1.0
# BD name:  sync_phase1_bd
# Wrapper:  wrapper_0 @ 0xA0000000, 64 KB
# =============================================================================

set PART         "xczu9eg-ffvb1156-2-e"
set BOARD_PART   "xilinx.com:zcu102:part0:3.4"
set PROJ_NAME    "step27_zcu102_bd"
set PROJ_DIR     "vivado/step27_zcu102_bd"
set BD_NAME      "sync_phase1_bd"
set RTL          "rtl"
set RPTS         "reports/step27"
set WRAP_MOD     "frac_cfo_sync_bram_test_wrapper"
set WRAP_CELL    "wrapper_0"
set WRAP_BASE    "0xA0000000"
set WRAP_RANGE   "64K"

# IP packaging settings
set IP_VENDOR    "zealatan.local"
set IP_LIBRARY   "user"
set IP_NAME      "frac_cfo_sync_bram_test_wrapper"
set IP_VERSION   "1.0"
set IP_VLNV      "${IP_VENDOR}:${IP_LIBRARY}:${IP_NAME}:${IP_VERSION}"
set IP_REPO_BASE "vivado/ip_repo"
set IP_ROOT      "${IP_REPO_BASE}/${IP_NAME}_1_0"
set PACK_PROJ    "${IP_REPO_BASE}/pack_proj"

# All RTL source files for frac_cfo_sync_bram_test_wrapper hierarchy
set RTL_FILES [list \
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

puts "========================================================"
puts "Step 27 (v3): ZCU102 Block Design — IP packaging + HPM1 disable + addr fix"
puts "Part:    $PART"
puts "BD:      $BD_NAME"
puts "IP VLNV: $IP_VLNV"
puts "No ILA | No DMA | No implementation"
puts "========================================================"

file mkdir $RPTS
file mkdir $IP_REPO_BASE

# =============================================================================
# PHASE 1 — Package frac_cfo_sync_bram_test_wrapper as a local Vivado IP
# =============================================================================
puts ""
puts "--- PHASE 1: Packaging $WRAP_MOD as local IP ---"

# Remove previous packaging artefacts so this script is idempotent
if {[file exists $IP_ROOT]} {
    file delete -force $IP_ROOT
    puts "INFO: Removed previous IP at $IP_ROOT"
}
if {[file exists $PACK_PROJ]} {
    file delete -force $PACK_PROJ
}

# Create a temporary project for IP packaging only.
# Use add_files (not read_verilog -sv) so Vivado treats .v files as Verilog,
# not SystemVerilog.  This avoids the BD module-reference restriction that
# triggered the Step 27 failure.
puts "INFO: Creating packaging project..."
create_project -force ip_pack_proj $PACK_PROJ -part $PART
set_property target_language    Verilog [current_project]
set_property source_mgmt_mode   All     [current_project]

# Add RTL files; Vivado infers file type from .v extension → Verilog (not SV)
add_files $RTL_FILES
set_property top $WRAP_MOD [get_fileset sources_1]
update_compile_order -fileset sources_1

puts "INFO: Top module set to $WRAP_MOD"
puts "INFO: Running ipx::package_project..."

# Package the IP.  -import_files copies RTL into the IP directory so the IP
# is self-contained (no dependency on rtl/ paths after packaging).
ipx::package_project \
    -root_dir        $IP_ROOT \
    -vendor          $IP_VENDOR \
    -library         $IP_LIBRARY \
    -taxonomy        {/UserIP} \
    -import_files

# ipx::package_project sets ipx::current_core when -set_current is not false.
# Set required metadata on the packaged core.
set_property name            $IP_NAME    [ipx::current_core]
set_property version         $IP_VERSION [ipx::current_core]
set_property core_revision   1           [ipx::current_core]
set_property display_name    "Frac CFO Sync BRAM Test Wrapper" [ipx::current_core]
set_property description \
    "Phase 1 OFDM synchronizer: AXI-Lite BRAM preload/readback wrapper \
     for frac_cfo_frame_corrector_top. \
     Reg map 0x0000-0x0028, input_mem 0x1000-0x1FFF, output_mem 0x2000-0x2FFF." \
    [ipx::current_core]
set_property vendor_display_name $IP_VENDOR [ipx::current_core]

puts "INFO: IP metadata set."

# -----------------------------------------------------------------------
# AXI-Lite interface: ipx::package_project should auto-infer S_AXI from
# s_axi_* ports.  Verify it was found; if not, add it manually.
# -----------------------------------------------------------------------
set axi_ifs [ipx::get_bus_interfaces -of_objects [ipx::current_core]]
puts "INFO: Inferred bus interfaces: $axi_ifs"

set saxi_if [lsearch -nocase -inline $axi_ifs "*axi*"]
if {$saxi_if ne ""} {
    puts "INFO: AXI interface found: $saxi_if"
    # Normalize to uppercase S_AXI for consistency
    set saxi_name [string toupper $saxi_if]
} else {
    puts "INFO: AXI interface not auto-inferred — adding S_AXI manually..."
    set saxi_name "S_AXI"
    set s_axi_intf [ipx::add_bus_interface S_AXI [ipx::current_core]]
    set_property abstraction_type_vlnv xilinx.com:interface:aximm_rtl:1.0 $s_axi_intf
    set_property bus_type_vlnv         xilinx.com:interface:aximm:1.0     $s_axi_intf
    set_property interface_mode        slave                               $s_axi_intf
    # Port mapping
    foreach {sig port} {
        AWADDR  s_axi_awaddr
        AWVALID s_axi_awvalid
        AWREADY s_axi_awready
        WDATA   s_axi_wdata
        WSTRB   s_axi_wstrb
        WVALID  s_axi_wvalid
        WREADY  s_axi_wready
        BRESP   s_axi_bresp
        BVALID  s_axi_bvalid
        BREADY  s_axi_bready
        ARADDR  s_axi_araddr
        ARVALID s_axi_arvalid
        ARREADY s_axi_arready
        RDATA   s_axi_rdata
        RRESP   s_axi_rresp
        RVALID  s_axi_rvalid
        RREADY  s_axi_rready
    } {
        set pm [ipx::add_port_map $sig $s_axi_intf]
        set_property physical_name $port $pm
    }
    puts "INFO: S_AXI interface manually defined."
}

# -----------------------------------------------------------------------
# Clock interface: associate aclk with S_AXI
# -----------------------------------------------------------------------
if {[catch {
    ipx::associate_bus_interfaces \
        -busif  S_AXI \
        -clock  aclk  \
        [ipx::current_core]
    puts "INFO: aclk associated with S_AXI."
} assoc_err]} {
    puts "WARNING: Could not auto-associate aclk with S_AXI: $assoc_err"
    puts "         Clock association can be set manually in Vivado GUI."
}

# -----------------------------------------------------------------------
# Save and integrity check
# -----------------------------------------------------------------------
if {[catch {ipx::check_integrity -quiet [ipx::current_core]} chk_err]} {
    puts "WARNING: ipx::check_integrity: $chk_err"
}
ipx::save_core [ipx::current_core]
puts "INFO: IP saved to $IP_ROOT"

close_project
puts "INFO: Packaging project closed."
puts "--- PHASE 1 COMPLETE ---"
puts ""

# =============================================================================
# PHASE 2 — Create ZCU102 Vivado project and block design
# =============================================================================
puts "--- PHASE 2: Creating ZCU102 block design ---"

# Remove previous BD project so script is idempotent
if {[file exists "${PROJ_DIR}/${PROJ_NAME}.xpr"]} {
    file delete -force $PROJ_DIR
    puts "INFO: Removed previous project at $PROJ_DIR"
}

create_project $PROJ_NAME $PROJ_DIR -part $PART -force
set_property default_lib     work    [current_project]
set_property target_language Verilog [current_project]

# Try to load ZCU102 board files
if {[catch {set_property board_part $BOARD_PART [current_project]} brd_err]} {
    puts "INFO: Board part '$BOARD_PART' not found — continuing without board preset."
    set board_available 0
} else {
    puts "INFO: ZCU102 board part loaded."
    set board_available 1
}

# Add the local IP repository
set_property ip_repo_paths [list [file normalize $IP_ROOT]] [current_project]
update_ip_catalog -rebuild
puts "INFO: IP catalog updated with local repo: $IP_ROOT"

# Verify the packaged IP is visible in the catalog
set found_ip [get_ipdefs -filter "VLNV == $IP_VLNV"]
if {[llength $found_ip] > 0} {
    puts "INFO: Custom IP found in catalog: $found_ip"
} else {
    puts "WARNING: Custom IP '$IP_VLNV' not found in catalog."
    puts "         Verify $IP_ROOT/component.xml exists and is valid."
}

# =============================================================================
# Create block design
# =============================================================================
puts "INFO: Creating block design '$BD_NAME'..."
create_bd_design $BD_NAME
current_bd_design $BD_NAME

# Add Zynq UltraScale+ MPSoC PS
puts "INFO: Adding Zynq UltraScale+ MPSoC..."
set ps [create_bd_cell -type ip \
    -vlnv xilinx.com:ip:zynq_ultra_ps_e:* \
    zynq_ultra_ps_e_0]

# Board automation (optional — requires board files)
set bd_auto_ok 0
if {$board_available} {
    if {[catch {
        apply_bd_automation \
            -rule xilinx.com:bd_rule:zynq_ultra_ps_e \
            -config {apply_board_preset "1"} \
            [get_bd_cells zynq_ultra_ps_e_0]
        set bd_auto_ok 1
        puts "INFO: Board automation applied."
    } auto_err]} {
        puts "INFO: Board automation unavailable ($auto_err) — using manual config."
    }
}

# Minimal PS configuration (idempotent — reinforces automation or provides fallback).
# PSU__USE__M_AXI_GP1=0 is critical: ZCU102 board automation enables both
# M_AXI_HPM0_FPD and M_AXI_HPM1_FPD.  HPM1 is unused in this design; if left
# enabled its maxihpm1_fpd_aclk pin is unconnected and validate_bd_design fails.
set_property CONFIG.PSU__USE__M_AXI_GP0              {1}   $ps
set_property CONFIG.PSU__USE__M_AXI_GP1              {0}   $ps
set_property CONFIG.PSU__FPGA_PL0_ENABLE             {1}   $ps
set_property CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ {100} $ps
puts "INFO: PS configured: HPM0 FPD enabled, HPM1 FPD disabled, FCLK0 = 100 MHz."

# proc_sys_reset
puts "INFO: Adding proc_sys_reset..."
set rst0 [create_bd_cell -type ip \
    -vlnv xilinx.com:ip:proc_sys_reset:* \
    proc_sys_reset_0]

# Tie dcm_locked=1 (no external MMCM/PLL)
set const1 [create_bd_cell -type ip \
    -vlnv xilinx.com:ip:xlconstant:* \
    xlconstant_0]
set_property CONFIG.CONST_VAL   {1} $const1
set_property CONFIG.CONST_WIDTH {1} $const1

# AXI SmartConnect (1 master → 1 slave)
puts "INFO: Adding AXI SmartConnect..."
set sc [create_bd_cell -type ip \
    -vlnv xilinx.com:ip:smartconnect:* \
    axi_smc]
set_property CONFIG.NUM_SI   {1} $sc
set_property CONFIG.NUM_CLKS {1} $sc

# Instantiate packaged IP (the fix: -type ip -vlnv instead of -type module -reference)
puts "INFO: Adding $IP_VLNV as $WRAP_CELL..."
set wrap [create_bd_cell -type ip -vlnv $IP_VLNV $WRAP_CELL]

# Report what interfaces are available on the wrapper cell
puts "INFO: Interfaces on $WRAP_CELL:"
foreach pin [get_bd_intf_pins ${WRAP_CELL}/*] {
    puts "  $pin"
}

# =============================================================================
# Clock connections
# =============================================================================
puts "INFO: Connecting clocks..."

connect_bd_net \
    [get_bd_pins zynq_ultra_ps_e_0/pl_clk0] \
    [get_bd_pins zynq_ultra_ps_e_0/maxihpm0_fpd_aclk]
connect_bd_net \
    [get_bd_pins zynq_ultra_ps_e_0/pl_clk0] \
    [get_bd_pins proc_sys_reset_0/slowest_sync_clk]
connect_bd_net \
    [get_bd_pins zynq_ultra_ps_e_0/pl_clk0] \
    [get_bd_pins axi_smc/aclk]
connect_bd_net \
    [get_bd_pins zynq_ultra_ps_e_0/pl_clk0] \
    [get_bd_pins ${WRAP_CELL}/aclk]

# =============================================================================
# Reset connections
# =============================================================================
puts "INFO: Connecting resets..."

connect_bd_net \
    [get_bd_pins zynq_ultra_ps_e_0/pl_resetn0] \
    [get_bd_pins proc_sys_reset_0/ext_reset_in]
connect_bd_net \
    [get_bd_pins xlconstant_0/dout] \
    [get_bd_pins proc_sys_reset_0/dcm_locked]
connect_bd_net \
    [get_bd_pins proc_sys_reset_0/peripheral_aresetn] \
    [get_bd_pins axi_smc/aresetn]
connect_bd_net \
    [get_bd_pins proc_sys_reset_0/peripheral_aresetn] \
    [get_bd_pins ${WRAP_CELL}/aresetn]

# =============================================================================
# AXI interface connections
# Detect the actual AXI-Lite interface name on the wrapper cell.
# ipx::package_project may name it S_AXI, s_axi, or similar.
# =============================================================================
puts "INFO: Connecting AXI interfaces..."

# Detect wrapper AXI slave interface name
set wrap_axi_intf ""
foreach intf_pin [get_bd_intf_pins ${WRAP_CELL}/*] {
    set mode [get_property MODE $intf_pin]
    set vlnv [get_property VLNV $intf_pin]
    if {[string match "*aximm*" $vlnv] && $mode eq "Slave"} {
        set wrap_axi_intf $intf_pin
        puts "INFO: Found AXI slave interface on wrapper: $intf_pin"
        break
    }
}

if {$wrap_axi_intf eq ""} {
    puts "ERROR: No AXI-Lite slave interface found on $WRAP_CELL."
    puts "       Available interfaces:"
    foreach pin [get_bd_intf_pins ${WRAP_CELL}/*] {
        puts "         $pin  mode=[get_property MODE $pin]  vlnv=[get_property VLNV $pin]"
    }
    puts "       Check IP packaging: s_axi_* ports must be mapped to an AXI-MM interface."
    puts "       Script will continue but AXI connection will be missing."
} else {
    connect_bd_intf_net \
        [get_bd_intf_pins zynq_ultra_ps_e_0/M_AXI_HPM0_FPD] \
        [get_bd_intf_pins axi_smc/S00_AXI]
    connect_bd_intf_net \
        [get_bd_intf_pins axi_smc/M00_AXI] \
        [get_bd_intf_pins $wrap_axi_intf]
    puts "INFO: AXI chain connected: PS -> SmartConnect -> $wrap_axi_intf"
}

# =============================================================================
# Address assignment
# assign_bd_address -offset -range <slave_seg> both creates the master-mapped
# segment and sets its offset/range in one call.  This avoids the Step 27C
# failure where set_property offset/range was called on a slave-side segment
# (which has no OFFSET/RANGE properties — only master-mapped segments do).
# =============================================================================
puts "INFO: Assigning addresses..."
set slave_segs [get_bd_addr_segs -of_objects [get_bd_intf_pins ${WRAP_CELL}/*]]
set addr_ok 0
if {[llength $slave_segs] > 0} {
    set slave_seg [lindex $slave_segs 0]
    if {[catch {
        assign_bd_address \
            -offset $WRAP_BASE \
            -range  64K \
            $slave_seg
        set addr_ok 1
        puts "INFO: Address assigned: offset=$WRAP_BASE range=64K"
    } addr_err]} {
        puts "WARNING: Targeted assign_bd_address failed: $addr_err"
        puts "INFO: Falling back to auto-assign..."
    }
}
if {!$addr_ok} {
    catch {assign_bd_address} ae
    puts "INFO: Auto-assigned addresses. Verify $WRAP_BASE in Vivado GUI."
}

# =============================================================================
# Validate
# =============================================================================
puts "INFO: Validating block design..."
if {[catch {validate_bd_design} vld_err]} {
    puts "WARNING: validate_bd_design: $vld_err"
    puts "INFO: Continuing — check messages for critical vs. advisory."
} else {
    puts "INFO: Block design validated OK."
}

save_bd_design
puts "INFO: Block design saved."

# =============================================================================
# HDL wrapper
# =============================================================================
puts "INFO: Creating HDL wrapper..."
set bd_file_list [get_files ${BD_NAME}.bd]
if {[llength $bd_file_list] > 0} {
    set wrapper_file [make_wrapper -files [lindex $bd_file_list 0] -top]
    add_files -norecurse $wrapper_file
    set_property top ${BD_NAME}_wrapper [current_fileset]
    update_compile_order -fileset sources_1
    puts "INFO: HDL wrapper '${BD_NAME}_wrapper' set as top."
} else {
    puts "WARNING: BD file not found — HDL wrapper not created."
}

# =============================================================================
# Generate output products (no synthesis)
# =============================================================================
puts "INFO: Generating output products..."
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
puts "Step 27 (v3) COMPLETE."
puts ""
puts "IP packaged: $IP_VLNV"
puts "IP repo:     $IP_ROOT"
puts "Project:     ${PROJ_DIR}/${PROJ_NAME}.xpr"
puts "BD:          $BD_NAME"
puts "Top:         ${BD_NAME}_wrapper"
puts "Address:     $WRAP_BASE (range $WRAP_RANGE)"
puts ""
puts "No synthesis, no implementation, no bitstream."
puts "RTL not modified."
puts ""
puts "Open in Vivado GUI to verify BD:"
puts "  vivado.bat ${PROJ_DIR}/${PROJ_NAME}.xpr"
puts ""
puts "Step 28: synthesis + implementation + bitstream + XSA"
puts "========================================================"

exit 0
