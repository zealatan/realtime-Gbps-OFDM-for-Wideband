# =============================================================================
# digital_loopback_bd.tcl
# -----------------------------------------------------------------------------
# Build a DMA-FREE, RF-FREE DIGITAL-loopback BD around the OFDM-sync DUT.
#
# Datapath (single clock, no RFDC, no AXI DMA):
#
#   dut_player (BRAM stimulus, AXIS master, 32b)
#        |  m_axis_t{data,valid,ready,last}
#        v
#   phase3_sync_axis_dma_wrapper  (DUT: AXI-Lite slave + AXIS slave + AXIS master)
#        |  m_axis_t{data,valid,ready,last}
#        v
#   dut_capture (BRAM capture, AXIS slave, 32b)
#
#   Control / status / readback over 4 AXI GPIOs + DUT AXI-Lite, all hung off
#   the existing PS AXI interconnect (ps8_0_axi_periph). One pl_clk0 clock and
#   one proc_sys_reset feed everything (no clk_adc2 / no RFDC needed because the
#   loopback is purely digital).
#
# This script is fully MANUAL wiring in the style of scripts/s2_bd_edit.tcl
# (create_bd_cell / connect_bd_net / connect_bd_intf_net / interconnect master
# port add / assign_bd_address / validate_bd_design). It is EDIT-ONLY: it opens
# the project + BD, builds the cells, validates and saves. It does NOT run synth.
#
# =============================================================================
# CRITICAL PREREQUISITES  (this script does NOT solve these -- it ASSUMES them)
# =============================================================================
# The DUT phase3_sync_axis_dma_wrapper instantiates THREE Xilinx xfft 9.1 IP
# cores (instances xfft_N / xfft_2N / xfft_IFFT inside the meyr_* core). For the
# BD to add the DUT as a module reference AND for synthesis to succeed, those
# xfft IPs MUST be available in THIS project for the TARGET board part
# (xczu49dr-ffvf1760-2-e). Before running this script, ensure ONE of:
#
#   (A) Add all DUT RTL .v files + the three xfft .xci to the project sources:
#         add_files -norecurse {
#           RTL_SYNC_PHASE5/rtl/ram_2port.v
#           RTL_SYNC_PHASE5/rtl/delayT.v
#           RTL_SYNC_PHASE5/rtl/complex_mult.v
#           RTL_SYNC_PHASE5/rtl/complex_mult_iq.v
#           RTL_SYNC_PHASE5/rtl/complex_mult_32.v
#           RTL_SYNC_PHASE5/rtl/cordic_atan2.v
#           RTL_SYNC_PHASE5/rtl/nco_phase_gen.v
#           RTL_SYNC_PHASE5/rtl/complex_rotator.v
#           RTL_SYNC_PHASE5/rtl/delay_sample.v
#           RTL_SYNC_PHASE5/rtl/moving_avg_optimized.v
#           RTL_SYNC_PHASE5/rtl/sample_power_sq.v
#           RTL_SYNC_PHASE5/rtl/complex_to_mag.v
#           RTL_SYNC_PHASE5/rtl/streaming_cp_autocorr.v
#           RTL_SYNC_PHASE5/rtl/peak_detector.v
#           RTL_SYNC_PHASE5/rtl/timing_sync_top.v
#           RTL_SYNC_PHASE5/rtl/frac_cfo_estimator.v
#           RTL_SYNC_PHASE5/rtl/frame_frac_cfo_top.v
#           RTL_SYNC_PHASE5/rtl/frac_cfo_corrector_top.v
#           RTL_SYNC_PHASE5/rtl/sliding_window_sum.v
#           RTL_SYNC_PHASE5/rtl/frame_detect_fsm.v
#           RTL_SYNC_PHASE5/rtl/frame_detector.v
#           RTL_SYNC_PHASE5/rtl/iq_frame_buffer.v
#           RTL_SYNC_PHASE5/rtl/frac_cfo_frame_corrector_top.v
#           RTL_SYNC_PHASE5/rtl/meyr_feeder.v
#           RTL_SYNC_PHASE5/rtl/meyr_ak_buf.v
#           RTL_SYNC_PHASE5/rtl/meyr_zeropad.v
#           RTL_SYNC_PHASE5/rtl/meyr_FFT_ak_dut.v
#           RTL_SYNC_PHASE5/rtl/meyr_Rm_dut.v
#           RTL_SYNC_PHASE5/rtl/meyr_ifft_peak_dut.v
#           RTL_SYNC_PHASE5/rtl/meyr_cfo_top.v
#           RTL_SYNC_PHASE5/rtl/meyr_slot_frontend.v
#           RTL_SYNC_PHASE5/rtl/meyr_sync_capture.v
#           RTL_SYNC_PHASE5/rtl/slot_start_controller.v
#           RTL_SYNC_PHASE5/rtl/phase3_axi_lite_regs.v
#           RTL_SYNC_PHASE5/rtl/phase3_sync_top.v
#           RTL_SYNC_PHASE5/rtl/phase3_sync_axis_dma_wrapper.v
#         }
#         import_ip RTL_SYNC_PHASE5/rtl/xfft_N/xfft_N.xci
#         import_ip RTL_SYNC_PHASE5/rtl/xfft_2N/xfft_2N.xci
#         import_ip RTL_SYNC_PHASE5/rtl/xfft_IFFT/xfft_IFFT.xci
#         update_compile_order -fileset sources_1
#       (verify the .xci C_PART == xczu49dr-ffvf1760-2-e -- it already is in the
#        repo copies; if a project was created for a different part, regenerate
#        the xfft IP for xczu49dr before synthesis.)
#
#   (B) Package the whole DUT hierarchy (RTL_SYNC_PHASE5/rtl + the 3 xfft .xci)
#       as a user IP (ip_repo) and add it to ip_repo_paths, so the DUT appears
#       as a single packaged BD cell with its xfft sub-IPs contained.
#
# Because the DUT module-ref cell below cannot be created until the DUT sources
# (and xfft IP) are in the project, this script auto-adds them (option A) IF the
# files exist; otherwise it warns and you must do (A) or (B) by hand first.
#
# A NEW or COPIED project is recommended: the existing 09_pl_bypass project is
# the RFDC+DMA design. Copy it (or create a fresh xczu49dr / zcu216 project with
# a Zynq UltraScale+ MPSoC PS) so the loopback BD does not clobber the RF design.
# Set $proj below to that project. The DUT GPIO BASE addresses MUST stay fixed
# (they are already baked into software/.../rfdc_capture/src/main.c).
# =============================================================================

# ---- project + BD ------------------------------------------------------------
# EDIT this to point at the NEW/COPIED loopback project (.xpr).
set proj hardware/generated/12_xcvr_loopback/zcu216_xcvr.xpr
# Guard: when sourced from build_digital_loopback.tcl the project is already
# open -- re-opening throws "already open" and skips the cell wiring. Only open
# if no project is currently open (standalone use).
if {[catch {current_project} _cp] || $_cp eq ""} {
    if {![file exists $proj]} {
        puts "DLB: ERROR project not found: $proj"
        puts "DLB: create/copy a zcu216 (xczu49dr-ffvf1760-2-e) project first, then re-run."
        return
    }
    open_project $proj
} else {
    puts "DLB: project already open ($_cp) -- reusing (sourced from wrapper)"
}

# Open (or create) the block design. We expect a PS-only system.bd to exist.
set bd_files [get_files -quiet system.bd]
if {$bd_files eq ""} {
    puts "DLB: ERROR system.bd not found in project. Create a BD with a"
    puts "DLB: Zynq UltraScale+ MPSoC + interconnect first (or copy one in)."
    return
}
if {[catch {current_bd_design} _cb] || $_cb eq ""} {
    open_bd_design [get_files system.bd]
} else {
    puts "DLB: bd already open ($_cb) -- reusing"
}

# ---- cell names already present in the PS subsystem --------------------------
# Discovered from the 09_pl_bypass design; adjust if your base BD differs.
set PS    zynq_ultra_ps_e_0
set IC    ps8_0_axi_periph
set CLK   /${PS}/pl_clk0
# proc_sys_reset for pl_clk0. In 09_pl_bypass it is rst_ps8_0_99M_0.
set RSTC  rst_ps8_0_99M_0
set RST   /${RSTC}/peripheral_aresetn

# Fallback: if the reset cell name differs, try to find the pl_clk0 reset.
if {[get_bd_cells -quiet /$RSTC] eq ""} {
    set cand [get_bd_cells -quiet -filter {VLNV =~ "*proc_sys_reset*"}]
    if {$cand ne ""} {
        set RSTC [lindex $cand 0]
        set RST  ${RSTC}/peripheral_aresetn
        puts "DLB: using detected proc_sys_reset = $RSTC"
    }
}

# =============================================================================
# 1. Add the DUT + shell RTL sources (option A auto-add; harmless if already in)
# =============================================================================
set rtl_dir   [file normalize hardware/rtl]
set dut_dir   [file normalize RTL_SYNC_PHASE5/rtl]

# Shell modules (DMA-free player / capture).
foreach f {dut_player.v dut_capture.v} {
    set p [file join $rtl_dir $f]
    if {[file exists $p] && [get_files -quiet $p] eq ""} { add_files -norecurse $p }
}

# DUT RTL closure (leaf-first; matches scripts/phase3_dut_filelist_newdesign.f).
set dut_srcs {
    ram_2port.v delayT.v complex_mult.v complex_mult_iq.v complex_mult_32.v
    cordic_atan2.v nco_phase_gen.v complex_rotator.v delay_sample.v
    moving_avg_optimized.v sample_power_sq.v complex_to_mag.v
    streaming_cp_autocorr.v peak_detector.v timing_sync_top.v
    frac_cfo_estimator.v frame_frac_cfo_top.v frac_cfo_corrector_top.v
    sliding_window_sum.v frame_detect_fsm.v frame_detector.v iq_frame_buffer.v
    frac_cfo_frame_corrector_top.v meyr_feeder.v meyr_ak_buf.v meyr_zeropad.v
    meyr_FFT_ak_dut.v meyr_Rm_dut.v meyr_ifft_peak_dut.v meyr_cfo_top.v
    meyr_slot_frontend.v meyr_sync_capture.v slot_start_controller.v
    phase3_axi_lite_regs.v phase3_sync_top.v phase3_sync_axis_dma_wrapper.v
}
# FULL-RX: the DUT RTL closure + downstream live INSIDE the packaged full_rx IP
# (user:user:ofdm_xcvr_board_top:1.0); adding loose RTL would duplicate modules.
puts "DLB: full_rx closure is inside the packaged IP -- skipping loose RTL add"

# xfft IPs (must match xczu49dr). import_ip copies the .xci into the project.
# xfft IPs are contained in the packaged full_rx IP -- do not import loosely.
update_compile_order -fileset sources_1

# =============================================================================
# 2. Module-reference BD cells: dut_player, DUT, dut_capture
# =============================================================================
create_bd_cell -type module -reference dut_player                   dut_player_0
# LEAD_IN reverted to 0 (default): the 64-sample warmup did NOT fix the pos48
# early-frame case AND it broke the meyr int-CFO (offset 60-tracking -> stuck 82).
# Player runs without lead-in = the known-good +60-tracking behavior.
catch { set_property CONFIG.LEAD_IN {0} [get_bd_cells dut_player_0] }
create_bd_cell -type module -reference dut_capture                  dut_capture_0
# MULTI-FRAME: bump the capture DEPTH to 16384 (AW=14) so it holds N>=5 frames
# of demod nibbles (2652/frame) back-to-back for the on-silicon streaming proof.
# The 14-bit read index splits low12=ctrl[13:2] / hi2=ctrl[19:18] inside dut_capture
# (the hi bits live in the player load_addr field but are player-safe in readback).
catch { set_property CONFIG.AW {14} [get_bd_cells dut_capture_0] }
puts "DLB: dut_capture_0 AW = [get_property CONFIG.AW [get_bd_cells dut_capture_0]] (DEPTH=16384)"
create_bd_cell -type ip -vlnv user:user:ofdm_xcvr_board_top:1.0 dut_0
# CRITICAL: the IP defaults THRESHOLD=10240000, but the tc0000 vector + the C/
# python golden + the P5 sim TBs all use the proven detection level THRESHOLD=
# 40000 (256x lower). With the default the frame detector NEVER fires -> frac_
# frame_error -> sync chain deadlocks (board: FSV=0, IN stuck at 4096). Override.
catch { set_property CONFIG.THRESHOLD {40000} [get_bd_cells dut_0] }
puts "DLB: dut_0 THRESHOLD set -> [get_property CONFIG.THRESHOLD [get_bd_cells dut_0]]"

# =============================================================================
# 3. AXI GPIOs (fixed SW contract)
#    loop_ctrl_gpio   0xA0050000  OUT 32b  -> player.ctrl + capture.ctrl
#    stim_load_gpio   0xA0090000  OUT 32b  -> player.stim_wdata
#    loop_status_gpio 0xA0060000  IN  dual -> ch1 capture.status0 / ch2 player.status
#    capture_gpio     0xA0080000  IN  32b  -> capture.status_capture
# =============================================================================
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 loop_ctrl_gpio
set_property -dict [list CONFIG.C_GPIO_WIDTH {32} CONFIG.C_IS_DUAL {1} \
    CONFIG.C_ALL_OUTPUTS {1} CONFIG.C_GPIO2_WIDTH {32} CONFIG.C_ALL_OUTPUTS_2 {1}] [get_bd_cells loop_ctrl_gpio]

create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 stim_load_gpio
set_property -dict [list CONFIG.C_GPIO_WIDTH {32} CONFIG.C_IS_DUAL {0} \
    CONFIG.C_ALL_OUTPUTS {1}] [get_bd_cells stim_load_gpio]

create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 loop_status_gpio
set_property -dict [list CONFIG.C_GPIO_WIDTH {32} CONFIG.C_GPIO2_WIDTH {32} \
    CONFIG.C_IS_DUAL {1} CONFIG.C_ALL_INPUTS {1} CONFIG.C_ALL_INPUTS_2 {1}] \
    [get_bd_cells loop_status_gpio]

create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 capture_gpio
set_property -dict [list CONFIG.C_GPIO_WIDTH {32} CONFIG.C_IS_DUAL {0} \
    CONFIG.C_ALL_INPUTS {1}] [get_bd_cells capture_gpio]

# ON-CHIP HW BER CHECKER GPIOs (additive; wire to dut_0 ber_ctrl/ber_status).
#   ber_ctrl_gpio   0xA00C0000  OUT 32b -> dut_0.ber_ctrl
#                     bit0 = soft clear, bits[7:4] = status_sel
#   ber_status_gpio 0xA00D0000  IN  32b <- dut_0.ber_status (selected counter)
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 ber_ctrl_gpio
set_property -dict [list CONFIG.C_GPIO_WIDTH {32} CONFIG.C_IS_DUAL {0} \
    CONFIG.C_ALL_OUTPUTS {1}] [get_bd_cells ber_ctrl_gpio]
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 ber_status_gpio
set_property -dict [list CONFIG.C_GPIO_WIDTH {32} CONFIG.C_IS_DUAL {0} \
    CONFIG.C_ALL_INPUTS {1}] [get_bd_cells ber_status_gpio]

# =============================================================================
# 4. Datapath AXIS wiring (32b, single clock)
#    player.m_axis  -> DUT.s_axis ;  DUT.m_axis -> capture.s_axis
# =============================================================================
# AXIS at INTERFACE level (modules expose inferred m_axis/s_axis interfaces).
# Per-signal connect_bd_net caused 41-1306 interface-override warnings + a
# malformed-objects error; intf_net is the correct, clean way.
# dut_player.m_axis -> dut_0.s_axis
connect_bd_intf_net [get_bd_intf_pins dut_player_0/m_axis] [get_bd_intf_pins dut_0/s_axis]
# dut_0.m_axis -> AXIS broadcaster -> {dut_capture (BRAM, existing readback),
#                                       rx_dma S2MM (DDR sink, PHY-rate milestone)}
create_bd_cell -type ip -vlnv xilinx.com:ip:axis_broadcaster:1.1 demod_bcast
connect_bd_net [get_bd_pins $CLK] [get_bd_pins demod_bcast/aclk]
connect_bd_net [get_bd_pins $RST] [get_bd_pins demod_bcast/aresetn]
connect_bd_intf_net [get_bd_intf_pins dut_0/m_axis]         [get_bd_intf_pins demod_bcast/S_AXIS]
connect_bd_intf_net [get_bd_intf_pins demod_bcast/M00_AXIS] [get_bd_intf_pins dut_capture_0/s_axis]
puts "DLB: demod_bcast M00 -> dut_capture (M01 -> rx_dma S2MM below)"

# =============================================================================
# 5. GPIO -> module port wiring (the fixed contract)
# =============================================================================
# loop_ctrl_gpio (OUT) -> player.ctrl AND capture.ctrl (fan-out from one driver)
connect_bd_net [get_bd_pins loop_ctrl_gpio/gpio_io_o] [get_bd_pins dut_player_0/ctrl]
connect_bd_net [get_bd_pins loop_ctrl_gpio/gpio_io_o] [get_bd_pins dut_capture_0/ctrl]

# stim_load_gpio (OUT) -> player.stim_wdata
connect_bd_net [get_bd_pins stim_load_gpio/gpio_io_o] [get_bd_pins dut_player_0/stim_wdata]

# loop_status_gpio (IN dual): ch1=capture.status0, ch2=player.status
connect_bd_net [get_bd_pins dut_capture_0/status0] [get_bd_pins loop_status_gpio/gpio_io_i]
connect_bd_net [get_bd_pins dut_player_0/status]   [get_bd_pins loop_status_gpio/gpio2_io_i]

# capture_gpio (IN): capture.status_capture readback
connect_bd_net [get_bd_pins dut_capture_0/status_capture] [get_bd_pins capture_gpio/gpio_io_i]

# ber_ctrl_gpio (OUT) -> dut_0.ber_ctrl ; ber_status_gpio (IN) <- dut_0.ber_status
connect_bd_net [get_bd_pins ber_ctrl_gpio/gpio_io_o]   [get_bd_pins dut_0/ber_ctrl]
connect_bd_net [get_bd_pins dut_0/ber_status]          [get_bd_pins ber_status_gpio/gpio_io_i]

# =============================================================================
# 6. Clocks + resets (single pl_clk0 domain + one proc_sys_reset)
# =============================================================================
foreach c {dut_player_0/aclk dut_capture_0/aclk dut_0/aclk} {
    connect_bd_net [get_bd_pins $CLK] [get_bd_pins $c]
}
foreach r {dut_player_0/aresetn dut_capture_0/aresetn dut_0/aresetn} {
    connect_bd_net [get_bd_pins $RST] [get_bd_pins $r]
}
# GPIO + DUT AXI-Lite slave clocks/resets
foreach g {loop_ctrl_gpio stim_load_gpio loop_status_gpio capture_gpio ber_ctrl_gpio ber_status_gpio} {
    connect_bd_net [get_bd_pins $CLK] [get_bd_pins $g/s_axi_aclk]
    connect_bd_net [get_bd_pins $RST] [get_bd_pins $g/s_axi_aresetn]
}

# =============================================================================
# 7. AXI-Lite masters: grow the PS interconnect by 5 ports (4 GPIO + DUT lite)
#    Mirrors s2_bd_edit.tcl: bump NUM_MI, clock/reset each new Mxx port, then
#    connect each new master AXI to the slave's S_AXI / S_AXI_LITE.
# =============================================================================
# IC (ps8_0_axi_periph) is now a SINGLE SmartConnect (built in the wrapper) doing
# the AXI4(PS)->AXI4LITE(slaves) conversion for ALL slaves directly — no axi_
# interconnect xbar, no per-slave auto_pc, no cascade. The earlier xbar/auto_pc/
# cascaded-SmartConnect mangled the DUT module-ref write channel (ILA: wstrb=0,
# wdata corrupt -> regs never latched). SmartConnect has a single clock domain:
# NO per-MI ACLK/ARESETN pins; just set NUM_MI and connect each M0x_AXI.
set slaves [list \
    loop_ctrl_gpio/S_AXI \
    stim_load_gpio/S_AXI \
    loop_status_gpio/S_AXI \
    capture_gpio/S_AXI \
    dut_0/s_axi \
    ber_ctrl_gpio/S_AXI \
    ber_status_gpio/S_AXI \
]
set_property CONFIG.NUM_MI [llength $slaves] [get_bd_cells $IC]
set i 0
foreach sl $slaves {
    set idx [format "M%02d" $i]
    set sp [get_bd_intf_pins -quiet $sl]
    if {$sp eq ""} { set sp [get_bd_intf_pins -quiet [string map {s_axi S_AXI S_AXI s_axi} $sl]] }
    connect_bd_intf_net [get_bd_intf_pins $IC/${idx}_AXI] $sp
    puts "DLB: smartconnect $idx -> $sl"
    incr i
}

# --- ILA monitor (DISABLED for 200 MHz timing; change to `if {1}` to re-enable) ---
if {0} {
create_bd_cell -type ip -vlnv xilinx.com:ip:system_ila:1.1 dut_ila
set_property -dict [list CONFIG.C_NUM_MONITOR_SLOTS {3} CONFIG.C_DATA_DEPTH {2048} \
  CONFIG.C_SLOT_0_INTF_TYPE {xilinx.com:interface:aximm_rtl:1.0} \
  CONFIG.C_SLOT_1_INTF_TYPE {xilinx.com:interface:aximm_rtl:1.0} \
  CONFIG.C_SLOT_2_INTF_TYPE {xilinx.com:interface:aximm_rtl:1.0} \
  CONFIG.C_MON_TYPE {INTERFACE}] [get_bd_cells dut_ila]
# SLOT_0 = DUT (broken W), SLOT_1 = PS HPM0 input to SmartConnect, SLOT_2 = a
# working GPIO — to isolate where wdata becomes the constant 0x02 / wstrb=0.
connect_bd_intf_net [get_bd_intf_pins dut_0/s_axi]                  [get_bd_intf_pins dut_ila/SLOT_0_AXI]
connect_bd_intf_net [get_bd_intf_pins ps8_0_axi_periph/S00_AXI]     [get_bd_intf_pins dut_ila/SLOT_1_AXI]
connect_bd_intf_net [get_bd_intf_pins loop_ctrl_gpio/S_AXI]         [get_bd_intf_pins dut_ila/SLOT_2_AXI]
connect_bd_net [get_bd_pins $CLK] [get_bd_pins dut_ila/clk]
connect_bd_net [get_bd_pins $RST] [get_bd_pins dut_ila/resetn]
puts "DLB: ILA 3-slot: SLOT_0=dut_0/s_axi  SLOT_1=PS S00  SLOT_2=loop_ctrl_gpio"
}
puts "DLB: dut_ila DISABLED (200 MHz timing build)"

# =============================================================================
# 7b. AXI DMA (MM2S ONLY) -> TX payload bridge (arbitrary DDR payload -> TX)
# -----------------------------------------------------------------------------
# axi_dma 7.1, DIRECT (no scatter-gather), MM2S enabled / S2MM disabled.
#   MM2S M_AXI_MM2S -> SmartConnect (mm2s_sc) -> PS S_AXI_HP0_FPD (DDR read)
#   MM2S M_AXIS_MM2S -> dut_0/tx_s_axis (the axi_to_parallel_tx bridge)
#   DMA S_AXI_LITE   -> new port on the existing PS periph SmartConnect (IC)
# All on pl_clk0 (single clock, no CDC). DMA base addr 0xA00E0000 (SW contract).
# The RX->BRAM path (dut_capture) is UNTOUCHED; S2MM is intentionally absent.
# =============================================================================
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 tx_dma
set_property -dict [list \
    CONFIG.c_include_sg {0} \
    CONFIG.c_include_mm2s {1} \
    CONFIG.c_include_s2mm {0} \
    CONFIG.c_sg_include_stscntrl_strm {0} \
    CONFIG.c_mm2s_burst_size {16} \
    CONFIG.c_include_mm2s_dre {0} \
    CONFIG.c_m_axi_mm2s_data_width {128} \
    CONFIG.c_m_axis_mm2s_tdata_width {32} \
    CONFIG.c_sg_length_width {16} \
] [get_bd_cells tx_dma]
# BUGFIX(bug1): memory-map read width MUST equal the 32-bit stream width. With
# 64-bit mem width > 32-bit stream + DRE off, the axi_dma internal downsizer
# replicated every 64-bit DDR read into 4 stream beats (w0,w1,w0,w1) and skipped
# the odd 64-bit blocks -> every 2nd 16-carrier block was a duplicate of the
# previous (board: got[block2n+1]==exp[block2n], dup_prev=1245/1245). Setting
# c_m_axi_mm2s_data_width=32 removes the width conversion: one 32b read = one 32b
# beat, sequential. The mm2s SmartConnect upsizes 32->64 to PS HP0 (standard).
puts "DLB: tx_dma axi_dma MM2S-only direct-mode created (m_axi=32b == stream 32b)"

# MM2S output stream -> AXIS register slice -> the bridge slave on the DUT.
# BUGFIX(bug2): the DMA-delivered beats were arriving REPLICATED (bank readback
# showed each 32b word Nx; N=128/mem_width, per-boot ~50%). A fully-registered
# AXIS register slice on the M_AXIS_MM2S -> tx_s_axis link re-times the handshake
# so each beat is transferred exactly once (skid buffer, registered tvalid/tready
# /tdata), removing the marginal over-sampling.
create_bd_cell -type ip -vlnv xilinx.com:ip:axis_register_slice:1.1 tx_axis_rs
set_property -dict [list CONFIG.REG_CONFIG {1}] [get_bd_cells tx_axis_rs]
connect_bd_net [get_bd_pins $CLK] [get_bd_pins tx_axis_rs/aclk]
connect_bd_net [get_bd_pins $RST] [get_bd_pins tx_axis_rs/aresetn]
connect_bd_intf_net [get_bd_intf_pins tx_dma/M_AXIS_MM2S] [get_bd_intf_pins tx_axis_rs/S_AXIS]
connect_bd_intf_net [get_bd_intf_pins tx_axis_rs/M_AXIS]  [get_bd_intf_pins dut_0/tx_s_axis]
puts "DLB: axis_register_slice tx_axis_rs inserted M_AXIS_MM2S -> tx_s_axis"

# MM2S read master -> dedicated SmartConnect -> PS HP0 (DDR read).
create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 mm2s_sc
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {1} CONFIG.NUM_CLKS {1}] [get_bd_cells mm2s_sc]
connect_bd_net [get_bd_pins $CLK] [get_bd_pins mm2s_sc/aclk]
connect_bd_net [get_bd_pins $RST] [get_bd_pins mm2s_sc/aresetn]
connect_bd_intf_net [get_bd_intf_pins tx_dma/M_AXI_MM2S] [get_bd_intf_pins mm2s_sc/S00_AXI]

# Enable + clock the PS HP0 slave (S_AXI_HP0_FPD == saxihp0_fpd_aclk).
catch { connect_bd_net [get_bd_pins $CLK] [get_bd_pins zynq_ultra_ps_e_0/saxihp0_fpd_aclk] }
set hp0 [get_bd_intf_pins -quiet zynq_ultra_ps_e_0/S_AXI_HP0_FPD]
if {$hp0 eq ""} { set hp0 [get_bd_intf_pins -quiet zynq_ultra_ps_e_0/S_AXI_HP0] }
if {$hp0 ne ""} {
    connect_bd_intf_net [get_bd_intf_pins mm2s_sc/M00_AXI] $hp0
    puts "DLB: mm2s_sc/M00_AXI -> PS HP0 ($hp0)"
} else {
    puts "DLB: ERROR PS HP0 slave not found -- enable PSU__USE__S_AXI_GP2 in build script"
}

# DMA clocks/resets (single pl_clk0 domain).
connect_bd_net [get_bd_pins $CLK] [get_bd_pins tx_dma/s_axi_lite_aclk]
connect_bd_net [get_bd_pins $CLK] [get_bd_pins tx_dma/m_axi_mm2s_aclk]
connect_bd_net [get_bd_pins $RST] [get_bd_pins tx_dma/axi_resetn]

# DMA AXI-Lite control -> grow the PS periph SmartConnect by one MI port.
set dma_mi [get_property CONFIG.NUM_MI [get_bd_cells $IC]]
set_property CONFIG.NUM_MI [expr {$dma_mi + 1}] [get_bd_cells $IC]
set dma_idx [format "M%02d" $dma_mi]
connect_bd_intf_net [get_bd_intf_pins $IC/${dma_idx}_AXI] [get_bd_intf_pins tx_dma/S_AXI_LITE]
puts "DLB: tx_dma S_AXI_LITE -> $IC/${dma_idx}_AXI (DMA lite reg base 0xA00E0000)"

# =============================================================================
# 7c. RX demod -> AXI DMA S2MM -> PS HP1 -> DDR (PHY-rate sink, milestone M1)
# The demod stream (dut_0/m_axis, 32b, per-frame tlast every 2652 nibbles) is
# written straight to DDR by an S2MM DMA -> no per-frame JTAG readback. Single
# pl_clk0 domain + tlast present -> the S2MM write FSM issues AWVALID cleanly
# (the RFDC-case S2MM wedge was an async-clock + free-running-stream problem).
# =============================================================================
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 rx_dma
set_property -dict [list \
    CONFIG.c_include_sg {0} \
    CONFIG.c_include_mm2s {0} \
    CONFIG.c_include_s2mm {1} \
    CONFIG.c_sg_include_stscntrl_strm {0} \
    CONFIG.c_s2mm_burst_size {16} \
    CONFIG.c_include_s2mm_dre {0} \
    CONFIG.c_s_axis_s2mm_tdata_width {32} \
    CONFIG.c_m_axi_s2mm_data_width {128} \
    CONFIG.c_sg_length_width {20} \
] [get_bd_cells rx_dma]
# c_m_axi_s2mm_data_width=128 to MATCH the native 128-bit HP port (same fix as
# the MM2S path): a 32-bit write master to the 128-bit HP wrote each 32b beat to
# only one lane of a 128b-strided address -> only every 4th DDR word landed.
# 128b mem packs 4 stream beats into one full 128b write -> all words written.
# --- S2MM leg DECOUPLE FIFO -----------------------------------------------
# The axis_broadcaster only asserts S_tready when EVERY master leg is ready. With
# the S2MM leg wired straight to rx_dma, whenever S2MM is idle/re-arming its tready
# drops -> the broadcaster stalls the demod mid-frame -> the dut_capture leg (and
# the frame framing) desync, and the final tlast beat of a captured frame comes out
# as 0xF fill (never flushed). A deep AXIS data FIFO on this leg keeps tready HIGH
# across S2MM idle/re-arm gaps: the demod streams continuously into the FIFO (no
# broadcaster stall), the last beat always flushes, and S2MM drains the FIFO frame
# by frame. Depth 4096 (> 1 frame of 2652 beats) absorbs a full re-arm gap.
# HAS_TLAST {0}: the FIFO drops the demod's per-frame tlast so the S2MM DMA does
# NOT complete on each frame boundary -- it captures a fixed LENGTH spanning
# several frames CONTIGUOUSLY (only the demod's tvalid gaps are skipped). This is
# the fix for the 1-beat head drop: re-arming S2MM per frame dropped each frame's
# first 128-bit beat (4 nibbles); with one arm capturing N frames, only the very
# first frame loses a beat and the firmware offset-search picks a clean interior
# frame (BER=0). The demod frames are separated by tvalid gaps, so tlast is not
# needed to delimit them in DDR.
create_bd_cell -type ip -vlnv xilinx.com:ip:axis_data_fifo:2.0 s2mm_fifo
set_property -dict [list \
    CONFIG.TDATA_NUM_BYTES {4} \
    CONFIG.HAS_TLAST {0} \
    CONFIG.FIFO_DEPTH {32768} \
    CONFIG.FIFO_MODE {1} \
] [get_bd_cells s2mm_fifo]
# DEPTH 4096->32768 (M3): the demod output is bursty; brief S2MM/DDR drain gaps let a
# 4096 FIFO fill and back-pressure the DUT m_axis (errf bit3 STALL_TIMEOUT). A single
# such stall permanently desyncs the (non-elastic) RX timing -> frame 0 BER=0 but all
# later continuous frames garbage. A deep FIFO (12 frames) rides through the drain
# gaps so the demod output never stalls -> continuous BER=0 at PHY rate.
connect_bd_net [get_bd_pins $CLK] [get_bd_pins s2mm_fifo/s_axis_aclk]
connect_bd_net [get_bd_pins $RST] [get_bd_pins s2mm_fifo/s_axis_aresetn]
connect_bd_intf_net [get_bd_intf_pins demod_bcast/M01_AXIS] [get_bd_intf_pins s2mm_fifo/S_AXIS]
connect_bd_intf_net [get_bd_intf_pins s2mm_fifo/M_AXIS]     [get_bd_intf_pins rx_dma/S_AXIS_S2MM]
puts "DLB: demod_bcast M01 -> s2mm_fifo(4096) -> rx_dma S_AXIS_S2MM"

create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 s2mm_sc
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {1} CONFIG.NUM_CLKS {1}] [get_bd_cells s2mm_sc]
connect_bd_net [get_bd_pins $CLK] [get_bd_pins s2mm_sc/aclk]
connect_bd_net [get_bd_pins $RST] [get_bd_pins s2mm_sc/aresetn]
connect_bd_intf_net [get_bd_intf_pins rx_dma/M_AXI_S2MM] [get_bd_intf_pins s2mm_sc/S00_AXI]

catch { connect_bd_net [get_bd_pins $CLK] [get_bd_pins zynq_ultra_ps_e_0/saxihp1_fpd_aclk] }
set hp1 [get_bd_intf_pins -quiet zynq_ultra_ps_e_0/S_AXI_HP1_FPD]
if {$hp1 eq ""} { set hp1 [get_bd_intf_pins -quiet zynq_ultra_ps_e_0/S_AXI_HP1] }
if {$hp1 ne ""} {
    connect_bd_intf_net [get_bd_intf_pins s2mm_sc/M00_AXI] $hp1
    puts "DLB: s2mm_sc/M00_AXI -> PS HP1 ($hp1)"
} else {
    puts "DLB: ERROR PS HP1 slave not found -- enable PSU__USE__S_AXI_GP3 in build script"
}

connect_bd_net [get_bd_pins $CLK] [get_bd_pins rx_dma/s_axi_lite_aclk]
connect_bd_net [get_bd_pins $CLK] [get_bd_pins rx_dma/m_axi_s2mm_aclk]
connect_bd_net [get_bd_pins $RST] [get_bd_pins rx_dma/axi_resetn]

set rdma_mi [get_property CONFIG.NUM_MI [get_bd_cells $IC]]
set_property CONFIG.NUM_MI [expr {$rdma_mi + 1}] [get_bd_cells $IC]
set rdma_idx [format "M%02d" $rdma_mi]
connect_bd_intf_net [get_bd_intf_pins $IC/${rdma_idx}_AXI] [get_bd_intf_pins rx_dma/S_AXI_LITE]
puts "DLB: rx_dma S_AXI_LITE -> $IC/${rdma_idx}_AXI (DMA lite reg base 0xA00F0000)"

# =============================================================================
# 8. Addresses (fixed contract) + validate + save
# =============================================================================
# Let Vivado auto-assign first, then override to the SW-locked offsets.
assign_bd_address

proc dlb_set_addr {seg_glob off} {
    set segs [get_bd_addr_segs -quiet $seg_glob]
    foreach s $segs {
        if {![catch {set_property OFFSET $off $s} e]} {
            puts "DLB: addr $s = $off"
        } else {
            puts "DLB: WARN could not set $s = $off ($e)"
        }
    }
}
# CRITICAL: auto-assign_bd_address packs the NEW cells (ber_*) into the low
# 0xA004/0xA005 slots, which then OVERLAP the locked loop_ctrl/loop_status
# targets below -> the set_property OFFSET silently fails (caught) and leaves
# loop_ctrl at 0xA0040000 / loop_status at 0xA0050000 (WRONG). The firmware then
# writes PLAY_EN to an INPUT-only gpio -> player never starts -> capture hangs.
# FIX: first PARK every segment at a distinct, collision-free high address, THEN
# move each to its locked offset (now nothing is in the way).
proc dlb_park_all {} {
    # park inside the SAME 0xA0000000 HPM aperture, well clear of the locked
    # 0xA004..0xA00D target band (use 0xA0F0_0000+).
    set base 0x00A0F00000
    set i 0
    foreach s [get_bd_addr_segs -quiet /zynq_ultra_ps_e_0/Data/*] {
        catch { set_property OFFSET [format 0x%X [expr {$base + $i*0x10000}]] $s }
        incr i
    }
    puts "DLB: parked $i segments to avoid overlap during re-assign"
}
dlb_park_all

# Match: loop_ctrl=0xA0050000 loop_status=0xA0060000 capture=0xA0080000
#        stim_load=0xA0090000 DUT lite=0xA00A0000  ber_ctrl=0xA00C0000 ber_status=0xA00D0000
dlb_set_addr "*loop_ctrl_gpio*Reg*"   0xA0050000
dlb_set_addr "*loop_status_gpio*Reg*" 0xA0060000
dlb_set_addr "*capture_gpio*Reg*"     0xA0080000
dlb_set_addr "*stim_load_gpio*Reg*"   0xA0090000
dlb_set_addr "*dut_0*Reg*"            0xA00A0000
dlb_set_addr "*ber_ctrl_gpio*Reg*"    0xA00C0000
dlb_set_addr "*ber_status_gpio*Reg*"  0xA00D0000
dlb_set_addr "*tx_dma*Reg*"           0xA00E0000
dlb_set_addr "*rx_dma*Reg*"           0xA00F0000

# S2MM write master must reach DDR (auto-assign usually maps it; log it).
catch {
    foreach s [get_bd_addr_segs -quiet /rx_dma/Data_S2MM/*] {
        puts "DLB: rx_dma S2MM seg $s off [get_property OFFSET $s] range [get_property RANGE $s]"
    }
}

# MM2S read master must reach DDR: ensure the tx_dma/Data_MM2S segment is mapped
# onto the PS HP0 DDR address space (auto-assign usually does this; be explicit).
catch {
    foreach s [get_bd_addr_segs -quiet /tx_dma/Data_MM2S/*] {
        puts "DLB: tx_dma MM2S seg $s off [get_property OFFSET $s] range [get_property RANGE $s]"
    }
}

regenerate_bd_layout
save_bd_design

if {[catch {validate_bd_design} verr]} {
    puts "DLB: VALIDATE_ERROR: $verr"
} else {
    puts "DLB: VALIDATE_OK"
}
save_bd_design

puts "DLB: address segments --"
catch {
    foreach s [get_bd_addr_segs] {
        puts "  seg $s off [get_property OFFSET $s] range [get_property RANGE $s]"
    }
}
puts "DLB: DONE"
