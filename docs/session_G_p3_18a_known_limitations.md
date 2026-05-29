# Phase 3 Known Limitations

**Document:** Session G / P3-18A  
**Date:** 2026-05-28

---

## L-01 — FFT Bypass Stub in `phase3_sync_top`

**Severity:** High (functional correctness)  
**Scope:** `phase3_sync_top` pipeline; Sessions A, C, D all run through this path.

`rtl/fft256_dual_symbol_frontend.v` is a behavioral bypass stub: the `S_COMPUTE` state
copies time-domain samples directly to the "FFT output" buffers without performing any
frequency-domain transform. Consequence: the `meyr_integer_cfo_fft_frontend_top` inside
`phase3_sync_top` always receives un-FFT'd data, which means peak_index = 255 and
`int_cfo_word = 0` for all integer CFO values.

**Impact:**
- Session A (P3-12C): Checks C1–C10 validate pipeline structure only, not CFO accuracy. C10
  confirms Meyr completes; the zero word is expected and noted.
- Session D (P3-15A): `int_cfo_est_bins = 1` (not 0) in the wrapper is a wrapper-probe
  artifact, not an accuracy failure (see L-04).
- Integer CFO accuracy across the full `phase3_sync_axis_dma_wrapper` pipeline is unvalidated
  with real FFT.

**Workaround for Session B:** Session B used a separate harness
(`meyr_fft256_actual_integration_top` with `USE_BEHAVIORAL_STUB=0`) to validate the real
Xilinx xfft_v9_1_9 IP independently of `phase3_sync_top`.

**Resolution path:**
1. Create adapter `meyr_fft256_harness_adapter.v` (P3-11 plan).
2. Instantiate `fft256_xilinx_wrapper` instead of `fft256_dual_symbol_frontend` in a new top
   module or via parameter override.
3. Re-generate ROMs from DFT of ZC PSS + Gold-code SSS reference sequences
   (`scripts/gen_meyr_fft_reference_roms.py` already exists).
4. Requires Vivado on build host or XCI pre-compiled VHDL simulation wrapper.

---

## L-02 — xsim Availability

**Severity:** Medium (gate authority)  
**Scope:** All xsim-dependent gates.

Vivado xsim is not installed on the WSL2 Linux build host. It is available via
Windows Vivado 2023.1 at `C:\Xilinx\Vivado\2023.1` and invoked from WSL2 using
`/mnt/c/Windows/System32/cmd.exe /c "..."` interop. All iverilog gates are marked
`SANITY_GATE` only; xsim is required for `CI_GATE` or `OFFICIAL_GATE` authority.

**Impact:** Sessions A, C, and D produced only iverilog SANITY gates. The CI policy
documented in `docs/p3_09x_verification_flow_status.md` requires xsim for authoritative
sign-off on any module other than the Meyr estimator unit harness (Session B).

**Resolution path:** Run `--sim xsim` variants of each session runner from a host with
Vivado installed, or install Vivado on the Linux build host.

---

## L-03 — Single Test Stimulus

**Severity:** Medium (coverage)  
**Scope:** Sessions A, C, D; all golden comparison flows.

All end-to-end simulations use one deterministic stimulus:
- 704 samples, NSC=256, CP_LEN=32, k_int=0, eps_frac=+0.05, QPSK IFFT seed=0xC0FFEE.

No multi-frame, multi-CFO, or variable-SNR testing has been run through the full wrapper.
The integer CFO sweep (Session B) covers 9 k_int values but only for the Meyr estimator
harness, not the complete wrapper pipeline.

**Resolution path:** Extend `scripts/gen_phase3_iq_stimulus.py` to accept k_int and
eps_frac as arguments; run Session C and D comparison flows for at least k_int ∈ {−4, +4}.

---

## L-04 — Meyr Peak Index Off-by-One in Wrapper Probe

**Severity:** Low (within tolerance)  
**Scope:** Session D Stage 3; any probe of `dut_meyr_peak_index` through the wrapper.

When `meyr_peak_index` is read from the AXI-Lite snapshot register
(`ADDR_INT_CFO_I`, `INT_CFO_INDEX_AXI`) or the hierarchical probe
`u_dut.dut_meyr_peak_index`, the value is consistently 256 (not 255) for zero-CFO
stimulus. Session A, which probes `phase3_sync_top` directly, correctly reports 255.

**Root cause candidates:**
1. Pipeline register delay in the wrapper's debug path — the hierarchical probe reads
   `dut_meyr_peak_index` one cycle after `dut_int_cfo_valid` fires, and the peak_index
   register may have already advanced.
2. AXI-Lite snapshot convention — the register latches on the int_cfo_valid rising edge,
   which may coincide with an index already incremented by the output pipeline.
3. The issue is also observed in Session C (`INT_CFO_STEP_WORD = 0xFF000000` implies
   `k_int = +1` through the full wrapper despite a zero-CFO stimulus).

**Impact:** Session D Stage 3 applies ±1 tolerance to `int_cfo_index` and
`int_cfo_est_bins`. The actual correction applied is k_int=+1 (confirmed:
`INT_CFO_APPLIED=1`, `step_word=0xFF000000`), which the Session C sample-by-sample golden
compare verified produces numerically correct output — so the error is in the reported
estimate, not the correction applied.

**Resolution path:** Session B confirmed that the real Meyr estimator produces peak=255
for k_int=0 stimulus. A full xsim run of `phase3_sync_axis_dma_wrapper` with real FFT
would clarify the wrapper's snapshot timing.

---

## L-05 — M_AXIS IQ Golden Unavailable (Stages 4–5 Blocked)

**Severity:** Low (partial coverage)  
**Scope:** Session D Stages 4 and 5.

`scripts/golden_dump.c` implements Steps 1–3 of the C reference algorithm (frame
detection, fractional CFO estimation, slot start) but does not implement the NCO-based
integer CFO correction or produce M_AXIS output IQ. As a result, there is no C reference
golden for the 576-sample output of `phase3_sync_axis_dma_wrapper`.

**Impact:** Session D Stages 4 (M_AXIS metadata) and 5 (sample-by-sample IQ comparison)
are permanently BLOCKED until a C software model is provided.

**Resolution path:** Extend `scripts/golden_dump.c` (or write a separate Python script)
to apply the NCO rotation: `phase = n * step_word` (32-bit wrap), `idx = phase >> 24`,
look up cosine/sine from the same Q1.15 ROM used by the RTL, apply the rotator formula.
Write output to `golden/session_D_p3_15a/c_m_axis_iq_golden.txt` (one `I Q` per line).
The Session D comparison framework is already wired to read this file once present.

---

## L-06 — Integer CFO Range Not Fully Validated

**Severity:** Low (coverage)  
**Scope:** Session B integer CFO sweep.

The Session B sweep covers k_int ∈ {−8, −4, −2, −1, 0, +1, +2, +4, +8}. The estimator
theoretically supports |k_int| ≤ 127 (±127 bins in a 256-pt FFT), but values outside
±8 have not been tested. Very large CFO values could introduce fixed-point saturation
in the 16-bit correlation accumulator.

**Resolution path:** Extend `golden/p3_09_sweep` to add cases at k_int ∈ {±16, ±32, ±64}
and re-run `scripts/run_session_B_p3_13c_real_fft_ip_xsim.sh`.

---

## L-07 — No Multipath or Noise Testing

**Severity:** Informational  
**Scope:** All sessions.

All testing uses a clean AWGN-free, single-path, deterministic stimulus. No
multi-path channel, frequency-selective fading, or additive noise model has been applied.
Robustness under realistic channel conditions is untested.

---

## L-08 — km8 and kp8 Produce Identical Correlation Scores

**Severity:** Informational  
**Scope:** Session B (k_int = ±8).

Both k_int=+8 and k_int=−8 produce a correlation score of 509,590,562. This is
numerically coincidental (peak locations are 263 and 247 respectively — correctly
distinct). No functional impact.

---

## L-09 — THRESHOLD_VAL=40000 Only Valid for Amplitude-3000 Stimulus

**Severity:** Medium (configuration hazard)

The frame detector threshold in simulation testbenches is set to `THRESHOLD_VAL=40000`
to match the peak amplitude of approximately 3000 per IQ component in the test stimulus.
Real signals with full-scale amplitude (~32767 per component) require
`THRESHOLD_VAL ≈ 10,240,000` (256× higher). This parameter is a TB override and does
not affect the synthesized RTL default, but any simulation of a production-scale signal
with the current TB would fail to detect frames.

---

## L-10 — WSL2 Path Dependency for xsim Runner

**Severity:** Informational  
**Scope:** Session B runner, all `--sim xsim` paths.

`scripts/run_session_B_p3_13c_real_fft_ip_xsim.sh` hard-codes the Vivado path to
`C:\Xilinx\Vivado\2023.1`. A different Vivado installation path or version requires the
`--vivado-ver` argument or manual path editing. The runner auto-detects xsim absence and
exits `BLOCKED_XSIM_UNAVAILABLE` cleanly.
