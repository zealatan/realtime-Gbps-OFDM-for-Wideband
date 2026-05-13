# Step 35B — NCO sin/cos Replacement Preparation

## Objective

Prepare a Xilinx-IP-compatible wrapper and testbench for the fractional CFO path's NCO
sin/cos generation, without modifying the existing top-level integration.  The wrapper
provides an interface-compatible drop-in for `nco_phase_gen.v` that can be swapped to a
real Xilinx CORDIC rotate-mode or DDS Compiler IP in a future step.

## Why this step is needed

The fractional CFO correction path requires a sin/cos generator driven by a controlled
phase accumulator.  The existing `rtl/nco_phase_gen.v` was already upgraded from a
`$sin`/`$cos` behavioral model (Step 20) to a 256-entry Q1.15 ROM in a prior step.  The
ROM is technically synthesizable as LUTRAM, but it is not the production-optimal
implementation for an FPGA device.  Production targets are:

- Xilinx CORDIC v6.0 in rotate (translate) mode — FPGA-optimised iterative algorithm,
  configurable pipeline depth, and automatic gain compensation.
- Xilinx DDS Compiler v6.0 — dedicated NCO with integrated phase accumulator.

Step 35B creates the wrapper shell and a validated testbench so that, when real IP is
generated, the swap is mechanical (change one parameter and instantiate the IP).

## Existing behavioral nco_phase_gen status

`rtl/nco_phase_gen.v` is **unchanged** by Step 35B.

The module passed its own testbench (`tb/nco_phase_gen_tb.sv`) with:
- PASS: 38, FAIL: 0, CI GATE: PASSED (per prior step history)

The existing module uses a 256-entry Q1.15 ROM synthesizable as LUTRAM.  It is the
reference against which the wrapper is tested in T14.

## Existing interface and phase scaling

```
module nco_phase_gen #(
    parameter integer NCO_PHASE_WIDTH     = 32,  // phase accumulator width
    parameter integer CORDIC_PHASE_WIDTH  = 16,  // (unused in ROM path; reserved for CORDIC)
    parameter integer ROTATOR_COEFF_WIDTH = 16,  // sin/cos output width
    parameter integer LATENCY             = 15   // pipeline depth
)(
    input  wire aclk, aresetn,
    input  wire load_step,
    input  wire signed [31:0] step_word,
    input  wire phase_reset,
    input  wire enable,
    output wire signed [15:0] sin_out, cos_out,
    output wire sincos_valid,
    output wire [31:0] phase_acc
);
```

**Phase convention:**
- 32-bit unsigned accumulator.  The full 2π cycle spans exactly 2^32 accumulator counts.
- `phase_acc[31:24]` (top 8 bits) selects one of 256 ROM entries.
- Phase accumulates on each `enable` pulse with `!phase_reset`.
- Output sin/cos corresponds to the **pre-accumulation** phase (the value of `phase_acc`
  at the start of the cycle, before `+= step_word`).  This is a consequence of NBA
  semantics in the always block.
- Natural 32-bit unsigned wrap is equivalent to a 2π phase wrap.

**Sin/cos scaling (Q1.15, unsigned-stored):**

| phase_acc      | ROM index | cos          | sin           |
|----------------|-----------|--------------|---------------|
| 0x0000_0000    | 0         | +32767 ≈ +1  | 0             |
| 0x4000_0000    | 64        | 0            | +32767 ≈ +1   |
| 0x8000_0000    | 128       | -32767 ≈ -1  | 0             |
| 0xC000_0000    | 192       | 0            | -32767 ≈ -1   |

Stored as 16-bit two's complement.  Positive values: 0x0001..0x7FFF.
Negative values: 0xFFFF..0x8001.  Maximum magnitude: ±32767.

## Existing latency and valid behavior

```
valid_pipe[0]      <= enable && !phase_reset;    // stage 0
valid_pipe[k]      <= valid_pipe[k-1];            // stages 1..LATENCY-1
sincos_valid_r     <= valid_pipe[LATENCY-1];      // output register
```

Total latency: **LATENCY clock cycles** from the `enable` posedge to `sincos_valid`.

With default LATENCY=15: output appears 15 posedges after the enable pulse.

`phase_reset` clears `phase_acc_r` immediately and also invalidates the pipeline entry
for that cycle (`valid_pipe[0] = 0` when `phase_reset=1`).  Previous in-flight pipeline
tokens are NOT flushed; they drain naturally.

## Production replacement options

### Option A — Xilinx CORDIC v6.0 rotate (translate) mode (RECOMMENDED)

Keep the existing 32-bit phase accumulator in RTL.  Feed the top 16 bits as a signed
Q1.15 phase to the CORDIC IP:

```
cordic_phase_in = signed(phase_acc_r[31:16])
```

This gives the mapping:
- 0x0000 → 0 rad
- 0x4000 → +π/2
- 0x8000 → −π (two's complement, same as +π at the boundary)
- 0xC000 → −π/2

The CORDIC IP outputs {Y=sin, X=cos} after LATENCY pipeline stages.

**Pros:**
- Phase accumulator stays in RTL — existing load_step/phase_reset/enable interface
  is unchanged.
- CORDIC latency is configurable and predictable.
- Scale-compensation mode eliminates the CORDIC gain factor automatically.
- Direct AXI-Stream handshake maps naturally to `enable`/`sincos_valid`.

**Cons:**
- Phase scaling step (top 16 bits) reduces effective phase resolution to 16 bits
  for CORDIC input (the lower 16 bits of the accumulator are discarded).
- AXI-S back-pressure must be handled if IP has flow control enabled.

### Option B — Xilinx DDS Compiler v6.0

Use DDS Compiler as both the phase accumulator and the sin/cos generator.  Drive the
phase increment input with `step_word`.

**Pros:**
- Production-grade, highly optimised NCO + sin/cos pipeline.
- Supports programmable frequency offset.

**Cons:**
- The phase accumulator is internal to the IP — dynamic `phase_reset` and
  non-contiguous `enable` gating require additional handling.
- The interface differs significantly from the existing `nco_phase_gen.v` interface,
  requiring non-trivial changes to `complex_rotator.v` or `timing_frac_cfo_top.v`.
- Less transparent than CORDIC for debugging.

## Recommended replacement strategy

**CORDIC rotate mode (Option A)** is recommended for this project because:

1. The existing `nco_phase_gen.v` explicitly reserves `CORDIC_PHASE_WIDTH=16`, which
   matches the 16-bit CORDIC phase input convention.
2. Phase accumulator behavior (load_step, phase_reset, enable, non-contiguous valid) is
   cleanly separated from the sin/cos computation — CORDIC replaces only the ROM lookup.
3. The wrapper's `USE_BEHAVIORAL_MODEL=0` path documents the exact CORDIC instantiation
   hook with correct port names and scaling notes.
4. Step 35A (CORDIC atan2 wrapper) already introduces CORDIC IP infrastructure in a
   parallel branch; the same IP family can be reused here.

## Wrapper interface

`rtl/nco_phase_gen_xilinx_wrapper.v` is **pin-compatible** with `nco_phase_gen.v`:

```
module nco_phase_gen_xilinx_wrapper #(
    parameter integer NCO_PHASE_WIDTH      = 32,
    parameter integer CORDIC_PHASE_WIDTH   = 16,
    parameter integer ROTATOR_COEFF_WIDTH  = 16,
    parameter integer LATENCY              = 15,
    parameter integer USE_BEHAVIORAL_MODEL = 1
)(
    input  wire aclk, aresetn,
    input  wire load_step,
    input  wire signed [31:0] step_word,
    input  wire phase_reset,
    input  wire enable,
    output wire signed [15:0] sin_out, cos_out,
    output wire sincos_valid,
    output wire [31:0] phase_acc
);
```

The only addition is `USE_BEHAVIORAL_MODEL` which is not a port.

## Simulation behavior

**`USE_BEHAVIORAL_MODEL=1` (default):**

The wrapper uses an identical 256-entry Q1.15 ROM and identical pipeline to
`nco_phase_gen.v`.  Outputs are **bit-identical** to the reference module (verified by T14).

This is the intermediate synthesizable path.  It is marked clearly as non-production in
the RTL comments and is intended only for interface validation and simulation.

**`USE_BEHAVIORAL_MODEL=0`:**

The wrapper exposes the phase accumulator and contains a commented scaffold for future
Xilinx CORDIC IP instantiation.  The `sin_out`/`cos_out` outputs are zero and
`sincos_valid` propagates correctly.  This mode is for IP integration staging only.

## Intended future Xilinx CORDIC/DDS IP configuration

For CORDIC v6.0 rotate mode:

| Property                  | Value            |
|---------------------------|------------------|
| Functional Selection      | Translate        |
| Phase Format              | Radians          |
| Input Width (phase)       | 16 bits          |
| Output Width (X/Y)        | 16 bits          |
| Pipelining Mode           | Maximum          |
| Scale Compensation        | Enabled          |
| AXI4-Stream               | Enabled          |
| ARESETN                   | Enabled          |

Phase input: `signed(phase_acc_r[31:16])` — top 16 bits of 32-bit accumulator.

The TCL helper `scripts/create_cordic_sincos_ip.tcl` contains a preliminary IP creation
script with all required properties noted.  It is **not verified** and must be reviewed
against the target Vivado version before use.

## Testbench scenarios

File: `tb/nco_phase_gen_xilinx_wrapper_tb.sv`

| Group | Name                     | What it checks                                        |
|-------|--------------------------|-------------------------------------------------------|
| T1    | reset_defaults           | After reset: acc=0, valid=0, outputs=0                |
| T2    | phase_zero               | step=0 holds phase at 0; cos≈+32767, sin≈0            |
| T3    | quarter_cycle            | phase=0x40000000; cos≈0, sin≈+32767                   |
| T4    | half_cycle               | phase=0x80000000; cos≈-32767, sin≈0                   |
| T5    | three_quarter_cycle      | phase=0xC0000000; cos≈0, sin≈-32767                   |
| T6    | small_positive_step      | acc increments correctly; spot-check 4 samples        |
| T7    | negative_step            | negative step_word wraps accumulator downward         |
| T8    | wraparound_positive      | step near 2^31; unsigned wrap across 0                |
| T9    | wraparound_negative      | step=-1; acc wraps 0→0xFFFFFFFF                       |
| T10   | phase_reset_priority     | phase_reset overrides enable; acc returns to 0        |
| T11   | back_to_back_valids      | 8 consecutive enables; count and spot-check outputs   |
| T12   | valid_gating             | interleaved enable/disable; 3 valids in 6 cycles      |
| T13   | large_step               | step=0x40000000; full quarter-cycle rotation per beat |
| T14   | compare_existing_model   | wrapper output bit-identical to nco_phase_gen (24 checks) |

Tolerance: 1 LSB for golden-model comparisons.  T14 uses bit-exact comparison against
the nco_phase_gen reference instance — any difference is a failure.

## Simulation command

```bash
bash scripts/run_nco_phase_gen_xilinx_wrapper_sim.sh
```

The script compiles `rtl/nco_phase_gen.v`, `rtl/nco_phase_gen_xilinx_wrapper.v`, and
`tb/nco_phase_gen_xilinx_wrapper_tb.sv` with xvlog/xelab/xsim, saves logs to
`logs/nco_phase_gen_xilinx_wrapper_xsim.log`, and exits non-zero on any failure.

## Simulation result

**PASS: 88   FAIL: 0   CI GATE: PASSED**

Verified with Vivado 2022.2 / xsim.

### Testbench golden-model fix (Step 35B fix)

The initial run produced PASS: 84, FAIL: 4 (T6 and T7 failures).

**Root cause:** The original golden model used the full 32-bit phase value
(`2*pi * acc / 2^32`) to compute expected sin/cos.  The existing `nco_phase_gen` uses
only the top 8 bits of the accumulator (`acc[31:24]`) as a 256-entry ROM index.

Consequences:
- T6 used `step_word = 0x00010000`.  Phase values 0x00010000..0x00030000 give
  `acc[31:24] = 0`, so all outputs are cos=32767, sin=0.  The continuous-phase golden
  model incorrectly expected non-zero sin values (≈3 and ≈9 LSB).
- T7 used `step_word = -0x10000`.  Phase 0xFFFF0000 gives `acc[31:24] = 0xFF = 255`,
  mapping to ROM[255]: cos=32757, sin=−804.  The continuous-phase golden model
  incorrectly expected near-zero sin (≈−3 LSB for phase ≈2*pi).

**Fix:** Changed the golden model angle formula from
`2*pi * real(acc) / 4294967296.0` to `2*pi * real(acc[31:24]) / 256.0` in both
`gold_cos()` and `gold_sin()`.  No RTL changes were made.

**Key implication:** Phase steps smaller than 0x01000000 (1/256 of the full cycle) do
not change the ROM index and produce no change in sin/cos output.  This is the defined
behavior of the legacy 8-bit ROM design.  A future Xilinx CORDIC replacement uses
16-bit phase resolution and will require a separate golden model policy.

## Known limitations

1. **Actual Xilinx CORDIC IP XCI is not integrated.** No XCI file has been generated.
   The wrapper uses the same ROM as the existing module for simulation.

2. **Current wrapper uses 256-entry ROM** (same as `nco_phase_gen.v`) when
   `USE_BEHAVIORAL_MODEL=1`.  This is synthesizable as LUTRAM but is not the target
   production implementation.

3. **Integration into `timing_frac_cfo_top.v` or `frac_cfo_frame_corrector_top.v` is
   not done in Step 35B.**  The wrapper is standalone only.

4. **Board validation is not part of Step 35B.**  No ZCU102 hardware tests are performed.

5. **CORDIC TCL script is preliminary** — property names have not been verified against
   the specific Vivado version in this project.  Do not run it without review.

6. **CORDIC gain compensation** — if Scale Compensation is not enabled in the IP, the
   output magnitude will be ~1.6468× the intended value, requiring a post-CORDIC
   correction multiplier.

## Next steps

**Step 35B-2 (recommended):**
1. Generate `cordic_v6_0` XCI using `scripts/create_cordic_sincos_ip.tcl` in Vivado.
2. Verify CORDIC latency; update `LATENCY` parameter if different from 15.
3. Set `USE_BEHAVIORAL_MODEL=0` in the wrapper and instantiate the real IP.
4. Re-run `run_nco_phase_gen_xilinx_wrapper_sim.sh` with the XCI included in the
   compile list.
5. Confirm T14 passes against the reference `nco_phase_gen.v` to within 1–2 LSB
   (CORDIC has ~0.5 LSB RMS error vs. ideal sin/cos at 16-bit output width).

**Integration step (after Step 35A is complete):**
- Replace `nco_phase_gen` with `nco_phase_gen_xilinx_wrapper` in
  `rtl/complex_rotator.v` or `rtl/timing_frac_cfo_top.v`.
- Re-run the full fractional CFO testbench to confirm end-to-end correctness.
