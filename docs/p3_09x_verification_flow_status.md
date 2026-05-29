# P3-09X — Phase 3 Verification Flow Status

**Date:** 2026-05-28  
**Status:** xsim runner created; iverilog demoted; xsim unavailable on current build host

---

## 1. Official CI Gate Policy

| Simulator | Role | Sign-off authority |
|-----------|------|--------------------|
| Vivado xsim | **Official CI gate** | YES — required for all Phase 3 PASS results |
| iverilog | Optional quick sanity check | NO — prototype-level only |
| Verilator | Not configured | NO |
| Synthesis check | Future gate (not this step) | N/A |
| FPGA/Vitis/board | Not part of Phase 3 verification | N/A |

**A result is ONLY official if produced by `scripts/run_phase3_sync_xsim.sh`.**

---

## 2. Official Vivado xsim Runner

**File:** `scripts/run_phase3_sync_xsim.sh`

**Flow:**
1. Check for xsim in PATH; auto-discover Vivado settings64.sh if needed
2. Build golden_dump from `scripts/golden_dump.c`
3. Auto-generate IQ stimulus if absent (`scripts/gen_phase3_iq_stimulus.py`)
4. Run golden dump → `golden/phase3_golden_values.txt`
5. Convert IQ float32 → Q15 hex (`golden/phase3_iq_stimulus_q15.hex`)
6. Compile RTL (30 files) with `xvlog -d SIMULATION`
7. Compile testbench with `xvlog --sv`
8. Elaborate with `xelab -debug typical`
9. Simulate with `xsim --runall`
10. Compare results with `compare_golden_rtl.py` (10 checks)
11. Print `CI_GATE: PASS  (Vivado xsim)` or `CI_GATE: FAIL`

**If xsim is unavailable:**
```
CI_GATE: BLOCKED_XSIM_UNAVAILABLE
```
The script prints exact instructions to source Vivado settings or install Vivado.
It does NOT fake a PASS.

---

## 3. Quick Sanity Check (iverilog — NOT Official)

```bash
bash scripts/run_phase3_sync_sim.sh --sim iverilog
```

- Uses iverilog 11.0 (`/usr/bin/iverilog -g2012`)
- Available on current build host
- Results are PROTOTYPE-LEVEL only — do not record as CI sign-off
- The runner prints `CI_GATE: PASS` or `CI_GATE: FAIL` but these are not official

Similarly for P3-08 backend:
```bash
bash scripts/run_p3_08_meyr_backend.sh --sim iverilog
```

---

## 4. Current Host Status

| Component | Status |
|-----------|--------|
| iverilog 11.0 | Available at `/usr/bin/iverilog` |
| Vivado / xsim | NOT INSTALLED on current build host |
| `VIVADO_SETTINGS_FILE` env var | Not set |

**To install Vivado on this host:**
1. Download Vivado installer from Xilinx (AMD): https://www.xilinx.com/support/download.html
2. Install (recommend 2022.2 or later for Verilog-2005 + SystemVerilog support)
3. After install:
   ```bash
   source /opt/Xilinx/Vivado/YYYY.N/settings64.sh
   bash scripts/run_phase3_sync_xsim.sh
   ```
   OR permanently add to your shell profile.

---

## 5. Simulation Gate Progression

The table below tracks which checks have been executed and under which simulator.
All future sign-off requires xsim revalidation.

| Check | Description | iverilog status | xsim status |
|-------|-------------|-----------------|-------------|
| 0 | DETECTION_STATUS | PASS (P3-05C) | PENDING |
| 1 | frameStart ±1 | PASS (P3-05C) | PENDING |
| 2 | peakIndex ±1 | PASS (P3-05C) | PENDING |
| 3 | slotStartIndex ±1 | PASS (P3-05C) | PENDING |
| 4 | frac CFO (1% rel or ±2 LSB) | PASS (P3-05C) | PENDING |
| 5 | PSS_START exact | PASS (P3-05C) | PENDING |
| 6 | SSS_START exact | PASS (P3-05C) | PENDING |
| 7 | PSS_SAMPLE_COUNT=256 | PASS (P3-07) | PENDING |
| 8 | SSS_SAMPLE_COUNT=256 | PASS (P3-07) | PENDING |
| 9 | Meyr peak_index=255 (k_int=0, bypass path) | PASS (P3-08) | PENDING |
| 10 | integer_cfo_word=0 (k_int=0, bypass path) | PASS (P3-08) | PENDING |
| P3-09 | Integer CFO sweep k_int≠0 | BLOCKED (bypass FFT) | BLOCKED |
| P3-10A | Replay buffer unit tests T01–T08 | PASS (standalone) | PENDING |

---

## 6. Synthesis Check (Future Gate)

A synthesis check is a FUTURE gate, not part of the current Phase 3 verification step.

When the RTL is feature-complete (real FFT integrated, integer CFO correction connected):
```bash
vivado -mode batch -source scripts/run_synthesis_check.tcl
```
This gate is NOT part of Phase 3 until explicitly added.

---

## 7. FPGA / Vitis / Board Testing

FPGA bring-up and board testing are NOT part of Phase 3 verification.
They will be addressed in a future phase after:
- All xsim CI checks pass
- Synthesis is clean
- Timing closure achieved

---

## 8. Runner Summary

| Script | Purpose | Default simulator | Official? |
|--------|---------|-------------------|-----------|
| `scripts/run_phase3_sync_xsim.sh` | OFFICIAL CI gate | xsim only | **YES** |
| `scripts/run_phase3_sync_sim.sh` | Multi-sim runner | xsim | Only when run with xsim |
| `scripts/run_p3_08_meyr_backend.sh` | P3-08 Meyr backend | xsim (repaired) | Only when run with xsim |
| `scripts/run_p3_09_integer_cfo_sweep.sh` | P3-09 CFO sweep | xsim (repaired) | Only when run with xsim; BLOCKED |
| `scripts/run_p3_10a_iq_replay_buffer_sim.sh` | P3-10A replay buffer | iverilog | NO — sanity only |
