# CLAUDE.md — quick context for the next session

Read this first. Single source of truth for state is
`status/dashboard.json` (rendered to `p5_status_kpi_dashboard.html`
and `p5_issue_tracker.html` by `scripts/gen_dashboards.py`).

## What this repo is

OFDM receiver synchronizer with a new FFT-correlation Meyr
integer-CFO core (`meyr_cfo_top`), targeting ZCU102
(`xczu9eg-ffvb1156-2-e`) at 250 MHz line rate, 250 Msps continuous
input with zero sample drops. Top module = `phase3_sync_axis_dma_wrapper`
(AXI-Lite slave + AXI-Stream slave/master).

## Where things are

- `rtl/` — synthesizable Verilog (top: `phase3_sync_axis_dma_wrapper.v`)
  - `meyr_cfo_top.v` + `meyr_{Rm,ifft_peak,feeder,slot_frontend,sync_capture,FFT_ak,zeropad,ak_buf}_dut.v`
    + `complex_mult*.v` — new FFT-correlation core (OOC closes at 302 MHz)
  - `frame_detector.v`, `frac_cfo_*` — reused timing / fractional-CFO chain
  - `phase3_sync_top.v` — orchestrator FSM (replay buffer retired in P5-03)
  - `phase3_sync_axis_dma_wrapper.v` — board-integration top
  - `xfft_{N,2N,IFFT}/*.xci` — Xilinx xfft 9.1 IPs, persisted to `xczu9eg`
- `tb/` — TBs (P5-CONT-{SMOKE, NIGHTLY, ROBUST} + P5-EQUIV + P5-D + invariants/cov)
- `docs/` — spec + iteration logs (e.g. `p5_04_status.md`, `p5_06_gate_level_status.md`,
  `p5_08_p2_status.md`)
- `scripts/` — runners, golden generators, dashboard gen, OOC synth
- `ref/` — C reference (`receiver.c`) + 3-way dump (`dump_p5_d1.c`)
- `golden/` — bit-exact reference vectors (per-gate subdirs)
- `vectors/` — B[k] ROM, stimuli, random sweep manifest
- `status/dashboard.json` — single source of truth for KPIs, issues,
  phases, levels
- `hil/agent_fsm/scripts/run_rtl_regression.py` — required-gate
  registry; current required set is 11

## Current state

- **Regression: 11/11 PASS, exit 0** (gates: LINT_CORDIC, P3-15A,
  P3-15C, P3-23A, P5-EQUIV, P5-CONT-SMOKE/NIGHTLY/ROBUST,
  P5-CORRECTED, P5-AXI-COV, P5-D1-3WAY)
- **PHASE 1 (Meyr integration): done**
- **PHASE 3 (250 MHz timing closure): prog, best WNS −0.568 ns ≈ 219 MHz** —
  7 iter attempted, next blocker is `meyr_sync_capture` LUTRAM
  (combinational read; needs registered-read + BRAM + TB latency update).
  See `docs/p5_04_status.md` + `docs/p5_05_status.md`.
- **PHASE 2 (verification expansion): partial** — coverage
  infrastructure ready, full % collection deferred (xelab `-cc`
  flag needed). See `docs/p5_08_p2_status.md`.

## How to do common things

```bash
# Sanity check after any RTL change
python3 hil/agent_fsm/scripts/run_rtl_regression.py
# Expected: Overall: PASS  required=11P/0F/0skip

# Regenerate dashboards
python3 scripts/gen_dashboards.py
# → p5_status_kpi_dashboard.html + p5_issue_tracker.html at repo root

# Force a specific gate cold-run (cache invalidation)
touch <any-rtl-or-TB-file-it-depends-on>
bash scripts/run_p5_03_smoke_gate.sh      # spec a/b/c
bash scripts/run_p5_03_nightly_gate.sh    # spec d
bash scripts/run_p5_03_robust_gate.sh     # spec e+f
bash scripts/run_p5_equiv_gate.sh         # meyr_cfo_top 17/17
bash scripts/run_p5_corrected_gate.sh     # bit-exact M_AXIS
bash scripts/run_p5_axi_cov.sh            # AXI-Lite 21-reg sweep
bash scripts/run_p5_d1_3way_gate.sh       # C ↔ Python ↔ RTL

# Full-design timing measurement (Windows Vivado via WSL mirror)
rsync -a --delete rtl/ /mnt/c/work/RTL_SYNC_PHASE5/rtl/
cmd.exe /c "C: && cd C:\work\RTL_SYNC_PHASE5 && \
            C:\Xilinx\Vivado\2022.2\bin\vivado.bat -mode batch \
            -source scripts\p5_04_fulldesign_timing.tcl"
# Then for internal-only WNS:
cmd.exe /c "... -source scripts\p5_04_internal_timing.tcl"
```

## Hard rules (from project history)

- **Real Xilinx IP is the acceptance gate; stubs are sanity only.**
  Never mark a gate PASSED on a stub run.
  See `~/.claude/projects/-home-zealatan-RTL-SYNC-PHASE5/memory/feedback_real_ip_is_the_gate.md`.
- **Target part lock: `xczu9eg-ffvb1156-2-e`.** Functional xsim
  silently falls back to an installed zynquplus variant on systems
  without ZU9 part files (recorded in the gate output); synthesis
  / timing closure MUST run on the locked part.
- **Don't touch `meyr_cfo_top`.** It's 302 MHz OOC; the gap is in
  the reused chain. Iter 5 + Iter 7 (P5-04) tried adjacent cuts and
  reverted.
- **Function FIRST.** Regression must stay green after every change;
  revert anything that breaks it.

## Known blockers

- `meyr_sync_capture` LUTRAM combinational read prevents BRAM
  conversion → distributed-RAM routing dominates the remaining
  timing gap.
- Full code coverage % requires `xelab -cc <type>` flag (infra
  written, value not yet measured).

## Next probable steps (in priority order)

1. P3 G2 / G3 — architecture diagram, module header cleanup
2. PHASE 5 — bitstream + ZCU102 board bringup (requires
   timing-closed RTL; either close 250 MHz first or build at 200
   MHz target as a derisking step)
3. PHASE 6 — HW throughput measurement (boards + DMA driver)
