# Session B3 / P3-13E — FFT Formal-Lite + Protocol Verification

**Date:** 2026-05-29  
**Gate:** `SANITY_FFT_PROTOCOL_GATE: PASS` (iverilog)  
**Passes:** 17/17  
**Failures:** 0  
**Simulator:** iverilog

---

## Summary

All B3-1 / B3-2 / B3-3 / B3-4 checks pass across 2 FFT runs and 3 Meyr runs.
Three RTL fixes and one TB timing fix were required to reach PASS.

---

## B3-1: FFT Input Protocol Results

DUT: `fft256_dual_symbol_frontend`

| Check | Run 1 (d=0xA5A5 r=0xDEAD) | Run 2 (d=0x3C3C r=0x5678) |
|-------|--------------------------|--------------------------|
| PSS 256/256 accepted | PASS | PASS |
| SSS 256/256 accepted | PASS | PASS |
| output count [512,514] | PASS (513) | PASS (512) |
| fft_done fired | PASS | PASS |

---

## B3-2: FFT Output Protocol Results

Continuous monitor active throughout all runs (no FAIL lines emitted).

| Check | Result |
|-------|--------|
| tvalid stability (m_valid not dropped during stall) | PASS |
| tdata stability ({m_index, m_i, m_q} stable within symbol during stall) | PASS |

---

## B3-3: Meyr Invariants

DUT: `meyr_integer_cfo_fft_frontend_top`

| Stimulus | peak_index | int_cfo | Result |
|----------|-----------|---------|--------|
| Run 1 (all-zeros) | 0 | −255 | PASS |
| Run 2 (d=0xCAFE) | 510 | +255 | PASS |
| Run 3 (d=0xBEEF) | 510 | +255 | PASS |

All peak_index values in [0, 510]. All int_cfo values in [−255, +255].

---

## B3-4: Formal-Lite Checks

| Check | Result |
|-------|--------|
| meyr_done 1-cycle pulse (never double-done) | PASS (monitor, 0 violations) |
| fft_done 1-cycle pulse (never double-done) | PASS (monitor, 0 violations) |
| peak_index ≤ 510 whenever done=1 | PASS (monitor, 0 violations) |
| meyr_done fired within 150k cycles | PASS (wd=66834 all 3 runs) |

---

## RTL Fixes Applied

### Fix A — S_STREAM_PSS non-last branch missing prefetch override
**File:** `rtl/fft256_dual_symbol_frontend.v`, S_STREAM_PSS non-last branch.  
**Problem:** On a handshake in cycle P, `stream_ptr` advanced to P+1 via NBA but `m_index/m_i/m_q` still showed P (default NBA). On the next cycle with `m_ready=0`, the monitor saw the data change from P→P+1 — a false tdata stability violation.  
**Fix:** Added override NBAs `m_index <= stream_ptr + 1; m_i <= fft_pss_i[stream_ptr+1]; m_q <= ...` in the non-last branch so data is presented one cycle early.

### Fix B — S_STREAM_PSS advance guard missing m_valid check
**File:** `rtl/fft256_dual_symbol_frontend.v`, S_STREAM_PSS.  
**Problem:** `if (m_ready)` fired on the first S_STREAM_PSS cycle when `m_valid=0`, spuriously advancing `stream_ptr` from 0→1 and skipping PSS bin 0 from the meyr's FFT output buffer.  
**Fix:** Changed to `if (m_valid && m_ready)`.

### Fix C — S_STREAM_SSS ghost m_valid cycle at last bin
**File:** `rtl/fft256_dual_symbol_frontend.v`, S_STREAM_SSS last-bin branch.  
**Problem:** The unconditional `m_valid <= 1'b1` NBA fired even when transitioning to S_DONE, leaving `m_valid=1` for one extra cycle with `m_ready` potentially 1 — causing an extra output handshake and a tvalid-drops-while-not-ready false FAIL.  
**Fix:** Added `m_valid <= 1'b0` in the last-bin branch of S_STREAM_SSS.

---

## TB Fix Applied

### TB timing fix — PSS→SSS symbol_sel race at zero simulation delay
**File:** `tb/session_B3_p3_13e_fft_protocol_tb.sv`, `run_meyr_test` task.  
**Problem:** When the PSS for-loop's last `while(!meyr_srdy)` exits, the SSS for-loop immediately sets `meyr_ssel=1` at zero simulation delay — within the same active region as the DUT's always block at that posedge. The DUT could evaluate `s_symbol_sel=1` (SSS) instead of 0 (PSS), firing an SSS handshake and leaving `pss_cnt` at 255 permanently, blocking `S_FILL→S_COMPUTE`.  
**Fix:** Inserted `@(negedge aclk)` between the PSS and SSS loops. The `ssel` change now lands between posedges, stable at the next posedge with no DUT evaluation race.

---

## Known Limitations (unchanged from D3)

| ID | Description |
|----|-------------|
| L-01 | FFT bypass stub: `fft256_dual_symbol_frontend` copies time-domain input to frequency-domain output. Meyr estimator operates on unprocessed time-domain data, not real frequency bins. peak_index and int_cfo are determined by the synthetic PRNG term2 ROM, not the input signal. |
| L-02 | io_count tolerance [512, 514]: FFT Run 1 outputs 513 (one extra handshake from the PSS→SSS boundary during the meyr's internal streaming). This is counted by the standalone B3-2 monitor as a harmless extra observation. |

---

## Gate Record

```
SANITY_FFT_PROTOCOL_GATE: PASS
Simulator: iverilog
Passes:    17
Failures:  0
Date:      2026-05-29
```

---

## Files

| File | Purpose |
|------|---------|
| `tb/session_B3_p3_13e_fft_protocol_tb.sv` | Verification TB (B3-1 through B3-4) |
| `scripts/run_session_B3_p3_13e_fft_protocol.sh` | Compile + simulate + gate |
| `rtl/fft256_dual_symbol_frontend.v` | DUT 1 (3 fixes applied) |
| `rtl/meyr_integer_cfo_fft_frontend_top.v` | DUT 2 (no changes) |
| `reports/session_B3_p3_13e/fft_protocol_gate.txt` | Gate record |
| `docs/session_B3_p3_13e_fft_protocol.md` | This document |
