# S2 PL BYPASS — add AXI DMA (S2MM): RFDC ADC2 → broadcaster → {adc_cap, DMA} → DDR.
# Fully manual wiring (no apply_bd_automation). DMA runs single-clock at clk_adc2
# (307.2): stream + MM + lite. HP0 reached via a dedicated SmartConnect @ clk_adc2.
# AXI-Lite control reaches the DMA through the existing ps8_0_axi_periph by adding
# one master port clocked at clk_adc2 (the interconnect inserts the pl_clk0->307.2 CDC).
# Phase 1: edit + validate ONLY (no synth).

set proj hardware/generated/09_pl_bypass/zcu216_rfdc_capture.xpr
open_project $proj
open_bd_design [get_files system.bd]

set CLK_ADC /usp_rf_data_converter_0/clk_adc2
set RST_ADC /rst_adc2/peripheral_aresetn
set CLK_PL  /zynq_ultra_ps_e_0/pl_clk0
set RST_PL  /rst_ps8_0_99M/peripheral_aresetn

# 1. AXI DMA — S2MM only, direct (no SG).
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 axi_dma_0
set_property -dict [list \
  CONFIG.c_include_sg {0} \
  CONFIG.c_sg_include_stscntrl_strm {0} \
  CONFIG.c_include_mm2s {0} \
  CONFIG.c_include_s2mm {1} \
  CONFIG.c_include_s2mm_dre {0} \
  CONFIG.c_s2mm_burst_size {16} \
  CONFIG.c_s_axis_s2mm_tdata_width {128} \
  CONFIG.c_m_axi_s2mm_data_width {128} \
  CONFIG.c_addr_width {40} \
] [get_bd_cells axi_dma_0]
# NOTE: M_AXI_S2MM HAS_BURST(=0)/MAX_BURST_LENGTH(=16) are READ-ONLY auto-derived
# and already correct here — confirmed 2026-06-22 (set_property is rejected
# "read-only"). The earlier "missing burst metadata" hypothesis is REFUTED.

# 2. ADC m20_axis -> adc_tlast_gen (TLAST @ beat 8192 = buffer boundary) -> DMA.
#    A free-running stream with no TLAST never activates the S2MM write FSM (0
#    beats). Re-added now that width=128 + psu_init AFI + single-clock are fixed,
#    so the earlier 8192-tlast "deadlock" (really the width=32 bug) should be gone.
add_files -norecurse hardware/rtl/adc_tlast_gen.v
update_compile_order -fileset sources_1
create_bd_cell -type module -reference adc_tlast_gen adc_tlast
set_property -dict [list CONFIG.DW {128} CONFIG.PKT_BEATS {8192}] [get_bd_cells adc_tlast]
delete_bd_objs [get_bd_intf_nets usp_rf_data_converter_0_m20_axis]
connect_bd_intf_net [get_bd_intf_pins usp_rf_data_converter_0/m20_axis] [get_bd_intf_pins adc_tlast/S_AXIS]
connect_bd_intf_net [get_bd_intf_pins adc_tlast/M_AXIS] [get_bd_intf_pins axi_dma_0/S_AXIS_S2MM]
connect_bd_net [get_bd_pins $CLK_ADC] [get_bd_pins adc_tlast/aclk]
connect_bd_net [get_bd_pins $RST_ADC] [get_bd_pins adc_tlast/aresetn]

# 3. Clocks/resets — DMA is async: stream/MM on clk_adc2, AXI-Lite on pl_clk0
#    (matching the PS interconnect, so no cross-clock on the control path).
# Single-clock DMA: lite + mm + stream all on clk_adc2, reset rst_adc2 (released
# only after clk_adc2 is stable) so the S2MM datapath resets in its own domain.
connect_bd_net [get_bd_pins $CLK_ADC] [get_bd_pins axi_dma_0/m_axi_s2mm_aclk]
connect_bd_net [get_bd_pins $CLK_ADC] [get_bd_pins axi_dma_0/s_axi_lite_aclk]
connect_bd_net [get_bd_pins $RST_ADC] [get_bd_pins axi_dma_0/axi_resetn]

# 4. Enable PS HP0 (S_AXI_HP0_FPD = SAXIGP2), 128-bit, clocked at clk_adc2.
set_property -dict [list CONFIG.PSU__USE__S_AXI_GP2 {1} CONFIG.PSU__SAXIGP2__DATA_WIDTH {128}] [get_bd_cells zynq_ultra_ps_e_0]
connect_bd_net [get_bd_pins $CLK_ADC] [get_bd_pins zynq_ultra_ps_e_0/saxihp0_fpd_aclk]

# 5. SmartConnect: DMA M_AXI_S2MM -> PS S_AXI_HP0_FPD (single clock clk_adc2).
create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 hp0_sc
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {1} CONFIG.NUM_CLKS {1}] [get_bd_cells hp0_sc]
connect_bd_net [get_bd_pins $CLK_ADC] [get_bd_pins hp0_sc/aclk]
connect_bd_net [get_bd_pins $RST_ADC] [get_bd_pins hp0_sc/aresetn]
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXI_S2MM] [get_bd_intf_pins hp0_sc/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins hp0_sc/M00_AXI] [get_bd_intf_pins zynq_ultra_ps_e_0/S_AXI_HP0_FPD]

# 6. AXI-Lite: add a master port on the existing ps8_0_axi_periph @ clk_adc2 (CDC inside).
set ic ps8_0_axi_periph
set n [get_property CONFIG.NUM_MI [get_bd_cells $ic]]
set_property CONFIG.NUM_MI [expr {$n + 1}] [get_bd_cells $ic]
set idx [format "M%02d" $n]
connect_bd_net [get_bd_pins $CLK_PL] [get_bd_pins $ic/${idx}_ACLK]
connect_bd_net [get_bd_pins $RST_PL] [get_bd_pins $ic/${idx}_ARESETN]
# Lite CDC: interconnect M06 (pl_clk0) -> SmartConnect (pl_clk0 in / clk_adc2 out)
# -> DMA S_AXI_LITE (clk_adc2). SmartConnect does the robust CDC (the bare
# interconnect cross-clock port read 0 earlier). DMA stays @ 0xA0090000.
create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 lite_sc
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {1} CONFIG.NUM_CLKS {2}] [get_bd_cells lite_sc]
connect_bd_net [get_bd_pins $CLK_PL]  [get_bd_pins lite_sc/aclk]
connect_bd_net [get_bd_pins $RST_PL]  [get_bd_pins lite_sc/aresetn]
connect_bd_net [get_bd_pins $CLK_ADC] [get_bd_pins lite_sc/aclk1]
connect_bd_intf_net [get_bd_intf_pins $ic/${idx}_AXI] [get_bd_intf_pins lite_sc/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins lite_sc/M00_AXI] [get_bd_intf_pins axi_dma_0/S_AXI_LITE]
puts "S2_BD: added interconnect master port $idx (was NUM_MI=$n)"

# ILA: monitor the DMA write path (M_AXI_S2MM) + the input stream, clk_adc2.
# The DMA stalls statically (DMASR=0), so a free-run capture shows the stuck
# AW/W/B levels — isolates "DMA never asserts AWVALID" vs "HP0 never AWREADY".
create_bd_cell -type ip -vlnv xilinx.com:ip:system_ila:1.1 ila0
set_property -dict [list CONFIG.C_NUM_MONITOR_SLOTS {2} CONFIG.C_DATA_DEPTH {1024} \
  CONFIG.C_SLOT_0_INTF_TYPE {xilinx.com:interface:aximm_rtl:1.0} \
  CONFIG.C_SLOT_1_INTF_TYPE {xilinx.com:interface:axis_rtl:1.0}] [get_bd_cells ila0]
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXI_S2MM] [get_bd_intf_pins ila0/SLOT_0_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/S_AXIS_S2MM] [get_bd_intf_pins ila0/SLOT_1_AXIS]
connect_bd_net [get_bd_pins $CLK_ADC] [get_bd_pins ila0/clk]
connect_bd_net [get_bd_pins $RST_ADC] [get_bd_pins ila0/resetn]

assign_bd_address
regenerate_bd_layout
save_bd_design

if {[catch {validate_bd_design} verr]} {
    puts "S2_BD: VALIDATE_ERROR: $verr"
} else {
    puts "S2_BD: VALIDATE_OK"
}
save_bd_design

puts "S2_BD: address segments —"
catch { foreach s [get_bd_addr_segs] { puts "  seg $s off [get_property OFFSET $s] range [get_property RANGE $s]" } }
puts "S2_BD: DONE"
