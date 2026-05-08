# Step 28C — Export XSA with Embedded Bitstream

## Motivation

Vitis can use an XSA that contains the embedded bitstream to program the FPGA
automatically when launching an application, without requiring a separate Vivado
Hardware Manager session.

Step 28 generated an XSA without the embedded bitstream. This document explains
the root cause and the fix applied in Step 28C.

---

## Step 28 Issue

In Step 28, `write_hw_platform -include_bit` failed with:

```
Unable to get BIT file from implementation run.
Please ensure implementation has been run all the way through Bitstream generation.
```

The root cause: the Step 28 Tcl script launched implementation with:

```tcl
launch_runs impl_1 -jobs 4
```

This stops implementation at `route_design` (the default final step). Bitstream
generation was then called as a **separate** command:

```tcl
write_bitstream -force $BIT_FILE
```

When `write_bitstream` runs standalone (not as part of the Vivado run infrastructure),
Vivado does not register the resulting `.bit` file path in the `impl_1` run object.
So when `write_hw_platform -include_bit` queries `impl_1` for the BIT file path, it
finds nothing and fails.

The Step 28 script fell back to:

```tcl
write_hw_platform -fixed -force -file $XSA_FILE
```

This generated an XSA without embedded bitstream. The fallback XSA is valid for
Vitis platform creation, but Vitis cannot automatically program the FPGA from it —
the bitstream must be programmed separately via Vivado Hardware Manager first.

---

## Step 28C Fix

Step 28C changes the implementation launch to:

```tcl
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
```

The `-to_step write_bitstream` flag tells Vivado to run impl_1 all the way through
bitstream generation as part of the run. Vivado then records the bitstream path in
the `impl_1` run object. After `wait_on_run impl_1` returns, `write_hw_platform -include_bit`
can retrieve that path and embed the bitstream into the XSA.

Step 28C then calls:

```tcl
write_hw_platform -fixed -include_bit -force -file $XSA_WITH_BIT
```

with **no fallback**. If this command fails, the script exits non-zero so the failure
is visible rather than silently producing a deficient artifact.

---

## Inputs

| Input | Path |
|-------|------|
| Step 27 Vivado project | `vivado/step27_zcu102_bd/step27_zcu102_bd.xpr` |
| RTL (via packaged IP in project) | `rtl/` (not re-read; already in project) |

The Step 27 project must exist before running Step 28C. If it does not, run:

```bat
.\scripts\windows\run_step27_create_zcu102_bd_no_ila.bat
```

---

## Outputs

| File | Description |
|------|-------------|
| `outputs/step28/sync_phase1_bd_wrapper_with_bit.xsa` | **New** XSA with embedded bitstream |
| `reports/step28c/step28c_synth_utilization.rpt` | Synthesis resource usage |
| `reports/step28c/step28c_synth_timing_summary.rpt` | Synthesis timing |
| `reports/step28c/step28c_impl_utilization.rpt` | Implementation resource usage |
| `reports/step28c/step28c_timing_summary.rpt` | Implementation timing (WNS/WHS) |
| `reports/step28c/step28c_drc.rpt` | DRC results |
| `reports/step28c/step28c_power.rpt` | Power estimate |
| `reports/step28c/step28c_export_xsa_with_bitstream.log` | Full Vivado console log |

### Step 28 outputs are preserved and not overwritten

| File | Status |
|------|--------|
| `outputs/step28/sync_phase1_bd_wrapper.bit` | Preserved |
| `outputs/step28/sync_phase1_bd_wrapper.xsa` | Preserved (no embedded bitstream) |

---

## Difference from Step 28

| Aspect | Step 28 | Step 28C |
|--------|---------|---------|
| Implementation launch | `launch_runs impl_1` | `launch_runs impl_1 -to_step write_bitstream` |
| Bitstream generation | Separate `write_bitstream` call | Part of impl_1 run |
| XSA bitstream embedding | Attempted, fell back on failure | Required, exits on failure |
| Fallback to no-bit XSA | Yes | No |
| Output XSA name | `sync_phase1_bd_wrapper.xsa` | `sync_phase1_bd_wrapper_with_bit.xsa` |
| Reports directory | `reports/step28/` | `reports/step28c/` |

---

## How to Run on Windows

From Windows PowerShell or CMD, run from the repository root:

```bat
cd C:\RTL_SYNC
.\scripts\windows\run_step28c_export_xsa_with_bitstream.bat
```

The batch runner:
1. Checks Vivado 2022.2 is installed at `C:\Xilinx\Vivado\2022.2\`
2. Verifies Step 27 project exists
3. Creates `reports\step28c\` and `outputs\step28\`
4. Runs `scripts\vivado\step28c_export_xsa_with_bitstream.tcl` in Vivado batch mode
5. Checks that `outputs\step28\sync_phase1_bd_wrapper_with_bit.xsa` exists after the run
6. Prints `STEP 28C RESULT: PASS` or `STEP 28C RESULT: FAIL`

---

## Expected Vitis Usage

After Step 28C produces the embedded-bitstream XSA:

1. Open Vitis 2022.2 on Windows.
2. **File → New → Platform Project**
3. Name: `sync_phase1_platform`
4. XSA: `C:\RTL_SYNC\outputs\step28\sync_phase1_bd_wrapper_with_bit.xsa`
5. OS: **standalone**, Processor: **psu_cortexa53_0**
6. Build the platform (BSP generation).
7. Create application project `known_vector_test` using the Step 29A source files.
8. **Run As → Launch on Hardware** — Vitis will program the FPGA from the embedded
   bitstream automatically before starting the Cortex-A53 ELF.

Using the embedded-bitstream XSA avoids the separate Vivado Hardware Manager
programming step required when using the no-bit XSA from Step 28.

---

## Copying Results to WSL

After the Windows run completes:

```bash
# From WSL:
cp /mnt/c/RTL_SYNC/outputs/step28/sync_phase1_bd_wrapper_with_bit.xsa \
   /home/zealatan/RTL_SYNC/outputs/step28/
cp /mnt/c/RTL_SYNC/reports/step28c/*.rpt \
   /home/zealatan/RTL_SYNC/reports/step28c/
cp /mnt/c/RTL_SYNC/reports/step28c/step28c_export_xsa_with_bitstream.log \
   /home/zealatan/RTL_SYNC/reports/step28c/
```

---

## Known Limitations

- No ILA — no in-hardware visibility beyond the register interface
- No DMA — samples transferred word-by-word via AXI-Lite
- Phase 1 only — known-vector bring-up design; no streaming redesign
- The same synthesized netlist as Step 28 (timing PASS: WNS=+0.891 ns, WHS=+0.010 ns)
- RTL not modified in this step

---

## Execution Status

**Prepared — pending Windows Vivado execution.**

---

## Recommended Next Action

After `sync_phase1_bd_wrapper_with_bit.xsa` is generated:

1. In Vitis 2022.2, create a new platform from the embedded-bitstream XSA.
2. Build the known-vector test application (`sw/step29a_vitis_known_vector/`).
3. Connect ZCU102 via JTAG and UART (115200 baud).
4. Run As → Launch on Hardware (Vitis programs FPGA from embedded bitstream).
5. Capture UART output → `reports/step29b/step29b_uart_log.txt`.
6. Classify result as PASS or FAIL per Step 29B criteria.

See `docs/step29b_zcu102_vitis_bringup_uart_test.md` for the full board bring-up procedure.
