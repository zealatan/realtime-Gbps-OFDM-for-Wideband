# Step 36B — CORDIC/NCO Xilinx IP Generation and Interface Audit

## Objective

Prepare Tcl scripts and documentation for Xilinx CORDIC and DDS Compiler IP generation
and interface audit, enabling a future integration of Xilinx IP into the fractional CFO
atan2 and NCO sin/cos paths.  No integration into the production top path is performed
in this step.

---

## Relationship to Steps 35A and 35B

**Step 35A** created `rtl/cordic_atan2_xilinx_wrapper.v` as an IP-ready atan2 wrapper
and `scripts/create_cordic_atan2_ip.tcl` as a preliminary Tcl skeleton.
The wrapper passed simulation (PASS: 35, FAIL: 0) using a behavioral `$atan2` model.
Actual Xilinx CORDIC XCI was not generated.

**Step 35B** created `rtl/nco_phase_gen_xilinx_wrapper.v` as an IP-ready sin/cos wrapper
and `scripts/create_cordic_sincos_ip.tcl` as a preliminary Tcl skeleton.
The wrapper passed simulation (PASS: 88, FAIL: 0) using a 256-entry ROM behavioral model.
Actual Xilinx CORDIC/DDS XCI was not generated.

**Step 36B** improves both Tcl scripts with full property documentation and TODO tracking,
adds property probe scripts to discover actual Vivado IP configuration key names, and
documents the integration audit procedure.

---

## Existing atan2 Implementation Status

`rtl/cordic_atan2.v` is a **synthesizable** 15-stage CORDIC vectoring pipeline.
It implements the full CORDIC algorithm with a fixed ATAN lookup table.
It does not use `$atan2`, `real`, `$itor`, or `$rtoi`.

The synthesis stub `scripts/synth_stubs/cordic_atan2_stub.v` declares it as a
`(* black_box *)` module for OOC synthesis (Steps 22, 24).

Current simulation test pass count: **38** (from Step 35A context).

`rtl/cordic_atan2_xilinx_wrapper.v` provides the interface scaffold with:
- `USE_BEHAVIORAL_MODEL=1` (default): behavioral `$atan2` pipeline for simulation.
- `USE_BEHAVIORAL_MODEL=0`: empty placeholder stub for future `cordic_v6_0` instantiation.

The wrapper is **not** integrated into `rtl/frac_cfo_estimator.v` or any top file.

---

## Existing NCO Implementation Status

`rtl/nco_phase_gen.v` uses a 256-entry Q1.15 ROM synthesizable as LUTRAM.
It uses `phase_acc[31:24]` (top 8 bits) as the ROM index.

`rtl/nco_phase_gen_xilinx_wrapper.v` provides the interface scaffold with:
- `USE_BEHAVIORAL_MODEL=1` (default): identical 256-entry ROM (same logic as nco_phase_gen.v).
- `USE_BEHAVIORAL_MODEL=0`: empty placeholder scaffold with commented `cordic_v6_0` template.

Current simulation test pass count: **88** (from Step 35B context).

The wrapper is **not** integrated into any top file.

---

## Why Xilinx IP Audit Is Still Useful

Even though the synthesizable RTL (`cordic_atan2.v`) and ROM-based NCO (`nco_phase_gen.v`)
are fully functional and verified, there are production reasons to eventually adopt
Xilinx CORDIC or DDS IP:

1. **Resource efficiency** — Xilinx CORDIC IP is optimised for Xilinx FPGA fabric
   (DSP slice usage, routing, timing closure) vs hand-written RTL CORDIC.
2. **Phase resolution** — CORDIC rotate mode can accept 16-bit phase inputs vs the
   8-bit (256-entry ROM) resolution of the current NCO.
3. **Vendor support** — IP-based implementations are covered by Xilinx simulation models
   and are tested across synthesis and implementation flows.
4. **Latency verification** — The Xilinx CORDIC IP reports actual latency via
   `CONFIG.Latency`, enabling automated wrapper parameter updates.

---

## CORDIC atan2 Target Configuration

| Parameter | Target value | Source |
|-----------|-------------|--------|
| IP | `cordic_v6_0` (xilinx.com:ip:cordic:6.0) | Vivado IP Catalog |
| Functional mode | `Translate` (vectoring, computes atan2) | CORDIC v6.0 PG105 |
| Architectural config | `Fully_Pipelined` | Throughput requirement |
| Pipelining mode | `Maximum` | Timing closure |
| Input width | 32 bits per Cartesian component | Matches `INPUT_WIDTH=32` in wrapper |
| Output width | 16 bits | Matches `PHASE_WIDTH=16` in wrapper |
| Phase format | `Scaled_Radians` | Maps pi → +32767; matches project convention |
| Round mode | `Truncate` | Conservative choice; may be `Round_Pos_Inf` |
| Has ARESETn | `true` | Required by wrapper |
| Has ACLKEN | `false` | Not needed; wrapper handles backpressure via tvalid |
| Flow control | `Blocking` | AXI-Stream tvalid/tready handshake |
| Target latency | 15 cycles | Matches `CORDIC_LATENCY=15` in `frac_cfo_estimator.v` |

**Note**: All `CONFIG.*` property names are preliminary pending confirmation via
`scripts/probe_cordic_ip_properties.tcl`.

---

## CORDIC Rotate-Mode sin/cos Target Configuration

| Parameter | Target value | Source |
|-----------|-------------|--------|
| IP | `cordic_v6_0` (xilinx.com:ip:cordic:6.0) | Vivado IP Catalog |
| Functional mode | `Rotate` (computes cos/sin from phase) | CORDIC v6.0 PG105 |
| Architectural config | `Fully_Pipelined` | Throughput requirement |
| Pipelining mode | `Maximum` | Timing closure |
| Input width | 16 bits (phase) | Signed Q1.15, maps to `phase_acc[31:16]` |
| Output width | 16 bits (cos/sin each) | Matches `ROTATOR_COEFF_WIDTH=16` |
| Phase format | `Scaled_Radians` | Signed 16-bit, -32768 → -pi, +32767 → +pi |
| Scale compensation | `true` | Removes CORDIC gain (~1.6468); outputs ±1 |
| Has ARESETn | `true` | Required by wrapper |
| Has ACLKEN | `false` | Not needed |
| Flow control | `Blocking` | AXI-Stream handshake |
| Target latency | 15 cycles | Matches `LATENCY=15` in wrapper |

**Phase accumulator**: remains in RTL (`nco_phase_gen_xilinx_wrapper.v`).
The CORDIC IP receives a snapshot of `phase_acc_r[31:16]` as the phase input.

---

## DDS Compiler Alternative Analysis

The DDS Compiler (`xilinx.com:ip:dds_compiler:6.0`) is an alternative to CORDIC rotate
mode for NCO sin/cos generation.

**Advantages of DDS Compiler:**
- Higher-precision internal accumulator (typically 48-bit).
- Dedicated NCO architecture with phase dithering options.
- Potentially lower area than CORDIC for a single tone.

**Disadvantages for this project:**
- DDS Compiler typically **owns the phase accumulator internally**.  The existing design
  has the accumulator in RTL (`nco_phase_gen_xilinx_wrapper.v`) with explicit `phase_reset`
  and `step_word` ports.  DDS integration would require:
  - Removing the RTL accumulator.
  - Mapping `phase_reset` to a DDS `phase_clear` or equivalent port.
  - Mapping `step_word` to a DDS phase increment reload port.
  - This is a significant interface restructure vs a simple IP swap.
- CORDIC rotate mode is a more direct drop-in because it accepts an external phase input
  and does not own the accumulator.
- The CORDIC IP family is already in use for atan2; reusing it reduces IP version risk.

**Recommendation**: Use CORDIC rotate mode for first integration.  DDS Compiler may be
evaluated for a future high-precision NCO upgrade if needed.

`scripts/probe_dds_ip_properties.tcl` and `scripts/create_dds_nco_ip.tcl` are provided
as optional evaluation tools and are clearly marked as non-recommended path.

---

## Tcl Scripts Created / Updated

| Script | Status | Purpose |
|--------|--------|---------|
| `scripts/probe_cordic_ip_properties.tcl` | **NEW** | Probe CORDIC IP properties in Vivado; write full CONFIG.* dumps |
| `scripts/create_cordic_atan2_ip.tcl` | **UPDATED** | Create CORDIC atan2/vectoring IP; full TODO tracking; log files |
| `scripts/create_cordic_sincos_ip.tcl` | **UPDATED** | Create CORDIC rotate sin/cos IP; Mode A/B documentation; log files |
| `scripts/probe_dds_ip_properties.tcl` | **NEW (optional)** | Probe DDS Compiler IP properties; compatibility analysis |
| `scripts/create_dds_nco_ip.tcl` | **NEW (optional)** | Create DDS Compiler IP; marked as optional/evaluation only |

---

## Expected AXI-Stream Interfaces

### CORDIC atan2 (vectoring mode)

```
Input:
  aclk                           clock
  aresetn                        active-low synchronous reset
  s_axis_cartesian_tvalid        input valid
  s_axis_cartesian_tready        output ready (always 1, fully pipelined)
  s_axis_cartesian_tdata[63:0]   {Q[31:0], I[31:0]}  — upper=Y/Q, lower=X/I

Output:
  m_axis_dout_tvalid             output valid (LATENCY cycles after input valid)
  m_axis_dout_tdata[15:0]        signed phase: pi→+32767, -pi→-32767
```

### CORDIC rotate (sin/cos mode)

```
Input:
  aclk                           clock
  aresetn                        active-low synchronous reset
  s_axis_phase_tvalid            input valid (= enable && !phase_reset)
  s_axis_phase_tdata[15:0]       signed phase: -32768→-pi, +32767→+pi

Output:
  m_axis_dout_tvalid             output valid (LATENCY cycles after input valid)
  m_axis_dout_tdata[31:0]        packed {sin[15:0], cos[15:0]}
                                 (upper 16 = sin, lower 16 = cos — verify from IP stub)
```

**Note**: The sin/cos word ordering in `m_axis_dout_tdata` must be confirmed from the
generated instantiation template (`.veo` or `.vho` file) after IP generation.

---

## Phase Scaling and Compatibility Risks

### atan2 path

The existing `cordic_atan2.v` uses this convention:

```
output = atan2(Q, I) / pi * 32767    (signed 16-bit)
pi  → +32767 (0x7FFF)
0   → 0x0000
-pi → -32767 (0x8001)
```

Xilinx CORDIC in `Scaled_Radians` mode with output width N maps:

```
pi  → +(2^(N-1) - 1) = +32767  for N=16
-pi → -(2^(N-1))     = -32768  for N=16
```

**Risk**: The Xilinx IP may produce -32768 for exactly -pi, while the existing CORDIC
RTL produces -32767.  This 1-LSB difference is acceptable for most applications but
should be confirmed in the testbench before integration.

**Risk**: The Xilinx IP output may be affected by `Round_Mode`.  Using `Truncate` vs
`Round_Pos_Inf` changes the LSB behavior.  Testbench should validate with a tolerance
of ±1 LSB initially, then tighten.

### NCO path — Mode A vs Mode B

The legacy `nco_phase_gen.v` uses 8-bit phase resolution (256-entry ROM).

**Mode A (recommended first)**: use `phase_acc[31:16]` as the 16-bit CORDIC phase input.

```
Effective phase resolution: 2*pi / 65536 radians/step
Legacy ROM resolution:      2*pi / 256   radians/step
Improvement: 256x finer phase resolution.
Not bit-exact to legacy ROM — regression tolerances must be updated.
```

**Mode B (legacy-match)**: use `{phase_acc[31:24], 8'h00}` as the 16-bit CORDIC phase.

```
Effective phase resolution: 2*pi / 256 radians/step (same as ROM)
Closest to bit-exact match with legacy behavior.
Does not exploit CORDIC precision.
Use only for bit-exact regression requirement.
```

---

## Latency and Valid Alignment Risks

The existing `frac_cfo_estimator.v` uses `CORDIC_LATENCY=15` to time the phase output
relative to the input frame.  If the Xilinx CORDIC IP produces a different latency, the
timing compensation must be updated.

**Action required after IP generation**:
1. Read `CONFIG.Latency` from the generated IP or `report_property` output.
2. If latency differs from 15, update `LATENCY` in `rtl/cordic_atan2_xilinx_wrapper.v`.
3. If the wrapper is integrated into `frac_cfo_estimator.v`, update `CORD_LAT` there.

The same applies to the NCO sin/cos CORDIC IP for `nco_phase_gen_xilinx_wrapper.v`.

**Note**: Vivado CORDIC v6.0 in `Fully_Pipelined` / `Maximum` pipelining mode with
INPUT_WIDTH=32, OUTPUT_WIDTH=16 typically produces a latency in the range 13–16 cycles.
The exact value depends on the number of CORDIC iterations required to achieve the target
output precision.

---

## What Was Run in WSL

- File inspection: all existing wrapper RTL, Tcl skeletons, and docs were read.
- `ip/` directory created for future XCI output.
- Scripts written and updated (no Vivado execution; WSL Vivado not available or not licensed).
- No XCI files generated.
- No simulation run for Step 36B (no new RTL to simulate).

---

## What Must Be Run in Windows Vivado

To complete Step 36B and enable the next integration step, the user must run the
following in **Vivado 2022.2** on the Windows side:

### Step 1: Property probe (required before create scripts)

```tcl
# In Vivado Tcl console with any project open:
source scripts/probe_cordic_ip_properties.tcl
```

Inspect:
- `reports/cordic_atan2_property_probe.txt` — verify `CONFIG.Functional_Selection`
  enum, `CONFIG.Phase_Format` enum, `CONFIG.Latency` read-back.
- `reports/cordic_rotate_property_probe.txt` — verify same for rotate mode.
- `reports/cordic_ip_properties.txt` — combined summary with key questions.

Update any `[TODO-*]` items in `create_cordic_atan2_ip.tcl` and
`create_cordic_sincos_ip.tcl` if property names differ from expected.

### Step 2: Create CORDIC atan2 IP

```tcl
source scripts/create_cordic_atan2_ip.tcl
```

Verify:
- `ip/cordic_atan2_xilinx/cordic_atan2_xilinx.xci` exists.
- `reports/cordic_atan2_ip_generation.log` shows no errors.
- `reports/cordic_atan2_ip_properties.txt` shows expected CONFIG values.
- `CONFIG.Latency` matches target of 15 cycles.

### Step 3: Create CORDIC sincos IP

```tcl
source scripts/create_cordic_sincos_ip.tcl
```

Verify:
- `ip/cordic_sincos_xilinx/cordic_sincos_xilinx.xci` exists.
- `reports/cordic_sincos_ip_generation.log` shows no errors.
- `reports/cordic_sincos_ip_properties.txt` shows Scale_Compensation applied.
- Latency matches target.

### Step 4: Optional DDS evaluation

```tcl
source scripts/probe_dds_ip_properties.tcl
# Review reports/dds_ip_analysis.txt for recommendation.
# If DDS is selected:
source scripts/create_dds_nco_ip.tcl
```

### Step 5: Collect artifacts

Copy back to the repository:
- `ip/cordic_atan2_xilinx/*.xci`
- `ip/cordic_sincos_xilinx/*.xci`
- (optional) `ip/dds_nco_xilinx/*.xci`
- `reports/cordic_atan2_property_probe.txt`
- `reports/cordic_rotate_property_probe.txt`
- `reports/cordic_atan2_ip_generation.log`
- `reports/cordic_sincos_ip_generation.log`
- Generated `.veo` or `.vho` instantiation templates

Report any property name mismatches or errors back into the project.

---

## Files Expected from Actual IP Generation

After running the Windows Vivado steps, the following files should appear:

```
ip/cordic_atan2_xilinx/
    cordic_atan2_xilinx.xci              — IP configuration
    cordic_atan2_xilinx_stub.v           — synthesis stub
    cordic_atan2_xilinx.veo              — Verilog instantiation template
    cordic_atan2_xilinx_sim_netlist.v    — simulation model

ip/cordic_sincos_xilinx/
    cordic_sincos_xilinx.xci
    cordic_sincos_xilinx_stub.v
    cordic_sincos_xilinx.veo
    cordic_sincos_xilinx_sim_netlist.v

reports/
    cordic_atan2_property_probe.txt
    cordic_rotate_property_probe.txt
    cordic_ip_properties.txt
    cordic_atan2_ip_generation.log
    cordic_atan2_ip_properties.txt
    cordic_sincos_ip_generation.log
    cordic_sincos_ip_properties.txt
    (optional) dds_ip_properties.txt
    (optional) dds_ip_analysis.txt
```

---

## What Should Be Committed to Git

**Commit**:
- `scripts/probe_cordic_ip_properties.tcl` (new)
- `scripts/create_cordic_atan2_ip.tcl` (updated)
- `scripts/create_cordic_sincos_ip.tcl` (updated)
- `scripts/probe_dds_ip_properties.tcl` (new, optional)
- `scripts/create_dds_nco_ip.tcl` (new, optional)
- `docs/step36B_cordic_nco_xilinx_ip_audit.md` (new)
- `md_files/36B_cordic_nco_xilinx_ip_audit_prompt.md` (new)

**Commit after Vivado generation** (separate commit or PR update):
- `ip/cordic_atan2_xilinx/*.xci`
- `ip/cordic_sincos_xilinx/*.xci`
- `reports/cordic_*` log and property files

**Do NOT commit**:
- `ip/cordic_atan2_xilinx/` output products (`.v`, `.vhd`, simulation netlists) —
  these are large generated files; only the `.xci` is version-controlled.
- `build/` scratch directories from probe scripts.
- Vivado journal and log files from batch runs.

Add to `.gitignore` if not already present:
```
ip/*/
!ip/*/*.xci
build/
*.jou
*.log
```

---

## Known Limitations

1. **Actual Xilinx CORDIC/DDS XCI may not be generated in this WSL step.**
   WSL Vivado is not available or not licensed for this step.
   All scripts are prepared for Windows Vivado execution.

2. **Property names may require Vivado `report_property` confirmation.**
   All `CONFIG.*` property names in the create scripts are marked as preliminary
   (`[TODO-*]` items) and must be verified by running `probe_cordic_ip_properties.tcl`
   in the actual target Vivado version (2022.2).
   Property names can vary between Vivado versions.

3. **No integration into `frac_cfo_estimator.v` or `timing_frac_cfo_top.v` in Step 36B.**
   The wrappers remain as standalone modules.  Integration is a future step.

4. **No board validation in Step 36B.**
   ZCU102 board programming and UART tests are out of scope.

5. **Existing synthesizable atan2 RTL and legacy NCO wrapper remain the verified paths.**
   `rtl/cordic_atan2.v` (15-stage synthesizable CORDIC) and
   `rtl/nco_phase_gen.v` (256-entry ROM) remain the production fallback until actual
   Xilinx IP is generated, integrated, simulated, and validated.

6. **Phase scaling must be confirmed with actual IP.**
   The 1-LSB difference at exactly ±pi, and the Scaled_Radians output mapping, must be
   verified against the testbench (`tb/cordic_atan2_xilinx_wrapper_tb.sv`) before
   claiming compatibility with the project's phase convention.

7. **Latency must be confirmed with actual IP.**
   The CORDIC IP latency in `Maximum` pipelining mode with the configured widths may
   differ from the target of 15 cycles.  Wrapper LATENCY parameters must be updated
   after confirmation.

8. **sin/cos tdata packing must be verified from the generated instantiation template.**
   The mapping of cos/sin to the lower/upper 16 bits of `m_axis_dout_tdata` must be
   read from the `.veo` file generated by Vivado, not assumed.

---

## Next Steps

**Immediate (Windows Vivado):**
1. Run `scripts/probe_cordic_ip_properties.tcl` in Vivado 2022.2.
2. Review generated reports; update any `[TODO-*]` items in create scripts.
3. Run `scripts/create_cordic_atan2_ip.tcl` and `scripts/create_cordic_sincos_ip.tcl`.
4. Confirm latency, phase scaling, and tdata packing from generated artifacts.
5. Commit XCI files and reports.

**Following steps (WSL/simulation):**
- Step 36B-2: Update wrappers with actual IP instantiation (replace placeholder blocks).
  Set `USE_BEHAVIORAL_MODEL=0` and instantiate `cordic_atan2_xilinx` / `cordic_sincos_xilinx`.
  Add XCI paths to simulation compile scripts.
  Run `tb/cordic_atan2_xilinx_wrapper_tb.sv` and `tb/nco_phase_gen_xilinx_wrapper_tb.sv`.

- Step 36C or later: Integrate verified CORDIC/NCO IP wrappers into
  `rtl/frac_cfo_estimator.v` and `rtl/timing_frac_cfo_top.v`.
  Update LATENCY parameters if needed.  Run full regression.

- Keep existing `rtl/cordic_atan2.v` and `rtl/nco_phase_gen.v` as fallback until
  IP-based wrappers pass the full regression suite.
