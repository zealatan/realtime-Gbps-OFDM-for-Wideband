# Claude Code Prompt — P3-25A Real FFT/Meyr Production Restore + Verification Closure

Working Directory:
~/RTL_SYNC_PHASE3

CRITICAL

Do NOT ask YES/NO questions.

Do NOT ask for confirmation.

Do NOT stop after code changes.

Do NOT stop after compile.

Do NOT stop after hierarchy restoration.

Continue automatically through:

1. Audit
2. RTL update
3. Compile
4. Regression
5. Documentation
6. Gate evaluation

The task is NOT complete until PASS / FAIL can be determined.

------------------------------------------------------------
FROZEN ARCHITECTURE (MUST NOT CHANGE)
------------------------------------------------------------

phase3_sync_axis_dma_wrapper
│
├─ phase3_axi_lite_regs
│
├─ phase3_sync_top
│   │
│   ├─ frac_cfo_frame_corrector_top
│   │   │
│   │   ├─ iq_frame_buffer
│   │   │
│   │   ├─ frame_detector
│   │   │   ├─ sample_power_sq
│   │   │   ├─ sliding_window_sum
│   │   │   └─ frame_detect_fsm
│   │   │
│   │   ├─ frame_frac_cfo_top
│   │   │   ├─ timing_sync_top
│   │   │   │   ├─ streaming_cp_autocorr
│   │   │   │   └─ peak_detector
│   │   │   └─ frac_cfo_estimator
│   │   │
│   │   └─ frac_cfo_corrector_top
│   │       ├─ nco_phase_gen
│   │       └─ complex_rotator
│   │
│   ├─ slot_start_controller
│   │
│   ├─ pss_sss_symbol_extractor
│   │
│   └─ meyr_integer_cfo_fft_frontend_top
│       ├─ fft256_dual_symbol_frontend
│       │   └─ fft256_xilinx_wrapper
│       │       └─ Xilinx FFT IP
│       │
│       └─ meyr_integer_cfo_freq_estimator_top
│           ├─ meyr_pss_sss_product_gen
│           └─ meyr_integer_cfo_core
│               └─ peak_detector
│
├─ iq_replay_buffer_576
│
├─ nco_phase_gen
│
└─ complex_rotator

Do NOT remove hierarchy.

Do NOT rename hierarchy.

Do NOT bypass hierarchy.

------------------------------------------------------------
PROBLEM
------------------------------------------------------------

Current production DUT still contains bypass placeholders.

Verified by grep:

fft256_dual_symbol_frontend.v
→ bypass/stub

meyr_integer_cfo_fft_frontend_top.v
→ placeholder compute stage

This is not acceptable for final P3 closure.

------------------------------------------------------------
IMPORTANT REFERENCE IMPLEMENTATION
------------------------------------------------------------

A verified implementation has been supplied:

meyr_fft256_actual_integration_top

This implementation contains:

- real fft256_xilinx_wrapper integration
- PSS buffering
- SSS buffering
- FFT output capture
- FFT event handling
- watchdog handling
- estimator replay path
- FLUSH_COUNT support

Use this implementation as the REFERENCE DESIGN.

HOWEVER:

DO NOT instantiate
meyr_fft256_actual_integration_top
directly if that breaks frozen hierarchy.

Instead:

Port/adapt its INTERNAL implementation into

rtl/DUT/meyr_integer_cfo_fft_frontend_top.v

while preserving:

- module name
- hierarchy
- external interface

The frozen hierarchy must remain visible in Vivado.

------------------------------------------------------------
MANDATORY ARCHIVAL RULE
------------------------------------------------------------

Save this prompt first:

md_files/p3_25a_real_fft_meyr_restore_prompt.md

------------------------------------------------------------
ALLOWED FILES
------------------------------------------------------------

rtl/DUT/fft256_dual_symbol_frontend.v

rtl/DUT/meyr_integer_cfo_fft_frontend_top.v

rtl/DUT/meyr_integer_cfo_freq_estimator_top.v

rtl/DUT/meyr_integer_cfo_core.v

rtl/DUT/fft256_xilinx_wrapper.v
(if required)

scripts/phase3_dut_filelist.f

tb/p3_25a_real_fft_meyr_restore_tb.sv

scripts/run_p3_25a_real_fft_meyr_restore.sh

docs/p3_25a_real_fft_meyr_restore.md

------------------------------------------------------------
DO NOT MODIFY
------------------------------------------------------------

phase3_sync_axis_dma_wrapper.v

phase3_sync_top.v

frac_cfo_frame_corrector_top.v

frame_frac_cfo_top.v

timing_sync_top.v

streaming_cp_autocorr.v

frame_detector.v

iq_replay_buffer_576.v

phase3_axi_lite_regs.v

nco_phase_gen.v

complex_rotator.v

------------------------------------------------------------
TASK 1
AUDIT EXISTING REAL FFT ASSETS
------------------------------------------------------------

Search entire repository.

Locate:

- Session B
- Session P3-13B
- Session P3-13C

Find:

- verified FFT path
- verified Meyr path
- OFFICIAL_GATE PASS evidence

Document:

which files were reused.

Do NOT invent new FFT logic.

------------------------------------------------------------
TASK 2
RESTORE REAL FFT FRONTEND
------------------------------------------------------------

Current:

fft256_dual_symbol_frontend
is bypass/stub.

Restore real FFT path.

Production default:

USE_BEHAVIORAL_STUB = 0

must execute:

fft256_xilinx_wrapper

Hierarchy must become:

meyr_integer_cfo_fft_frontend_top
└─ fft256_dual_symbol_frontend
   └─ fft256_xilinx_wrapper

------------------------------------------------------------
TASK 3
RESTORE REAL MEYR ESTIMATOR
------------------------------------------------------------

Current production estimator must not be stub.

Restore:

meyr_integer_cfo_freq_estimator_top
├─ meyr_pss_sss_product_gen
└─ meyr_integer_cfo_core
   └─ peak_detector

Expected behavior:

peak_index = 255 + k_int

int_cfo = peak_index - 255

------------------------------------------------------------
TASK 4
KEEP STUB AS OPTIONAL ONLY
------------------------------------------------------------

Behavioral modes may remain.

But:

parameter USE_BEHAVIORAL_STUB = 0

must be production default.

No silent bypass in production hierarchy.

------------------------------------------------------------
TASK 5
HIERARCHY VERIFICATION
------------------------------------------------------------

Verify active hierarchy contains:

phase3_sync_axis_dma_wrapper
└─ phase3_sync_top
   └─ meyr_integer_cfo_fft_frontend_top
      ├─ fft256_dual_symbol_frontend
      │   └─ fft256_xilinx_wrapper
      └─ meyr_integer_cfo_freq_estimator_top
          ├─ meyr_pss_sss_product_gen
          └─ meyr_integer_cfo_core
              └─ peak_detector

Fail if hierarchy is missing.

------------------------------------------------------------
TASK 6
VERIFICATION
------------------------------------------------------------

Run automatically.

No user interaction.

V1.
Compile.

V2.
Hierarchy audit.

V3.
Integer CFO sweep:

k_int:

0
+1
-1
+2
-2
+4
-4
+8
-8

Expected:

peak_index = 255 + k_int

int_cfo = k_int

V4.
Replay validation.

Expected:

output_count = 576

TLAST = 575

INT_CFO_APPLIED = 1

V5.
End-to-end validation.

Reuse Session E.

Expected:

8/8 PASS

V6.
Equivalence validation.

Reuse Session D.

Expected:

EQUIV_GATE PASS

V7.
Channel robustness sanity.

Reuse Session K.

Expected:

11/11 PASS

------------------------------------------------------------
TASK 7
DOCUMENTATION
------------------------------------------------------------

Create:

docs/p3_25a_real_fft_meyr_restore.md

Include:

- reused assets
- files changed
- before hierarchy
- after hierarchy
- FFT binding status
- Meyr status
- regression results
- remaining risks

------------------------------------------------------------
FINAL GATE
------------------------------------------------------------

REAL_FFT_MEYR_RESTORE_GATE: PASS

ONLY IF:

- hierarchy restored
- FFT active
- Meyr active
- CFO sweep passes
- replay validation passes
- Session E passes
- Session D passes
- Session K passes

Otherwise:

REAL_FFT_MEYR_RESTORE_GATE: FAIL

------------------------------------------------------------
FINAL RESPONSE FORMAT
------------------------------------------------------------

P3-25A Final Status

1. Files Changed

2. Reused FFT/Meyr Assets

3. Before Hierarchy

4. After Hierarchy

5. CFO Sweep Results

6. Replay Validation Results

7. Session E Result

8. Session D Result

9. Session K Result

10. Gate Result

11. Remaining Risks

12. Recommended Next Step
