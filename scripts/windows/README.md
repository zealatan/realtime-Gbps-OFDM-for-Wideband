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
