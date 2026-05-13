# Step 35A — Xilinx CORDIC atan2 Wrapper Preparation

## Objective

Prepare an IP-ready atan2 wrapper (`cordic_atan2_xilinx_wrapper.v`) as the future
drop-in replacement for the project's `cordic_atan2.v` when actual Xilinx CORDIC IP
(`cordic_v6_0`) is integrated.  Verify the wrapper interface, phase convention, and
latency timing with a deterministic standalone testbench.

---

## Why This Step Is Needed

The current project uses `rtl/cordic_atan2.v` as a synthesizable 15-stage CORDIC
pipeline for atan2 computation in `frac_cfo_estimator.v`.  While the existing module
is synthesizable RTL, the synthesis stub (`scripts/synth_stubs/cordic_atan2_stub.v`)
already declares it a `(* black_box *)` placeholder for the production build, with a
comment indicating replacement with Xilinx `cordic_v6_0` IP.

Step 35A creates the wrapper layer that will bridge the project interface to the
Xilinx IP when that IP is generated in a future step, without disturbing any existing
simulation or integration path.

---

## Existing cordic_atan2 Status

`rtl/cordic_atan2.v` is a **synthesizable** 15-stage CORDIC vectoring pipeline.
It does **not** use `$atan2`, `real`, `$itor`, or `$rtoi`.
It implements the full CORDIC algorithm with a fixed ATAN lookup table.

The synthesis stub (`scripts/synth_stubs/cordic_atan2_stub.v`) is used for OOC
synthesis checks (Steps 22, 24) and declares the module as a black box.

Existing passing testbench: `tb/cordic_atan2_tb.sv` — PASS: 38, FAIL: 0.

---

## Existing Interface and Phase Scaling

Inspected from `rtl/cordic_atan2.v`:

```
module cordic_atan2 #(
    parameter integer INPUT_WIDTH = 32,
    parameter integer PHASE_WIDTH = 16,
    parameter integer LATENCY     = 15
) (
    input  wire                       aclk,
    input  wire                       aresetn,
    input  wire [2*INPUT_WIDTH-1:0]   s_axis_cartesian_tdata,
    input  wire                       s_axis_cartesian_tvalid,
    output wire                       s_axis_cartesian_tready,
    output reg  [PHASE_WIDTH-1:0]     m_axis_dout_tdata,
    output reg                        m_axis_dout_tvalid
);
```

**tdata packing**: `s_axis_cartesian_tdata = {Q[31:0], I[31:0]}`
(lower half = I = X component, upper half = Q = Y component)

**Phase convention** (from ATAN table and header comments):
- Output: signed 16-bit
- `atan2(Q, I) / pi * 32767`
- `pi → +32767 (0x7FFF)`
- `0 → 0x0000`
- `-pi/2 → -16383 (0xC001)`
- `+pi/2 → +16383 (0x3FFF)`
- Range: `[-32767, +32767]` (signed Q15, pi maps to full-scale positive)

**Latency**: exactly 15 clock cycles from `s_axis_cartesian_tvalid` high to
`m_axis_dout_tvalid` high.  The pipeline is fully registered; `tready = 1` always.

---

## Proposed Xilinx CORDIC Replacement Strategy

The wrapper module `cordic_atan2_xilinx_wrapper.v` will serve as the future
integration point, with two build modes controlled by a parameter:

| Mode | Parameter | Use |
|------|-----------|-----|
| Simulation | `USE_BEHAVIORAL_MODEL=1` | `$atan2` behavioral model with shift-register pipeline |
| Production | `USE_BEHAVIORAL_MODEL=0` | Placeholder for `cordic_v6_0` IP instantiation |

The module exports the **identical interface** as `cordic_atan2.v`, enabling
drop-in replacement in `frac_cfo_estimator.v` (instance `u_cordic`).

Integration path (future step):
1. Change `frac_cfo_estimator.v` line 61: replace `cordic_atan2` with
   `cordic_atan2_xilinx_wrapper`.
2. Set `USE_BEHAVIORAL_MODEL=0` for production synthesis.
3. Populate the `gen_ip_placeholder` block with the actual `cordic_v6_0` instance.

---

## Wrapper Interface

```verilog
module cordic_atan2_xilinx_wrapper #(
    parameter integer INPUT_WIDTH          = 32,
    parameter integer PHASE_WIDTH          = 16,
    parameter integer LATENCY             = 15,
    parameter integer USE_BEHAVIORAL_MODEL = 1
) (
    input  wire                       aclk,
    input  wire                       aresetn,
    input  wire [2*INPUT_WIDTH-1:0]   s_axis_cartesian_tdata,
    input  wire                       s_axis_cartesian_tvalid,
    output wire                       s_axis_cartesian_tready,
    output reg  [PHASE_WIDTH-1:0]     m_axis_dout_tdata,
    output reg                        m_axis_dout_tvalid
);
```

Identical to `cordic_atan2.v` except for the added `USE_BEHAVIORAL_MODEL` parameter.

---

## Simulation Behavior (USE_BEHAVIORAL_MODEL=1)

Under `// synthesis translate_off / translate_on` guards:

1. The current input bus is decomposed into signed I and Q components.
2. `$atan2(Q, I)` is computed in double-precision real.
3. The result is scaled: `phase = $rtoi(atan2(Q,I)/pi * 32767)`.
4. The phase value is inserted into `beh_data_pipe[0]`; `s_valid` into `beh_valid_pipe[0]`.
5. A 15-stage shift register propagates both through the pipeline.
6. `m_axis_dout_tdata <= beh_data_pipe[14]` and `m_axis_dout_tvalid <= beh_valid_pipe[14]`
   read the registered value from the previous clock, so output valid appears **exactly
   15 cycles** after input valid — matching the existing `cordic_atan2.v` behavior.

The behavioral model reads `synthesis translate_off/on` guarded code; Vivado xsim
ignores these directives and simulates the code normally.

---

## Intended Future Xilinx IP Configuration

**Target IP**: Xilinx CORDIC v6.0 (`cordic_v6_0`)

| Property | Value | Notes |
|----------|-------|-------|
| Functional_Selection | Translate (Vectoring) | Computes atan2(Y,X) |
| Architectural_Configuration | Fully_Pipelined | Fixed latency |
| Pipelining_Mode | Maximum | Achieve LATENCY=15 |
| Input_Width | 32 | Per component (I or Q) |
| Output_Width | 16 | Phase bits |
| Round_Mode | Truncate | Match $rtoi behavior |
| ARESETN | true | Active-low reset |
| Phase_Format | Radians | Must verify pi -> +32767 scaling |

**Verification required before production use**:
- Confirm phase scaling: Xilinx CORDIC output in Translate mode should give
  pi → (2^(PHASE_WIDTH-1) - 1) = 32767 for PHASE_WIDTH=16.  Verify with the
  same test vectors as `cordic_atan2_xilinx_wrapper_tb.sv` but with `USE_BEHAVIORAL_MODEL=0`.
- Confirm tdata packing order (Q upper, I lower) matches Xilinx IP expectations.
- Confirm latency is exactly 15 cycles for the chosen configuration.
- Confirm `tready` behavior (always-1 for fully pipelined mode).
- Confirm quadrant correctness for all four quadrants.
- Confirm zero-vector behavior (atan2(0,0) — Xilinx may define differently).

TCL generation skeleton: `scripts/create_cordic_atan2_ip.tcl` (preliminary, needs
verification against actual IP Catalog properties).

---

## Testbench Scenarios

File: `tb/cordic_atan2_xilinx_wrapper_tb.sv`

| Group | Name | I (X) | Q (Y) | Expected Phase |
|-------|------|--------|--------|----------------|
| T1 | reset_defaults | — | — | m_valid=0, tready=1 |
| T2 | positive_x_zero_y | +100000 | 0 | 0 |
| T3 | zero_x_positive_y | 0 | +100000 | +16383 (~pi/2) |
| T4 | negative_x_zero_y | -100000 | 0 | +32767 (+pi) |
| T5 | zero_x_negative_y | 0 | -100000 | -16383 (~-pi/2) |
| T6 | quadrant_I | +60000 | +60000 | +8191 (~pi/4) |
| T7 | quadrant_II | -60000 | +60000 | +24575 (~3pi/4) |
| T8 | quadrant_III | -60000 | -60000 | -24575 (~-3pi/4) |
| T9 | quadrant_IV | +60000 | -60000 | -8191 (~-pi/4) |
| T10 | small_values | 50, 100 | 50, -50 | ~8191, ~-8191 |
| T11 | large_values | 2e9, -1.5e9 | 1e9, 1.5e9 | ~4836, ~24575 |
| T12 | back_to_back_valids | 6 consecutive samples | verified in order |
| T13 | zero_vector | 0 | 0 | 0 |
| T14 | pipeline_latency | +300000 | 0 | m_valid=0 at T+14, m_valid=1 at T+15 |

Tolerance: `PHASE_TOL=2` LSBs (wrapper and golden model use the same `$atan2` formula).

---

## Simulation Command

```bash
bash scripts/run_cordic_atan2_xilinx_wrapper_sim.sh
```

Compiles `rtl/cordic_atan2_xilinx_wrapper.v` and `tb/cordic_atan2_xilinx_wrapper_tb.sv`
only. Does **not** include `rtl/cordic_atan2.v` (avoids module-name conflict).
Logs saved to `logs/cordic_atan2_xilinx_wrapper_xvlog.log`,
`logs/cordic_atan2_xilinx_wrapper_xelab.log`,
`logs/cordic_atan2_xilinx_wrapper_xsim.log`.

---

## Simulation Result

```
PASS: 35   FAIL: 0
CI GATE: PASSED
```

All 14 test groups passed (35 individual checks). Zero failures.
Log: `logs/cordic_atan2_xilinx_wrapper_xsim.log`

---

## Known Limitations

1. **Actual Xilinx CORDIC IP (XCI) is not integrated in Step 35A.**
   The wrapper uses a behavioral `$atan2` model under `synthesis translate_off` for
   simulation.  The `gen_ip_placeholder` branch holds zeros until a real
   `cordic_v6_0` instance is added.

2. **USE_BEHAVIORAL_MODEL=1 is NOT synthesizable.**
   The `synthesis translate_off` guards prevent Vivado synthesis from seeing the
   `real` / `$atan2` code, but the output registers are undriven in synthesis with
   this setting.  Use `USE_BEHAVIORAL_MODEL=0` for any synthesis target.

3. **Integration into timing_frac_cfo_top / frac_cfo_estimator is NOT done.**
   The wrapper is standalone in this step.  `frac_cfo_estimator.v` still
   instantiates `cordic_atan2` (the existing synthesizable CORDIC RTL).

4. **Board validation is not part of Step 35A.**
   No ZCU102 testing was performed.

5. **TCL IP generation script is preliminary.**
   `scripts/create_cordic_atan2_ip.tcl` has TODO items for exact property names
   and phase-scaling verification.

---

## Next Steps

- **Step 35A-2**: Generate actual Xilinx CORDIC IP via `scripts/create_cordic_atan2_ip.tcl`
  in Vivado, verify XCI compiles, verify phase output matches the testbench expected
  values with `USE_BEHAVIORAL_MODEL=0`.
- **Step 35B** (parallel lane): NCO phase generator replacement preparation.
- **Step 36**: Integrate `cordic_atan2_xilinx_wrapper` into `frac_cfo_estimator.v`
  after Step 35A-2 and Step 35B are complete.
