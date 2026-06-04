# Session D / P3-24C — CP Autocorr Revalidation Impact Matrix

**Date:** 2026-05-31  
**Trigger:** Switch production timing path from `rtl/unit_test/cp_autocorr_core.v` +
`rtl/unit_test/timing_metric_core.v` to `rtl/DUT/streaming_cp_autocorr.v` +
`rtl/DUT/timing_metric_core.v` (and full DUT tree reorganisation).

---

## 1. Architectural Change Description

### 1.1 What Changed

The production RTL tree has been reorganised. The old multi-directory layout
(`rtl/unit_test/`, `rtl/phase2_legacy/`, scattered `rtl/*.v`) has been collapsed
into a single canonical directory: `rtl/DUT/`.

Two algorithmic files are changing:

| Old path | New path | Module name |
|----------|----------|-------------|
| `rtl/unit_test/cp_autocorr_core.v` | `rtl/DUT/streaming_cp_autocorr.v` | `streaming_cp_autocorr` |
| `rtl/unit_test/timing_metric_core.v` | `rtl/DUT/timing_metric_core.v` | `timing_metric_core` |

All legacy primitives (`complex_mult`, `delay_sample`, `moving_avg_optimized`,
`ram_2port`, `delayT`) have moved from `rtl/phase2_legacy/` to `rtl/DUT/`.
The module names and interfaces are preserved.

### 1.2 Metric Formula Change (Critical)

The `timing_metric_core.v` in `rtl/DUT/` uses a different peak-selection formula:

| Version | Formula | Property |
|---------|---------|----------|
| OLD (`unit_test`) | `M[m] = 2×alpha_max_beta_min(|P_I|,|P_Q|) − E[m]` | ≤3.5% magnitude underestimate |
| NEW (`DUT`) | `metric_out = ~(sq_neg >> 27)`, `sq_neg = E² − 4×|P|²` | Exact Cauchy-Schwarz; no bias |

For **clean signals** (high SNR, no multipath): both formulas identify the same peak
lag — the systematic magnitude underestimate is equal across all lags, so relative
ordering is preserved.

For **noisy or multipath signals**: the 3.5% bias can flip the ordering of adjacent
lags. The new exact formula is strictly more robust.

### 1.3 `streaming_cp_autocorr` vs `cp_autocorr_core` Implementation

Both files define module `streaming_cp_autocorr`. The module interface (ports,
parameters, IQ convention, pipeline depth) is identical. The internal implementation
uses the same phase2 legacy primitives in the same topology:

```
s_valid → delay_sample(256) → complex_mult(3cy) → moving_avg_optimized(4cy) → p_i/p_q
s_valid → sample_power_sq(2cy) + 2cy align → moving_avg_optimized(4cy) → energy
```

Numerically, the autocorrelation outputs (`p_i`, `p_q`, `energy`, `sample_index`)
are **bit-identical** between the two source files. The peak lag and frac CFO can
only differ if the metric formula selects a different lag (see §1.2).

### 1.4 Missing Module — Blocking Gap

`rtl/DUT/` does **not** contain `timing_sync_top.v`.
`rtl/DUT/timing_frac_cfo_top.v` instantiates `timing_sync_top`, so all full-chain
compilations will fail with a module-not-found error until `timing_sync_top.v` is
provided (either created or copied into `rtl/DUT/`).

**This gap must be resolved before any rerun can produce valid results.**

### 1.5 Source List Impact (Universal)

Every test script currently has `rtl/unit_test/cp_autocorr_core.v` in its compile
list. That path no longer exists (`rtl/unit_test/` is absent from the filesystem).
All runners require source list surgery before they can compile.

Affected runners (exhaustive):

```
run_phase3_sync_sim.sh
run_phase3_sync_xsim.sh
run_p3_04_phase3_sync_top_compile.sh
run_p3_09_integer_cfo_sweep.sh
run_p3_12b_frame_detector_golden_regression.sh
run_p3_14a_axi_dma_wrapper_smoke.sh
run_p3_14b_dma_replay.sh
run_session_A_p3_12c_full_phase3_regression.sh
run_session_C_p3_14c_dma_replay_golden_compare.sh
run_session_C2_p3_14d_replay_hardening.sh
run_session_C3_p3_20a_axi_stress.sh
run_session_C4_p3_20b_axi_soak.sh
run_session_D_p3_15a_full_c_golden_equivalence.sh
run_session_D3_p3_15c_equiv_robustness.sh
run_session_D4_p3_15d_regression.sh
run_session_E_p3_16a_full_end_to_end_phase3.sh
run_session_I_p3_20a_axi_backpressure_stress.sh
run_session_J_p3_21a_cfo_coverage.sh  (J2/J3 path only)
run_session_K_p3_22a_channel_robustness.sh
run_session_L_p3_23a_stress.sh
```

---

## 2. Affected Signal Paths

### 2.1 Changed path

```
S_TIMING_CFO (frac_cfo_frame_corrector_top)
  → timing_frac_cfo_top.u_tst  (timing_sync_top)
      → streaming_cp_autocorr   ← MODULE SWITCH (file path change)
      → timing_metric_core      ← METRIC FORMULA CHANGE
      → peak_lag, peak_corr_i/q
  → timing_frac_cfo_top.u_fce  (frac_cfo_estimator)
      → frac_phase              ← depends on peak_corr_i/q
```

All outputs that flow from `peak_lag` or `frac_phase` can differ from prior runs:

| Derived output | Dependency on autocorr path |
|----------------|----------------------------|
| `peak_lag` | Direct — timing_metric_core selects it |
| `frac_phase` | Direct — CORDIC of P_I/P_Q at peak_lag |
| `slot_start` | `frame_index + peak_lag` |
| `frac_cfo_word` | Same as frac_phase (Q1.15 encoding) |
| M_AXIS IQ | Via NCO step = frac_phase × 2⁸ → rotator output |
| `int_cfo_word` | PSS/SSS windows = f(slot_start) → Meyr FFT |

### 2.2 Unaffected paths

| Path | Why unaffected |
|------|----------------|
| Frame energy detection | `frame_detect_fsm` uses `sliding_window_sum` of sample energy, does **not** use `timing_metric_core` |
| PSS/SSS extraction | Downstream of slot_start; values correct once slot_start is correct |
| Meyr FFT path (Session B) | Standalone DUT `meyr_fft256_actual_integration_top`; no cp_autocorr dependency |
| NCO / complex_rotator | Downstream of int_cfo_word; logic is invariant to the path that produces it |
| AXI-Lite register map | No algorithmic content; layout unchanged |
| J1 integer CFO sweep | Uses standalone Meyr DUT; no cp_autocorr in compile list |

---

## 3. Impact Matrix

| Test | Gate | DUT | Autocorr-dependent | Classification | Reasoning |
|------|------|-----|-------------------|----------------|-----------|
| **A** frame detector regression | SANITY_GATE | `phase3_sync_top` | Yes — peak_lag, frame_index, slot_start are primary outputs | **Must rerun** | Directly measures the changed signal path; new metric can shift peak_lag |
| **D2** RTL vs C IQ equivalence | SANITY_EQUIV_GATE | `phase3_sync_axis_dma_wrapper` | Yes — all 6 checked fields (frame_index, peak_lag, slot_start, frac_cfo, int_cfo_index, M_AXIS IQ) | **Must rerun** | Highest-fidelity numerical comparison; M_AXIS IQ tolerance ±1 LSB will fail on any peak_lag shift |
| **D4** 100-case randomized equivalence | RANDOM_EQUIV_GATE | `phase3_sync_axis_dma_wrapper` | Yes — slot_start(±2), frac_cfo(≤2%), M_AXIS IQ(±1 LSB) are gate-controlling | **Must rerun** | Broadest parametric coverage of the changed path; essential for statistical confidence in new metric |
| **E** end-to-end integration | INTEGRATION_GATE | `phase3_sync_axis_dma_wrapper` | Yes — frame_found, frame_index(±1), int_cfo_applied, output_count, TLAST | **Must rerun** | Full pipeline smoke; any peak_lag regression cascades to int_cfo_applied and output_count |
| **K** channel robustness | CHANNEL_GATE | `phase3_sync_axis_dma_wrapper` | Yes — frame detection under AWGN + multipath | **Must rerun** | The metric formula change (exact vs ≤3.5% approximate) has the largest impact under degraded channel; critical for characterising robustness of new metric |
| **I** AXI backpressure | SANITY_AXI_GATE | `phase3_sync_axis_dma_wrapper` | Indirect — output_count=576 requires detection to work; AXI protocol compliance is invariant | **Recommended** | Cycle budget shifts (streaming path is one-pass vs two-pass); deterministic stall periods interact with new per-frame latency |
| **J** CFO sweep — J1 only | J1_GATE | `meyr_fft256_actual_integration_top` | **No** — standalone Meyr DUT, no cp_autocorr in compile | **No rerun needed** | Completely separate RTL path; no source file overlap with changed modules |
| **J** CFO sweep — J2/J3 | J2_GATE, J3_GATE | `phase3_sync_axis_dma_wrapper` | Yes — frac_cfo_valid(1), output_count(576) depend on autocorr path | **Recommended** | frac_cfo derived from new metric path; mathematical CFO invariance holds but new metric may shift peak by ±1 lag under large CFO |
| **L** reset / multiframe | SANITY_STRESS_GATE | `phase3_sync_axis_dma_wrapper` | Yes — each of 10 consecutive frames must detect correctly; enable-toggle test (L4) exercises s_valid gating through the streaming pipeline | **Recommended** | Streaming pipeline has different reset-to-first-valid latency; multi-frame auto-rearm cycle count changes |
| **C2** replay hardening | REPLAY_HARDENING_GATE | `phase3_sync_axis_dma_wrapper` | Mixed — C2-1/C2-3 require detection; C2-2 forces `dut_int_cfo_word` (bypass); C2-4 tests rotator phase (invariant) | **Recommended** | C2-2 and C2-4 are detection-independent but C2-1 (backpressure) and C2-3 (restart) require correct frame timing |
| **C3** AXI random backpressure | AXI_STRESS_GATE | `phase3_sync_axis_dma_wrapper` | Indirect — output_count=576 depends on detection; LFSR stalls interact with new latency profile | **Recommended** | Functional gate (output_count) depends on detection; random stall patterns stress new timing differently |
| **C4** AXI soak (1400 frames) | AXI_SOAK_GATE | `phase3_sync_axis_dma_wrapper` | Indirect — B4 (replay_done_cnt=1400) and B5 (counter monotonicity) require detection across all frames | **Recommended** | Provides the highest long-run confidence but is the most expensive to run (~103M cycles for B2 alone); defer until E+K+L+C2+C3 pass |

---

## 4. Required Reruns (Must Rerun)

Five tests must be rerun before P3-24C can be declared closed:

| Priority | Test | Gate | Primary driver |
|----------|------|------|---------------|
| 1 | **A** frame detector regression | SANITY_GATE | Direct measurement of peak_lag and slot_start — baseline for all other tests |
| 2 | **D2** RTL vs C IQ equivalence | SANITY_EQUIV_GATE | Numerical golden compare; closes the algorithmic correctness loop against C reference |
| 3 | **E** end-to-end integration | INTEGRATION_GATE | Full pipeline smoke with output_count and TLAST; confirms no cascading regression |
| 4 | **K** channel robustness | CHANNEL_GATE | Validates new Cauchy-Schwarz metric under AWGN + multipath — most sensitive to formula change |
| 5 | **D4** 100-case randomized equivalence | RANDOM_EQUIV_GATE | Statistical coverage across 100 stimuli; builds confidence that peak_lag is correct across parameter space |

**Run order:** A → D2 → E → K → D4  
Rationale: A is the fastest (phase3_sync_top only, ~40K cycles). A PASS unlocks confidence
for D2 and E. K validates the regime where the old and new metrics can diverge. D4 is the
broadest statistical sweep and takes longest (100 × 103K cycles).

---

## 5. Optional Reruns (Recommended)

Six additional tests add depth without being blocking for closure:

| Test | Gate | When to run |
|------|------|-------------|
| **I** AXI backpressure | SANITY_AXI_GATE | After E passes — validates AXI protocol compliance under new timing profile |
| **J** J2/J3 wrapper CFO sweep | J2_GATE, J3_GATE | After D2 passes — validates frac_cfo_valid under fractional + combined CFO |
| **L** reset / multiframe | SANITY_STRESS_GATE | After E passes — validates multi-frame auto-rearm and reset sequencing with new pipeline |
| **C2** replay hardening | REPLAY_HARDENING_GATE | After E passes — C2-1/C2-3 need detection; C2-2/C2-4 are independent |
| **C3** AXI random backpressure | AXI_STRESS_GATE | After I passes — LFSR stress with new timing |
| **C4** AXI soak (1400 frames) | AXI_SOAK_GATE | Last; only run if time permits; requires ~103M cycles for full soak |

J1 sub-test of Session J requires **no rerun** (see §6 below).

---

## 6. Safe-to-Skip Tests

| Test | Gate | Reason safe to skip |
|------|------|----------------------|
| **J1** integer CFO sweep (standalone Meyr) | J1_GATE | Standalone DUT `meyr_fft256_actual_integration_top`; source list has no overlap with changed RTL files; prior OFFICIAL_GATE: PASS (xsim, P3-13B/C) remains valid |

No other test in the matrix is fully independent of the changed modules.

---

## 7. Minimal Closure Plan

### Pre-condition: Resolve Blocking Gap

Before any rerun can compile:

1. **Create `rtl/DUT/timing_sync_top.v`**  
   Must instantiate `streaming_cp_autocorr` (not `cp_autocorr_core`) and wire the
   streaming `p_i`/`p_q`/`energy`/`out_valid` outputs to a result store so that
   `timing_metric_core`'s combinatorial read port (`result_rd_addr → result_autocorr_I/Q/E`)
   can read them. This is the only new RTL needed.

2. **Update all runner source lists**  
   Replace every occurrence of:
   - `rtl/unit_test/cp_autocorr_core.v` → `rtl/DUT/streaming_cp_autocorr.v`
   - `rtl/unit_test/timing_metric_core.v` → `rtl/DUT/timing_metric_core.v`
   - `rtl/phase2_legacy/complex_mult.v` → `rtl/DUT/complex_mult.v`
   - `rtl/phase2_legacy/delay_sample.v` → `rtl/DUT/delay_sample.v`
   - `rtl/phase2_legacy/moving_avg_optimized.v` → `rtl/DUT/moving_avg_optimized.v`
   - `rtl/phase2_legacy/ram_2port.v` → `rtl/DUT/ram_2port.v`
   - `rtl/phase2_legacy/delayT.v` → `rtl/DUT/delayT.v`
   - `rtl/phase2_legacy/complex_to_mag.v` → `rtl/DUT/complex_to_mag.v`
   - All other `rtl/` top-level modules → `rtl/DUT/` equivalents  
   For J2/J3, `rtl/unit_test/and2.v` should be dropped (not needed by DUT path).

### Closure Steps

| Step | Action | Gate | Unblocks |
|------|--------|------|---------|
| P | Create `rtl/DUT/timing_sync_top.v` + update all source lists | compile (iverilog exits 0) | Everything below |
| 1 | Rerun test A (`run_p3_12b_frame_detector_golden_regression.sh`) | SANITY_GATE: PASS | D2, E, K |
| 2 | Rerun test D2 (`run_session_D_p3_15a_full_c_golden_equivalence.sh`) | SANITY_EQUIV_GATE | D4 |
| 3 | Rerun test E (`run_session_E_p3_16a_full_end_to_end_phase3.sh`) | INTEGRATION_GATE | I, L, C2, C3 |
| 4 | Rerun test K (`run_session_K_p3_22a_channel_robustness.sh`) | CHANNEL_GATE | (confidence) |
| 5 | Rerun test D4 (`run_session_D4_p3_15d_regression.sh`) | RANDOM_EQUIV_GATE | closure |
| 6 (opt) | Rerun I, J2/J3, L, C2, C3 | sub-gates | C4 |
| 7 (opt) | Rerun C4 (`run_session_C4_p3_20b_axi_soak.sh`) | AXI_SOAK_GATE | (depth) |

**Minimum gate set for P3-24C closure declaration:**
```
SANITY_GATE: PASS          (test A)
SANITY_EQUIV_GATE: PASS    (test D2)
INTEGRATION_GATE: PASS     (test E)
CHANNEL_GATE: PASS         (test K)
RANDOM_EQUIV_GATE: PASS    (test D4)
```

---

## 8. Reference

| Session | Test letter | Gate emitted |
|---------|-------------|-------------|
| P3-12B | A | SANITY_GATE |
| P3-15A (Session D) | D2 | SANITY_EQUIV_GATE |
| P3-15D (Session D4) | D4 | RANDOM_EQUIV_GATE |
| P3-16A (Session E) | E | INTEGRATION_GATE |
| P3-20A (Session I) | I | SANITY_AXI_GATE |
| P3-21A (Session J) | J1 / J2 / J3 | J1_GATE / J2_GATE / J3_GATE |
| P3-22A (Session K) | K | CHANNEL_GATE |
| P3-23A (Session L) | L | SANITY_STRESS_GATE |
| P3-14D (Session C2) | C2 | REPLAY_HARDENING_GATE |
| P3-20A (Session C3) | C3 | AXI_STRESS_GATE |
| P3-20B (Session C4) | C4 | AXI_SOAK_GATE |
