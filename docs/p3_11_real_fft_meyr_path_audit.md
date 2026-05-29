# P3-11 — Real FFT / Meyr Actual Path Audit

**Version:** 1.0  
**Date:** 2026-05-28  
**Status:** INVESTIGATION COMPLETE — No RTL modified

---

## 1. Current Bypass Path

### 1.1 Data Flow Diagram

```
phase3_sync_top
  │
  ├─ u_frac_corr: frac_cfo_frame_corrector_top
  │     IQ input → frac-corrected FRAME_LEN=576 samples
  │     slotStart = 64 (= PRE_ZEROS)
  │
  ├─ u_ssc: slot_start_controller
  │     pss_fft_start = CP_LEN = 32   (offset within corrected frame)
  │     sss_fft_start = 2*CP_LEN+NSC = 320
  │
  ├─ u_extractor: pss_sss_symbol_extractor
  │     Accepts FRAME_LEN corrected samples
  │     → PSS: corrected_frame[32..287]  (m_symbol_sel=0, 256 samples)
  │     → SSS: corrected_frame[320..575] (m_symbol_sel=1, 256 samples)
  │
  └─ u_meyr_fft: meyr_integer_cfo_fft_frontend_top  ← UNIT_TEST MODULE
        │
        ├─ u_fft: fft256_dual_symbol_frontend  ← BYPASS STUB
        │     S_IDLE → S_FILL (accept 512 samples) → S_COMPUTE → S_STREAM_PSS → S_STREAM_SSS
        │     S_COMPUTE: for-loop copies {pss_buf_i[k],pss_buf_q[k]} → {fft_pss_i[k],fft_pss_q[k]}
        │                 ↑ NO COMPUTATION — time-domain samples passed as "FFT bins"
        │
        └─ u_est: meyr_integer_cfo_freq_estimator_top
              │
              ├─ u_prod_gen: meyr_pss_sss_product_gen
              │     term1[j] = PSS_td[j] × conj(SSS_td[j])   ← TIME-DOMAIN cross-product
              │
              └─ u_core: meyr_integer_cfo_core
                    ROM loaded from vectors/*.txt at elaboration
                    Current ROM: PSS_rom[j] = term1_ref[j] (time-domain cross-product, Q1.15)
                                 SSS_rom[j] = +32767 (sign=+1)
                    Correlates term1 vs term2[j] = PSS_rom[j]×sign(SSS_rom_I[j])
                    511-lag correlation → argmax → peak_index, int_cfo
                    k_int=0: peak_index=255, int_cfo=0  ✓ (P3-08 CI_GATE PASS)
                    k_int≠0: peak_index=255, int_cfo=0  ✗ (integer CFO cancels in PSS_td×conj(SSS_td))
```

### 1.2 Why k_int≠0 Fails with Bypass

With integer CFO k_int applied to the stimulus:

```
PSS_td_shifted[j] = PSS_td_ref[j] × exp(j·2π·k_int·j/NSC)
SSS_td_shifted[j] = SSS_td_ref[j] × exp(j·2π·k_int·j/NSC)

term1_shifted[j]  = PSS_td_shifted[j] × conj(SSS_td_shifted[j])
                  = PSS_td_ref[j] × exp(+j·2π·k_int·j/NSC)
                    × conj(SSS_td_ref[j]) × exp(−j·2π·k_int·j/NSC)
                  = PSS_td_ref[j] × conj(SSS_td_ref[j])   ← k_int cancels exactly
                  = term1_ref[j]
```

The correlation always peaks at lag=255 regardless of k_int. This is not a bug in the RTL — it is mathematically correct behavior for a time-domain cross-product. The Meyr estimator requires **frequency-domain** bins as input.

---

## 2. Intended Real FFT Path

### 2.1 Data Flow Diagram

```
phase3_sync_top (unchanged OR with new test harness)
  │
  ├─ u_frac_corr, u_ssc, u_extractor  (identical — no change)
  │
  └─ [replacement/harness]: meyr_fft256_actual_integration_top
        │
        │  s_axis_tdata = {Q[31:16], I[15:0]}  (packed AXI-Stream)
        │  s_axis_tvalid / s_axis_tready / s_axis_tlast
        │  s_symbol_sel (informational)
        │
        ├─ FSM: S_PSS_BUF → S_PSS_STREAM → [S_PSS_FLUSH] → S_PSS_CAP
        │       → S_SSS_BUF → S_SSS_STREAM → [S_SSS_FLUSH] → S_SSS_CAP
        │       → S_EST → S_WAIT_EST → S_DONE
        │
        ├─ u_fft: fft256_xilinx_wrapper
        │     USE_BEHAVIORAL_STUB=0: Xilinx xfft_v9_1_8 (NOT available on this host)
        │     USE_BEHAVIORAL_STUB=1: passthrough stub (compile-only, not an FFT)
        │     USE_BEHAVIORAL_STUB=2: sequential output stub (FSM hardening only)
        │
        │     FFT output: m_axis_tdata = {Im[15:0], Re[15:0]}
        │                  m_axis_tuser = xk_index[7:0]  (bin index, natural order)
        │                  m_axis_tlast = 1 at bin 255
        │
        └─ u_est: meyr_integer_cfo_freq_estimator_top
              │
              ├─ u_prod_gen: meyr_pss_sss_product_gen
              │     term1_fft[j] = FFT(PSS)[j] × conj(FFT(SSS)[j])  ← FREQUENCY-DOMAIN
              │
              └─ u_core: meyr_integer_cfo_core
                    ROM must be: PSS_rom[j] = DFT(PSS_ref)[j] × conj(DFT(SSS_ref)[j])
                                              normalized to Q1.15
                                 SSS_rom[j] = +32767 (sign=+1, same convention)
                    Correlation peak at lag = k_int:
                      peak_index = 255 + k_int
                      int_cfo    = k_int
                      integer_cfo_word = −k_int × 2^24
```

---

## 3. Module-by-Module Interface Comparison

### 3.1 Port Table

| Port | meyr_integer_cfo_fft_frontend_top | meyr_fft256_actual_integration_top | Compatible? |
|------|-----------------------------------|------------------------------------|-------------|
| `aclk` | wire | wire | YES |
| `aresetn` | wire | wire | YES |
| `start` | wire | wire | YES |
| `s_valid` / `s_axis_tvalid` | s_valid | s_axis_tvalid | YES (rename) |
| `s_ready` / `s_axis_tready` | s_ready (wire output) | s_axis_tready (wire output) | YES (rename) |
| `s_i[15:0]` + `s_q[15:0]` | separate signed[15:0] | — | **MISSING IN ACTUAL** |
| `s_axis_tdata[31:0]` | — | {Q[31:16], I[15:0]} packed | **MISSING IN FRONTEND** |
| `s_axis_tlast` | — | required; asserted at sample 255 | **MISSING IN FRONTEND** |
| `s_symbol_sel` | used for PSS/SSS routing | informational only | COMPATIBLE (semantics differ) |
| `s_index[7:0]` | used by FFT frontend FSM | — not used | **DROPPED** in actual |
| `done` | wire output | reg output | COMPATIBLE |
| `busy` | wire output | reg output | COMPATIBLE |
| `error` | wire output | reg output | COMPATIBLE |
| `error_code[3:0]` | — | reg output | **NEW** (can leave open) |
| `ev_tlast_missing_o` etc. | — | 5 sticky event regs | **NEW** (can leave open) |
| `int_cfo[15:0]` | wire signed | wire signed | YES |
| `peak_index[8:0]` | wire | wire | YES |
| `peak_score[63:0]` | wire | wire | YES |

### 3.2 Parameter Table

| Parameter | meyr_integer_cfo_fft_frontend_top | meyr_fft256_actual_integration_top |
|-----------|-----------------------------------|------------------------------------|
| FFT_LEN / NSC | FFT_LEN=256 | NSC=256 (rename) |
| IQ_WIDTH | 16 | 16 |
| PROD_WIDTH | 32 | 32 |
| ACC_WIDTH | 56 | 56 |
| SCORE_WIDTH | 64 | 64 |
| INDEX_WIDTH | 9 | 9 |
| USE_BEHAVIORAL_STUB | — | 0=production, 1=passthrough, 2=sequential |
| STUB_TLAST_AT | — | 255 (default) |
| STUB_STOP_AT | — | 255 (default) |
| FLUSH_COUNT | — | 1 (default; 0=no flush) |
| WATCHDOG_CYCLES | — | 2047 (default) |

### 3.3 Critical Interface Differences

**1. Data packing format** (most important difference):

```verilog
// meyr_integer_cfo_fft_frontend_top — current
input wire signed [IQ_WIDTH-1:0] s_i,   // separate I signal
input wire signed [IQ_WIDTH-1:0] s_q,   // separate Q signal

// meyr_fft256_actual_integration_top — candidate
input wire [2*IQ_WIDTH-1:0] s_axis_tdata,  // packed: {Q[31:16], I[15:0]}
```

Any adapter must repack: `s_axis_tdata = {s_q[15:0], s_i[15:0]}`

**2. TLAST generation** — actual integration top requires `s_axis_tlast` high at the 256th sample of each symbol. The extractor output does not currently drive tlast at sample 255; it fires `ext_m_tlast` at the last sample of the entire extracted sequence (not per-symbol). This must be generated or the harness must synthesize it from an internal counter.

**3. Symbol routing** — frontend top uses `s_symbol_sel` to route PSS/SSS; actual integration top expects PSS samples first (256), then SSS samples (256) as a sequential AXI-Stream. The `s_symbol_sel` input to actual integration top is purely informational (not used in FSM). The extractor produces PSS first then SSS, which is compatible.

**4. s_index** — frontend top passes `s_index` to fft256_dual_symbol_frontend; actual integration top uses an internal counter (`in_cnt`) and ignores external indexing. Index is dropped.

---

## 4. Can meyr_fft256_actual_integration_top Replace meyr_integer_cfo_fft_frontend_top Directly?

**Answer: Not directly — an interface adapter is required.**

The differences are non-trivial:
- `s_i`/`s_q` → `s_axis_tdata` repacking
- `s_axis_tlast` generation (per-symbol, at sample 255)
- 5 new event outputs (can be tied off)
- `error_code` (can be tied off)
- Parameter name change (`FFT_LEN` → `NSC`, `USE_BEHAVIORAL_STUB` new)

A thin adapter wrapper (`meyr_fft256_adapter_top.v`) would bridge the interfaces and could be substituted in phase3_sync_top in place of `meyr_integer_cfo_fft_frontend_top`.

---

## 5. Latency Implications

### 5.1 Bypass Path Latency

| Stage | Cycles |
|-------|--------|
| fft256_dual_symbol_frontend S_FILL | 512 (256 PSS + 256 SSS, back-to-back) |
| S_COMPUTE | 1 (parallel buffer copy in one clock cycle via NBA) |
| S_STREAM_PSS | 256 (1 per bin) |
| S_STREAM_SSS | 256 (1 per bin) |
| meyr_integer_cfo_freq_estimator_top S_RECV | ~258 (256 inputs + 2 pipeline) |
| meyr_integer_cfo_core 511-lag correlation | ~1533 (511 lags × ~3 cycles/lag) |
| Peak detector | ~515 (511 scores + setup) |
| **Total (approximate)** | **~3330 cycles** |

### 5.2 Real FFT Path Latency (FLUSH_COUNT=1, USE_BEHAVIORAL_STUB=0)

| Stage | Cycles |
|-------|--------|
| S_PSS_BUF | 256 (buffering PSS, tready=1) |
| S_PSS_STREAM | 256 (continuous tvalid to FFT, assumes fft_s_ready always high) |
| S_PSS_FLUSH | 256 + FFT_pipeline_latency (~10–50 cycles) |
| S_PSS_CAP | 256 + FFT_pipeline_latency |
| S_SSS_BUF | 256 |
| S_SSS_STREAM | 256 |
| S_SSS_FLUSH | 0 (flush_rem may be 0 after PSS consumed it) |
| S_SSS_CAP | 256 + FFT_pipeline_latency |
| S_EST | 256 (replay buffered bins to estimator) |
| S_WAIT_EST | estimator: ~258 (recv) + ~1533 (core) + ~515 (pd) |
| **Total (approximate)** | **~3900–4500 cycles** |

Real FFT path is ~15–35% slower than bypass due to buffering, flush, and FFT pipeline overhead. This is expected and acceptable.

### 5.3 Latency with USE_BEHAVIORAL_STUB=1 (Passthrough)

Passthrough stub: `s_axis_tready = m_axis_tready; m_axis_tvalid = s_axis_tvalid`. The stream is immediately reflected back. Latency for FSM transitions in S_PSS_CAP/S_SSS_CAP ≈ 256 cycles each (same speed as streaming). Total ≈ ~3500 cycles. Not useful for accuracy — only for compile/FSM verification.

---

## 6. tvalid/tready Implications

### 6.1 Upstream Backpressure

`meyr_fft256_actual_integration_top` asserts `s_axis_tready = 1` only during `S_PSS_BUF` and `S_SSS_BUF` states. All other states: `s_axis_tready = 0`. This applies backpressure to the extractor.

`meyr_integer_cfo_fft_frontend_top` delegates backpressure to `fft256_dual_symbol_frontend.s_ready`, which is high during S_FILL. Functionally equivalent.

**Critical:** The extractor must tolerate backpressure (it has its own AXI-Stream handshake). Confirmed: `pss_sss_symbol_extractor` respects `s_axis_tready` upstream — it will stall when backpressure is applied.

### 6.2 FFT Output (tready)

In `fft256_xilinx_wrapper` production mode (C_THROTTLE_SCHEME=0), `m_axis_tready` is not connected to the IP — data flows at full rate regardless of downstream ready. `meyr_fft256_actual_integration_top` drives `m_axis_tready = 1'b1` (always ready), which is correct for this IP configuration.

---

## 7. TLAST / Index Implications

### 7.1 TLAST in meyr_fft256_actual_integration_top

Input (`s_axis_tlast`): expected high at the last sample (index 255) of each PSS/SSS block. This is used in a consistency check (`ev_tlast_missing`, `ev_tlast_unexpected` events) but the FSM transitions on `in_cnt == 8'd255`, not on `s_axis_tlast`. So incorrect TLAST causes sticky error events but does not deadlock the FSM.

Output FFT (`fft_m_tlast`): asserted by the Xilinx IP at bin 255 of each 256-point frame. The FSM in S_PSS_CAP/S_SSS_CAP checks `fft_m_tlast` against `cap_bin_cnt == 255` for TLAST mismatch detection.

**Implication for adapter design:** A per-symbol `s_axis_tlast` must be generated. Simple counter: assert tlast when sample index = NSC-1 (255). This is not available from the current extractor output (which only fires tlast at the end of the SSS block), so the adapter must synthesize it.

### 7.2 Bin Index (xk_index)

The Xilinx FFT IP outputs bins in natural order (k=0 = DC, k=1..127 = positive freq, k=128..255 = negative freq) and puts the bin index in `m_axis_tuser[7:0]`. The actual integration top uses `fft_m_tuser` as the RAM write address (`pss_buf[fft_m_tuser]`, `sss_buf[fft_m_tuser]`). This correctly populates the FFT output buffers at the right bin indices.

In bypass mode (`USE_BEHAVIORAL_STUB=1`), `m_axis_tuser = 8'h00` always (stub ties user to zero). This means all bins land at index 0 — the buffer is not correctly populated, and correlation results are meaningless. This is expected; stub mode is for compile and FSM verification only.

---

## 8. Reset / Start / Done Behavior

| Aspect | meyr_integer_cfo_fft_frontend_top | meyr_fft256_actual_integration_top |
|--------|-----------------------------------|------------------------------------|
| Reset | active-low aresetn, sync | active-low aresetn, sync |
| Start | 1-cycle pulse when !busy_r | 1-cycle pulse when !busy |
| Start while busy | sets error_r sticky | sets error sticky, error_code=4'd1 |
| Done | 1-cycle pulse (done_r) in S_DONE | 1-cycle pulse (done) in S_DONE |
| Busy | deasserts simultaneously with done | deasserts simultaneously with done |
| Error | sticky (cleared only by aresetn) | sticky (cleared only by aresetn) |

Both modules are functionally equivalent in reset/start/done behavior. The actual integration top adds `error_code` distinguishing error sources (1=start-while-busy, 2=FFT error, 3=estimator error, 4=watchdog, 5=TLAST mismatch).

**Re-use requirement:** Both modules are single-shot per `start` pulse. A new `aresetn` toggle is needed between runs (same as current behavior in phase3_sync_top).

---

## 9. Required Xilinx FFT IP Dependencies

| Dependency | File | Status on Build Host |
|------------|------|----------------------|
| Xilinx xfft_v9_1_8 IP | `fft256_xilinx.v` (via IP catalog) | **NOT PRESENT** |
| IP config | `ip/fft256_xilinx/fft256_xilinx/fft256_xilinx.xci` | **NOT PRESENT** (no `ip/` dir) |
| Port declarations | `ip/fft256_xilinx/fft256_xilinx/fft256_xilinx.veo` | **NOT PRESENT** |
| Vivado IP stub | generated by `generate_target` TCL | **NOT PRESENT** |

When `USE_BEHAVIORAL_STUB != 0`, the `gen_production` generate block is suppressed and `fft256_xilinx` is never referenced. For iverilog simulation, `USE_BEHAVIORAL_STUB=1` is the only feasible option.

---

## 10. Simulation Feasibility Under Vivado xsim

| Mode | Feasibility | Notes |
|------|-------------|-------|
| iverilog + USE_BEHAVIORAL_STUB=1 | **Compile and FSM verification only** | xk_index always 0; all bins at index 0; no accurate CFO output |
| iverilog + USE_BEHAVIORAL_STUB=2 | **FSM hardening only** | Sequential zero output; not useful for CFO |
| xsim + USE_BEHAVIORAL_STUB=1 | **Same as iverilog case** | No accuracy benefit |
| xsim + USE_BEHAVIORAL_STUB=0 + Xilinx IP | **Full accuracy — k_int sweep works** | Requires Vivado + IP generation |

**Conclusion:** Vivado xsim with USE_BEHAVIORAL_STUB=0 and a generated Xilinx FFT IP is the only path to accurate k_int≠0 simulation. This is BLOCKED on build host (no Vivado, no IP directory).

**Alternative:** A software behavioral DFT model (new stub mode, e.g. USE_BEHAVIORAL_STUB=3) could be implemented in pure Verilog for iverilog. This would require a fixed-point DFT (e.g. radix-2 Cooley-Tukey) with natural-order output and xk_index tracking. This is feasible but not trivial (~200 lines of Verilog).

---

## 11. Synthesis Feasibility

| Tool | Status | Notes |
|------|--------|-------|
| Vivado 2023.x synthesis | **BLOCKED** — Vivado not installed | Once installed: requires `ip/fft256_xilinx/` generated |
| Yosys + open-source | **NOT FEASIBLE** | Xilinx DSP48/BRAM primitives not supported |
| Synplify | NOT APPLICABLE | Not a Xilinx flow |

Once Vivado is installed and the Xilinx FFT IP is generated (`create_ip` + `generate_target`), synthesis with USE_BEHAVIORAL_STUB=0 should be straightforward. The wrapper correctly maps all required IP ports.

---

## 12. ROM Regeneration Requirement

### 12.1 Current ROMs (bypass-compatible)

```
PSS_rom[j] = term1_ref[j] = PSS_td_ref[j] × conj(SSS_td_ref[j]),  normalized Q1.15
SSS_rom[j] = {I=+32767, Q=0}  → sign=+1 → term2[j] = PSS_rom[j]

Valid for: bypass FFT (time-domain path), k_int=0 only
```

### 12.2 Required ROMs (real FFT path)

```python
# Reference sequences (must match actual ZC PSS and Gold-code SSS)
# For the test stimulus (SEED=0xC0FFEE QPSK OFDM), the reference sequences are:
PSS_fft_ref = np.fft.fft(pss_td_ref, n=NSC)    # 256-point DFT of PSS OFDM symbol
SSS_fft_ref = np.fft.fft(sss_td_ref, n=NSC)    # 256-point DFT of SSS OFDM symbol

term1_fft_ref[j] = PSS_fft_ref[j] * np.conj(SSS_fft_ref[j])

PSS_rom[j]    = term1_fft_ref[j]  normalized to Q1.15  (same packing as P3-08)
SSS_rom_I[j]  = +32767             (sign=+1, same convention)
```

### 12.3 Expected Peak Behavior with Real FFT ROMs

With a k_int-shifted stimulus, the FFT output for PSS is:

```
FFT(PSS_shifted)[j] = FFT(PSS_ref)[j−k_int]   (circular shift in freq domain)
```

The cross-product `term1_fft[j] = FFT(PSS_shifted)[j] × conj(FFT(SSS_shifted)[j])`:

```
= FFT(PSS_ref)[j−k_int] × conj(FFT(SSS_ref)[j−k_int])
= term1_fft_ref[j−k_int]
```

The 511-lag correlation of `term1_fft` (shifted by k_int) against `term2_fft_ref = term1_fft_ref` peaks at `lag = k_int`:

```
peak_index     = 255 + k_int
int_cfo        = k_int
integer_cfo_word = −k_int × 2^24   (for NSC=256, INT_CFO_SHIFT=24)
```

### 12.4 ROM Generation Script

The new script (to be created in a future session) follows:

```python
# scripts/gen_meyr_fft_reference_roms.py  (future P3-11 work)
#
# Key difference from gen_meyr_reference_roms.py:
#   1. Extract pss_td_ref and sss_td_ref from frame_norot (same windows as P3-08)
#   2. Compute PSS_fft_ref = np.fft.fft(pss_td_ref)     ← DFT, not raw samples
#              SSS_fft_ref = np.fft.fft(sss_td_ref)
#   3. term1_fft[j] = PSS_fft_ref[j] * np.conj(SSS_fft_ref[j])
#   4. Normalize to Q1.15, pack to {Q[31:16], I[15:0]}, write to vectors/*.txt
#
# IMPORTANT: The Xilinx FFT IP uses natural-order output with no fftshift.
# The ROM must be in natural order to match bin indices.
#
# IMPORTANT: The Xilinx FFT IP output bit width may require scaling:
#   For 16-bit input, the FFT output is also 16-bit with internal scaling
#   controlled by SCALE_SCH=0xAA (scale at alternating stages).
#   The ROM must be normalized relative to the FFT IP's output range,
#   not the raw float DFT range. Scaling factor must be verified in simulation.
```

---

## 13. Integration Option Analysis

### Option A: Replace meyr_integer_cfo_fft_frontend_top in phase3_sync_top

**Approach:** Add a thin adapter wrapper `meyr_fft256_adapter_top.v` that:
1. Repacks separate s_i/s_q → packed s_axis_tdata
2. Generates per-symbol s_axis_tlast (counter to 255)
3. Instantiates meyr_fft256_actual_integration_top

Then modify `phase3_sync_top.v` to instantiate this adapter in place of `u_meyr_fft`.

**Pros:**
- Clean replacement; phase3_sync_top maintains a single Meyr instance
- All downstream (integer CFO word computation, dbg_integer_cfo_word) unchanged

**Cons:**
- Modifies phase3_sync_top.v (production RTL) — **violates DO NOT MODIFY constraint**
- Requires fft256_xilinx_wrapper in compile path for ALL simulations, even those using bypass
- USE_BEHAVIORAL_STUB=1 parameter must be threaded through to allow iverilog compile

**Status:** REJECTED for this session (violates DO NOT MODIFY)

### Option B: Modify meyr_integer_cfo_fft_frontend_top with bypass/real parameter

**Approach:** Add `USE_REAL_FFT` parameter to `meyr_integer_cfo_fft_frontend_top`. When set, instantiate `meyr_fft256_actual_integration_top` (with adapter); when cleared, keep current `fft256_dual_symbol_frontend`.

**Pros:**
- Single interface point; backward compatible with existing testbenches
- CI_GATE tests continue to pass with USE_REAL_FFT=0

**Cons:**
- Modifies meyr_integer_cfo_fft_frontend_top.v (unit_test RTL) — **violates DO NOT MODIFY constraint**
- Adds complexity to a unit_test module
- fft256_xilinx_wrapper still enters compile path in USE_REAL_FFT=1 mode

**Status:** REJECTED for this session (violates DO NOT MODIFY)

### Option C: Separate top-level test harness (RECOMMENDED)

**Approach:** Create a new standalone testbench and DUT wrapper:
- `tb/p3_11_real_fft_meyr_tb.sv` — drives PSS+SSS samples to meyr_fft256_actual_integration_top
- Reads per-case .mem files from `golden/p3_09_sweep/`
- Checks peak_index, int_cfo, integer_cfo_word
- Completely independent from phase3_sync_top

No existing RTL is modified. The harness is a new artifact.

**Pros:**
- Zero impact on existing CI_GATE PASS (P3-08, P3-05C, etc.)
- Can be iterated independently
- meyr_fft256_actual_integration_top is already complete (Step 42-B)
- For accurate results: set USE_BEHAVIORAL_STUB=0 and run under Vivado xsim with Xilinx FFT IP
- For compile verification: set USE_BEHAVIORAL_STUB=1 and run under iverilog

**Cons:**
- Does not exercise the full phase3_sync_top extraction path
- Requires a stimulus adapter (feed PSS/SSS samples directly, not via extractor)

**Status:** RECOMMENDED for P3-11 → P3-12

---

## 14. Vivado/xsim Dependency Status

| Component | Required For | Available | Blocker |
|-----------|-------------|-----------|---------|
| iverilog 11.0 | Compile + FSM tests (STUB=1/2) | YES | — |
| xsim | Simulation with Xilinx IP | NO | Vivado not installed |
| Vivado 2023.x | xsim + synthesis | NO | Not installed |
| fft256_xilinx IP | STUB=0 simulation | NO | No `ip/` directory |
| `fft256_xilinx.v` / `.veo` | STUB=0 compile | NO | IP not generated |
| Python 3 + numpy | ROM generation scripts | YES (assumed) | — |

**BLOCKED path:** USE_BEHAVIORAL_STUB=0 → requires fft256_xilinx IP → requires Vivado generate_target → requires Vivado installation.

**Available path:** USE_BEHAVIORAL_STUB=1 → iverilog compile + FSM FSM verification only (no accurate CFO).

---

## 15. Summary of Findings

| Item | Finding |
|------|---------|
| Bypass limitation | S_COMPUTE in fft256_dual_symbol_frontend copies buffers; integer CFO cancels in cross-product; k_int≠0 always gives wrong answer |
| meyr_fft256_actual_integration_top | Complete (Step 42-B); NOT in phase3_sync_top sim path; requires interface adapter |
| Interface gap | Packed AXI-Stream vs separate I/Q; per-symbol TLAST generation; 5 new event ports |
| Latency | Real FFT path ~15-35% slower than bypass (~3900-4500 vs ~3330 cycles) |
| TLAST | Must be generated per-symbol at sample 255; extractor does not currently provide this |
| ROM status | Current ROMs bypass-compatible (time-domain cross-product); must be regenerated from DFT(PSS)×conj(DFT(SSS)) for real FFT path |
| Xilinx IP | Not present; no `ip/` directory; USE_BEHAVIORAL_STUB=1 required for iverilog |
| xsim | Not installed; Vivado not installed |
| Recommended option | Option C: separate test harness |
| Next step | P3-12: create gen_meyr_fft_reference_roms.py + p3_11_real_fft_meyr_tb.sv + adapter + dryrun script |
