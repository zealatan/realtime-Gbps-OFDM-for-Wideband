# Step 33 — Real mU/goldU Reference Audit and term2 ROM Generation

## Mandatory archival rule

Before modifying any file, save this entire prompt verbatim as:

md_files/33_real_mU_goldU_term2_reference_audit_prompt.md

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

This Step 33 is primarily a C-reference audit + ROM generation + simulation step.

## Context

Step 29I is complete and passed on ZCU102.

Step 30 is complete and defines the Meyr-based integer CFO architecture.

Step 31 is complete and passed simulation:
- rtl/meyr_integer_cfo_core.v
- 511-lag direct correlation
- zero CFO peak index = 255
- intCFO = peak_index - 255
- synthetic XOR-shift32 PRNG term2 ROM
- PASS: 32, FAIL: 0, CI GATE: PASSED

Step 32 is complete and passed simulation:
- rtl/meyr_pss_sss_product_gen.v
- rtl/meyr_term2_ref_rom.v
- rtl/meyr_integer_cfo_freq_estimator_top.v
- Product generator PASS: 13, FAIL: 0, CI GATE: PASSED
- Estimator top PASS: 32, FAIL: 0, CI GATE: PASSED

Step 32 verified the structure:

synthetic PSS_FFT/SSS_FFT
-> term1 = PSS_FFT * conj(SSS_FFT)
-> synthetic fallback term2 ROM
-> Meyr integer CFO direct-correlation core
-> peak_index
-> intCFO

However, Step 32 explicitly documented:

Real mU/goldU ROM status: pending

Reason:
- ref/receiver.c verifies the formula:
  term1[j] = PSS_FFT[j] * conj(SSS_FFT[j])
  term2[j] = mU[j + CP_LEN] * conj(goldU[j + CP_LEN])
- But mU/goldU sequences appear to be external parameters in ref/receiver.c.
- The generation code or concrete values may not be present in ref/receiver.c itself.

Therefore Step 33 must audit the reference source and determine how to obtain or generate the real term2 ROM.

## Step 33 goal

The goal of Step 33 is to close or precisely characterize the gap between the synthetic term2 ROM and the real C-reference term2.

Step 33 should:

1. Audit the repository for mU/goldU definitions, generation code, dumps, headers, Python scripts, or data files.
2. Determine whether real mU/goldU-derived term2 values can be generated from files already in this repository.
3. If possible, create a reproducible term2 ROM generation flow.
4. If possible, generate a real term2 ROM file/module.
5. Add tests that verify ROM values against the generated reference data.
6. If real data is not available, document exactly what is missing and preserve the synthetic fallback as the only verified path.
7. Do not proceed to FFT integration yet.

This is intentionally before FFT integration. We do not want to connect FFT to a synthetic-only reference path and accidentally claim C-reference equivalence.

## Critical C-reference formulation

The C reference formulation is:

term1[j] = PSS_FFT[j] * conj(SSS_FFT[j])

term2[j] = mU[j + CP_LEN] * conj(goldU[j + CP_LEN])

Meyr correlation:
corr = xcorr(term2, term1)

Peak mapping:
peakIndexMeyr = argmax |corr|^2
intCFO = peakIndexMeyr - 255

For NSC=256:
- 511 correlation lags
- zero CFO peak index = 255
- intCFO = peak_index - 255

Do not change this formula.

## Files to inspect first

Inspect repository structure:

find . -maxdepth 4 -type f | sort

Search for all relevant C-reference symbols and possible sequence generation files:

grep -R "carrierFreqOffsetEstMeyr\|fft_correlation_Meyr\|Meyr\|meyr\|intCFO\|peakIndexMeyr" -n . 2>/dev/null
grep -R "goldU\|mU\|gold\|Gold\|mseq\|m_seq\|PSS\|SSS\|CP_LEN\|NSC" -n . 2>/dev/null
grep -R "zadoff\|Zadoff\|ZC\|zc\|mSequence\|sequence\|sync" -n . 2>/dev/null
find . -type f | grep -Ei "\.(c|h|cpp|hpp|py|m|mat|txt|csv|hex|mem|dat|json|md)$"

Inspect at minimum, if present:

ref/receiver.c
ref/
docs/step30_meyr_integer_cfo_pss_sss_architecture.md
docs/step32_meyr_product_generator_real_term2.md
rtl/meyr_term2_ref_rom.v
rtl/meyr_integer_cfo_freq_estimator_top.v
tb/meyr_integer_cfo_freq_estimator_top_tb.sv
ai_context/current_status.md
README.md

## Audit questions to answer

The Step 33 documentation must answer:

1. Where are mU and goldU declared?
2. Are mU and goldU passed as function arguments?
3. Are mU and goldU generated inside this repository?
4. Are mU and goldU stored in any file format such as .h, .c, .txt, .csv, .hex, .mem, .mat, .json?
5. What are the types and scaling of mU/goldU?
6. Are they complex float, double, fixed-point, int16, or another type?
7. What is CP_LEN?
8. What is NSC?
9. Why does the formula use j + CP_LEN?
10. Can term2[j] = mU[j + CP_LEN] * conj(goldU[j + CP_LEN]) be generated reproducibly from current repo files?
11. If not, what exact missing artifact is needed?

## Possible outcomes

Step 33 may result in one of three outcomes.

Outcome A — Real mU/goldU available:
- mU/goldU values or generation code are found.
- Generate real term2 values.
- Create ROM/data file from real C-reference values.
- Add tests verifying the ROM.

Outcome B — Partial data available:
- Some definitions are found, but not enough to generate exact term2.
- Document what is available and what is missing.
- Keep synthetic fallback as the only verified RTL path.
- Create a placeholder generation script with clear TODOs only if useful.

Outcome C — Real data unavailable:
- mU/goldU are only external parameters and no generator/data exists in this repo.
- Document this clearly.
- Do not claim real ROM implementation.
- Preserve synthetic fallback and mark real term2 ROM pending.
- Recommend next action: obtain mU/goldU dump from C model or add sequence generator.

Be honest. Do not fabricate real reference constants.

## Preferred implementation if real data is available

If mU/goldU data can be generated or extracted, create:

scripts/generate_meyr_term2_rom.py

Purpose:
- Read or generate mU/goldU according to the C reference.
- Compute term2[j] = mU[j + CP_LEN] * conj(goldU[j + CP_LEN]) for j=0..255.
- Quantize to the RTL PROD_WIDTH format.
- Emit a ROM include file or memory file.

Possible outputs:
- rtl/meyr_term2_ref_rom_real.vh
or
- data/meyr_term2_real.hex
or
- rtl/meyr_term2_ref_rom_real.v

Use the existing project style if there is already a data/ or generated/ directory.

The generated file should include:
- 256 term2_i values
- 256 term2_q values
- clear comment header:
  Generated by scripts/generate_meyr_term2_rom.py
  Source: <file/source>
  NSC=256
  CP_LEN=<value>
  Formula: term2[j] = mU[j+CP_LEN] * conj(goldU[j+CP_LEN])
  Quantization: <describe>

Then update or extend:

rtl/meyr_term2_ref_rom.v

to support a real ROM mode, for example:

parameter USE_SYNTHETIC_FALLBACK = 1

If USE_SYNTHETIC_FALLBACK=1:
- Preserve existing synthetic PRNG behavior.

If USE_SYNTHETIC_FALLBACK=0 and real data exists:
- Use the real generated ROM.

Important:
- Preserve Step 32 tests.
- If changing rtl/meyr_term2_ref_rom.v, rerun Step 32 simulations.

## If real data is not available

If mU/goldU cannot be generated from this repository:

1. Do not create fake real ROM constants.
2. Keep rtl/meyr_term2_ref_rom.v synthetic fallback as-is.
3. Create a clear audit document saying real mU/goldU-derived term2 ROM is pending.
4. Optionally create a template script:

scripts/generate_meyr_term2_rom.py

But only if it is useful and explicitly marked as requiring external mU/goldU input.

A useful template script may:
- Accept input CSV or JSON containing mU and goldU arrays.
- Compute term2 from those arrays.
- Emit a ROM include file.
- Include --help.
- Not claim to generate real data unless actual arrays are supplied.

If creating this template, also create a small sample synthetic input under data/ or tests/ only if consistent with project style.

## Required tests if real ROM is implemented

If real ROM data is implemented, create:

tb/meyr_term2_ref_rom_tb.sv

Test requirements:
- Reset-independent ROM read behavior.
- Check selected addresses:
  addr 0
  addr 1
  addr 2
  addr 127
  addr 128
  addr 254
  addr 255
- Expected values must match generated reference data.
- Include at least 8 checks.
- Print:
  PASS: <count> FAIL: <count>
  CI GATE: PASSED
  or CI GATE: FAILED

Create:

scripts/run_meyr_term2_ref_rom_sim.sh

Then run:
bash scripts/run_meyr_term2_ref_rom_sim.sh

Also rerun Step 32 if rtl/meyr_term2_ref_rom.v changed:
bash scripts/run_meyr_pss_sss_product_gen_sim.sh
bash scripts/run_meyr_integer_cfo_freq_estimator_top_sim.sh

If Step 31 core was not modified, no need to rerun Step 31.

## Required tests if real ROM is not available

If real ROM data is not available but a generator template is created:

Create Python self-checks only if lightweight and practical.

For example:
python3 scripts/generate_meyr_term2_rom.py --help

Optionally create a small synthetic JSON/CSV sample and verify that the script can emit a ROM from externally provided arrays.

Do not call this real mU/goldU.

The documentation must say:
- real mU/goldU-derived term2 ROM remains pending
- script supports external-dump-based generation
- exact source arrays are required before C-reference-equivalent ROM can be produced

## Documentation update

Create:

docs/step33_real_mU_goldU_term2_reference_audit.md

The document must include:

# Step 33 — Real mU/goldU Reference Audit and term2 ROM Generation

Sections:
- Objective
- Relationship to Step 30, Step 31, and Step 32
- C-reference formula
- Repository audit summary
- mU/goldU source analysis
- CP_LEN and NSC findings
- term2 generation feasibility
- Implemented artifacts
- ROM status
- Simulation or script-check results
- Impact on next steps
- Conclusion

The ROM status section must explicitly state one of:

Case A:
Real mU/goldU-derived term2 ROM: implemented and verified

Case B:
Real mU/goldU-derived term2 ROM: partially blocked
Reason: <specific reason>

Case C:
Real mU/goldU-derived term2 ROM: pending
Reason: mU/goldU values or generation source are not present in this repository

Also include:
Synthetic fallback ROM: implemented and verified in Step 32

## Current status update

Update:

ai_context/current_status.md

Add a Step 33 entry.

If real ROM is implemented:

Step 33 — Real mU/goldU term2 ROM generation
Status: completed, real term2 ROM implemented and verified

Purpose:
- Audit C-reference mU/goldU source.
- Generate real term2[j] = mU[j+CP_LEN] * conj(goldU[j+CP_LEN]).
- Verify selected ROM values against generated reference.
- Preserve synthetic fallback mode.

Observed:
- <simulation results>

Next recommended step:
- Step 34: connect real term2 ROM mode into the frequency-domain estimator top and compare synthetic vs real ROM behavior.

If real ROM is not available:

Step 33 — Real mU/goldU term2 reference audit
Status: completed as audit; real term2 ROM pending

Purpose:
- Audit repository for mU/goldU source data or generation code.
- Determine whether C-reference-equivalent term2 ROM can be generated.
- Preserve Step 32 synthetic fallback path.

Findings:
- mU/goldU are external to ref/receiver.c or not fully available in this repository.
- Real mU/goldU-derived term2 ROM cannot be generated yet from available files.
- Synthetic fallback ROM remains the verified simulation path.

Next recommended step:
- Obtain or dump mU/goldU arrays from the C reference environment, or proceed with FFT/frontend structural integration while clearly marking the estimator as synthetic-reference until real term2 is supplied.

Do not delete previous step history.

## Optional README update

If README.md has a progress section, add one short line.

If real ROM implemented:
- Step 33: Real mU/goldU-derived Meyr term2 ROM generated and verified; synthetic fallback preserved.

If real ROM pending:
- Step 33: mU/goldU reference audit completed; real term2 ROM remains pending because source arrays are external/not present, while synthetic fallback remains verified.

Do not rewrite the full README.

## Do not modify

Do not modify board/Vitis host files.

Do not modify:
host/
sw/
src/
include/

Do not modify frame/timing/fractional CFO modules.

Do not modify BRAM wrapper.

Avoid modifying rtl/meyr_integer_cfo_core.v.

Do not run board tests.

Do not perform destructive git operations.

Do not claim real ROM implementation unless actual real data is found and used.

## Local checks and simulation

Run only relevant WSL-side checks.

Always run:

grep -R "mU\|goldU\|carrierFreqOffsetEstMeyr\|fft_correlation_Meyr\|CP_LEN\|NSC" -n ref rtl tb docs scripts . 2>/dev/null | head -200
git status --short

If a Python generator script is created:
python3 scripts/generate_meyr_term2_rom.py --help

If a ROM testbench is created:
bash scripts/run_meyr_term2_ref_rom_sim.sh

If rtl/meyr_term2_ref_rom.v or estimator top was modified:
bash scripts/run_meyr_pss_sss_product_gen_sim.sh
bash scripts/run_meyr_integer_cfo_freq_estimator_top_sim.sh

If Vivado is not available in this WSL environment, do not fake the result. Document simulation pending.

## Acceptance criteria

Step 33 is complete if:

- md_files/33_real_mU_goldU_term2_reference_audit_prompt.md exists.
- docs/step33_real_mU_goldU_term2_reference_audit.md exists.
- ai_context/current_status.md is updated.
- README.md is optionally updated with one-line accurate status.
- The repository audit result is explicit and honest.
- Real term2 ROM status is one of:
  implemented and verified, partially blocked, or pending.
- If real ROM is implemented:
  - generation source is documented
  - generated ROM/data file exists
  - ROM testbench exists
  - simulation result is reported
- If real ROM is not implemented:
  - exact missing artifact is documented
  - synthetic fallback status remains clear
  - no false claim of C-reference-equivalent real ROM is made

## Final response required

After completing Step 33, report:

Step 33 real mU/goldU term2 reference audit complete.

Files changed:
- ...

Audit result:
- mU source: found / external / missing
- goldU source: found / external / missing
- CP_LEN: found value / not found
- NSC: found value / not found
- real term2 ROM status: implemented / partially blocked / pending

Implemented artifacts:
- ...

Simulation / checks:
- ...

C-reference alignment:
- term1 formula remains: PSS_FFT * conj(SSS_FFT)
- term2 formula remains: mU[j+CP_LEN] * conj(goldU[j+CP_LEN])
- intCFO mapping remains: peakIndexMeyr - 255

Next recommended step:
- If real ROM implemented: Step 34 — connect real term2 ROM mode into estimator top and run real-ROM estimator tests.
- If real ROM pending: obtain/dump mU/goldU arrays, or proceed with FFT/frontend structural integration while clearly marking synthetic-reference limitation.
