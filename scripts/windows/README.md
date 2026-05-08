# Windows Vivado Scripts — RTL_SYNC Phase 1

## Environment Split

| Task | Environment |
|------|-------------|
| RTL editing | WSL `/home/zealatan/RTL_SYNC` |
| Testbench editing | WSL |
| Vivado xsim simulation | WSL |
| Documentation | WSL |
| Prompt archive | WSL |
| Script generation | WSL |
| Vivado synthesis | **Windows** `C:\RTL_SYNC` |
| Vivado implementation | **Windows** |
| Bitstream generation | **Windows** |
| ZCU102 board bring-up | **Windows** / Vitis |

## Windows Workspace

```
C:\RTL_SYNC
```

This directory mirrors `/home/zealatan/RTL_SYNC` in WSL.

## Vivado Version

```
2022.2
```

```
C:\Xilinx\Vivado\2022.2\bin\vivado.bat -version
```

## Target Board / Part

- Board: ZCU102
- Part: `xczu9eg-ffvb1156-2-e`

## Step 22 — Phase-1 OOC Synthesis Check

### Command

Run from Windows PowerShell or CMD:

```bat
cd C:\RTL_SYNC
scripts\windows\run_step22_zcu102_ooc_synth.bat
```

### What it does

1. Calls Vivado 2022.2 in batch mode.
2. Runs `scripts/step22_synth_check.tcl`.
3. Synthesizes `frac_cfo_frame_corrector_top` out-of-context (OOC) targeting `xczu9eg-ffvb1156-2-e`.
4. Clock: `aclk` at 100 MHz (10.000 ns period).
5. Generates reports under `reports/`.

### Synthesis Stub Strategy

Two modules are behavioral simulation models that are not synthesizable:

| Module | Issue | Replacement |
|--------|-------|-------------|
| `rtl/cordic_atan2.v` | Uses `real`, `$atan2` | `cordic_v6_0` IP (translate mode) |
| `rtl/nco_phase_gen.v` | Uses `real`, `$sin`, `$cos` | `cordic_v6_0` IP (rotate mode) + NCO |

For the Step 22 OOC check, synthesizable stubs are used instead
(`scripts/synth_stubs/cordic_atan2_stub.v` and `scripts/synth_stubs/nco_phase_gen_stub.v`).
This lets the rest of the design hierarchy be checked for synthesis correctness.

Before production FPGA build (Step 23+), these stubs must be replaced with actual
Xilinx CORDIC IP instances generated from the Vivado IP Catalog.

### Reports generated

| File | Contents |
|------|----------|
| `reports/step22_synth_utilization.rpt` | LUT / FF / BRAM / DSP usage |
| `reports/step22_timing_summary.rpt` | WNS / TNS, unconstrained paths |
| `reports/step22_drc.rpt` | Design rule check results |
| `reports/step22_clock_interaction.rpt` | Clock domain crossings |
| `reports/step22_synth_messages.log` | Full Vivado console log |

### Copying reports back to WSL

After the Windows run completes:

```bash
# From WSL
cp /mnt/c/RTL_SYNC/reports/step22_*.rpt /home/zealatan/RTL_SYNC/reports/
cp /mnt/c/RTL_SYNC/reports/step22_synth_messages.log /home/zealatan/RTL_SYNC/reports/
```

## Constraints

- **Do NOT run bitstream generation in Step 22.** Synthesis only.
- **Do NOT run implementation in Step 22.** Synthesis only.
- **Do NOT run Vitis in Step 22.**
- int_cfo_estimator.v is deferred to Step 24+.

## Recommended Step 23

Depends on Step 22 result:

- If synthesis passes (no critical errors beyond expected CORDIC stub warnings):
  → Step 23 = AXI-Lite debug/config wrapper for Phase-1 FPGA bring-up
- If synthesis fails (unexpected RTL blocker):
  → Step 23 = Fix synthesis blocker while preserving Step 21 simulation (PASS=176)

---

## Step 27 — ZCU102 Block Design (No ILA)

### Command

Run from Windows PowerShell or CMD:

```bat
cd C:\RTL_SYNC
scripts\windows\run_step27_create_zcu102_bd_no_ila.bat
```

### What it does

1. Calls Vivado 2022.2 in batch mode.
2. Runs `scripts/vivado/step27_create_zcu102_bd_no_ila.tcl`.
3. Creates Vivado project `step27_zcu102_bd` under `vivado/step27_zcu102_bd/`.
4. Adds all RTL sources for `frac_cfo_sync_bram_test_wrapper`.
5. Creates block design `sync_phase1_bd`.
6. Instantiates: Zynq UltraScale+ MPSoC PS, AXI SmartConnect, proc_sys_reset, xlconstant.
7. Adds `frac_cfo_sync_bram_test_wrapper` as a BD module cell.
8. Connects: PS M_AXI_HPM0_FPD → SmartConnect → wrapper AXI-Lite slave.
9. Clock: PS pl_clk0 (100 MHz) → all IP.
10. Reset: PS pl_resetn0 → proc_sys_reset → peripheral_aresetn → wrapper + SmartConnect.
11. Assigns wrapper base address: 0xA0000000, range 64 KB.
12. Validates BD, creates HDL wrapper, generates output products.
13. Does NOT run synthesis, implementation, or bitstream generation.

### Output

| File/Directory | Contents |
|----------------|----------|
| `vivado\step27_zcu102_bd\` | Vivado project |
| `vivado\step27_zcu102_bd\step27_zcu102_bd.xpr` | Project file (open in Vivado GUI) |
| `reports\step27\step27_create_bd.log` | Console log |
| `reports\step27\step27_create_bd.jou` | Journal |

### No ILA / No DMA

ILA and DMA are intentionally omitted. Phase 1 bring-up uses PS AXI reads/writes only.

### Constraints

- **Do NOT run implementation in Step 27.** Block design creation only.
- **Do NOT run bitstream generation in Step 27.**
- **Do NOT add ILA or DMA.**

### Copying results back to WSL

```bash
# From WSL after Windows run:
cp /mnt/c/RTL_SYNC/reports/step27/step27_create_bd.log \
   /home/zealatan/RTL_SYNC/reports/step27/
```

### Recommended Step 28

Run the Step 27 block design through synthesis + implementation + bitstream + XSA export.

---

## Step 28 — ZCU102 Synthesis, Implementation, Bitstream, XSA

### Command

Run from Windows PowerShell or CMD:

```bat
cd C:\RTL_SYNC
scripts\windows\run_step28_build_bitstream_xsa.bat
```

### What it does

1. Opens Step 27 project: `vivado\step27_zcu102_bd\step27_zcu102_bd.xpr`
2. Verifies top = `sync_phase1_bd_wrapper`
3. Resets prior runs (idempotent)
4. Runs synthesis (`synth_1`, 4 jobs)
5. Generates synthesis utilization and timing summary reports
6. Runs implementation (`impl_1`, 4 jobs)
7. Generates implementation utilization, timing, DRC, and power reports
8. Checks timing: prints `TIMING CHECK: PASS` or exits non-zero
9. Writes bitstream to `outputs\step28\sync_phase1_bd_wrapper.bit`
10. Exports XSA to `outputs\step28\sync_phase1_bd_wrapper.xsa`
11. Saves full log to `reports\step28\step28_build.log`

### Outputs

| File | Contents |
|------|----------|
| `outputs\step28\sync_phase1_bd_wrapper.bit` | FPGA bitstream |
| `outputs\step28\sync_phase1_bd_wrapper.xsa` | Vitis hardware platform |
| `reports\step28\step28_build.log` | Full console log |
| `reports\step28\step28_synth_utilization.rpt` | Synthesis resource usage |
| `reports\step28\step28_synth_timing_summary.rpt` | Synthesis timing |
| `reports\step28\step28_impl_utilization.rpt` | Implementation resource usage |
| `reports\step28\step28_timing_summary.rpt` | Implementation timing (WNS/WHS) |
| `reports\step28\step28_drc.rpt` | DRC results |
| `reports\step28\step28_power.rpt` | Power estimate |

### No ILA / No DMA / No Integer CFO

ILA, DMA, VIO, and integer CFO are intentionally omitted.
Phase 1 bring-up uses PS AXI reads/writes and UART print-out via Vitis (Step 29).

### Copying results back to WSL

```bash
# From WSL after Windows run:
cp /mnt/c/RTL_SYNC/outputs/step28/sync_phase1_bd_wrapper.bit \
   /home/zealatan/RTL_SYNC/outputs/step28/
cp /mnt/c/RTL_SYNC/outputs/step28/sync_phase1_bd_wrapper.xsa \
   /home/zealatan/RTL_SYNC/outputs/step28/
cp /mnt/c/RTL_SYNC/reports/step28/*.rpt \
   /home/zealatan/RTL_SYNC/reports/step28/
cp /mnt/c/RTL_SYNC/reports/step28/step28_build.log \
   /home/zealatan/RTL_SYNC/reports/step28/
```

### Recommended Step 28C

Run Step 28C to re-export the XSA with the embedded bitstream (see below).

---

## Step 28C — Export XSA with Embedded Bitstream

### Command

Run from Windows PowerShell or CMD:

```bat
cd C:\RTL_SYNC
.\scripts\windows\run_step28c_export_xsa_with_bitstream.bat
```

### Prerequisite

Step 27 block design project must exist:

```
vivado\step27_zcu102_bd\step27_zcu102_bd.xpr
```

If not, run Step 27 first:

```bat
.\scripts\windows\run_step27_create_zcu102_bd_no_ila.bat
```

### Why this step exists

Step 28 generated `sync_phase1_bd_wrapper.xsa` **without** the embedded bitstream.
`write_hw_platform -include_bit` failed because bitstream generation was called as a
standalone `write_bitstream` command rather than through the Vivado run infrastructure.

Step 28C fixes this by using:

```tcl
launch_runs impl_1 -to_step write_bitstream -jobs 4
```

This drives `impl_1` all the way through bitstream generation as a run step, after which
`write_hw_platform -include_bit` succeeds.

### What it does

1. Opens Step 27 project: `vivado\step27_zcu102_bd\step27_zcu102_bd.xpr`
2. Resets prior runs (idempotent)
3. Runs synthesis (`synth_1`, 4 jobs)
4. Runs implementation **to write_bitstream** (`impl_1 -to_step write_bitstream`, 4 jobs)
5. Verifies bitstream exists in run directory before proceeding
6. Generates timing, utilization, DRC, and power reports
7. Checks timing: exits non-zero if WNS < 0 or WHS < 0
8. Exports `outputs\step28\sync_phase1_bd_wrapper_with_bit.xsa` with embedded bitstream
   — **no fallback to no-bit XSA**
9. Checks that the XSA file was actually written

### Outputs

| File | Contents |
|------|----------|
| `outputs\step28\sync_phase1_bd_wrapper_with_bit.xsa` | XSA with embedded bitstream |
| `reports\step28c\step28c_synth_utilization.rpt` | Synthesis resource usage |
| `reports\step28c\step28c_synth_timing_summary.rpt` | Synthesis timing |
| `reports\step28c\step28c_impl_utilization.rpt` | Implementation resource usage |
| `reports\step28c\step28c_timing_summary.rpt` | Implementation timing |
| `reports\step28c\step28c_drc.rpt` | DRC results |
| `reports\step28c\step28c_power.rpt` | Power estimate |
| `reports\step28c\step28c_export_xsa_with_bitstream.log` | Full console log |

### Step 28 outputs preserved

| File | Status |
|------|--------|
| `outputs\step28\sync_phase1_bd_wrapper.bit` | Preserved |
| `outputs\step28\sync_phase1_bd_wrapper.xsa` | Preserved (no embedded bitstream) |

### Copying results back to WSL

```bash
# From WSL after Windows run:
cp /mnt/c/RTL_SYNC/outputs/step28/sync_phase1_bd_wrapper_with_bit.xsa \
   /home/zealatan/RTL_SYNC/outputs/step28/
cp /mnt/c/RTL_SYNC/reports/step28c/*.rpt \
   /home/zealatan/RTL_SYNC/reports/step28c/
cp /mnt/c/RTL_SYNC/reports/step28c/step28c_export_xsa_with_bitstream.log \
   /home/zealatan/RTL_SYNC/reports/step28c/
```

### Recommended next action after Step 28C

Use `sync_phase1_bd_wrapper_with_bit.xsa` as the Vitis platform input.
Vitis will automatically program the FPGA when launching the application —
no separate Vivado Hardware Manager programming step required.

See `docs/step29b_zcu102_vitis_bringup_uart_test.md` for the board bring-up procedure.

---

## Step 29 — ZCU102 Vitis Bring-Up (Recommended next action after Step 28C)

Create a Vitis baremetal C application for known-vector testing.
Import `sync_phase1_bd_wrapper_with_bit.xsa` into Vitis 2022.2 as the hardware platform.
See `sw/step29a_vitis_known_vector/README.md` for detailed Vitis GUI steps.
