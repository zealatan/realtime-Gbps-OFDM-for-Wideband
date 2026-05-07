Step 27C Fix Prompt — Disable Unused HPM1 FPD and Fix BD Address Assignment

Active workspace:

/home/zealatan/RTL_SYNC

Windows workspace:

C:\RTL_SYNC

Problem observed during Windows Vivado Step 27B execution:

validate_bd_design reported two errors that block a clean BD:

Error 1 — Unconnected maxihpm1_fpd_aclk:

  [BD 41-1273] ...maxihpm1_fpd_aclk is an unconnected clock input port.

Root cause:
  ZCU102 board automation applies apply_board_preset "1" which enables BOTH
  M_AXI_HPM0_FPD (GP0) and M_AXI_HPM1_FPD (GP1) on the Zynq UltraScale+ PS.
  The design only uses HPM0 (one AXI master to the SmartConnect → wrapper_0).
  HPM1 is not used, so maxihpm1_fpd_aclk is left unconnected.
  validate_bd_design treats an unconnected clock input on an enabled AXI master as an error.

Error 2 — set_property offset/range on wrong segment type:

  WARNING: Property offset does not exist on object of type bd_addr_seg.
  WARNING: Property range does not exist on object of type bd_addr_seg.

Root cause:
  The v2 script called:
    get_bd_addr_segs -of_objects [get_bd_intf_pins wrapper_0/*]
  which returns slave-side segments (e.g. wrapper_0/S_AXI/reg0).
  Slave-side bd_addr_segs do NOT have OFFSET or RANGE properties.
  Only master-mapped segments (created when a slave is mapped into a master's
  address space) have these properties.
  set_property offset/range on slave segments silently does nothing (warning only),
  leaving the address map in an unverified state.

Task:

Patch scripts/vivado/step27_create_zcu102_bd_no_ila.tcl (v2 → v3) to fix both errors
so that validate_bd_design passes and make_wrapper passes cleanly.

Fix 1 — Disable HPM1 FPD:

After the PS automation block and existing PSU__USE__M_AXI_GP0 / FCLK0 configuration,
explicitly add:

  set_property CONFIG.PSU__USE__M_AXI_GP1 {0} $ps

This forces HPM1 disabled even if board automation had enabled it.
Do NOT add any maxihpm1_fpd_aclk clock connection (only maxihpm0_fpd_aclk is connected).
The existing clock connection to maxihpm0_fpd_aclk in the clock section is correct as-is.

Fix 2 — Use assign_bd_address -offset -range <slave_seg>:

Replace the current pattern:
  assign_bd_address
  set segs [get_bd_addr_segs -of_objects [get_bd_intf_pins ...]]
  set_property offset $WRAP_BASE $seg    ; THIS FAILS — slave seg has no OFFSET
  set_property range  $WRAP_RANGE $seg   ; THIS FAILS — slave seg has no RANGE

With the correct form:
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

This uses assign_bd_address -offset -range <slave_seg> which:
  - takes the slave-side segment as input (not the master-mapped segment)
  - creates the master-mapped segment with the correct offset and range
  - is the documented Vivado Tcl API for address assignment with explicit values
Fallback to plain assign_bd_address (auto) if targeted form fails for any reason.

Required results:

- validate_bd_design passes (no errors)
- make_wrapper passes (HDL wrapper created cleanly)
- generate_target all completes without error

Do not:
- Add ILA or DMA
- Modify RTL
- Modify existing simulation scripts or testbenches
- Change the BD architecture or address map

Files to modify:

- scripts/vivado/step27_create_zcu102_bd_no_ila.tcl  (v2 → v3)

Files to create:

- md_files/27c_disable_unused_hpm1_prompt.md  (this file)

Files to update:

- docs/step27_zcu102_bd_integration_no_ila.md  (add Step 27C failure/fix section)
- ai_context/current_status.md  (Step 27C status)

Final report format:

Step 27C fix complete.

Prompt archive:
- saved prompt path: md_files/27c_disable_unused_hpm1_prompt.md

Files changed:
- scripts/vivado/step27_create_zcu102_bd_no_ila.tcl (v3)
- docs/step27_zcu102_bd_integration_no_ila.md
- ai_context/current_status.md
- md_files/27c_disable_unused_hpm1_prompt.md

Failures fixed:
- Error 1: maxihpm1_fpd_aclk unconnected
  Root cause: board automation enables HPM1 FPD; HPM1 unused
  Fix: set PSU__USE__M_AXI_GP1=0 after automation
- Error 2: set_property offset/range on slave segment (bd_addr_seg)
  Root cause: slave segs have no OFFSET/RANGE property
  Fix: assign_bd_address -offset -range <slave_seg>

RTL modified: No

Recommended next action:
- Run Windows Step 27 again (v3 script) and confirm validate_bd_design passes.
