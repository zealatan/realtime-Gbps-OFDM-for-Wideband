# Step 27 — ZCU102 Vivado Block Design Integration (No ILA)

## Goal

Create a minimal ZCU102 Vivado block design connecting the Zynq UltraScale+ MPSoC PS
to `frac_cfo_sync_bram_test_wrapper` via AXI.  The wrapper is memory-mapped into the
PS address space so ARM firmware can write IQ samples, trigger a synchronizer run, and
read results — all through standard memory-mapped I/O.

No ILA, no DMA, no implementation in this step.

## Phase 1 Context

| Phase | Goal |
|-------|------|
| 1 (current) | Functional FPGA synchronizer: PS writes IQ to BRAM, triggers run, reads results |
| 2 | 1 sample/clock streaming synchronizer |
| 3 | Multi-sample/clock parallel synchronizer |

This step completes the Phase 1 hardware integration path: simulation-verified RTL →
OOC synthesis (Step 24) → AXI wrapper (Steps 25–26) → ZCU102 block design (Step 27).

## Step 26 Wrapper Summary

`frac_cfo_sync_bram_test_wrapper` exposes a single AXI4-Lite slave (16-bit byte address, 32-bit data)
and internally contains:

- Control/status registers (11 × 32-bit at 0x0000–0x0028)
- Input memory window (1024 × 32-bit at 0x1000–0x1FFF, R/W from PS)
- Output memory window (1024 × 32-bit at 0x2000–0x2FFF, R/O from PS)
- Stream source FSM (input_mem → DUT AXI-Stream)
- `frac_cfo_frame_corrector_top` (synchronizer DUT)
- Stream sink FSM (DUT AXI-Stream → output_mem)

Memories are inferred (reg arrays, not Xilinx BRAM IP).  No external AXI BRAM Controller
or Block Memory Generator is needed.

## Why ILA Is Omitted

The user explicitly decided that ILA is not needed at this stage.  Phase 1 FPGA bring-up
is done via PS AXI reads/writes.  STATUS, INPUT_COUNT, OUTPUT_COUNT, and DEBUG_STATE
registers provide the necessary observability without intrusive debug fabric.  ILA can be
added in a later step if needed.

## Target

| Item | Value |
|------|-------|
| Board | ZCU102 Rev 1.0 |
| Part | `xczu9eg-ffvb1156-2-e` |
| Vivado | 2022.2 (Windows) |
| Clock target | 100 MHz via PS FCLK0 |
| BD name | `sync_phase1_bd` |

## Block Design Architecture

```
Zynq UltraScale+ MPSoC
  pl_clk0 (100 MHz) ──────────────────────────────────────────────┐
  pl_resetn0 ──► proc_sys_reset_0 ──► peripheral_aresetn ──────┐  │
                                                                 │  │
  M_AXI_HPM0_FPD ──► axi_smc (SmartConnect 1S→1M) ──► s_axi  │  │
                                                    wrapper_0   │  │
                         frac_cfo_sync_bram_test_wrapper ◄──────┘  │
                           aclk ◄──────────────────────────────────┘
```

### Xilinx IP Used

| IP | VLNV | Purpose |
|----|------|---------|
| Zynq UltraScale+ MPSoC | `xilinx.com:ip:zynq_ultra_ps_e:*` | PS — AXI master, clock, reset |
| AXI SmartConnect | `xilinx.com:ip:smartconnect:*` | AXI crossbar (1 master → 1 slave) |
| Processor System Reset | `xilinx.com:ip:proc_sys_reset:*` | Synchronized active-low reset |
| XL Constant | `xilinx.com:ip:xlconstant:*` | Tie `dcm_locked=1` for proc_sys_reset |

### Custom RTL Module

| Module | File | Role |
|--------|------|------|
| `frac_cfo_sync_bram_test_wrapper` | `rtl/frac_cfo_sync_bram_test_wrapper.v` | BD cell (`wrapper_0`) |
| (internal hierarchy) | `rtl/frac_cfo_frame_corrector_top.v` + dependencies | Instantiated inside wrapper |

## Clock / Reset Strategy

| Signal | Source | Destination |
|--------|--------|-------------|
| `pl_clk0` (100 MHz) | PS | `maxihpm0_fpd_aclk`, `proc_sys_reset_0/slowest_sync_clk`, `axi_smc/aclk`, `wrapper_0/aclk` |
| `pl_resetn0` (active-low) | PS | `proc_sys_reset_0/ext_reset_in` |
| `peripheral_aresetn` (active-low) | `proc_sys_reset_0` | `axi_smc/aresetn`, `wrapper_0/aresetn` |
| `dcm_locked` | `xlconstant_0` (=1) | `proc_sys_reset_0/dcm_locked` |

All logic runs in a single 100 MHz clock domain — no CDC required.

## AXI Address Map

| Slave | Base Address | Range | Notes |
|-------|-------------|-------|-------|
| `wrapper_0` (`frac_cfo_sync_bram_test_wrapper`) | `0xA000_0000` | 64 KB | Covers 0x0000–0x2FFF (control + memories) |

### Register Offsets Within Wrapper

| Offset | Register | Access |
|--------|----------|--------|
| 0x0000 | CONTROL | W/R |
| 0x0004 | STATUS | R/O |
| 0x0008 | CFG_CFO_STEP | W/R |
| 0x000C | CFG_TIMING_OFFSET | W/R |
| 0x0010 | CFG_FRAME_LEN | W/R |
| 0x0014 | INPUT_LEN | W/R |
| 0x0018 | OUTPUT_MAX_LEN | W/R |
| 0x001C | INPUT_COUNT | R/O |
| 0x0020 | OUTPUT_COUNT | R/O |
| 0x0024 | DEBUG_STATE | R/O |
| 0x0028 | ERROR_STATUS | R/O |
| 0x1000–0x1FFF | Input memory window | W/R |
| 0x2000–0x2FFF | Output memory window | R/O |

## Files

| File | Description |
|------|-------------|
| `scripts/vivado/step27_create_zcu102_bd_no_ila.tcl` | Vivado Tcl — creates project, BD, connects IPs, assigns addresses |
| `scripts/windows/run_step27_create_zcu102_bd_no_ila.bat` | Windows batch — calls Vivado batch mode, saves log |
| `docs/step27_zcu102_bd_integration_no_ila.md` | This document |

## Tcl Script Description

`scripts/vivado/step27_create_zcu102_bd_no_ila.tcl`:

1. Creates project `step27_zcu102_bd` under `vivado/step27_zcu102_bd/`
2. Attempts to load ZCU102 board preset (`xilinx.com:zcu102:part0:3.4`) — falls back to manual PS config if board files unavailable
3. Reads all 18 RTL source files for the `frac_cfo_sync_bram_test_wrapper` hierarchy
4. Creates block design `sync_phase1_bd`
5. Adds PS (`zynq_ultra_ps_e_0`): enables HPM0 FPD master, FCLK0 at 100 MHz
6. Adds `proc_sys_reset_0` with `dcm_locked` tied to 1
7. Adds `axi_smc` (SmartConnect, 1S→1M)
8. Adds `wrapper_0` (`frac_cfo_sync_bram_test_wrapper`)
9. Connects all clocks and resets
10. Connects `M_AXI_HPM0_FPD → axi_smc → wrapper_0/s_axi`
11. Assigns addresses: wrapper base = `0xA0000000`, range = 64 KB
12. Validates, saves BD
13. Creates HDL wrapper `sync_phase1_bd_wrapper`, sets as top
14. Generates output products (no synthesis)

## Windows Batch Command

```bat
cd C:\RTL_SYNC
scripts\windows\run_step27_create_zcu102_bd_no_ila.bat
```

Output log: `reports\step27\step27_create_bd.log`

## Execution Status

**Prepared, pending Windows Vivado run.**

The Tcl script and batch file have been authored in WSL and are ready for execution on Windows.
Vivado block design creation, `validate_bd_design`, and output product generation
have **not yet been run**.  No synthesis, no implementation, no bitstream.

## Known Limitations

1. **Board files**: ZCU102 board preset (`xilinx.com:zcu102:part0:3.4`) may not be installed.
   The script auto-detects and falls back to minimal manual PS configuration.  Install from
   Vivado Tools → Vivado Board Store if needed for full board automation.

2. **AXI-Lite interface inference**: Vivado IP Integrator infers AXI interfaces from
   port name conventions.  The wrapper's `s_axi_*` port names follow the standard AXI4-Lite
   naming pattern.  If inference fails (Vivado error on `connect_bd_intf_net`), the user
   may need to open the BD in GUI and manually define/map the interface.

3. **Address width**: The wrapper's `s_axi_awaddr`/`s_axi_araddr` are 16-bit.  Vivado SmartConnect
   typically outputs 40-bit addresses for MPSoC.  Vivado BD handles this through address
   assignment (the base address is stripped; only the 16-bit offset reaches the wrapper).
   A DRC warning may appear but should not be critical.

4. **Inferred memory synthesis**: The wrapper uses `reg [31:0] input_mem [0:1023]` and
   `output_mem [0:1023]` — inferred BRAM.  Vivado synthesis should map these to RAMB36
   primitives.  If synthesis encounters issues with initial blocks or memory inference,
   the user should run synthesis in Step 28 and check the utilization report.

5. **PS configuration completeness**: Without board files, DDR, MIO, and other PS
   peripherals are not configured.  This is sufficient for a PL-only bring-up via JTAG
   AXI access.  Full PS configuration (DDR, UART, SD) is a Step 28+ concern.

## Recommended Step 28

**Step 28 — Vivado Synthesis / Implementation / Bitstream / XSA Export**

Run the Step 27 block design through the full implementation flow on Windows:

```bat
REM In C:\RTL_SYNC
REM Run in Vivado Tcl console or via a new batch script:
open_project vivado\step27_zcu102_bd\step27_zcu102_bd.xpr
launch_runs synth_1 -jobs 4
wait_on_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
open_run impl_1
write_hw_platform -fixed -include_bit -force -file reports\step28\sync_phase1.xsa
```

Export the XSA to Vitis for ARM firmware development.
