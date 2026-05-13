# Step 32 — Meyr PSS/SSS Product Generator and Real term2 Reference ROM

## Mandatory archival rule

Before modifying any file, save this entire prompt verbatim as:

md_files/32_meyr_product_generator_real_term2_prompt.md

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

This Step 32 is an RTL simulation step only.

## Context

Step 29I is complete and passed on ZCU102.

Step 30 is complete and defines the Meyr-based integer CFO architecture.

Step 31 is complete and passed simulation:

Step 31 — Meyr Integer CFO Direct-Correlation Core
Status: COMPLETE — PASS: 32, FAIL: 0, CI GATE: PASSED

Step 31 created:
- rtl/meyr_integer_cfo_core.v
- tb/meyr_integer_cfo_core_tb.sv
- scripts/run_meyr_integer_cfo_core_sim.sh
- docs/step31_meyr_integer_cfo_core.md

Step 31 verified:
- NSC=256
- 511 direct correlation lags
- zero CFO peak index = 255
- intCFO = peak_index - 255
- synthetic XOR-shift32 PRNG term2 ROM
- no FFT IP
- no PSS/SSS symbol extraction
- no board wrapper changes

Step 32 now moves one level closer to the C reference algorithm.

## Critical C-reference formulation

The Step 30 architecture was verified against ref/receiver.c.

The correct Meyr product definitions are:

term1[j] = PSS_FFT[j] * conj(SSS_FFT[j])

term2[j] = mU[j + CP_LEN] * conj(goldU[j + CP_LEN])

The earlier generic planning formula with conjugation on the other side was corrected in Step 30. Use the C-reference formulation above.

The integer CFO mapping remains:

peakIndexMeyr = argmax |corr|^2
intCFO = peakIndexMeyr - 255

For NSC=256, correlation has 511 lags and zero CFO is index 255.

## Step 32 goal

Implement and verify the Meyr product-generation layer before adding FFT.

Step 32 should add:

1. Product generator for received PSS/SSS FFT outputs:
   term1[j] = PSS_FFT[j] * conj(SSS_FFT[j])

2. Real or C-derived term2 reference ROM:
   term2[j] = mU[j + CP_LEN] * conj(goldU[j + CP_LEN])

3. A frequency-domain estimator wrapper that connects:
   PSS_FFT / SSS_FFT inputs
   -> term1 product generator
   -> real term2 ROM path
   -> Step 31 Meyr correlation core or a refactored compatible core
   -> peak_index / int_cfo / peak_score

4. Deterministic simulation tests that verify:
   - product generator arithmetic
   - term2 ROM read behavior
   - end-to-end shift recovery using PSS_FFT and SSS_FFT-like synthetic vectors
   - no FFT IP is used

Important:
- Step 32 still does not add FFT.
- The testbench directly supplies synthetic frequency-domain PSS_FFT and SSS_FFT vectors.
- FFT integration is reserved for a later step.

## Files to inspect first

Inspect these files before editing:

rtl/meyr_integer_cfo_core.v
tb/meyr_integer_cfo_core_tb.sv
scripts/run_meyr_integer_cfo_core_sim.sh
docs/step30_meyr_integer_cfo_pss_sss_architecture.md
docs/step31_meyr_integer_cfo_core.md
ai_context/current_status.md
README.md

Also inspect:

rtl/peak_detector.v
ref/receiver.c
ref/
docs/
scripts/

Search for C-reference symbols and existing ROM/data conventions:

grep -R "carrierFreqOffsetEstMeyr\|fft_correlation_Meyr\|Meyr\|meyr\|intCFO\|peakIndexMeyr\|goldU\|mU\|PSS\|SSS\|CP_LEN\|NSC" -n . 2>/dev/null
grep -R "module .*rom\|case.*addr\|read.*rom\|localparam.*ROM" -n rtl tb 2>/dev/null
grep -R "module peak_detector" -n rtl tb 2>/dev/null

Before modifying rtl/meyr_integer_cfo_core.v, understand exactly how Step 31 term2 ROM is implemented.

## Required design approach

Prefer minimal, safe extension over rewriting Step 31.

Step 31 already passed. Preserve its behavior.

Recommended approach:

1. Create a separate term2 ROM module:
   rtl/meyr_term2_ref_rom.v

2. Create a product generator:
   rtl/meyr_pss_sss_product_gen.v

3. Create a Step 32 wrapper:
   rtl/meyr_integer_cfo_freq_estimator_top.v

4. Refactor rtl/meyr_integer_cfo_core.v only if necessary to allow external term2 values.

Acceptable options for connecting real term2 to the core:

Option A — Preferred if simple:
- Modify meyr_integer_cfo_core.v to support parameter USE_EXTERNAL_TERM2.
- Default USE_EXTERNAL_TERM2=0 preserves Step 31 synthetic ROM behavior.
- When USE_EXTERNAL_TERM2=1, the core reads term2_i/q from an external ROM interface:
  output term2_req_valid
  output term2_req_index
  input signed term2_i
  input signed term2_q
- Re-run Step 31 simulation to make sure old behavior still passes.
- Run new Step 32 simulation with USE_EXTERNAL_TERM2=1.

Option B — If refactoring the core is risky:
- Create a new wrapper/core variant for Step 32:
  rtl/meyr_integer_cfo_core_extterm2.v
- Keep rtl/meyr_integer_cfo_core.v unchanged.
- Use the new extterm2 core only in Step 32 tests.
- Document that Step 33 may consolidate the two versions later.

Option C — If the Step 31 core already has a clean internal term2 function:
- Replace or parameterize only the term2 lookup function.
- Preserve synthetic mode for Step 31 tests.
- Add real-ROM mode for Step 32 tests.

Do not break Step 31 regression.

## term2 reference ROM requirements

Create:

rtl/meyr_term2_ref_rom.v

Purpose:
- Provide term2[j] = mU[j + CP_LEN] * conj(goldU[j + CP_LEN]) for j=0..255.

Interface recommendation:

module meyr_term2_ref_rom #(
    parameter NSC = 256,
    parameter PROD_WIDTH = 32,
    parameter USE_SYNTHETIC_FALLBACK = 0
)(
    input  wire [7:0] addr,
    output reg signed [PROD_WIDTH-1:0] term2_i,
    output reg signed [PROD_WIDTH-1:0] term2_q
);

Implementation guidance:
- If ref/receiver.c exposes mU and goldU sequences clearly, derive term2 constants from them.
- If extracting exact constants manually is too error-prone, write a small helper script under scripts/ to parse or generate the ROM data from ref/receiver.c, but only if practical.
- If true mU/goldU extraction is not possible within this step, implement a deterministic C-reference-compatible placeholder mode and document it clearly. However, first attempt to use real data from ref/receiver.c.
- The ROM should be deterministic and synthesizable.
- Avoid huge unreadable logic if a case statement or localparam array is cleaner within project style.
- Keep PROD_WIDTH=32 unless existing project style requires another width.

Important:
- Step 32 acceptance is strongest if real term2 values are extracted from ref/receiver.c.
- If real values cannot be extracted, the final report must clearly say so and mark real ROM extraction as pending. Do not claim real mU/goldU if synthetic values are used.

## Product generator requirements

Create:

rtl/meyr_pss_sss_product_gen.v

Purpose:
- Compute term1[j] = PSS_FFT[j] * conj(SSS_FFT[j])

Inputs:
- pss_i, pss_q
- sss_i, sss_q
- valid/index handshake

Recommended interface:

module meyr_pss_sss_product_gen #(
    parameter IQ_WIDTH = 16,
    parameter PROD_WIDTH = 32
)(
    input  wire                         aclk,
    input  wire                         aresetn,

    input  wire                         s_valid,
    output wire                         s_ready,
    input  wire [7:0]                   s_index,
    input  wire signed [IQ_WIDTH-1:0]   pss_i,
    input  wire signed [IQ_WIDTH-1:0]   pss_q,
    input  wire signed [IQ_WIDTH-1:0]   sss_i,
    input  wire signed [IQ_WIDTH-1:0]   sss_q,

    output reg                          m_valid,
    input  wire                         m_ready,
    output reg [7:0]                    m_index,
    output reg signed [PROD_WIDTH-1:0]  term1_i,
    output reg signed [PROD_WIDTH-1:0]  term1_q
);

Arithmetic:
- PSS = a + jb
- SSS = c + jd
- conj(SSS) = c - jd
- term1 = PSS * conj(SSS)
- term1_i = a*c + b*d
- term1_q = b*c - a*d

Behavior:
- Simple one-cycle or registered pipeline is acceptable.
- Preserve index alignment.
- Support backpressure through m_ready if implemented.
- If s_ready is always tied to m_ready or 1, document the behavior.
- Do not over-optimize.

## Frequency estimator top requirements

Create:

rtl/meyr_integer_cfo_freq_estimator_top.v

Purpose:
- Accept PSS_FFT and SSS_FFT samples.
- Generate term1 using meyr_pss_sss_product_gen.
- Provide term2 from meyr_term2_ref_rom.
- Feed term1 and term2 into the Meyr CFO core.
- Output int_cfo, peak_index, peak_score, done, busy, error.

Recommended interface:

module meyr_integer_cfo_freq_estimator_top #(
    parameter NSC = 256,
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
    input  wire [7:0]                   s_index,
    input  wire signed [IQ_WIDTH-1:0]   pss_i,
    input  wire signed [IQ_WIDTH-1:0]   pss_q,
    input  wire signed [IQ_WIDTH-1:0]   sss_i,
    input  wire signed [IQ_WIDTH-1:0]   sss_q,

    output wire                         busy,
    output wire                         done,
    output wire                         error,

    output wire signed [15:0]           int_cfo,
    output wire [INDEX_WIDTH-1:0]       peak_index,
    output wire [SCORE_WIDTH-1:0]       peak_score
);

Implementation note:
- It is acceptable if the wrapper first loads all 256 generated term1 samples into the core and then starts correlation, depending on the Step 31 core protocol.
- The top may start the core first and stream term1 in if that matches the existing Step 31 interface.
- Keep the design simple and deterministic.

## Important test strategy

The testbench should not require FFT.

It should construct synthetic PSS_FFT and SSS_FFT vectors such that the generated term1 vector is a shifted version of term2.

One practical way:

Given desired shift s:
- Obtain term2[n] from the same ROM/golden model.
- Choose SSS_FFT[n] = 1 + j0 for all valid n.
- Choose PSS_FFT[n] = shifted term2[n] scaled/truncated into IQ_WIDTH if term2 values are small enough.
- Then term1[n] = PSS_FFT[n] * conj(SSS_FFT[n]) = PSS_FFT[n].

However, if real term2 values exceed IQ_WIDTH or product scaling is too large:
- Use a controlled synthetic mode for testing product generator and end-to-end wrapper.
- Or choose PSS/SSS pairs whose product equals a small shifted target sequence.
- Document the scaling and test convention.

Recommended robust test mode:
- meyr_term2_ref_rom may support USE_SYNTHETIC_FALLBACK=1 for test-friendly small values.
- Step 32 can test both:
  1. Product arithmetic with explicit small values.
  2. End-to-end shift recovery with synthetic fallback term2.
  3. Real ROM read consistency against extracted/golden constants if real constants are available.

Do not fake real mU/goldU verification if only synthetic fallback is tested.

## Required testbench

Create:

tb/meyr_pss_sss_product_gen_tb.sv

This testbench should verify product arithmetic only.

Required tests:
- reset/default behavior
- simple real multiply: PSS=2+j0, SSS=3+j0 => term1=6+j0
- conjugate behavior: PSS=1+j2, SSS=3+j4 => term1 = (1+j2)*(3-j4) = 11+j2
- negative values
- index preservation
- backpressure if supported
- at least 8 checks
- CI GATE line

Create:

tb/meyr_integer_cfo_freq_estimator_top_tb.sv

This testbench should verify the top-level product-gen + term2-ROM + Meyr core path.

Required tests:
- T1 reset_defaults
- T2 zero_cfo
- T3 positive_shift_plus1
- T4 negative_shift_minus1
- T5 positive_shift_plus3
- T6 negative_shift_minus4
- T7 positive_shift_plus8
- T8 negative_shift_minus8
- T9 restart_two_frames
- T10 start_while_busy or protocol error behavior
- T11 zero/weak input behavior
- T12 product_gen_to_core_index_alignment

Expected mapping:
- peak_index = 255 + shift
- int_cfo = shift

If using synthetic fallback term2 for the top-level shift tests, state this clearly in comments and docs.

If using real term2 ROM for tests, also include a few ROM consistency checks against known constants extracted from ref/receiver.c.

The testbench must print:
PASS: <count> FAIL: <count>
CI GATE: PASSED

or:
CI GATE: FAILED

## Required simulation scripts

Create:

scripts/run_meyr_pss_sss_product_gen_sim.sh

Create:

scripts/run_meyr_integer_cfo_freq_estimator_top_sim.sh

Use the existing repository script style.

Each script should:
- compile required RTL
- compile testbench
- run xsim
- save logs according to project convention
- grep for FAIL/FATAL/CI GATE failure
- exit nonzero on failure
- be executable

If Step 31 regression could be affected by refactoring meyr_integer_cfo_core.v, also run:

bash scripts/run_meyr_integer_cfo_core_sim.sh

Do not claim Step 31 still passes unless it actually does.

## Documentation update

Create:

docs/step32_meyr_product_generator_real_term2.md

Include:

# Step 32 — Meyr PSS/SSS Product Generator and term2 Reference ROM

Sections:
- Objective
- Relationship to Step 30 and Step 31
- C-reference formulas
- Product generator arithmetic
- term2 ROM source
- Whether real mU/goldU constants were extracted or synthetic fallback was used
- Frequency estimator top architecture
- Testbench scenarios
- Simulation commands
- Simulation results
- Known limitations
- Next steps

Important documentation requirement:
- Be honest about real ROM status.
- If true mU/goldU-derived term2 is not fully implemented, state:
  Real mU/goldU-derived term2 ROM: pending
  Synthetic fallback ROM: implemented and verified
- If real ROM is implemented, state:
  Real mU/goldU-derived term2 ROM: implemented
  Source: ref/receiver.c
  Include enough detail to reproduce or verify extraction.

## Current status update

Update:

ai_context/current_status.md

Add a Step 32 entry:

Step 32 — Meyr PSS/SSS product generator and term2 reference ROM
Status: implemented and simulated / or implemented, simulation pending depending on actual run

Purpose:
- Add the received-product generator for term1 = PSS_FFT * conj(SSS_FFT).
- Add a term2 reference ROM path for mU * conj(goldU), or documented synthetic fallback if real extraction is pending.
- Connect product generation and term2 reference into the Meyr integer CFO core before FFT integration.
- Verify the frequency-domain estimator path using deterministic synthetic PSS_FFT/SSS_FFT inputs.

Key design:
- No FFT IP
- No PSS/SSS time-domain extraction
- No board wrapper changes
- Step 31 Meyr core reused or safely refactored
- intCFO mapping remains intCFO = peak_index - 255

Next recommended step:
- Step 33: consolidate the Meyr frequency-domain estimator top and prepare for FFT frontend integration, or complete real mU/goldU ROM extraction if still pending.

Do not delete previous step history.

## Optional README update

If README.md has a progress section, add one short line only after simulation passes:

- Step 32: Meyr PSS/SSS product generator and frequency-domain estimator path verified without FFT IP; real term2 ROM status documented.

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

Do not run board tests.

Do not perform destructive git operations.

Avoid changing rtl/meyr_integer_cfo_core.v unless necessary. If changed, preserve Step 31 behavior and rerun Step 31 simulation.

## Local checks and simulation

Run simulations if the repository environment supports existing xsim scripts from WSL.

Recommended commands:

bash scripts/run_meyr_pss_sss_product_gen_sim.sh
bash scripts/run_meyr_integer_cfo_freq_estimator_top_sim.sh

If rtl/meyr_integer_cfo_core.v was modified, also run:

bash scripts/run_meyr_integer_cfo_core_sim.sh

If Vivado is not available in this WSL environment, do not fake the result. Document simulation pending.

After running or attempting to run, check:

grep -R "CI GATE" -n logs sim_build . 2>/dev/null
git status --short

## Acceptance criteria

Step 32 is complete only if:

- md_files/32_meyr_product_generator_real_term2_prompt.md exists.
- rtl/meyr_pss_sss_product_gen.v exists.
- rtl/meyr_term2_ref_rom.v exists.
- rtl/meyr_integer_cfo_freq_estimator_top.v exists, unless a clearly documented alternative top name is used.
- tb/meyr_pss_sss_product_gen_tb.sv exists.
- tb/meyr_integer_cfo_freq_estimator_top_tb.sv exists.
- scripts/run_meyr_pss_sss_product_gen_sim.sh exists and is executable.
- scripts/run_meyr_integer_cfo_freq_estimator_top_sim.sh exists and is executable.
- docs/step32_meyr_product_generator_real_term2.md exists.
- ai_context/current_status.md is updated.
- No FFT IP is required.
- Board wrapper is not modified.
- Real term2 ROM status is honestly documented.
- Final response reports exact PASS/FAIL/pending status honestly.

## Final response required

After completing Step 32, report:

Step 32 Meyr product generator / term2 ROM implementation complete.

Files changed:
- ...

Main implementation:
- rtl/meyr_pss_sss_product_gen.v
- rtl/meyr_term2_ref_rom.v
- rtl/meyr_integer_cfo_freq_estimator_top.v
- Step 31 core reused/refactored: yes/no, details

C-reference alignment:
- term1 = PSS_FFT * conj(SSS_FFT)
- term2 = mU * conj(goldU)
- real mU/goldU ROM status: implemented / pending / synthetic fallback only

Testbenches:
- tb/meyr_pss_sss_product_gen_tb.sv
- tb/meyr_integer_cfo_freq_estimator_top_tb.sv

Simulation:
- product generator command: bash scripts/run_meyr_pss_sss_product_gen_sim.sh
- product generator result: PASS / FAIL / pending
- estimator top command: bash scripts/run_meyr_integer_cfo_freq_estimator_top_sim.sh
- estimator top result: PASS / FAIL / pending
- Step 31 regression rerun if core changed: PASS / FAIL / not needed / pending

Next recommended step:
- Step 33 — consolidate Meyr frequency-domain estimator top and prepare FFT frontend integration, or complete real mU/goldU ROM extraction if still pending.
