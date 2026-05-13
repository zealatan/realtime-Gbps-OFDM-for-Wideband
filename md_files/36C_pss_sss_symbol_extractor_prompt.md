# Step 36C — PSS/SSS Symbol Extractor Standalone RTL/TB

## Mandatory archival rule

Before modifying any file, save this entire prompt verbatim as:

md_files/36C_pss_sss_symbol_extractor_prompt.md

If the md_files/ directory does not exist, create it first.

## Working directory

/home/zealatan/RTL_SYNC_STEP36C_EXTRACTOR

## Branch / worktree context

This worktree is dedicated to Step 36C:

branch: step36c_pss_sss_extractor
path: /home/zealatan/RTL_SYNC_STEP36C_EXTRACTOR

The main repository remains at:

/home/zealatan/RTL_SYNC

Do not modify the main worktree from this session.

## Important workflow separation

This project uses a split workflow:

WSL/Linux side:
- Claude Code works here.
- Source/documentation editing is done here.
- RTL/testbench/simulation work is done here.
- Vivado xsim simulation may be run from WSL if supported.

Windows side:
- The user manually runs Vivado/Vitis when needed.
- The user manually generates actual Xilinx IP/XCI when needed.
- The user manually programs the ZCU102 board later.
- The user manually runs UART/COM tests later.

For this step:
- Do not run Vitis.
- Do not access COM5.
- Do not modify board/Vitis host files.
- Do not claim any board result.
- Do not modify existing top integration files.
- Do not integrate into the full receiver yet.

This is a standalone PSS/SSS symbol extractor RTL/TB step.

## Critical output rule

Do not print long source files into the chat.

Create or edit files directly in the filesystem.

At the end, report only:
- files changed
- tests run
- PASS/FAIL/pending
- next step

## Context

The RTL_SYNC project currently has:

Step 29I:
- ZCU102 board regression PASS / CLOSED.
- AXI-Lite, BRAM source, stream handshake, frame detector, corrected output BRAM, and PS readback path validated.

Step 30:
- Meyr-based integer CFO / PSS-SSS architecture specified.
- Correct C-reference formulas:
  term1[j] = PSS_FFT[j] * conj(SSS_FFT[j])
  term2[j] = mU[j + CP_LEN] * conj(goldU[j + CP_LEN])
  intCFO = peakIndexMeyr - 255

Step 31:
- Meyr direct-correlation core passed.
- PASS: 32, FAIL: 0, CI GATE: PASSED.

Step 32:
- Meyr PSS/SSS product generator and frequency-domain estimator top passed.
- Product generator PASS: 13, FAIL: 0.
- Estimator top PASS: 32, FAIL: 0.

Step 33:
- real mU/goldU audit completed.
- real mU/goldU-derived term2 ROM remains pending because source arrays are external.

Step 34:
- FFT256 frontend behavioral/bypass integration with Meyr estimator passed.
- PASS: 31, FAIL: 0, CI GATE: PASSED.
- No Xilinx FFT IP was used.
- Production FFT remains pending.

Step 35A:
- CORDIC atan2 wrapper preparation passed.
- PASS: 35, FAIL: 0, CI GATE: PASSED.
- Actual Xilinx CORDIC XCI generation remains pending.

Step 35B:
- NCO sin/cos wrapper preparation passed.
- PASS: 88, FAIL: 0, CI GATE: PASSED.
- Actual Xilinx CORDIC/DDS XCI generation remains pending.

Step 36A:
- Xilinx FFT256 IP generation/interface audit is being handled separately in the Step36A worktree.

Step 36B:
- CORDIC/NCO Xilinx IP generation/interface audit is being handled separately in the Step36B worktree.

Step 36C now focuses only on the PSS/SSS symbol extractor that will later sit between corrected frame output and FFT frontend.

## Why Step 36C is needed

The current verified board path outputs a corrected time-domain frame.

The future Meyr integer CFO path needs two OFDM symbols:

corrected time-domain frame
-> PSS/SSS symbol extractor
-> PSS FFT
-> SSS FFT
-> term1 = PSS_FFT * conj(SSS_FFT)
-> Meyr integer CFO estimator

Before connecting this into the full receiver, we need a standalone extractor that:

- consumes a corrected frame stream
- selects one PSS symbol window
- selects one SSS symbol window
- optionally removes CP
- outputs exactly NSC samples for each symbol
- preserves sample order and index
- asserts valid/last correctly
- handles frame length and configuration safely

Step 36C should implement and verify this extractor standalone, without FFT IP and without full receiver integration.

## Step 36C goal

Create and verify a standalone RTL module:

rtl/pss_sss_symbol_extractor.v

The extractor should:

1. Accept a corrected frame stream.
2. Count input sample indices within the frame.
3. Extract PSS symbol samples according to configurable offset.
4. Extract SSS symbol samples according to configurable offset.
5. Remove CP by starting at FFT-window start, not CP start.
6. Output two NSC-length symbol streams:
   - symbol_sel = 0 for PSS
   - symbol_sel = 1 for SSS
7. Preserve sample index 0..NSC-1 within each extracted symbol.
8. Assert output tlast on index NSC-1 for each symbol.
9. Produce done after both symbols have been emitted.
10. Produce error on malformed frame or invalid config.

This step must remain standalone:
- no FFT integration
- no Meyr estimator integration
- no board wrapper changes
- no host/Vitis changes
- no README/current_status updates in this branch

## Files to inspect first

Inspect these files before editing:

rtl/
tb/
scripts/
docs/
md_files/

Relevant existing files:

rtl/frac_cfo_frame_corrector_top.v
rtl/fft256_dual_symbol_frontend.v
rtl/meyr_integer_cfo_fft_frontend_top.v
docs/step34_fft256_frontend_behavioral_integration.md
docs/step30_meyr_integer_cfo_pss_sss_architecture.md
docs/step32_meyr_product_generator_real_term2.md
docs/step33_real_mU_goldU_term2_reference_audit.md

Search for frame/symbol/extractor style:

find . -type f | grep -Ei "symbol|extract|frame|fft|meyr|cfo"
grep -R "symbol_sel\|s_symbol_sel\|m_symbol_sel\|frame_index\|frame_len\|tlast\|extract\|FFT_LEN\|NSC\|CP_LEN" -n rtl tb docs scripts 2>/dev/null | head -300
grep -R "module .*extract\|module .*frontend\|module .*frame" -n rtl tb 2>/dev/null | head -200

Also inspect script style:

find scripts -maxdepth 1 -type f -name "run_*_sim.sh" -print

## Do not modify shared status files

To avoid merge conflicts with other Step 36 worktrees, do not modify:

README.md
ai_context/current_status.md

All Step 36C status should go into:

docs/step36C_pss_sss_symbol_extractor.md

The main branch can later update README/current_status once Step 36A/36B/36C are merged.

## Required RTL module

Create:

rtl/pss_sss_symbol_extractor.v

Recommended interface:

module pss_sss_symbol_extractor #(
    parameter NSC = 256,
    parameter CP_LEN = 32,
    parameter IQ_WIDTH = 16,
    parameter FRAME_INDEX_WIDTH = 12
)(
    input  wire                         aclk,
    input  wire                         aresetn,

    input  wire                         start,

    input  wire [FRAME_INDEX_WIDTH-1:0] pss_fft_start,
    input  wire [FRAME_INDEX_WIDTH-1:0] sss_fft_start,
    input  wire [FRAME_INDEX_WIDTH-1:0] frame_len,

    input  wire                         s_axis_tvalid,
    output wire                         s_axis_tready,
    input  wire [2*IQ_WIDTH-1:0]         s_axis_tdata,
    input  wire                         s_axis_tlast,

    output reg                          m_axis_tvalid,
    input  wire                         m_axis_tready,
    output reg [2*IQ_WIDTH-1:0]          m_axis_tdata,
    output reg                          m_axis_tlast,
    output reg                          m_symbol_sel,
    output reg [7:0]                    m_symbol_index,

    output reg                          busy,
    output reg                          done,
    output reg                          error,
    output reg [3:0]                    error_code
);

Recommended signal meaning:
- pss_fft_start: frame sample index of the first FFT-window sample of PSS, after CP removal.
- sss_fft_start: frame sample index of the first FFT-window sample of SSS, after CP removal.
- frame_len: total corrected frame length.
- input stream is corrected frame time-domain samples.
- output stream emits exactly NSC PSS samples and NSC SSS samples.

symbol_sel:
- 0 = PSS
- 1 = SSS

m_symbol_index:
- 0..NSC-1 within each extracted symbol

m_axis_tlast:
- 1 only on sample index NSC-1 for each symbol

done:
- one-cycle pulse after both PSS and SSS symbols have been completely emitted.

busy:
- high from accepted start until done/error.

error:
- sticky or pulsed, but document behavior.
- Should be asserted if configuration is invalid or frame ends before both symbols are extracted.

error_code recommendation:
- 0 = no error
- 1 = invalid_config
- 2 = frame_tlast_too_early
- 3 = output_backpressure_overflow_or_internal_error
- 4 = start_while_busy

Keep implementation simple and deterministic.

## Required behavior

The extractor should operate in a streaming-friendly way.

Recommended behavior:

1. IDLE:
   - wait for start
   - validate config:
     pss_fft_start + NSC <= frame_len
     sss_fft_start + NSC <= frame_len
     pss_fft_start != sss_fft_start unless intentionally allowed
   - if invalid, assert error
   - if valid, enter CAPTURE/STREAM state

2. CAPTURE/STREAM:
   - accept input samples when s_axis_tvalid && s_axis_tready.
   - keep frame sample counter.
   - if current frame index is in PSS window:
     output sample with symbol_sel=0 and symbol_index=current_idx - pss_fft_start.
   - if current frame index is in SSS window:
     output sample with symbol_sel=1 and symbol_index=current_idx - sss_fft_start.
   - If output is not ready when a selected sample arrives, either:
     A. deassert s_axis_tready to apply backpressure, preferred
     or
     B. use a small skid/hold register.
   - Do not drop selected samples.

3. DONE:
   - after both windows emitted NSC samples.
   - done pulse.
   - busy low.

Implementation may assume PSS and SSS windows do not overlap.
If overlap is not supported, invalid_config should catch overlap.

## Backpressure policy

Preferred simple policy:
- s_axis_tready = 1 when no selected output is pending.
- If selected sample must be output and m_axis_tready=0, hold that sample and deassert s_axis_tready until consumed.

This avoids dropping selected samples.

Use a one-deep hold register if needed.

The testbench must check output backpressure.

## Important design assumptions

For this standalone step, use explicit pss_fft_start and sss_fft_start.

Do not hardcode PSS/SSS positions into the module.

Do not assume a full 5G NR frame.

This is a generic OFDM-like frame extractor intended for the current RTL_SYNC project.

Recommended default for tests:
- NSC = 256
- CP_LEN = 32
- PSS FFT start = 32
- SSS FFT start = 32 + 256 + 32 = 320
- frame_len >= 576 or larger

This matches the earlier observation that the frame buffer may need to grow beyond 288 samples to reach SSS.

## Required testbench

Create:

tb/pss_sss_symbol_extractor_tb.sv

The testbench must be deterministic and self-checking.

It should:
- Generate a synthetic corrected frame.
- Mark each input sample with a unique word that encodes frame index.
- Configure pss_fft_start and sss_fft_start.
- Feed the frame through AXI-stream style valid/ready.
- Capture output samples.
- Verify:
  - PSS output has exactly NSC samples.
  - SSS output has exactly NSC samples.
  - PSS output data matches input frame[pss_fft_start + i].
  - SSS output data matches input frame[sss_fft_start + i].
  - symbol_sel is correct.
  - symbol_index is correct.
  - tlast is asserted only at i=NSC-1 for each symbol.
  - done behavior is correct.
  - error behavior is correct for invalid cases.

Required tests: at least 12 groups.

Recommended tests:

T1 reset_defaults:
- After reset, busy=0, done=0, error=0, m_axis_tvalid=0.

T2 basic_extract:
- frame_len=640
- pss_fft_start=32
- sss_fft_start=320
- no backpressure
- expect 512 outputs total.

T3 pss_data_exact:
- Check selected PSS samples match source frame.

T4 sss_data_exact:
- Check selected SSS samples match source frame.

T5 tlast_positions:
- Check tlast at PSS index 255 and SSS index 255 only.

T6 output_backpressure:
- Deassert m_axis_tready periodically.
- Verify no selected sample is lost or duplicated.

T7 input_gaps:
- Insert gaps in s_axis_tvalid.
- Verify extraction still correct.

T8 different_offsets:
- Use pss_fft_start=16, sss_fft_start=400 if frame_len allows.
- Verify output.

T9 invalid_config_pss_out_of_range:
- pss_fft_start + NSC > frame_len.
- Expect error.

T10 invalid_config_sss_out_of_range:
- sss_fft_start + NSC > frame_len.
- Expect error.

T11 early_tlast:
- Input tlast arrives before both symbols extracted.
- Expect error.

T12 start_while_busy:
- Assert start while busy.
- Expect ignored or error according to documented behavior.

T13 optional overlap_invalid:
- pss and sss windows overlap.
- Expect invalid_config if overlap unsupported.

T14 optional exact_minimum_frame:
- frame_len exactly equals sss_fft_start + NSC.
- Expect success.

Required final output:
PASS: <count> FAIL: <count>
CI GATE: PASSED
or
CI GATE: FAILED

## Test data format

Use 32-bit IQ word format consistent with the project:

word[15:0] = I
word[31:16] = Q

For easy checking, use:
I = frame_index[15:0]
Q = bitwise or simple transformed index, for example ~frame_index[15:0] or frame_index + 1000

Keep values within signed 16-bit if needed.

Do not use random data unless seeded and deterministic.

## Required simulation script

Create:

scripts/run_pss_sss_symbol_extractor_sim.sh

Use existing project script style.

The script should:
- compile rtl/pss_sss_symbol_extractor.v
- compile tb/pss_sss_symbol_extractor_tb.sv
- run xsim
- save logs according to project convention
- grep for [FAIL]/FATAL/CI GATE failure
- exit nonzero on failure
- be executable

Important:
- Avoid bare grep "FAIL" if it falsely matches "FAIL: 0".
- Prefer grep patterns like "[FAIL]" or "CI GATE: FAILED".

## Required documentation

Create:

docs/step36C_pss_sss_symbol_extractor.md

The document must include:

# Step 36C — PSS/SSS Symbol Extractor Standalone RTL/TB

Sections:
- Objective
- Relationship to Step 34
- Why this extractor is needed
- Interface definition
- PSS/SSS offset convention
- CP removal convention
- Output stream convention
- Backpressure policy
- Error handling
- Testbench scenarios
- Simulation command
- Simulation result
- Known limitations
- Next steps

Known limitations must include:
- Not integrated with frac_cfo_frame_corrector_top yet.
- Not connected to FFT frontend yet.
- PSS/SSS positions are externally configured.
- No board validation in Step 36C.
- Real OFDM/PSS/SSS waveform validation is not part of this standalone step.

## Do not modify

Do not modify:
README.md
ai_context/current_status.md
host/
sw/
src/
include/

Do not modify:
rtl/frac_cfo_frame_corrector_top.v
rtl/timing_frac_cfo_top.v
rtl/frac_cfo_sync_bram_test_wrapper.v
rtl/meyr_integer_cfo_fft_frontend_top.v
rtl/fft256_dual_symbol_frontend.v

Do not modify CORDIC/NCO/IP audit files in this Step 36C lane.

Do not run board tests.

Do not perform destructive git operations.

Do not claim full receiver integration.

## Local checks and simulation

Run:

export PATH="/home/zealatan/Downloads/Vivado/2022.2/bin:$PATH"
bash scripts/run_pss_sss_symbol_extractor_sim.sh

If Vivado is unavailable, do not fake the result. Document simulation pending.

After running:

grep -R "CI GATE\|PASS:\|FAIL:" -n logs build . 2>/dev/null | head -100
git status --short

## Acceptance criteria

Step 36C is complete if:

- md_files/36C_pss_sss_symbol_extractor_prompt.md exists.
- rtl/pss_sss_symbol_extractor.v exists.
- tb/pss_sss_symbol_extractor_tb.sv exists.
- scripts/run_pss_sss_symbol_extractor_sim.sh exists and is executable.
- docs/step36C_pss_sss_symbol_extractor.md exists.
- README.md is not modified.
- ai_context/current_status.md is not modified.
- Existing top integration files are not modified.
- No board/Vitis files are modified.
- Testbench has at least 12 deterministic test groups.
- Simulation result is reported honestly.
- The standalone limitation is explicit.

## Final response required

After completing Step 36C, report:

Step 36C PSS/SSS symbol extractor complete.

Files changed:
- ...

Main implementation:
- rtl/pss_sss_symbol_extractor.v
- tb/pss_sss_symbol_extractor_tb.sv
- scripts/run_pss_sss_symbol_extractor_sim.sh
- docs/step36C_pss_sss_symbol_extractor.md

Design decisions:
- PSS/SSS offset convention: externally configured FFT-window start
- CP removal: handled by using FFT-window start, not CP start
- output convention: symbol_sel 0=PSS, 1=SSS; symbol_index 0..255
- backpressure policy: describe
- error policy: describe

Simulation:
- command: bash scripts/run_pss_sss_symbol_extractor_sim.sh
- result: PASS / FAIL / pending
- CI gate: PASSED / FAILED / not run
- PASS/FAIL count

Limitations:
- not integrated with FFT yet
- not integrated with corrected frame top yet
- no board validation

Next recommended step:
- Integrate extractor output with FFT frontend after Step 36A FFT IP audit, or run extractor + Step 34 behavioral FFT integration as an intermediate Step 37.
