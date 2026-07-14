# =============================================================================
# build_digital_loopback.tcl
# -----------------------------------------------------------------------------
# Vivado BATCH builder for the 10_digital_loopback project: a DMA-FREE, RF-FREE
# digital-loopback bitstream around the OFDM-sync DUT.
#
#   dut_player (BRAM stim, AXIS master) -> phase3_sync_axis_dma_wrapper (DUT)
#       -> dut_capture (BRAM capture, AXIS slave), all driven from PS pl_clk0,
#       control/status over 4 AXI GPIOs + the DUT AXI-Lite slave, hung off the
#       PS interconnect (ps8_0_axi_periph).
#
# This script CREATES the project + PS BD base, adds all sources, sources the
# manual-wiring BD editor (scripts/digital_loopback_bd.tcl), wraps the BD, and
# (optionally) runs synth/impl/bitstream/XSA.
#
# STAGED:
#   STAGE=validate  (default): create project + add sources + build PS BD +
#                   source digital_loopback_bd.tcl (cells/wiring/addr) +
#                   validate_bd_design + save, then STOP.  No synth (fast).
#   STAGE=build   : everything in validate, then generate_target + synth_1 +
#                   impl_1 (write_bitstream) + write_hw_platform (XSA).
#
# RUN:
#   vivado -mode batch -source scripts/build_digital_loopback.tcl -tclargs validate
#   vivado -mode batch -source scripts/build_digital_loopback.tcl -tclargs build
#
# Markers printed (grep these):
#   DLB_BUILD: VALIDATE_OK | BUILD_OK | BUILD_FAILED | DONE
#   DLB_BUILD: <stage> ERROR: <msg>   (a caught failure surfaces the exact step)
# =============================================================================

# ---- 0. stage selection ------------------------------------------------------
set STAGE [expr {[llength $argv] > 0 ? [lindex $argv 0] : ""}]
if {$STAGE eq ""} {
    if {[info exists ::env(STAGE)]} { set STAGE $::env(STAGE) } else { set STAGE validate }
}
set STAGE [string tolower [string trim $STAGE]]
if {$STAGE ne "validate" && $STAGE ne "build"} {
    puts "DLB_BUILD: unknown STAGE '$STAGE' -- defaulting to validate"
    set STAGE validate
}
puts "DLB_BUILD: STAGE = $STAGE"

# ---- paths (all relative to the repo root = Vivado launch dir) ---------------
set REPO       [pwd]
set PROJ_DIR   hardware/generated/10_digital_loopback
set PROJ_NAME  zcu216_loopback
set PROJ_XPR   ${PROJ_DIR}/${PROJ_NAME}.xpr
set PART       xczu49dr-ffvf1760-2-e
set BOARD_PART xilinx.com:zcu216:part0:2.0
set RTL_DIR    [file normalize hardware/rtl]
set DUT_DIR    [file normalize RTL_SYNC_PHASE5/rtl]
set STIM_MEM   stim_fc_kp0.mem
set BD_EDIT    scripts/digital_loopback_bd.tcl
set XSA_OUT    ${PROJ_DIR}/${PROJ_NAME}.xsa

# ---- helper: run a step in a catch, print a clear marker on failure ----------
proc dlb_step {label body} {
    if {[catch {uplevel 1 $body} msg]} {
        puts "DLB_BUILD: $label ERROR: $msg"
        return 0
    }
    return 1
}

# =============================================================================
# 1. Create project (part + best-effort board)
# =============================================================================
dlb_step "create_project" {
    create_project $PROJ_NAME $PROJ_DIR -part $PART -force
}
# Best-effort board_part: only if the board files are installed in this Vivado.
if {[catch {
    set avail [get_board_parts -quiet $BOARD_PART]
    if {$avail ne ""} {
        set_property board_part $BOARD_PART [current_project]
        puts "DLB_BUILD: board_part = $BOARD_PART"
    } else {
        puts "DLB_BUILD: WARN board_part '$BOARD_PART' not installed -- part-only flow"
    }
} bmsg]} {
    puts "DLB_BUILD: WARN board_part lookup failed ($bmsg) -- part-only flow"
}

# 1b. Register the packaged DUT IP (formal AXI4-Lite slave — fixes the module_ref
#     wstrb=0 SmartConnect write-mangle). Built by scripts/package_dut_ip.tcl.
dlb_step "add_dut_ip_repo" {
    set repo [file normalize hardware/ip_repo/dut_sync]
    if {[file exists [file join $repo component.xml]]} {
        set_property ip_repo_paths $repo [current_project]
        update_ip_catalog -rebuild
        puts "DLB_BUILD: DUT IP repo added: $repo"
    } else {
        puts "DLB_BUILD: ERROR DUT IP repo missing ($repo) -- run scripts/package_dut_ip.tcl first"
    }
}

# =============================================================================
# 2. Add sources: shell RTL, DUT closure (leaf-first), xfft IPs, stim mem
# =============================================================================
# 2a. shell RTL (DMA-free player / capture)
dlb_step "add_shell_rtl" {
    foreach f {dut_player.v dut_capture.v} {
        set p [file join $RTL_DIR $f]
        if {[file exists $p]} {
            if {[get_files -quiet $p] eq ""} { add_files -norecurse $p }
        } else {
            puts "DLB_BUILD: WARN shell RTL missing: $p"
        }
    }
}

# 2b. DUT RTL closure. Prefer the leaf-first list in
#     scripts/phase3_dut_filelist_newdesign.f (paths begin with rtl/, relative
#     to RTL_SYNC_PHASE5/). Skip xfft .xci (added separately) and any path that
#     would dip into a stale rtl/DUT/ subtree. Fall back to add_files on the dir.
# 2b-2c. DUT RTL closure + the 3 xfft IPs are now INSIDE the packaged DUT IP
#        (user:user:phase3_sync_axis_dma_wrapper:1.0, built by package_dut_ip.tcl
#        + registered in step 1b). Adding them again as loose project sources
#        would duplicate the module definitions and break synthesis, so SKIP.
puts "DLB_BUILD: DUT closure + xfft live inside the packaged DUT IP -- skipping loose RTL/xfft add"

# 2d. stim memory init file for the player's $readmemh INIT_FILE bake.
#     Add it as a Memory-Init source and mark it used-in synthesis so the .mem
#     ends up on the synthesis path where $readmemh can find it by bare name.
dlb_step "add_stim_mem" {
    set p [file join $RTL_DIR $STIM_MEM]
    if {[file exists $p]} {
        if {[get_files -quiet $p] eq ""} { add_files -norecurse $p }
        catch { set_property file_type {Memory Initialization Files} [get_files $p] }
        catch { set_property used_in_simulation true  [get_files $p] }
        catch { set_property used_in_synthesis  true  [get_files $p] }
        puts "DLB_BUILD: stim mem added: $p"
    } else {
        puts "DLB_BUILD: WARN stim mem missing: $p (player INIT_FILE will be empty)"
    }
}

update_compile_order -fileset sources_1

# =============================================================================
# 3. PS BD base for ZCU216 (mirror 08/09 cell names that the BD editor expects:
#    zynq_ultra_ps_e_0, ps8_0_axi_periph, rst_ps8_0_99M_0, pl_clk0)
# =============================================================================
dlb_step "create_ps_bd" {
    create_bd_design system

    # 3a. PS cell + ZCU216 board/preset automation.
    create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:3.3 zynq_ultra_ps_e_0
    if {[catch {
        apply_bd_automation -rule xilinx.com:bd_rule:zynq_ultra_ps_e \
            -config {apply_board_preset "1"} [get_bd_cells zynq_ultra_ps_e_0]
    } amsg]} {
        puts "DLB_BUILD: WARN PS board automation failed ($amsg) -- applying minimal config"
    }

    # 3b. Force the minimal config the loopback needs, regardless of preset:
    #     - M_AXI_HPM0_FPD enabled (AXI-Lite master to GPIOs + DUT)
    #     - pl_clk0 = 100 MHz, one PL fabric reset
    set_property -dict [list \
        CONFIG.PSU__USE__M_AXI_GP0 {1} \
        CONFIG.PSU__USE__M_AXI_GP1 {0} \
        CONFIG.PSU__MAXIGP0__DATA_WIDTH {32} \
        CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ {200} \
        CONFIG.PSU__FPGA_PL0_ENABLE {1} \
        CONFIG.PSU__NUM_FABRIC_RESETS {1} \
    ] [get_bd_cells zynq_ultra_ps_e_0]
}

# 3c. proc_sys_reset for pl_clk0, named rst_ps8_0_99M_0 (matches BD editor).
dlb_step "create_proc_sys_reset" {
    create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_ps8_0_99M_0
    connect_bd_net [get_bd_pins zynq_ultra_ps_e_0/pl_clk0] \
                   [get_bd_pins rst_ps8_0_99M_0/slowest_sync_clk]
    connect_bd_net [get_bd_pins zynq_ultra_ps_e_0/pl_resetn0] \
                   [get_bd_pins rst_ps8_0_99M_0/ext_reset_in]
}

# 3d. AXI interconnect ps8_0_axi_periph from M_AXI_HPM0_FPD (start NUM_MI=1; the
#     BD editor grows it for the GPIOs + DUT lite).
dlb_step "create_interconnect" {
    # Single SmartConnect (NOT axi_interconnect): does AXI4(PS)->AXI4LITE(slaves)
    # for ALL slaves directly. Avoids the xbar/auto_pc that mangled the DUT
    # module-ref write channel (wstrb=0). Single clock domain (NUM_CLKS=1).
    create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 ps8_0_axi_periph
    set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {1} CONFIG.NUM_CLKS {1}] [get_bd_cells ps8_0_axi_periph]
    # CRITICAL: disable Low-Area Mode. In low-area mode this SmartConnect ZEROED
    # the write strobe (wstrb 0xF at PS S00 -> 0 at the DUT M04, ILA-confirmed),
    # so the DUT's phase3_axi_lite_regs (which gates writes on s_axi_wstrb) never
    # latched — DUT enable stuck 0. (AXI GPIO ignores wstrb so it appeared to
    # work.) Full mode preserves wstrb.
    catch { set_property CONFIG.ADVANCED_PROPERTIES {__experimental_features__ {disable_low_area_mode 1}} [get_bd_cells ps8_0_axi_periph] }

    set CLK /zynq_ultra_ps_e_0/pl_clk0
    set RST /rst_ps8_0_99M_0/peripheral_aresetn

    # SmartConnect single aclk/aresetn (no per-port ACLK pins).
    connect_bd_net [get_bd_pins $CLK] [get_bd_pins ps8_0_axi_periph/aclk]
    connect_bd_net [get_bd_pins $RST] [get_bd_pins ps8_0_axi_periph/aresetn]

    # PS clock into maxihpm0_fpd_aclk + the SmartConnect SI from PS HPM0.
    connect_bd_net [get_bd_pins $CLK] [get_bd_pins zynq_ultra_ps_e_0/maxihpm0_fpd_aclk]
    connect_bd_intf_net [get_bd_intf_pins zynq_ultra_ps_e_0/M_AXI_HPM0_FPD] \
                        [get_bd_intf_pins ps8_0_axi_periph/S00_AXI]

    save_bd_design
    puts "DLB_BUILD: PS BD base created (PS + interconnect + reset)"
}

# =============================================================================
# 4. Source the manual-wiring BD editor (adds player + DUT + capture + 4 GPIOs,
#    wiring, addresses, validate). It opens the project/BD by path itself, so it
#    is self-contained; we keep the BD open here too.
# =============================================================================
dlb_step "source_bd_editor" {
    if {[file exists $BD_EDIT]} {
        source $BD_EDIT
    } else {
        error "BD editor not found: $BD_EDIT"
    }
}

# 4b. Bake the stim mem into the player via its INIT_FILE module-ref param, if
#     the module-ref exposed it. Use a bare filename so $readmemh resolves it on
#     the synthesis search path (the .mem is added used_in_synthesis above).
dlb_step "set_player_init_file" {
    set cell [get_bd_cells -quiet dut_player_0]
    if {$cell ne ""} {
        if {[catch {set_property CONFIG.INIT_FILE $STIM_MEM $cell} ie]} {
            puts "DLB_BUILD: WARN could not set dut_player_0 INIT_FILE ($ie)"
            puts "DLB_BUILD: NOTE bake the mem via the module param or \$readmemh path manually"
        } else {
            puts "DLB_BUILD: dut_player_0 INIT_FILE = $STIM_MEM"
            catch { save_bd_design }
        }
    } else {
        puts "DLB_BUILD: WARN dut_player_0 not present -- INIT_FILE not set"
    }
}

# =============================================================================
# 5. make_wrapper + set the BD wrapper as top
# =============================================================================
dlb_step "make_wrapper" {
    set bd [get_files -quiet system.bd]
    if {$bd eq ""} { error "system.bd not found after BD editor" }
    make_wrapper -files [get_files $bd] -top -import
    set wrap [get_files -quiet system_wrapper.v]
    if {$wrap eq ""} { set wrap [get_files -quiet *system_wrapper.v] }
    if {$wrap ne ""} {
        set_property top system_wrapper [current_fileset]
    } else {
        # fall back to whatever the wrapper top is named
        catch { set_property top system_wrapper [current_fileset] }
        puts "DLB_BUILD: WARN system_wrapper.v not located by name -- top set best-effort"
    }
    update_compile_order -fileset sources_1
    puts "DLB_BUILD: top = [get_property top [current_fileset]]"
}

# =============================================================================
# Stop here for STAGE=validate
# =============================================================================
if {$STAGE eq "validate"} {
    catch { save_bd_design }
    puts "DLB_BUILD: address segments --"
    catch {
        open_bd_design [get_files -quiet system.bd]
        foreach s [get_bd_addr_segs -quiet] {
            puts "  seg $s off [get_property OFFSET $s] range [get_property RANGE $s]"
        }
    }
    puts "DLB_BUILD: VALIDATE_OK"
    puts "DLB_BUILD: DONE"
    return
}

# =============================================================================
# 6. STAGE=build: generate_target + synth + impl + bitstream + XSA
# =============================================================================
set build_ok 1

if {$build_ok} {
    set build_ok [dlb_step "generate_target" {
        generate_target all [get_files system.bd]
        catch { export_ip_user_files -of_objects [get_files system.bd] -no_script -sync -force -quiet }
    }]
}

if {$build_ok} {
    set build_ok [dlb_step "synth" {
        reset_run synth_1
        launch_runs synth_1 -jobs 8
        wait_on_run synth_1
        set st [get_property STATUS [get_runs synth_1]]
        set pr [get_property PROGRESS [get_runs synth_1]]
        puts "DLB_BUILD: synth_1 STATUS=$st PROGRESS=$pr"
        if {$pr ne "100%"} { error "synth_1 did not complete ($st / $pr)" }
    }]
}

if {$build_ok} {
    set build_ok [dlb_step "impl_bitstream" {
        launch_runs impl_1 -to_step write_bitstream -jobs 8
        wait_on_run impl_1
        set st [get_property STATUS [get_runs impl_1]]
        set pr [get_property PROGRESS [get_runs impl_1]]
        puts "DLB_BUILD: impl_1 STATUS=$st PROGRESS=$pr"
        if {$pr ne "100%"} { error "impl_1 did not reach 100% ($st / $pr)" }
    }]
}

if {$build_ok} {
    set build_ok [dlb_step "write_hw_platform" {
        open_run impl_1
        write_hw_platform -fixed -include_bit -force $XSA_OUT
        puts "DLB_BUILD: XSA written -> $XSA_OUT"
    }]
}

# ---- final markers + address segment dump (like s2_bd_edit.tcl) -------------
catch {
    if {[get_files -quiet system.bd] ne ""} {
        catch { open_bd_design [get_files system.bd] }
        puts "DLB_BUILD: address segments --"
        foreach s [get_bd_addr_segs -quiet] {
            puts "  seg $s off [get_property OFFSET $s] range [get_property RANGE $s]"
        }
    }
}

if {$build_ok} {
    puts "DLB_BUILD: BUILD_OK"
} else {
    puts "DLB_BUILD: BUILD_FAILED"
}
puts "DLB_BUILD: DONE"
