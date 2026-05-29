# Session B3 / P3-13E — FFT Formal-Lite + Protocol Verification

**Date:** 2026-05-29  
**Gate:** `FFT_PROTOCOL_GATE: PASS / FAIL`  
**Simulator:** iverilog (SANITY prefix) | xsim (official)

---

## Session Overview

Verify the FFT dual-symbol frontend and Meyr integer-CFO pipeline for:
1. AXI-Stream input/output protocol correctness (no sample loss, no stall violation)
2. Meyr invariants on peak_index and int_cfo
3. Formal-lite liveness and safety properties on done

---

## B3-1: FFT Input Protocol Assertions

DUT: `fft256_dual_symbol_frontend`

Verify for each run:
- **No sample loss**: all 256 PSS indices and 256 SSS indices are accepted (s_valid && s_ready)
- **No duplicate**: no index accepted twice within same run
- **No deadlock**: s_ready eventually asserts within watchdog; done fires
- **input_count == output_count**: 512 input handshakes → 512 output handshakes
- **eventually fft_done**: done fires within watchdog

Multiple runs with different LFSR data seeds.

---

## B3-2: FFT Output Protocol Assertions

DUT: `fft256_dual_symbol_frontend`

With randomly stalling m_ready (LFSR-driven):
- **tvalid stability**: once m_valid=1, must not deassert until m_valid&&m_ready handshake
- **tdata stability**: when m_valid=1 and m_ready=0 (stall), {m_index, m_i, m_q} must not change

Note: m_symbol_sel transitions from 0→1 at the PSS→SSS boundary exactly once; this
transition always follows a handshake (m_ready=1 in prev cycle), so tdata stability is
checked only within each symbol stream (m_symbol_sel unchanged between cycles).

Continuous monitor runs throughout all B3-1 runs.

---

## B3-3: Meyr Invariants

DUT: `meyr_integer_cfo_fft_frontend_top`

After each meyr_done pulse:
- `0 ≤ peak_index ≤ 510` (LAG_COUNT=511, CENTER=255)
- `-255 ≤ int_cfo ≤ +255` (int_cfo = peak_index − 255)

Three stimulus variants: all-zeros, LFSR-A, LFSR-B.

---

## B3-4: Formal-Lite Checks

DUT: `meyr_integer_cfo_fft_frontend_top` (and `fft256_dual_symbol_frontend`)

- **Eventually meyr_done**: done fires within 150000-cycle watchdog after start
- **Never double done**: meyr_done (and fft_done) never high for two consecutive cycles
- **Never illegal peak_index**: peak_index ≤ 510 whenever done=1

Implemented as continuous `always @(posedge aclk)` monitors, checked throughout all runs.

---

## Tolerances / Conventions

| Property | Value |
|----------|-------|
| FFT_LEN | 256 |
| LAG_COUNT | 511 |
| CENTER | 255 |
| peak_index range | [0, 510] |
| int_cfo range | [−255, +255] |
| m_valid stall rule | cannot deassert during stall |
| tdata stall rule | {m_index, m_i, m_q} must be stable during stall within each symbol |
| LFSR polynomial | x^16 + x^14 + x^13 + x^11 + 1 (poly 0xB400) |

---

## Gate Definition

```
FFT_PROTOCOL_GATE: PASS   ← all B3-1/B3-2/B3-3/B3-4 checks pass
FFT_PROTOCOL_GATE: FAIL   ← any check fails
```

iverilog: `SANITY_FFT_PROTOCOL_GATE: PASS / FAIL`

---

## Files

| File | Purpose |
|------|---------|
| `tb/session_B3_p3_13e_fft_protocol_tb.sv` | Verification TB |
| `scripts/run_session_B3_p3_13e_fft_protocol.sh` | Compile + simulate + gate |
| `docs/session_B3_p3_13e_fft_protocol.md` | Final result document |
| `md_files/session_B3_p3_13e_fft_protocol_prompt.md` | This file (prompt archive) |
