# Step 30 — Meyr-Based Integer CFO / PSS-SSS Algorithm-to-RTL Architecture Spec

## Mandatory archival rule

Before modifying any file, save this entire prompt verbatim as:

md_files/30_meyr_integer_cfo_pss_sss_architecture_prompt.md

If the md_files/ directory does not exist, create it first.

## Working directory

/home/zealatan/RTL_SYNC

## Important workflow separation

This project uses a split workflow:

WSL/Linux side:
- Claude Code works here.
- Source/documentation editing is done here.
- RTL/testbench/simulation work is done here when requested.

Windows side:
- The user manually pulls updated code from Git.
- The user manually uses Vivado/Vitis.
- The user manually programs the ZCU102 board.
- The user manually runs UART/COM tests.

For this step:
- Do not run Vivado.
- Do not run Vitis.
- Do not access COM5.
- Do not modify board/Vitis host files.
- Do not claim any new board result.

This Step 30 is primarily an architecture/specification step.

## Context

The project is RTL_SYNC, an FPGA-ready OFDM synchronizer subsystem.

The currently validated board path is:

PS host
-> AXI-Lite control
-> input BRAM preload/readback
-> BRAM source
-> AXI-Stream input
-> frame detector
-> timing / fractional CFO path
-> corrected output BRAM
-> PS readback

Step 29I has passed on ZCU102.

Observed board regression result:

Step 29I Host Test: BRAM wrapper board regression
Board: ZCU102
IP base: 0xA0000000

Case A: negative short-quiet detector stress : PASS
  STATUS=0x0000019A
  INPUT_COUNT=116
  OUTPUT_COUNT=0
  DEBUG_STATE=0xFD88B074
  ERROR_STATUS=0
  FRAME_ERROR=1
  handshake_seen=1

Case B: positive long-quiet frame detection : PASS
  STATUS=0x0000009A
  INPUT_COUNT=632
  OUTPUT_COUNT=288
  DEBUG_STATE=0xFD88A278
  ERROR_STATUS=0
  FRAME_ERROR=0
  handshake_seen=1

RESULT: PASS

This confirms that the board-level wrapper, control path, BRAM source, AXI-Stream handshake, detector behavior, output BRAM, and PS readback are working.

Now we want to move toward the next synchronization stage:

Meyr-based integer CFO estimation using PSS/SSS.

## Critical correction from earlier planning

Do not specify the integer CFO path as a generic single-PSS shifted-bin correlator.

The existing C reference for integer CFO uses a Meyr-style algorithm.

The relevant C-reference function names are expected to be similar to:

carrierFreqOffsetEstMeyr()
fft_correlation_Meyr()

Search the repository for these exact or similar names before writing the final document:

Meyr
meyr
carrierFreqOffset
carrierFreqOffsetEstMeyr
fft_correlation_Meyr
integer CFO
intCFO
PSS
SSS
goldU
mU

If the C reference files are present, inspect them and align the Step 30 architecture document with the actual implementation.
If the exact files are not present in this repository, document the algorithm based on the known project description below and clearly state that the architecture is intended to match the existing C reference.

## Known Meyr integer CFO algorithm from project context

The C reference integer CFO flow is approximately:

1. Extract or obtain the PSS symbol.
2. Extract or obtain the SSS symbol.
3. Perform NSC-point FFT on both symbols.
   Typical project value: NSC = 256.

4. Generate received product term1:
   term1[j] = conj(PSS_FFT[j]) * SSS_FFT[j]

5. Generate reference product term2:
   term2[j] = conj(mU[j + CP_LEN]) * goldU[j + CP_LEN]

6. Cross-correlate term2 and term1 using Meyr correlation:
   corr = fft_correlation_Meyr(term2, term1)

7. Compute correlation magnitude score:
   score[i] = |corr[i]|^2

8. Find peak:
   peakIndexMeyr = argmax_i score[i]

9. Convert peak index to integer CFO estimate:
   intCFO = peakIndexMeyr - (NSC - 1)

The document must use this Meyr-based formulation as the main integer CFO architecture.

## High-level Step 30 goal

Create a detailed architecture/specification document for the Meyr-based integer CFO and PSS/SSS path.

This step should answer:

1. What exactly is the integer CFO problem in this RTL_SYNC receiver?
2. How is integer CFO different from fractional CFO?
3. Why does the project use a Meyr-style PSS/SSS product correlation?
4. Where does the Meyr integer CFO block sit relative to the existing frame detector / timing / fractional CFO path?
5. What input symbols does it consume?
6. What intermediate products are generated?
7. What correlation is performed?
8. How is peakIndexMeyr converted to intCFO?
9. What is the first RTL implementation target for Step 31?
10. How can we start without Xilinx FFT IP?
11. What verification strategy should be used before board integration?

## Important design stance

For now, do not require Xilinx FFT IP.

The current project direction is:

Phase 1:
- Use custom/behavioral/simple RTL blocks to build and verify the architecture.
- Avoid early dependency on Xilinx FFT IP.
- First isolate the core Meyr correlation and peak logic.

Later:
- Xilinx FFT IP may be considered for production-quality FFT implementation or timing closure.
- Custom FFT RTL may also be considered if the goal is IP independence and architecture-level control.

Therefore Step 30 should specify an architecture that can start with:
- synthetic frequency-domain term1 and term2 inputs
- direct correlation or simple RTL correlation core
- deterministic testbench vectors
- no FFT IP dependency in the first RTL step

But Step 30 should also clearly note where a future FFT block or Xilinx FFT IP would be inserted.

## Files to inspect first

Inspect the repository structure and relevant files:

rtl/
tb/
docs/
scripts/
ai_context/current_status.md
README.md
md_files/

Look specifically for existing synchronizer top modules and docs:

rtl/*frame*
rtl/*timing*
rtl/*cfo*
rtl/*sync*
rtl/*buffer*
tb/*frame*
tb/*timing*
tb/*cfo*
docs/step*
docs/*cfo*
docs/*sync*

Also search for C reference or algorithm reference files:

find . -type f | grep -Ei "c$|h$|cpp$|py$|md$|txt$"
grep -R "Meyr\|meyr\|carrierFreqOffset\|fft_correlation\|intCFO\|goldU\|mU\|PSS\|SSS" -n . 2>/dev/null

Also inspect current status:

ai_context/current_status.md

If a Step 30 document already exists, do not overwrite it blindly. Update or extend it.

## Existing architecture context to preserve

The existing chain is approximately:

input stream
-> frame detector
-> frame buffer
-> timing synchronization
-> fractional CFO estimation
-> NCO / complex rotator
-> corrected time-domain frame output

Step 30 should propose how the Meyr integer CFO/PSS-SSS path connects to this.

Possible placement to analyze:

Option A:
- Run integer CFO after frame detection but before fractional CFO correction.
- Problem: integer CFO estimator may see residual fractional CFO and timing uncertainty.

Option B:
- Run integer CFO after timing and fractional CFO correction using corrected time-domain frame.
- Advantage: Step 29 already validates corrected frame output. This isolates integer CFO from earlier timing/fractional CFO bring-up risk.

Option C:
- Use PSS/SSS path as a separate validation/detection stage after coarse frame detection.
- Advantage: useful for debug and staged integration.

Recommended for this project:
- Start with Option B or C.
- Use the validated corrected time-domain frame path as the source for PSS/SSS symbol extraction in later integration.
- For Step 31, do not connect to corrected frame yet. Instead, verify the Meyr correlation core using synthetic frequency-domain term1 and term2 inputs.

The document should make this recommendation explicit.

## Algorithm background to document

Write a practical explanation of integer CFO in OFDM.

Include the idea that CFO can be decomposed as:

normalized CFO = integer_subcarrier_offset + fractional_subcarrier_offset

Where:

fractional CFO:
- already handled by the current CP/timing/fractional CFO path
- appears as a continuous phase rotation across time-domain samples
- current RTL_SYNC path already estimates and corrects this component

integer CFO:
- appears as a subcarrier-index shift after FFT
- must be estimated using known synchronization structure
- in this project, the reference C implementation uses a Meyr-style PSS/SSS product correlation

Explain that the Meyr method uses the relationship between PSS and SSS frequency-domain symbols. Instead of correlating one received symbol directly against one reference, it forms products:

received product:
term1[j] = conj(PSS_FFT[j]) * SSS_FFT[j]

reference product:
term2[j] = conj(mU[j + CP_LEN]) * goldU[j + CP_LEN]

Then it cross-correlates term2 and term1 and finds the peak.

## PSS/SSS representation decision

Discuss these options:

Option 1 — Frequency-domain PSS/SSS references

Store or generate PSS/SSS in frequency domain.
After FFT of received PSS and SSS symbols, generate the Meyr product terms and correlate.

Pros:
- Natural for integer CFO because integer CFO appears as a frequency-bin shift.
- Matches the known C reference direction.
- Directly supports Meyr product correlation.
- Good for RTL once FFT output is available.

Cons:
- Requires FFT of PSS/SSS symbols before product generation.
- FFT frontend is a later integration concern.

Option 2 — Time-domain IFFT'ed PSS/SSS references

Store already-IFFT'ed PSS/SSS time-domain sequences.
Use time-domain correlation.

Pros:
- Can be used for frame/time detection.
- Reference can be precomputed offline.

Cons:
- Integer CFO appears as a complex phase ramp in time domain, not simply a bin shift.
- Does not directly match the existing Meyr C reference.
- Integer CFO search may require multiple derotation hypotheses or more complex correlation.

Required recommendation:

For this project:
- Use frequency-domain PSS/SSS representation for the Meyr integer CFO path.
- Optionally keep IFFT'ed time-domain PSS/SSS references for future time-domain detection experiments.
- Do not make time-domain PSS correlation the main integer CFO path.

Reason:
- The C reference uses PSS/SSS FFT products and Meyr cross-correlation.
- The target integer CFO quantity is a frequency-bin shift.
- Frequency-domain product correlation is the closest architecture to the validated reference algorithm.

## Meyr correlation formulation to include

Let:

NSC = number of subcarriers or FFT length used by the reference algorithm, likely 256.
PSS_FFT[j] = FFT of received PSS symbol.
SSS_FFT[j] = FFT of received SSS symbol.
mU[] = known PSS-related reference sequence from the C model.
goldU[] = known SSS/gold reference sequence from the C model.
CP_LEN = cyclic prefix length or reference offset used by the C model.

Received product:

term1[j] = conj(PSS_FFT[j]) * SSS_FFT[j]

Reference product:

term2[j] = conj(mU[j + CP_LEN]) * goldU[j + CP_LEN]

Meyr cross-correlation:

corr = xcorr(term2, term1)

Peak:

peakIndexMeyr = argmax_i |corr[i]|^2

Integer CFO estimate:

intCFO = peakIndexMeyr - (NSC - 1)

Explain that a full linear correlation of two length-NSC sequences produces 2*NSC - 1 correlation lags.
For NSC = 256, the lag count is 511.
The center index NSC - 1 corresponds to zero integer CFO.
Therefore the detected offset is peakIndexMeyr - (NSC - 1).

## Initial hardware architecture to specify

Create a block-level architecture for Step 31+.

Recommended staged architecture:

Later full path:

corrected time-domain frame
-> PSS/SSS symbol extractor
-> PSS FFT
-> SSS FFT
-> received product generator: term1 = conj(PSS_FFT) * SSS_FFT
-> reference product ROM/generator: term2 = conj(mU) * goldU
-> Meyr correlation core
-> magnitude-squared score
-> peak detector / argmax
-> intCFO estimate register

But first RTL implementation should start smaller:

Step 31 initial path:

synthetic term1 input
synthetic term2/reference input or ROM
-> Meyr direct correlation core
-> magnitude-squared score
-> peak detector
-> intCFO estimate

Do not include FFT in Step 31.

## First RTL target recommendation

The document must recommend Step 31 as:

Step 31 — Meyr Correlation Core RTL and Deterministic Testbench

Step 31 should implement a pure RTL core that consumes synthetic frequency-domain product vectors or a streamed vector representation.

Recommended Step 31 scope:

- No FFT.
- No PSS/SSS symbol extraction.
- No Xilinx IP.
- No board wrapper changes.
- Implement and verify the core mapping:
  term1, term2 -> correlation score -> peak index -> intCFO.

Possible module name:

rtl/meyr_integer_cfo_core.v

Possible testbench name:

tb/meyr_integer_cfo_core_tb.sv

Possible run script:

scripts/run_meyr_integer_cfo_core_sim.sh

## RTL interface proposal

Propose a future RTL module interface, but do not implement it in Step 30 unless the repository convention requires placeholder stubs.

Suggested Step 31 direct-vector/simplified interface may be documented as:

module meyr_integer_cfo_core #(
    parameter NSC = 256,
    parameter IQ_WIDTH = 16,
    parameter PROD_WIDTH = 32,
    parameter ACC_WIDTH = 56,
    parameter SCORE_WIDTH = 64
)(
    input  wire                     aclk,
    input  wire                     aresetn,
    input  wire                     start,

    input  wire                     term_valid,
    input  wire [$clog2(NSC)-1:0]    term_index,
    input  wire signed [PROD_WIDTH-1:0] term1_i,
    input  wire signed [PROD_WIDTH-1:0] term1_q,
    input  wire signed [PROD_WIDTH-1:0] term2_i,
    input  wire signed [PROD_WIDTH-1:0] term2_q,

    output wire                     ready,
    output wire                     done,
    output wire signed [15:0]        int_cfo,
    output wire [$clog2(2*NSC-1)-1:0] peak_index,
    output wire [SCORE_WIDTH-1:0]    peak_score,
    output wire                     error
);

But the document may propose a more practical interface after inspecting repository conventions.

The key point:
- Step 31 core should be independently testable without FFT.

## Direct correlation versus FFT correlation

The C reference may use fft_correlation_Meyr(), which likely implements correlation using FFT/IFFT.

For Step 31 RTL, document this distinction:

Reference algorithm:
- Uses FFT-based correlation for efficiency.

Initial RTL verification:
- May use direct correlation across 2*NSC - 1 lags to validate functionality.
- Direct correlation is simpler to verify and does not require FFT IP.
- Once behavior is locked, a later step can replace or accelerate the correlation using FFT-based architecture.

This is acceptable because the mathematical output should match the reference correlation peak and intCFO mapping.

## Fixed-point and accumulator considerations

Include practical notes:

- Input IQ width in existing RTL is likely 16-bit signed.
- FFT outputs may grow depending on scaling.
- PSS/SSS product term1 = conj(PSS_FFT) * SSS_FFT can require wider product representation.
- Reference product term2 may be precomputed and quantized.
- Complex multiply inside correlation between term2 and term1 may require wide intermediate products.
- Accumulating across up to NSC terms requires wider accumulators.
- Use at least 56-bit accumulation for first Meyr correlation RTL planning if term products are 32-bit scale.
- Magnitude-squared score may require even wider intermediate width.
- For the first skeleton, compare peak scores with safe truncation only after accumulation.
- Do not over-optimize or finalize quantization in Step 30.

## Verification plan

Specify a staged verification plan.

Step 31 deterministic tests should include:

1. Zero CFO case:
   - term1 equals term2 or aligned version.
   - Expected peak index = NSC - 1.
   - Expected intCFO = 0.

2. Positive integer CFO case:
   - term1 is shifted relative to term2.
   - Expected peak index = NSC - 1 + shift.
   - Expected intCFO = shift.

3. Negative integer CFO case:
   - term1 shifted in opposite direction.
   - Expected peak index = NSC - 1 - shift_abs.
   - Expected intCFO = negative shift.

4. Multiple shifts:
   - Test shifts such as -4, -2, -1, 0, +1, +3, +4.

5. Weak/no-correlation case:
   - Should not falsely report a strong valid result if a validity threshold is later added.
   - For the first core, this may only check peak behavior and no crash.

6. Tie-breaking case:
   - If two peaks are equal, define deterministic tie behavior.
   - Recommended: choose the lowest peak index or first encountered peak.
   - Document chosen behavior.

7. Reset/restart case:
   - Core should process one vector, finish, reset or restart, then process another vector.

## Recommended roadmap after Step 30

Step 31:
- Implement Meyr direct correlation core using synthetic term1/term2 vectors.
- Verify peak index and intCFO mapping.

Step 32:
- Add PSS/SSS product generator:
  PSS_FFT + SSS_FFT -> term1.
  reference ROM/generator -> term2.

Step 33:
- Add integer CFO estimator top:
  product generator + Meyr core + peak detector + status/debug.

Step 34:
- Add FFT frontend strategy:
  behavioral FFT first, then custom FFT or Xilinx FFT IP decision.

Step 35:
- Integrate with corrected frame output:
  corrected frame -> PSS/SSS symbol extraction -> FFT -> Meyr estimator.

Step 36:
- Extend BRAM/AXI-Lite wrapper with integer CFO debug registers.

Step 37:
- ZCU102 board smoke test for known integer CFO vector.

Step 38:
- Simulation and selected board regression over multiple integer CFO shifts.

## Required output document

Create or update:

docs/step30_meyr_integer_cfo_pss_sss_architecture.md

The document must include:

# Step 30 — Meyr-Based Integer CFO / PSS-SSS Algorithm-to-RTL Architecture

## Objective
## Current validated receiver state
## Integer CFO problem definition
## Relationship to fractional CFO
## C-reference Meyr algorithm summary
## PSS/SSS representation choices
## Recommended representation for this project
## Meyr product generation
## Meyr correlation and peak mapping
## Proposed block-level architecture
## Proposed RTL interface
## Direct-correlation first strategy
## Future FFT-based acceleration path
## Fixed-point and accumulator considerations
## Verification strategy
## Recommended Step 31 target
## Future integration notes
## Conclusion

## Current status update

Update:

ai_context/current_status.md

Add a Step 30 entry:

Step 30 — Meyr-based integer CFO / PSS-SSS architecture spec
Status: completed as architecture/specification step

Purpose:
- Define how integer CFO estimation should be added after the validated frame/timing/fractional CFO path.
- Align the design with the existing C reference Meyr algorithm.
- Specify the PSS/SSS product-based Meyr correlation:
  term1 = conj(PSS_FFT) * SSS_FFT
  term2 = conj(mU) * goldU
  corr = xcorr(term2, term1)
  intCFO = peakIndexMeyr - (NSC - 1)
- Recommend frequency-domain PSS/SSS representation for the main integer CFO path.
- Define a staged RTL roadmap that starts with a synthetic-input Meyr correlation core before adding FFT.

Recommended next step:
- Step 31: implement and verify the Meyr integer CFO correlation core using synthetic term1/term2 inputs before adding FFT IP.

Do not delete previous step history.

## Optional README update

If README.md has a progress section, add one short line:

- Step 30: Meyr-based integer CFO / PSS-SSS architecture specified; Step 31 will start with a synthetic-input Meyr correlation core before FFT integration.

Do not rewrite the full README.

## Do not modify

Do not modify RTL in this step unless only adding a non-used placeholder is clearly consistent with project convention.

Prefer documentation only.

Do not modify:

rtl/
tb/
host/
sw/
src/
include/
scripts/run_*_sim.sh

Do not run simulation.
Do not run board tests.
Do not perform destructive git operations.

## Local checks

After editing, run simple checks only:

grep -R "Step 30" -n docs ai_context README.md md_files 2>/dev/null
grep -R "Meyr\|meyr\|intCFO\|peakIndexMeyr" -n docs ai_context README.md md_files 2>/dev/null
git status --short

Do not run Vivado or Vitis.

## Final response required

After completing Step 30, report:

Step 30 Meyr architecture/specification update complete.

Files changed:
- ...

Main decisions:
- Integer CFO will follow the existing C-reference Meyr algorithm.
- The main path uses PSS/SSS frequency-domain products:
  term1 = conj(PSS_FFT) * SSS_FFT
  term2 = conj(mU) * goldU
- Integer CFO is computed from the Meyr correlation peak:
  intCFO = peakIndexMeyr - (NSC - 1)
- Step 31 should start with a synthetic-input Meyr direct-correlation RTL core before adding FFT or Xilinx IP.

Next recommended step:
- Step 31 — implement Meyr integer CFO correlation core RTL and deterministic simulation testbench.
