# Task Prompt Archive: Algorithm Specification from C Reference

**Saved:** 2026-06-02  
**Output document:** `docs/algorithm_reference_spec.html`

---

## Task

Create an algorithm specification document from the C reference code, for the purpose of RTL functionality verification.

**Rules:**
- This is NOT a code modification task.
- Do NOT modify RTL files.
- Do NOT modify testbench files unless explicitly required.
- Primary output is documentation.

**Mandatory archival rule:**
- Save this prompt as: `/home/zealatan/RTL_SYNC_PHASE4/md_files/step_algorithm_spec_from_c_reference.md`
- Create main document: `/home/zealatan/RTL_SYNC_PHASE4/docs/algorithm_reference_spec.html`
- Update `reports/current_status.html` and `reports/issue_tracking.html` only if documentation-related issues, mismatch risks, or missing reference mapping are discovered.

## Context

- Project: RTL_SYNC_PHASE4
- RTL implements an FPGA streaming OFDM/NR-style synchronization chain.
- C reference code is the golden functional reference.
- Verification dashboard shows P3-15D random equivalence and P3-16A full integration have open issues.

## Primary directories inspected

- ref/ — C reference source
- rtl/ — Verilog RTL modules
- tb/ — testbenches
- golden/ — golden reference vectors
- vectors/ — ROM hex files
- scripts/ — build/sim scripts
- reports/ — status dashboards
- logs/ — simulation logs

## Required sections

1. Project Purpose
2. End-to-End Synchronization Flow
3. C Reference Function Inventory (inspect ref/, document each function)
4. Algorithm Stage Breakdown (table: Stage | C Function | Algorithm | RTL Module | Gate | Status)
5. Mathematical Formulation (frame detection, CP autocorrelation, timing metric, frac CFO, CFO correction, Meyr integer CFO)
6. Reference vs RTL Implementation Difference (float vs fixed-point, random access vs replay buffer, FFTW vs FFT IP, atan2 vs CORDIC, sequential vs pipeline)
7. Fixed-Point and Streaming Constraints (IQ width, phase word, CFO word, valid/ready, stall/backpressure, latency, frame decisions)
8. Verification Mapping (all gates: P3-12B/C, P3-13E, P3-14B/C, P3-15A/C/D, P3-16A, P3-20A, P3-22A, P3-23A)
9. Known Open Functional Risks (ISSUE-001: complex_mult_iq backpressure; ISSUE-002: P3-15D 15/100 failures)
10. RTL Functionality Verification Checklist
11. Recommended Next Verification Steps

## Document Style

- Dark technical dashboard style matching reports/current_status.html
- Tables, code snippets, equations, stage diagrams in plain HTML/CSS
- PASS/WARN/FAIL badges
- No external CDN, no JavaScript
