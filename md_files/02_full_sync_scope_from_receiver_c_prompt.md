# Step 2 — Full C Synchronizer Scope Extraction and RTL Architecture Mapping

Workspace:

`/home/zealatan/RTL_SYNC`

## Goal

The final project goal is **full RTL replacement** of the C `synchronization()` function used in the OFDM receiver.

Do **not** reduce the target to timing-only synchronization.

The full C synchronization path includes:

```text
frame detection
+ CP auto-correlation timing
+ fractional CFO estimation
+ fractional CFO correction
+ PSS/SSS FFT
+ integer CFO estimation
+ integer CFO correction
```

This step is **analysis-only**.

Do not implement RTL yet.  
Do not create Verilog/SystemVerilog files.  
Do not modify existing RTL, testbenches, or simulation scripts.

---

## Reference C file

Use:

- `ref/receiver.c`

If this file does not exist, stop and report that `ref/receiver.c` is missing.

---

## Tasks

### 1. Locate the full synchronization path

Inspect `ref/receiver.c` and identify all C functions involved in synchronization.

At minimum, look for:

- `synchronization()`
- `frame_detector()`
- `VanDeBeekAutoCorrelation()`
- `auto_corr()`
- `auto_corr_norm()`
- `find_max_index()`
- `apply_carrier_freq_offset()`
- `carrierFreqOffsetEstMeyr()`
- `fft_correlation_Meyr()`
- `generate_complex_symbol()`
- `fft_without_rearrange()`

Also identify helper functions, constants, macros, and global variables used by this path.

---

### 2. Build the C call graph

Create a call graph starting from:

```c
synchronization(...)
```

The graph should show the actual function calls used by the C code.

Expected high-level structure:

```text
synchronization()
├── frame_detector()
├── VanDeBeekAutoCorrelation()
│   ├── auto_corr()
│   ├── auto_corr_norm()
│   └── find_max_index()
├── apply_carrier_freq_offset()
├── carrierFreqOffsetEstMeyr()
│   ├── generate_complex_symbol()
│   ├── fft_without_rearrange()
│   ├── fft_correlation_Meyr()
│   └── find_max_index()
└── apply_carrier_freq_offset()
```

Adjust this based on the actual C implementation.

---

### 3. Summarize each synchronizer stage

For each stage, summarize:

- C function name
- purpose
- inputs
- outputs
- main computation
- important constants
- RTL difficulty
- verification risk

Cover all of these stages:

1. Frame detection
2. CP auto-correlation timing
3. Timing metric generation
4. Peak detection
5. Fractional CFO estimation
6. Fractional CFO correction
7. PSS/SSS symbol extraction
8. FFT
9. Integer CFO estimation using Meyr method
10. Integer CFO correction

---

### 4. Create C-to-RTL block mapping

Create a table mapping C code to proposed RTL blocks.

Use this style:

| C function / operation | Proposed RTL block | Notes |
|---|---|---|
| `frame_detector()` | `frame_detector.v` | energy-based coarse detection |
| `auto_corr()` | `cp_autocorr_core.v` | complex conjugate multiply and accumulation |
| `auto_corr_norm()` | `timing_metric_core.v` | timing metric generation |
| `find_max_index()` | `peak_detector.v` | reusable peak finder |
| `atan2()` | `cordic_atan2.v` or Xilinx CORDIC wrapper | phase estimation |
| `apply_carrier_freq_offset()` | `nco_phase_gen.v` + `complex_rotator.v` | CFO correction |
| `generate_complex_symbol()` | `symbol_extractor.v` | CP removal and symbol slicing |
| `fft_without_rearrange()` | `fft_wrapper.v` | FFT engine |
| `carrierFreqOffsetEstMeyr()` | `integer_cfo_estimator.v` | Meyr estimator top |
| `fft_correlation_Meyr()` | `meyr_corr_core.v` | correlation engine |

Adjust module names if better names are justified.

---

### 5. Propose final RTL hierarchy

Propose a full hierarchy for:

```text
ofdm_synchronizer_top.v
```

Include at least:

```text
ofdm_synchronizer_top.v
├── sync_control_fsm.v
├── frame_detector.v
├── cp_autocorr_core.v
├── timing_metric_core.v
├── peak_detector.v
├── frac_cfo_estimator.v
├── cordic_atan2.v or xilinx_cordic_wrapper.v
├── nco_phase_gen.v
├── complex_rotator.v
├── symbol_extractor.v
├── fft_wrapper.v
├── pss_sss_rom.v
├── meyr_corr_core.v
├── integer_cfo_estimator.v
├── integer_cfo_corrector.v
└── axi_lite_sync_regs.v
```

Also explain how existing repo blocks/concepts can be reused:

- `axis_complex_mult.v`
- `axi_lite_regfile.v`
- `simple_dma_add_ctrl.v`
- `axi_mem_model.sv`

---

### 6. Define implementation roadmap

Create a realistic full implementation roadmap with approximately 25 to 35 steps.

The roadmap must eventually include:

- frame detector
- CP timing
- fractional CFO estimator
- CORDIC or atan2 replacement
- NCO phase generator
- complex rotator
- fractional CFO correction
- symbol extractor
- FFT wrapper
- PSS/SSS ROM or reference sequence logic
- Meyr integer CFO estimator
- integer CFO correction
- full top integration
- AXI-Lite status/config wrapper
- Python/C golden model comparison
- randomized regression
- synthesis/resource review
- FPGA/ILA bring-up plan

---

### 7. Identify fixed-point decisions needed in Step 3

List all numeric/interface decisions needed before RTL implementation.

Include:

- input IQ width
- correlation multiplier width
- accumulator width
- timing metric width
- phase width
- CORDIC output width
- NCO phase accumulator width
- sine/cosine LUT vs CORDIC decision
- complex rotator output scaling
- FFT input/output width
- Meyr correlation accumulator width
- CFO estimate representation
- saturation vs wrap behavior
- AXI-Stream input/output format
- AXI-Lite register map requirements

---

### 8. Recommend Step 3

Recommend the exact next step:

```text
Step 3 — Fixed-Point and Interface Specification for Full OFDM Synchronizer RTL
```

Do not implement RTL in Step 3 yet.

---

## Output files

Create:

- `docs/step2_full_sync_scope_from_receiver_c.md`

Also create or update:

- `ai_context/current_status.md`

The status file should briefly record:

- Step 1 completed
- Step 2 completed
- final goal is full RTL replacement of C `synchronization()`
- next step is fixed-point/interface specification

---

## Constraints

Allowed:

- create `docs/step2_full_sync_scope_from_receiver_c.md`
- create or update `ai_context/current_status.md`

Not allowed:

- do not create Verilog files
- do not create SystemVerilog files
- do not edit existing RTL files
- do not edit existing testbench files
- do not edit existing scripts
- do not implement synchronizer logic yet
- do not reduce the project target to timing-only synchronization

---

## Report format

The markdown report must include:

1. Purpose and final goal
2. C synchronization call graph
3. Full synchronization stage breakdown
4. Function-by-function summary
5. C-to-RTL block mapping table
6. Proposed final RTL hierarchy
7. Reuse from existing repository
8. Full 25–35 step implementation roadmap
9. Fixed-point decisions required in Step 3
10. Recommended Step 3
11. Files inspected
12. Files changed

---

## Final response format

When finished, respond with:

```text
Step 2 complete.

Files changed:
- docs/step2_full_sync_scope_from_receiver_c.md
- ai_context/current_status.md

Key findings:
- ...
- ...
- ...

Recommended Step 3:
- Fixed-point and interface specification for full OFDM synchronizer RTL.
```
