# Step 34 — FFT256 Frontend Wrapper and Behavioral FFT Integration for Meyr Estimator

## Mandatory archival rule

Before modifying any file, save this entire prompt verbatim as:

md_files/34_fft256_frontend_behavioral_integration_prompt.md

If the md_files/ directory does not exist, create it first.

## Working directory

/home/zealatan/RTL_SYNC

## Important workflow separation

This project uses a split workflow:

WSL/Linux side:
- Claude Code works here.
- Source/documentation editing is done here.
- RTL/testbench/simulation work is done here.
- Vivado xsim simulation may be run from WSL if the existing project flow supports it.

Windows side:
- The user manually pulls updated code from Git.
- The user manually uses Vivado/Vitis for synthesis/implementation/board execution.
- The user manually programs the ZCU102 board.
- The user manually runs UART/COM tests.

For this step:
- Do not run Windows Vivado.
- Do not run Vitis.
- Do not access COM5.
- Do not modify board/Vitis host files.
- Do not claim any board result.

This Step 34 is an RTL simulation / architecture-interface step only.

## Context

Step 29I is complete and passed on ZCU102.

Step 30 is complete:
- Meyr-based integer CFO / PSS-SSS architecture specified.
- Correct C-reference formulas documented:
  term1[j] = PSS_FFT[j] * conj(SSS_FFT[j])
  term2[j] = mU[j + CP_LEN] * conj(goldU[j + CP_LEN])
  intCFO = peakIndexMeyr - 255

Step 31 is complete:
- rtl/meyr_integer_cfo_core.v implemented.
- Direct 511-lag Meyr correlation verified.
- PASS: 32, FAIL: 0, CI GATE: PASSED.

Step 32 is complete:
- rtl/meyr_pss_sss_product_gen.v implemented.
- rtl/meyr_term2_ref_rom.v implemented with synthetic fallback ROM.
- rtl/meyr_integer_cfo_freq_estimator_top.v implemented.
- Product generator PASS: 13, FAIL: 0.
- Estimator top PASS: 32, FAIL: 0.
- CI GATE: PASSED.

Step 33 is complete as an audit:
- Real mU/goldU source is external.
- mU/goldU are float* struct fields defined in pluto.h, which is not present in this repo.
- Real mU/goldU-derived term2 ROM remains pending.
- Synthetic PRNG fallback remains the verified simulation path.
- scripts/generate_meyr_term2_rom.py was created as a template generator for future external mU/goldU dumps.

Now Step 34 should add an FFT256 frontend interface and behavioral simulation model, without adding Xilinx FFT IP and without board integration.

## Step 34 goal

Create and verify a simulation-oriented FFT256 frontend path that can feed PSS_FFT and SSS_FFT streams into the existing Step 32 Meyr frequency-domain estimator.

The goal is not production FFT RTL yet.

The goal is to define and verify:

1. Time-domain PSS/SSS symbol input interface.
2. FFT256 frontend wrapper interface.
3. FFT output bin order convention.
4. Streaming format into meyr_integer_cfo_freq_estimator_top.
5. A behavioral FFT model for deterministic simulation only.
6. End-to-end simulation:
   synthetic time-domain PSS/SSS symbols
   -> behavioral FFT256 frontend
   -> PSS_FFT/SSS_FFT stream
   -> term1 product generator
   -> synthetic term2 ROM
   -> Meyr core
   -> peak_index / intCFO

Important:
- Do not add Xilinx FFT IP.
- Do not implement optimized production FFT RTL.
- Do not modify board wrapper.
- Do not modify Vitis host files.
- Continue to use synthetic term2 fallback because real mU/goldU is pending from Step 33.
- Document this limitation clearly.

## Files to inspect first

Inspect these files before editing:

rtl/meyr_integer_cfo_core.v
rtl/meyr_pss_sss_product_gen.v
rtl/meyr_term2_ref_rom.v
rtl/meyr_integer_cfo_freq_estimator_top.v
tb/meyr_integer_cfo_core_tb.sv
tb/meyr_integer_cfo_freq_estimator_top_tb.sv
docs/step30_meyr_integer_cfo_pss_sss_architecture.md
docs/step31_meyr_integer_cfo_core.md
docs/step32_meyr_product_generator_real_term2.md
docs/step33_real_mU_goldU_term2_reference_audit.md
ai_context/current_status.md
README.md

Search for existing FFT or DFT related files:

find . -type f | grep -Ei "fft|dft|ifft|ofdm|symbol|extract|meyr|cfo"
grep -R "FFT\|fft\|DFT\|dft\|IFFT\|ifft\|OFDM\|symbol" -n rtl tb docs scripts ref . 2>/dev/null | head -300

Also inspect existing script style:

ls scripts
find scripts -maxdepth 1 -type f -name "run_*_sim.sh" -print

## Key design stance

This step should not introduce Xilinx FFT IP.

Use one of the following simulation-friendly approaches:

Preferred approach:
- Create a SystemVerilog behavioral FFT/DFT model inside the testbench or as a simulation-only module.
- Use real-valued math only in the testbench or simulation-only model, not in synthesizable RTL.
- Keep production RTL wrappers clean and replaceable.

Acceptable approach:
- Create rtl/fft256_frontend_wrapper.v as a synthesizable interface skeleton with no real FFT implementation, and create tb/fft256_behavioral_model.sv for simulation.
- The wrapper/interface defines how a future custom FFT or Xilinx FFT IP will connect.

Avoid:
- Adding Xilinx FFT IP.
- Adding vendor-specific encrypted simulation models.
- Over-optimizing FFT.
- Claiming synthesizable FFT implementation if behavioral real-number code is used.

## Required architecture

Create a clean frontend path:

time-domain PSS samples
time-domain SSS samples
-> FFT256 behavioral frontend
-> PSS_FFT stream and SSS_FFT stream
-> meyr_integer_cfo_freq_estimator_top
-> intCFO

Recommended hierarchy for Step 34:

1. Simulation-only FFT model:
   tb/fft256_behavioral_model.sv

2. FFT frontend wrapper/interface:
   rtl/fft256_dual_symbol_frontend.v

3. Top-level simulation integration wrapper:
   rtl/meyr_integer_cfo_fft_frontend_top.v

4. Testbench:
   tb/meyr_integer_cfo_fft_frontend_top_tb.sv

If repository conventions prefer different names, keep names clear and document them.

## FFT bin order convention

Step 34 must explicitly define and test FFT bin order.

Use natural order unless existing project convention says otherwise:

- Input time samples n = 0..255.
- Output frequency bins k = 0..255.
- Bin k=0 is DC.
- Positive frequencies are k=1..127.
- Negative frequencies are k=128..255 in natural FFT order.
- No fftshift is applied.

Document this in comments and docs.

If a different convention is needed to match ref/receiver.c, document it and use that convention consistently.

## Scaling convention

Define simple scaling for behavioral FFT:

Option A:
- Use unnormalized DFT:
  X[k] = sum_{n=0}^{255} x[n] * exp(-j*2*pi*k*n/256)

Option B:
- Use normalized DFT:
  X[k] = (1/256) * sum ...

Recommended for Step 34:
- Use unnormalized DFT in the behavioral model unless existing C reference uses normalized FFT.
- Then scale/truncate into IQ_WIDTH or PROD_WIDTH carefully for the estimator input.

Because the current estimator top expects IQ_WIDTH=16 PSS_FFT/SSS_FFT inputs, Step 34 must define a deterministic quantization from behavioral FFT output to signed 16-bit.

Recommended:
- Generate small-amplitude time-domain vectors so FFT outputs remain within signed 16-bit.
- Saturate or round to int16 if needed.
- Document the behavior in the testbench.

## Critical simplification for deterministic testing

Because the real mU/goldU term2 ROM is pending, and because Step 34 is about FFT frontend integration, the testbench may construct time-domain PSS/SSS symbols that produce known frequency-domain vectors compatible with the synthetic term2 fallback.

A robust deterministic strategy:

1. Use the same synthetic term2 reference pattern as Step 32.
2. Choose desired integer shift s.
3. Construct desired frequency-domain PSS_FFT and SSS_FFT such that:
   term1[k] = PSS_FFT[k] * conj(SSS_FFT[k])
   becomes a shifted version of synthetic term2.
4. Use behavioral IFFT in the testbench to generate time-domain PSS and SSS symbols.
5. Feed those time-domain symbols to the FFT frontend.
6. The frontend FFT should reconstruct PSS_FFT and SSS_FFT within quantization limits.
7. The estimator should detect intCFO = s.

If implementing IFFT in the testbench is too much for this step:
- It is acceptable to create a simpler "frequency-to-FFT-output bypass mode" for the integration top, but the preferred Step 34 objective is to test the behavioral FFT path with time-domain inputs.
- If bypass mode is used, document that true time-domain FFT verification is pending.

Do not fake an FFT test. Be explicit.

## Required RTL module: fft256_dual_symbol_frontend

Create:

rtl/fft256_dual_symbol_frontend.v

Purpose:
- Define a clean wrapper/interface for a future FFT256 frontend.
- For now, this may be a structural shell that is driven by a simulation-only behavioral model in the testbench.
- It should establish the streaming protocol and bin order.

Recommended interface:

module fft256_dual_symbol_frontend #(
    parameter FFT_LEN = 256,
    parameter IQ_WIDTH = 16
)(
    input  wire                         aclk,
    input  wire                         aresetn,

    input  wire                         start,

    input  wire                         s_valid,
    output wire                         s_ready,
    input  wire                         s_symbol_sel,
    input  wire [7:0]                   s_index,
    input  wire signed [IQ_WIDTH-1:0]   s_i,
    input  wire signed [IQ_WIDTH-1:0]   s_q,

    output reg                          m_valid,
    input  wire                         m_ready,
    output reg                          m_symbol_sel,
    output reg [7:0]                    m_index,
    output reg signed [IQ_WIDTH-1:0]    m_i,
    output reg signed [IQ_WIDTH-1:0]    m_q,

    output reg                          busy,
    output reg                          done,
    output reg                          error
);

symbol_sel:
- 0 = PSS symbol
- 1 = SSS symbol

Behavior options:
- For synthesizable placeholder mode, the module may simply buffer and replay samples or provide a stub path if clearly documented.
- For Step 34 simulation, the behavioral FFT may be implemented in the testbench and drive downstream expected outputs.
- If using simulation-only code inside this module, wrap it clearly and document that it is not production synthesizable.

Preferred:
- Keep rtl/fft256_dual_symbol_frontend.v synthesizable as an interface skeleton.
- Put real FFT math in tb/fft256_behavioral_model.sv.

## Required top module: meyr_integer_cfo_fft_frontend_top

Create:

rtl/meyr_integer_cfo_fft_frontend_top.v

Purpose:
- Connect FFT frontend outputs to meyr_integer_cfo_freq_estimator_top.
- Accept time-domain PSS/SSS samples or already-FFT-like streams depending on chosen implementation.
- Produce intCFO output.

Recommended behavior:
- Collect or pass FFT outputs for PSS and SSS with matching indices.
- Feed pss_i/q and sss_i/q pairs into meyr_integer_cfo_freq_estimator_top.
- Preserve index alignment.
- Start the estimator after both PSS and SSS FFT outputs are available, or stream paired bins directly if timing is simple.

Recommended interface:

module meyr_integer_cfo_fft_frontend_top #(
    parameter FFT_LEN = 256,
    parameter IQ_WIDTH = 16,
    parameter PROD_WIDTH = 32,
    parameter ACC_WIDTH = 56,
    parameter SCORE_WIDTH = 64,
    parameter INDEX_WIDTH = 9
)(
    input  wire                         aclk,
    input  wire                         aresetn,

    input  wire                         start,

    input  wire                         s_valid,
    output wire                         s_ready,
    input  wire                         s_symbol_sel,
    input  wire [7:0]                   s_index,
    input  wire signed [IQ_WIDTH-1:0]   s_i,
    input  wire signed [IQ_WIDTH-1:0]   s_q,

    output wire                         busy,
    output wire                         done,
    output wire                         error,

    output wire signed [15:0]           int_cfo,
    output wire [INDEX_WIDTH-1:0]       peak_index,
    output wire [SCORE_WIDTH-1:0]       peak_score
);

Important:
- Keep this simple.
- If real FFT is not in synthesizable RTL yet, document that this top is a frontend integration scaffold.
- The testbench may directly drive FFT-output-equivalent streams into the estimator if needed, but the top/interface should prepare for time-domain input integration.

## Required behavioral FFT model

Create:

tb/fft256_behavioral_model.sv

Purpose:
- Simulation-only behavioral FFT/DFT helper.
- It may use real numbers, $cos, $sin, and SystemVerilog real math because it is testbench-only.
- It must not be used as production RTL.

Functions/tasks:
- dft256(input arrays time_i/time_q, output arrays freq_i/freq_q)
- optional idft256(input freq arrays, output time arrays)
- quantization helper to signed 16-bit
- saturation helper

Use deterministic rounding.

Document:
- DFT sign convention
- scaling convention
- bin order convention

## Required testbench

Create:

tb/meyr_integer_cfo_fft_frontend_top_tb.sv

The testbench should be deterministic and self-checking.

Minimum required tests: at least 10 tests.

Recommended tests:

T1 reset_defaults:
- After reset, busy/done/error/int_cfo/peak behavior sane.

T2 fft_model_single_bin:
- Validate behavioral FFT model on a simple single-bin complex exponential.
- Expected dominant bin index known.

T3 product_alignment_zero_cfo:
- Construct PSS/SSS frequency vectors so term1 aligns with synthetic term2.
- Convert to time domain if IFFT implemented.
- Feed through FFT frontend path.
- Expected peak_index=255, intCFO=0.

T4 positive_shift_plus1:
- Expected peak_index=256, intCFO=+1.

T5 negative_shift_minus1:
- Expected peak_index=254, intCFO=-1.

T6 positive_shift_plus3:
- Expected peak_index=258, intCFO=+3.

T7 negative_shift_minus4:
- Expected peak_index=251, intCFO=-4.

T8 positive_shift_plus8:
- Expected peak_index=263, intCFO=+8.

T9 negative_shift_minus8:
- Expected peak_index=247, intCFO=-8.

T10 restart_two_frames:
- Run shift 0, then shift +3.

T11 optional quantization_stress:
- Use lower-amplitude vectors and confirm no overflow/error.

T12 optional protocol_error:
- start while busy or missing symbol case if implemented.

Required output:
PASS: <count> FAIL: <count>
CI GATE: PASSED
or
CI GATE: FAILED

## Test generation details

Use the synthetic term2 fallback from rtl/meyr_term2_ref_rom.v for now.

The testbench must mirror the same synthetic ROM pattern, or read it through the RTL ROM, so that expected vectors match the estimator.

For a desired shift s:
- Generate target term1[k] as shifted synthetic term2:
  term1[k] = term2[k - s] if in range, else 0
- Choose SSS_FFT[k] = 1 + j0
- Choose PSS_FFT[k] = term1[k]
- Then term1 = PSS_FFT * conj(SSS_FFT) = PSS_FFT

If term2 values exceed int16, scale synthetic term2 or use a test-local small vector consistent with the estimator mode.
Do not silently change estimator ROM without documenting it.

If IFFT/FFT roundtrip causes quantization differences that break exact shift recovery:
- reduce amplitude
- use integer-friendly vectors
- add tolerance only for FFT model checks, not for final intCFO checks
- final intCFO must still match exactly.

## Required simulation script

Create:

scripts/run_meyr_integer_cfo_fft_frontend_top_sim.sh

Use the existing repository script style.

The script should:
- compile required RTL:
  rtl/fft256_dual_symbol_frontend.v
  rtl/meyr_pss_sss_product_gen.v
  rtl/meyr_term2_ref_rom.v
  rtl/meyr_integer_cfo_core.v
  rtl/meyr_integer_cfo_freq_estimator_top.v
  rtl/meyr_integer_cfo_fft_frontend_top.v
  rtl/peak_detector.v if required
- compile TB/helper:
  tb/fft256_behavioral_model.sv
  tb/meyr_integer_cfo_fft_frontend_top_tb.sv
- run xsim
- save logs according to project convention
- grep for FAIL/FATAL/CI GATE failure
- exit nonzero on failure
- be executable

Also run prior simulations if any reused module was modified:
bash scripts/run_meyr_pss_sss_product_gen_sim.sh
bash scripts/run_meyr_integer_cfo_freq_estimator_top_sim.sh
bash scripts/run_meyr_integer_cfo_core_sim.sh if core changed

Do not claim prior regressions still pass unless they were actually run or unchanged.

## Documentation update

Create:

docs/step34_fft256_frontend_behavioral_integration.md

Include:

# Step 34 — FFT256 Frontend Wrapper and Behavioral FFT Integration

Sections:
- Objective
- Relationship to Steps 30–33
- Why Xilinx FFT IP is not used yet
- FFT bin order convention
- FFT scaling and quantization convention
- Frontend wrapper interface
- Behavioral FFT model
- Meyr estimator integration
- Synthetic term2 limitation
- Testbench scenarios
- Simulation command
- Simulation result
- Known limitations
- Next steps

Known limitations must include:
- Real mU/goldU-derived term2 ROM is still pending from Step 33.
- Behavioral FFT model is simulation-only.
- Production FFT implementation is still pending.
- Board integration is not part of Step 34.

## Current status update

Update:

ai_context/current_status.md

Add a Step 34 entry:

Step 34 — FFT256 frontend wrapper and behavioral FFT integration
Status: implemented and simulated / or implemented, simulation pending depending on actual result

Purpose:
- Define the FFT256 frontend interface for PSS/SSS symbols.
- Establish natural-order FFT bin convention.
- Add a simulation-only behavioral FFT model.
- Connect FFT-output streams to the existing Meyr frequency-domain estimator path.
- Verify end-to-end integer CFO recovery without Xilinx FFT IP.

Key design:
- No Xilinx FFT IP.
- No board wrapper changes.
- Uses synthetic term2 fallback because real mU/goldU is pending.
- Behavioral FFT is simulation-only.
- intCFO mapping remains intCFO = peak_index - 255.

Next recommended step:
- Step 35: implement PSS/SSS symbol extractor from corrected time-domain frame, or proceed to production FFT frontend decision if Step 34 simulation is stable.

Do not delete previous step history.

## Optional README update

If README.md has a progress section, add one short line only after simulation passes:

- Step 34: FFT256 behavioral frontend and Meyr estimator integration verified without Xilinx FFT IP; real term2 ROM and production FFT remain pending.

If simulation is not run or fails, do not claim verified.

## Do not modify

Do not modify board/Vitis host files.

Do not modify:
host/
sw/
src/
include/

Do not modify frame/timing/fractional CFO modules.

Do not modify BRAM wrapper.

Avoid modifying Step 31/32 core modules unless necessary. If modified, rerun affected simulations.

Do not run board tests.

Do not perform destructive git operations.

Do not add Xilinx FFT IP.

Do not claim production FFT implementation if using behavioral testbench FFT.

## Local checks and simulation

Run simulations if the repository environment supports existing xsim scripts from WSL.

Recommended command:

bash scripts/run_meyr_integer_cfo_fft_frontend_top_sim.sh

If reused modules were changed, also run:
bash scripts/run_meyr_pss_sss_product_gen_sim.sh
bash scripts/run_meyr_integer_cfo_freq_estimator_top_sim.sh
bash scripts/run_meyr_integer_cfo_core_sim.sh

If Vivado is not available in this WSL environment, do not fake the result. Document simulation pending.

After running or attempting to run, check:

grep -R "CI GATE" -n logs sim_build . 2>/dev/null
git status --short

## Acceptance criteria

Step 34 is complete only if:

- md_files/34_fft256_frontend_behavioral_integration_prompt.md exists.
- rtl/fft256_dual_symbol_frontend.v exists.
- rtl/meyr_integer_cfo_fft_frontend_top.v exists.
- tb/fft256_behavioral_model.sv exists.
- tb/meyr_integer_cfo_fft_frontend_top_tb.sv exists.
- scripts/run_meyr_integer_cfo_fft_frontend_top_sim.sh exists and is executable.
- docs/step34_fft256_frontend_behavioral_integration.md exists.
- ai_context/current_status.md is updated.
- No Xilinx FFT IP is used.
- Board wrapper is not modified.
- Real term2 ROM limitation is documented.
- Behavioral FFT simulation-only limitation is documented.
- Final response reports exact PASS/FAIL/pending status honestly.

## Final response required

After completing Step 34, report:

Step 34 FFT256 frontend / behavioral integration complete.

Files changed:
- ...

Main implementation:
- rtl/fft256_dual_symbol_frontend.v
- rtl/meyr_integer_cfo_fft_frontend_top.v
- tb/fft256_behavioral_model.sv
- tb/meyr_integer_cfo_fft_frontend_top_tb.sv

Design decisions:
- FFT bin order: natural order / other, specify
- FFT scaling: unnormalized / normalized, specify
- Xilinx FFT IP used: no
- Behavioral FFT model: simulation-only
- term2 ROM: synthetic fallback / real, specify

Simulation:
- command: bash scripts/run_meyr_integer_cfo_fft_frontend_top_sim.sh
- result: PASS / FAIL / pending
- CI gate: PASSED / FAILED / not run

Limitations:
- real mU/goldU term2 ROM remains pending unless Step 33 data is later provided
- production FFT RTL/IP remains pending
- board integration not performed

Next recommended step:
- Step 35 — implement PSS/SSS symbol extractor from corrected frame output, or decide production FFT frontend strategy if Step 34 exposed interface issues.
