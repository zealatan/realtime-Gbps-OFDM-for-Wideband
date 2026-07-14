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
set proj hardware/generated/11_full_rx_loopback/zcu216_fullrx.xpr
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
# (user:user:rx_full_board_top:1.0); adding loose RTL would duplicate modules.
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
create_bd_cell -type ip -vlnv user:user:rx_full_board_top:1.0 dut_0
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
# dut_0.m_axis -> dut_capture.s_axis
connect_bd_intf_net [get_bd_intf_pins dut_0/m_axis] [get_bd_intf_pins dut_capture_0/s_axis]

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
