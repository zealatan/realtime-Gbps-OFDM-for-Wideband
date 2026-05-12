# Step 30 — Integer CFO / PSS-SSS Algorithm-to-RTL Architecture Spec

## Mandatory archival rule

Before modifying any file, save this entire prompt verbatim as:

md_files/30_integer_cfo_pss_sss_architecture_prompt.md

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

The current validated path is:

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

integer CFO estimation / PSS-SSS detection path

## High-level Step 30 goal

Create a detailed architecture/specification document for the integer CFO and PSS/SSS path.

This step should answer:

1. What exactly is the integer CFO problem in this RTL_SYNC receiver?
2. Where does the integer CFO block sit relative to the existing frame detector / timing / fractional CFO path?
3. What input samples does it consume?
4. What output does it produce?
5. What PSS/SSS representation should be used?
6. Should PSS/SSS be stored in frequency domain, time domain, or both?
7. What is the initial FPGA-friendly architecture?
8. What is the first RTL implementation target for Step 31?
9. What testbench strategy should be used before board integration?

## Important design stance

For now, do not require Xilinx FFT IP.

The current project direction is:

Phase 1:
- Use custom/behavioral/simple RTL blocks to build and verify the architecture.
- Avoid early dependency on Xilinx FFT IP.

Later:
- Xilinx FFT IP may be considered for production-quality implementation or timing closure.

Therefore Step 30 should specify an architecture that can start with:
- custom RTL skeletons
- behavioral FFT model for simulation if needed
- simple reference PSS correlation path
- deterministic testbench vectors

But Step 30 should also clearly note where a future Xilinx FFT IP could be inserted.

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

Step 30 should propose how the integer CFO/PSS-SSS path connects to this.

Possible placement to analyze:

Option A:
- Run integer CFO after frame detection but before fractional CFO correction.

Option B:
- Run integer CFO after timing and fractional CFO correction using corrected time-domain frame.

Option C:
- Use PSS/SSS path as a separate validation/detection stage after coarse frame detection.

Recommended for this project:
- Start with Option B or C, because Step 29 already validates corrected time-domain frame output.

The document should make a clear recommendation.

## Algorithm background to document

Write a practical explanation of integer CFO in OFDM.

Include the idea that CFO can be decomposed as:

normalized CFO = integer_subcarrier_offset + fractional_subcarrier_offset

Where:

fractional CFO:
- already handled by the current CP/timing/fractional CFO path

integer CFO:
- appears as a subcarrier-index shift after FFT
- can be estimated by searching over candidate frequency shifts using a known synchronization sequence

Explain that a PSS-like known sequence can be used for integer CFO detection.

## PSS/SSS representation decision

Discuss these options:

Option 1 — Frequency-domain PSS/SSS reference

Store PSS/SSS in frequency domain.
After FFT of received symbol, compare shifted bins against known reference.

Pros:
- Natural for integer CFO because integer CFO appears as a bin shift.
- Easy to search candidate integer offsets.
- Good for RTL once FFT output is available.

Cons:
- Requires FFT before correlation.

Option 2 — Time-domain IFFT'ed PSS/SSS reference

Store already-IFFT'ed PSS/SSS time-domain sequence.
Use time-domain correlation.

Pros:
- Can be used before FFT.
- Good for frame/time detection.
- Reference can be precomputed offline.

Cons:
- Integer CFO appears as a complex phase ramp in time domain, not simply a bin shift.
- Integer CFO search may require multiple derotation hypotheses or more complex correlation.

Required recommendation:

For this project, recommend:
- Use frequency-domain PSS reference for integer CFO estimation.
- Optionally keep an IFFT'ed time-domain PSS for future time-domain detection experiments.

Reason:
- The main target of integer CFO is subcarrier shift estimation, and frequency-domain correlation makes this direct.

## Candidate integer CFO algorithm

Specify a simple first implementation.

Given:

Y[k] = FFT of corrected received synchronization symbol
PSS_REF[k] = known frequency-domain PSS reference
m = candidate integer CFO shift

Metric:

metric[m] = sum over active PSS bins k of conj(PSS_REF[k]) * Y[k + m]

Score:

score[m] = |metric[m]|^2

Decision:

integer_cfo_hat = argmax_m score[m]

Search range example:

m in [-M, +M]

For first RTL skeleton:

M = 4 or 8

The document should explain that the exact range can be expanded later.

## Initial hardware architecture to specify

Create a block-level architecture for Step 31+.

Recommended staged architecture:

corrected time-domain frame
-> sync symbol extractor
-> FFT256 wrapper/skeleton
-> active-bin selector
-> integer CFO candidate correlator
-> peak detector / argmax
-> integer CFO estimate register

Where:

sync symbol extractor:
- selects one OFDM symbol from corrected frame output

FFT256 wrapper/skeleton:
- initially may be a placeholder/simulation model
- later replaceable by custom FFT RTL or Xilinx FFT IP

active-bin selector:
- maps FFT bins to active PSS bins

integer CFO candidate correlator:
- tries candidate shifts m = -M ... +M

peak detector:
- chooses max score and emits integer_cfo_hat

## RTL interface proposal

Propose a future RTL module interface, but do not implement it yet unless existing project convention strongly prefers stubs.

Example future interface:

module integer_cfo_estimator_top #(
    parameter FFT_LEN = 256,
    parameter NUM_PSS_BINS = 127,
    parameter SEARCH_RADIUS = 4,
    parameter IQ_WIDTH = 16,
    parameter ACC_WIDTH = 48
)(
    input  wire                     aclk,
    input  wire                     aresetn,

    input  wire                     s_axis_tvalid,
    output wire                     s_axis_tready,
    input  wire [2*IQ_WIDTH-1:0]     s_axis_tdata,
    input  wire                     s_axis_tlast,

    output wire                     m_axis_tvalid,
    input  wire                     m_axis_tready,
    output wire signed [15:0]        m_axis_integer_cfo,
    output wire [ACC_WIDTH-1:0]      m_axis_peak_score,

    output wire                     done,
    output wire                     error
);

Keep this as a documented proposal in Step 30.

## Verification plan

Specify a staged verification plan.

Step 31 target:

Step 31 — FFT/PSS integer CFO estimator skeleton and simulation testbench

Step 31 should likely implement:

Option 31A:
- Create a pure RTL candidate correlator that consumes synthetic frequency-domain FFT bins.
- No FFT implementation yet.
- Testbench directly feeds shifted PSS frequency bins.
- Verify integer_cfo_hat.

Option 31B:
- Create an FFT256 wrapper/skeleton plus behavioral FFT model for simulation.
- More realistic but more work.

Required recommendation:

Start with Option 31A.

Reason:
- It isolates the integer CFO estimator logic from FFT implementation complexity.
- It avoids pulling in Xilinx IP too early.
- It gives a deterministic RTL testbench for candidate shift / argmax behavior.

Then later:

Step 32:
- Add FFT wrapper or custom FFT frontend.

Step 33:
- Integrate integer CFO estimator with corrected frame output path.

## Required output document

Create or update:

docs/step30_integer_cfo_pss_sss_architecture.md

The document must include:

# Step 30 — Integer CFO / PSS-SSS Algorithm-to-RTL Architecture

## Objective
## Current validated receiver state
## Integer CFO problem definition
## Relationship to fractional CFO
## PSS/SSS representation choices
## Recommended representation for this project
## Candidate integer CFO algorithm
## Proposed block-level architecture
## Proposed RTL interface
## Fixed-point and accumulator considerations
## Verification strategy
## Recommended Step 31 target
## Future integration notes
## Conclusion

## Fixed-point considerations

Include practical notes:

- Input IQ width is likely 16-bit signed.
- Complex multiply between FFT bin and conjugated PSS reference may produce roughly 32-bit products.
- Accumulating across many PSS bins requires wider accumulators.
- Use at least 48-bit accumulation for first RTL implementation.
- Magnitude-squared may require even wider intermediate width.
- For first skeleton, compare approximate power/score with safe truncation only after accumulation.

Do not over-optimize in Step 30.

## Current status update

Update:

ai_context/current_status.md

Add a Step 30 entry:

Step 30 — Integer CFO / PSS-SSS architecture spec
Status: completed as architecture/specification step

Purpose:
- Define how integer CFO estimation should be added after the validated frame/timing/fractional CFO path.
- Compare frequency-domain and time-domain PSS/SSS representations.
- Recommend frequency-domain PSS correlation for integer CFO estimation.
- Define the proposed RTL block architecture and verification roadmap.

Recommended next step:
- Step 31: implement and verify a frequency-domain integer CFO candidate correlator using synthetic FFT-bin inputs before adding any FFT IP.

Do not delete previous step history.

## Optional README update

If README.md has a progress section, add one short line:

- Step 30: Integer CFO / PSS-SSS algorithm-to-RTL architecture specified; Step 31 will start with a frequency-domain candidate correlator before FFT integration.

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
git status --short

Do not run Vivado or Vitis.

## Final response required

After completing Step 30, report:

Step 30 architecture/specification update complete.

Files changed:
- ...

Main decisions:
- Integer CFO will be treated as a frequency-bin shift after FFT.
- Frequency-domain PSS reference is recommended for integer CFO estimation.
- Time-domain IFFT'ed PSS can be kept for future detection experiments but is not the primary integer CFO path.
- Step 31 should start with a frequency-domain candidate correlator using synthetic FFT-bin inputs, before adding FFT IP.

Next recommended step:
- Step 31 — implement integer CFO candidate correlator RTL and deterministic simulation testbench.
