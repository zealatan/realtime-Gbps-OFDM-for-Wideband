# Step 23 Prompt — Replace Simulation-Only CORDIC/NCO with Synthesizable RTL

## Context

Step 22 OOC synthesis passed (stubs for cordic_atan2 and nco_phase_gen).
Step 21 integration test: PASS=176, FAIL=0.

The two behavioral simulation-only modules are:
- `rtl/cordic_atan2.v` — uses `real`, `$atan2`, `$itor`, `$rtoi`
- `rtl/nco_phase_gen.v` — uses `real`, `$sin`, `$cos`, `$itor`, `$rtoi`

## Requirements

1. Replace `rtl/cordic_atan2.v` with synthesizable 15-stage CORDIC vectoring pipeline:
   - No `real`, `$atan2`, `$itor`, `$rtoi`
   - Same module port signature (INPUT_WIDTH=32, PHASE_WIDTH=16, LATENCY=15)
   - AXI-Stream input {Q[31:0], I[31:0]}, output phase[15:0]
   - Convention: 0x7FFF = +π, 0x4000 = +π/2, 0x0000 = 0, 0xC000 = -π/2
   - ATAN table: atan(2^-k)/π × 32767 for k=0..14
   - Quadrant preprocessing for full ±π range
   - Fully pipelined (tready always 1)

2. Replace `rtl/nco_phase_gen.v` with synthesizable ROM-based NCO:
   - No `real`, `$sin`, `$cos`, `$itor`, `$rtoi`
   - Same module port signature (NCO_PHASE_WIDTH=32, ROTATOR_COEFF_WIDTH=16, LATENCY=15)
   - 256-entry sin/cos ROM, index = phase_acc[31:24]
   - `initial` block initialization (synthesizes to LUTRAM in Vivado)
   - Same phase accumulator + pipeline structure as behavioral model

3. Preserve all existing testbenches and simulation scripts.
   - Testbench golden models (`$atan2`, `$sin`, `$cos`) remain in testbenches (simulation only).
   - Add ±4 LSB tolerance to cordic_atan2_tb phase checks (CORDIC quantization).
   - Add ±1 LSB tolerance to nco_phase_gen_tb coefficient checks (ROM rounding vs float truncation).

4. Re-run integration test: must achieve PASS=176, FAIL=0.

5. WSL-only step. No Windows Vivado, no AXI-Lite, no DMA, no FFT, no integer CFO.

## Key Design Rules

- CORDIC stage decisions (`d_k = sign(y_k)`) must be declared as combinatorial `wire`
  OUTSIDE the `always @(posedge aclk)` block. Wire declarations inside always blocks are
  illegal Verilog.
- CORDIC convention: d=1 if y≥0, d=0 if y<0; `d = ~y[MSB]`
  - x' = x + (d ? (y>>>k) : -(y>>>k))
  - y' = y - (d ? (x>>>k) : -(x>>>k))
  - z' = z - (d ? -ATAN_k : ATAN_k)  [adds d×ATAN_k to z]
- Quadrant preprocessing: if (I<0) OR (I=0 AND Q<0): negate both I and Q, set z_init = ±π
  - z_init = +π if Q≥0 (Q2), z_init = -π if Q<0 (Q3 or negative imaginary axis)
- NCO: pre-accumulation phase — sample k uses phase_acc BEFORE the k-th enable increment.
  The LUT is read from phase_acc_r BEFORE the accumulator updates (NBA semantics).

## Result

- `rtl/cordic_atan2.v`: PASS (38 checks, 0 fails in unit test)
- `rtl/nco_phase_gen.v`: PASS (33 checks, 0 fails in unit test)
- Integration `frac_cfo_frame_corrector_top_tb`: PASS=176, FAIL=0, CI GATE: PASSED
- Both modules are synthesizable (no `real` or system math functions)
